---
title: RocketMQ Producer
data: 2020-10-13 23:24:34
---
# RocketMQ Producer

**源码基于：4.7.1**

## 用例(普通消息，非事务消息)

```java
public class SyncProducer {
	public static void main(String[] args) throws Exception {
    	// 实例化消息生产者Producer
        DefaultMQProducer producer = new DefaultMQProducer("please_rename_unique_group_name");
    	// 设置NameServer的地址
    	producer.setNamesrvAddr("localhost:9876");
    	// 启动Producer实例
        producer.start();
    	for (int i = 0; i < 100; i++) {
    	    // 创建消息，并指定Topic，Tag和消息体
    	    Message msg = new Message("TopicTest" /* Topic */,
        	"TagA" /* Tag */,
        	("Hello RocketMQ " + i).getBytes(RemotingHelper.DEFAULT_CHARSET) /* Message body */
        	);
        	// 发送消息到一个Broker
            SendResult sendResult = producer.send(msg);
            // 通过sendResult返回消息是否成功送达
            System.out.printf("%s%n", sendResult);
    	}
    	// 如果不再发送消息，关闭Producer实例。
    	producer.shutdown();
    }
}
```

## DefaultMQProducer构建

1. DefaultMQProducer namespace producerGroup赋值
2. DefaultMQProducerImpl对象构建

```java
DefaultMQProducerImpl.class
    
public DefaultMQProducerImpl(final DefaultMQProducer defaultMQProducer, RPCHook rpcHook) {
    this.defaultMQProducer = defaultMQProducer;
    this.rpcHook = rpcHook;
    //构建Executor用于发送异步消息
    //Executor线程池核心大小和最大大小都为CPU核心数
    this.asyncSenderThreadPoolQueue = new LinkedBlockingQueue<Runnable>(50000);
    this.defaultAsyncSenderExecutor = new ThreadPoolExecutor(
        Runtime.getRuntime().availableProcessors(),
        Runtime.getRuntime().availableProcessors(),
        1000 * 60,
        TimeUnit.MILLISECONDS,
        this.asyncSenderThreadPoolQueue,
        new ThreadFactory() {
            private AtomicInteger threadIndex = new AtomicInteger(0);

            @Override
            public Thread newThread(Runnable r) {
                return new Thread(r, "AsyncSenderExecutor_" + this.threadIndex.incrementAndGet());
            }
        });
}
```

## DefaultMQProducer start

DefaultMQProducer start方法重要处理：

1. 调用defaultMQProducerImpl(DefaultMQProducerImpl)的start方法启动defaultMQProducerImpl
2. 如果开启消息追踪则启动traceDispatcher，消息追踪通过SendMessageHook来获取消息发送事件，然后处理

###  DefaultMQProducerImpl start

```java
DefaultMQProducerImpl.class
    
public void start(final boolean startFactory) throws MQClientException {
    switch (this.serviceState) {
        case CREATE_JUST:
            //起始状态就是JUST状态
            this.serviceState = ServiceState.START_FAILED;
            //检测配置，起始就是对ProducerGroup进行检测
            //ProducerGroup不能设置为null且不能设置为DEFAULT_PRODUCER_GROUP(DEFAULT_PRODUCER)
            this.checkConfig();

            //如果ProducerGroup不是CLIENT_INNER_PRODUCER_GROUP(CLIENT_INNER_PRODUCER)，则将其InstanceName设置成PID
            if (!this.defaultMQProducer.getProducerGroup().equals(MixAll.CLIENT_INNER_PRODUCER_GROUP)) {
                this.defaultMQProducer.changeInstanceNameToPID();
            }
            //获取MQClientInstance
            this.mQClientFactory = MQClientManager.getInstance().getOrCreateMQClientInstance(this.defaultMQProducer, rpcHook);

            //注册Producer
            //其实就是将这个对象加入到MQClientInstance的producerTable中，其他地方会在何时时间遍历这个Map获取数据，做其他操作，比如心跳等等
            boolean registerOK = mQClientFactory.registerProducer(this.defaultMQProducer.getProducerGroup(), this);
            if (!registerOK) {
                this.serviceState = ServiceState.CREATE_JUST;
                throw new MQClientException("The producer group[" + this.defaultMQProducer.getProducerGroup()
                    + "] has been created before, specify another name please." + FAQUrl.suggestTodo(FAQUrl.GROUP_NAME_DUPLICATE_URL),
                    null);
            }

            //将这个Producer的CreateTopic以及一个空路由信息保存到topicPublishInfoTable Map中
            //topicPublishInfoTable: String TopicName <-> TopicPublishInfo Topic发布信息(路由信息)
            this.topicPublishInfoTable.put(this.defaultMQProducer.getCreateTopicKey(), new TopicPublishInfo());

            if (startFactory) {
                //启动该Producer对应的这个MQClientInstance
                mQClientFactory.start();
            }

            log.info("the producer [{}] start OK. sendMessageWithVIPChannel={}", this.defaultMQProducer.getProducerGroup(),
                this.defaultMQProducer.isSendMessageWithVIPChannel());
            this.serviceState = ServiceState.RUNNING;
            break;
        case RUNNING:
        case START_FAILED:
        case SHUTDOWN_ALREADY:
            throw new MQClientException("The producer service state not OK, maybe started once, "
                + this.serviceState
                + FAQUrl.suggestTodo(FAQUrl.CLIENT_SERVICE_NOT_OK),
                null);
        default:
            break;
    }
    //向所有Broker发送心跳消息
    this.mQClientFactory.sendHeartbeatToAllBrokerWithLock();

    //定时扫描过期的request并清除、回调
    this.timer.scheduleAtFixedRate(new TimerTask() {
        @Override
        public void run() {
            try {
                RequestFutureTable.scanExpiredRequest();
            } catch (Throwable e) {
                log.error("scan RequestFutureTable exception", e);
            }
        }
    }, 1000 * 3, 1000);
}
```

总结:

1. 对ProducerGroup以及InstanceName进行设置
2. 获取或构建MQClientInstance
3. 将该对象(DefaultMQProducerImpl)加入到MQClientInstance的producerTable
4. 启动MQClientInstance
5. 向Broker发送心跳
6. 启动定时器定时清除过期Request并回调

### MQClientInstance start

```java
MQClientInstance.class
    
public void start() throws MQClientException {

        synchronized (this) {
            switch (this.serviceState) {
                case CREATE_JUST:
                    this.serviceState = ServiceState.START_FAILED;
                    // 如果name srv地址没有指定 则尝试从系统变量中设置的http服务获取name srv
                    // If not specified,looking address from name server
                    if (null == this.clientConfig.getNamesrvAddr()) {
                        this.mQClientAPIImpl.fetchNameServerAddr();
                    }
                    //启动netty服务
                    // Start request-response channel
                    this.mQClientAPIImpl.start();
                    //启动各种定时任务 
                    //1. 定时fetchNameServerAddr:定时从http服务器获取name srv地址 间隔2分钟
                    //2. 定时从name srv更新topic路由信息 默认间隔30秒
                    //3. 定时清除下线的Broker,定时向Broker发送心跳 默认间隔30秒
                    //4. 定时persistAllConsumerOffset：定时持久化Consumer的消费偏移量 默认间隔5秒
                    //5. MQClientInstance定时调整线程池 默认间隔1分钟
                    // Start various schedule tasks
                    this.startScheduledTask();
                    //启动pullMessageService 该服务用于client从broker拉取消息
                    // Start pull service
                    this.pullMessageService.start();
                    //启动rebalanceService 该服务用于client处理负载均衡
                    // Start rebalance service
                    this.rebalanceService.start();
                    //启动另一个defaultMQProducer 暂时猜测是用于推送其他系统消息所使用
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

总结：

1. 如果没有指定name srv则尝试从某个http服务(配置中心)获取name srv
2. 启动netty服务
3. 启动各种定时任务
   1. 定时fetchNameServerAddr:定时从http服务器获取name srv地址 间隔2分钟
   2. 定时从name srv更新topic路由信息 默认间隔30秒
   3. 定时清除下线的Broker,定时向Broker发送心跳 默认间隔30秒
   4. 定时persistAllConsumerOffset：定时持久化Consumer的消费偏移量 默认间隔5秒
   5. MQClientInstance定时调整线程池 默认间隔1分钟
4. 启动pullMessageService 启动rebalanceService 启动另一个defaultMQProducer这都与consumer相关

**重点**：

定时persistAllConsumerOffset：定时持久化Consumer的消费偏移量 默认间隔5秒，这个默认5秒持久化consumer的消费偏移量，如果broker宕机，极有可能造成消息的重复消费，所以customer一定要做好幂等

## Producer send msg

### 同步



### 异步



