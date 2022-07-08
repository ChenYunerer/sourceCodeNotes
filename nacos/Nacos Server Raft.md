---
title: Nacos Server Raft
tags: Nacos
categories: Nacos
---



# Nacos Raft算法

# Raft部分

## 角色

Raft分为三种角色：

1. LEADER： 向其他所有节点发送心跳，并负责集群内的数据“写”
2. FOLLOWER：如果在心跳周期内没有收到Leader的心跳，则标识Leader挂了，可以转为Candidate节点发起投票
3. CANDIDATE：可以发起投票，如果投票数大于集群半数，则成功晋升为Leader并开始向Follower发送心跳

## 轮次

投票选举、心跳都存在轮次概念，低于本地记录的轮次的数据可能是网络延迟导致的老数据，丢弃不做处理

投票选举可能不到半数或是刚好半数，则也要发起下一轮次的投票

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
RaftCore HeartBeat.calss
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
RaftCore HeartBeat.calss
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
    
    //如果轮次低于本地记录的轮次则不处理
    if (local.term.get() > remote.term.get()) {
        Loggers.RAFT
                .info("[RAFT] out of date beat, beat-from-term: {}, beat-to-term: {}, remote peer: {}, and leaderDueMs: {}",
                        remote.term.get(), local.term.get(), JacksonUtils.toJson(remote), local.leaderDueMs);
        throw new IllegalArgumentException(
                "out of date beat, beat-from-term: " + remote.term.get() + ", beat-to-term: " + local.term.get());
    }
    
   //如果本节点不是Follower节点，则切换到Follower模式，并且为该节点投票
    if (local.state != RaftPeer.State.FOLLOWER) {
        
        Loggers.RAFT.info("[RAFT] make remote as leader, remote peer: {}", JacksonUtils.toJson(remote));
        // mk follower
        local.state = RaftPeer.State.FOLLOWER;
        local.voteFor = remote.ip;
    }
    
    final JsonNode beatDatums = beat.get("datums");
    local.resetLeaderDue();
    local.resetHeartbeatDue();
    //设置Leader
    peers.makeLeader(remote);
   //如果并非单纯的心跳，如果包含数据的话，则对数据进行处理
    ......
    return local;
}
```

说明：

1. 定时任务周期性的判断是否可以进行心跳发送
2. 如果到达时间则尝试发送心跳
3. 判断当前节点身份是否是Leader且非Standalone模式，否则不发起心跳
4. 封装心跳数据，有可能尝试携带Instance数据
5. 通过Http协议向所有集群中的其他节点发送心跳数据
6. Follower接收到心跳则设置Leader为该节点，并设置自己为Follower，并重制LeaderDue和HeartbeatDue

## 选主

RaftCore init方法中会开启MasterElection任务，定时周期性检测并尝试发起投票

```java
RaftCore MasterElection.calss
        public void run() {
            try {
                
                if (!peers.isReady()) {
                    return;
                }
                //MasterElection task周期性执行，每次执行将Leader过期时间减去周期时间
                //如果大于0则表示Leader正常
                //如果小于0则标识Leader可能挂了，在过期时间内没有收到Leader的心跳了
                RaftPeer local = peers.local();
                local.leaderDueMs -= GlobalExecutor.TICK_PERIOD_MS;
                
                if (local.leaderDueMs > 0) {
                    return;
                }
                
                // reset timeout
                local.resetLeaderDue();
                local.resetHeartbeatDue();
                //发起投票，竞选Leader
                sendVote();
            } catch (Exception e) {
                Loggers.RAFT.warn("[RAFT] error while master election {}", e);
            }
            
        }
```

```java
RaftCore MasterElection.calss
private void sendVote() {
            //拿到代表自己的RaftPeer
            RaftPeer local = peers.get(NetUtils.localServer());
            Loggers.RAFT.info("leader timeout, start voting,leader: {}, term: {}", JacksonUtils.toJson(getLeader()),
                    local.term);
            
            peers.reset();
            //投票轮数加1，并默认自己投票给自己，并切换到Candidate模式
            local.term.incrementAndGet();
            local.voteFor = local.ip;
            local.state = RaftPeer.State.CANDIDATE;
            //封装数据
            Map<String, String> params = new HashMap<>(1);
            params.put("vote", JacksonUtils.toJson(local));
 						//遍历集群内除了自己的所有节点
            for (final String server : peers.allServersWithoutMySelf()) {
              	//向每个节点发起投票请求
                final String url = buildUrl(server, API_VOTE);
                try {
                    HttpClient.asyncHttpPost(url, null, params, new AsyncCompletionHandler<Integer>() {
                        @Override
                        public Integer onCompleted(Response response) throws Exception {
                            if (response.getStatusCode() != HttpURLConnection.HTTP_OK) {
                                Loggers.RAFT
                                        .error("NACOS-RAFT vote failed: {}, url: {}", response.getResponseBody(), url);
                                return 1;
                            }
                            
                            RaftPeer peer = JacksonUtils.toObj(response.getResponseBody(), RaftPeer.class);
                            
                            Loggers.RAFT.info("received approve from peer: {}", JacksonUtils.toJson(peer));
                            //处理投票结果，该方法中如果统计该次轮次内获得的投票大于集群数量的一半则
                          	//成功晋升为Leader，并向其他节点发送心跳
                          	//如果不够票数，则等待下次任务执行，尝试再次发起下一轮次的竞选
                            peers.decideLeader(peer);
                            
                            return 0;
                        }
                    });
                } catch (Exception e) {
                    Loggers.RAFT.warn("error while sending vote to server: {}", server);
                }
            }
        }
```

```java
RaftCore MasterElection.calss
public synchronized RaftPeer receivedVote(RaftPeer remote) {
  	//如果发起投票的节点不在我的节点列表中则不做处理
    if (!peers.contains(remote)) {
        throw new IllegalStateException("can not find peer: " + remote.ip);
    }
    
    RaftPeer local = peers.get(NetUtils.localServer());
  	//如果投票轮次小于当前节点轮次，则将轮次信息返回给remote节点，并投票给自己
    if (remote.term.get() <= local.term.get()) {
        String msg = "received illegitimate vote" + ", voter-term:" + remote.term + ", votee-term:" + local.term;
        
        Loggers.RAFT.info(msg);
        if (StringUtils.isEmpty(local.voteFor)) {
            local.voteFor = local.ip;
        }
        
        return local;
    }
    
    local.resetLeaderDue();
    //将自己的模式设置为Follwoer并为remote节点投票
    local.state = RaftPeer.State.FOLLOWER;
    local.voteFor = remote.ip;
    local.term.set(remote.term.get());
    
    Loggers.RAFT.info("vote {} as leader, term: {}", remote.ip, remote.term);
    
    return local;
}
```

说明：

1. 定时任务周期性的判断是否Leader以及掉线
2. 如果Leader掉线，在周期内没有收到Leader心跳，则尝试发起投票
3. 切换当前节点模式为Candidate，投票轮次加一，且默认自己投票给自己
4. 封装投票数据，发送给集群内的其他节点
5. 其他节点接收到投票，判断合法性之后，对该Remote节点进行投票
6. Local节点对返回的投票数进行计算，如果大于集群的一半则晋升为Leader节点，向集群发送心跳

# Nacos 部分

nacos 集群节点接收到服务注册消息，如果是采用的Raft一致性方案的时候：

1. 如果本地节点不是Leader节点则会将注册数据发送给Leader节点

2. 如果本地节点是Leader节点，则进行写入File Cache和Map，并同步给集群其他节点，同步过程进行加锁处理保证数据一致性

```java
public void signalPublish(String key, Record value) throws Exception {
    //如果当前节点是不是Leader，则通过raftProxy发送给Leader节点
    if (!isLeader()) {
        ObjectNode params = JacksonUtils.createEmptyJsonNode();
        params.put("key", key);
        params.replace("value", JacksonUtils.transferToJsonNode(value));
        Map<String, String> parameters = new HashMap<>(1);
        parameters.put("key", key);
        
        final RaftPeer leader = getLeader();
        
        raftProxy.proxyPostLarge(leader.ip, API_PUB, params.toString(), parameters);
        return;
    }
    //如果当前节点是Leader节点，则将数据通过RaftStore保存之本地FileCache，并同步给集群内的其他节点
  	//通过的时候进行加锁，保证数据的一致性
    try {
        OPERATE_LOCK.lock();
        final long start = System.currentTimeMillis();
        final Datum datum = new Datum();
        datum.key = key;
        datum.value = value;
        if (getDatum(key) == null) {
            datum.timestamp.set(1L);
        } else {
            datum.timestamp.set(getDatum(key).timestamp.incrementAndGet());
        }
        
        ObjectNode json = JacksonUtils.createEmptyJsonNode();
        json.replace("datum", JacksonUtils.transferToJsonNode(datum));
        json.replace("source", JacksonUtils.transferToJsonNode(peers.local()));
        
        onPublish(datum, peers.local());
        
        final String content = json.toString();
        
        final CountDownLatch latch = new CountDownLatch(peers.majorityCount());
        for (final String server : peers.allServersIncludeMyself()) {
            if (isLeader(server)) {
                latch.countDown();
                continue;
            }
            final String url = buildUrl(server, API_ON_PUB);
          	//通过Http请求将数据发送给所有节点
            HttpClient.asyncHttpPostLarge(url, Arrays.asList("key=" + key), content,
                    new AsyncCompletionHandler<Integer>() {
                        @Override
                        public Integer onCompleted(Response response) throws Exception {
                            if (response.getStatusCode() != HttpURLConnection.HTTP_OK) {
                                Loggers.RAFT
                                        .warn("[RAFT] failed to publish data to peer, datumId={}, peer={}, http code={}",
                                                datum.key, server, response.getStatusCode());
                                return 1;
                            }
                            latch.countDown();
                            return 0;
                        }
                        
                        @Override
                        public STATE onContentWriteCompleted() {
                            return STATE.CONTINUE;
                        }
                    });
            
        }
        
        if (!latch.await(UtilsAndCommons.RAFT_PUBLISH_TIMEOUT, TimeUnit.MILLISECONDS)) {
            // only majority servers return success can we consider this update success
            Loggers.RAFT.error("data publish failed, caused failed to notify majority, key={}", key);
            throw new IllegalStateException("data publish failed, caused failed to notify majority, key=" + key);
        }
        
        long end = System.currentTimeMillis();
        Loggers.RAFT.info("signalPublish cost {} ms, key: {}", (end - start), key);
    } finally {
        OPERATE_LOCK.unlock();
    }
}
```

