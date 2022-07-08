---
title: RocketMQ Consumer
data: 2020-10-13 23:24:49
tags: RocketMQ
categories: MQ

---
# RocketMQ Consumer

**源码基于：4.7.1**

RocketMQ的消费模式分为：

1. 广播模式
2. 集群模式

## 广播模式用例

```java
public class PushConsumer {

    public static void main(String[] args) throws InterruptedException, MQClientException {
        DefaultMQPushConsumer consumer = new DefaultMQPushConsumer("CID_JODIE_1");
        consumer.subscribe("TopicTest", "*");
        consumer.setConsumeFromWhere(ConsumeFromWhere.CONSUME_FROM_FIRST_OFFSET);
        //wrong time format 2017_0422_221800
        consumer.setConsumeTimestamp("20181109221800");
        consumer.registerMessageListener(new MessageListenerConcurrently() {

            @Override
            public ConsumeConcurrentlyStatus consumeMessage(List<MessageExt> msgs, ConsumeConcurrentlyContext context) {
                System.out.printf("%s Receive New Messages: %s %n", Thread.currentThread().getName(), msgs);
                return ConsumeConcurrentlyStatus.CONSUME_SUCCESS;
            }
        });
        consumer.start();
        System.out.printf("Consumer Started.%n");
    }
}
```

## DefaultMQPushConsumer构建

```java
DefaultMQPushConsumer.class
public DefaultMQPushConsumer(final String namespace, final String consumerGroup, RPCHook rpcHook,
    AllocateMessageQueueStrategy allocateMessageQueueStrategy) {
    this.consumerGroup = consumerGroup;
    this.namespace = namespace;
    this.allocateMessageQueueStrategy = allocateMessageQueueStrategy;
    defaultMQPushConsumerImpl = new DefaultMQPushConsumerImpl(this, rpcHook);
}
```

主要就是对consumerGroup namespace allocateMessageQueueStrategy进行设置，并且构建DefaultMQPushConsumerImpl

allocateMessageQueueStrategy：该类用于r配置Consume应该从哪几个MessageQueue获取Message，默认为：AllocateMessageQueueAveragely

## MessageQueue分配策略

| 策略                                  | 说明                                                         | 默认 |
| ------------------------------------- | ------------------------------------------------------------ | ---- |
| AllocateMachineRoomNearby             | 就近机房分配策略：根据BrokerName ConsumerId的前缀来判断是否是同一机房，然后进行分配 |      |
| AllocateMessageQueueAveragely         | 平均分配策略                                                 | 默认 |
| AllocateMessageQueueAveragelyByCircle | 环状平均分配策略                                             |      |
| AllocateMessageQueueByConfig          | 根据配置分配策略：根据配置来进行分配                         |      |
| AllocateMessageQueueByMachineRoom     | 指定机房策略                                                 |      |
| AllocateMessageQueueConsistentHash    | 统一哈希策略：根据client在hash环上的位置来确定从哪个message queue获取消息 |      |



## DefaultMQPushConsumer start

```java
DefaultMQPushConsumer.class
    
public void start() throws MQClientException {
    //根据NameSpace重新设置下ConsumerGroup
    setConsumerGroup(NamespaceUtil.wrapNamespace(this.getNamespace(), this.consumerGroup));
    //启动defaultMQPushConsumerImpl
    this.defaultMQPushConsumerImpl.start();
    if (null != traceDispatcher) {
        try {
            traceDispatcher.start(this.getNamesrvAddr(), this.getAccessChannel());
        } catch (MQClientException e) {
            log.warn("trace dispatcher start failed ", e);
        }
    }
}
```

```java
DefaultMQPushConsumerImpl.class
    
public synchronized void start() throws MQClientException {
    switch (this.serviceState) {
        case CREATE_JUST:
            log.info("the consumer [{}] start beginning. messageModel={}, isUnitMode={}", this.defaultMQPushConsumer.getConsumerGroup(),
                this.defaultMQPushConsumer.getMessageModel(), this.defaultMQPushConsumer.isUnitMode());
            this.serviceState = ServiceState.START_FAILED;
            //对配置进行校验 错误则抛错
            this.checkConfig();
            //将topic订阅信息赋值给rebalanceImpl(RebalanceImpl)，如果是集群模式增加重试topic订阅信息到rebalanceImpl
            this.copySubscription();
            //如果是集群模式将instanceName设置成PID
            if (this.defaultMQPushConsumer.getMessageModel() == MessageModel.CLUSTERING) {
                this.defaultMQPushConsumer.changeInstanceNameToPID();
            }
            //获取MQClientInstance
            this.mQClientFactory = MQClientManager.getInstance().getOrCreateMQClientInstance(this.defaultMQPushConsumer, this.rpcHook);
           
            //配置RebalanceImpl
            this.rebalanceImpl.setConsumerGroup(this.defaultMQPushConsumer.getConsumerGroup());
            this.rebalanceImpl.setMessageModel(this.defaultMQPushConsumer.getMessageModel());
            this.rebalanceImpl.setAllocateMessageQueueStrategy(this.defaultMQPushConsumer.getAllocateMessageQueueStrategy());
            this.rebalanceImpl.setmQClientFactory(this.mQClientFactory);

            this.pullAPIWrapper = new PullAPIWrapper(
                mQClientFactory,
                this.defaultMQPushConsumer.getConsumerGroup(), isUnitMode());
            this.pullAPIWrapper.registerFilterMessageHook(filterMessageHookList);
            //根据不同模式构建不同的offsetStore，并调用load方法加载当前consumer的消费偏移量
            //广播模式：mq消费offset由consumer自己保存到本地
            //集群模式：mq消费offset由broker保存
            if (this.defaultMQPushConsumer.getOffsetStore() != null) {
                this.offsetStore = this.defaultMQPushConsumer.getOffsetStore();
            } else {
                switch (this.defaultMQPushConsumer.getMessageModel()) {
                    case BROADCASTING:
                        this.offsetStore = new LocalFileOffsetStore(this.mQClientFactory, this.defaultMQPushConsumer.getConsumerGroup());
                        break;
                    case CLUSTERING:
                        this.offsetStore = new RemoteBrokerOffsetStore(this.mQClientFactory, this.defaultMQPushConsumer.getConsumerGroup());
                        break;
                    default:
                        break;
                }
                this.defaultMQPushConsumer.setOffsetStore(this.offsetStore);
            }
            this.offsetStore.load();
            //根据消费模式不同构建不同的ConsumeMessageService，并启动ConsumeMessageService处理消息回调
            //如果是顺序消费则构建ConsumeMessageOrderlyService
            //非顺序消费则构建ConsumeMessageConcurrentlyService
            if (this.getMessageListenerInner() instanceof MessageListenerOrderly) {
                this.consumeOrderly = true;
                this.consumeMessageService =
                    new ConsumeMessageOrderlyService(this, (MessageListenerOrderly) this.getMessageListenerInner());
            } else if (this.getMessageListenerInner() instanceof MessageListenerConcurrently) {
                this.consumeOrderly = false;
                this.consumeMessageService =
                    new ConsumeMessageConcurrentlyService(this, (MessageListenerConcurrently) this.getMessageListenerInner());
            }

            this.consumeMessageService.start();
            //将当前consumer注册到MQClientInstance consumerTable(MAP key: consumerGroup value: MQConsumerInner)
            boolean registerOK = mQClientFactory.registerConsumer(this.defaultMQPushConsumer.getConsumerGroup(), this);
            if (!registerOK) {
                this.serviceState = ServiceState.CREATE_JUST;
                this.consumeMessageService.shutdown(defaultMQPushConsumer.getAwaitTerminationMillisWhenShutdown());
                throw new MQClientException("The consumer group[" + this.defaultMQPushConsumer.getConsumerGroup()
                    + "] has been created before, specify another name please." + FAQUrl.suggestTodo(FAQUrl.GROUP_NAME_DUPLICATE_URL),
                    null);
            }
            //启动MQClientInstance
            mQClientFactory.start();
            log.info("the consumer [{}] start OK.", this.defaultMQPushConsumer.getConsumerGroup());
            this.serviceState = ServiceState.RUNNING;
            break;
        case RUNNING:
        case START_FAILED:
        case SHUTDOWN_ALREADY:
            throw new MQClientException("The PushConsumer service state not OK, maybe started once, "
                + this.serviceState
                + FAQUrl.suggestTodo(FAQUrl.CLIENT_SERVICE_NOT_OK),
                null);
        default:
            break;
    }
    //新增了订阅信息，所以尝试从NameSrv更新topic的路由信息并更新RebalanceImpl topicSubscribeInfoTable(topicSubscribeInfoTable记录了topic以及对应的多有MessageQueue信息)
    this.updateTopicSubscribeInfoWhenSubscriptionChanged();
    //从Brokerk核对Client信息(不懂啥意思，不懂这个Broker的请求有啥用)
    this.mQClientFactory.checkClientInBroker();
    //向Broker发送心跳
    this.mQClientFactory.sendHeartbeatToAllBrokerWithLock();
    //唤醒RebalanceService，RebalanceService服务用于给当前consumer分配message queue并触发消息拉取
    this.mQClientFactory.rebalanceImmediately();
}
```

```java
MQClientInstance.class
    
public void start() throws MQClientException {

    synchronized (this) {
        switch (this.serviceState) {
            case CREATE_JUST:
                this.serviceState = ServiceState.START_FAILED;
                // If not specified,looking address from name server
                if (null == this.clientConfig.getNamesrvAddr()) {
                    this.mQClientAPIImpl.fetchNameServerAddr();
                }
                // Start request-response channel
                this.mQClientAPIImpl.start();
                // Start various schedule tasks
                this.startScheduledTask();
                // Start pull service
                this.pullMessageService.start();
                // Start rebalance service
                this.rebalanceService.start();
                // Start push service
                this.defaultMQProducer.getDefaultMQProducerImpl().start(false);
                log.info("the client factory [{}] start OK", this.clientId);
                this.serviceState = ServiceState.RUNNING;
                break;
            case START_FAILED:
                throw new MQClientException("The Factory object[" + this.getClientId() + "] has been created before, and failed.", null);
            default:
                break;
        }
    }
}
```

部分代码在Producer源码笔记部分已经说明了，Consumer主要关注两部分：

1. this.pullMessageService.start() 从Broker的MessageQueue拉取Message
2. this.rebalanceService.start() 给当前Consumer根据一定策略分配MessageQueue

## RebalanceService start

```java
RebalanceService.class
    
@Override
public void run() {
    log.info(this.getServiceName() + " service started");

    //非停止状态下 默认每隔20秒进行重新分配
    while (!this.isStopped()) {
        this.waitForRunning(waitInterval);
        this.mqClientFactory.doRebalance();
    }

    log.info(this.getServiceName() + " service end");
}
```

```java
MQClientInstance.class
//调用所有注册上来的MQConsumerInner的doRebalance方法进行分配
public void doRebalance() {
    for (Map.Entry<String, MQConsumerInner> entry : this.consumerTable.entrySet()) {
        MQConsumerInner impl = entry.getValue();
        if (impl != null) {
            try {
                impl.doRebalance();
            } catch (Throwable e) {
                log.error("doRebalance exception", e);
            }
        }
    }
}
```
```java
RebalanceImpl.class
//对consumer的每个订阅topic进行重新配置(包括重试topic)
public void doRebalance(final boolean isOrder) {
        Map<String, SubscriptionData> subTable = this.getSubscriptionInner();
        if (subTable != null) {
            for (final Map.Entry<String, SubscriptionData> entry : subTable.entrySet()) {
                final String topic = entry.getKey();
                try {
                    this.rebalanceByTopic(topic, isOrder);
                } catch (Throwable e) {
                    if (!topic.startsWith(MixAll.RETRY_GROUP_TOPIC_PREFIX)) {
                        log.warn("rebalanceByTopic Exception", e);
                    }
                }
            }
        }

        this.truncateMessageQueueNotMyTopic();
    }
```
```java
RebalanceImpl.class
private void rebalanceByTopic(final String topic, final boolean isOrder) {
    switch (messageModel) {
        case BROADCASTING: {
            Set<MessageQueue> mqSet = this.topicSubscribeInfoTable.get(topic);
            if (mqSet != null) {
                boolean changed = this.updateProcessQueueTableInRebalance(topic, mqSet, isOrder);
                if (changed) {
                    this.messageQueueChanged(topic, mqSet, mqSet);
                    log.info("messageQueueChanged {} {} {} {}",
                        consumerGroup,
                        topic,
                        mqSet,
                        mqSet);
                }
            } else {
                log.warn("doRebalance, {}, but the topic[{}] not exist.", consumerGroup, topic);
            }
            break;
        }
        case CLUSTERING: {
            //集群模式
            //获取topic所有相关的message queue
            Set<MessageQueue> mqSet = this.topicSubscribeInfoTable.get(topic);
            //获取topic所有的ConsumerId
            List<String> cidAll = this.mQClientFactory.findConsumerIdList(topic, consumerGroup);
            if (null == mqSet) {
                if (!topic.startsWith(MixAll.RETRY_GROUP_TOPIC_PREFIX)) {
                    log.warn("doRebalance, {}, but the topic[{}] not exist.", consumerGroup, topic);
                }
            }

            if (null == cidAll) {
                log.warn("doRebalance, {} {}, get consumer id list failed", consumerGroup, topic);
            }

            if (mqSet != null && cidAll != null) {
                List<MessageQueue> mqAll = new ArrayList<MessageQueue>();
                mqAll.addAll(mqSet);

                Collections.sort(mqAll);
                Collections.sort(cidAll);

                AllocateMessageQueueStrategy strategy = this.allocateMessageQueueStrategy;
                //通过分配策略选出当前consumer分配到的message queue
                List<MessageQueue> allocateResult = null;
                try {
                    allocateResult = strategy.allocate(
                        this.consumerGroup,
                        this.mQClientFactory.getClientId(),
                        mqAll,
                        cidAll);
                } catch (Throwable e) {
                    log.error("AllocateMessageQueueStrategy.allocate Exception. allocateMessageQueueStrategyName={}", strategy.getName(),
                        e);
                    return;
                }

                Set<MessageQueue> allocateResultSet = new HashSet<MessageQueue>();
                if (allocateResult != null) {
                    allocateResultSet.addAll(allocateResult);
                }
                //在RebalanceImpl中更新processQueueTable，主要就是在该方法中构建PullRequest并添加到PullMessageService的pullRequestQueue队列中，PullMessageService将从该队列取出PullRequest然后向Broker发起请求
                boolean changed = this.updateProcessQueueTableInRebalance(topic, allocateResultSet, isOrder);
                if (changed) {
                    log.info(
                        "rebalanced result changed. allocateMessageQueueStrategyName={}, group={}, topic={}, clientId={}, mqAllSize={}, cidAllSize={}, rebalanceResultSize={}, rebalanceResultSet={}",
                        strategy.getName(), consumerGroup, topic, this.mQClientFactory.getClientId(), mqSet.size(), cidAll.size(),
                        allocateResultSet.size(), allocateResultSet);
                    this.messageQueueChanged(topic, mqSet, allocateResultSet);
                }
            }
            break;
        }
        default:
            break;
    }
}
```

```java
RebalanceImpl.class
  
private boolean updateProcessQueueTableInRebalance(final String topic, final Set<MessageQueue> mqSet,
    final boolean isOrder) {
    boolean changed = false;
  	//以下代码其实就是在更新processQueueTable
    Iterator<Entry<MessageQueue, ProcessQueue>> it = this.processQueueTable.entrySet().iterator();
    while (it.hasNext()) {
        Entry<MessageQueue, ProcessQueue> next = it.next();
        MessageQueue mq = next.getKey();
        ProcessQueue pq = next.getValue();

        if (mq.getTopic().equals(topic)) {
            if (!mqSet.contains(mq)) {
                pq.setDropped(true);
                if (this.removeUnnecessaryMessageQueue(mq, pq)) {
                    it.remove();
                    changed = true;
                    log.info("doRebalance, {}, remove unnecessary mq, {}", consumerGroup, mq);
                }
            } else if (pq.isPullExpired()) {
                switch (this.consumeType()) {
                    case CONSUME_ACTIVELY:
                        break;
                    case CONSUME_PASSIVELY:
                        pq.setDropped(true);
                        if (this.removeUnnecessaryMessageQueue(mq, pq)) {
                            it.remove();
                            changed = true;
                            log.error("[BUG]doRebalance, {}, remove unnecessary mq, {}, because pull is pause, so try to fixed it",
                                consumerGroup, mq);
                        }
                        break;
                    default:
                        break;
                }
            }
        }
    }
  	//构建PullRequest
    List<PullRequest> pullRequestList = new ArrayList<PullRequest>();
    for (MessageQueue mq : mqSet) {
        if (!this.processQueueTable.containsKey(mq)) {
            if (isOrder && !this.lock(mq)) {
                log.warn("doRebalance, {}, add a new mq failed, {}, because lock failed", consumerGroup, mq);
                continue;
            }

            this.removeDirtyOffset(mq);
            ProcessQueue pq = new ProcessQueue();
            long nextOffset = this.computePullFromWhere(mq);
            if (nextOffset >= 0) {
                ProcessQueue pre = this.processQueueTable.putIfAbsent(mq, pq);
                if (pre != null) {
                    log.info("doRebalance, {}, mq already exists, {}", consumerGroup, mq);
                } else {
                    log.info("doRebalance, {}, add a new mq, {}", consumerGroup, mq);
                    PullRequest pullRequest = new PullRequest();
                    pullRequest.setConsumerGroup(consumerGroup);
                    pullRequest.setNextOffset(nextOffset);
                    pullRequest.setMessageQueue(mq);
                    pullRequest.setProcessQueue(pq);
                    pullRequestList.add(pullRequest);
                    changed = true;
                }
            } else {
                log.warn("doRebalance, {}, add new mq failed, {}", consumerGroup, mq);
            }
        }
    }
  	//分发PullRequest其实就是将pullRequestList添加到PullMessageService的pullRequestQueue队列中，PullMessageService将从该队列取出PullRequest然后向Broker发起请求
    this.dispatchPullRequest(pullRequestList);

    return changed;
}
```

**以上涉及到的几个重要的HashMap**

| 名称                                  | key          | key说明               | value                 | value说明                     |
| ------------------------------------- | ------------ | --------------------- | --------------------- | ----------------------------- |
| MQClientInstance consumerTable        | String       | ConsumerGroup         | MQConsumerInner       | Consume                       |
| MQClientInstance brokerAddrTable      | String       | brokerName broker名称 | HashMap<Long, String> | key: brokerId value: address  |
| RebalanceImpl topicSubscribeInfoTable | String       | topic                 | Set<MessageQueue>     | 该topic相关的所有MessageQueue |
| RebalanceImpl processQueueTable       | MessageQueue |                       | ProcessQueue          |                               |

## PullMessageService start

```java
PullMessageService.class
  
public void run() {
    log.info(this.getServiceName() + " service started");

    while (!this.isStopped()) {
        try {
          	//阻塞式从pullRequestQueue中获取PullRequest并进行处理（发送消息到broker来获取message）
            PullRequest pullRequest = this.pullRequestQueue.take();
            this.pullMessage(pullRequest);
        } catch (InterruptedException ignored) {
        } catch (Exception e) {
            log.error("Pull Message Service Run Method exception", e);
        }
    }

    log.info(this.getServiceName() + " service end");
}
```

```java
PullMessageService.class
  
private void pullMessage(final PullRequest pullRequest) {
  	//获取对应的MQConsumerInner并调用其pullMessage
    final MQConsumerInner consumer = this.mQClientFactory.selectConsumer(pullRequest.getConsumerGroup());
    if (consumer != null) {
        DefaultMQPushConsumerImpl impl = (DefaultMQPushConsumerImpl) consumer;
        impl.pullMessage(pullRequest);
    } else {
        log.warn("No matched consumer for the PullRequest {}, drop it", pullRequest);
    }
}
```

```java
DefaultMQPushConsumerImpl.class

public void pullMessage(final PullRequest pullRequest) {
    final ProcessQueue processQueue = pullRequest.getProcessQueue();
    if (processQueue.isDropped()) {
        log.info("the pull request[{}] is dropped.", pullRequest.toString());
        return;
    }

    pullRequest.getProcessQueue().setLastPullTimestamp(System.currentTimeMillis());

    try {
        this.makeSureStateOK();
    } catch (MQClientException e) {
        log.warn("pullMessage exception, consumer state not ok", e);
        this.executePullRequestLater(pullRequest, pullTimeDelayMillsWhenException);
        return;
    }

    if (this.isPause()) {
        log.warn("consumer was paused, execute pull request later. instanceName={}, group={}", this.defaultMQPushConsumer.getInstanceName(), this.defaultMQPushConsumer.getConsumerGroup());
        this.executePullRequestLater(pullRequest, PULL_TIME_DELAY_MILLS_WHEN_SUSPEND);
        return;
    }

    long cachedMessageCount = processQueue.getMsgCount().get();
    long cachedMessageSizeInMiB = processQueue.getMsgSize().get() / (1024 * 1024);

    if (cachedMessageCount > this.defaultMQPushConsumer.getPullThresholdForQueue()) {
        this.executePullRequestLater(pullRequest, PULL_TIME_DELAY_MILLS_WHEN_FLOW_CONTROL);
        if ((queueFlowControlTimes++ % 1000) == 0) {
            log.warn(
                "the cached message count exceeds the threshold {}, so do flow control, minOffset={}, maxOffset={}, count={}, size={} MiB, pullRequest={}, flowControlTimes={}",
                this.defaultMQPushConsumer.getPullThresholdForQueue(), processQueue.getMsgTreeMap().firstKey(), processQueue.getMsgTreeMap().lastKey(), cachedMessageCount, cachedMessageSizeInMiB, pullRequest, queueFlowControlTimes);
        }
        return;
    }

    if (cachedMessageSizeInMiB > this.defaultMQPushConsumer.getPullThresholdSizeForQueue()) {
        this.executePullRequestLater(pullRequest, PULL_TIME_DELAY_MILLS_WHEN_FLOW_CONTROL);
        if ((queueFlowControlTimes++ % 1000) == 0) {
            log.warn(
                "the cached message size exceeds the threshold {} MiB, so do flow control, minOffset={}, maxOffset={}, count={}, size={} MiB, pullRequest={}, flowControlTimes={}",
                this.defaultMQPushConsumer.getPullThresholdSizeForQueue(), processQueue.getMsgTreeMap().firstKey(), processQueue.getMsgTreeMap().lastKey(), cachedMessageCount, cachedMessageSizeInMiB, pullRequest, queueFlowControlTimes);
        }
        return;
    }

    if (!this.consumeOrderly) {
        if (processQueue.getMaxSpan() > this.defaultMQPushConsumer.getConsumeConcurrentlyMaxSpan()) {
            this.executePullRequestLater(pullRequest, PULL_TIME_DELAY_MILLS_WHEN_FLOW_CONTROL);
            if ((queueMaxSpanFlowControlTimes++ % 1000) == 0) {
                log.warn(
                    "the queue's messages, span too long, so do flow control, minOffset={}, maxOffset={}, maxSpan={}, pullRequest={}, flowControlTimes={}",
                    processQueue.getMsgTreeMap().firstKey(), processQueue.getMsgTreeMap().lastKey(), processQueue.getMaxSpan(),
                    pullRequest, queueMaxSpanFlowControlTimes);
            }
            return;
        }
    } else {
        if (processQueue.isLocked()) {
            if (!pullRequest.isLockedFirst()) {
                final long offset = this.rebalanceImpl.computePullFromWhere(pullRequest.getMessageQueue());
                boolean brokerBusy = offset < pullRequest.getNextOffset();
                log.info("the first time to pull message, so fix offset from broker. pullRequest: {} NewOffset: {} brokerBusy: {}",
                    pullRequest, offset, brokerBusy);
                if (brokerBusy) {
                    log.info("[NOTIFYME]the first time to pull message, but pull request offset larger than broker consume offset. pullRequest: {} NewOffset: {}",
                        pullRequest, offset);
                }

                pullRequest.setLockedFirst(true);
                pullRequest.setNextOffset(offset);
            }
        } else {
            this.executePullRequestLater(pullRequest, pullTimeDelayMillsWhenException);
            log.info("pull message later because not locked in broker, {}", pullRequest);
            return;
        }
    }

    final SubscriptionData subscriptionData = this.rebalanceImpl.getSubscriptionInner().get(pullRequest.getMessageQueue().getTopic());
    if (null == subscriptionData) {
        this.executePullRequestLater(pullRequest, pullTimeDelayMillsWhenException);
        log.warn("find the consumer's subscription failed, {}", pullRequest);
        return;
    }

    final long beginTimestamp = System.currentTimeMillis();

    PullCallback pullCallback = new PullCallback() {
        @Override
        public void onSuccess(PullResult pullResult) {
            if (pullResult != null) {
                pullResult = DefaultMQPushConsumerImpl.this.pullAPIWrapper.processPullResult(pullRequest.getMessageQueue(), pullResult,
                    subscriptionData);

                switch (pullResult.getPullStatus()) {
                    case FOUND:
                        long prevRequestOffset = pullRequest.getNextOffset();
                        pullRequest.setNextOffset(pullResult.getNextBeginOffset());
                        long pullRT = System.currentTimeMillis() - beginTimestamp;
                        DefaultMQPushConsumerImpl.this.getConsumerStatsManager().incPullRT(pullRequest.getConsumerGroup(),
                            pullRequest.getMessageQueue().getTopic(), pullRT);

                        long firstMsgOffset = Long.MAX_VALUE;
                        if (pullResult.getMsgFoundList() == null || pullResult.getMsgFoundList().isEmpty()) {
                            DefaultMQPushConsumerImpl.this.executePullRequestImmediately(pullRequest);
                        } else {
                            firstMsgOffset = pullResult.getMsgFoundList().get(0).getQueueOffset();

                            DefaultMQPushConsumerImpl.this.getConsumerStatsManager().incPullTPS(pullRequest.getConsumerGroup(),
                                pullRequest.getMessageQueue().getTopic(), pullResult.getMsgFoundList().size());

                            boolean dispatchToConsume = processQueue.putMessage(pullResult.getMsgFoundList());
                            DefaultMQPushConsumerImpl.this.consumeMessageService.submitConsumeRequest(
                                pullResult.getMsgFoundList(),
                                processQueue,
                                pullRequest.getMessageQueue(),
                                dispatchToConsume);

                            if (DefaultMQPushConsumerImpl.this.defaultMQPushConsumer.getPullInterval() > 0) {
                                DefaultMQPushConsumerImpl.this.executePullRequestLater(pullRequest,
                                    DefaultMQPushConsumerImpl.this.defaultMQPushConsumer.getPullInterval());
                            } else {
                                DefaultMQPushConsumerImpl.this.executePullRequestImmediately(pullRequest);
                            }
                        }

                        if (pullResult.getNextBeginOffset() < prevRequestOffset
                            || firstMsgOffset < prevRequestOffset) {
                            log.warn(
                                "[BUG] pull message result maybe data wrong, nextBeginOffset: {} firstMsgOffset: {} prevRequestOffset: {}",
                                pullResult.getNextBeginOffset(),
                                firstMsgOffset,
                                prevRequestOffset);
                        }

                        break;
                    case NO_NEW_MSG:
                        pullRequest.setNextOffset(pullResult.getNextBeginOffset());

                        DefaultMQPushConsumerImpl.this.correctTagsOffset(pullRequest);

                        DefaultMQPushConsumerImpl.this.executePullRequestImmediately(pullRequest);
                        break;
                    case NO_MATCHED_MSG:
                        pullRequest.setNextOffset(pullResult.getNextBeginOffset());

                        DefaultMQPushConsumerImpl.this.correctTagsOffset(pullRequest);

                        DefaultMQPushConsumerImpl.this.executePullRequestImmediately(pullRequest);
                        break;
                    case OFFSET_ILLEGAL:
                        log.warn("the pull request offset illegal, {} {}",
                            pullRequest.toString(), pullResult.toString());
                        pullRequest.setNextOffset(pullResult.getNextBeginOffset());

                        pullRequest.getProcessQueue().setDropped(true);
                        DefaultMQPushConsumerImpl.this.executeTaskLater(new Runnable() {

                            @Override
                            public void run() {
                                try {
                                    DefaultMQPushConsumerImpl.this.offsetStore.updateOffset(pullRequest.getMessageQueue(),
                                        pullRequest.getNextOffset(), false);

                                    DefaultMQPushConsumerImpl.this.offsetStore.persist(pullRequest.getMessageQueue());

                                    DefaultMQPushConsumerImpl.this.rebalanceImpl.removeProcessQueue(pullRequest.getMessageQueue());

                                    log.warn("fix the pull request offset, {}", pullRequest);
                                } catch (Throwable e) {
                                    log.error("executeTaskLater Exception", e);
                                }
                            }
                        }, 10000);
                        break;
                    default:
                        break;
                }
            }
        }

        @Override
        public void onException(Throwable e) {
            if (!pullRequest.getMessageQueue().getTopic().startsWith(MixAll.RETRY_GROUP_TOPIC_PREFIX)) {
                log.warn("execute the pull request exception", e);
            }

            DefaultMQPushConsumerImpl.this.executePullRequestLater(pullRequest, pullTimeDelayMillsWhenException);
        }
    };

    boolean commitOffsetEnable = false;
    long commitOffsetValue = 0L;
    if (MessageModel.CLUSTERING == this.defaultMQPushConsumer.getMessageModel()) {
        commitOffsetValue = this.offsetStore.readOffset(pullRequest.getMessageQueue(), ReadOffsetType.READ_FROM_MEMORY);
        if (commitOffsetValue > 0) {
            commitOffsetEnable = true;
        }
    }

    String subExpression = null;
    boolean classFilter = false;
    SubscriptionData sd = this.rebalanceImpl.getSubscriptionInner().get(pullRequest.getMessageQueue().getTopic());
    if (sd != null) {
        if (this.defaultMQPushConsumer.isPostSubscriptionWhenPull() && !sd.isClassFilterMode()) {
            subExpression = sd.getSubString();
        }

        classFilter = sd.isClassFilterMode();
    }

    int sysFlag = PullSysFlag.buildSysFlag(
        commitOffsetEnable, // commitOffset
        true, // suspend
        subExpression != null, // subscription
        classFilter // class filter
    );
    try {
        this.pullAPIWrapper.pullKernelImpl(
            pullRequest.getMessageQueue(),
            subExpression,
            subscriptionData.getExpressionType(),
            subscriptionData.getSubVersion(),
            pullRequest.getNextOffset(),
            this.defaultMQPushConsumer.getPullBatchSize(),
            sysFlag,
            commitOffsetValue,
            BROKER_SUSPEND_MAX_TIME_MILLIS,
            CONSUMER_TIMEOUT_MILLIS_WHEN_SUSPEND,
            CommunicationMode.ASYNC,
            pullCallback
        );
    } catch (Exception e) {
        log.error("pullKernelImpl exception", e);
        this.executePullRequestLater(pullRequest, pullTimeDelayMillsWhenException);
    }
}
```

### PullMessageService pullMessage主要部分：
#### 第一部分
##### 判断是否需要延迟发送Pull消息，如果需要则延迟执行

1. 如果堆积未处理的消息过多，则扔回PullMessageService,延时执行（默认50ms）

2. 如果堆积消息的size过大，则扔回PullMessageService,延时执行（默认50ms）

3. 无序消息，则扔回PullMessageService,延时执行（默认50ms）

#### 第二部分

##### 检查订阅关系有没有变化（有可能在延时期间，topic或者consumer的配置都发生了变化）

#### 第三部分

##### 发送请求并通过PullCallback处理返回逻辑，如果正常返回则直接往PullMessageService的pullRequestQueue再扔一个RequestQueue，等于说再次发起下次请求，类似于长轮询（long poll）

#### 第四部分

##### 将请求返回的Mesage提交到ConsumeMessageService由ConsumeMessageService异步回调给Consumer注册的MessageListener

## ConsumeMessageService 消息回调（Concurrently）

上文当PullCallback回调时，如果存在消息则将消息提交给consumeMessageService

```java
ConsumeMessageConcurrentlyService.class
    
public void submitConsumeRequest(
    final List<MessageExt> msgs,
    final ProcessQueue processQueue,
    final MessageQueue messageQueue,
    final boolean dispatchToConsume) {
    final int consumeBatchSize = this.defaultMQPushConsumer.getConsumeMessageBatchMaxSize();
    if (msgs.size() <= consumeBatchSize) {
        //如果消息数量小于设置的批量消费数量 则直接构建ConsumeRequest并且异步执行回调监听器 如果线程池慢了则稍后再次提交
        ConsumeRequest consumeRequest = new ConsumeRequest(msgs, processQueue, messageQueue);
        try {
            this.consumeExecutor.submit(consumeRequest);
        } catch (RejectedExecutionException e) {
            this.submitConsumeRequestLater(consumeRequest);
        }
    } else {
        //如果消息数量大于设置的批量消费数量 则分批次构建ConsumeRequest并且异步执行回调监听器 如果线程池慢了则稍后再次提交
        for (int total = 0; total < msgs.size(); ) {
            List<MessageExt> msgThis = new ArrayList<MessageExt>(consumeBatchSize);
            for (int i = 0; i < consumeBatchSize; i++, total++) {
                if (total < msgs.size()) {
                    msgThis.add(msgs.get(total));
                } else {
                    break;
                }
            }

            ConsumeRequest consumeRequest = new ConsumeRequest(msgThis, processQueue, messageQueue);
            try {
                this.consumeExecutor.submit(consumeRequest);
            } catch (RejectedExecutionException e) {
                for (; total < msgs.size(); total++) {
                    msgThis.add(msgs.get(total));
                }

                this.submitConsumeRequestLater(consumeRequest);
            }
        }
    }
}
```

```java
ConsumeRequest.class
    
public void run() {
    if (this.processQueue.isDropped()) {
        log.info("the message queue not be able to consume, because it's dropped. group={} {}", ConsumeMessageConcurrentlyService.this.consumerGroup, this.messageQueue);
        return;
    }

    MessageListenerConcurrently listener = ConsumeMessageConcurrentlyService.this.messageListener;
    ConsumeConcurrentlyContext context = new ConsumeConcurrentlyContext(messageQueue);
    ConsumeConcurrentlyStatus status = null;
    defaultMQPushConsumerImpl.resetRetryAndNamespace(msgs, defaultMQPushConsumer.getConsumerGroup());

    ConsumeMessageContext consumeMessageContext = null;
    if (ConsumeMessageConcurrentlyService.this.defaultMQPushConsumerImpl.hasHook()) {
        consumeMessageContext = new ConsumeMessageContext();
        consumeMessageContext.setNamespace(defaultMQPushConsumer.getNamespace());
        consumeMessageContext.setConsumerGroup(defaultMQPushConsumer.getConsumerGroup());
        consumeMessageContext.setProps(new HashMap<String, String>());
        consumeMessageContext.setMq(messageQueue);
        consumeMessageContext.setMsgList(msgs);
        consumeMessageContext.setSuccess(false);
        ConsumeMessageConcurrentlyService.this.defaultMQPushConsumerImpl.executeHookBefore(consumeMessageContext);
    }

    long beginTimestamp = System.currentTimeMillis();
    boolean hasException = false;
    ConsumeReturnType returnType = ConsumeReturnType.SUCCESS;
    try {
        if (msgs != null && !msgs.isEmpty()) {
            for (MessageExt msg : msgs) {
                MessageAccessor.setConsumeStartTimeStamp(msg, String.valueOf(System.currentTimeMillis()));
            }
        }
        status = listener.consumeMessage(Collections.unmodifiableList(msgs), context);
    } catch (Throwable e) {
        log.warn("consumeMessage exception: {} Group: {} Msgs: {} MQ: {}",
            RemotingHelper.exceptionSimpleDesc(e),
            ConsumeMessageConcurrentlyService.this.consumerGroup,
            msgs,
            messageQueue);
        hasException = true;
    }
    long consumeRT = System.currentTimeMillis() - beginTimestamp;
    if (null == status) {
        if (hasException) {
            returnType = ConsumeReturnType.EXCEPTION;
        } else {
            returnType = ConsumeReturnType.RETURNNULL;
        }
    } else if (consumeRT >= defaultMQPushConsumer.getConsumeTimeout() * 60 * 1000) {
        returnType = ConsumeReturnType.TIME_OUT;
    } else if (ConsumeConcurrentlyStatus.RECONSUME_LATER == status) {
        returnType = ConsumeReturnType.FAILED;
    } else if (ConsumeConcurrentlyStatus.CONSUME_SUCCESS == status) {
        returnType = ConsumeReturnType.SUCCESS;
    }

    if (ConsumeMessageConcurrentlyService.this.defaultMQPushConsumerImpl.hasHook()) {
        consumeMessageContext.getProps().put(MixAll.CONSUME_CONTEXT_TYPE, returnType.name());
    }

    if (null == status) {
        log.warn("consumeMessage return null, Group: {} Msgs: {} MQ: {}",
            ConsumeMessageConcurrentlyService.this.consumerGroup,
            msgs,
            messageQueue);
        status = ConsumeConcurrentlyStatus.RECONSUME_LATER;
    }

    if (ConsumeMessageConcurrentlyService.this.defaultMQPushConsumerImpl.hasHook()) {
        consumeMessageContext.setStatus(status.toString());
        consumeMessageContext.setSuccess(ConsumeConcurrentlyStatus.CONSUME_SUCCESS == status);
        ConsumeMessageConcurrentlyService.this.defaultMQPushConsumerImpl.executeHookAfter(consumeMessageContext);
    }

    ConsumeMessageConcurrentlyService.this.getConsumerStatsManager()
        .incConsumeRT(ConsumeMessageConcurrentlyService.this.consumerGroup, messageQueue.getTopic(), consumeRT);

    if (!processQueue.isDropped()) {
        ConsumeMessageConcurrentlyService.this.processConsumeResult(status, context, this);
    } else {
        log.warn("processQueue is dropped without process consume result. messageQueue={}, msgs={}", messageQueue, msgs);
    }
}
```