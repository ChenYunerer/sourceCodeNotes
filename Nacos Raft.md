# Nacos Raft算法

## 角色
Raft分为三种角色：

1. LEADER： 向其他所有节点发送心跳，并负责集群内的数据“写”
2. FOLLOWER：如果在心跳周期内没有收到Leader的心跳，则标识Leader挂了，可以转为Candidate节点发起投票
3. CANDIDATE：可以发起投票，如果投票数大于集群半数，则成功晋升为Leader并开始向Follower发送心跳

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

说明：

1. 定时任务周期性的判断是否可以进行心跳发送
2. 如果到达时间则尝试发送心跳
3. 判断当前节点身份是否是Leader且非Standalone模式，否则不发起心跳
4. 封装心跳数据，有可能尝试携带Instance数据
5. 通过Http协议向所有集群中的其他节点发送心跳数据

## 选主

