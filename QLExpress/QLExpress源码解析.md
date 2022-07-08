---
title: QLExpress源码解析
tags: QLExpress
categories: QLExpress
data: 2021-10-28 12:04:14
---

# QLExpress源码解析

### 脚本举例

```java
int a = 1;
a = a + 1;
return a;
```

### 拆词结果

```java
int
a
=
1
;
a
=
a
+
1
;
return
a
;
```

### 词性分析结果

```java
int:CONST_CLASS
a:ID
=:=
1:CONST_INTEGER
;:;
a:ID
=:=
a:ID
+:+
1:CONST_INTEGER
;:;
return:return
a:ID
;:;
```



```java
1:   STAT_BLOCK:STAT_BLOCK
2:      STAT_SEMICOLON:STAT_SEMICOLON
3:         =:=
4:            def:def
5:               int:CONST_CLASS
5:               a:ID
4:            1:CONST_INTEGER
2:      STAT_SEMICOLON:STAT_SEMICOLON
3:         =:=
4:            a:ID
4:            +:+
5:               a:ID
5:               1:CONST_INTEGER
2:      STAT_SEMICOLON:STAT_SEMICOLON
3:         return:return
4:            a:ID
```

