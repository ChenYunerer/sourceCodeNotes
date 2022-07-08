---
title: Spring IOC
tags: Spring&SpringCloud
categories: Spring&SpringCloud
---



### Spring IOC源码阅读笔记

#### 启动加载BeanDefination

从main函数开始跟踪代码

```java
@EnableEurekaClient
@SpringBootApplication
@EnableDistributedTransaction
public class SpringApp3Application {

    public static void main(String[] args) {
        SpringApplication.run(SpringApp3Application.class, args);
    }

}
```

可以看到关键代码：

```java
AbstractApplicationContext.class
@Override
public void refresh() throws BeansException, IllegalStateException {
   synchronized (this.startupShutdownMonitor) {
      // Prepare this context for refreshing.
     //准备Refresh，主要记录启动时间，设置context容器状态，检查配置的必要的参数配置是否存在
      prepareRefresh();

      // Tell the subclass to refresh the internal bean factory.
     //初始化BeanFactory并进行扫描，获取BeanDefination
      ConfigurableListableBeanFactory beanFactory = obtainFreshBeanFactory();

      // Prepare the bean factory for use in this context.
     //对beanFactory进行一些设置，比如ignoreDependencyInterface，取消对一些实例的自动装配
     //registerResolvableDependency对一些实例进行特殊的自动装配，注入一些特殊的对象
      prepareBeanFactory(beanFactory);

      try {
         // Allows post-processing of the bean factory in context subclasses.
        //由子类实现，可以对beanFactory进行修改，比如注册特殊的BeanPostProcessors等
         postProcessBeanFactory(beanFactory);

         // Invoke factory processors registered as beans in the context.
        //执行BeanFactoryPostProcessor以及他的子类BeanDefinitionRegistryPostProcessor
         invokeBeanFactoryPostProcessors(beanFactory);

         // Register bean processors that intercept bean creation.
        //注册BeanPostProcessor
         registerBeanPostProcessors(beanFactory);

         // Initialize message source for this context.
        //初始化多语言国际化相关功能
         initMessageSource();

         // Initialize event multicaster for this context.
        //初始化applicationEventMulticaster以供Spring Event功能使用
         initApplicationEventMulticaster();

         // Initialize other special beans in specific context subclasses.
         onRefresh();

         // Check for listener beans and register them.
        //注册Spring Event的Listener
         registerListeners();

         // Instantiate all remaining (non-lazy-init) singletons.
        //实例化非懒加载的单例对象
         finishBeanFactoryInitialization(beanFactory);

         // Last step: publish corresponding event.
        //结束Refresh，清理Scan缓存，发送ContextRefreshedEvent事件等
         finishRefresh();
      }

      catch (BeansException ex) {
         if (logger.isWarnEnabled()) {
            logger.warn("Exception encountered during context initialization - " +
                  "cancelling refresh attempt: " + ex);
         }

         // Destroy already created singletons to avoid dangling resources.
         destroyBeans();

         // Reset 'active' flag.
         cancelRefresh(ex);

         // Propagate exception to caller.
         throw ex;
      }

      finally {
         // Reset common introspection caches in Spring's core, since we
         // might not ever need metadata for singleton beans anymore...
         resetCommonCaches();
      }
   }
}
```

对于其中关键的方法做下分析：

1. obtainFreshBeanFactory方法中，获取BeanDefination的具体逻辑：

   主要就是通过AnnotatedBeanDefinitionReader来加载所有指定的Class

   通过ClassPathBeanDefinitionScanner来扫描所有指定的basePackages目录

```java
AnnotationConfigWebApplicationContext.class
@Override
protected void loadBeanDefinitions(DefaultListableBeanFactory beanFactory) {
   AnnotatedBeanDefinitionReader reader = getAnnotatedBeanDefinitionReader(beanFactory);
   ClassPathBeanDefinitionScanner scanner = getClassPathBeanDefinitionScanner(beanFactory);

   BeanNameGenerator beanNameGenerator = getBeanNameGenerator();
   if (beanNameGenerator != null) {
      reader.setBeanNameGenerator(beanNameGenerator);
      scanner.setBeanNameGenerator(beanNameGenerator);
      beanFactory.registerSingleton(AnnotationConfigUtils.CONFIGURATION_BEAN_NAME_GENERATOR, beanNameGenerator);
   }

   ScopeMetadataResolver scopeMetadataResolver = getScopeMetadataResolver();
   if (scopeMetadataResolver != null) {
      reader.setScopeMetadataResolver(scopeMetadataResolver);
      scanner.setScopeMetadataResolver(scopeMetadataResolver);
   }

   if (!this.annotatedClasses.isEmpty()) {
      if (logger.isDebugEnabled()) {
         logger.debug("Registering annotated classes: [" +
               StringUtils.collectionToCommaDelimitedString(this.annotatedClasses) + "]");
      }
      reader.register(ClassUtils.toClassArray(this.annotatedClasses));
   }

   if (!this.basePackages.isEmpty()) {
      if (logger.isDebugEnabled()) {
         logger.debug("Scanning base packages: [" +
               StringUtils.collectionToCommaDelimitedString(this.basePackages) + "]");
      }
      scanner.scan(StringUtils.toStringArray(this.basePackages));
   }

   String[] configLocations = getConfigLocations();
   if (configLocations != null) {
      for (String configLocation : configLocations) {
         try {
            Class<?> clazz = ClassUtils.forName(configLocation, getClassLoader());
            if (logger.isTraceEnabled()) {
               logger.trace("Registering [" + configLocation + "]");
            }
            reader.register(clazz);
         }
         catch (ClassNotFoundException ex) {
            if (logger.isTraceEnabled()) {
               logger.trace("Could not load class for config location [" + configLocation +
                     "] - trying package scan. " + ex);
            }
            int count = scanner.scan(configLocation);
            if (count == 0 && logger.isDebugEnabled()) {
               logger.debug("No annotated classes found for specified class/package [" + configLocation + "]");
            }
         }
      }
   }
}
```

2. prepareBeanFactory方法中：

   ```java
   //对指定接口不进行自动装配，比如EnvironmentAware的属性是不需要自动装配的，该数据会在实例化Bean的时候，通过调用，手动传入，其他Aware接口也类似
   beanFactory.ignoreDependencyInterface(EnvironmentAware.class);
   //对指定的注入类型，指定注入的对象，比如如果有某个实例需要注入BeanFactory，则使用方法指定的beanFactory对象
   beanFactory.registerResolvableDependency(BeanFactory.class, beanFactory);
   ```

3. invokeBeanFactoryPostProcessors方法中执行的BeanFactoryPostProcessor以及BeanDefinitionRegistryPostProcessor，其中BeanDefinitionRegistryPostProcessor的实现类ConfigurationClassPostProcessor，就会在此期间对@Component、@PropertySource、@ComponentScan、@Import、@ImportResource、@Bean注解做处理

   比如对于@ComponentScan的处理

```java
ComponentScanAnnotationParser.class
// Process any @ComponentScan annotations
//获取所有ComponentScans注解信息
Set<AnnotationAttributes> componentScans = AnnotationConfigUtils.attributesForRepeatable(
      sourceClass.getMetadata(), ComponentScans.class, ComponentScan.class);
if (!componentScans.isEmpty() &&
      !this.conditionEvaluator.shouldSkip(sourceClass.getMetadata(), ConfigurationPhase.REGISTER_BEAN)) {
   for (AnnotationAttributes componentScan : componentScans) {
      // The config class is annotated with @ComponentScan -> perform the scan immediately
     //通过componentScanParser.parse进行解析，其中就是通过ClassPathBeanDefinitionScanner来进行扫描，只不过ClassPathBeanDefinitionScanner设置的扫描参数是从ComponentScan注解获取的
      Set<BeanDefinitionHolder> scannedBeanDefinitions =
            this.componentScanParser.parse(componentScan, sourceClass.getMetadata().getClassName());
      // Check the set of scanned definitions for any further config classes and parse recursively if needed
      for (BeanDefinitionHolder holder : scannedBeanDefinitions) {
         BeanDefinition bdCand = holder.getBeanDefinition().getOriginatingBeanDefinition();
         if (bdCand == null) {
            bdCand = holder.getBeanDefinition();
         }
         if (ConfigurationClassUtils.checkConfigurationClassCandidate(bdCand, this.metadataReaderFactory)) {
            parse(bdCand.getBeanClassName(), holder.getBeanName());
         }
      }
   }
}
```

4. Spring Evnet

   1. 初始化applicationEventMulticaster

   ```java
   //初始化applicationEventMulticaster
   	protected void initApplicationEventMulticaster() {
   		ConfigurableListableBeanFactory beanFactory = getBeanFactory();
   		if (beanFactory.containsLocalBean(APPLICATION_EVENT_MULTICASTER_BEAN_NAME)) {
   			this.applicationEventMulticaster =
   					beanFactory.getBean(APPLICATION_EVENT_MULTICASTER_BEAN_NAME, ApplicationEventMulticaster.class);
   			if (logger.isTraceEnabled()) {
   				logger.trace("Using ApplicationEventMulticaster [" + this.applicationEventMulticaster + "]");
   			}
   		}
   		else {
   			this.applicationEventMulticaster = new SimpleApplicationEventMulticaster(beanFactory);
   			beanFactory.registerSingleton(APPLICATION_EVENT_MULTICASTER_BEAN_NAME, this.applicationEventMulticaster);
   			if (logger.isTraceEnabled()) {
   				logger.trace("No '" + APPLICATION_EVENT_MULTICASTER_BEAN_NAME + "' bean, using " +
   						"[" + this.applicationEventMulticaster.getClass().getSimpleName() + "]");
   			}
   		}
   	}
   ```

   2. 扫描@EventListener注解的方法，创建ApplicationListener并有ApplicaotnContext维护

   finishBeanFactoryInitialization()->preInstantiateSingletons()方法中加载非懒加载的单例，并调用其afterSingletonsInstantiated()方法,EventListenerMethodProcessor在afterSingletonsInstantiated方法中实现了对于@EventListener的扫描，构建ApplicationListener并加入到AbstractApplicationContext的applicationListeners中维护

   ```sequence
   AbstractApplicationContext.refresh() -> initApplicationEventMulticaster(): Instantiate ApplicationEventMulticaster
   AbstractApplicationContext.refresh() -> finishBeanFactoryInitialization(): Instantiate non lazy singletons 
   finishBeanFactoryInitialization() -> beanFactory.preInstantiateSingletons(): Do Instantiate
   beanFactory.preInstantiateSingletons() -> smartSingleton.afterSingletonsInstantiated(): EventListenerMethodProcessor be instantiated \n postProcessBeanFactory method be called
   afterSingletonsInstantiated() -> processBean() : get all @EventListener method \n create ApplicationListener add to AbstractApplicationContext.applicationListeners(Set<ApplicationListener<?>>)
   ```

   3. Publish Evnet

      ```sequence
      ApplicationContext.publishEvent() -> AbstractApplicationEventMulticaster.multicastEvent(): invok multicastEvent method
      multicastEvent() -> multicastEvent(): find applicationListener and invokeListener
      
      ```


5. @Value注解的处理

   AbstractAnnotationBeanPostProcessor

#### GetBean

```java
AbstractBeanFactory.class
  
protected <T> T doGetBean(final String name, @Nullable final Class<T> requiredType,
      @Nullable final Object[] args, boolean typeCheckOnly) throws BeansException {
  //对bean name做转换
   final String beanName = transformedBeanName(name);
   Object bean;

  //尝试从单例缓存中获取实例
   // Eagerly check singleton cache for manually registered singletons.
   Object sharedInstance = getSingleton(beanName);
   if (sharedInstance != null && args == null) {
      if (logger.isTraceEnabled()) {
         if (isSingletonCurrentlyInCreation(beanName)) {
            logger.trace("Returning eagerly cached instance of singleton bean '" + beanName +
                  "' that is not fully initialized yet - a consequence of a circular reference");
         }
         else {
            logger.trace("Returning cached instance of singleton bean '" + beanName + "'");
         }
      }
      bean = getObjectForBeanInstance(sharedInstance, name, beanName, null);
   }

   else {
     //判断是否是循环引用
      // Fail if we're already creating this bean instance:
      // We're assumably within a circular reference.
      if (isPrototypeCurrentlyInCreation(beanName)) {
         throw new BeanCurrentlyInCreationException(beanName);
      }
     //尝试从父容器getBean
      // Check if bean definition exists in this factory.
      BeanFactory parentBeanFactory = getParentBeanFactory();
      if (parentBeanFactory != null && !containsBeanDefinition(beanName)) {
         // Not found -> check parent.
         String nameToLookup = originalBeanName(name);
         if (parentBeanFactory instanceof AbstractBeanFactory) {
            return ((AbstractBeanFactory) parentBeanFactory).doGetBean(
                  nameToLookup, requiredType, args, typeCheckOnly);
         }
         else if (args != null) {
            // Delegation to parent with explicit args.
            return (T) parentBeanFactory.getBean(nameToLookup, args);
         }
         else if (requiredType != null) {
            // No args -> delegate to standard getBean method.
            return parentBeanFactory.getBean(nameToLookup, requiredType);
         }
         else {
            return (T) parentBeanFactory.getBean(nameToLookup);
         }
      }
     
     //准备create bean，把beanName加入到alreadyCreated集合
      if (!typeCheckOnly) {
         markBeanAsCreated(beanName);
      }
     
     //先构建Bean的依赖
      try {
         final RootBeanDefinition mbd = getMergedLocalBeanDefinition(beanName);
         checkMergedBeanDefinition(mbd, beanName, args);

         // Guarantee initialization of beans that the current bean depends on.
         String[] dependsOn = mbd.getDependsOn();
         if (dependsOn != null) {
            for (String dep : dependsOn) {
               if (isDependent(beanName, dep)) {
                  throw new BeanCreationException(mbd.getResourceDescription(), beanName,
                        "Circular depends-on relationship between '" + beanName + "' and '" + dep + "'");
               }
               registerDependentBean(dep, beanName);
               try {
                  getBean(dep);
               }
               catch (NoSuchBeanDefinitionException ex) {
                  throw new BeanCreationException(mbd.getResourceDescription(), beanName,
                        "'" + beanName + "' depends on missing bean '" + dep + "'", ex);
               }
            }
         }
        
        //判断Bean的Scope，根据不同的Scope create bean
         // Create bean instance.
         if (mbd.isSingleton()) {
           //Scope 为单例模式的情况下
            sharedInstance = getSingleton(beanName, () -> {
               try {
                  return createBean(beanName, mbd, args);
               }
               catch (BeansException ex) {
                  // Explicitly remove instance from singleton cache: It might have been put there
                  // eagerly by the creation process, to allow for circular reference resolution.
                  // Also remove any beans that received a temporary reference to the bean.
                  destroySingleton(beanName);
                  throw ex;
               }
            });
            bean = getObjectForBeanInstance(sharedInstance, name, beanName, mbd);
         }

         else if (mbd.isPrototype()) {
           //Scope为原型模式的情况下
            // It's a prototype -> create a new instance.
            Object prototypeInstance = null;
            try {
               beforePrototypeCreation(beanName);
               prototypeInstance = createBean(beanName, mbd, args);
            }
            finally {
               afterPrototypeCreation(beanName);
            }
            bean = getObjectForBeanInstance(prototypeInstance, name, beanName, mbd);
         }

         else {
           //其他Scope模式
            String scopeName = mbd.getScope();
            final Scope scope = this.scopes.get(scopeName);
            if (scope == null) {
               throw new IllegalStateException("No Scope registered for scope name '" + scopeName + "'");
            }
            try {
               Object scopedInstance = scope.get(beanName, () -> {
                  beforePrototypeCreation(beanName);
                  try {
                     return createBean(beanName, mbd, args);
                  }
                  finally {
                     afterPrototypeCreation(beanName);
                  }
               });
               bean = getObjectForBeanInstance(scopedInstance, name, beanName, mbd);
            }
            catch (IllegalStateException ex) {
               throw new BeanCreationException(beanName,
                     "Scope '" + scopeName + "' is not active for the current thread; consider " +
                     "defining a scoped proxy for this bean if you intend to refer to it from a singleton",
                     ex);
            }
         }
      }
      catch (BeansException ex) {
         cleanupAfterBeanCreationFailure(beanName);
         throw ex;
      }
   }

  //对Bean进行类型转换
   // Check if required type matches the type of the actual bean instance.
   if (requiredType != null && !requiredType.isInstance(bean)) {
      try {
         T convertedBean = getTypeConverter().convertIfNecessary(bean, requiredType);
         if (convertedBean == null) {
            throw new BeanNotOfRequiredTypeException(name, requiredType, bean.getClass());
         }
         return convertedBean;
      }
      catch (TypeMismatchException ex) {
         if (logger.isTraceEnabled()) {
            logger.trace("Failed to convert bean '" + name + "' to required type '" +
                  ClassUtils.getQualifiedName(requiredType) + "'", ex);
         }
         throw new BeanNotOfRequiredTypeException(name, requiredType, bean.getClass());
      }
   }
   return (T) bean;
}
```

```java
//从缓存中获取单例对象，可以解决循环引用问题，单例对象加入缓存可以看下文的addSingletonFactory()方法
@Nullable
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

```java
AbstractAutowireCapableBeanFactory.class
protected Object doCreateBean(final String beanName, final RootBeanDefinition mbd, final @Nullable Object[] args)
      throws BeanCreationException {

  //实例化Bean
   // Instantiate the bean.
   BeanWrapper instanceWrapper = null;
   if (mbd.isSingleton()) {
      instanceWrapper = this.factoryBeanInstanceCache.remove(beanName);
   }
   if (instanceWrapper == null) {
      instanceWrapper = createBeanInstance(beanName, mbd, args);
   }
   final Object bean = instanceWrapper.getWrappedInstance();
   Class<?> beanType = instanceWrapper.getWrappedClass();
   if (beanType != NullBean.class) {
      mbd.resolvedTargetType = beanType;
   }

  //执行post-processors MergedBeanDefinitionPostProcessor.postProcessMergedBeanDefinition()
   // Allow post-processors to modify the merged bean definition.
   synchronized (mbd.postProcessingLock) {
      if (!mbd.postProcessed) {
         try {
            applyMergedBeanDefinitionPostProcessors(mbd, beanType, beanName);
         }
         catch (Throwable ex) {
            throw new BeanCreationException(mbd.getResourceDescription(), beanName,
                  "Post-processing of merged bean definition failed", ex);
         }
         mbd.postProcessed = true;
      }
   }

  //在对Bean进行配置前，就新暴露出去，以供循环引用使用
   // Eagerly cache singletons to be able to resolve circular references
   // even when triggered by lifecycle interfaces like BeanFactoryAware.
   boolean earlySingletonExposure = (mbd.isSingleton() && this.allowCircularReferences &&
         isSingletonCurrentlyInCreation(beanName));
   if (earlySingletonExposure) {
      if (logger.isTraceEnabled()) {
         logger.trace("Eagerly caching bean '" + beanName +
               "' to allow for resolving potential circular references");
      }
      addSingletonFactory(beanName, () -> getEarlyBeanReference(beanName, mbd, bean));
   }

 
   // Initialize the bean instance.
   Object exposedObject = bean;
   try {
     //执行
     //InstantiationAwareBeanPostProcessor.postProcessProperties()
     //InstantiationAwareBeanPostProcessor.postProcessPropertyValues()
     //对Bean的属性等进行主动注入:通过AutowiredAnnotationBeanPostProcessor InjectionMetadata InjectedElement（AnnotatedFieldElement、AnnotatedMethodElement）对Bean进行依赖注入
      populateBean(beanName, mbd, instanceWrapper);
     //对AwareMethod进行注入
     //执行BeanPostProcessor.postProcessBeforeInitialization()
     //执行init method
     //执行BeanPostProcessor.postProcessAfterInitialization()
      exposedObject = initializeBean(beanName, exposedObject, mbd);
   }
   catch (Throwable ex) {
      if (ex instanceof BeanCreationException && beanName.equals(((BeanCreationException) ex).getBeanName())) {
         throw (BeanCreationException) ex;
      }
      else {
         throw new BeanCreationException(
               mbd.getResourceDescription(), beanName, "Initialization of bean failed", ex);
      }
   }

   if (earlySingletonExposure) {
      Object earlySingletonReference = getSingleton(beanName, false);
      if (earlySingletonReference != null) {
         if (exposedObject == bean) {
            exposedObject = earlySingletonReference;
         }
         else if (!this.allowRawInjectionDespiteWrapping && hasDependentBean(beanName)) {
            String[] dependentBeans = getDependentBeans(beanName);
            Set<String> actualDependentBeans = new LinkedHashSet<>(dependentBeans.length);
            for (String dependentBean : dependentBeans) {
               if (!removeSingletonIfCreatedForTypeCheckOnly(dependentBean)) {
                  actualDependentBeans.add(dependentBean);
               }
            }
            if (!actualDependentBeans.isEmpty()) {
               throw new BeanCurrentlyInCreationException(beanName,
                     "Bean with name '" + beanName + "' has been injected into other beans [" +
                     StringUtils.collectionToCommaDelimitedString(actualDependentBeans) +
                     "] in its raw version as part of a circular reference, but has eventually been " +
                     "wrapped. This means that said other beans do not use the final version of the " +
                     "bean. This is often the result of over-eager type matching - consider using " +
                     "'getBeanNamesOfType' with the 'allowEagerInit' flag turned off, for example.");
            }
         }
      }
   }

  //注册Bean的Disposable方法，以供销毁Bean是进行回调调用
   // Register bean as disposable.
   try {
      registerDisposableBeanIfNecessary(beanName, bean, mbd);
   }
   catch (BeanDefinitionValidationException ex) {
      throw new BeanCreationException(
            mbd.getResourceDescription(), beanName, "Invalid destruction signature", ex);
   }

   return exposedObject;
}
```

提前暴露bean：

```java
protected void addSingletonFactory(String beanName, ObjectFactory<?> singletonFactory) {
   Assert.notNull(singletonFactory, "Singleton factory must not be null");
   synchronized (this.singletonObjects) {
      if (!this.singletonObjects.containsKey(beanName)) {
         this.singletonFactories.put(beanName, singletonFactory);
         this.earlySingletonObjects.remove(beanName);
         this.registeredSingletons.add(beanName);
      }
   }
}
```