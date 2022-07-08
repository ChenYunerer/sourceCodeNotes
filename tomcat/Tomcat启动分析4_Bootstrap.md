---
title: Tomcat启动分析4_Bootstrap
tags: Tomcat
categories: Tomcat
---



## Tomcat启动分析4_Bootstrap解析

通过catalina.sh脚本可知，所有的启动、停止命令最终都是加载执行Bootstrap并传入对应start或是stop等参数，具体的处理由Bootstrap来处理。

#### Bootstrap静态初始化块

主要对catalina.home以及catalina.base系统变量进行赋值

#### Bootstrap main

1. 构建Bootstrap对象，并调用init方法进行初始化
   1. Bootstrap.init主要就是初始化ClassLoader，
   2. 实例化Catalina对象，反射调用其setParentClassLoader方法，将ClassLoader传递过去
2. 通过入参args判读操作类型：start（参数为空则默认为start）、startd、stopd、configtest，这里暂时只关注start
   1. daemon.load() : 反射调用Catalina对象的load方法并传递参数
   2. daemon.stat() : 反射调用Catalina对象的start方法

```java
Bootstrap.class
public static void main(String args[]) {

        if (daemon == null) {
            // Don't set daemon until init() has completed
          //构建Bootstrap对象
            Bootstrap bootstrap = new Bootstrap();
            try {
              //初始化：初始化ClassLoader并构建Catalina对象，反射调用其方法，传递ClassLoader对象
                bootstrap.init();
            } catch (Throwable t) {
                handleThrowable(t);
                t.printStackTrace();
                return;
            }
            daemon = bootstrap;
        } else {
            // When running as a service the call to stop will be on a new
            // thread so make sure the correct class loader is used to prevent
            // a range of class not found exceptions.
            Thread.currentThread().setContextClassLoader(daemon.catalinaLoader);
        }

        try {
          //具体处理不同命令，args为空默认为start
          //load和start等方法实际都是对于Catalina对象对应方法的反射调用，具体逻辑由Catalina来处理
            String command = "start";
            if (args.length > 0) {
                command = args[args.length - 1];
            }

            if (command.equals("startd")) {
                args[args.length - 1] = "start";
                daemon.load(args);
                daemon.start();
            } else if (command.equals("stopd")) {
                args[args.length - 1] = "stop";
                daemon.stop();
            } else if (command.equals("start")) {
                daemon.setAwait(true);
                daemon.load(args);
                daemon.start();
            } else if (command.equals("stop")) {
                daemon.stopServer(args);
            } else if (command.equals("configtest")) {
                daemon.load(args);
                if (null==daemon.getServer()) {
                    System.exit(1);
                }
                System.exit(0);
            } else {
                log.warn("Bootstrap: command \"" + command + "\" does not exist.");
            }
        } catch (Throwable t) {
            // Unwrap the Exception for clearer error reporting
            if (t instanceof InvocationTargetException &&
                    t.getCause() != null) {
                t = t.getCause();
            }
            handleThrowable(t);
            t.printStackTrace();
            System.exit(1);
        }

    }
```

#### Catalina load

```java
Catalina.class
public void load(String args[]) {

    try {
        if (arguments(args)) {
            load();
        }
    } catch (Exception e) {
        e.printStackTrace(System.out);
    }
}
```

1. arguments方法:对入参args进行解析，设置对应的参数
2. load方法:
   1. initDirs：判断java.io.tmpdir路径是否存在
   2. initNaming：不知道这个Naming有啥用
   3. 构建Digester，获取server.xml文件，通过Digester对server.xml进行具体解析，其中获取server.xml使用了2种方式：FileInputStream方式，getClass().getClassLoader().getResourceAsStream。如果server.xml不存在，则说明tomcat可能是嵌入式tomcat，则转而获取server-embed.xml

```java
Catalina.class
protected Digester createStartDigester() {
    long t1=System.currentTimeMillis();
    // Initialize the digester
    Digester digester = new Digester();
    digester.setValidating(false);
    digester.setRulesValidation(true);
    HashMap<Class<?>, List<String>> fakeAttributes = new HashMap<>();
    ArrayList<String> attrs = new ArrayList<>();
    attrs.add("className");
    fakeAttributes.put(Object.class, attrs);
    digester.setFakeAttributes(fakeAttributes);
    digester.setUseContextClassLoader(true);

    // Configure the actions we will be using
  //遇到Server标签则创建org.apache.catalina.core.StandardServer，如果Server标签存在属性className，则用该属性值替换org.apache.catalina.core.StandardServer，创建完成之后进行压栈
    digester.addObjectCreate("Server",
                             "org.apache.catalina.core.StandardServer",
                             "className");
  //遇到Server标签则对栈头部元素进行属性赋值
    digester.addSetProperties("Server");
  //遇到Server标签则对栈头部的前一个元素使用setServer(org.apache.catalina.Server)方法传递自己
  //在解析前通过digester.push(this)传入了Catalina对象，所以在解析一开始的栈头部元素就是Catalina对象
  //所以在解析完成之后，Catalina就获取了server引用
    digester.addSetNext("Server",
                        "setServer",
                        "org.apache.catalina.Server");

    digester.addObjectCreate("Server/GlobalNamingResources",
                             "org.apache.catalina.deploy.NamingResourcesImpl");
    digester.addSetProperties("Server/GlobalNamingResources");
    digester.addSetNext("Server/GlobalNamingResources",
                        "setGlobalNamingResources",
                        "org.apache.catalina.deploy.NamingResourcesImpl");
  ......
}
```

Digester解析完成后，Catalina获取到server引用，再对server

```java
Catalina.class
//为server设置catalina引用,配置CatalinaHome CatalinaBase
getServer().setCatalina(this);
getServer().setCatalinaHome(Bootstrap.getCatalinaHomeFile());
getServer().setCatalinaBase(Bootstrap.getCatalinaBaseFile());

// Stream redirection
//设置System.out System.err
initStreams();

// Start the new server
try {
  //初始化Server 初始化流程见下图
    getServer().init();
} catch (LifecycleException e) {
    if (Boolean.getBoolean("org.apache.catalina.startup.EXIT_ON_INIT_FAILURE")) {
        throw new java.lang.Error(e);
    } else {
        log.error("Catalina.start", e);
    }
}
```

```sequence
title:初始化流程
Server -> Service: init Service
Service -> Engine: init Engine
Service -> Executor: init Executor
Service -> Connector: init Connector
Connector -> ProtocolHandler: init ProtocolHandler
ProtocolHandler -> EndPoint: init EndPoint
```

#### Catalina start

```java
Catalina.class
/**
 * Start a new server instance.
 */
public void start() {
  //获取Server对象判断是否为null，如果为null再次进行初始化
    if (getServer() == null) {
        load();
    }

    if (getServer() == null) {
        log.fatal("Cannot start server. Server instance is not configured.");
        return;
    }

    long t1 = System.nanoTime();

    // Start the new server
    try {
      //调用Server start方法开始start各个组件流程 start流程见下图
        getServer().start();
    } catch (LifecycleException e) {
        log.fatal(sm.getString("catalina.serverStartFail"), e);
        try {
            getServer().destroy();
        } catch (LifecycleException e1) {
            log.debug("destroy() failed for failed Server ", e1);
        }
        return;
    }

    long t2 = System.nanoTime();
    if(log.isInfoEnabled()) {
        log.info("Server startup in " + ((t2 - t1) / 1000000) + " ms");
    }

    // Register shutdown hook
    if (useShutdownHook) {
        if (shutdownHook == null) {
            shutdownHook = new CatalinaShutdownHook();
        }
        Runtime.getRuntime().addShutdownHook(shutdownHook);

        // If JULI is being used, disable JULI's shutdown hook since
        // shutdown hooks run in parallel and log messages may be lost
        // if JULI's hook completes before the CatalinaShutdownHook()
        LogManager logManager = LogManager.getLogManager();
        if (logManager instanceof ClassLoaderLogManager) {
            ((ClassLoaderLogManager) logManager).setUseShutdownHook(
                    false);
        }
    }

    if (await) {
        await();
        stop();
    }
}
```

```sequence
title: start流程
Server -> GlobalNamingResources: globalNamingResources.start();
Server -> Service :services[i].start();
Service -> Engine : engine.start();
Service -> Executor : executor.start();
Executor -> Executor: 构建ThreadPoolExecutor
Service -> MapperListener :  mapperListener.start();
Service -> Connector : connector.start();
Connector -> ProtocolHandler : protocolHandler.start();
ProtocolHandler -> EndPoint : endpoint.start();
```

#### Tomcat对于请求的处理

```sequence
title: Endpoint
Endpoint -> Endpoint: initializeConnectionLatch
Endpoint -> Poller: start Pollers
Poller -> Poller: run(): 循环获取同步队列中的PollerEvent,并注册NIO事件，对事件进行select

Endpoint -> Acceptor: start Acceptors
Acceptor -> Acceptor: run(): 循环监听socket accept请求
Acceptor --> Poller: 接收到请求将请求封装成PollerEvent加入Poller中的Event同步队列
```

```sequence
title: Poller
Poller -> SocketProcessor:Poller\n监听到OP_READ OP_WRITE 事件后\n交由SocketProcessor处理
SocketProcessor -> ConnectionHandler: SocketProcessor\n将对象再次交给\nConnectionHandler
ConnectionHandler -> ProtocolHandler:ConnectionHandler\n构建Processor
ProtocolHandler -> Processor: create Processor
Processor -> Processor: process()\nservice()
Processor -> Adapter: getAdapter()\n.service(request, response)
Adapter -> Adapter: 构建\nrequest\nresponse
Adapter -> Pipeline: 
Pipeline -> Pipeline: invode Valve
Pipeline -> Pipeline: invode Valve
Pipeline -> Pipeline: invode Valve \n ....
Pipeline -> Pipeline: invode StandardWrapperValve \n ....

```

```sequence
title: StandardWrapperValve invoke
StandardWrapperValve -> StandardWrapperValve: servlet = wrapper.allocate(); \n 构建servlet实例
StandardWrapperValve -> StandardWrapperValve: ApplicationFilterFactory\n.createFilterChain(request, wrapper, servlet);
StandardWrapperValve -> ApplicationFilterChain:filterChain.doFilter(xxx);
ApplicationFilterChain -> Servlet: servlet.service(request, response);
Servlet -> Servlet: dispathServlet()
```

 Endpoint startInternal:

```java
NioEndpoint.class
@Override
public void startInternal() throws Exception {

    if (!running) {
        running = true;
        paused = false;

        processorCache = new SynchronizedStack<>(SynchronizedStack.DEFAULT_SIZE,
                socketProperties.getProcessorCache());
        eventCache = new SynchronizedStack<>(SynchronizedStack.DEFAULT_SIZE,
                        socketProperties.getEventCache());
        nioChannels = new SynchronizedStack<>(SynchronizedStack.DEFAULT_SIZE,
                socketProperties.getBufferPool());

        // Create worker collection
        if ( getExecutor() == null ) {
            createExecutor();
        }
      //初始化连接Latch 用于限制连接数量 默认1000
        initializeConnectionLatch();

        // Start poller threads
      //启动多个Poller
        pollers = new Poller[getPollerThreadCount()];
        for (int i=0; i<pollers.length; i++) {
            pollers[i] = new Poller();
            Thread pollerThread = new Thread(pollers[i], getName() + "-ClientPoller-"+i);
            pollerThread.setPriority(threadPriority);
            pollerThread.setDaemon(true);
            pollerThread.start();
        }
      //开启Acceptor线程用于监听请求连接
        startAcceptorThreads();
    }
}

AbstractEndpoint.class
protected final void startAcceptorThreads() {
        int count = getAcceptorThreadCount();
        acceptors = new Acceptor[count];

        for (int i = 0; i < count; i++) {
            acceptors[i] = createAcceptor();
            String threadName = getName() + "-Acceptor-" + i;
            acceptors[i].setThreadName(threadName);
          //启动Acceptor线程
            Thread t = new Thread(acceptors[i], threadName);
            t.setPriority(getAcceptorThreadPriority());
            t.setDaemon(getDaemon());
            t.start();
        }
    }
```

Acceptor线程启动后，开启循环监听socket连接，在监听前会计算连接数量，如果超过连接数量则进行等待，获取到SocketChannel之后通过setSocketOptions将SocketChannel根据是否开启SSL进行封装构建SecureNioChannel、NioChannel，在将该Channel注册到Poller中

注册过程中又将NioChannel进行包裹NioSocketWrapper进而构建PollerEvent，添加到Poller的同步队列（SynchronizedQueue<PollerEvent> events）当中去

```java
public void register(final NioChannel socket) {
    socket.setPoller(this);
    NioSocketWrapper ka = new NioSocketWrapper(socket, NioEndpoint.this);
    socket.setSocketWrapper(ka);
    ka.setPoller(this);
    ka.setReadTimeout(getSocketProperties().getSoTimeout());
    ka.setWriteTimeout(getSocketProperties().getSoTimeout());
    ka.setKeepAliveLeft(NioEndpoint.this.getMaxKeepAliveRequests());
    ka.setSecure(isSSLEnabled());
    ka.setReadTimeout(getSoTimeout());
    ka.setWriteTimeout(getSoTimeout());
    PollerEvent r = eventCache.pop();
    ka.interestOps(SelectionKey.OP_READ);//this is what OP_REGISTER turns into.
    if ( r==null) r = new PollerEvent(socket,ka,OP_REGISTER);
    else r.reset(socket,ka,OP_REGISTER);
    addEvent(r);
}
```

Poller线程启动后会循环从events队列中获取PollerEvent并调用其run方法，在该方法中进行事件注册SelectionKey.OP_READ事件，然后进行selector.selectedKeys()获取SelectionKey对SelectionKey进行逐一处理调用processKey对不同的Key进行处理：

1. processSendfile() 处理文件
2. processSocket(attachment, SocketEvent.OPEN_READ, true) 处理OP_READ
3. processSocket(attachment, SocketEvent.OPEN_WRITE, true) 处理OP_WRITE

具体的执行由SocketProcessor进行处理

```java
AbstractEndpoint.SocketProcessor.class
public boolean processSocket(SocketWrapperBase<S> socketWrapper,
        SocketEvent event, boolean dispatch) {
    try {
        if (socketWrapper == null) {
            return false;
        }
      //构建SocketProcessorBase 没有则进行创建
        SocketProcessorBase<S> sc = processorCache.pop();
        if (sc == null) {
            sc = createSocketProcessor(socketWrapper, event);
        } else {
            sc.reset(socketWrapper, event);
        }
      //通过Executor进行执行
        Executor executor = getExecutor();
        if (dispatch && executor != null) {
            executor.execute(sc);
        } else {
            sc.run();
        }
    } catch (RejectedExecutionException ree) {
        getLog().warn(sm.getString("endpoint.executor.fail", socketWrapper) , ree);
        return false;
    } catch (Throwable t) {
        ExceptionUtils.handleThrowable(t);
        // This means we got an OOM or similar creating a thread, or that
        // the pool and its queue are full
        getLog().error(sm.getString("endpoint.process.fail"), t);
        return false;
    }
    return true;
}
```

接下来代码量太多了，不贴代码了......