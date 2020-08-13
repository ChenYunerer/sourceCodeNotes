# Mysql Innodb

## 体系结构

![image-20200812220144238](Mysql innodb.assets/image-20200812220144238.png)

组成部分：

1. 连接池组件
2. 管理服务和工具组件
3. SQL接口组件
4. 查询分析器组件
5. 优化器组件
6. 缓冲组件
7. 插件式存储引擎
8. 物理文件

## 存储引擎

### InnoDB（默认）

支持事务，支持行锁，支持外键，支持非锁定读；

表文件单独存放在独立的idb文件中；

支持MVCC多版本并发控制，实现了SQL标准的4种隔离级别

支持next-key locking，避免幻读

提供插入缓冲（insert buffer），二次写（double write），自适应哈希索引（adaptive hash index），预读（read ahead）等高性能高可用功能

采用聚集（clustered）的方式存储数据：每张表的数据都按照主键顺序进行存放，如果没有显式的定义主键，innodb会为该表生成一个6字节的ROWID作为主键

### MyISAM

不支持事务，不支持表锁和全文索引，但是对于一些OLAP（Online Analytical Processing 在线分析处理）场景下操作速度快

MyISAM存储引擎表由MYD和MYI组成，MYD存放数据文件，MYI存放索引文件，数据文件还可以通过myisampack工具来进行压缩，压缩后的表是只读的，也可以通过myisampack来解压，可以用于一些存档数据（只查不改）的查询，速度快，数据占用空间小

### NDB

NDB是集群存储引擎，NDB数据全部存放于内存中（5.1版本开始非索引数据可以存放在磁盘上），因此主键查询速度极快

可以通过增加集群节点数，线性提高性能

### Memory

表中的数据全部存放在内存中，查询速度极快，数据库重启或是宕机则数据丢失，可以用于存放临时数据

默认使用哈希索引

## 数据库连接方式

1. TCP/IP
2. 命名管道和共享内存（数据库和连接进程处于同一台机器（windows），可以通过该方式进行连接）
3. Unix域套接字（数据库和连接进程处于同一台机器（Linux或Unix），可以通过该方式进行连接）

## InnoDB

### 体系架构

![image-20200812222309186](Mysql innodb.assets/image-20200812222309186.png)

### 后台线程

1. IO thread
   1. insert buffer thread
   2. log thread
   3. read thread
   4. write thread
2. Master thread
3. 锁监控线程
4. 错误监控线程
#### Master thread

Master thread内部由几个循环组成：

1. 主循环loop
2. 后台循环background loop
3. 刷新循环flush loop
4. 暂停循环suspend loop

master thread根据数据库运行状态进在4种循环中进行切换

##### 主循环loop

大多数操作都发生在主循环中，按照时间可以分为每秒的操作和每10秒的操作

每秒一次的操作包括：

1. 总是对日志缓冲进行落盘（不管事务是否已经提交都进行日志落盘，这可以保证长事务在最后提交的时候响应也非常快速）

 	2. 可能合并插入缓冲（innodb会根据当前1秒内的IO情况进行判定是否进行合并插入缓冲，如果innodb认为当前IO压力小，则会进行合并插入缓冲）
 	3. 可能对缓冲池中的脏页进行落盘（刷新做多100个脏页，当脏页数量超过配置的百分比阈值（buf_get_modified_ratio_pact）则进行落盘）
 	4. 可能切换到后台循环background loop

每10秒的操作包括：

1. 刷新100个脏页（可能）
2. 合并之多5个插入缓冲（总是）
3. 将日志缓冲刷新到磁盘（总是）
4. 删除无用的undo页（总是）
5. 刷新100个或是10个脏页到磁盘（总是）
6. 产生一个检查点checkpoint（总是）

##### 后台循环background loop

当数据库空闲或是数据库关闭时，会进入该循环，该循环执行以下操作：

1. 总是删除无用的undo页

2. 总是合并20个插入缓冲

3. 总是跳回到主循环

4. 不断刷新100个脏页，直到符合条件（使得脏页占比小于阈值）（可能由flush loop来做这一步）

##### 刷新循环flush loop

1. 不断刷新100个脏页，直到符合条件（使得脏页占比小于阈值）

### 内存

![image-20200812223645778](Mysql innodb.assets/image-20200812223645778.png)

可以通过配置文件中的：innodb_buffer_pool_size 和 innodb_log_buffer_size的大小决定

#### 缓冲池buffer pool

用于存放各种数据的缓存，以Page页的方式管理数据，一页为16K。

通过LRU（最近最少使用）算法来保留数据或是删除数据。

每次修改数据先修改缓存池中的数据，然后在落盘，还未落盘的数据称为脏页

可以通过命令：SHOW ENGINE INNODB STATUS来查看innodb_buffer_pool的使用情况

#### 重做日志缓冲池redo log buffer

用于存储redo log，一般该内存区域不用特别大，因为redo log会按照每一秒进行落盘，只要保证每秒产生的事务量在这个缓冲大小内就可以

#### 额外的内存池additional memory pool

不太关注，不管了



### 关键特性

1. 插入缓冲 Insert Buffer
2. 两次写 Double Write
3. 自适应哈希索引 Adaptive Hash Index
4. 异步IO Async IO
5. 刷新邻接页 Flush Neighbor Page

#### 插入缓冲Insert Buffer

Insert Buffer：

对于插入的数据，主键自增的情况下，对于聚集索引页来说是顺序写入

对于非聚集索引页（辅助索引页）来说，如果辅助索引是非唯一的，则先判断非聚集索引页是否存在缓存中，如果存在则直接进行插入，如果不在则将插入数据放入Insert Buffer中，然后通过一定的频率进行Insert Buffer和辅助索引的合并操作。这时通常能将多个插入合并到一个操作中，提高非聚集索引的插入性能。

对于非聚集索引来说，如果辅助索引是唯一的，则需要访问所有该非聚集索引页来判断唯一情况。通常是随机访问，这也是由于B+树的特性决定的。

Change Buffer：

IChange Buffer是nsert Buffer的升级，可以对Insert Delte Update 进行缓冲，分别对应Insert Buffer，Delete Buffer，Purge Buffer。生效条件依旧是非聚集索引（辅助索引）且非唯一

#### 两次写Double Write

![image-20200814000213490](Mysql innodb.assets/image-20200814000213490.png)

脏页进行落盘的时候，为避免写入部分数据时宕机（部分写失效），引入Double Write机制，落盘的时候先将脏页复制到Double Write Buffer（2M大小）然后由Double Write Buffer分2次每次1M大小顺序的写入共享表空间，再将Double Write Buffer中的页写入各个表空间文件中。

#### 自适应哈希索引Adaptive Hash Index（AHI）

哈希索引的时间复杂度为O1，查询次数为1次，而B+树的查询次数由其高度决定。

InnoDB会监控对表上个***索引页***的查询，如果发现改用哈希索引能带来性能提升，则将B+树索引改为哈希索引。

AHI要求：
