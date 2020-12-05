---
title: RocketMQ NameSrv
tags: RocketMQ
categories: MQ
data: 2020-10-13 23:24:26
---
# RocketMQ NameSrv

**源码基于：4.7.1**

## 大致功能说明

broker的注册中心，负责维护topic和broker的关联关系

producer可通过namer srv获取topic对应的broker并选择其中的某个进行发送消息，实现负载均衡

consumer可通过name srv获取topic对应的broker并获取数据

## 流程

1. 通过解析cmd入参以及cmd -c指定的配置文件，封装配置到NamesrvConfig NettyServerConfig对象中并构建NamesrvController
3. 调用NamesrvController initialize方法进行初始化
4. 调用NamesrvController start方法启动

### 1. CMD配置解析NamesrvConfig NettyServerConfig

```java
NamesrvStartup.class
    
public static NamesrvController createNamesrvController(String[] args) throws IOException, JoranException {
  
    //PackageConflictDetect.detectFastjson();
    //通过org.apache.commons.cli包来对cmd的args进行解析
    Options options = ServerUtil.buildCommandlineOptions(new Options());
    commandLine = ServerUtil.parseCmdLine("mqnamesrv", args, buildCommandlineOptions(options), new PosixParser());
    if (null == commandLine) {
        System.exit(-1);
        return null;
    }
    //构建namesrvConfig以及nettyServerConfig配置对象
    final NamesrvConfig namesrvConfig = new NamesrvConfig();
    final NettyServerConfig nettyServerConfig = new NettyServerConfig();
    nettyServerConfig.setListenPort(9876);
    //如果cmd指定了c也就是配置文件 则读取配置文件 将配置数据赋值给namesrvConfig以及nettyServerConfig
    if (commandLine.hasOption('c')) {
        String file = commandLine.getOptionValue('c');
        if (file != null) {
            InputStream in = new BufferedInputStream(new FileInputStream(file));
            properties = new Properties();
            properties.load(in);
            MixAll.properties2Object(properties, namesrvConfig);
            MixAll.properties2Object(properties, nettyServerConfig);

            namesrvConfig.setConfigStorePath(file);

            System.out.printf("load config properties file OK, %s%n", file);
            in.close();
        }
    }

    //如果cmd包含p命令 则将namesrvConfig配置以及nettyServerConfig配置进行打印 然后退出程序
    if (commandLine.hasOption('p')) {
        InternalLogger console = InternalLoggerFactory.getLogger(LoggerName.NAMESRV_CONSOLE_NAME);
        MixAll.printObjectProperties(console, namesrvConfig);
        MixAll.printObjectProperties(console, nettyServerConfig);
        System.exit(0);
    }

    MixAll.properties2Object(ServerUtil.commandLine2Properties(commandLine), namesrvConfig);

    if (null == namesrvConfig.getRocketmqHome()) {
        System.out.printf("Please set the %s variable in your environment to match the location of the RocketMQ installation%n", MixAll.ROCKETMQ_HOME_ENV);
        System.exit(-2);
    }

    //对日志进行设置
    LoggerContext lc = (LoggerContext) LoggerFactory.getILoggerFactory();
    JoranConfigurator configurator = new JoranConfigurator();
    configurator.setContext(lc);
    lc.reset();
    configurator.doConfigure(namesrvConfig.getRocketmqHome() + "/conf/logback_namesrv.xml");

    log = InternalLoggerFactory.getLogger(LoggerName.NAMESRV_LOGGER_NAME);

    //打印namesrvConfig nettyServerConfig配置内容
    MixAll.printObjectProperties(log, namesrvConfig);
    MixAll.printObjectProperties(log, nettyServerConfig);

    //通过namesrvConfig nettyServerConfig两个配置构建NamesrvController对象
    final NamesrvController controller = new NamesrvController(namesrvConfig, nettyServerConfig);

    // remember all configs to prevent discard
    controller.getConfiguration().registerConfig(properties);

    return controller;
}
```

#### NamesrvConfig封装的配置信息

| 字段               | 说明                                       | 默认值                               |
| ------------------ | ------------------------------------------ | ------------------------------------ |
| rocketmqHome       | RocketMQ HOME目录                          |                                      |
| kvConfigPath       | kv配置文件路径，包含顺序消息主题的配置信息 | user.home/namesrv/kvConfig.json      |
| configStorePath    | NameServer配置文件存储路径                 | user.home/namesrv/namesrv.properties |
| productEnvName     | todo 不知道啥意思                          |                                      |
| clusterTest        | 是否开启集群测试                           | false                                |
| orderMessageEnable | 是否支持顺序消息                           | false                                |



#### NettyServerConfig封装的配置信息(Netty相关配置)

| 字段                               | 说明                                                         | 默认值 |
| ---------------------------------- | ------------------------------------------------------------ | ------ |
| listenPort                         | netty 服务监听端口                                           | 8888   |
| serverWorkerThreads                | netty Worker线程数量(业务线程线程数量)                       | 8      |
| serverCallbackExecutorThreads      | netty public任务线程池个数，netty网络设计根据业务类型会创建不同线程池如处理发送消息，消息消费心跳检测等。如果业务类型（RequestCode）未注册线程池，则由public线程池执行 | 0      |
| serverSelectorThreads              | netty childGroup线程数量                                     | 3      |
| serverOnewaySemaphoreValue         | send oneway消息请求并发度                                    | 256    |
| serverAsyncSemaphoreValue          | send异步消息最大并发度                                       | 64     |
| serverChannelMaxIdleTimeSeconds    | 网络连接最大空闲时间。如果链接空闲时间超过此参数设置的值，连接将被关闭 | 120    |
| serverSocketSndBufSize             | netty网络socket发送缓存区大小                                | 65535  |
| serverSocketRcvBufSize             | netty网络socket接收缓存区大小                                | 65535  |
| serverPooledByteBufAllocatorEnable | ByteBuffer是否开启缓存                                       | true   |
| useEpollNativeSelector             | 是否启用Epoll IO模型。Linux环境建议开启                      | false  |

### 2. NamesrvController 构建以及initialize

#### 构建

```java
NamesrvController.class
    
public NamesrvController(NamesrvConfig namesrvConfig, NettyServerConfig nettyServerConfig) {
    //namesrvConfig nettyServerConfig赋值
    this.namesrvConfig = namesrvConfig;
    this.nettyServerConfig = nettyServerConfig;
    //构建KVConfigManager RouteInfoManager BrokerHousekeepingService等对象
    this.kvConfigManager = new KVConfigManager(this);
    this.routeInfoManager = new RouteInfoManager();
    this.brokerHousekeepingService = new BrokerHousekeepingService(this);
    this.configuration = new Configuration(
        log,
        this.namesrvConfig, this.nettyServerConfig
    );
    this.configuration.setStorePathFromConfig(this.namesrvConfig, "configStorePath");
}
```

KVConfigManager： 用于存储操作kvConfig.json

RouteInfoManager：用于存储Broker以及Topic的路由信息

BrokerHousekeepingService(继承于ChannelEventListener)：用于监听Broker Netty Channel的连接情况

#### initialize初始化

```java
NamesrvController.calss
    
public boolean initialize() {

    //加载KV配置文件到内存HashMap
    this.kvConfigManager.load();

    //构建NettyRemotingServer，该类主要处理Netty服务相关
    this.remotingServer = new NettyRemotingServer(this.nettyServerConfig, this.brokerHousekeepingService);

    //构建remotingExecutor供下面的这个defaultRequestProcessor异步调用使用
    this.remotingExecutor =
        Executors.newFixedThreadPool(nettyServerConfig.getServerWorkerThreads(), new ThreadFactoryImpl("RemotingExecutorThread_"));

    //注册一个defaultRequestProcessor当请求的RemotingCommand code没有对应的Processor处理时 采用该默认Processor处理
    this.registerProcessor();

    //开启定时任务定时扫描非活跃的Broker并剔除
    //设备定时进行注册 如果一段时间没有注册 超过BROKER_CHANNEL_EXPIRED_TIME(默认1000 * 60 * 2)定义的时间 则剔除并关闭连接
    this.scheduledExecutorService.scheduleAtFixedRate(new Runnable() {

        @Override
        public void run() {
            NamesrvController.this.routeInfoManager.scanNotActiveBroker();
        }
    }, 5, 10, TimeUnit.SECONDS);

    //开启任务定时打印KV配置
    this.scheduledExecutorService.scheduleAtFixedRate(new Runnable() {

        @Override
        public void run() {
            NamesrvController.this.kvConfigManager.printAllPeriodically();
        }
    }, 1, 10, TimeUnit.MINUTES);

    //如果开启了TLS 则监听几个文件的变化 然后做相应操作
    if (TlsSystemConfig.tlsMode != TlsMode.DISABLED) {
        ......
    }

    return true;
}
```

### 3. NamesrvController 启动start

```java
NamesrvController.class
    
public void start() throws Exception {
    //通过remotingServer启动Netty服务，主要关注Netty所添加的serverHandler，该handler主要用于处理客户端的请求
    this.remotingServer.start();

    if (this.fileWatchService != null) {
        this.fileWatchService.start();
    }
}
```

```java
NettyServerHandler.class
class NettyServerHandler extends SimpleChannelInboundHandler<RemotingCommand> {

        @Override
        protected void channelRead0(ChannelHandlerContext ctx, RemotingCommand msg) throws Exception {
            processMessageReceived(ctx, msg);
        }
    }
```

```java
NettyRemotingAbstract.class
public void processMessageReceived(ChannelHandlerContext ctx, RemotingCommand msg) throws Exception {
        final RemotingCommand cmd = msg;
        if (cmd != null) {
            switch (cmd.getType()) {
                case REQUEST_COMMAND:
                    //对于Request信息的处理
                    //processRequestCommand尝试从cmd的code获取对应的Pair<NettyRequestProcessor, ExecutorService>来处理，如果没有对应的则使用defaultRequestProcessor（DefaultRequestProcessor，remotingExecutor）来处理
                    processRequestCommand(ctx, cmd);
                    break;
                case RESPONSE_COMMAND:
                    //对于Resposne信息的处理
                    processResponseCommand(ctx, cmd);
                    break;
                default:
                    break;
            }
        }
    }
```

```java
DefaultRequestProcessor.class
//DefaultRequestProcessor根据request中携带的code字段来判断走哪种逻辑
public RemotingCommand processRequest(ChannelHandlerContext ctx,
    RemotingCommand request) throws RemotingCommandException {
    if (ctx != null) {
        log.debug("receive request, {} {} {}",
            request.getCode(),
            RemotingHelper.parseChannelRemoteAddr(ctx.channel()),
            request);
    }
    switch (request.getCode()) {
        case RequestCode.PUT_KV_CONFIG:
            //添加KV配置
            return this.putKVConfig(ctx, request);
        case RequestCode.GET_KV_CONFIG:
            //添获取KV配置
            return this.getKVConfig(ctx, request);
        case RequestCode.DELETE_KV_CONFIG:
            //删除KV配置
            return this.deleteKVConfig(ctx, request);
        case RequestCode.QUERY_DATA_VERSION:
            //查询数据版本
            return queryBrokerTopicConfig(ctx, request);
        case RequestCode.REGISTER_BROKER:
            //Broker注册
            Version brokerVersion = MQVersion.value2Version(request.getVersion());
            if (brokerVersion.ordinal() >= MQVersion.Version.V3_0_11.ordinal()) {
                return this.registerBrokerWithFilterServer(ctx, request);
            } else {
                return this.registerBroker(ctx, request);
            }
        case RequestCode.UNREGISTER_BROKER:
            //Broker反注册
            return this.unregisterBroker(ctx, request);
        case RequestCode.GET_ROUTEINFO_BY_TOPIC:
            //获取Topic的路由信息
            return this.getRouteInfoByTopic(ctx, request);
        ......
    }
    return null;
}
```

## Broker注册事件处理

```java
DefaultRequestProcessor.class
    
public RemotingCommand registerBrokerWithFilterServer(ChannelHandlerContext ctx, RemotingCommand request)
    throws RemotingCommandException {
    //构建返回的response
    final RemotingCommand response = RemotingCommand.createResponseCommand(RegisterBrokerResponseHeader.class);
    //构建responseHeader
    final RegisterBrokerResponseHeader responseHeader = (RegisterBrokerResponseHeader) response.readCustomHeader();
    //从rqeust中解码获取responseHeader内容
    final RegisterBrokerRequestHeader requestHeader =
        (RegisterBrokerRequestHeader) request.decodeCommandCustomHeader(RegisterBrokerRequestHeader.class);

    //进行crc校验
    if (!checksum(ctx, request, requestHeader)) {
        response.setCode(ResponseCode.SYSTEM_ERROR);
        response.setRemark("crc32 not match");
        return response;
    }

    RegisterBrokerBody registerBrokerBody = new RegisterBrokerBody();

    if (request.getBody() != null) {
        try {
            //从request中获取registerBrokerBody
            registerBrokerBody = RegisterBrokerBody.decode(request.getBody(), requestHeader.isCompressed());
        } catch (Exception e) {
            throw new RemotingCommandException("Failed to decode RegisterBrokerBody", e);
        }
    } else {
        registerBrokerBody.getTopicConfigSerializeWrapper().getDataVersion().setCounter(new AtomicLong(0));
        registerBrokerBody.getTopicConfigSerializeWrapper().getDataVersion().setTimestamp(0);
    }

    //通过RouteInfoManager进行Broker注册
    RegisterBrokerResult result = this.namesrvController.getRouteInfoManager().registerBroker(
        requestHeader.getClusterName(),
        requestHeader.getBrokerAddr(),
        requestHeader.getBrokerName(),
        requestHeader.getBrokerId(),
        requestHeader.getHaServerAddr(),
        registerBrokerBody.getTopicConfigSerializeWrapper(),
        registerBrokerBody.getFilterServerList(),
        ctx.channel());

    responseHeader.setHaServerAddr(result.getHaServerAddr());
    responseHeader.setMasterAddr(result.getMasterAddr());

    byte[] jsonValue = this.namesrvController.getKvConfigManager().getKVListByNamespace(NamesrvUtil.NAMESPACE_ORDER_TOPIC_CONFIG);
    response.setBody(jsonValue);

    response.setCode(ResponseCode.SUCCESS);
    response.setRemark(null);
    return response;
}
```
DefaultRequestProcessor registerBrokerWithFilterServer方法主要工作：

1. 从request请求数据中获取responseHeader以及registerBrokerBody
2. 通过RouteInfoManager进行具体的Broker注册


```java
RouteInfoManager.class
    
public RegisterBrokerResult registerBroker(
    final String clusterName,
    final String brokerAddr,
    final String brokerName,
    final long brokerId,
    final String haServerAddr,
    final TopicConfigSerializeWrapper topicConfigWrapper,
    final List<String> filterServerList,
    final Channel channel) {
    RegisterBrokerResult result = new RegisterBrokerResult();
    try {
        try {
            //操作加锁
            this.lock.writeLock().lockInterruptibly();
            //将broker信息加入到其所属的集群中去
            //clusterAddrTable: String集群名称<->set<String>该集群下的所有broker名称
            Set<String> brokerNames = this.clusterAddrTable.get(clusterName);
            if (null == brokerNames) {
                brokerNames = new HashSet<String>();
                this.clusterAddrTable.put(clusterName, brokerNames);
            }
            brokerNames.add(brokerName);

            boolean registerFirst = false;

            //将broker信息添加到brokerAddrTable
            //brokerAddrTable: String Broker名称<->BrokerData Broker信息
            BrokerData brokerData = this.brokerAddrTable.get(brokerName);
            if (null == brokerData) {
                registerFirst = true;
                brokerData = new BrokerData(clusterName, brokerName, new HashMap<Long, String>());
                this.brokerAddrTable.put(brokerName, brokerData);
            }
            Map<Long, String> brokerAddrsMap = brokerData.getBrokerAddrs();
            //如果发现有相同的IP和端口的Broker则删除老的数据，新增当前的Broker数据
            //Switch slave to master: first remove <1, IP:PORT> in namesrv, then add <0, IP:PORT>
            //The same IP:PORT must only have one record in brokerAddrTable
            Iterator<Entry<Long, String>> it = brokerAddrsMap.entrySet().iterator();
            while (it.hasNext()) {
                Entry<Long, String> item = it.next();
                if (null != brokerAddr && brokerAddr.equals(item.getValue()) && brokerId != item.getKey()) {
                    it.remove();
                }
            }

            String oldAddr = brokerData.getBrokerAddrs().put(brokerId, brokerAddr);
            registerFirst = registerFirst || (null == oldAddr);

            //调用createAndUpdateQueueData方法创建或是更新这个broker的topic信息
            if (null != topicConfigWrapper
                && MixAll.MASTER_ID == brokerId) {
                if (this.isBrokerTopicConfigChanged(brokerAddr, topicConfigWrapper.getDataVersion())
                    || registerFirst) {
                    ConcurrentMap<String, TopicConfig> tcTable =
                        topicConfigWrapper.getTopicConfigTable();
                    if (tcTable != null) {
                        for (Map.Entry<String, TopicConfig> entry : tcTable.entrySet()) {
                            //见下文分析
                            this.createAndUpdateQueueData(brokerName, entry.getValue());
                        }
                    }
                }
            }

            //存储broker存活信息，主要用于记录其lastUpdateTimestamp字段，会有线程不断扫描非活跃broker并进行移除
            //brokerLiveTable: String Broker地址<->BrokerLiveInfo Broker存活信息(心跳信息)
            BrokerLiveInfo prevBrokerLiveInfo = this.brokerLiveTable.put(brokerAddr,
                new BrokerLiveInfo(
                    System.currentTimeMillis(),
                    topicConfigWrapper.getDataVersion(),
                    channel,
                    haServerAddr));
            if (null == prevBrokerLiveInfo) {
                log.info("new broker registered, {} HAServer: {}", brokerAddr, haServerAddr);
            }

            //处理filterServerList
            //filterServerTable：String Broker地址<->List<String> filterServerList
            if (filterServerList != null) {
                if (filterServerList.isEmpty()) {
                    this.filterServerTable.remove(brokerAddr);
                } else {
                    this.filterServerTable.put(brokerAddr, filterServerList);
                }
            }
            //如果当前Broker是非主节点，则获取其主节点信息，将信息返回给Client
            if (MixAll.MASTER_ID != brokerId) {
                String masterAddr = brokerData.getBrokerAddrs().get(MixAll.MASTER_ID);
                if (masterAddr != null) {
                    BrokerLiveInfo brokerLiveInfo = this.brokerLiveTable.get(masterAddr);
                    if (brokerLiveInfo != null) {
                        result.setHaServerAddr(brokerLiveInfo.getHaServerAddr());
                        result.setMasterAddr(masterAddr);
                    }
                }
            }
        } finally {
            this.lock.writeLock().unlock();
        }
    } catch (Exception e) {
        log.error("registerBroker Exception", e);
    }

    return result;
}
```

```java
RouteInfoManager.class
    
private void createAndUpdateQueueData(final String brokerName, final TopicConfig topicConfig) {
    //封装QueueData
    QueueData queueData = new QueueData();
    queueData.setBrokerName(brokerName);
    queueData.setWriteQueueNums(topicConfig.getWriteQueueNums());
    queueData.setReadQueueNums(topicConfig.getReadQueueNums());
    queueData.setPerm(topicConfig.getPerm());
    queueData.setTopicSynFlag(topicConfig.getTopicSysFlag());

    //从topicQueueTable根据topic名称获取QueueData信息
    //如果原先没有，则添加到topicQueueTable中
    //如果原先存在，则删除原先数据，然后添加新QueueData(QueueDatade的equals方法被重写过)
    List<QueueData> queueDataList = this.topicQueueTable.get(topicConfig.getTopicName());
    if (null == queueDataList) {
        queueDataList = new LinkedList<QueueData>();
        queueDataList.add(queueData);
        this.topicQueueTable.put(topicConfig.getTopicName(), queueDataList);
        log.info("new topic registered, {} {}", topicConfig.getTopicName(), queueData);
    } else {
        boolean addNewOne = true;

        Iterator<QueueData> it = queueDataList.iterator();
        while (it.hasNext()) {
            QueueData qd = it.next();
            if (qd.getBrokerName().equals(brokerName)) {
                if (qd.equals(queueData)) {
                    addNewOne = false;
                } else {
                    log.info("topic changed, {} OLD: {} NEW: {}", topicConfig.getTopicName(), qd,
                        queueData);
                    it.remove();
                }
            }
        }

        if (addNewOne) {
            queueDataList.add(queueData);
        }
    }
}
```

**以上涉及到的几个重要的HashMap**

| 名称                  | key    | key说明                     | value           | value说明                                                    |
| --------------------- | ------ | --------------------------- | --------------- | ------------------------------------------------------------ |
| **clusterAddrTable**  | String | clusterName(broker集群名称) | Set<String>     | 该集群下的broker名称集合                                     |
| **brokerAddrTable**   | String | brokerName broker名称       | BrokerData      | broker信息(集群名称，broker名称，Map<brokerID, brokerAddr>)  |
| **brokerLiveTable**   | String | brokerAddr                  | BrokerLiveInfo  | broker存活信息(心跳信息)主要是维护了一个时间参数，可以用于判断改broker是否存活 |
| **filterServerTable** | String | brokerAddr                  | List<String>    | filterServerList                                             |
| **topicQueueTable**   | String | topic名称                   | List<QueueData> | 该topic所有可用的QueueData信息(brokerName等信息)             |

以上各个Map结合可以给consumer提供topic的路由信息

## Consumer Topic请求路由信息处理

```java
DefaultRequestProcessor.class
  
public RemotingCommand getRouteInfoByTopic(ChannelHandlerContext ctx,
    RemotingCommand request) throws RemotingCommandException {
  //构建返回的response
    final RemotingCommand response = RemotingCommand.createResponseCommand(null);
  //从请求中解析requestHeader
    final GetRouteInfoRequestHeader requestHeader =
        (GetRouteInfoRequestHeader) request.decodeCommandCustomHeader(GetRouteInfoRequestHeader.class);

  //通过RouteInfoManager获取Topic路由信息
    TopicRouteData topicRouteData = this.namesrvController.getRouteInfoManager().pickupTopicRouteData(requestHeader.getTopic());

  //如果开启了顺序消息 则对topicRouteData设置OrderTopicConf
    if (topicRouteData != null) {
        if (this.namesrvController.getNamesrvConfig().isOrderMessageEnable()) {
            String orderTopicConf =
                this.namesrvController.getKvConfigManager().getKVConfig(NamesrvUtil.NAMESPACE_ORDER_TOPIC_CONFIG,
                    requestHeader.getTopic());
            topicRouteData.setOrderTopicConf(orderTopicConf);
        }

        byte[] content = topicRouteData.encode();
        response.setBody(content);
        response.setCode(ResponseCode.SUCCESS);
        response.setRemark(null);
        return response;
    }

    response.setCode(ResponseCode.TOPIC_NOT_EXIST);
    response.setRemark("No topic route info in name server for the topic: " + requestHeader.getTopic()
        + FAQUrl.suggestTodo(FAQUrl.APPLY_TOPIC_URL));
    return response;
}
```

```java
RouteInfoManager.class
//该方法1.从topicQueueTable中获取对应topic的QueueData，2.从brokerAddrTable中获取BrokerData，3.从filterServerTable中获取filterServerList，将数据封装成TopicRouteData返回
public TopicRouteData pickupTopicRouteData(final String topic) {
    TopicRouteData topicRouteData = new TopicRouteData();
    boolean foundQueueData = false;
    boolean foundBrokerData = false;
    Set<String> brokerNameSet = new HashSet<String>();
    List<BrokerData> brokerDataList = new LinkedList<BrokerData>();
    topicRouteData.setBrokerDatas(brokerDataList);

    HashMap<String, List<String>> filterServerMap = new HashMap<String, List<String>>();
    topicRouteData.setFilterServerTable(filterServerMap);

    try {
        try {
            this.lock.readLock().lockInterruptibly();
            List<QueueData> queueDataList = this.topicQueueTable.get(topic);
            if (queueDataList != null) {
                topicRouteData.setQueueDatas(queueDataList);
                foundQueueData = true;

                Iterator<QueueData> it = queueDataList.iterator();
                while (it.hasNext()) {
                    QueueData qd = it.next();
                    brokerNameSet.add(qd.getBrokerName());
                }

                for (String brokerName : brokerNameSet) {
                    BrokerData brokerData = this.brokerAddrTable.get(brokerName);
                    if (null != brokerData) {
                        BrokerData brokerDataClone = new BrokerData(brokerData.getCluster(), brokerData.getBrokerName(), (HashMap<Long, String>) brokerData
                            .getBrokerAddrs().clone());
                        brokerDataList.add(brokerDataClone);
                        foundBrokerData = true;
                        for (final String brokerAddr : brokerDataClone.getBrokerAddrs().values()) {
                            List<String> filterServerList = this.filterServerTable.get(brokerAddr);
                            filterServerMap.put(brokerAddr, filterServerList);
                        }
                    }
                }
            }
        } finally {
            this.lock.readLock().unlock();
        }
    } catch (Exception e) {
        log.error("pickupTopicRouteData Exception", e);
    }

    log.debug("pickupTopicRouteData {} {}", topic, topicRouteData);

    if (foundBrokerData && foundQueueData) {
        return topicRouteData;
    }

    return null;
}
```

## 其他

### 1. topicQueueTable brokerAddrTable等数据不做持久化处理，Broker会不断发送注册事件，Name Srv通过这些事件来维护这些数据，所以在Name Srv重启的一段时间内，而Broker处于发送注册事件的间隙，则Name Srv将存在短暂的时间无法提供有效的Topic 路由信息，但是过一段时间等所有Broker都注册上来之后就能恢复正常

### 2. Namer Srv不持久化Topic路由信息，Broker会持久化其自身的Topic信息

