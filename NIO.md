# NIO

### Channel（数据通道）：
对应实现有：FileChannel DatagramChannel SocketChannel ServerSocketChannel

### Buffer（缓冲区）：
对应的实现有：ByteBuffer CharBuffer DoubleBuffer MappedByteBuffer 等

### Selector（数据通道事件轮询器）：
处理多个Channel，select()方法会一直阻塞到某个注册的通道有事件就绪，直到收到某个通道的事件，则进行对应的处理

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
            this.adjustThreadsCount();
            this.finishLock.reset();
            this.startLock.startThreads();

            try {
                this.begin();

                try {
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
            int var3 = this.updateSelectedKeys();
            this.resetWakeupSocket();
            return var3;
        }
    }
}
```

### SocketChannel.read()