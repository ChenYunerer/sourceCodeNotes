---
title: Tomcat启动分析2_catalina.sh
tags: Tomcat
categories: Tomcat
---



## Tomcat8.5.9启动流程分析2

### catalina.sh 脚本

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
# Control Script for the CATALINA Server
#
# Environment Variable Prerequisites
#
#   Do not set the variables in this script. Instead put them into a script
#   setenv.sh in CATALINA_BASE/bin to keep your customizations separate.
#
#   CATALINA_HOME   May point at your Catalina "build" directory.
# 
#
#   CATALINA_BASE   (Optional) Base directory for resolving dynamic portions
#                   of a Catalina installation.  If not present, resolves to
#                   the same directory that CATALINA_HOME points to.
#
#   CATALINA_OUT    (Optional) Full path to a file where stdout and stderr
#                   will be redirected.
#                   Default is $CATALINA_BASE/logs/catalina.out
#
#   CATALINA_OPTS   (Optional) Java runtime options used when the "start",
#                   "run" or "debug" command is executed.
#                   Include here and not in JAVA_OPTS all options, that should
#                   only be used by Tomcat itself, not by the stop process,
#                   the version command etc.
#                   Examples are heap size, GC logging, JMX ports etc.
#
#   CATALINA_TMPDIR (Optional) Directory path location of temporary directory
#                   the JVM should use (java.io.tmpdir).  Defaults to
#                   $CATALINA_BASE/temp.
#
#   JAVA_HOME       Must point at your Java Development Kit installation.
#                   Required to run the with the "debug" argument.
#
#   JRE_HOME        Must point at your Java Runtime installation.
#                   Defaults to JAVA_HOME if empty. If JRE_HOME and JAVA_HOME
#                   are both set, JRE_HOME is used.
#
#   JAVA_OPTS       (Optional) Java runtime options used when any command
#                   is executed.
#                   Include here and not in CATALINA_OPTS all options, that
#                   should be used by Tomcat and also by the stop process,
#                   the version command etc.
#                   Most options should go into CATALINA_OPTS.
#
#   JPDA_TRANSPORT  (Optional) JPDA transport used when the "jpda start"
#                   command is executed. The default is "dt_socket".
#
#   JPDA_ADDRESS    (Optional) Java runtime options used when the "jpda start"
#                   command is executed. The default is localhost:8000.
#
#   JPDA_SUSPEND    (Optional) Java runtime options used when the "jpda start"
#                   command is executed. Specifies whether JVM should suspend
#                   execution immediately after startup. Default is "n".
#
#   JPDA_OPTS       (Optional) Java runtime options used when the "jpda start"
#                   command is executed. If used, JPDA_TRANSPORT, JPDA_ADDRESS,
#                   and JPDA_SUSPEND are ignored. Thus, all required jpda
#                   options MUST be specified. The default is:
#
#                   -agentlib:jdwp=transport=$JPDA_TRANSPORT,
#                       address=$JPDA_ADDRESS,server=y,suspend=$JPDA_SUSPEND
#
#   JSSE_OPTS       (Optional) Java runtime options used to control the TLS
#                   implementation when JSSE is used. Default is:
#                   "-Djdk.tls.ephemeralDHKeySize=2048"
#
#   CATALINA_PID    (Optional) Path of the file which should contains the pid
#                   of the catalina startup java process, when start (fork) is
#                   used
#
#   LOGGING_CONFIG  (Optional) Override Tomcat's logging config file
#                   Example (all one line)
#                   LOGGING_CONFIG="-Djava.util.logging.config.file=$CATALINA_BASE/conf/logging.properties"
#
#   LOGGING_MANAGER (Optional) Override Tomcat's logging manager
#                   Example (all one line)
#                   LOGGING_MANAGER="-Djava.util.logging.manager=org.apache.juli.ClassLoaderLogManager"
#
#   UMASK           (Optional) Override Tomcat's default UMASK of 0027
#
#   USE_NOHUP       (Optional) If set to the string true the start command will
#                   use nohup so that the Tomcat process will ignore any hangup
#                   signals. Default is "false" unless running on HP-UX in which
#                   case the default is "true"
# -----------------------------------------------------------------------------

# OS specific support.  $var _must_ be set to either true or false.
# 通过uname命令来判断tomcat所处的炒作系统环境
# darwin: macOS 
# os400：OS/400是IBM公司为其AS/400以及AS/400e系列商业计算机开发的操作系统
# hpux :HP-UX操作系统是惠普(Hewlett-Packard)公司的UNIX系统，其设计目标是依照POSIX标准为HP公司的网络可靠而稳# 定地运行、能进行严格管理的UNIX系统。它以良好的开放性、互操作性和出色的软件功能而在金融等领域得到广泛的应用
cygwin=false
darwin=false
os400=false
hpux=false
case "`uname`" in
CYGWIN*) cygwin=true;;
Darwin*) darwin=true;;
OS400*) os400=true;;
HP-UX*) hpux=true;;
esac

# resolve links - $0 may be a softlink
# -h 判断启动文件是否为链接文件
# 如果是链接文件则通过ls -ld 以及正则表达式循环直至获取到源文件
# $0表示引用启动文件 $1表示引用第一个启动参数
# eg: ./scripeNmae a b c $0: scripeNmae $1: a $2: b ...
PRG="$0"

while [ -h "$PRG" ]; do
  ls=`ls -ld "$PRG"`
  link=`expr "$ls" : '.*-> \(.*\)$'`
  if expr "$link" : '/.*' > /dev/null; then
    PRG="$link"
  else
    PRG=`dirname "$PRG"`/"$link"
  fi
done

# Get standard environment variables
# dirname命令获取文件dir名称 
PRGDIR=`dirname "$PRG"`

# Only set CATALINA_HOME if not already set
# 通过-z判断CATALINA_HOME是否为空，如果为空则为其赋值：catalina.sb源文件的上一级目录
# `cd "$PRGDIR/.." >/dev/null; pwd` 这里通过cd进入PRGDIR的上级目录（如果存在标准输出则输出到/dev/null避免在控制台打印信息），然后通过pwd获取目录path
# cd命令存在标准输出？cd不存在的路径的时候会有输出
[ -z "$CATALINA_HOME" ] && CATALINA_HOME=`cd "$PRGDIR/.." >/dev/null; pwd`

# Copy CATALINA_BASE from CATALINA_HOME if not already set
# 通过-z判断CATALINA_BASE是否为空，如果是空则CATALINA_BASE默认与CATALINA_HOME相同
[ -z "$CATALINA_BASE" ] && CATALINA_BASE="$CATALINA_HOME"

# Ensure that any user defined CLASSPATH variables are not used on startup,
# but allow them to be specified in setenv.sh, in rare case when it is needed.
# 如果在CATALINA_BASE/bin以及CATALINA_HOME/bin下存在setenv.sh脚本则执行脚本(setenv.sh存在优先级，CATALINA_BASE/bin优先级最高)，可以用来为tomcat设置CLASSPATH变量，tomcat也推荐用户编写setenv.sh来自主设置环境变量而不是直接修改catalina.sh
CLASSPATH=

if [ -r "$CATALINA_BASE/bin/setenv.sh" ]; then
  . "$CATALINA_BASE/bin/setenv.sh"
elif [ -r "$CATALINA_HOME/bin/setenv.sh" ]; then
  . "$CATALINA_HOME/bin/setenv.sh"
fi

# For Cygwin, ensure paths are in UNIX format before anything is touched
# 如果是Cygwin环境，则cygpath --unix来格式化各个环境变量来符合unix编码风格
if $cygwin; then
  [ -n "$JAVA_HOME" ] && JAVA_HOME=`cygpath --unix "$JAVA_HOME"`
  [ -n "$JRE_HOME" ] && JRE_HOME=`cygpath --unix "$JRE_HOME"`
  [ -n "$CATALINA_HOME" ] && CATALINA_HOME=`cygpath --unix "$CATALINA_HOME"`
  [ -n "$CATALINA_BASE" ] && CATALINA_BASE=`cygpath --unix "$CATALINA_BASE"`
  [ -n "$CLASSPATH" ] && CLASSPATH=`cygpath --path --unix "$CLASSPATH"`
fi

# Ensure that neither CATALINA_HOME nor CATALINA_BASE contains a colon
# as this is used as the separator in the classpath and Java provides no
# mechanism for escaping if the same character appears in the path.
# 判断CATALINA_HOME和CATALINA_BASE中是否包含冒号,如果存在冒号则推出
# JAVA类路径中也可能存在冒号，所以路径中不能出现该字符，JAVA也没有对路径中存在冒号做转义
case $CATALINA_HOME in
  *:*) echo "Using CATALINA_HOME:   $CATALINA_HOME";
       echo "Unable to start as CATALINA_HOME contains a colon (:) character";
       exit 1;
esac
case $CATALINA_BASE in
  *:*) echo "Using CATALINA_BASE:   $CATALINA_BASE";
       echo "Unable to start as CATALINA_BASE contains a colon (:) character";
       exit 1;
esac

# For OS400
# 如果是OS400操作系统则做一些特殊处理
if $os400; then
  # Set job priority to standard for interactive (interactive - 6) by using
  # the interactive priority - 6, the helper threads that respond to requests
  # will be running at the same priority as interactive jobs.
  COMMAND='chgjob job('$JOBNAME') runpty(6)'
  system $COMMAND

  # Enable multi threading
  export QIBM_MULTI_THREADED=Y
fi

# Get standard Java environment variables
# 执行CATALINA_HOME/bin目录下的setclasspath.sh脚本，该脚本主要用来设置以及查验JAVA_HOME以及JRE_HOME环境变量
if $os400; then
  # -r will Only work on the os400 if the files are:
  # 1. owned by the user
  # 2. owned by the PRIMARY group of the user
  # this will not work if the user belongs in secondary groups
  . "$CATALINA_HOME"/bin/setclasspath.sh
else
  if [ -r "$CATALINA_HOME"/bin/setclasspath.sh ]; then
    . "$CATALINA_HOME"/bin/setclasspath.sh
  else
    echo "Cannot find $CATALINA_HOME/bin/setclasspath.sh"
    echo "This file is needed to run this program"
    exit 1
  fi
fi

# Add on extra jar files to CLASSPATH
# CLASSPATH追加jar配置
if [ ! -z "$CLASSPATH" ] ; then
  CLASSPATH="$CLASSPATH":
fi
CLASSPATH="$CLASSPATH""$CATALINA_HOME"/bin/bootstrap.jar

# 为CATALINA_OUT设置默认值
if [ -z "$CATALINA_OUT" ] ; then
  CATALINA_OUT="$CATALINA_BASE"/logs/catalina.out
fi

# 为CATALINA_TMPDIR设置默认值
if [ -z "$CATALINA_TMPDIR" ] ; then
  # Define the java.io.tmpdir to use for Catalina
  CATALINA_TMPDIR="$CATALINA_BASE"/temp
fi

# Add tomcat-juli.jar to classpath
# tomcat-juli.jar can be over-ridden per instance
# 如果CATALINA_BASE/bin/tomcat-juli.jar存在且可读则追加到CLASSPATH当中，否则追加CATALINA_HOME/bin/tomcat-juli.jar
if [ -r "$CATALINA_BASE/bin/tomcat-juli.jar" ] ; then
  CLASSPATH=$CLASSPATH:$CATALINA_BASE/bin/tomcat-juli.jar
else
  CLASSPATH=$CLASSPATH:$CATALINA_HOME/bin/tomcat-juli.jar
fi

# Bugzilla 37848: When no TTY is available, don't output to console
# 通过tty命令来判断是否存在虚拟终端、虚拟控制台
have_tty=0
if [ "`tty`" != "not a tty" ]; then
    have_tty=1
fi

# For Cygwin, switch paths to Windows format before running java
# 对cygwin做特殊处理 转换环境变量中的路径为windows格式
if $cygwin; then
  JAVA_HOME=`cygpath --absolute --windows "$JAVA_HOME"`
  JRE_HOME=`cygpath --absolute --windows "$JRE_HOME"`
  CATALINA_HOME=`cygpath --absolute --windows "$CATALINA_HOME"`
  CATALINA_BASE=`cygpath --absolute --windows "$CATALINA_BASE"`
  CATALINA_TMPDIR=`cygpath --absolute --windows "$CATALINA_TMPDIR"`
  CLASSPATH=`cygpath --path --windows "$CLASSPATH"`
fi

# 为JSSE_OPTS设置默认值
if [ -z "$JSSE_OPTS" ] ; then
  JSSE_OPTS="-Djdk.tls.ephemeralDHKeySize=2048"
fi
# 为JAVA_OPTS追加JSSE_OPTS
JAVA_OPTS="$JAVA_OPTS $JSSE_OPTS"

# Register custom URL handlers
# Do this here so custom URL handles (specifically 'war:...') can be used in the security policy
JAVA_OPTS="$JAVA_OPTS -Djava.protocol.handler.pkgs=org.apache.catalina.webresources"

# Set juli LogManager config file if it is present and an override has not been issued
if [ -z "$LOGGING_CONFIG" ]; then
  if [ -r "$CATALINA_BASE"/conf/logging.properties ]; then
    LOGGING_CONFIG="-Djava.util.logging.config.file=$CATALINA_BASE/conf/logging.properties"
  else
    # Bugzilla 45585
    LOGGING_CONFIG="-Dnop"
  fi
fi

if [ -z "$LOGGING_MANAGER" ]; then
  LOGGING_MANAGER="-Djava.util.logging.manager=org.apache.juli.ClassLoaderLogManager"
fi

# Set UMASK unless it has been overridden
# 设置默认的umask值，umask表示新建文件的权限需要削减的值
# umask由4位数字组成比如0022，第一位表示特殊权限，第二位到第四位分别标识，用户，用户组以及其他用户
# eg: 某文件夹的默认权限为drwxrwxrwx，umaks为0002，则该目录下创建的文件默认权限为：rwxrwxr-x, linux文件权限数字1表示r（读权限）2表示w（写权限）4表示x(执行权限)
if [ -z "$UMASK" ]; then
    UMASK="0027"
fi
# 执行umask使之生效
umask $UMASK

# Uncomment the following line to make the umask available when using the
# org.apache.catalina.security.SecurityListener
#JAVA_OPTS="$JAVA_OPTS -Dorg.apache.catalina.security.SecurityListener.UMASK=`umask`"
# 为USE_NOHUP环境变量设置默认值，如果是hpux操作系统环境则为ture否则false
# 默认centos下USE_NOHUP会被设置成false，如果tomcat USE_NOHUP为ture则表示以nohup模式启动，不响应任何hangup signals，简单说就是可以在后台运行
if [ -z "$USE_NOHUP" ]; then
    if $hpux; then
        USE_NOHUP="true"
    else
        USE_NOHUP="false"
    fi
fi
unset _NOHUP
if [ "$USE_NOHUP" = "true" ]; then
    _NOHUP=nohup
fi

# ----- Execute The Requested Command -----------------------------------------
# 以下所有内容都在根据不同命令来执行不同动作
# start run debug stop以不同方式启动tomcat
# configtest 测试配置
# version 打印版本信息
# 如果都没有匹配则打印提示信息

# Bugzilla 37848: only output this if we have a TTY
# 如果存在终端或是串口则向外打印一些提示信息
if [ $have_tty -eq 1 ]; then
  echo "Using CATALINA_BASE:   $CATALINA_BASE"
  echo "Using CATALINA_HOME:   $CATALINA_HOME"
  echo "Using CATALINA_TMPDIR: $CATALINA_TMPDIR"
  if [ "$1" = "debug" ] ; then
    echo "Using JAVA_HOME:       $JAVA_HOME"
  else
    echo "Using JRE_HOME:        $JRE_HOME"
  fi
  echo "Using CLASSPATH:       $CLASSPATH"
  if [ ! -z "$CATALINA_PID" ]; then
    echo "Using CATALINA_PID:    $CATALINA_PID"
  fi
fi

if [ "$1" = "jpda" ] ; then
  if [ -z "$JPDA_TRANSPORT" ]; then
    JPDA_TRANSPORT="dt_socket"
  fi
  if [ -z "$JPDA_ADDRESS" ]; then
    JPDA_ADDRESS="localhost:8000"
  fi
  if [ -z "$JPDA_SUSPEND" ]; then
    JPDA_SUSPEND="n"
  fi
  if [ -z "$JPDA_OPTS" ]; then
    JPDA_OPTS="-agentlib:jdwp=transport=$JPDA_TRANSPORT,address=$JPDA_ADDRESS,server=y,suspend=$JPDA_SUSPEND"
  fi
  CATALINA_OPTS="$JPDA_OPTS $CATALINA_OPTS"
  # shift用于移动$指向的参数位置 $1本来指向第一个参数 shift一次 $1变为指向第二个参数
  shift
fi

# debug模式启动tomcat 使用_RUNJDB执行org.apache.catalina.startup.Bootstrap
# _RUNJDB变量在setclasspath.sh当中已经设置成了JAVA_HOME/bin/jdb
if [ "$1" = "debug" ] ; then
  if $os400; then
    echo "Debug command not available on OS400"
    exit 1
  else
    shift
    if [ "$1" = "-security" ] ; then
      if [ $have_tty -eq 1 ]; then
        echo "Using Security Manager"
      fi
      shift
      exec "$_RUNJDB" "$LOGGING_CONFIG" $LOGGING_MANAGER $JAVA_OPTS $CATALINA_OPTS \
        -classpath "$CLASSPATH" \
        -sourcepath "$CATALINA_HOME"/../../java \
        -Djava.security.manager \
        -Djava.security.policy=="$CATALINA_BASE"/conf/catalina.policy \
        -Dcatalina.base="$CATALINA_BASE" \
        -Dcatalina.home="$CATALINA_HOME" \
        -Djava.io.tmpdir="$CATALINA_TMPDIR" \
        org.apache.catalina.startup.Bootstrap "$@" start
    else
      exec "$_RUNJDB" "$LOGGING_CONFIG" $LOGGING_MANAGER $JAVA_OPTS $CATALINA_OPTS \
        -classpath "$CLASSPATH" \
        -sourcepath "$CATALINA_HOME"/../../java \
        -Dcatalina.base="$CATALINA_BASE" \
        -Dcatalina.home="$CATALINA_HOME" \
        -Djava.io.tmpdir="$CATALINA_TMPDIR" \
        org.apache.catalina.startup.Bootstrap "$@" start
    fi
  fi

# start模式启动tomcat 使用_RUNJAVA执行org.apache.catalina.startup.Bootstrap
# _RUNJAVA变量在setclasspath.sh当中已经设置成了JRE_HOME/bin/java
# 与run启动tomcat不同的是，start会根据nohup配置确认是否nohup启动，并且将输出log输出到CATALINA_OUT，而run则会打印在终端上
elif [ "$1" = "run" ]; then

  shift
  if [ "$1" = "-security" ] ; then
    if [ $have_tty -eq 1 ]; then
      echo "Using Security Manager"
    fi
    shift
    eval exec "\"$_RUNJAVA\"" "\"$LOGGING_CONFIG\"" $LOGGING_MANAGER $JAVA_OPTS $CATALINA_OPTS \
      -classpath "\"$CLASSPATH\"" \
      -Djava.security.manager \
      -Djava.security.policy=="\"$CATALINA_BASE/conf/catalina.policy\"" \
      -Dcatalina.base="\"$CATALINA_BASE\"" \
      -Dcatalina.home="\"$CATALINA_HOME\"" \
      -Djava.io.tmpdir="\"$CATALINA_TMPDIR\"" \
      org.apache.catalina.startup.Bootstrap "$@" start
  else
    eval exec "\"$_RUNJAVA\"" "\"$LOGGING_CONFIG\"" $LOGGING_MANAGER $JAVA_OPTS $CATALINA_OPTS \
      -classpath "\"$CLASSPATH\"" \
      -Dcatalina.base="\"$CATALINA_BASE\"" \
      -Dcatalina.home="\"$CATALINA_HOME\"" \
      -Djava.io.tmpdir="\"$CATALINA_TMPDIR\"" \
      org.apache.catalina.startup.Bootstrap "$@" start
  fi

# start模式启动tomcat 使用_RUNJAVA执行org.apache.catalina.startup.Bootstrap
# _RUNJAVA变量在setclasspath.sh当中已经设置成了JRE_HOME/bin/java
# 与run启动tomcat不同的是，start会根据nohup配置确认是否nohup启动，并且将输出log输出到CATALINA_OUT，而run则会打印在终端上
elif [ "$1" = "start" ] ; then
  #对PIDFILE进行处理
  #判断CATALINA_PID配置项是否为空
  if [ ! -z "$CATALINA_PID" ]; then
  	#判断CATALINA_PID配置的文件是否存在
    if [ -f "$CATALINA_PID" ]; then
      #判断CATALINA_PID配置的文件是否存在且非空
      if [ -s "$CATALINA_PID" ]; then
        echo "Existing PID file found during start."
        #判断CATALINA_PID文件是否可读
        if [ -r "$CATALINA_PID" ]; then
          #读取PID并判断该PID是否有进程使用
          PID=`cat "$CATALINA_PID"`
          ps -p $PID >/dev/null 2>&1
          if [ $? -eq 0 ] ; then
            #$?获取上个命令\函数的返回值
            echo "Tomcat appears to still be running with PID $PID. Start aborted."
            echo "If the following process is not a Tomcat process, remove the PID file and try again:"
            ps -f -p $PID
            exit 1
          else
            echo "Removing/clearing stale PID file."
            #删除CATALINA_PID文件
            rm -f "$CATALINA_PID" >/dev/null 2>&1
            if [ $? != 0 ]; then
              if [ -w "$CATALINA_PID" ]; then
                #如果CATALINA_PID文件可写则置空
                cat /dev/null > "$CATALINA_PID"
              else
              	#CATALINA_PID存在且非空 删除失败 且没有写入权限 否则结束运行
                echo "Unable to remove or clear stale PID file. Start aborted."
                exit 1
              fi
            fi
          fi
        else
          #CATALINA_PID存在非空且不可读 否则结束运行
          echo "Unable to read PID file. Start aborted."
          exit 1
        fi
      else
      	#如果CATALINA_PID存在且为空 则尝试删除 如果删除失败 判断是否有写入权限 否则结束运行
        rm -f "$CATALINA_PID" >/dev/null 2>&1
        if [ $? != 0 ]; then
          if [ ! -w "$CATALINA_PID" ]; then
            echo "Unable to remove or write to empty PID file. Start aborted."
            exit 1
          fi
        fi
      fi
    fi
  fi

  shift
  touch "$CATALINA_OUT"
  if [ "$1" = "-security" ] ; then
    if [ $have_tty -eq 1 ]; then
      echo "Using Security Manager"
    fi
    shift
    eval $_NOHUP "\"$_RUNJAVA\"" "\"$LOGGING_CONFIG\"" $LOGGING_MANAGER $JAVA_OPTS $CATALINA_OPTS \
      -classpath "\"$CLASSPATH\"" \
      -Djava.security.manager \
      -Djava.security.policy=="\"$CATALINA_BASE/conf/catalina.policy\"" \
      -Dcatalina.base="\"$CATALINA_BASE\"" \
      -Dcatalina.home="\"$CATALINA_HOME\"" \
      -Djava.io.tmpdir="\"$CATALINA_TMPDIR\"" \
      org.apache.catalina.startup.Bootstrap "$@" start \
      >> "$CATALINA_OUT" 2>&1 "&"

  else
    eval $_NOHUP "\"$_RUNJAVA\"" "\"$LOGGING_CONFIG\"" $LOGGING_MANAGER $JAVA_OPTS $CATALINA_OPTS \
      -classpath "\"$CLASSPATH\"" \
      -Dcatalina.base="\"$CATALINA_BASE\"" \
      -Dcatalina.home="\"$CATALINA_HOME\"" \
      -Djava.io.tmpdir="\"$CATALINA_TMPDIR\"" \
      org.apache.catalina.startup.Bootstrap "$@" start \
      >> "$CATALINA_OUT" 2>&1 "&"

  fi
  #写入PID到PIDFILE
  if [ ! -z "$CATALINA_PID" ]; then
    echo $! > "$CATALINA_PID"
  fi

  echo "Tomcat started."
#对stop命令做处理
elif [ "$1" = "stop" ] ; then

  shift

  SLEEP=5
  if [ ! -z "$1" ]; then
    echo $1 | grep "[^0-9]" >/dev/null 2>&1
    if [ $? -gt 0 ]; then
      SLEEP=$1
      shift
    fi
  fi

  FORCE=0
  if [ "$1" = "-force" ]; then
    shift
    FORCE=1
  fi
  #如果存在PID则通过kill -0判断该PID是否存在
  if [ ! -z "$CATALINA_PID" ]; then
    if [ -f "$CATALINA_PID" ]; then
      if [ -s "$CATALINA_PID" ]; then
        kill -0 `cat "$CATALINA_PID"` >/dev/null 2>&1
        if [ $? -gt 0 ]; then
          echo "PID file found but no matching process was found. Stop aborted."
          exit 1
        fi
      else
        echo "PID file is empty and has been ignored."
      fi
    else
      echo "\$CATALINA_PID was set but the specified file does not exist. Is Tomcat running? Stop aborted."
      exit 1
    fi
  fi

  eval "\"$_RUNJAVA\"" $JAVA_OPTS \
    -classpath "\"$CLASSPATH\"" \
    -Dcatalina.base="\"$CATALINA_BASE\"" \
    -Dcatalina.home="\"$CATALINA_HOME\"" \
    -Djava.io.tmpdir="\"$CATALINA_TMPDIR\"" \
    org.apache.catalina.startup.Bootstrap "$@" stop

  # stop failed. Shutdown port disabled? Try a normal kill.
  # stop失败 则通过kill -15杀死进程
  if [ $? != 0 ]; then
    if [ ! -z "$CATALINA_PID" ]; then
      echo "The stop command failed. Attempting to signal the process to stop through OS signal."
      kill -15 `cat "$CATALINA_PID"` >/dev/null 2>&1
    fi
  fi

  #在一定SLEEP时间内判断PID进程是否已经结束 如果结束则清空PIDFILE 否则打印JAVA堆栈信息
  #kill -3 PID 打印JAVA堆栈信息 1 如果项目通过Tomcat进行发布 则对应的堆栈信息会打印在 catalina.out文件中 2 如果项目是基于SpringBoot并且使用nohup java -jar xxx.jar & 命令运行，则java堆栈信息会在对应的nohup.out文件中
  if [ ! -z "$CATALINA_PID" ]; then
    if [ -f "$CATALINA_PID" ]; then
      while [ $SLEEP -ge 0 ]; do
        kill -0 `cat "$CATALINA_PID"` >/dev/null 2>&1
        if [ $? -gt 0 ]; then
          rm -f "$CATALINA_PID" >/dev/null 2>&1
          if [ $? != 0 ]; then
            if [ -w "$CATALINA_PID" ]; then
              cat /dev/null > "$CATALINA_PID"
              # If Tomcat has stopped don't try and force a stop with an empty PID file
              FORCE=0
            else
              echo "The PID file could not be removed or cleared."
            fi
          fi
          echo "Tomcat stopped."
          break
        fi
        if [ $SLEEP -gt 0 ]; then
          sleep 1
        fi
        if [ $SLEEP -eq 0 ]; then
          echo "Tomcat did not stop in time."
          if [ $FORCE -eq 0 ]; then
            echo "PID file was not removed."
          fi
          echo "To aid diagnostics a thread dump has been written to standard out."
          kill -3 `cat "$CATALINA_PID"`
        fi
        SLEEP=`expr $SLEEP - 1 `
      done
    fi
  fi
  #到这一步程序没有停止运行则尝试使用kill -9杀死进程
  KILL_SLEEP_INTERVAL=5
  if [ $FORCE -eq 1 ]; then
    if [ -z "$CATALINA_PID" ]; then
      echo "Kill failed: \$CATALINA_PID not set"
    else
      if [ -f "$CATALINA_PID" ]; then
        PID=`cat "$CATALINA_PID"`
        echo "Killing Tomcat with the PID: $PID"
        kill -9 $PID
        while [ $KILL_SLEEP_INTERVAL -ge 0 ]; do
            kill -0 `cat "$CATALINA_PID"` >/dev/null 2>&1
            if [ $? -gt 0 ]; then
                rm -f "$CATALINA_PID" >/dev/null 2>&1
                if [ $? != 0 ]; then
                    if [ -w "$CATALINA_PID" ]; then
                        cat /dev/null > "$CATALINA_PID"
                    else
                        echo "The PID file could not be removed."
                    fi
                fi
                echo "The Tomcat process has been killed."
                break
            fi
            if [ $KILL_SLEEP_INTERVAL -gt 0 ]; then
                sleep 1
            fi
            KILL_SLEEP_INTERVAL=`expr $KILL_SLEEP_INTERVAL - 1 `
        done
        if [ $KILL_SLEEP_INTERVAL -lt 0 ]; then
            echo "Tomcat has not been killed completely yet. The process might be waiting on some system call or might be UNINTERRUPTIBLE."
        fi
      fi
    fi
  fi

elif [ "$1" = "configtest" ] ; then

    eval "\"$_RUNJAVA\"" $LOGGING_MANAGER $JAVA_OPTS \
      -classpath "\"$CLASSPATH\"" \
      -Dcatalina.base="\"$CATALINA_BASE\"" \
      -Dcatalina.home="\"$CATALINA_HOME\"" \
      -Djava.io.tmpdir="\"$CATALINA_TMPDIR\"" \
      org.apache.catalina.startup.Bootstrap configtest
    result=$?
    if [ $result -ne 0 ]; then
        echo "Configuration error detected!"
    fi
    exit $result

elif [ "$1" = "version" ] ; then

    "$_RUNJAVA"   \
      -classpath "$CATALINA_HOME/lib/catalina.jar" \
      org.apache.catalina.util.ServerInfo

else
# 没有匹配任何命令 默认打印提示信息
  echo "Usage: catalina.sh ( commands ... )"
  echo "commands:"
  if $os400; then
    echo "  debug             Start Catalina in a debugger (not available on OS400)"
    echo "  debug -security   Debug Catalina with a security manager (not available on OS400)"
  else
    echo "  debug             Start Catalina in a debugger"
    echo "  debug -security   Debug Catalina with a security manager"
  fi
  echo "  jpda start        Start Catalina under JPDA debugger"
  echo "  run               Start Catalina in the current window"
  echo "  run -security     Start in the current window with security manager"
  echo "  start             Start Catalina in a separate window"
  echo "  start -security   Start in a separate window with security manager"
  echo "  stop              Stop Catalina, waiting up to 5 seconds for the process to end"
  echo "  stop n            Stop Catalina, waiting up to n seconds for the process to end"
  echo "  stop -force       Stop Catalina, wait up to 5 seconds and then use kill -KILL if still running"
  echo "  stop n -force     Stop Catalina, wait up to n seconds and then use kill -KILL if still running"
  echo "  configtest        Run a basic syntax check on server.xml - check exit code for result"
  echo "  version           What version of tomcat are you running?"
  echo "Note: Waiting for the process to end and use of the -force option require that \$CATALINA_PID is defined"
  exit 1

fi

```
### 结束tomcat进程流程

脚本对tomcat进程的结束处理的比较优雅，先是通过PID判断进程是否存在，存在进程则先通过java程序内部来结束进程，如果停止失败再使用kill -15来停止进程，如果还结束进程失败，最后通过kill -9杀死进程

|  if判断   |      为ture的条件      |
| :-------: | :--------------------: |
|  -r FILE  |     文件存在且可读     |
|  -w FILE  |     文件存在且可写     |
|  -x FILE  |    文件存在且可执行    |
| -z STRING |       字符串为空       |
| -n STRING |       字符串非空       |
|  -f FILE  |  文件存在且是普通文件  |
|  -s FILE  |   文件存在且大小非0    |
|  -S FILE  | 文件存在且为套接字文件 |
|  -a FILE  |        文件存在        |
