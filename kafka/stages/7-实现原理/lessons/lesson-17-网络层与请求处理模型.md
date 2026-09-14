# 课 17：网络层与请求处理模型

> 所属阶段：阶段 7（实现原理）· 第 1 课
> 实测环境：3 节点 KRaft 集群（`apache/kafka:4.0.0`）+ JMX Exporter + Prometheus，Windows WSL Docker
> 全部数值均为本机实测，非纸面推演

---

## 第一幕：场景引入——「带宽没跑满，为什么吞吐上不去？」

你接手了一个 Kafka 集群，业务方反馈：

> 「我们给 broker 配了万兆网卡，但实际吞吐卡在 33 MB/s 就上不去了。CPU 也不高，磁盘也没满，网络监控显示带宽只用了一小部分。」

你登上看，确实：

```text
20000 records sent, 33955.9 records/sec (33.16 MB/sec), 160.90 ms avg latency
```

33 MB/s —— 离万兆网卡的理论上限差了两个数量级。

**问题出在哪？**

一种常见的错误反应是「加机器」。但在加机器之前，你得先能回答一个更基本的问题：**一个请求从网卡进来，到落盘，中间经过了哪些环节？**

这就是本课要解决的：**Kafka 的网络层与请求处理模型**。

---

## 第二幕：认知冲突——「一个连接一个线程」的直觉为什么是错的

### 2.1 你的直觉可能是这样

学过网络编程的人，第一反应通常是 BIO 模型：

```text
while (true) {
    Socket conn = serverSocket.accept();   // 阻塞等连接
    new Thread(() -> handle(conn)).start(); // 来一个连接开一个线程
}
```

这个模型简单直观，但有个致命问题：**连接数和线程数是 1:1 的**。

一个 Kafka 集群要面对什么量级的连接？

- 几十个 producer 实例
- 上百个 consumer 实例（一个消费组就可能有几十个成员）
- 每个 broker 还要和其他 broker 维持连接（副本拉取）
- 各种运维工具、监控探针

轻轻松松上千个连接。**开一千个线程，光上下文切换就把 CPU 吃光了**。

### 2.2 官方怎么说

Kafka 官方对网络层的描述（[Network Layer](https://kafka.apache.org/43/implementation/network-layer/)）极其简短，原文是：

> The network layer is a fairly straight-forward NIO server, and will not be described in great detail. The sendfile implementation is done by giving the `TransferableRecords` interface a `writeTo` method. This allows the file-backed message set to use the more efficient `transferTo` implementation instead of an in-process buffered write. **The threading model is a single acceptor thread and N processor threads which handle a fixed number of connections each.** This design has been pretty thoroughly tested elsewhere and found to be simple to implement and fast. **The protocol is kept quite simple to allow for future implementation of clients in other languages.**

注意官方的语气："will not be described in great detail"（不打算细讲）——因为这是个**成熟且标准**的设计，不是 Kafka 独创。

这句话里有三个关键信息：

1. **NIO**（非阻塞 IO），不是 BIO
2. **1 个 acceptor 线程 + N 个 processor 线程**，每个 processor 管固定数量的连接
3. 协议**刻意保持简单**，为的是让别人能用别的语言写客户端

第三点常被忽略，但它解释了 Kafka 生态为什么繁荣——协议简单到社区能轻松实现 [librdkafka（C/C++）](https://github.com/confluentinc/librdkafka)、[confluent-kafka-go](https://github.com/confluentinc/confluent-kafka-go)、[kafka-python](https://github.com/dpkp/kafka-python) 等几十种语言的客户端。

### 2.3 冲突的核心

| 你的直觉 | Kafka 的实际做法 |
|---------|-----------------|
| 一个连接一个线程 | 一个 processor 线程管**一批**连接 |
| 线程内完成读+处理+写 | 读/写由 processor 做，**处理交给另一组线程** |
| 阻塞等待 | 全程非阻塞（NIO + Selector） |

关键在于：**网络 IO 和请求处理被拆成了两组不同的线程**。为什么？因为它们的瓶颈性质完全不同——网络 IO 是 IO 密集，请求处理（尤其是落盘）涉及磁盘和锁。混在一起会互相拖累。

---

## 第三幕：层层揭示

### 3.1 一句话定义

> Kafka 的网络层是一个 **Reactor 模式的 NIO 服务器**：1 个 acceptor 线程负责接连接，N 个 processor 线程负责读写（每个管一批连接），M 个 request handler 线程负责真正的业务处理，中间用一个请求队列解耦。

### 3.2 直觉建立：餐厅模型

把这个模型想成一家餐厅：

```mermaid
flowchart LR
    C["顾客<br/>（客户端连接）"] --> A["领位员 ×1<br/>acceptor 线程<br/>只负责安排座位"]
    A --> P["服务员 ×N<br/>processor 线程<br/>每人管固定几桌"]
    P -->|"下单<br/>（请求队列）"| K["后厨 ×M<br/>request handler 线程<br/>真正做菜"]
    K -->|"出菜<br/>（响应队列）"| P
    P --> C
    style A stroke:#d29922,stroke-width:2px
    style K stroke:#da3633,stroke-width:2px
```

- **领位员（acceptor）**：只有 1 个，因为「接客」这个动作很快，一个人够用。他不做菜，也不点单。
- **服务员（processor）**：有 N 个，每人固定负责几桌。他负责「听顾客说什么」（读请求）和「把菜端上去」（写响应），但**不做菜**。
- **后厨（request handler）**：有 M 个，真正干活（校验、落盘、查数据）。
- **下单窗口（请求队列）**：服务员把单子放这儿，后厨按顺序取。**这个队列是解耦的关键**——服务员不用等菜做好就能去服务下一桌。

对应到 Kafka 的配置项：

| 餐厅角色 | Kafka 组件 | 配置参数 | 默认值 |
|---------|-----------|---------|-------|
| 领位员 | Acceptor 线程 | （固定 1 个，不可配） | 1 |
| 服务员 | Processor 线程 | `num.network.threads` | **3** |
| 后厨 | Request Handler 线程 | `num.io.threads` | **8** |
| 下单窗口 | 请求队列 | `queued.max.requests` | 500 |
| 单份订单上限 | 单请求最大字节 | `socket.request.max.bytes` | 104857600（100MB） |

### 3.3 核心原理：请求的一生

一个 Produce 请求从进来到响应出去，完整链路：

```mermaid
flowchart TD
    S["客户端发送 Produce 请求"] --> N1["① 网卡 → Socket 接收缓冲"]
    N1 --> N2["② Processor 线程<br/>Selector 轮询到可读事件"]
    N2 --> N3["③ 读取并解析请求头<br/>（含 API Key + version）"]
    N3 --> N4["④ 放入 RequestChannel 请求队列"]
    N4 --> N5["⑤ IO 线程从队列取出"]
    N5 --> N6["⑥ 校验 + 追加到分区日志<br/>（顺序写 page cache）"]
    N6 --> N7["⑦ 副本同步（follower 拉取）"]
    N7 --> N8["⑧ 按 acks 策略决定何时响应"]
    N8 --> N9["⑨ 响应放入 processor 的响应队列"]
    N9 --> N10["⑩ Processor 写回客户端<br/>（零拷贝 sendfile）"]
    style N4 stroke:#d29922,stroke-width:2px
    style N6 stroke:#da3633,stroke-width:2px
    style N10 stroke:#238636,stroke-width:2px
```

**第④步的队列是整条链路的咽喉**。所有性能问题排查，第一个要看的就是这个队列有没有积压。

### 3.4 实测：线程数与空闲比

我们用课 15 搭的 3 节点集群实测。

**第一步：确认 processor 线程数量**

```bash
curl -s http://localhost:17071/metrics | grep -E 'kafka_network_processor_idlepercent' | grep -v '^#'
```

实测输出：

```text
kafka_network_processor_idlepercent{networkprocessor="0"} 1.0
kafka_network_processor_idlepercent{networkprocessor="1"} 1.0
kafka_network_processor_idlepercent{networkprocessor="2"} 1.0
```

**只有 3 个 processor（编号 0/1/2）**，正好印证 `num.network.threads` 默认值 3。空闲比都是 **1.0**（100% 空闲）——因为此刻没有流量。

> 📌 若你的 exporter 配置没有为该指标声明 `labels`，输出会是带 `_objectname` 的长格式（如 `kafka_network_processor_idlepercent{_objectname="kafka.network<type=Processor, name=IdlePercent, networkProcessor=0><>Value"}`）。**两种格式等价，关键看 `networkProcessor` 的取值有几个。**

**第二步：打流量，看空闲比怎么变**

```bash
docker exec l15-kafka-1 bash -c 'export PATH=/opt/kafka/bin:$PATH; unset KAFKA_JMX_OPTS
kafka-producer-perf-test.sh --topic net-demo --num-records 20000 --record-size 1024 \
  --throughput -1 --producer-props bootstrap.servers=kafka-1:9092 acks=1'
```

实测结果：

```text
20000 records sent, 33955.9 records/sec (33.16 MB/sec),
160.90 ms avg latency, 256.00 ms max latency,
180 ms 50th, 238 ms 95th, 250 ms 99th, 255 ms 99.9th.
```

压测后指标：

```text
kafka_network_socketserver_networkprocessoravgidlepercent  1.0        ← processor 依然空闲
kafka_network_requestchannel_requestqueuesize              0.0        ← 队列零积压
```

**这个结果本身就是答案**：processor 空闲比 1.0、队列 0 积压 —— 说明**瓶颈根本不在网络层**。33 MB/s 是**客户端单线程压测**的上限，不是集群的上限。

这正是本课最重要的思维方式：**在调任何参数之前，先用指标确认瓶颈在不在你以为的地方。**

### 3.5 ⚠️ 实测踩坑：`RequestHandlerAvgIdlePercent` 是个陷阱

这是本课最值得记住的实测发现。

很多教程、博客都会告诉你：「监控 `RequestHandlerAvgIdlePercent`，低于 0.3 说明 IO 线程不够」。

我们照做，查到的值是：

```text
kafka_server_kafkarequesthandlerpool_requesthandleravgidlepercent  6.122678585934E12
```

**6.1 万亿。** 一个「比率」怎么会是 6.1e12？

如果你照着教程配 `RequestHandlerAvgIdlePercent < 0.3` 告警，**永远都不会触发**，而你会误以为「IO 线程很健康」。

**根因是什么？** 先看 HELP 行：

```text
# HELP kafka_server_kafkarequesthandlerpool_requesthandleravgidlepercent
  Attribute exposed for management
  kafka.server:name=RequestHandlerAvgIdlePercent,type=KafkaRequestHandlerPool,attribute=Count
                                                                                    ^^^^^
```

**`attribute=Count`** —— exporter 取的是这个 MBean 的 **Count 属性**，不是 Value。

为什么？因为我们的 exporter 配置末尾有一条兜底规则：

```yaml
  - pattern: 'kafka.(\w+)<type=(.+), name=(.+)><>(Value|Count)'
    name: kafka_$1_$2_$3
```

`(Value|Count)` 两个属性都可能匹配，而这个 MBean 在本环境中**只暴露了 Count 一个属性**（我们实测确认：exporter 输出里只有一条 requesthandler 记录，没有 Value 版本）。

**它到底是什么语义？** 连续采样 5 次，每 3 秒一次：

```text
sample 1: 2.36489227576E11
sample 2: 2.42772197115E11
sample 3: 2.49134616829E11
sample 4: 2.55369948383E11
sample 5: 2.61778758301E11
```

**严格单调递增**，每次约 +6.3e9。这是**累积计数**（纳秒级累计空闲时间的量级），不是比率。

对照组 `NetworkProcessorAvgIdlePercent` 同期稳定在 `0.9997967698116609` ~ `1.0` —— 这才是真正的 0~1 比率。

**结论与替代方案**：

| 想监控什么 | 别用 | 改用 |
|-----------|------|------|
| IO 线程是否够用 | ~~`RequestHandlerAvgIdlePercent`~~（本环境是累积计数） | `RequestQueueSize`（队列积压）+ `TotalTimeMs`（请求总耗时） |
| 网络线程是否够用 | — | `kafka_network_processor_idlepercent`（实测正常，0~1） |
| 请求是否积压 | — | `kafka_network_requestchannel_requestqueuesize`（实测 0.0） |

> 📌 **通用教训**：**任何指标在写进告警规则之前，先 curl 一次看它的实际值和 HELP 行**。值与语义不符（比率却很大、计数却会下降）时，先查 `attribute=` 是 Count 还是 Value。这条比记住某个具体指标名重要得多。

### 3.6 零拷贝：为什么 Kafka 能扛住高吞吐

回到官方那段话的第二句：

> The sendfile implementation is done by giving the `TransferableRecords` interface a `writeTo` method. This allows the file-backed message set to use the more efficient `transferTo` implementation instead of an in-process buffered write.

消费者拉数据时，数据在**磁盘上的日志文件**里。传统做法：

```text
磁盘 → 内核缓冲区 → 用户空间缓冲区 → Socket 缓冲区 → 网卡
       （DMA拷贝）    （CPU拷贝）      （CPU拷贝）
```

4 次拷贝，2 次 CPU 参与，2 次上下文切换。

零拷贝（`sendfile` / `transferTo`）：

```text
磁盘 → 内核缓冲区 → 网卡
       （DMA拷贝）   （DMA拷贝）
```

2 次拷贝，**0 次 CPU 拷贝**。

这就是课 4 讲过的零拷贝在网络层的落地。官方特意指出这个能力是通过给 `TransferableRecords` 接口加 `writeTo` 方法实现的——**让「文件支撑的消息集」自己决定怎么写出去**，而不是由调用方统一 `read()` 再 `write()`。

> ⚠️ **边界说明**：零拷贝只在**消费者拉取、且数据仍在 page cache / 文件**的路径上生效。如果消息需要解压、需要按事务隔离级别过滤、或者走了加密（SSL），就无法走纯零拷贝路径。

---

## 第四幕：实操验证

### 4.1 前置条件

沿用课 15/16 的实验环境。若已销毁，重新拉起：

```bash
cd /mnt/d/projects/learning/kafka/assets/stage6-observability
docker compose up -d
sleep 45
docker ps --format '{{.Names}}\t{{.Status}}' | grep l15-kafka
```

预期三个 broker 全部 `Up`。

> ⚠️ 本课所有 `docker exec` 里的命令都**必须**带 `export PATH=/opt/kafka/bin:$PATH; unset KAFKA_JMX_OPTS`。
> 前者因为该镜像的 CLI 不在默认 PATH；后者因为容器注入的 `KAFKA_JMX_OPTS` 含 `-javaagent`，CLI 继承后会因端口已被 broker 占用而启动失败（详见课 15 踩坑记录）。

### 4.2 步骤 1：确认网络线程数

```bash
curl -s http://localhost:17071/metrics | grep -E 'kafka_network_processor_idlepercent' | grep -v '^#'
```

预期：3 行，`networkProcessor=0/1/2`，值为 1.0（空闲）。未显式声明 labels 时会显示为 `_objectname=...networkProcessor=0...` 的长格式，同样正常。

### 4.3 步骤 2：建 topic 并压测

```bash
docker exec l15-kafka-1 bash -c 'export PATH=/opt/kafka/bin:$PATH; unset KAFKA_JMX_OPTS
kafka-topics.sh --bootstrap-server kafka-1:9092 --create --if-not-exists \
  --topic net-demo --partitions 6 --replication-factor 3'

docker exec l15-kafka-1 bash -c 'export PATH=/opt/kafka/bin:$PATH; unset KAFKA_JMX_OPTS
kafka-producer-perf-test.sh --topic net-demo --num-records 20000 --record-size 1024 \
  --throughput -1 --producer-props bootstrap.servers=kafka-1:9092 acks=1'
```

实测输出（本机）：

```text
20000 records sent, 33955.9 records/sec (33.16 MB/sec),
160.90 ms avg latency, 256.00 ms max latency,
180 ms 50th, 238 ms 95th, 250 ms 99th, 255 ms 99.9th.
```

### 4.4 步骤 3：看网络层是否成为瓶颈

```bash
echo "--- processor 空闲比 ---"
curl -s http://localhost:17071/metrics | grep -i 'networkprocessoravgidlepercent' | grep -v '^#'

echo "--- 请求队列积压 ---"
curl -s http://localhost:17071/metrics | grep -i 'requestchannel_requestqueuesize' | grep -v '^#'

echo "--- 各请求类型的耗时计数 ---"
curl -s http://localhost:17071/metrics | grep -E 'totaltimems' | grep -iE 'produce|fetch' | grep -v '^#'
```

实测：

```text
kafka_network_socketserver_networkprocessoravgidlepercent  1.0
kafka_network_requestchannel_requestqueuesize              0.0
kafka_network_requestmetrics_totaltimems{...request="Fetch"...Count}          12747.0
kafka_network_requestmetrics_totaltimems{...request="FetchFollower"...Count}  12615.0
kafka_network_requestmetrics_totaltimems{...request="FetchConsumer"...Count}    132.0
```

**解读**：processor 100% 空闲、队列 0 积压 → 网络层完全不是瓶颈。FetchFollower 有 12615 次，说明**副本同步流量是主要负载**。

### 4.5 步骤 4：验证那个陷阱指标

```bash
for i in 1 2 3; do
  curl -s http://localhost:17071/metrics | grep -i 'kafkarequesthandlerpool' | grep -v '^#' | awk '{print "sample: "$2}'
  sleep 3
done
```

预期：值持续增大（累积计数），且量级在 1e11 以上。**如果你看到的是 0.x 的小数，说明你的 exporter 配置与我不同，请以实际为准**——这正是本步骤要你亲手确认的事。

---

## 第五幕：体系收束

### 5.1 一图总结

```mermaid
flowchart TD
    subgraph NET["网络层（NIO Reactor）"]
        A["Acceptor ×1<br/>接收连接"]
        P["Processor ×3<br/>num.network.threads<br/>读请求 / 写响应"]
        Q["RequestChannel 队列<br/>queued.max.requests=500"]
    end
    subgraph IO["处理层"]
        H["IO 线程 ×8<br/>num.io.threads<br/>校验 / 落盘 / 查数据"]
        L[("分区日志<br/>顺序写")]
    end
    subgraph SEND["发送"]
        ZC["零拷贝 sendfile<br/>transferTo<br/>2 次 DMA，0 次 CPU 拷贝"]
    end
    C["客户端"] --> A
    A --> P
    P --> Q
    Q --> H
    H --> L
    L --> ZC
    ZC --> P
    P --> C
    M["⚠️ RequestHandlerAvgIdlePercent<br/>实测为累积计数，勿当比率告警"] -.-> H
    style Q stroke:#d29922,stroke-width:2px
    style ZC stroke:#238636,stroke-width:2px
    style M stroke:#da3633,stroke-width:2px
```

### 5.2 核心结论（记住这五句）

1. **网络层是标准 Reactor NIO**：1 个 acceptor + N 个 processor（默认 3）+ M 个 IO 线程（默认 8），用请求队列解耦。
2. **队列是咽喉**：排查性能问题先看 `RequestQueueSize`，再看 processor 空闲比，最后才考虑调线程数。
3. **`RequestHandlerAvgIdlePercent` 在本环境实测是累积计数（1e11 量级、单调递增），不是 0~1 比率**——照抄教程配告警会失效。改用 `RequestQueueSize` + `TotalTimeMs`。
4. **零拷贝只在消费拉取路径生效**，靠 `TransferableRecords.writeTo` → `transferTo` 实现，把 4 次拷贝降到 2 次、CPU 拷贝降到 0 次。
5. **33 MB/s 不是集群上限**，是单客户端压测上限——processor 空闲比 1.0 已经证明了这一点。

### 5.3 常见误区

| # | 误区 | 正解 |
|---|------|------|
| 1 | 连接多了就加 `num.io.threads` | 连接数对应的是 `num.network.threads`（processor）；`num.io.threads` 管的是请求处理 |
| 2 | `RequestHandlerAvgIdlePercent` 是空闲比率，< 0.3 要告警 | 实测为累积计数；先 curl 验证语义再写告警 |
| 3 | 吞吐上不去就是网络瓶颈 | 实测 processor 空闲比 1.0、队列 0 积压，瓶颈在别处（如客户端并发、acks 策略） |
| 4 | 零拷贝对所有请求生效 | 只有「文件支撑的消息集」直接写出时生效；SSL、解压、事务过滤会走普通路径 |
| 5 | `num.network.threads` 越大越好 | 每个 processor 管一批连接，过多会增加 Selector 竞争；默认 3 适用于绝大多数场景 |

### 5.4 官方文档

- [Network Layer](https://kafka.apache.org/43/implementation/network-layer/)（本课本源，全文仅 3 段）
- [Apache Kafka 官方文档 · 4.3](https://kafka.apache.org/43/documentation.html)
- 完整路由表见 [web-index/kafka/index.md](../../../web-index/kafka/index.md)

### 5.5 课后小测

**Q1.** 某集群 processor 空闲比长期 0.98、请求队列 0 积压，但吞吐上不去。最可能的原因是什么？
<details><summary>答案</summary>瓶颈不在网络层。空闲比 0.98 说明 processor 几乎无事可做，队列 0 说明没有积压。应排查客户端并发度、`acks` 策略、分区数是否足够、磁盘 IO。本课实测的 33 MB/s 就是典型例子——单客户端压测的上限，而非集群上限。</details>

**Q2.** 你照教程配了 `RequestHandlerAvgIdlePercent < 0.3` 告警，从未触发。你该怎么做？
<details><summary>答案</summary>先 curl 看实际值与 HELP 行。本环境实测值为 1e11 量级且单调递增（`attribute=Count`），是累积计数而非比率，所以 `< 0.3` 永不成立。改用 `RequestQueueSize`（队列积压）和 `TotalTimeMs`（请求总耗时）监控 IO 线程压力。</details>

**Q3.** 零拷贝为什么能减少 CPU 开销？它在什么情况下会失效？
<details><summary>答案</summary>传统路径：磁盘→内核缓冲→用户空间→Socket 缓冲→网卡，4 次拷贝含 2 次 CPU 拷贝。零拷贝（`sendfile`/`transferTo`）让数据从内核缓冲直接到网卡，只剩 2 次 DMA 拷贝，CPU 拷贝为 0。失效场景：需要解压、需要按事务隔离级别过滤、启用 SSL 加密时，数据必须先进入用户空间处理，无法走纯零拷贝。</details>

---

**下一课**：[课 18：消费者位移与协调者](../lessons/lesson-18-消费者位移与协调者.md)

**上一课**：[课 16：集群运维操作](../../6-运维与可观测/lessons/lesson-16-集群运维操作.md)

**返回目录**：[课程目录](../../../02-课程目录.md)
