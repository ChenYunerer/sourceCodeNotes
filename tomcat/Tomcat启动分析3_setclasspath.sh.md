---
title: Tomcat启动分析3_setclasspath.sh
tags: Tomcat
categories: Tomcat
---



## Tomcat8.5.9启动流程分析3

### setclasspath.sh 脚本

```bash
#!/bin/sh

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
#  Set JAVA_HOME or JRE_HOME if not already set and ensure any provided
#  settings are valid and consistent with the selected start-up options.
# -----------------------------------------------------------------------------

# Make sure prerequisite environment variables are set
# 如果JAVA_HOME和JRE_HOME都为空，则设置JAVA_HOME JRE_HOME环境变量
if [ -z "$JAVA_HOME" -a -z "$JRE_HOME" ]; then
  # MacOS的JAVA路径不同于普通的linux，所以特殊处理来获取JAVA_HOME
  if $darwin; then
    # Bugzilla 54390
    if [ -x '/usr/libexec/java_home' ] ; then
      export JAVA_HOME=`/usr/libexec/java_home`
    # Bugzilla 37284 (reviewed).
    elif [ -d "/System/Library/Frameworks/JavaVM.framework/Versions/CurrentJDK/Home" ]; then
      export JAVA_HOME="/System/Library/Frameworks/JavaVM.framework/Versions/CurrentJDK/Home"
    fi
  else
  	# 通过which命令来获取java可执行文件的位置 "2>/dev/null"表示过滤错误输出
    JAVA_PATH=`which java 2>/dev/null`
    if [ "x$JAVA_PATH" != "x" ]; then
    # JAVA_PATH非空，则通过dirname获取其所在文件夹路径赋值给JAVA_PATH以及JRE_HOME
      JAVA_PATH=`dirname $JAVA_PATH 2>/dev/null`
      JRE_HOME=`dirname $JAVA_PATH 2>/dev/null`
    fi
    # 如果JRE_HOME变量没有设置，且存在/usr/bin/java可执行文件，则默认JRE_HOME设置为/usr
    if [ "x$JRE_HOME" = "x" ]; then
      # XXX: Should we try other locations?
      if [ -x /usr/bin/java ]; then
        JRE_HOME=/usr
      fi
    fi
  fi
  # 如果到这一步JAVA_HOME都JRE_HOME都为空，则直接退出
  if [ -z "$JAVA_HOME" -a -z "$JRE_HOME" ]; then
    echo "Neither the JAVA_HOME nor the JRE_HOME environment variable is defined"
    echo "At least one of these environment variable is needed to run this program"
    exit 1
  fi
fi
# 判断是否以debug模式启动tomcat，如果是debug模式则要求JAVA_HOME环境变量不能为空，否则直接退出
if [ -z "$JAVA_HOME" -a "$1" = "debug" ]; then
  echo "JAVA_HOME should point to a JDK in order to run in debug mode."
  exit 1
fi
# 如果JRE_HOME环境变量为空，则默认赋值JAVA_HOME的值
if [ -z "$JRE_HOME" ]; then
  JRE_HOME="$JAVA_HOME"
fi

# If we're running under jdb, we need a full jdk.
# 如果debug模式启动tomcat则需要完整jdk而不仅仅jre，所以需要判断对应的可执行文件是否存在
# jdb用于debug模式启动tomcat
if [ "$1" = "debug" ] ; then
  if [ "$os400" = "true" ]; then
    if [ ! -x "$JAVA_HOME"/bin/java -o ! -x "$JAVA_HOME"/bin/javac ]; then
      echo "The JAVA_HOME environment variable is not defined correctly"
      echo "This environment variable is needed to run this program"
      echo "NB: JAVA_HOME should point to a JDK not a JRE"
      exit 1
    fi
  else
    if [ ! -x "$JAVA_HOME"/bin/java -o ! -x "$JAVA_HOME"/bin/jdb -o ! -x "$JAVA_HOME"/bin/javac ]; then
      echo "The JAVA_HOME environment variable is not defined correctly"
      echo "This environment variable is needed to run this program"
      echo "NB: JAVA_HOME should point to a JDK not a JRE"
      exit 1
    fi
  fi
fi

# Set standard commands for invoking Java, if not already set.
# 设置_RUNJAVA _RUNJDB变量值，之后用于启动org.apache.catalina.startup.Bootstrap
# _RUNJAVA使用java命令启动
# _RUNJDB使用jdb命令启动
if [ -z "$_RUNJAVA" ]; then
  _RUNJAVA="$JRE_HOME"/bin/java
fi
if [ "$os400" != "true" ]; then
  if [ -z "$_RUNJDB" ]; then
    _RUNJDB="$JAVA_HOME"/bin/jdb
  fi
fi

```

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
