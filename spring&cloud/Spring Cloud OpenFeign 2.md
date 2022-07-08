---
title: Spring Cloud OpenFeign 2
tags: Spring&SpringCloud
categories: Spring&SpringCloud
---



## Spring Cloud OpenFeign源码笔记2

Feign.target 构建FeignClient代理

```java
public <T> T target(Target<T> target) {
  return build().newInstance(target);
}
```

主要2个方法：

1. build() 构建Feign对象

```java
public Feign build() {
  SynchronousMethodHandler.Factory synchronousMethodHandlerFactory =
      new SynchronousMethodHandler.Factory(client, retryer, requestInterceptors, logger,
          logLevel, decode404, closeAfterDecode, propagationPolicy);
  ParseHandlersByName handlersByName =
      new ParseHandlersByName(contract, options, encoder, decoder, queryMapEncoder,
          errorDecoder, synchronousMethodHandlerFactory);
  return new ReflectiveFeign(handlersByName, invocationHandlerFactory, queryMapEncoder);
}
```

2. newInstance() 通过Feign对象获取代理对象

```java
@Override
  public <T> T newInstance(Target<T> target) {
    Map<String, MethodHandler> nameToHandler = targetToHandlersByName.apply(target);
    Map<Method, MethodHandler> methodToHandler = new LinkedHashMap<Method, MethodHandler>();
    List<DefaultMethodHandler> defaultMethodHandlers = new LinkedList<DefaultMethodHandler>();

    for (Method method : target.type().getMethods()) {
      if (method.getDeclaringClass() == Object.class) {
        continue;
      } else if (Util.isDefault(method)) {
        DefaultMethodHandler handler = new DefaultMethodHandler(method);
        defaultMethodHandlers.add(handler);
        methodToHandler.put(method, handler);
      } else {
        methodToHandler.put(method, nameToHandler.get(Feign.configKey(target.type(), method)));
      }
    }
    InvocationHandler handler = factory.create(target, methodToHandler);
    T proxy = (T) Proxy.newProxyInstance(target.type().getClassLoader(),
        new Class<?>[] {target.type()}, handler);

    for (DefaultMethodHandler defaultMethodHandler : defaultMethodHandlers) {
      defaultMethodHandler.bindTo(proxy);
    }
    return proxy;
  }
```

构建代理对象InvocationHandler handler = factory.create(target, methodToHandler);

```java
static final class Default implements InvocationHandlerFactory {

  @Override
  public InvocationHandler create(Target target, Map<Method, MethodHandler> dispatch) {
    return new ReflectiveFeign.FeignInvocationHandler(target, dispatch);
  }
}
```

代理方法

```java
@Override
public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {
  //对于特殊方法进行特殊处理
  if ("equals".equals(method.getName())) {
    try {
      Object otherHandler =
          args.length > 0 && args[0] != null ? Proxy.getInvocationHandler(args[0]) : null;
      return equals(otherHandler);
    } catch (IllegalArgumentException e) {
      return false;
    }
  } else if ("hashCode".equals(method.getName())) {
    return hashCode();
  } else if ("toString".equals(method.getName())) {
    return toString();
  }
//对于一般方法，通过method找到对应的MethodHandler，通过MethodHandler来具体处理
  return dispatch.get(method).invoke(args);
}
```
dispatch.get(method).invoke(args)
```java
//这里存在2种情况
//第一种：interface method没有默认实现，则需要代理进行具体的实现
@Override
public Object invoke(Object[] argv) throws Throwable {
  //封装网络请求
  RequestTemplate template = buildTemplateFromArgs.create(argv);
  //由于每个请求都需要通过Retryer判断是否继续请求，所以需要进行clone否则，每个线程的重试记录将会影响其他线程
  Retryer retryer = this.retryer.clone();
  while (true) {
    try {
      //调用具体Client处理Http请求，并通过Decoder继续decode
      return executeAndDecode(template);
    } catch (RetryableException e) {
      try {
        //循环处理重试，如果不抛错，则继续循环重试，否则抛错
        retryer.continueOrPropagate(e);
      } catch (RetryableException th) {
        Throwable cause = th.getCause();
        if (propagationPolicy == UNWRAP && cause != null) {
          throw cause;
        } else {
          throw th;
        }
      }
      if (logLevel != Logger.Level.NONE) {
        logger.logRetry(metadata.configKey(), logLevel);
      }
      continue;
    }
  }
}


//第二种，interface method存在default实现，则直接调用该方法
	@Override
  public Object invoke(Object[] argv) throws Throwable {
    if (handle == null) {
      throw new IllegalStateException(
          "Default method handler invoked before proxy has been bound.");
    }
    return handle.invokeWithArguments(argv);
  }
```

RequestTemplate封装了HTTP请求信息，通过executeAndDecode方法，处理拦截器之后，再具体调用Client的execute方法执行HTTP请求，并对返回的response做处理，如果返回对象就是Response则处理body之后直接返回，如果非Response则通过Decoder decode

以上代码还可以看到对于重试的处理

executeAndDecode：

```java
Object executeAndDecode(RequestTemplate template) throws Throwable {
  //执行所有拦截器
    Request request = targetRequest(template);

    if (logLevel != Logger.Level.NONE) {
      logger.logRequest(metadata.configKey(), logLevel, request);
    }

    Response response;
    long start = System.nanoTime();
    try {
      //将request请求信息以及配置传入，使用具体的Client进行网络请求
      response = client.execute(request, options);
    } catch (IOException e) {
      if (logLevel != Logger.Level.NONE) {
        logger.logIOException(metadata.configKey(), logLevel, e, elapsedTime(start));
      }
      throw errorExecuting(request, e);
    }
    long elapsedTime = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - start);

    boolean shouldClose = true;
    try {
      if (logLevel != Logger.Level.NONE) {
        response =
            logger.logAndRebufferResponse(metadata.configKey(), logLevel, response, elapsedTime);
      }
      if (Response.class == metadata.returnType()) {
        //如果方法的返回类型就是Response，直接对Response处理body就可以返回了
        if (response.body() == null) {
          return response;
        }
        if (response.body().length() == null ||
            response.body().length() > MAX_RESPONSE_BUFFER_SIZE) {
          shouldClose = false;
          return response;
        }
        // Ensure the response body is disconnected
        byte[] bodyData = Util.toByteArray(response.body().asInputStream());
        return response.toBuilder().body(bodyData).build();
      }
      //如果返回类型不是Response，就需要通过Decoder进行decode，对http请求状态做处理
      if (response.status() >= 200 && response.status() < 300) {
        //如果是void返回，直接不用处理了
        if (void.class == metadata.returnType()) {
          return null;
        } else {
          //Decode解码
          Object result = decode(response);
          shouldClose = closeAfterDecode;
          return result;
        }
      } else if (decode404 && response.status() == 404 && void.class != metadata.returnType()) {
        //根据配置，判断404的情况是否也需要进行decode并返回数据
        Object result = decode(response);
        shouldClose = closeAfterDecode;
        return result;
      } else {
        //其他网络状态码处理
        throw errorDecoder.decode(metadata.configKey(), response);
      }
    } catch (IOException e) {
      if (logLevel != Logger.Level.NONE) {
        logger.logIOException(metadata.configKey(), logLevel, e, elapsedTime);
      }
      throw errorReading(request, response, e);
    } finally {
      if (shouldClose) {
        ensureClosed(response.body());
      }
    }
  }
```

