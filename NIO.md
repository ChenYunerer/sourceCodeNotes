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
#@startuml
Server -> Service: init Service
Service --> Engine: init Engine
Service --> Executor: init Executor
Service --> Connector: init Connector
Connector --> ProtocolHandler: init ProtocolHandler
ProtocolHandler --> EndPoint: init EndPoint

#@enduml
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
Service -> Engine : sengine.start();
Service -> Executor : executor.start();
Executor -> Executor: 构建ThreadPoolExecutor
Service -> MapperListener :  mapperListener.start();
Service -> Connector : connector.start();
Connector -> ProtocolHandler : protocolHandler.start();
ProtocolHandler -> EndPoint : endpoint.start();
```

