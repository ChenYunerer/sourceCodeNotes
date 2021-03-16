---
title: Java SPI
tags: Java基础
categories: Java基础
data: 2020-09-19 14:44:04
---
# Java SPI

## 使用

```java
Iterator iterator = ServiceLoader.load(XXX.class).iterator();
while (iterator.hasNext()){
    iterator.next();
}
```

## 关键代码

```java
LazyClassPathLookupIterator.class
//判断是否存在下一个Service(Provider)
private boolean hasNextService() {
            while (nextProvider == null && nextError == null) {
                try {
                    //获取下一个Class
                    Class<?> clazz = nextProviderClass();
                    if (clazz == null)
                        return false;

                    if (clazz.getModule().isNamed()) {
                        // ignore class if in named module
                        continue;
                    }
                    //构建ProviderImpl，通过ProviderImpl就可以获取实例
                    //将ProviderImpl赋予nextProvider以供next方法返回
                    if (service.isAssignableFrom(clazz)) {
                        Class<? extends S> type = (Class<? extends S>) clazz;
                        Constructor<? extends S> ctor
                            = (Constructor<? extends S>)getConstructor(clazz);
                        ProviderImpl<S> p = new ProviderImpl<S>(service, type, ctor, acc);
                        nextProvider = (ProviderImpl<T>) p;
                    } else {
                        fail(service, clazz.getName() + " not a subtype");
                    }
                } catch (ServiceConfigurationError e) {
                    nextError = e;
                }
            }
            return true;
        }
```

1. 获取下一个class
2. 构建对应的ProviderImpl，ProviderImpl其实就是该class的封装，可以获取该class的实例
3. 将该ProviderImpl赋予nextProvider，以供next方法返回

```java
LazyClassPathLookupIterator.class
  
//获取下一个Class
private Class<?> nextProviderClass() {
    //首次调用configs为空，configs就是META-INF/services/目录下对应的资源文件
    if (configs == null) {
        try {
            String fullName = PREFIX + service.getName();
            if (loader == null) {
                configs = ClassLoader.getSystemResources(fullName);
            } else if (loader == ClassLoaders.platformClassLoader()) {
                // The platform classloader doesn't have a class path,
                // but the boot loader might.
                if (BootLoader.hasClassPath()) {
                    configs = BootLoader.findResources(fullName);
                } else {
                    configs = Collections.emptyEnumeration();
                }
            } else {
                configs = loader.getResources(fullName);
            }
        } catch (IOException x) {
            fail(service, "Error locating configuration files", x);
        }
    }
   	//pending是Iterator，包含了所有对应文件记录的class name
    while ((pending == null) || !pending.hasNext()) {
        if (!configs.hasMoreElements()) {
            return null;
        }
        //pendin通过对资源文件的解析获得，具体解析过程就是按行读取而已
        pending = parse(configs.nextElement());
    }
    String cn = pending.next();
    try {
        return Class.forName(cn, false, loader);
    } catch (ClassNotFoundException x) {
        fail(service, "Provider " + cn + " not found");
        return null;
    }
}
```

1. 读取固定目录META-INF/services/下的资源文件
2. 逐行解析，保存className到LinkedHashSet并提供iterator
3. iterator.next获取className并通过Class.forName构建Class