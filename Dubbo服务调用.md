---
title: Dubbo服务调用
data: 2020-09-19 11:21:01
---
# Dubbo服务调用

### 流程

1. ReferenceAnnotationBeanPostProcessor扫描Reference注解
2. 构建ReferenceBean
3. 通过ReferenceBean构建代理对象注入容器
4. 代理方法使用Invoker（DubboInvoker）调用服务

### 关键代码