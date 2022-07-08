---
title: RocketMQ Order Msg顺序消息
tags: RocketMQ
categories: MQ
data: 2020-10-13 23:25:28

---
# RocketMQ Order Msg 顺序消息

**源码基于：4.7.1**

## 总体说明

RocketMQ的顺序消息，需要producer和consumer配和处理：

1. producer端：producer发送消息到**同一个broker**
2. consumer端：集群消费模式下，只能由**一个consumer**来进行**单线程消费**；广播消费模式下一个consumer只能**单线程**进行消费

## Example

### Producer

```java
public static void main(String[] args) throws UnsupportedEncodingException {
        try {
            MQProducer producer = new DefaultMQProducer("please_rename_unique_group_name");
            producer.start();

            String[] tags = new String[] {"TagA", "TagB", "TagC", "TagD", "TagE"};
            for (int i = 0; i < 100; i++) {
                int orderId = i % 10;
                Message msg =
                    new Message("TopicTestjjj", tags[i % tags.length], "KEY" + i,
                        ("Hello RocketMQ " + i).getBytes(RemotingHelper.DEFAULT_CHARSET));
              	//唯一不同就是制定了MessageQueueSelector，由producer来指定messageQueue
                SendResult sendResult = producer.send(msg, new MessageQueueSelector() {
                    @Override
                    public MessageQueue select(List<MessageQueue> mqs, Message msg, Object arg) {
                        Integer id = (Integer) arg;
                        int index = id % mqs.size();
                        return mqs.get(index);
                    }
                }, orderId);

                System.out.printf("%s%n", sendResult);
            }

            producer.shutdown();
        } catch (MQClientException | RemotingException | MQBrokerException | InterruptedException e) {
            e.printStackTrace();
        }
    }
```

和普通消息唯一不同的就是producer.send方法传入了一个Selector

所以说顺序消息的MessageQueue的选择是由发送方来选择，而不是采用默认的轮询策略

```java
DefaultMQProducerImpl.class
  
private SendResult sendSelectImpl(
    Message msg,
    MessageQueueSelector selector,
    Object arg,
    final CommunicationMode communicationMode,
    final SendCallback sendCallback, final long timeout
) throws MQClientException, RemotingException, MQBrokerException, InterruptedException {
    long beginStartTime = System.currentTimeMillis();
    this.makeSureStateOK();
    Validators.checkMessage(msg, this.defaultMQProducer);
  	//获取topic对应的发布信息也就是路由信息
    TopicPublishInfo topicPublishInfo = this.tryToFindTopicPublishInfo(msg.getTopic());
    if (topicPublishInfo != null && topicPublishInfo.ok()) {
        MessageQueue mq = null;
        try {
          	//获取对应的MessageQueue信息
            List<MessageQueue> messageQueueList =
                mQClientFactory.getMQAdminImpl().parsePublishMessageQueues(topicPublishInfo.getMessageQueueList());
            Message userMessage = MessageAccessor.cloneMessage(msg);
            String userTopic = NamespaceUtil.withoutNamespace(userMessage.getTopic(), mQClientFactory.getClientConfig().getNamespace());
            userMessage.setTopic(userTopic);
						//通过selector来选择一个messageQueue来发送消息
            mq = mQClientFactory.getClientConfig().queueWithNamespace(selector.select(messageQueueList, userMessage, arg));
        } catch (Throwable e) {
            throw new MQClientException("select message queue throwed exception.", e);
        }

        long costTime = System.currentTimeMillis() - beginStartTime;
        if (timeout < costTime) {
            throw new RemotingTooMuchRequestException("sendSelectImpl call timeout");
        }
        if (mq != null) {
            return this.sendKernelImpl(msg, mq, communicationMode, sendCallback, null, timeout - costTime);
        } else {
            throw new MQClientException("select message queue return null.", null);
        }
    }

    validateNameServerSetting();
    throw new MQClientException("No route info for this topic, " + msg.getTopic(), null);
}
```

### Consumer

```java
public static void main(String[] args) throws MQClientException {
    DefaultMQPushConsumer consumer = new DefaultMQPushConsumer("please_rename_unique_group_name_3");

    consumer.setConsumeFromWhere(ConsumeFromWhere.CONSUME_FROM_FIRST_OFFSET);

    consumer.subscribe("TopicTest", "TagA || TagC || TagD");
		//唯一不同就是监听器采用MessageListenerOrderly而不是MessageListenerConcurrently
    consumer.registerMessageListener(new MessageListenerOrderly() {
        AtomicLong consumeTimes = new AtomicLong(0);

        @Override
        public ConsumeOrderlyStatus consumeMessage(List<MessageExt> msgs, ConsumeOrderlyContext context) {
            context.setAutoCommit(true);
            System.out.printf("%s Receive New Messages: %s %n", Thread.currentThread().getName(), msgs);
            this.consumeTimes.incrementAndGet();
            if ((this.consumeTimes.get() % 2) == 0) {
                return ConsumeOrderlyStatus.SUCCESS;
            } else if ((this.consumeTimes.get() % 3) == 0) {
                return ConsumeOrderlyStatus.ROLLBACK;
            } else if ((this.consumeTimes.get() % 4) == 0) {
                return ConsumeOrderlyStatus.COMMIT;
            } else if ((this.consumeTimes.get() % 5) == 0) {
                context.setSuspendCurrentQueueTimeMillis(3000);
                return ConsumeOrderlyStatus.SUSPEND_CURRENT_QUEUE_A_MOMENT;
            }

            return ConsumeOrderlyStatus.SUCCESS;
        }
    });

    consumer.start();
    System.out.printf("Consumer Started.%n");
}
```

唯一不同就是监听器采用MessageListenerOrderly而不是MessageListenerConcurrently

consumer端逻辑：

1. Consumer启动后会初始化一个RebalanceImpl做rebalance操作，从而得到当前这个consumer负责处理哪些queue的消息
2. RebalanceImpl到broker拉取制定queue的消息，然后把消息按照queueId放到对应的本地的ProcessQueue缓存中
3. ConsumeMessageService调用listener处理消息，处理成功后清除掉

顺序消息所使用的ConsumeMessageService的实现是：ConsumeMessageOrderlyService

## ConsumeMessageOrderlyService

### 锁定Broker

```java
ConsumeMessageOrderlyService.class
  
public void start() {
  	//如果是集群消费模式则每隔一定时间（默认20秒）来检测锁状态（尝试发送请求锁定broker）
    if (MessageModel.CLUSTERING.equals(ConsumeMessageOrderlyService.this.defaultMQPushConsumerImpl.messageModel())) {
        this.scheduledExecutorService.scheduleAtFixedRate(new Runnable() {
            @Override
            public void run() {
                ConsumeMessageOrderlyService.this.lockMQPeriodically();
            }
        }, 1000 * 1, ProcessQueue.REBALANCE_LOCK_INTERVAL, TimeUnit.MILLISECONDS);
    }
}
```

start方法主要就是启动一个任务每隔一定时间（默认20秒）来检测锁状态（尝试发送请求锁定broker）只有当自己锁定该broker之后，才开始消费

```java
ConsumeMessageOrderlyService.class
  
public synchronized void lockMQPeriodically() {
    if (!this.stopped) {
        this.defaultMQPushConsumerImpl.getRebalanceImpl().lockAll();
    }
}
```

```java
RebalanceImpl.class
  
public void lockAll() {
  	//获取该订阅topic的相关broker messagequeuq信息
    HashMap<String, Set<MessageQueue>> brokerMqs = this.buildProcessQueueTableByBrokerName();

    Iterator<Entry<String, Set<MessageQueue>>> it = brokerMqs.entrySet().iterator();
  	//逐个发送消息，进行“锁定”,然后更新本地processQueue的lock状态，processQueue的isLockExpired默认30秒过期
    while (it.hasNext()) {
        Entry<String, Set<MessageQueue>> entry = it.next();
        final String brokerName = entry.getKey();
        final Set<MessageQueue> mqs = entry.getValue();

        if (mqs.isEmpty())
            continue;

        FindBrokerResult findBrokerResult = this.mQClientFactory.findBrokerAddressInSubscribe(brokerName, MixAll.MASTER_ID, true);
        if (findBrokerResult != null) {
            LockBatchRequestBody requestBody = new LockBatchRequestBody();
            requestBody.setConsumerGroup(this.consumerGroup);
            requestBody.setClientId(this.mQClientFactory.getClientId());
            requestBody.setMqSet(mqs);

            try {
                Set<MessageQueue> lockOKMQSet =
                    this.mQClientFactory.getMQClientAPIImpl().lockBatchMQ(findBrokerResult.getBrokerAddr(), requestBody, 1000);
              	//更新本地状态
                for (MessageQueue mq : lockOKMQSet) {
                    ProcessQueue processQueue = this.processQueueTable.get(mq);
                    if (processQueue != null) {
                        if (!processQueue.isLocked()) {
                            log.info("the message queue locked OK, Group: {} {}", this.consumerGroup, mq);
                        }

                        processQueue.setLocked(true);
                        processQueue.setLastLockTimestamp(System.currentTimeMillis());
                    }
                }
              	//更新本地状态
                for (MessageQueue mq : mqs) {
                    if (!lockOKMQSet.contains(mq)) {
                        ProcessQueue processQueue = this.processQueueTable.get(mq);
                        if (processQueue != null) {
                            processQueue.setLocked(false);
                            log.warn("the message queue locked Failed, Group: {} {}", this.consumerGroup, mq);
                        }
                    }
                }
            } catch (Exception e) {
                log.error("lockBatchMQ exception, " + mqs, e);
            }
        }
    }
}
```

1. 获取该订阅topic的相关broker messagequeuq信息
2. 逐个发送消息，进行“锁定”,然后更新本地processQueue的lock状态，processQueue的isLockExpired默认30秒过期
3. 更新本地ProcessQueue的lock状态

### 消费

RebalanceImpl在从Broker获取到消息后，会调用ConsumeMessageOrderlyServic`的submitConsumeRequest()方法：

```java
ConsumeMessageOrderlyService.class
  
@Override
public void submitConsumeRequest(
    final List<MessageExt> msgs,
    final ProcessQueue processQueue,
    final MessageQueue messageQueue,
    final boolean dispathToConsume) {
    if (dispathToConsume) {
        ConsumeRequest consumeRequest = new ConsumeRequest(processQueue, messageQueue);
        this.consumeExecutor.submit(consumeRequest);
    }
}
```

```java
ConsumeMessageOrderlyService.class ConsumeRequest
@Override
public void run() {
    if (this.processQueue.isDropped()) {
        log.warn("run, the message queue not be able to consume, because it's dropped. {}", this.messageQueue);
        return;
    }
  	//对messageQueue加锁，避免consumer多个线程同时消费导致消息消费顺序不同
    final Object objLock = messageQueueLock.fetchLockObject(this.messageQueue);
    synchronized (objLock) {
      	//消费时如果是广播模式则直接消费，如果是集群模式则要判断ProcessQueue的lock状态以及lock是否过期，集群模式只有当自己拿到锁才进行消费
        if (MessageModel.BROADCASTING.equals(ConsumeMessageOrderlyService.this.defaultMQPushConsumerImpl.messageModel())
            || (this.processQueue.isLocked() && !this.processQueue.isLockExpired())) {
            final long beginTime = System.currentTimeMillis();
            for (boolean continueConsume = true; continueConsume; ) {
                if (this.processQueue.isDropped()) {
                    log.warn("the message queue not be able to consume, because it's dropped. {}", this.messageQueue);
                    break;
                }
              	//如果是集群消费模式却没有获取到锁，则尝试获取锁并重新消费
                if (MessageModel.CLUSTERING.equals(ConsumeMessageOrderlyService.this.defaultMQPushConsumerImpl.messageModel())
                    && !this.processQueue.isLocked()) {
                    log.warn("the message queue not locked, so consume later, {}", this.messageQueue);
                    ConsumeMessageOrderlyService.this.tryLockLaterAndReconsume(this.messageQueue, this.processQueue, 10);
                    break;
                }
								//如果是集群消费模式但是获取到的锁过期，则尝试获取锁并重新消费
                if (MessageModel.CLUSTERING.equals(ConsumeMessageOrderlyService.this.defaultMQPushConsumerImpl.messageModel())
                    && this.processQueue.isLockExpired()) {
                    log.warn("the message queue lock expired, so consume later, {}", this.messageQueue);
                    ConsumeMessageOrderlyService.this.tryLockLaterAndReconsume(this.messageQueue, this.processQueue, 10);
                    break;
                }
              	//如果本次拉取的所有msg消费时常超过了一定时间（默认60秒）则等待下次执行
                long interval = System.currentTimeMillis() - beginTime;
                if (interval > MAX_TIME_CONSUME_CONTINUOUSLY) {
                    ConsumeMessageOrderlyService.this.submitConsumeRequestLater(processQueue, messageQueue, 10);
                    break;
                }
              	//根据指定的批量回调消息数量来获取一批次消息
                final int consumeBatchSize =
                    ConsumeMessageOrderlyService.this.defaultMQPushConsumer.getConsumeMessageBatchMaxSize();

                List<MessageExt> msgs = this.processQueue.takeMessages(consumeBatchSize);
                defaultMQPushConsumerImpl.resetRetryAndNamespace(msgs, defaultMQPushConsumer.getConsumerGroup());
                if (!msgs.isEmpty()) {
                    final ConsumeOrderlyContext context = new ConsumeOrderlyContext(this.messageQueue);

                    ConsumeOrderlyStatus status = null;

                    ConsumeMessageContext consumeMessageContext = null;
                  	//hook处理
                    if (ConsumeMessageOrderlyService.this.defaultMQPushConsumerImpl.hasHook()) {
                        consumeMessageContext = new ConsumeMessageContext();
                        consumeMessageContext
                            .setConsumerGroup(ConsumeMessageOrderlyService.this.defaultMQPushConsumer.getConsumerGroup());
                        consumeMessageContext.setNamespace(defaultMQPushConsumer.getNamespace());
                        consumeMessageContext.setMq(messageQueue);
                        consumeMessageContext.setMsgList(msgs);
                        consumeMessageContext.setSuccess(false);
                        // init the consume context type
                        consumeMessageContext.setProps(new HashMap<String, String>());
                        ConsumeMessageOrderlyService.this.defaultMQPushConsumerImpl.executeHookBefore(consumeMessageContext);
                    }

                    long beginTimestamp = System.currentTimeMillis();
                    ConsumeReturnType returnType = ConsumeReturnType.SUCCESS;
                    boolean hasException = false;
                    try {
                        this.processQueue.getLockConsume().lock();
                        if (this.processQueue.isDropped()) {
                            log.warn("consumeMessage, the message queue not be able to consume, because it's dropped. {}",
                                this.messageQueue);
                            break;
                        }
                      	//调用回调方法来消费消息
                        status = messageListener.consumeMessage(Collections.unmodifiableList(msgs), context);
                    } catch (Throwable e) {
                        log.warn("consumeMessage exception: {} Group: {} Msgs: {} MQ: {}",
                            RemotingHelper.exceptionSimpleDesc(e),
                            ConsumeMessageOrderlyService.this.consumerGroup,
                            msgs,
                            messageQueue);
                        hasException = true;
                    } finally {
                        this.processQueue.getLockConsume().unlock();
                    }

                    if (null == status
                        || ConsumeOrderlyStatus.ROLLBACK == status
                        || ConsumeOrderlyStatus.SUSPEND_CURRENT_QUEUE_A_MOMENT == status) {
                        log.warn("consumeMessage Orderly return not OK, Group: {} Msgs: {} MQ: {}",
                            ConsumeMessageOrderlyService.this.consumerGroup,
                            msgs,
                            messageQueue);
                    }

                    long consumeRT = System.currentTimeMillis() - beginTimestamp;
                  	//根据不同情况设置最后的returnType（成功、回滚、报错、超时、挂起等等）
                    if (null == status) {
                        if (hasException) {
                            returnType = ConsumeReturnType.EXCEPTION;
                        } else {
                            returnType = ConsumeReturnType.RETURNNULL;
                        }
                    } else if (consumeRT >= defaultMQPushConsumer.getConsumeTimeout() * 60 * 1000) {
                        returnType = ConsumeReturnType.TIME_OUT;
                    } else if (ConsumeOrderlyStatus.SUSPEND_CURRENT_QUEUE_A_MOMENT == status) {
                        returnType = ConsumeReturnType.FAILED;
                    } else if (ConsumeOrderlyStatus.SUCCESS == status) {
                        returnType = ConsumeReturnType.SUCCESS;
                    }

                    if (ConsumeMessageOrderlyService.this.defaultMQPushConsumerImpl.hasHook()) {
                        consumeMessageContext.getProps().put(MixAll.CONSUME_CONTEXT_TYPE, returnType.name());
                    }

                    if (null == status) {
                        status = ConsumeOrderlyStatus.SUSPEND_CURRENT_QUEUE_A_MOMENT;
                    }
                  	//hook处理
                    if (ConsumeMessageOrderlyService.this.defaultMQPushConsumerImpl.hasHook()) {
                        consumeMessageContext.setStatus(status.toString());
                        consumeMessageContext
                            .setSuccess(ConsumeOrderlyStatus.SUCCESS == status || ConsumeOrderlyStatus.COMMIT == status);
                        ConsumeMessageOrderlyService.this.defaultMQPushConsumerImpl.executeHookAfter(consumeMessageContext);
                    }

                    ConsumeMessageOrderlyService.this.getConsumerStatsManager()
                        .incConsumeRT(ConsumeMessageOrderlyService.this.consumerGroup, messageQueue.getTopic(), consumeRT);
                  	//处理消费结果
                    continueConsume = ConsumeMessageOrderlyService.this.processConsumeResult(msgs, status, context, this);
                } else {
                    continueConsume = false;
                }
            }
        } else {
            if (this.processQueue.isDropped()) {
                log.warn("the message queue not be able to consume, because it's dropped. {}", this.messageQueue);
                return;
            }
          	//尝试锁定broker后再消费
            ConsumeMessageOrderlyService.this.tryLockLaterAndReconsume(this.messageQueue, this.processQueue, 100);
        }
    }
}
```

1. 对messageQueue加锁，避免consumer多个线程同时消费导致消息消费顺序不同
2. 消费时如果是广播模式则直接消费，如果是集群模式则要判断ProcessQueue的lock状态以及lock是否过期，集群模式只有当自己拿到锁才进行消费
3. 如果是集群消费模式却没有获取到锁，则尝试获取锁并重新消费
4. 如果是集群消费模式但是获取到的锁过期，则尝试获取锁并重新消费
5. 如果本次拉取的所有msg消费时常超过了一定时间（默认60秒）则等待下次执行
6. 根据指定的批量回调消息数量来获取一批次消息
7. hook处理
8. 调用listener方法消费消息
9. 处理listener消费返回值，根据不同情况设置最后的returnType（成功、回滚、报错、超时、挂起等等）
10. hook处理
11. 处理消费结果

### 消费结果处理

```java
ConsumeMessageOrderlyService.class
//处理consumer消费结果
public boolean processConsumeResult(
    final List<MessageExt> msgs,
    final ConsumeOrderlyStatus status,
    final ConsumeOrderlyContext context,
    final ConsumeRequest consumeRequest
) {
    boolean continueConsume = true;
    long commitOffset = -1L;
    if (context.isAutoCommit()) {
        switch (status) {
            case COMMIT:
            case ROLLBACK:
                log.warn("the message queue consume result is illegal, we think you want to ack these message {}",
                    consumeRequest.getMessageQueue());
            case SUCCESS:
            		//消费成功
            		//调用ProcessQueue commit
                commitOffset = consumeRequest.getProcessQueue().commit();
            		//记录consumer状态
                this.getConsumerStatsManager().incConsumeOKTPS(consumerGroup, consumeRequest.getMessageQueue().getTopic(), msgs.size());
                break;
            case SUSPEND_CURRENT_QUEUE_A_MOMENT:
            		//消费失败
            		//记录consumer状态
                this.getConsumerStatsManager().incConsumeFailedTPS(consumerGroup, consumeRequest.getMessageQueue().getTopic(), msgs.size());
            		//判断是否需要重试
                if (checkReconsumeTimes(msgs)) {
                  	//如果需要重试，则把之前取出来的msg重新放入ProcessQueue
                    consumeRequest.getProcessQueue().makeMessageToCosumeAgain(msgs);
                  	//提交到下次消费
                    this.submitConsumeRequestLater(
                        consumeRequest.getProcessQueue(),
                        consumeRequest.getMessageQueue(),
                        context.getSuspendCurrentQueueTimeMillis());
                    continueConsume = false;
                } else {
                  	//调用ProcessQueue commit
                    commitOffset = consumeRequest.getProcessQueue().commit();
                }
                break;
            default:
                break;
        }
    } else {
        switch (status) {
            case SUCCESS:
                this.getConsumerStatsManager().incConsumeOKTPS(consumerGroup, consumeRequest.getMessageQueue().getTopic(), msgs.size());
                break;
            case COMMIT:
                commitOffset = consumeRequest.getProcessQueue().commit();
                break;
            case ROLLBACK:
                consumeRequest.getProcessQueue().rollback();
                this.submitConsumeRequestLater(
                    consumeRequest.getProcessQueue(),
                    consumeRequest.getMessageQueue(),
                    context.getSuspendCurrentQueueTimeMillis());
                continueConsume = false;
                break;
            case SUSPEND_CURRENT_QUEUE_A_MOMENT:
                this.getConsumerStatsManager().incConsumeFailedTPS(consumerGroup, consumeRequest.getMessageQueue().getTopic(), msgs.size());
                if (checkReconsumeTimes(msgs)) {
                    consumeRequest.getProcessQueue().makeMessageToCosumeAgain(msgs);
                    this.submitConsumeRequestLater(
                        consumeRequest.getProcessQueue(),
                        consumeRequest.getMessageQueue(),
                        context.getSuspendCurrentQueueTimeMillis());
                    continueConsume = false;
                }
                break;
            default:
                break;
        }
    }
		//记录消费偏移量
    if (commitOffset >= 0 && !consumeRequest.getProcessQueue().isDropped()) {
        this.defaultMQPushConsumerImpl.getOffsetStore().updateOffset(consumeRequest.getMessageQueue(), commitOffset, false);
    }

    return continueConsume;
}
```

消费成功逻辑（autoCommit分支）：

ProcessQueue commit获取消费偏移量并更新到本地

消费失败逻辑：

判断是否需要重新消费

如果需要重新消费，则将之前取出来的msg重新放入ProcessQueue然后提交到下次执行重新消费

如果不需要重新消费，则调用ProcessQueue的commit方法获取消费偏移量并更新到本地

### 是否需要重试判断

```java
ConsumeMessageOrderlyService.class
  
private boolean checkReconsumeTimes(List<MessageExt> msgs) {
    boolean suspend = false;
    if (msgs != null && !msgs.isEmpty()) {
        for (MessageExt msg : msgs) {
          	//判断重试次数
            if (msg.getReconsumeTimes() >= getMaxReconsumeTimes()) {
              	//如果重试次数超过最大值
                MessageAccessor.setReconsumeTime(msg, String.valueOf(msg.getReconsumeTimes()));
              	//调用sendMessageBack发送消息给broker，broker会将该msg放入dead letter queue死信队列，不会重新“投递”
                if (!sendMessageBack(msg)) {
                  	//发送消息给broekr失败了，重试次数+1，再次消费
                    suspend = true;
                    msg.setReconsumeTimes(msg.getReconsumeTimes() + 1);
                }
            } else {
              	//如果重试次数没有超过最大值
                suspend = true;
              	//重试次数+1
                msg.setReconsumeTimes(msg.getReconsumeTimes() + 1);
            }
        }
    }
    return suspend;
}
```

1. 判断重试次数
2. 如果超过重试次数则调用sendMessageBack将msg发送给broker，broker将该msg放入dead letter queue死信队列，不会再“投递”
3. 如果sendMessageBack发送消息给broker失败，则该msg重试次数+1还会重试
4. 如果没有超过重试次数则重试次数+1

### 重试次数

DefaultMQPushConsumer maxReconsumeTimes默认-1表示最大重试是16次

但是对于顺序消息，默认的-1将会变成无限次重试，其实也能理解，如果不能将msg发送给broker从而进入死信队列，就会造成该消息的重复投递，破坏了顺序消息的顺序性，所以必须是无限次重试。

```java
ConsumeMessageOrderlyService.class
  
private int getMaxReconsumeTimes() {
    // default reconsume times: Integer.MAX_VALUE
    if (this.defaultMQPushConsumer.getMaxReconsumeTimes() == -1) {
        return Integer.MAX_VALUE;
    } else {
        return this.defaultMQPushConsumer.getMaxReconsumeTimes();
    }
}
```

