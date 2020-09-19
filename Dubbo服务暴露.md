---
title: Dubbo源码笔记
data: 2020-09-01 12:04:14
---
# Dubbo源码笔记（以dubbo协议 netty服务为例）

## 服务暴露

### 流程

1. ServiceAnnotationBeanPostProcessor扫描Service注解，并构建BeanDefinition，BeanClass为：ServiceBean
2. ServiceBean export()方法将服务进行对外暴露
3. 具体暴露逻辑由协议（Protocol）来实现
4. DubboProtocol export方法中将会通过Transporters构建启动Netty（GrizzlyServer、MinaServer）服务
5. RegistryProtocol export方法中将会降服务暴露到注册中心

### 关键代码

```java
ServiceAnnotationBeanPostProcessor.class
  
@Override
public void postProcessBeanDefinitionRegistry(BeanDefinitionRegistry registry) throws BeansException {

    Set<String> resolvedPackagesToScan = resolvePackagesToScan(packagesToScan);

    if (!CollectionUtils.isEmpty(resolvedPackagesToScan)) {
        registerServiceBeans(resolvedPackagesToScan, registry);
    } else {
        if (logger.isWarnEnabled()) {
            logger.warn("packagesToScan is empty , ServiceBean registry will be ignored!");
        }
    }

}
```

## 服务调用

### 流程

1. ReferenceAnnotationBeanPostProcessor扫描Reference注解
2. 构建ReferenceBean
3. 通过ReferenceBean构建代理对象注入容器
4. 代理方法使用Invoker（DubboInvoker）调用服务

## SPI

