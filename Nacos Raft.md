# Nacos Raft算法

## 角色
Raft分为三种角色：

1. LEADER： 向其他所有节点发送心跳，并负责集群内的数据“写”
2. FOLLOWER：如果在心跳周期内没有收到Leader的心跳，则标识Leader挂了，可以转为Candidate节点发起投票
3. CANDIDATE：可以发起投票，如果投票数大于集群半数，则成功晋升为Leader并开始向Follower发送心跳

## 轮次



## 心跳

  Laser节点定时向所有从节点发送心跳，等于告诉所有从节点，我Leader没有挂...
  RaftCore init方法中会开启HeartBeat任务，定时周期性发送心跳

```java
RaftCore HeartBeat.calss

        public void run() {
            try {
                if (!peers.isReady()) {
                    return;
                }
                RaftPeer local = peers.local();
                //HeartBeat task周期性执行，每次执行将心跳间隔减去周期时间
                //如果大于0则表示还没到心跳时间
                //如果小于0则标识可以发起心跳
                local.heartbeatDueMs -= GlobalExecutor.TICK_PERIOD_MS;
                if (local.heartbeatDueMs > 0) {
                    return;
                }
                //发起心跳前重置心跳周期时间
                local.resetHeartbeatDue();
                //发起心跳
                sendBeat();
            } catch (Exception e) {
                Loggers.RAFT.warn("[RAFT] error while sending beat {}", e);
            }
        }
```
```java
private void sendBeat() throws IOException, InterruptedException {
        RaftPeer local = peers.local();
    	//如果集群是单节点启动或是当前节点并非Leader节点则不发起心跳
        if (ApplicationUtils.getStandaloneMode() || local.state != RaftPeer.State.LEADER) {
            return;
        }
        if (Loggers.RAFT.isDebugEnabled()) {
            Loggers.RAFT.debug("[RAFT] send beat with {} keys.", datums.size());
        }
        //重置Leader过期时间（只要Leader一直发心跳，则Leader不会过期，除非它挂了）
        local.resetLeaderDue();
        
        // build data
    	//封装心跳数据
        ObjectNode packet = JacksonUtils.createEmptyJsonNode();
        packet.replace("peer", JacksonUtils.transferToJsonNode(local));
        
        ArrayNode array = JacksonUtils.createEmptyArrayNode();
        //如果不仅仅发起心跳请求，则携带Instance数据
        if (switchDomain.isSendBeatOnly()) {
            Loggers.RAFT.info("[SEND-BEAT-ONLY] {}", String.valueOf(switchDomain.isSendBeatOnly()));
        }
        
        if (!switchDomain.isSendBeatOnly()) {
            for (Datum datum : datums.values()) {
                
                ObjectNode element = JacksonUtils.createEmptyJsonNode();
                
                if (KeyBuilder.matchServiceMetaKey(datum.key)) {
                    element.put("key", KeyBuilder.briefServiceMetaKey(datum.key));
                } else if (KeyBuilder.matchInstanceListKey(datum.key)) {
                    element.put("key", KeyBuilder.briefInstanceListkey(datum.key));
                }
                element.put("timestamp", datum.timestamp.get());
                
                array.add(element);
            }
        }
        
        packet.replace("datums", array);
        // broadcast
        Map<String, String> params = new HashMap<String, String>(1);
        params.put("beat", JacksonUtils.toJson(packet));
        
        String content = JacksonUtils.toJson(params);
        
    	//对数据进行GZIP压缩
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        GZIPOutputStream gzip = new GZIPOutputStream(out);
        gzip.write(content.getBytes(StandardCharsets.UTF_8));
        gzip.close();
        
        byte[] compressedBytes = out.toByteArray();
        String compressedContent = new String(compressedBytes, StandardCharsets.UTF_8);
        
        if (Loggers.RAFT.isDebugEnabled()) {
            Loggers.RAFT.debug("raw beat data size: {}, size of compressed data: {}", content.length(),
                    compressedContent.length());
        }
        //遍历除自己以外的集群服务节点
        for (final String server : peers.allServersWithoutMySelf()) {
            try {
                final String url = buildUrl(server, API_BEAT);
                if (Loggers.RAFT.isDebugEnabled()) {
                    Loggers.RAFT.debug("send beat to server " + server);
                }
                //向集群节点发送心跳请求（HTTP协议）
                HttpClient.asyncHttpPostLarge(url, null, compressedBytes, new AsyncCompletionHandler<Integer>() {
                    @Override
                    public Integer onCompleted(Response response) throws Exception {
                        if (response.getStatusCode() != HttpURLConnection.HTTP_OK) {
                            Loggers.RAFT.error("NACOS-RAFT beat failed: {}, peer: {}", response.getResponseBody(),
                                    server);
                            MetricsMonitor.getLeaderSendBeatFailedException().increment();
                            return 1;
                        }
                        
                        peers.update(JacksonUtils.toObj(response.getResponseBody(), RaftPeer.class));
                        if (Loggers.RAFT.isDebugEnabled()) {
                            Loggers.RAFT.debug("receive beat response from: {}", url);
                        }
                        return 0;
                    }
                    
                    @Override
                    public void onThrowable(Throwable t) {
                        Loggers.RAFT.error("NACOS-RAFT error while sending heart-beat to peer: {} {}", server, t);
                        MetricsMonitor.getLeaderSendBeatFailedException().increment();
                    }
                });
            } catch (Exception e) {
                Loggers.RAFT.error("error while sending heart-beat to peer: {} {}", server, e);
                MetricsMonitor.getLeaderSendBeatFailedException().increment();
            }
        }
        
    }
}
```

```java
public RaftPeer receivedBeat(JsonNode beat) throws Exception {
    //解析心跳数据
    final RaftPeer local = peers.local();
    final RaftPeer remote = new RaftPeer();
    JsonNode peer = beat.get("peer");
    remote.ip = peer.get("ip").asText();
    remote.state = RaftPeer.State.valueOf(peer.get("state").asText());
    remote.term.set(peer.get("term").asLong());
    remote.heartbeatDueMs = peer.get("heartbeatDueMs").asLong();
    remote.leaderDueMs = peer.get("leaderDueMs").asLong();
    remote.voteFor = peer.get("voteFor").asText();
    //如果发起方非Leader则不处理
    if (remote.state != RaftPeer.State.LEADER) {
        Loggers.RAFT.info("[RAFT] invalid state from master, state: {}, remote peer: {}", remote.state,
                JacksonUtils.toJson(remote));
        throw new IllegalArgumentException("invalid state from master, state: " + remote.state);
    }
    
    //如果轮次
    if (local.term.get() > remote.term.get()) {
        Loggers.RAFT
                .info("[RAFT] out of date beat, beat-from-term: {}, beat-to-term: {}, remote peer: {}, and leaderDueMs: {}",
                        remote.term.get(), local.term.get(), JacksonUtils.toJson(remote), local.leaderDueMs);
        throw new IllegalArgumentException(
                "out of date beat, beat-from-term: " + remote.term.get() + ", beat-to-term: " + local.term.get());
    }
    
    if (local.state != RaftPeer.State.FOLLOWER) {
        
        Loggers.RAFT.info("[RAFT] make remote as leader, remote peer: {}", JacksonUtils.toJson(remote));
        // mk follower
        local.state = RaftPeer.State.FOLLOWER;
        local.voteFor = remote.ip;
    }
    
    final JsonNode beatDatums = beat.get("datums");
    local.resetLeaderDue();
    local.resetHeartbeatDue();
    
    peers.makeLeader(remote);
    
    if (!switchDomain.isSendBeatOnly()) {
        
        Map<String, Integer> receivedKeysMap = new HashMap<>(datums.size());
        
        for (Map.Entry<String, Datum> entry : datums.entrySet()) {
            receivedKeysMap.put(entry.getKey(), 0);
        }
        
        // now check datums
        List<String> batch = new ArrayList<>();
        
        int processedCount = 0;
        if (Loggers.RAFT.isDebugEnabled()) {
            Loggers.RAFT
                    .debug("[RAFT] received beat with {} keys, RaftCore.datums' size is {}, remote server: {}, term: {}, local term: {}",
                            beatDatums.size(), datums.size(), remote.ip, remote.term, local.term);
        }
        for (Object object : beatDatums) {
            processedCount = processedCount + 1;
            
            JsonNode entry = (JsonNode) object;
            String key = entry.get("key").asText();
            final String datumKey;
            
            if (KeyBuilder.matchServiceMetaKey(key)) {
                datumKey = KeyBuilder.detailServiceMetaKey(key);
            } else if (KeyBuilder.matchInstanceListKey(key)) {
                datumKey = KeyBuilder.detailInstanceListkey(key);
            } else {
                // ignore corrupted key:
                continue;
            }
            
            long timestamp = entry.get("timestamp").asLong();
            
            receivedKeysMap.put(datumKey, 1);
            
            try {
                if (datums.containsKey(datumKey) && datums.get(datumKey).timestamp.get() >= timestamp
                        && processedCount < beatDatums.size()) {
                    continue;
                }
                
                if (!(datums.containsKey(datumKey) && datums.get(datumKey).timestamp.get() >= timestamp)) {
                    batch.add(datumKey);
                }
                
                if (batch.size() < 50 && processedCount < beatDatums.size()) {
                    continue;
                }
                
                String keys = StringUtils.join(batch, ",");
                
                if (batch.size() <= 0) {
                    continue;
                }
                
                Loggers.RAFT.info("get datums from leader: {}, batch size is {}, processedCount is {}"
                                + ", datums' size is {}, RaftCore.datums' size is {}", getLeader().ip, batch.size(),
                        processedCount, beatDatums.size(), datums.size());
                
                // update datum entry
                String url = buildUrl(remote.ip, API_GET) + "?keys=" + URLEncoder.encode(keys, "UTF-8");
                HttpClient.asyncHttpGet(url, null, null, new AsyncCompletionHandler<Integer>() {
                    @Override
                    public Integer onCompleted(Response response) throws Exception {
                        if (response.getStatusCode() != HttpURLConnection.HTTP_OK) {
                            return 1;
                        }
                        
                        List<JsonNode> datumList = JacksonUtils
                                .toObj(response.getResponseBody(), new TypeReference<List<JsonNode>>() {
                                });
                        
                        for (JsonNode datumJson : datumList) {
                            Datum newDatum = null;
                            OPERATE_LOCK.lock();
                            try {
                                
                                Datum oldDatum = getDatum(datumJson.get("key").asText());
                                
                                if (oldDatum != null && datumJson.get("timestamp").asLong() <= oldDatum.timestamp
                                        .get()) {
                                    Loggers.RAFT
                                            .info("[NACOS-RAFT] timestamp is smaller than that of mine, key: {}, remote: {}, local: {}",
                                                    datumJson.get("key").asText(),
                                                    datumJson.get("timestamp").asLong(), oldDatum.timestamp);
                                    continue;
                                }
                                
                                if (KeyBuilder.matchServiceMetaKey(datumJson.get("key").asText())) {
                                    Datum<Service> serviceDatum = new Datum<>();
                                    serviceDatum.key = datumJson.get("key").asText();
                                    serviceDatum.timestamp.set(datumJson.get("timestamp").asLong());
                                    serviceDatum.value = JacksonUtils
                                            .toObj(datumJson.get("value").toString(), Service.class);
                                    newDatum = serviceDatum;
                                }
                                
                                if (KeyBuilder.matchInstanceListKey(datumJson.get("key").asText())) {
                                    Datum<Instances> instancesDatum = new Datum<>();
                                    instancesDatum.key = datumJson.get("key").asText();
                                    instancesDatum.timestamp.set(datumJson.get("timestamp").asLong());
                                    instancesDatum.value = JacksonUtils
                                            .toObj(datumJson.get("value").toString(), Instances.class);
                                    newDatum = instancesDatum;
                                }
                                
                                if (newDatum == null || newDatum.value == null) {
                                    Loggers.RAFT.error("receive null datum: {}", datumJson);
                                    continue;
                                }
                                
                                raftStore.write(newDatum);
                                
                                datums.put(newDatum.key, newDatum);
                                notifier.addTask(newDatum.key, ApplyAction.CHANGE);
                                
                                local.resetLeaderDue();
                                
                                if (local.term.get() + 100 > remote.term.get()) {
                                    getLeader().term.set(remote.term.get());
                                    local.term.set(getLeader().term.get());
                                } else {
                                    local.term.addAndGet(100);
                                }
                                
                                raftStore.updateTerm(local.term.get());
                                
                                Loggers.RAFT.info("data updated, key: {}, timestamp: {}, from {}, local term: {}",
                                        newDatum.key, newDatum.timestamp, JacksonUtils.toJson(remote), local.term);
                                
                            } catch (Throwable e) {
                                Loggers.RAFT
                                        .error("[RAFT-BEAT] failed to sync datum from leader, datum: {}", newDatum,
                                                e);
                            } finally {
                                OPERATE_LOCK.unlock();
                            }
                        }
                        TimeUnit.MILLISECONDS.sleep(200);
                        return 0;
                    }
                });
                
                batch.clear();
                
            } catch (Exception e) {
                Loggers.RAFT.error("[NACOS-RAFT] failed to handle beat entry, key: {}", datumKey);
            }
            
        }
        
        List<String> deadKeys = new ArrayList<>();
        for (Map.Entry<String, Integer> entry : receivedKeysMap.entrySet()) {
            if (entry.getValue() == 0) {
                deadKeys.add(entry.getKey());
            }
        }
        
        for (String deadKey : deadKeys) {
            try {
                deleteDatum(deadKey);
            } catch (Exception e) {
                Loggers.RAFT.error("[NACOS-RAFT] failed to remove entry, key={} {}", deadKey, e);
            }
        }
        
    }
    
    return local;
}
```

说明：

1. 定时任务周期性的判断是否可以进行心跳发送
2. 如果到达时间则尝试发送心跳
3. 判断当前节点身份是否是Leader且非Standalone模式，否则不发起心跳
4. 封装心跳数据，有可能尝试携带Instance数据
5. 通过Http协议向所有集群中的其他节点发送心跳数据
6. Follower接收到心跳

## 选主

