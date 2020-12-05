---
title: Tomcat启动分析1_startup.sh
tags: Tomcat
categories: Tomcat
---



## Tomcat8.5.9启动流程分析1

### startup.sh 脚本

```bash
#!/bin/sh

# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# -----------------------------------------------------------------------------
# Start Script for the CATALINA Server
# -----------------------------------------------------------------------------

# Better OS/400 detection: see Bugzilla 31132
# 通过uname命令判断tomcat所处操作系统环境
# os400：OS/400是IBM公司为其AS/400以及AS/400e系列商业计算机开发的操作系统
os400=false
case "`uname`" in
OS400*) os400=true;;
esac

# resolve links - $0 may be a softlink
# -h 判断启动文件是否为链接文件
# 如果是链接文件则通过ls -ld 以及正则表达式循环直至获取到源文件
# $0表示引用启动文件 $1表示引用第一个启动参数
# eg: ./scripeNmae a b c $0: scripeNmae $1: a $2: b ...
PRG="$0"

while [ -h "$PRG" ] ; do
  ls=`ls -ld "$PRG"`
  link=`expr "$ls" : '.*-> \(.*\)$'`
  if expr "$link" : '/.*' > /dev/null; then
    PRG="$link"
  else
    PRG=`dirname "$PRG"`/"$link"
  fi
done
# dirname命令获取文件dir名称 
PRGDIR=`dirname "$PRG"`
EXECUTABLE=catalina.sh

# Check that target executable exists
# 判断是否是os400操作系统
if $os400; then
  # -x will Only work on the os400 if the files are:
  # 1. owned by the user
  # 2. owned by the PRIMARY group of the user
  # this will not work if the user belongs in secondary groups
  # 不太懂啥意思
  eval
else
  # 判断catalina.sh文件是否存在且可执行
  # -x 判断文件存在且可有可执行权限 类似的 -r -w 判断文件存在且有可读/可写权限
  if [ ! -x "$PRGDIR"/"$EXECUTABLE" ]; then
    echo "Cannot find $PRGDIR/$EXECUTABLE"
    echo "The file is absent or does not have execute permission"
    echo "This file is needed to run this program"
    exit 1
  fi
fi

# 启动catalina.sh脚本并附带参数： start 以及启动当前脚本时的所有参数
exec "$PRGDIR"/"$EXECUTABLE" start "$@"

```
其实类似于startup.sh，shutdown.sh、configtest.sh以及version.sh都是一样的：
1. 先对OS400操作系统进行判断
2. 获取执行脚本的源文件
3. 通过源文件获取到同目录下的catalina.sh脚本
4. 执行catalina.sh脚本，附带不同的参数，比如start、shutdown、configtest以及version指令都是由catalina.sh脚本来执行具体的逻辑

为什么需要进行源文件的判断？

​	因为需要执行源路径下的catalina.sh脚本，如果用户是通过链接文件执行的脚本，则该用户的链接文件同级目录几乎不可能存在catalina.sh脚本，所以需要获取源文件路径，catalina.sh脚本中也同样需要获取源文件路径，同理。

### IF常用判断速查
|  if判断   |  为ture的条件  |
| :-------: | :--------------: |
|  -r FILE  |  文件存在且可读  |
|  -w FILE  |  文件存在且可写  |
|  -x FILE  | 文件存在且可执行 |
| -z String |    字符串为空    |
| -n String |    字符串非空    |
|  -f FILE  |  文件存在且是普通文件  |
|  -s FILE  |   文件存在且大小非0    |
|  -S FILE  | 文件存在且为套接字文件 |
|  -a FILE  |        文件存在        |
