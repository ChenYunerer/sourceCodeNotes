---
title: Spring Cloud Discovery With Nacos
tags: Spring&SpringCloud
categories: Spring&SpringCloud
---



### Spring Cloud Service Registry & Discovery

#### Service Registry

##### 1. Spring Cloud Part

```java
AbstractApplicationContext.class

protected void finishRefresh() {
   // Clear context-level resource caches (such as ASM metadata from scanning).
   clearResourceCaches();

   // Initialize lifecycle processor for this context.
   initLifecycleProcessor();

   // Propagate refresh to lifecycle processor first.
   getLifecycleProcessor().onRefresh();

   // Publish the final event.
   publishEvent(new ContextRefreshedEvent(this));

   // Participate in LiveBeansView MBean, if active.
   LiveBeansView.registerApplicationContext(this);
}
```

服务注册：

容器启动之后进行容器Refresh，Refresh结束后，调用finishRefresh方法，其中getLifecycleProcessor().onRefresh();会获取DefaultLifecycleProcessor，并调用onRefresh方法，紧接着获取所有Lifecycle的实现Bean，构建LifecycleGroup并调用start方法，此处用于服务注册相关的Lifecycle对象为：WebServerStartStopLifecycle，在其start方法中，发送了ServletWebServerInitializedEvent事件，而AbstractAutoServiceRegistration正监听该事件，在接受到事件之后，调用ServiceRegistry进行具体的服务注册，ServiceRegistry的具体实现有EurekaServiceRegistry、NacosServiceRegistry等

```sequence
AbstractApplicationContext -> AbstractApplicationContext: getLifecycleProcessor()
AbstractApplicationContext -> DefaultLifecycleProcessor: onRefresh()
DefaultLifecycleProcessor -> LifecycleGroup:start()
LifecycleGroup -> WebServerStartStopLifecycle:start()
WebServerStartStopLifecycle -> AbstractAutoServiceRegistration: publishEvent \n ServletWebServerInitializedEvent
AbstractAutoServiceRegistration -> AbstractAutoServiceRegistration: listener Event
AbstractAutoServiceRegistration -> ServiceRegistry: register()
ServiceRegistry -> ServiceRegistry的具体实现:
```

服务下线：

```sequence
AbstractAutoServiceRegistration -> AbstractAutoServiceRegistration: @PreDestroy destroy()
AbstractAutoServiceRegistration -> AbstractAutoServiceRegistration: stop() deregister()
AbstractAutoServiceRegistration -> ServiceRegistry: serviceRegistry.deregister()
ServiceRegistry -> ServiceRegistry的具体实现:
```

AbstractAutoServiceRegistration对象生命周期的的@PreDestroy方法：destroy()方法中，会获取到ServiceRegistry对象，并调用其deregister方法，具体的实现由子类实现

##### 2. Nacos Part

###### register

```sequence
NacosServiceRegistry -> NacosNamingService:registerInstance()
NacosNamingService -> NacosNamingService: create BeatInfo
NacosNamingService -> BeatReactor:addBeatInfo()
NacosNamingService -> NamingProxy:registerService
NamingProxy -> NamingProxy: choose server
NamingProxy -> HttpClient: send http request for register
BeatReactor -> ScheduledExecutorService: schedule BeatTask
ScheduledExecutorService(BeatReactor) -> NamingProxy: sendBeat() or register()
```

简单来说：

1. nacos使用http协议向server注册自己
2. 同时开启定时任务，每隔一段时间（默认5秒）发送心跳

###### deregister

```sequence
NacosServiceRegistry -> NacosNamingService: deregister()
NacosNamingService -> NamingService: deregisterInstance();
NamingService -> BeatReactor: removeBeatInfo() 取消定时任务
NamingService -> NamingProxy: deregisterService()
NamingProxy -> HttpClient: send http request for deregister
```

简单来说：

1. 通过BeatReactor取消定时任务，避免任务下线后还不停的发送心跳
2. nacos使用http协议发送下线请求

#### Service Discovery

NacosDiscoveryClient实现了Spring DiscoveryClient接口

具体的寻址由NacosServiceDiscovery来处理

##### Pull

```sequence
NacosDiscoveryClient -> NacosServiceDiscovery: getInstances()
NacosServiceDiscovery -> NamingService: selectInstances()
NamingService -> HostReactor: getServiceInfo()
HostReactor -> HostReactor: try get service info from catch
HostReactor -> NamingProxy: if no catch, get service from nacos server
NamingProxy -> HostReactor: response service info
HostReactor -> HostReactor: catch service info \n catch: 1 map 2 diskcatch
HostReactor -> UpdateTask: start UpdateTask: 每隔一定时间向nacos服务请求服务信息并更新缓存
```

简单来说：

1. 从本地缓存尝试获取服务信息
2. 如果本地没有该服务信息，则发送http请求向nacos服务请求该服务信息（请求的时候会带上client的ip和udp port）
3. 对于nacos返回的服务信息进行本地缓存，缓存到内存Map以及硬盘
4. 开启定时任务UpdateTask对本地的服务信息进行定时更新：从nacos服务端获取最新的服务信息更新到本地缓存

#####  Push

1. 从pull的模式看，在http请求服务信息的时候，会带上client的ip和udp port，表示对该serverName的订阅
2. 当该服务发生变动的时候，nacos server会把服务的最新数据通过udp发送给所有的订阅者
3. UpdateTask再次执行的时候，发现服务数据已经通过push更新之后，就不会再次pull更新，但是依旧发送http请求，但不处理返回

这里有个疑问：为什么“UpdateTask再次执行的时候，发现服务数据已经通过push更新之后，就不会再次pull更新，但是依旧发送http请求”

我猜测是由于，对服务的订阅是通过UDP订阅的，订阅者下线之后nacos server并不知道，所以http的订阅只生效一次（或是一段时间，避免无效的推送数据），因此UpdateTask需要再次通过http请求去订阅，而不用再处理返回了