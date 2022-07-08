---
title: NIO
tags: NIO&Netty
categories: NIO&Netty
---



# NIO(Windows Platform)

## 注意：Windows 不支持EPoll因此JDK中的native方法poll0底层的实现并非epoll而是IOCP(Select)

### Channel（数据通道）：

对应实现有：FileChannel DatagramChannel SocketChannel ServerSocketChannel

### Buffer（缓冲区）：
对应的实现有：ByteBuffer CharBuffer DoubleBuffer MappedByteBuffer 等

### Selector（数据通道事件轮询器）：
处理多个Channel，select()方法会一直阻塞到某个注册的通道有事件就绪，直到收到某个通道的事件，则进行对应的处理

![image-20200820203915453](/Users/yuner/Library/Mobile Documents/com~apple~CloudDocs/sourceCodeNotes/NIO.assets/image-20200820203915453.png)

## 源码解析
### ServerSocketChannel.open()

```java
ServerSocketChannel.class
    
public static ServerSocketChannel open() throws IOException {
    	//获取SelectorProvider对象，并通过该对象获取ServerSocketChannel
        return SelectorProvider.provider().openServerSocketChannel();
}
```
```java
SelectorProvider.class
//SelectorProvider对象构建过程
public static SelectorProvider provider() {
        synchronized (lock) {
            //加载过直接返回provider
            if (provider != null)
                return provider;
            return AccessController.doPrivileged(
                new PrivilegedAction<SelectorProvider>() {
                    public SelectorProvider run() {
                        	//如果Property配置了SelectorProvider的class则构建该Provider
                            if (loadProviderFromProperty())
                                return provider;
                        	//通过ServiceLoader加载“插件化”加入的provider
                            if (loadProviderAsService())
                                return provider;
                        	//通过DefaultSelectorProvider构建WindowsSelectorProvider
                            provider = sun.nio.ch.DefaultSelectorProvider.create();
                            return provider;
                        }
                    });
        }
}
```

```java
SelectorProviderImpl.class
//构建ServerSocketChannelImpl对象
public ServerSocketChannel openServerSocketChannel() throws IOException {
        return new ServerSocketChannelImpl(this);
}
```

总结：

1. 获取SelectorProvider，如果没有则进行构建
2. 构建过程首先检查Property是否有定义SelectorProvider Class，其次ServiceLoader加载SelectorProvider，如果都没有则通过DefaultSelectorProvider构建默认的WindowsSelectorProvider
3. 通过SelectorProvider构建ServerSocketChannel，实际构建的对象为ServerSocketChannelImpl

**注意：不同平台的JDK有不同的实现，Windows平台为ServerSocketChannelImpl，MacOS平台为KQueueSelectorImpl（KQueue类似于Epoll）**

### Selector.open()

```java
Selector.class

public static Selector open() throws IOException {
    //获取SelectorProvider,通过SelectorProvider构建Selector
    return SelectorProvider.provider().openSelector();
}
```

```java
WindowsSelectorProvider.class
    
public AbstractSelector openSelector() throws IOException {
        return new WindowsSelectorImpl(this);
}
```

总结：

1. 获取SelectorProvider，如果没有则进行构建
2. SelectorProvider构建过程同上
3. 通过SelectorProvider构建Selector，实际构建的对象为WindowsSelectorImpl

### ServerSocketChannel.register()

```java
AbstractSelectableChannel.class
    
public final SelectionKey register(Selector sel, int ops,
                                       Object att)
        throws ClosedChannelException
    {
        synchronized (regLock) {
            if (!isOpen())
                throw new ClosedChannelException();
            if ((ops & ~validOps()) != 0)
                throw new IllegalArgumentException();
            if (blocking)
                throw new IllegalBlockingModeException();
            //获取SelectionKey
            SelectionKey k = findKey(sel);
            if (k != null) {
                //存在则进行设置
                k.interestOps(ops);
                k.attach(att);
            }
            //不存在则进行构建并保存
            if (k == null) {
                // New registration
                synchronized (keyLock) {
                    if (!isOpen())
                        throw new ClosedChannelException();
                    k = ((AbstractSelector)sel).register(this, ops, att);
                    addKey(k);
                }
            }
            return k;
        }
    }
```

```java
SelectorImpl.class
    
protected final SelectionKey register(AbstractSelectableChannel var1, int var2, Object var3) {
        if (!(var1 instanceof SelChImpl)) {
            throw new IllegalSelectorException();
        } else {
            //构建对象
            SelectionKeyImpl var4 = new SelectionKeyImpl((SelChImpl)var1, this);
            var4.attach(var3);
            synchronized(this.publicKeys) {
                //在WindowsSelectorImpl中对SelectionKey进行维护
                //比如，对threadsCount进行累加，以便下文Selector.select()调整线程数量
                this.implRegister(var4);
            }

            var4.interestOps(var2);
            return var4;
        }
    }
```



### Selector.select()

```java
protected int doSelect(long var1) throws IOException {
    if (this.channelArray == null) {
        throw new ClosedSelectorException();
    } else {
        this.timeout = var1;
        this.processDeregisterQueue();
        if (this.interruptTriggered) {
            this.resetWakeupSocket();
            return 0;
        } else {
            //调整线程数量，register多少个Selector以及OPS就应该有多少个线程
            //每个线程都会维护SubSelector，不停的调用其poll()方法，等待内核回调事件
            this.adjustThreadsCount();
            this.finishLock.reset();
            this.startLock.startThreads();

            try {
                this.begin();

                try {
                    //不停的调用poll()方法，等待内核回调事件
                    this.subSelector.poll();
                } catch (IOException var7) {
                    this.finishLock.setException(var7);
                }

                if (this.threads.size() > 0) {
                    this.finishLock.waitForHelperThreads();
                }
            } finally {
                this.end();
            }

            this.finishLock.checkForException();
            this.processDeregisterQueue();
            //查询所有线程的SubSelectort通过readFds、writeFds、exceptFds统计产生的事件总和
            //并获取对应的SelectionKey，设置其可读/可写状态，加入SelectorImpl selectedKeys（Set<SelectionKey>）等待被处理
            int var3 = this.updateSelectedKeys();
            this.resetWakeupSocket();
            //返回事件数量，因为poll0存在超时时间的设置，所以如果超时则事件数量是0
            return var3;
        }
    }
}
```

总结：

1. Selector.select()核心就是调用WindowsSelectorImpl.SubSelector的poll()方法，该方法调用native方法poll0，传入readFds、writeFds、exceptFds三个文件描述符数组，用于承接产生事件的文件描述符
2. poll0将会一直阻塞，直到内核发现有读写事件，如果产生了读写事件则往readFds、 writeFds,、exceptFds中添加产生可读可写事件对应的文件描述符
3. updateSelectedKeys()方法中根据1以及2中提到的文件描述符数组来统计事件数量，获取SelectionKeyImpl设置对应的可读可写状态，并添加至：SelectorImpl selectedKeys（Set<SelectionKey>）以供接下来的事件处理

**注意：windows平台上readFds writeFds exceptFds数组最大为1025 限制了性能**

### SocketChannel.read()

```java
public int read(ByteBuffer var1) throws IOException {
       ......
       do {
           //核心方法调用IOUtil read 通过对应的文件描述符读取数据到ByteBuffer
           var3 = IOUtil.read(this.fd, var1, -1L, nd);
       } while(var3 == -3 && this.isOpen());
		......
    }
```

总结:

1. 调用IOUtil read 通过对应的文件描述符读取数据到ByteBuffer

## TCP Example

```java
public static void clientCode(){
        ByteBuffer buffer = ByteBuffer.allocate(1024);
        SocketChannel socketChannel = null;
        try{
            socketChannel = SocketChannel.open();
            socketChannel.configureBlocking(false);
            socketChannel.connect(new InetSocketAddress("ip",port));
            if(socketChannel.finishConnect()){
                int i=0;
                while(true){
                    TimeUnit.SECONDS.sleep(1);
                    String info = "I'm "+i+++"-th information from client";
                    buffer.clear();
                    buffer.put(info.getBytes());
                    buffer.flip();
                    while(buffer.hasRemaining()){
                        System.out.println(buffer);
                        socketChannel.write(buffer);
                    }
                }
            }
        }
        catch (IOException | InterruptedException e){
            e.printStackTrace();
        } finally{
            try{
                if(socketChannel!=null){
                    socketChannel.close();
                }
            }catch(IOException e){
                e.printStackTrace();
            }
        }
    }
```

```java
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