---
title: Is Power Of Two
tags: 数据结构与算法
categories: Java基础
data: 2020-09-19 14:44:04
---
# Is Power Of Two判断一个值是否是2的N次幂



1. Netty做法

```java
public static boolean isPowerOfTwo0(Integer val) {
    return (val & -val) == val;
}
```

2. 其他做法

```java
public static boolean isPowerOfTwo1(Integer val) {
    if ((val & (~(val - 1)) + 1) == val) {
        return true;
    } else {
        return false;
    }
}
```

