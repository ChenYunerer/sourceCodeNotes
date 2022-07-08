---
title: Mybatis Interceptor
tags: Mybatis
categories: Spring&SpringCloud
---

# Mybatis Interceptor

源码基于：mybatis 3.3.0-SNAPSHOT

可以被拦截的几个对象：

Executor

```java
Configuration.class
//产生执行器
public Executor newExecutor(Transaction transaction, ExecutorType executorType) {
  executorType = executorType == null ? defaultExecutorType : executorType;
  //这句再做一下保护,囧,防止粗心大意的人将defaultExecutorType设成null?
  executorType = executorType == null ? ExecutorType.SIMPLE : executorType;
  Executor executor;
  //然后就是简单的3个分支，产生3种执行器BatchExecutor/ReuseExecutor/SimpleExecutor
  if (ExecutorType.BATCH == executorType) {
    executor = new BatchExecutor(this, transaction);
  } else if (ExecutorType.REUSE == executorType) {
    executor = new ReuseExecutor(this, transaction);
  } else {
    executor = new SimpleExecutor(this, transaction);
  }
  //如果要求缓存，生成另一种CachingExecutor(默认就是有缓存),装饰者模式,所以默认都是返回CachingExecutor
  if (cacheEnabled) {
    executor = new CachingExecutor(executor);
  }
  //此处调用插件,通过插件可以改变Executor行为
  executor = (Executor) interceptorChain.pluginAll(executor);
  return executor;
}
```

StatementHandler

```java
Configuration.class
//创建语句处理器
public StatementHandler newStatementHandler(Executor executor, MappedStatement mappedStatement, Object parameterObject, RowBounds rowBounds, ResultHandler resultHandler, BoundSql boundSql) {
  //创建路由选择语句处理器
  StatementHandler statementHandler = new RoutingStatementHandler(executor, mappedStatement, parameterObject, rowBounds, resultHandler, boundSql);
  //插件在这里插入
  statementHandler = (StatementHandler) interceptorChain.pluginAll(statementHandler);
  return statementHandler;
}
```

ResultSetHandler

```java
Configuration.class
//创建结果集处理器
public ResultSetHandler newResultSetHandler(Executor executor, MappedStatement mappedStatement, RowBounds rowBounds, ParameterHandler parameterHandler,
    ResultHandler resultHandler, BoundSql boundSql) {
  //创建DefaultResultSetHandler(稍老一点的版本3.1是创建NestedResultSetHandler或者FastResultSetHandler)
  ResultSetHandler resultSetHandler = new DefaultResultSetHandler(executor, mappedStatement, parameterHandler, resultHandler, boundSql, rowBounds);
  //插件在这里插入
  resultSetHandler = (ResultSetHandler) interceptorChain.pluginAll(resultSetHandler);
  return resultSetHandler;
}
```

ParameterHandler

```java
Configuration.class
//创建参数处理器
public ParameterHandler newParameterHandler(MappedStatement mappedStatement, Object parameterObject, BoundSql boundSql) {
  //创建ParameterHandler
  ParameterHandler parameterHandler = mappedStatement.getLang().createParameterHandler(mappedStatement, parameterObject, boundSql);
  //插件在这里插入
  parameterHandler = (ParameterHandler) interceptorChain.pluginAll(parameterHandler);
  return parameterHandler;
}
```

## InterceptorChain

```java
InterceptorChain.class
  
public class InterceptorChain {

  //内部就是一个拦截器的List
  //记录所有的Interceptor
  private final List<Interceptor> interceptors = new ArrayList<Interceptor>();

  public Object pluginAll(Object target) {
    //循环调用每个Interceptor.plugin方法
    //每个Interceptor都会创建代理，这里循环调用，就会出现套娃代理
    for (Interceptor interceptor : interceptors) {
      target = interceptor.plugin(target);
    }
    return target;
  }
	.......
}
```

## Plugin

```java
public static Object wrap(Object target, Interceptor interceptor) {
  //取得签名Map
  //对Intercepts注解做处理
  Map<Class<?>, Set<Method>> signatureMap = getSignatureMap(interceptor);
  //取得要改变行为的类(ParameterHandler|ResultSetHandler|StatementHandler|Executor)
  Class<?> type = target.getClass();
  //取得接口
  Class<?>[] interfaces = getAllInterfaces(type, signatureMap);
  //产生代理
  if (interfaces.length > 0) {
    //动态代理
    return Proxy.newProxyInstance(
        type.getClassLoader(),
        interfaces,
        new Plugin(target, interceptor, signatureMap));
  }
  return target;
}

//代理处理逻辑
@Override
public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {
  try {
    //看看如何拦截
    Set<Method> methods = signatureMap.get(method.getDeclaringClass());
    //看哪些方法需要拦截
    if (methods != null && methods.contains(method)) {
      //调用Interceptor.intercept，也即插入了我们自己的逻辑
      //调用拦截器逻辑
      return interceptor.intercept(new Invocation(target, method, args));
    }
    //最后还是执行原来逻辑
    return method.invoke(target, args);
  } catch (Exception e) {
    throw ExceptionUtil.unwrapThrowable(e);
  }
}
```

