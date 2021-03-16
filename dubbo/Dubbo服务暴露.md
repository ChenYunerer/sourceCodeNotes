---
title: Dubbo服务暴露
tags: Dubbo
categories: Dubbo
data: 2020-09-01 12:04:14
---
# Dubbo服务暴露（以dubbo协议 netty服务为例）

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
//Spring注解扫描，扫描Service注解
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

```java
ServiceBean.class
//ServiceBean服务暴露方法
@Override
public void export() {
    //具体暴露流程由父类处理
    super.export();
    // Publish ServiceBeanExportedEvent
    //服务暴露完毕发送事件
    publishExportEvent();
}
```

```java
ServiceConfig.class

private void doExportUrls() {
    //通过注册中心配置获取所有向注册中心暴露的URL
    List<URL> registryURLs = loadRegistries(true);
    for (ProtocolConfig protocolConfig : protocols) {
        String pathKey = URL.buildKey(getContextPath(protocolConfig).map(p -> p + "/" + path).orElse(path), group, version);
        ProviderModel providerModel = new ProviderModel(pathKey, ref, interfaceClass);
        ApplicationModel.initProviderModel(pathKey, providerModel);
        doExportUrlsFor1Protocol(protocolConfig, registryURLs);
    }
}
```

```java
ServiceConfig.class
    
private void doExportUrlsFor1Protocol(ProtocolConfig protocolConfig, List<URL> registryURLs) {
    //如果没有指定协议默认设置为dubbo
    String name = protocolConfig.getName();
    if (StringUtils.isEmpty(name)) {
        name = DUBBO;
    }
    //接下来一大块map的操作都是为了构建dubbo协议的url为服务暴露做准备
    Map<String, String> map = new HashMap<String, String>();
    map.put(SIDE_KEY, PROVIDER_SIDE);

    appendRuntimeParameters(map);
    appendParameters(map, metrics);
    appendParameters(map, application);
    appendParameters(map, module);
    // remove 'default.' prefix for configs from ProviderConfig
    // appendParameters(map, provider, Constants.DEFAULT_KEY);
    appendParameters(map, provider);
    appendParameters(map, protocolConfig);
    appendParameters(map, this);
    if (CollectionUtils.isNotEmpty(methods)) {
        for (MethodConfig method : methods) {
            appendParameters(map, method, method.getName());
            String retryKey = method.getName() + ".retry";
            if (map.containsKey(retryKey)) {
                String retryValue = map.remove(retryKey);
                if ("false".equals(retryValue)) {
                    map.put(method.getName() + ".retries", "0");
                }
            }
            List<ArgumentConfig> arguments = method.getArguments();
            if (CollectionUtils.isNotEmpty(arguments)) {
                for (ArgumentConfig argument : arguments) {
                    // convert argument type
                    if (argument.getType() != null && argument.getType().length() > 0) {
                        Method[] methods = interfaceClass.getMethods();
                        // visit all methods
                        if (methods != null && methods.length > 0) {
                            for (int i = 0; i < methods.length; i++) {
                                String methodName = methods[i].getName();
                                // target the method, and get its signature
                                if (methodName.equals(method.getName())) {
                                    Class<?>[] argtypes = methods[i].getParameterTypes();
                                    // one callback in the method
                                    if (argument.getIndex() != -1) {
                                        if (argtypes[argument.getIndex()].getName().equals(argument.getType())) {
                                            appendParameters(map, argument, method.getName() + "." + argument.getIndex());
                                        } else {
                                            throw new IllegalArgumentException("Argument config error : the index attribute and type attribute not match :index :" + argument.getIndex() + ", type:" + argument.getType());
                                        }
                                    } else {
                                        // multiple callbacks in the method
                                        for (int j = 0; j < argtypes.length; j++) {
                                            Class<?> argclazz = argtypes[j];
                                            if (argclazz.getName().equals(argument.getType())) {
                                                appendParameters(map, argument, method.getName() + "." + j);
                                                if (argument.getIndex() != -1 && argument.getIndex() != j) {
                                                    throw new IllegalArgumentException("Argument config error : the index attribute and type attribute not match :index :" + argument.getIndex() + ", type:" + argument.getType());
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    } else if (argument.getIndex() != -1) {
                        appendParameters(map, argument, method.getName() + "." + argument.getIndex());
                    } else {
                        throw new IllegalArgumentException("Argument config must set index or type attribute.eg: <dubbo:argument index='0' .../> or <dubbo:argument type=xxx .../>");
                    }

                }
            }
        } // end of methods for
    }

    if (ProtocolUtils.isGeneric(generic)) {
        map.put(GENERIC_KEY, generic);
        map.put(METHODS_KEY, ANY_VALUE);
    } else {
        String revision = Version.getVersion(interfaceClass, version);
        if (revision != null && revision.length() > 0) {
            map.put(REVISION_KEY, revision);
        }

        String[] methods = Wrapper.getWrapper(interfaceClass).getMethodNames();
        if (methods.length == 0) {
            logger.warn("No method found in service interface " + interfaceClass.getName());
            map.put(METHODS_KEY, ANY_VALUE);
        } else {
            map.put(METHODS_KEY, StringUtils.join(new HashSet<String>(Arrays.asList(methods)), ","));
        }
    }
    if (!ConfigUtils.isEmpty(token)) {
        if (ConfigUtils.isDefault(token)) {
            map.put(TOKEN_KEY, UUID.randomUUID().toString());
        } else {
            map.put(TOKEN_KEY, token);
        }
    }
    // export service
    String host = this.findConfigedHosts(protocolConfig, registryURLs, map);
    Integer port = this.findConfigedPorts(protocolConfig, name, map);
    URL url = new URL(name, host, port, getContextPath(protocolConfig).map(p -> p + "/" + path).orElse(path), map);

    if (ExtensionLoader.getExtensionLoader(ConfiguratorFactory.class)
            .hasExtension(url.getProtocol())) {
        url = ExtensionLoader.getExtensionLoader(ConfiguratorFactory.class)
                .getExtension(url.getProtocol()).getConfigurator(url).configure(url);
    }

    String scope = url.getParameter(SCOPE_KEY);
    // don't export when none is configured
    if (!SCOPE_NONE.equalsIgnoreCase(scope)) {
        //只要url中没有指定remote则进行本地jvm服务暴露，用于本地服务调用的情况，避免本地服务调用却使用远程服务调用
        // export to local if the config is not remote (export to remote only when config is remote)
        if (!SCOPE_REMOTE.equalsIgnoreCase(scope)) {
            exportLocal(url);
        }
        // export to remote if the config is not local (export to local only when config is local)
        if (!SCOPE_LOCAL.equalsIgnoreCase(scope)) {
            if (!isOnlyInJvm() && logger.isInfoEnabled()) {
                logger.info("Export dubbo service " + interfaceClass.getName() + " to url " + url);
            }
            //jvm本地服务暴露完成之后进行服务注册
            if (CollectionUtils.isNotEmpty(registryURLs)) {
                for (URL registryURL : registryURLs) {
                    //if protocol is only injvm ,not register
                    if (LOCAL_PROTOCOL.equalsIgnoreCase(url.getProtocol())) {
                        continue;
                    }
                    url = url.addParameterIfAbsent(DYNAMIC_KEY, registryURL.getParameter(DYNAMIC_KEY));
                    URL monitorUrl = loadMonitor(registryURL);
                    if (monitorUrl != null) {
                        url = url.addParameterAndEncoded(MONITOR_KEY, monitorUrl.toFullString());
                    }
                    if (logger.isInfoEnabled()) {
                        logger.info("Register dubbo service " + interfaceClass.getName() + " url " + url + " to registry " + registryURL);
                    }

                    // For providers, this is used to enable custom proxy to generate invoker
                    String proxy = url.getParameter(PROXY_KEY);
                    if (StringUtils.isNotEmpty(proxy)) {
                        registryURL = registryURL.addParameter(PROXY_KEY, proxy);
                    }
                    //服务注册url将dubbo的远程服务调用url放入了export字段
                    Invoker<?> invoker = PROXY_FACTORY.getInvoker(ref, (Class) interfaceClass, registryURL.addParameterAndEncoded(EXPORT_KEY, url.toFullString()));
                    DelegateProviderMetaDataInvoker wrapperInvoker = new DelegateProviderMetaDataInvoker(invoker, this);
                    //这里的protocl其实是ProtocolFilterWrapper包装类
                    Exporter<?> exporter = protocol.export(wrapperInvoker);
                    exporters.add(exporter);
                }
            } else {
                Invoker<?> invoker = PROXY_FACTORY.getInvoker(ref, (Class) interfaceClass, url);
                DelegateProviderMetaDataInvoker wrapperInvoker = new DelegateProviderMetaDataInvoker(invoker, this);

                Exporter<?> exporter = protocol.export(wrapperInvoker);
                exporters.add(exporter);
            }
            /**
             * @since 2.7.0
             * ServiceData Store
             */
            MetadataReportService metadataReportService = null;
            if ((metadataReportService = getMetadataReportService()) != null) {
                metadataReportService.publishProvider(url);
            }
        }
    }
    this.urls.add(url);
}
```

```java
ProtocolFilterWrapper.class
    
@Override
public <T> Exporter<T> export(Invoker<T> invoker) throws RpcException {
    //如果是registry协议则直接进行export protocol为：QosProtocolWrapper
    if (REGISTRY_PROTOCOL.equals(invoker.getUrl().getProtocol())) {
        return protocol.export(invoker);
    }
    //否则构建InvokerChain再进行export
    return protocol.export(buildInvokerChain(invoker, SERVICE_FILTER_KEY, CommonConstants.PROVIDER));
}
```

```java
QosProtocolWrapper.class

@Override
public <T> Exporter<T> export(Invoker<T> invoker) throws RpcException {
    //如果是registry协议尝试启动QosServer然后export protocol为：ProtocolListenerWrapper
    if (REGISTRY_PROTOCOL.equals(invoker.getUrl().getProtocol())) {
        startQosServer(invoker.getUrl());
        return protocol.export(invoker);
    }
    //否则直接进行export
    return protocol.export(invoker);
}
```

```java
ProtocolListenerWrapper.class
    
@Override
public <T> Exporter<T> export(Invoker<T> invoker) throws RpcException {
     //如果是registry协议则export protocol为：RegistryProtocol RegistryProtocol将通过Registry进行服务注册以及服务的远程暴露
    if (REGISTRY_PROTOCOL.equals(invoker.getUrl().getProtocol())) {
        return protocol.export(invoker);
    }
    return new ListenerExporterWrapper<T>(protocol.export(invoker),
            Collections.unmodifiableList(ExtensionLoader.getExtensionLoader(ExporterListener.class)
                    .getActivateExtension(invoker.getUrl(), EXPORTER_LISTENER_KEY)));
}
```

```java
RegistryProtocol.class
    
@Override
public <T> Exporter<T> export(final Invoker<T> originInvoker) throws RpcException {
    URL registryUrl = getRegistryUrl(originInvoker);
    // url to export locally
    URL providerUrl = getProviderUrl(originInvoker);

    // Subscribe the override data
    // FIXME When the provider subscribes, it will affect the scene : a certain JVM exposes the service and call
    //  the same service. Because the subscribed is cached key with the name of the service, it causes the
    //  subscription information to cover.
    final URL overrideSubscribeUrl = getSubscribedOverrideUrl(providerUrl);
    final OverrideListener overrideSubscribeListener = new OverrideListener(overrideSubscribeUrl, originInvoker);
    overrideListeners.put(overrideSubscribeUrl, overrideSubscribeListener);

    providerUrl = overrideUrlWithConfig(providerUrl, overrideSubscribeListener);
    //export invoker
    //本地暴露服务，启动Netty服务
    final ExporterChangeableWrapper<T> exporter = doLocalExport(originInvoker, providerUrl);

    // url to registry
    final Registry registry = getRegistry(originInvoker);
    final URL registeredProviderUrl = getRegisteredProviderUrl(providerUrl, registryUrl);
    ProviderInvokerWrapper<T> providerInvokerWrapper = ProviderConsumerRegTable.registerProvider(originInvoker,
            registryUrl, registeredProviderUrl);
    //to judge if we need to delay publish
    boolean register = registeredProviderUrl.getParameter("register", true);
    if (register) {
        //注册到注册中心
        register(registryUrl, registeredProviderUrl);
        providerInvokerWrapper.setReg(true);
    }

    // Deprecated! Subscribe to override rules in 2.6.x or before.
    registry.subscribe(overrideSubscribeUrl, overrideSubscribeListener);

    exporter.setRegisterUrl(registeredProviderUrl);
    exporter.setSubscribeUrl(overrideSubscribeUrl);
    //Ensure that a new exporter instance is returned every time export
    return new DestroyableExporter<>(exporter);
}
```

