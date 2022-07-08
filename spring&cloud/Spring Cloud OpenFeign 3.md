---
title: Spring Cloud OpenFeign 3
tags: Spring&SpringCloud
categories: Spring&SpringCloud
---



## Spring Cloud OpenFeign源码笔记3

#### 几种Client的实现

##### feign.Default

```java
@Override
public Response execute(Request request, Options options) throws IOException {
  HttpURLConnection connection = convertAndSend(request, options);
  return convertResponse(connection, request);
}
```

看到关键类HttpURLConnection就不多BB了

##### org.springframework.cloud.openfeign.ribbon.LoadBalancerFeignClient

```java
@Override
public Response execute(Request request, Request.Options options) throws IOException {
   try {
      URI asUri = URI.create(request.url());
      String clientName = asUri.getHost();
      URI uriWithoutHost = cleanUrl(request.url(), clientName);
      FeignLoadBalancer.RibbonRequest ribbonRequest = new FeignLoadBalancer.RibbonRequest(
            this.delegate, request, uriWithoutHost);

      IClientConfig requestConfig = getClientConfig(options, clientName);
      return lbClient(clientName).executeWithLoadBalancer(ribbonRequest,
            requestConfig).toResponse();
   }
   catch (ClientException e) {
      IOException io = findIOException(e);
      if (io != null) {
         throw io;
      }
      throw new RuntimeException(e);
   }
}
```

lbClient(clientName)通过服务名获取对应的FeignLoadBalancer，通过LoadBalancer发起请求

FeignLoadBalancer继承于AbstractLoadBalancerAwareClient，由ribbon提供负载均衡能力

##### org.springframework.cloud.sleuth.instrument.web.client.feign.TracingFeignClient

todo