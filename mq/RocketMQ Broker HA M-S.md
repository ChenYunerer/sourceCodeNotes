---
title: RocketMQ Broker HA M-S
data: 2020-10-13 23:25:28
---
# RocketMQ Broker HA Master-Slave

**源码基于：4.7.1**

RocketMQ支持

1. 多Master多Slave模式-同步双写
2. 多Master多Slave模式-异步双写

同步与异步的差别就在于，broker是否要在同步slave到之后返回ack

```java
CommitLog.class
  
public void handleHA(AppendMessageResult result, PutMessageResult putMessageResult, MessageExt messageExt) {
  	//判断当前broker是否是master节点，只有是master节点才做主从复制
    if (BrokerRole.SYNC_MASTER == this.defaultMessageStore.getMessageStoreConfig().getBrokerRole()) {
        HAService service = this.defaultMessageStore.getHaService();
        if (messageExt.isWaitStoreMsgOK()) {
            // Determine whether to wait
            if (service.isSlaveOK(result.getWroteOffset() + result.getWroteBytes())) {
                GroupCommitRequest request = new GroupCommitRequest(result.getWroteOffset() + result.getWroteBytes());
                service.putRequest(request);
                service.getWaitNotifyObject().wakeupAll();
                PutMessageStatus replicaStatus = null;
                try {
                    replicaStatus = request.future().get(this.defaultMessageStore.getMessageStoreConfig().getSyncFlushTimeout(),
                            TimeUnit.MILLISECONDS);
                } catch (InterruptedException | ExecutionException | TimeoutException e) {
                }
                if (replicaStatus != PutMessageStatus.PUT_OK) {
                    log.error("do sync transfer other node, wait return, but failed, topic: " + messageExt.getTopic() + " tags: "
                        + messageExt.getTags() + " client address: " + messageExt.getBornHostNameString());
                    putMessageResult.setPutMessageStatus(PutMessageStatus.FLUSH_SLAVE_TIMEOUT);
                }
            }
            // Slave problem
            else {
                // Tell the producer, slave not available
                putMessageResult.setPutMessageStatus(PutMessageStatus.SLAVE_NOT_AVAILABLE);
            }
        }
    }

}
```

