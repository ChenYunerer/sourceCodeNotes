---
title: RocketMQ Consumer
data: 2020-10-13 23:24:49
---
# RocketMQ Consumer

**源码基于：4.7.1**

## 用例

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

**以上涉及到的几个重要的HashMap**

| 名称                                  | key          | key说明               | value                 | value说明                     |
| ------------------------------------- | ------------ | --------------------- | --------------------- | ----------------------------- |
| MQClientInstance consumerTable        | String       | ConsumerGroup         | MQConsumerInner       | Consume                       |
| MQClientInstance brokerAddrTable      | String       | brokerName broker名称 | HashMap<Long, String> | key: brokerId value: address  |
| RebalanceImpl topicSubscribeInfoTable | String       | topic                 | Set<MessageQueue>     | 该topic相关的所有MessageQueue |
| RebalanceImpl processQueueTable       | MessageQueue |                       | ProcessQueue          |                               |

## PullMessageService start

## ConsumeMessageService start