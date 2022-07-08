---
title: Spring AOP
tags: Spring&SpringCloud
categories: Spring&SpringCloud
---



# Spring AOP Proxy

```sequence
AbstractAutoProxyCreator -> ProxyFactory: wrapIfNecessary getProxy
ProxyFactory -> AopProxyFactory: createAopProxy
AopProxyFactory -> JdkDynamicAopProxy: targetClass isInterface
AopProxyFactory -> ObjenesisCglibAopProxy: targetClass is not Interface
```

```java
DefaultAopProxyFactory.class
    
@Override
public AopProxy createAopProxy(AdvisedSupport config) throws AopConfigException {
		if (config.isOptimize() || config.isProxyTargetClass() || hasNoUserSuppliedProxyInterfaces(config)) {
			Class<?> targetClass = config.getTargetClass();
			if (targetClass == null) {
				throw new AopConfigException("TargetSource cannot determine target class: " +
						"Either an interface or a target is required for proxy creation.");
			}
			if (targetClass.isInterface() || Proxy.isProxyClass(targetClass)) {
				return new JdkDynamicAopProxy(config);
			}
			return new ObjenesisCglibAopProxy(config);
		}
		else {
			return new JdkDynamicAopProxy(config);
		}
	}
```

wrapIfNecessary调用时机：

1. AbstractAutoProxyCreator实现了什么artInstantiationAwareBeanPostProcessor，在postProcessAfterInitialization中调用wrapIfNecessary尝试构建代理
2. getEarlyBeanReference中调用wrapIfNecessary

getEarlyBeanReference：

提早暴露bean的时候，通过这个方法获取正确的对象（代理或是非代理）

