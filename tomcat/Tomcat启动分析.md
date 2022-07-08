---
title: Tomcat启动分析
tags: Tomcat
categories: Tomcat
---



## Tomcat启动分析

---

tomcat8.5启动入口：

```java
org.apache.catalina.startup.Bootstrap
```

Bootstrap.main()方法主要处理：

1. 构建Bootstrap对象，调用其init()方法，该方法主要处理：初始化ClassLoader，构建Catalina对象，并为其设置parentClassLoader
2. 调用Bootstrap对象的load()以及start()方法



--------------------------------------------------------------------------------------------------

### Bootstrap.load()主要反射调用了Catalina对象的load方法

Catalina.load()方法主要处理:

1. 通过Digester对象来解析server.config配置文件
2. 对解析生成的StandardServer进行设置初始化init()操作

StandardServer.initInternal()方法主要处理：

1. ClassLoader处理
2. 初始化init所有service,for调用service.init

StandardService.initInternal()方法主要处理：

1. 初始化StandardEngine，调用其init方法
2. 初始化StandardThreadExecutor，调用其init方法，首次启动不存在任何executor
3. 初始化MapperListener，调用其init方法
4. 初始化所有Connector，调用其init方法

StandardEngine.initInternal()方法主要处理：

1. 获取Realm

StandardThreadExecutor.initInternal()方法主要处理:

1. nothing

MapperListener.init()方法主要处理：

1. nothing

Connector.initInternal()方法主要处理：

1. 构建CoyoteAdapter对象
2. 为ProtocolHandler设置adapter
3. 初始化ProtocolHandler，调用其init方法，ProtocolHandler接口存在多个实现，主要有Http11NioProtocol等

AbstractProtocol.init()方法主要处理：

1. 初始化endpoint，调用其init方法

   1. bind()方法构建ServerSocketChannel并且绑定Tomcat地址和端口，初始化ssl，获取Selector，启动BlockPoller线程

   

--------------------------------------------------------------------------------------------------

### Bootstrap.start()主要反射调用了Catalina对象的start方法

Catalina.start()方法主要处理:

1. 获取init构建好的StandardServer对象，如果该对象不存在则再次调用load方法进行初始化，如果存在则调用StandardServer的start方法

StandardServer.startInternal()方法主要处理：

1. 调用所有StandardService的start方法

StandardService.startInternal()方法主要处理：

1. engine.start()
   1. cluster.start()
   2. realm.start()
   3. childContainer.start()此处的container其实是StandardHost对象
      1. StandardHost.startInternal()方法往pipeline添加errorValve
      2. init并且start所有valve
2. executor.start()
3. mapperListener.start()
4. connector.start()
   1. protocolHandler.start()(AbstractProtocol.start())
      1. endpoint.start() NioEndPoint
         1. AbstractEndpoint.start()方法检测socket绑定状态，如果未绑定尝试再次bind，然后调用startInternal()
            1. NioEndpoint.startInternal()方法主要处理：创建连接池，启动poller线程，启动acceptor线程



------

### tomcat接收请求

1. acceptor线程通过ServerSocketChannel accept客户端请求
2. 如果接受到请求则调用setSocketOptions处理请求，处理过程中，封装NioChannel对象，并注册到Poller
3. poller线程进行处理时，将NioChannel封装成PollerEvent
4. endpoint通过SocketProcessor处理具体请求->protocolHandler->http11Processor->CoyoteAdapter->pipeline.first.invoke->ApplicationFilterChain

