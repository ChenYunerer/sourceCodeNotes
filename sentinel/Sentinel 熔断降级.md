---
title: Sentinel 熔断降级
tags: Sentinel
categories: Sentinel
---



# Sentinel 熔断降级

Sentinel @SentinelResource注解通过对应的Aspect进行拦截处理

```java
SentinelResourceAspect.class
  
@Around("sentinelResourceAnnotationPointcut()")
public Object invokeResourceWithSentinel(ProceedingJoinPoint pjp) throws Throwable {
    Method originMethod = resolveMethod(pjp);

    SentinelResource annotation = originMethod.getAnnotation(SentinelResource.class);
    if (annotation == null) {
        // Should not go through here.
        throw new IllegalStateException("Wrong state for SentinelResource annotation");
    }
    String resourceName = getResourceName(annotation.value(), originMethod);
    EntryType entryType = annotation.entryType();
    int resourceType = annotation.resourceType();
    Entry entry = null;
    try {
      	//通过SphU.entry开启责任链ProcessorSlot一步一步进行处理，如果达到熔断降级条件则会抛出BlockException
        entry = SphU.entry(resourceName, resourceType, entryType, pjp.getArgs());
        Object result = pjp.proceed();
        return result;
    } catch (BlockException ex) {
      	//如果捕获到BlockException则进行熔断降级处理
        return handleBlockException(pjp, annotation, ex);
    } catch (Throwable ex) {
        Class<? extends Throwable>[] exceptionsToIgnore = annotation.exceptionsToIgnore();
        // The ignore list will be checked first.
        if (exceptionsToIgnore.length > 0 && exceptionBelongsTo(ex, exceptionsToIgnore)) {
            throw ex;
        }
        if (exceptionBelongsTo(ex, annotation.exceptionsToTrace())) {
            traceException(ex);
            return handleFallback(pjp, annotation, ex);
        }

        // No fallback function can handle the exception, so throw it out.
        throw ex;
    } finally {
        if (entry != null) {
            entry.exit(1, pjp.getArgs());
        }
    }
}
```

```java
AbstractSentinelAspectSupport.class 
//对BlockException错误进行处理
protected Object handleBlockException(ProceedingJoinPoint pjp, SentinelResource annotation, BlockException ex)
    throws Throwable {

    //Execute block handler if configured.
  	//获取熔断降级定义的回调方法
    Method blockHandlerMethod = extractBlockHandlerMethod(pjp, annotation.blockHandler(),
        annotation.blockHandlerClass());
    if (blockHandlerMethod != null) {
        Object[] originArgs = pjp.getArgs();
        // Construct args.
        Object[] args = Arrays.copyOf(originArgs, originArgs.length + 1);
        args[args.length - 1] = ex;
        try {
          	//进行方法调用
            if (isStatic(blockHandlerMethod)) {
                return blockHandlerMethod.invoke(null, args);
            }
            return blockHandlerMethod.invoke(pjp.getTarget(), args);
        } catch (InvocationTargetException e) {
            // throw the actual exception
            throw e.getTargetException();
        }
    }

    // If no block handler is present, then go to fallback.
    return handleFallback(pjp, annotation, ex);
}
```