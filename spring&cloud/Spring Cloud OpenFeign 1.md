---
title: Spring Cloud OpenFeign 1
tags: Spring&SpringCloud
categories: Spring&SpringCloud
---



## Spring Cloud OpenFeign源码笔记1

openFeign 存在2个配置文件，分别FeignClientProperties.class FeignHttpClientProperties.class

spring.factories 主要配置了FeignAutoConfiguration进行初始化

### FeignAutoConfiguration

注入Bean：FeignContext Targeter

```java
@Autowired(required = false)
private List<FeignClientSpecification> configurations = new ArrayList<>();

@Bean
	public FeignContext feignContext() {
		FeignContext context = new FeignContext();
		context.setConfigurations(this.configurations);
		return context;
	}

@Configuration
	@ConditionalOnClass(name = "feign.hystrix.HystrixFeign")
	protected static class HystrixFeignTargeterConfiguration {
		@Bean
		@ConditionalOnMissingBean
		public Targeter feignTargeter() {
			return new HystrixTargeter();
		}
	}

	@Configuration
	@ConditionalOnMissingClass("feign.hystrix.HystrixFeign")
	protected static class DefaultFeignTargeterConfiguration {
		@Bean
		@ConditionalOnMissingBean
		public Targeter feignTargeter() {
			return new DefaultTargeter();
		}
	}
```

#### FeignContext

这里构建了feignContext对象，并设置configurations

#### Targeter

如果存在熔断器则具体实例为：HystrixTargeter，否则为DefaultTargeter

当存在ApacheHttpClient且开启httpclient的时候，针对ApacheHttpClient进行配置（HttpClientConnectionManager、超时时间等），主要就是构造对应的client

当存在OkHttpClient且开启okhttp的时候，针对OkHttpClient进行配置（连接池、超时时间、重定向等），主要就是构造对应的client

### @EnableFeignClients

该注解注入了@Import(FeignClientsRegistrar.class)

#### FeignClientsRegistrar

FeignClietnsRegistrar实现了ImportBeanDefinitionRegistrar

```java
@Override
public void registerBeanDefinitions(AnnotationMetadata metadata,
      BeanDefinitionRegistry registry) {
   registerDefaultConfiguration(metadata, registry);
   registerFeignClients(metadata, registry);
}
```

主要处理2个步骤：

1. 注入默认的配置
2. 注入FeignClients

#### 注入默认的配置

```java
private void registerDefaultConfiguration(AnnotationMetadata metadata,
      BeanDefinitionRegistry registry) {
   Map<String, Object> defaultAttrs = metadata
         .getAnnotationAttributes(EnableFeignClients.class.getName(), true);

   if (defaultAttrs != null && defaultAttrs.containsKey("defaultConfiguration")) {
     //生成bean的名称
      String name;
      if (metadata.hasEnclosingClass()) {
         name = "default." + metadata.getEnclosingClassName();
      }
      else {
         name = "default." + metadata.getClassName();
      }
      registerClientConfiguration(registry, name,
            defaultAttrs.get("defaultConfiguration"));
   }
}

private void registerClientConfiguration(BeanDefinitionRegistry registry, Object name,
			Object configuration) {
  //构建BeanDefinition，实际的BeanDefinition是FeignClientSpecification，FeignClientSpecification中维护了configuration和对应的name
		BeanDefinitionBuilder builder = BeanDefinitionBuilder
				.genericBeanDefinition(FeignClientSpecification.class);
		builder.addConstructorArgValue(name);
		builder.addConstructorArgValue(configuration);
		registry.registerBeanDefinition(
				name + "." + FeignClientSpecification.class.getSimpleName(),
				builder.getBeanDefinition());
	}
```

#### 注入FeignClients

```java
public void registerFeignClients(AnnotationMetadata metadata,
      BeanDefinitionRegistry registry) {
   ClassPathScanningCandidateComponentProvider scanner = getScanner();
   scanner.setResourceLoader(this.resourceLoader);

   Set<String> basePackages;

   Map<String, Object> attrs = metadata
         .getAnnotationAttributes(EnableFeignClients.class.getName());
   AnnotationTypeFilter annotationTypeFilter = new AnnotationTypeFilter(
         FeignClient.class);
   final Class<?>[] clients = attrs == null ? null
         : (Class<?>[]) attrs.get("clients");
   if (clients == null || clients.length == 0) {
      scanner.addIncludeFilter(annotationTypeFilter);
      basePackages = getBasePackages(metadata);
   }
   else {
      final Set<String> clientClasses = new HashSet<>();
      basePackages = new HashSet<>();
      for (Class<?> clazz : clients) {
         basePackages.add(ClassUtils.getPackageName(clazz));
         clientClasses.add(clazz.getCanonicalName());
      }
      AbstractClassTestingTypeFilter filter = new AbstractClassTestingTypeFilter() {
         @Override
         protected boolean match(ClassMetadata metadata) {
            String cleaned = metadata.getClassName().replaceAll("\\$", ".");
            return clientClasses.contains(cleaned);
         }
      };
      scanner.addIncludeFilter(
            new AllTypeFilter(Arrays.asList(filter, annotationTypeFilter)));
   }

   for (String basePackage : basePackages) {
      Set<BeanDefinition> candidateComponents = scanner
            .findCandidateComponents(basePackage);
      for (BeanDefinition candidateComponent : candidateComponents) {
         if (candidateComponent instanceof AnnotatedBeanDefinition) {
            // verify annotated class is an interface
            AnnotatedBeanDefinition beanDefinition = (AnnotatedBeanDefinition) candidateComponent;
            AnnotationMetadata annotationMetadata = beanDefinition.getMetadata();
            Assert.isTrue(annotationMetadata.isInterface(),
                  "@FeignClient can only be specified on an interface");

            Map<String, Object> attributes = annotationMetadata
                  .getAnnotationAttributes(
                        FeignClient.class.getCanonicalName());
## NIO

            String name = getClientName(attributes);
            registerClientConfiguration(registry, name,
                  attributes.get("configuration"));
### Channel（数据通道）对应实现有：FileChannel DatagramChannel SocketChannel ServerSocketChannel

            registerFeignClient(registry, annotationMetadata, attributes);
         }
      }
   }
}
```
```java
private void registerFeignClient(BeanDefinitionRegistry registry,
      AnnotationMetadata annotationMetadata, Map<String, Object> attributes) {
   String className = annotationMetadata.getClassName();
   BeanDefinitionBuilder definition = BeanDefinitionBuilder
         .genericBeanDefinition(FeignClientFactoryBean.class);
   validate(attributes);
   definition.addPropertyValue("url", getUrl(attributes));
   definition.addPropertyValue("path", getPath(attributes));
   String name = getName(attributes);
   definition.addPropertyValue("name", name);
   definition.addPropertyValue("type", className);
   definition.addPropertyValue("decode404", attributes.get("decode404"));
   definition.addPropertyValue("fallback", attributes.get("fallback"));
   definition.addPropertyValue("fallbackFactory", attributes.get("fallbackFactory"));
   definition.setAutowireMode(AbstractBeanDefinition.AUTOWIRE_BY_TYPE);

   String alias = name + "FeignClient";
   AbstractBeanDefinition beanDefinition = definition.getBeanDefinition();

   boolean primary = (Boolean)attributes.get("primary"); // has a default, won't be null

   beanDefinition.setPrimary(primary);

   String qualifier = getQualifier(attributes);
   if (StringUtils.hasText(qualifier)) {
      alias = qualifier;
   }

   BeanDefinitionHolder holder = new BeanDefinitionHolder(beanDefinition, className,
         new String[] { alias });
   BeanDefinitionReaderUtils.registerBeanDefinition(holder, registry);
}
```

注入FeignClientFactoryBean BeanDefinition并为其设置url path name等@FeignClient注解配置的参数

最终构建BeanDefinitionHolder并通过BeanDefinitionReaderUtils.registerBeanDefinition进行注册。

BeanDefinitionHolder好处：可以对bean设置beanName的同时设置多个alias

对于上述3步骤：

```java
private void registerClientConfiguration(BeanDefinitionRegistry registry, Object name,
      Object configuration) {
   BeanDefinitionBuilder builder = BeanDefinitionBuilder
         .genericBeanDefinition(FeignClientSpecification.class);
   builder.addConstructorArgValue(name);
   builder.addConstructorArgValue(configuration);
   registry.registerBeanDefinition(
         name + "." + FeignClientSpecification.class.getSimpleName(),
         builder.getBeanDefinition());
}
```

和上文的注册默认配置一样，注册FeignClientSpecification BeanDefinition，由FeignClientSpecification来维护configuration以及其name

#### FeignClientFactoryBean构建Object流程

FeignClientFactoryBean实现了接口FactoryBean，由其来具体构建FeignClient对象

```java
@Override
public Object getObject() throws Exception {
   return getTarget();
}

<T> T getTarget() {
		FeignContext context = applicationContext.getBean(FeignContext.class);
		Feign.Builder builder = feign(context);

		if (!StringUtils.hasText(this.url)) {
			String url;
			if (!this.name.startsWith("http")) {
				url = "http://" + this.name;
			}
			else {
				url = this.name;
			}
			url += cleanPath();
			return (T) loadBalance(builder, context, new HardCodedTarget<>(this.type,
					this.name, url));
		}
		if (StringUtils.hasText(this.url) && !this.url.startsWith("http")) {
			this.url = "http://" + this.url;
		}
		String url = this.url + cleanPath();
		Client client = getOptional(context, Client.class);
		if (client != null) {
			if (client instanceof LoadBalancerFeignClient) {
				// not load balancing because we have a url,
				// but ribbon is on the classpath, so unwrap
				client = ((LoadBalancerFeignClient)client).getDelegate();
			}
			builder.client(client);
		}
		Targeter targeter = get(context, Targeter.class);
		return (T) targeter.target(this, builder, context, new HardCodedTarget<>(
				this.type, this.name, url));
	}
```

关键步骤：

1. 构建Feign.Builder（存在种实现：默认的Feign.Builder以及HystrixFeign.Builder），主要对Feign.Builder设置logger encoder decoder contract interceptors等（具体配置流程之后有空再看，再补充）默认的Decoder和Encoder由FeignClientsConfiguration构建
2. 对于url的处理：如果没有指定url，则通过name+path设置url，由url则对url进行http前缀处理
3. 对于没有指定url的情况，一定是通过服务治理的方式寻址，涉及到负载均衡，通过loadBalance()方法构建对应的FeignClient
4. 对于普通的存在url的情况，默认构建对应的FeignClient，两种情况存在url和不存在url其实区别主要在于对FeignClient设置的Client不同，一种是TraceLoadBalancerFeignClient一种是Default也有可能是OkHttpClient、ApacheHttpClient
5. 通过Targeter的target构建具体的FeignClient

Client的具体实现包括：Default、LazyClient、LazyTracingFeignClient、LoadBalancerFeignClient、TraceLoadBalancerFeignClient、TracingFeignClient以及上文提到的OkHttpClient、ApacheHttpClient

Targeter的具体实现包括：DefaultTargeter、HystrixTargeter

#### DefaultTargeter.target

```java
@Override
public <T> T target(FeignClientFactoryBean factory, Feign.Builder feign, FeignContext context,
               Target.HardCodedTarget<T> target) {
   return feign.target(target);
public class ServerConnect
{
    private static final int BUF_SIZE=1024;
    private static final int PORT = 8080;
    private static final int TIMEOUT = 3000;
    public static void main(String[] args)
    {
        selector();
    }
    public static void handleAccept(SelectionKey key) throws IOException{
        ServerSocketChannel ssChannel = (ServerSocketChannel)key.channel();
        SocketChannel sc = ssChannel.accept();
        sc.configureBlocking(false);
        sc.register(key.selector(), SelectionKey.OP_READ,ByteBuffer.allocateDirect(BUF_SIZE));
    }
    public static void handleRead(SelectionKey key) throws IOException{
        SocketChannel sc = (SocketChannel)key.channel();
        ByteBuffer buf = (ByteBuffer)key.attachment();
        long bytesRead = sc.read(buf);
        while(bytesRead>0){
            buf.flip();
            while(buf.hasRemaining()){
                System.out.print((char)buf.get());
            }
            System.out.println();
            buf.clear();
            bytesRead = sc.read(buf);
        }
        if(bytesRead == -1){
            sc.close();
        }
    }
    public static void handleWrite(SelectionKey key) throws IOException{
        ByteBuffer buf = (ByteBuffer)key.attachment();
        buf.flip();
        SocketChannel sc = (SocketChannel) key.channel();
        while(buf.hasRemaining()){
            sc.write(buf);
        }
        buf.compact();
    }
    public static void selector() {
        Selector selector = null;
        ServerSocketChannel ssc = null;
        try{
            selector = Selector.open();
            ssc= ServerSocketChannel.open();
            ssc.socket().bind(new InetSocketAddress(PORT));
            ssc.configureBlocking(false);
            ssc.register(selector, SelectionKey.OP_ACCEPT);
            while(true){
                if(selector.select(TIMEOUT) == 0){
                    System.out.println("==");
                    continue;
                }
                Iterator<SelectionKey> iter = selector.selectedKeys().iterator();
                while(iter.hasNext()){
                    SelectionKey key = iter.next();
                    if(key.isAcceptable()){
                        handleAccept(key);
                    }
                    if(key.isReadable()){
                        handleRead(key);
                    }
                    if(key.isWritable() && key.isValid()){
                        handleWrite(key);
                    }
                    if(key.isConnectable()){
                        System.out.println("isConnectable = true");
                    }
                    iter.remove();
                }
            }
        }catch(IOException e){
            e.printStackTrace();
        }finally{
            try{
                if(selector!=null){
                    selector.close();
                }
                if(ssc!=null){
                    ssc.close();
                }
            }catch(IOException e){
                e.printStackTrace();
            }
        }
    }
}
```

直接使用Feign.Builder来构建FeignClient代理对象,具体如何构建见其他md

#### HystrixTargeter.target

见名知义，绝对和熔断器有关，使FeignClient可以和熔断器进行配置


