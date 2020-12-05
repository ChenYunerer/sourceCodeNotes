---
title: Striped64&LongAdder
tags: Sentinel
categories: Sentinel
---



# Striped64 & LongAdder

JUC提供的高并发优化的累加器

## Striped64字段说明

```java
/** Number of CPUS, to place bound on table size */
//CPU数量
static final int NCPU = Runtime.getRuntime().availableProcessors();

/**
 * Table of cells. When non-null, size is a power of 2.
 * 如果存在竞争，则获取当前线程对应的Cell对该Cell的value进行累加
 */
transient volatile Cell[] cells;

/**
 * Base value, used mainly when there is no contention, but also as
 * a fallback during table initialization races. Updated via CAS.
 * 基础指，当不存在竞争情况是，直接对base进行累加，否则操作Cells
 */
transient volatile long base;

/**
 * Spinlock (locked via CAS) used when resizing and/or creating Cells.
 * 标记cells是否被占用 0 空闲 1 被占用
 */
transient volatile int cellsBusy;
```

## Striped64 Cell

```java
/**
 * Padded variant of AtomicLong supporting only raw accesses plus CAS.
 *
 * JVM intrinsics note: It would be possible to use a release-only
 * form of CAS here, if it were provided.
 */
@jdk.internal.vm.annotation.Contended static final class Cell {
  	//维护一个value字段
    volatile long value;
    Cell(long x) { value = x; }
  	//提供对value的CAS操作
    final boolean cas(long cmp, long val) {
        return VALUE.compareAndSet(this, cmp, val);
    }
    final void reset() {
        VALUE.setVolatile(this, 0L);
    }
    final void reset(long identity) {
        VALUE.setVolatile(this, identity);
    }
    final long getAndSet(long val) {
        return (long)VALUE.getAndSet(this, val);
    }

    // VarHandle mechanics value字段的Hadnler
    private static final VarHandle VALUE;
    static {
        try {
            MethodHandles.Lookup l = MethodHandles.lookup();
            VALUE = l.findVarHandle(Cell.class, "value", long.class);
        } catch (ReflectiveOperationException e) {
            throw new ExceptionInInitializerError(e);
        }
    }
}
```

## longAccumulate 针对Long类型的累加

```java
//wasUncontended表示在调用该方法前的CAS操作是否存在竞争，true表示不存在竞争 false表示存在竞争
final void longAccumulate(long x, LongBinaryOperator fn,
                          boolean wasUncontended) {
    //获取线程的probe值，如果为0则进行初始化，probe指的是线程的threadLocalRandomProbe变量
  	//下文会根据probe值来计算该线程所对应的cell的index
  	//如果h为0则表示该线程第一次进入该方法，如果非0则表示该线程之前执行过该方法
  	int h;
    if ((h = getProbe()) == 0) {
        ThreadLocalRandom.current(); // force initialization
        h = getProbe();
        wasUncontended = true;
    }
    boolean collide = false;                // True if last slot nonempty
    done: for (;;) {
      	//cs： cells ；c: 线程对应的cell ；n： cs length ；v： c value
        Cell[] cs; Cell c; int n; long v;
      	//如果cs不等于null且长度不为0则表示cells被初始化过，可以直接使用
        if ((cs = cells) != null && (n = cs.length) > 0) {
          	//经过计算【(n - 1) & h】拿到线程对应index的cell
          	//如果该cell为null则创建cell填入cells的该index
            if ((c = cs[(n - 1) & h]) == null) {
              	//如果cellsBusy为0则表示cells不存在竞争可以进行操作
                if (cellsBusy == 0) {       // Try to attach new Cell
                  	//create new Cell，init cell as x
                    Cell r = new Cell(x);   // Optimistically create
                  	//再次判断cellBusy，判断cells是否存在竞争
                  	//如果不存在竞争则尝试通过CAS操作将cellsBusy置为1
                    if (cellsBusy == 0 && casCellsBusy()) {
                        try {               // Recheck under lock
                            Cell[] rs; int m, j;
                          	//如果此时cells不为空，长度不为0，当前线程对应的cell为null，则进行填充
                            if ((rs = cells) != null &&
                                (m = rs.length) > 0 &&
                                rs[j = (m - 1) & h] == null) {
                                rs[j] = r;
                                break done;
                            }
                        } finally {
                          	//最后将cellsBusy设置为0，表示处理结束
                            cellsBusy = 0;
                        }
                        continue;           // Slot is now non-empty
                    }
                }
                collide = false;
            }
            else if (!wasUncontended)       // CAS already known to fail
              	//表示之前CAS存在竞争，直接将wasUncontended设置成true，等待下文advanceProbe后重试
                wasUncontended = true;      // Continue after rehash
            else if (c.cas(v = c.value,
                           (fn == null) ? v + x : fn.applyAsLong(v, x)))
              	//线程对应的cell非null，则尝试对该cell进行操作
              	//使用cas操作，对c.value进行操作，如果fn转换方法非空则尝试使用fn进行转换
              	//否则直接进行v+x的加操作
                break;
            else if (n >= NCPU || cells != cs)
              	//如果cells数组的长度已经到了最大值（大于等于cup数量），或者是当前cells已经做了扩容
              	//则将collide设置为false，后面重新计算prob的值
                collide = false;            // At max size or stale
            else if (!collide)
                collide = true;
            else if (cellsBusy == 0 && casCellsBusy()) {
              	//尝试对cells进行扩容，每次扩容长度为原来的2倍
                try {
                    if (cells == cs)        // Expand table unless stale
                        cells = Arrays.copyOf(cs, n << 1);
                } finally {
                    cellsBusy = 0;
                }
                collide = false;
                continue;                   // Retry with expanded table
            }
          	//重新设置线程的probe
            h = advanceProbe(h);
        }
        else if (cellsBusy == 0 && cells == cs && casCellsBusy()) {
          	//如果cells为null，则对cells进行初始化，初试大小为2
            try {                           // Initialize table
                if (cells == cs) {
                    Cell[] rs = new Cell[2];
                    rs[h & 1] = new Cell(x);
                    cells = rs;
                    break done;
                }
            } finally {
                cellsBusy = 0;
            }
        }
        // Fall back on using base
        else if (casBase(v = base,
                         (fn == null) ? v + x : fn.applyAsLong(v, x)))
          	//直接对base变量进行cas操作
            break done;
    }
}
```

## LongAdder

```java
public void add(long x) {
    Cell[] cs; long b, v; int m; Cell c;
  	//1.如果cells为null，则尝试直接CAS操作base，如果CAS操作失败则进一步操作
  	//2.如果cells不为null，则进一步操作
    if ((cs = cells) != null || !casBase(b = base, b + x)) {
      	//uncontended表示是否存在竞争 true表示不存在竞争 false表示存在竞争
        boolean uncontended = true;
      	//1.cs == null 表示cells未初始化
      	//2.(m = cs.length - 1) < 0 表示cells未初始化
      	//3.(c = cs[getProbe() & m]) == null 表示cells初始化 当前线程对应的cell为null
      	//4.!(uncontended = c.cas(v = c.value, v + x)) 表示当前线程对应的cell已经初始化，则进行cas操作
      	if (cs == null || (m = cs.length - 1) < 0 ||
            (c = cs[getProbe() & m]) == null ||
            !(uncontended = c.cas(v = c.value, v + x)))
            longAccumulate(x, null, uncontended);
    }
}
```

```java
//所有Cell的value+base才是完全的累积值
public long sum() {
    Cell[] cs = cells;
    long sum = base;
    if (cs != null) {
        for (Cell c : cs)
            if (c != null)
                sum += c.value;
    }
    return sum;
}
```

## 总结

Striped64类似于分段锁的设计，使用CAS操作更进一步降低竞争成本，提高性能。

在进行累加时，将累加操作拆分为多个操作：

1. 对base的CAS操作

2. 对线程对应的Cell的value的CAS操作

等于将累加值记录到base中以及多个cell的value中，来计算SUM值的时候，需要将base和所有的cell的value累加，等于是以空间换时间的做法提升性能。

