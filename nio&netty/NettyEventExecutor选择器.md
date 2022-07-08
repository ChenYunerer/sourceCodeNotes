---
title: Netty EventExecutor选择器
tags: NIO&Netty
categories: NIO&Netty
data: 2020-08-28 22:33:24
---
# Netty EventExecutor选择器

Netty在选择EventExecutor的时候，会使用EventExecutorChooser来进行选择，EventExecutorChooser的实现有2个：

1. GenericEventExecutorChooser：使用取余%来循环选择EventExecutor

```java
private static final class GenericEventExecutorChooser implements EventExecutorChooser {
    private final AtomicInteger idx = new AtomicInteger();
    private final EventExecutor[] executors;

    GenericEventExecutorChooser(EventExecutor[] executors) {
        this.executors = executors;
    }

    @Override
    public EventExecutor next() {
      //使用取余%来循环选择EventExecutor
        return executors[Math.abs(idx.getAndIncrement() % executors.length)];
    }
}
```

2. PowerOfTwoEventExecutorChooser：使用位运算&来循环选择EventExecutor

```java
private static final class PowerOfTwoEventExecutorChooser implements EventExecutorChooser {
    private final AtomicInteger idx = new AtomicInteger();
    private final EventExecutor[] executors;

    PowerOfTwoEventExecutorChooser(EventExecutor[] executors) {
        this.executors = executors;
    }

    @Override
    public EventExecutor next() {
      //使用位运算&来循环选择EventExecutor
        return executors[idx.getAndIncrement() & executors.length - 1];
    }
}
```

具体构建哪种由EventExecutorChooserFactory来进行构建，EventExecutorChooserFactory的实现类为：DefaultEventExecutorChooserFactory，它根据EventExecutor数量是否为2的N次幂来决定具体构建哪种，如果是2的N次幂则使用PowerOfTwoEventExecutorChooser否则GenericEventExecutorChooser

```java
DefaultEventExecutorChooserFactory.class
 
//如果EventExecutor数量为2的N次幂则使用PowerOfTwoEventExecutorChooser否则GenericEventExecutorChooser
public EventExecutorChooser newChooser(EventExecutor[] executors) {
    if (isPowerOfTwo(executors.length)) {
        return new PowerOfTwoEventExecutorChooser(executors);
    } else {
        return new GenericEventExecutorChooser(executors);
    }
}

//判断是否是2的N次幂
private static boolean isPowerOfTwo(int val) {
    return (val & -val) == val;
}
```

### 为何要采用这种模式在%和&两种运算模式之间进行选择？

因为&与运算的运算速度要高于%取余运算

### 为何要判断2的N次幂才使用&与运算的EventExecutorChooser

根据选择代码executors[idx.getAndIncrement() & executors.length - 1]

2的N次幂转为二进制可以表示为：...00100...除第N位为1其他位全0

2的N次幂-1二进制可以表示为：...000111111从0位到N-1位全1其他全0

2的N次幂-1与其他累加值进行与运算举例为：

0000(0) & ...0001111(15)=...0000000(0)

0001(1) & ...0001111(15)=...0000001(1)

0010(2) & ...0001111(15)=...0000010(2)

...

1111(15) & ...0001111(15)=...0001111(15)

10000(16) & ...0001111(15)=...0000000(0)

...