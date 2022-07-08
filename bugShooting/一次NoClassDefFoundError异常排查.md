---
title: 一次NoClassDefFoundError异常排查
tags: BugShooting
categories: BugShooting
data: 2022-06-09 12:04:14
---

# 一次NoClassDefFoundError异常排查

## 问题背景



## 排查过程

接收到系统测试的反馈，第一反应是怀疑这个应用服务A有问题，导致tomcat启动卡死。并且这个卡死的表象是：运管显示Tomcat正在运行，但是Tomcat里的所有服务却处于已停止状态。

### 查看tomcat catalina日志，判断tomcat卡在哪一步

根据Tomcat 8.5.9源码，tomcat成功启动应该会打印：Server startup in xxxx ms

```java
Catalina.class
    
public void start() {

    if (getServer() == null) {
        //初始化Tomcat：逐级调用各个组件的load方法
        load();
    }

    if (getServer() == null) {
        //到此Server为null说明load失败，打印日志，结束启动流程
        log.fatal("Cannot start server. Server instance is not configured.");
        return;
    }
	//记录启动时间
    long t1 = System.nanoTime();

    // Start the new server
    try {
        //执行start流程，逐级调用各个组件的start方法
        getServer().start();
    } catch (LifecycleException e) {
        //如果启动抛错，打印日志，并尝试destory
        log.fatal(sm.getString("catalina.serverStartFail"), e);
        try {
            getServer().destroy();
        } catch (LifecycleException e1) {
            log.debug("destroy() failed for failed Server ", e1);
        }
        return;
    }
	//记录启动结束时间，并打印提示日志
    long t2 = System.nanoTime();
    if(log.isInfoEnabled()) {
        log.info("Server startup in " + ((t2 - t1) / 1000000) + " ms");
    }

    // Register shutdown hook
    //注册shutdown hook
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

然而catalina日志并没有打印该日志，再次排查日志发现deployDirectory流程中日志打印Deploying web application directory {0}和Deployment of web application directory {0} has finished in {1} ms没有成对打印，说明某个组件（ihms）启动卡死

```java
HostConfig.class
    
protected void deployDirectory(ContextName cn, File dir) {


        long startTime = 0;
        // Deploy the application in this directory
    	//Deploying web application directory {0}日志
        if( log.isInfoEnabled() ) {
            startTime = System.currentTimeMillis();
            log.info(sm.getString("hostConfig.deployDir",
                    dir.getAbsolutePath()));
        }

        Context context = null;
        File xml = new File(dir, Constants.ApplicationContextXml);
        File xmlCopy =
                new File(host.getConfigBaseFile(), cn.getBaseName() + ".xml");


        DeployedApplication deployedApp;
        boolean copyThisXml = copyXML;

        try {
            if (deployXML && xml.exists()) {
                synchronized (digesterLock) {
                    try {
                        context = (Context) digester.parse(xml);
                    } catch (Exception e) {
                        log.error(sm.getString(
                                "hostConfig.deployDescriptor.error",
                                xml), e);
                        context = new FailedContext();
                    } finally {
                        digester.reset();
                        if (context == null) {
                            context = new FailedContext();
                        }
                    }
                }

                if (copyThisXml == false && context instanceof StandardContext) {
                    // Host is using default value. Context may override it.
                    copyThisXml = ((StandardContext) context).getCopyXML();
                }

                if (copyThisXml) {
                    Files.copy(xml.toPath(), xmlCopy.toPath());
                    context.setConfigFile(xmlCopy.toURI().toURL());
                } else {
                    context.setConfigFile(xml.toURI().toURL());
                }
            } else if (!deployXML && xml.exists()) {
                // Block deployment as META-INF/context.xml may contain security
                // configuration necessary for a secure deployment.
                log.error(sm.getString("hostConfig.deployDescriptor.blocked",
                        cn.getPath(), xml, xmlCopy));
                context = new FailedContext();
            } else {
                context = (Context) Class.forName(contextClass).newInstance();
            }

            Class<?> clazz = Class.forName(host.getConfigClass());
            LifecycleListener listener =
                (LifecycleListener) clazz.newInstance();
            context.addLifecycleListener(listener);

            context.setName(cn.getName());
            context.setPath(cn.getPath());
            context.setWebappVersion(cn.getVersion());
            context.setDocBase(cn.getBaseName());
            host.addChild(context);
        } catch (Throwable t) {
            ExceptionUtils.handleThrowable(t);
            log.error(sm.getString("hostConfig.deployDir.error",
                    dir.getAbsolutePath()), t);
        } finally {
            deployedApp = new DeployedApplication(cn.getName(),
                    xml.exists() && deployXML && copyThisXml);

            // Fake re-deploy resource to detect if a WAR is added at a later
            // point
            deployedApp.redeployResources.put(dir.getAbsolutePath() + ".war",
                    Long.valueOf(0));
            deployedApp.redeployResources.put(dir.getAbsolutePath(),
                    Long.valueOf(dir.lastModified()));
            if (deployXML && xml.exists()) {
                if (copyThisXml) {
                    deployedApp.redeployResources.put(
                            xmlCopy.getAbsolutePath(),
                            Long.valueOf(xmlCopy.lastModified()));
                } else {
                    deployedApp.redeployResources.put(
                            xml.getAbsolutePath(),
                            Long.valueOf(xml.lastModified()));
                    // Fake re-deploy resource to detect if a context.xml file is
                    // added at a later point
                    deployedApp.redeployResources.put(
                            xmlCopy.getAbsolutePath(),
                            Long.valueOf(0));
                }
            } else {
                // Fake re-deploy resource to detect if a context.xml file is
                // added at a later point
                deployedApp.redeployResources.put(
                        xmlCopy.getAbsolutePath(),
                        Long.valueOf(0));
                if (!xml.exists()) {
                    deployedApp.redeployResources.put(
                            xml.getAbsolutePath(),
                            Long.valueOf(0));
                }
            }
            addWatchedResources(deployedApp, dir.getAbsolutePath(), context);
            // Add the global redeploy resources (which are never deleted) at
            // the end so they don't interfere with the deletion process
            addGlobalRedeployResources(deployedApp);
        }

        deployed.put(cn.getName(), deployedApp);
    	//Deployment of web application directory {0} has finished in {1} ms日志
        if( log.isInfoEnabled() ) {
            log.info(sm.getString("hostConfig.deployDir.finished",
                    dir.getAbsolutePath(), Long.valueOf(System.currentTimeMillis() - startTime)));
        }
    }
```

### 查看ihms日志打印

查看ihms spring启动日志发现确实日志打印中断了

### 查看线程堆栈信息

使用jstack查看线程堆栈信息提示：

```java
Found one Java-level deadlock:
=============================
"localhost-startStop-6":
  waiting to lock monitor 0x00007fb1b90cfe80 (object 0x00000007679fd8a8, a java.lang.String),
  which is held by "Thread-43"
"Thread-43":
  waiting to lock monitor 0x00007fb16400e980 (object 0x00000007679fdb28, a java.util.concurrent.ConcurrentHashMap),
  which is held by "localhost-startStop-6"

Java stack information for the threads listed above:
===================================================
"localhost-startStop-6":
	at org.springframework.cloud.context.scope.GenericScope$BeanLifecycleWrapper.getBean(GenericScope.java:388)
	- waiting to lock <0x00000007679fd8a8> (a java.lang.String)
	at org.springframework.cloud.context.scope.GenericScope.get(GenericScope.java:186)
	at org.springframework.beans.factory.support.AbstractBeanFactory.doGetBean(AbstractBeanFactory.java:353)
	at org.springframework.beans.factory.support.AbstractBeanFactory.getBean(AbstractBeanFactory.java:199)
	at org.springframework.aop.target.SimpleBeanTargetSource.getTarget(SimpleBeanTargetSource.java:35)
	at org.springframework.aop.framework.CglibAopProxy$DynamicAdvisedInterceptor.intercept(CglibAopProxy.java:672)
	at brave.sampler.Sampler$$EnhancerBySpringCGLIB$$f171fa09.isSampled(<generated>)
	at brave.http.HttpSampler$3.isSampled(HttpSampler.java:64)
	at brave.Tracer.nextContext(Tracer.java:252)
	at brave.Tracer.newRootContext(Tracer.java:212)
	at brave.Tracer.newTrace(Tracer.java:142)
	at brave.Tracer.nextSpan(Tracer.java:436)
	at brave.http.HttpClientHandler.nextSpan(HttpClientHandler.java:114)
	at brave.http.HttpClientHandler.handleSend(HttpClientHandler.java:76)
	at brave.spring.web.TracingClientHttpRequestInterceptor.intercept(TracingClientHttpRequestInterceptor.java:49)
	at org.springframework.cloud.sleuth.instrument.web.client.LazyTracingClientHttpRequestInterceptor.intercept(TraceWebClientAutoConfiguration.java:306)
	at org.springframework.http.client.InterceptingClientHttpRequest$InterceptingRequestExecution.execute(InterceptingClientHttpRequest.java:92)
	at org.springframework.http.client.InterceptingClientHttpRequest.executeInternal(InterceptingClientHttpRequest.java:76)
	at org.springframework.http.client.AbstractBufferingClientHttpRequest.executeInternal(AbstractBufferingClientHttpRequest.java:48)
	at org.springframework.http.client.AbstractClientHttpRequest.execute(AbstractClientHttpRequest.java:53)
	at org.springframework.web.client.RestTemplate.doExecute(RestTemplate.java:735)
	at org.springframework.web.client.RestTemplate.execute(RestTemplate.java:670)
	at org.springframework.web.client.RestTemplate.exchange(RestTemplate.java:608)
	at com.hikvision.seashell.security.dh.DhClient.sendRequest(DhClient.java:278)
	at com.hikvision.seashell.security.dh.DhClient.getDhCryptInfo(DhClient.java:198)
	at com.hikvision.seashell.security.dh.DhClient.getDhCryptInfo(DhClient.java:150)
	at com.hikvision.seashell.http.dh.DhRestTemplate.getDhCryptInfo(DhRestTemplate.java:465)
	at com.hikvision.seashell.http.dh.DhRestTemplate.exchange(DhRestTemplate.java:150)
	at com.hikvision.seashell.http.dh.DhRestTemplate.exchange(DhRestTemplate.java:128)
	at com.hikvision.seashell.bic.service.impl.BicServiceImpl.getServiceInfoV2(BicServiceImpl.java:137)
	at com.hikvision.seashell.bic.service.impl.BicServiceImpl.getDhExchangeInfo(BicServiceImpl.java:76)
	at com.hikvision.seashell.bic.service.impl.BicServiceImpl.getServiceInfoV2(BicServiceImpl.java:127)
	at com.hikvision.seashell.bic.service.impl.ExtendNetdomainServiceImpl.getLocalDomainServiceInfo(ExtendNetdomainServiceImpl.java:88)
	at com.hikvision.seashell.issc.service.impl.IsscServiceImpl.getTokenTimebound(IsscServiceImpl.java:271)
	at jdk.internal.reflect.NativeMethodAccessorImpl.invoke0(java.base@11.0.5/Native Method)
	at jdk.internal.reflect.NativeMethodAccessorImpl.invoke(java.base@11.0.5/NativeMethodAccessorImpl.java:62)
	at jdk.internal.reflect.DelegatingMethodAccessorImpl.invoke(java.base@11.0.5/DelegatingMethodAccessorImpl.java:43)
	at java.lang.reflect.Method.invoke(java.base@11.0.5/Method.java:566)
	at org.springframework.beans.factory.annotation.InitDestroyAnnotationBeanPostProcessor$LifecycleElement.invoke(InitDestroyAnnotationBeanPostProcessor.java:363)
	at org.springframework.beans.factory.annotation.InitDestroyAnnotationBeanPostProcessor$LifecycleMetadata.invokeInitMethods(InitDestroyAnnotationBeanPostProcessor.java:307)
	at org.springframework.beans.factory.annotation.InitDestroyAnnotationBeanPostProcessor.postProcessBeforeInitialization(InitDestroyAnnotationBeanPostProcessor.java:136)
	at org.springframework.beans.factory.support.AbstractAutowireCapableBeanFactory.applyBeanPostProcessorsBeforeInitialization(AbstractAutowireCapableBeanFactory.java:414)
	at org.springframework.beans.factory.support.AbstractAutowireCapableBeanFactory.initializeBean(AbstractAutowireCapableBeanFactory.java:1770)
	at org.springframework.beans.factory.support.AbstractAutowireCapableBeanFactory.doCreateBean(AbstractAutowireCapableBeanFactory.java:593)
	at org.springframework.beans.factory.support.AbstractAutowireCapableBeanFactory.createBean(AbstractAutowireCapableBeanFactory.java:515)
	at org.springframework.beans.factory.support.AbstractBeanFactory.lambda$doGetBean$0(AbstractBeanFactory.java:320)
	at org.springframework.beans.factory.support.AbstractBeanFactory$$Lambda$583/0x0000000840932c40.getObject(Unknown Source)
	at org.springframework.beans.factory.support.DefaultSingletonBeanRegistry.getSingleton(DefaultSingletonBeanRegistry.java:222)
	- locked <0x00000007679fdb28> (a java.util.concurrent.ConcurrentHashMap)
	at org.springframework.beans.factory.support.AbstractBeanFactory.doGetBean(AbstractBeanFactory.java:318)
	at org.springframework.beans.factory.support.AbstractBeanFactory.getBean(AbstractBeanFactory.java:199)
	at org.springframework.beans.factory.config.DependencyDescriptor.resolveCandidate(DependencyDescriptor.java:277)
	at org.springframework.beans.factory.support.DefaultListableBeanFactory.doResolveDependency(DefaultListableBeanFactory.java:1251)
	at org.springframework.beans.factory.support.DefaultListableBeanFactory.resolveDependency(DefaultListableBeanFactory.java:1171)
	at org.springframework.beans.factory.annotation.AutowiredAnnotationBeanPostProcessor$AutowiredFieldElement.inject(AutowiredAnnotationBeanPostProcessor.java:593)
	at org.springframework.beans.factory.annotation.InjectionMetadata.inject(InjectionMetadata.java:90)
	at org.springframework.beans.factory.annotation.AutowiredAnnotationBeanPostProcessor.postProcessProperties(AutowiredAnnotationBeanPostProcessor.java:374)
	at org.springframework.beans.factory.support.AbstractAutowireCapableBeanFactory.populateBean(AbstractAutowireCapableBeanFactory.java:1411)
	at org.springframework.beans.factory.support.AbstractAutowireCapableBeanFactory.doCreateBean(AbstractAutowireCapableBeanFactory.java:592)
	at org.springframework.beans.factory.support.AbstractAutowireCapableBeanFactory.createBean(AbstractAutowireCapableBeanFactory.java:515)
	at org.springframework.beans.factory.support.AbstractBeanFactory.lambda$doGetBean$0(AbstractBeanFactory.java:320)
	at org.springframework.beans.factory.support.AbstractBeanFactory$$Lambda$583/0x0000000840932c40.getObject(Unknown Source)
	at org.springframework.beans.factory.support.DefaultSingletonBeanRegistry.getSingleton(DefaultSingletonBeanRegistry.java:222)
	- locked <0x00000007679fdb28> (a java.util.concurrent.ConcurrentHashMap)
	at org.springframework.beans.factory.support.AbstractBeanFactory.doGetBean(AbstractBeanFactory.java:318)
	at org.springframework.beans.factory.support.AbstractBeanFactory.getBean(AbstractBeanFactory.java:199)
	at org.springframework.beans.factory.support.DefaultListableBeanFactory.preInstantiateSingletons(DefaultListableBeanFactory.java:845)
	at org.springframework.context.support.AbstractApplicationContext.finishBeanFactoryInitialization(AbstractApplicationContext.java:877)
	at org.springframework.context.support.AbstractApplicationContext.refresh(AbstractApplicationContext.java:549)
	- locked <0x0000000767b47838> (a java.lang.Object)
	at org.springframework.boot.web.servlet.context.ServletWebServerApplicationContext.refresh(ServletWebServerApplicationContext.java:141)
	at org.springframework.boot.SpringApplication.refresh(SpringApplication.java:744)
	at org.springframework.boot.SpringApplication.refreshContext(SpringApplication.java:391)
	at org.springframework.boot.SpringApplication.run(SpringApplication.java:312)
	at org.springframework.boot.web.servlet.support.SpringBootServletInitializer.run(SpringBootServletInitializer.java:151)
	at org.springframework.boot.web.servlet.support.SpringBootServletInitializer.createRootApplicationContext(SpringBootServletInitializer.java:131)
	at org.springframework.boot.web.servlet.support.SpringBootServletInitializer.onStartup(SpringBootServletInitializer.java:91)
	at org.springframework.web.SpringServletContainerInitializer.onStartup(SpringServletContainerInitializer.java:171)
	at org.apache.catalina.core.StandardContext.startInternal(StandardContext.java:5144)
	- locked <0x000000076004af68> (a org.apache.catalina.core.StandardContext)
	at org.apache.catalina.util.LifecycleBase.start(LifecycleBase.java:183)
	- locked <0x000000076004af68> (a org.apache.catalina.core.StandardContext)
	at org.apache.catalina.core.ContainerBase.addChildInternal(ContainerBase.java:743)
	at org.apache.catalina.core.ContainerBase.addChild(ContainerBase.java:719)
	at org.apache.catalina.core.StandardHost.addChild(StandardHost.java:705)
	at org.apache.catalina.startup.HostConfig.deployDirectory(HostConfig.java:1125)
	at org.apache.catalina.startup.HostConfig$DeployDirectory.run(HostConfig.java:1858)
	at java.util.concurrent.Executors$RunnableAdapter.call(java.base@11.0.5/Executors.java:515)
	at java.util.concurrent.FutureTask.run(java.base@11.0.5/FutureTask.java:264)
	at java.util.concurrent.ThreadPoolExecutor.runWorker(java.base@11.0.5/ThreadPoolExecutor.java:1128)
	at java.util.concurrent.ThreadPoolExecutor$Worker.run(java.base@11.0.5/ThreadPoolExecutor.java:628)
	at java.lang.Thread.run(java.base@11.0.5/Thread.java:834)
"Thread-43":
	at org.springframework.beans.factory.support.DefaultSingletonBeanRegistry.getSingleton(DefaultSingletonBeanRegistry.java:179)
	- waiting to lock <0x00000007679fdb28> (a java.util.concurrent.ConcurrentHashMap)
	at org.springframework.beans.factory.support.AbstractBeanFactory.isTypeMatch(AbstractBeanFactory.java:493)
	at org.springframework.beans.factory.support.DefaultListableBeanFactory.doGetBeanNamesForType(DefaultListableBeanFactory.java:518)
	at org.springframework.beans.factory.support.DefaultListableBeanFactory.getBeanNamesForType(DefaultListableBeanFactory.java:489)
	at org.springframework.beans.factory.BeanFactoryUtils.beanNamesForTypeIncludingAncestors(BeanFactoryUtils.java:227)
	at org.springframework.beans.factory.support.DefaultListableBeanFactory.findAutowireCandidates(DefaultListableBeanFactory.java:1415)
	at org.springframework.beans.factory.support.DefaultListableBeanFactory.doResolveDependency(DefaultListableBeanFactory.java:1214)
	at org.springframework.beans.factory.support.DefaultListableBeanFactory.resolveDependency(DefaultListableBeanFactory.java:1171)
	at org.springframework.beans.factory.support.ConstructorResolver.resolveAutowiredArgument(ConstructorResolver.java:857)
	at org.springframework.beans.factory.support.ConstructorResolver.createArgumentArray(ConstructorResolver.java:760)
	at org.springframework.beans.factory.support.ConstructorResolver.instantiateUsingFactoryMethod(ConstructorResolver.java:509)
	at org.springframework.beans.factory.support.AbstractAutowireCapableBeanFactory.instantiateUsingFactoryMethod(AbstractAutowireCapableBeanFactory.java:1321)
	at org.springframework.beans.factory.support.AbstractAutowireCapableBeanFactory.createBeanInstance(AbstractAutowireCapableBeanFactory.java:1160)
	at org.springframework.beans.factory.support.AbstractAutowireCapableBeanFactory.doCreateBean(AbstractAutowireCapableBeanFactory.java:555)
	at org.springframework.beans.factory.support.AbstractAutowireCapableBeanFactory.createBean(AbstractAutowireCapableBeanFactory.java:515)
	at org.springframework.beans.factory.support.AbstractBeanFactory.lambda$doGetBean$1(AbstractBeanFactory.java:356)
	at org.springframework.beans.factory.support.AbstractBeanFactory$$Lambda$1801/0x0000000841e7b440.getObject(Unknown Source)
	at org.springframework.cloud.context.scope.GenericScope$BeanLifecycleWrapper.getBean(GenericScope.java:389)
	- locked <0x00000007679fd8a8> (a java.lang.String)
	at org.springframework.cloud.context.scope.GenericScope.get(GenericScope.java:186)
	at org.springframework.beans.factory.support.AbstractBeanFactory.doGetBean(AbstractBeanFactory.java:353)
	at org.springframework.beans.factory.support.AbstractBeanFactory.getBean(AbstractBeanFactory.java:199)
	at org.springframework.aop.target.SimpleBeanTargetSource.getTarget(SimpleBeanTargetSource.java:35)
	at org.springframework.aop.framework.CglibAopProxy$DynamicAdvisedInterceptor.intercept(CglibAopProxy.java:672)
	at brave.sampler.Sampler$$EnhancerBySpringCGLIB$$f171fa09.isSampled(<generated>)
	at brave.http.HttpSampler$3.isSampled(HttpSampler.java:64)
	at brave.Tracer.nextContext(Tracer.java:252)
	at brave.Tracer.newRootContext(Tracer.java:212)
	at brave.Tracer.newTrace(Tracer.java:142)
	at brave.Tracer.nextSpan(Tracer.java:436)
	at brave.http.HttpClientHandler.nextSpan(HttpClientHandler.java:114)
	at brave.http.HttpClientHandler.handleSend(HttpClientHandler.java:76)
	at brave.spring.web.TracingClientHttpRequestInterceptor.intercept(TracingClientHttpRequestInterceptor.java:49)
	at org.springframework.cloud.sleuth.instrument.web.client.LazyTracingClientHttpRequestInterceptor.intercept(TraceWebClientAutoConfiguration.java:306)
	at org.springframework.http.client.InterceptingClientHttpRequest$InterceptingRequestExecution.execute(InterceptingClientHttpRequest.java:92)
	at org.springframework.http.client.InterceptingClientHttpRequest.executeInternal(InterceptingClientHttpRequest.java:76)
	at org.springframework.http.client.AbstractBufferingClientHttpRequest.executeInternal(AbstractBufferingClientHttpRequest.java:48)
	at org.springframework.http.client.AbstractClientHttpRequest.execute(AbstractClientHttpRequest.java:53)
	at org.springframework.web.client.RestTemplate.doExecute(RestTemplate.java:735)
	at org.springframework.web.client.RestTemplate.execute(RestTemplate.java:670)
	at org.springframework.web.client.RestTemplate.exchange(RestTemplate.java:608)
	at com.hikvision.seashell.bic.service.impl.BicServiceImpl.getServiceNodeDomains(BicServiceImpl.java:240)
	at com.hikvision.ihms.common.service.LegalIpService.refreshLegalIpSet(LegalIpService.java:51)
	at com.hikvision.ihms.common.config.InitConfig.lambda$init$0(InitConfig.java:105)
	at com.hikvision.ihms.common.config.InitConfig$$Lambda$1670/0x0000000841ac3040.run(Unknown Source)
	at java.lang.Thread.run(java.base@11.0.5/Thread.java:834)

Found 1 deadlock.
```

重点在于com.hikvision.ihms.common.service.LegalIpService.refreshLegalIpSet(LegalIpService.java:51)，查看ihms对应的代码：

```java
@Component
@Slf4j
public class InitConfig {

    @PostConstruct
    public void init(){
        try{
            ......
            new Thread(() -> {
                //如果启动csrfHost安全拦截，则获取合法的ip
                //refreshLegalIpSet使用resttemplate请求bic获取LegalIp
                legalIpService.refreshLegalIpSet();
            }).start();
            ......
        } catch (Exception e) {
            log.error(LogFormatter.toLog(DefaultErrorCode.ERROR.getCode(),"msg","e"),"initDataSource Connect thread is Interrupted",e);
        }
    }
}
```

## 排查结果

线程：localhost-startStop-6(spring初始化线程)初始化流程中调用DefaultSingletonBeanRegistry的getSingleton锁住了singletonObjects对象，之后调用GenericScope$BeanLifecycleWrapper的getBean尝试获取name对象锁

```java
DefaultSingletonBeanRegistry.class
//localhost-startStop-6线程第一步getSingleton获取到singletonObjects对象锁
protected Object getSingleton(String beanName, boolean allowEarlyReference) {
   Object singletonObject = this.singletonObjects.get(beanName);
   if (singletonObject == null && isSingletonCurrentlyInCreation(beanName)) {
      synchronized (this.singletonObjects) {
         singletonObject = this.earlySingletonObjects.get(beanName);
         if (singletonObject == null && allowEarlyReference) {
            ObjectFactory<?> singletonFactory = this.singletonFactories.get(beanName);
            if (singletonFactory != null) {
               singletonObject = singletonFactory.getObject();
               this.earlySingletonObjects.put(beanName, singletonObject);
               this.singletonFactories.remove(beanName);
            }
         }
      }
   }
   return singletonObject;
}

BeanLifecycleWrapper.class
//localhost-startStop-6线程第二步getBean尝试获取到name对象锁  
public Object getBean() {
   if (this.bean == null) {
      synchronized (this.name) {
         if (this.bean == null) {
            this.bean = this.objectFactory.getObject();
         }
      }
   }
   return this.bean;
}
```

线程：Thread-43(InitConfig PostConstruct中启动的线程)则恰恰相反，该线程首先调用GenericScope$BeanLifecycleWrapper的getBean尝试获取到了name对象锁，然后DefaultSingletonBeanRegistry的getSingleton尝试获取singletonObjects对象锁

```java
BeanLifecycleWrapper.class
//Thread-43线程第一步getBean获取到name对象锁  
public Object getBean() {
   if (this.bean == null) {
      synchronized (this.name) {
         if (this.bean == null) {
            this.bean = this.objectFactory.getObject();
         }
      }
   }
   return this.bean;
}

DefaultSingletonBeanRegistry.class
//Thread-43线程第二步getSingleton尝试获取singletonObjects对象锁
protected Object getSingleton(String beanName, boolean allowEarlyReference) {
   Object singletonObject = this.singletonObjects.get(beanName);
   if (singletonObject == null && isSingletonCurrentlyInCreation(beanName)) {
      synchronized (this.singletonObjects) {
         singletonObject = this.earlySingletonObjects.get(beanName);
         if (singletonObject == null && allowEarlyReference) {
            ObjectFactory<?> singletonFactory = this.singletonFactories.get(beanName);
            if (singletonFactory != null) {
               singletonObject = singletonFactory.getObject();
               this.earlySingletonObjects.put(beanName, singletonObject);
               this.singletonFactories.remove(beanName);
            }
         }
      }
   }
   return singletonObject;
}
```

## 解决办法

项目集成了SpringCloudSluth所以避免在PostConstruct中启动线程使用restTemplate访问网络，将代码块迁移到ApplicationRunner的run方法中执行或是CommandLineRunner的run方法中执行



