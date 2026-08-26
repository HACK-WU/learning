# 第 5 课：生产者 Producer

> 所属阶段：阶段 2《Kafka 核心架构》｜ 水平：零基础 ｜ 本课知识点：生产者发送流程 / 分区策略 / acks 与发送可靠性
> 故事情节：发货方上场——一条消息是怎么被打包、选好货架、送进仓库的

## 🎯 本课目标

- 画出一条消息从应用到 Broker 的发送路径
- 解释分区策略：key 如何决定消息落到哪个 Partition
- 说清 acks=0 / 1 / all 对"可靠性 vs 性能"的取舍

---

## 第一幕：起源与场景引入

> 上一课我们看的是 Kafka「怎么存」——Topic 分片、Broker 集群。这一课回到故事的起点：消息是怎么**进入** Kafka 的。主角（消息的流动）要先被「发货方」正确地送进仓库，后面的存储、消费才有意义。

还记得第 3 课你干过的事吗？你敲了这样一条命令：

```bash
docker exec -it kafka /opt/kafka/bin/kafka-console-producer.sh \
  --topic orders --bootstrap-server localhost:9092
```

然后随便敲几行字、回车，消息就「进 Topic」了。当时你只是在**用**生产者，没关心它背后发生了什么。现在我们把这块黑盒拆开。

> 🎬 **场景**：你现在是一家电商的「下单服务」——每来一个订单，你就往 Kafka 发一条消息。你心里其实有三个没底的问题：
> 1. 这条消息发出去，中间要经过哪几道工序才真正落到 Broker 的磁盘上？
> 2. 一个 Topic 有 3 个分区，这条消息到底进了哪个分区？凭什么？
> 3. 你按下「发送」那一刻，就真的「发送成功」了吗？如果 Broker 恰好挂了，消息是丢了还是被救回来了？

这就是生产者（Producer）要回答的三件事。

---

## 第二幕：认知冲突

你可能觉得：「发消息不就是把数据丢过去吗，有什么好学的？」

但两个矛盾马上就冒出来：

- **分区怎么选？** 第 4 课你知道了——分区内有序、跨分区无序。那生产者发消息时，**凭什么决定**这条消息进哪个分区？如果它乱发，同一笔订单的先后顺序不就乱套了？如果它只会轮着发，那「想保证顺序」的业务（比如同一用户的订单必须按时间先后处理）怎么办？
- **发出去 = 成功了吗？** 你调用了 `send()`，方法返回了。但这代表 Broker 真的写进磁盘了吗？如果消息还在「半路」上 Broker 就挂了，是丢了、还是客户端会自动重试？你作为下单服务，敢不敢「只发一次就认为成功了」？

> ❓ **问题**：生产者既不能「乱选分区」，也不能「发了就不管」。它需要一套机制，既能**决定消息去哪**，又能**确认消息真的落地了**。这正是本课要拆的「发送流程」「分区策略」「acks 可靠性」三件事。

---

## 第三幕：层层揭示

### 知识点 1：生产者发送流程

#### 直觉建立（类比）

把生产者想成一个**发货部门**，一条消息从「你要发货」到「货进仓库」要过四道工序：

1. **打包**（序列化）：你手里是个「订单对象」，但物流只认得「一箱货」。得先把它装成能运输的样子（对象 → 字节）。
2. **选货架**（分区）：货进了仓库，得决定放进哪一条传送带（分区）。
3. **暂存待发**（消息累加器）：不是来一件发一件，而是**先堆在发货区，攒够一批再发**，省油省时。
4. **装车发出**（Sender 线程）：专门有一辆「送货的卡车」把攒好的货，一批批运到仓库。

> 💡 **类比的边界**：真实发货是「一件一件打包」，但 Kafka 的打包（序列化）和发送是**异步**的——你调用 `send()` 只是把货放进了「发货区」，真正「装车运走」是后面一个独立线程在干。所以 `send()` 返回 ≠ 消息已到 Broker，这是新手最容易误会的一点。

#### 概念与原理

生产者（Producer）把一条消息送进 Broker，内部要经过这几步：

```mermaid
flowchart LR
    A["应用调用 send()"] --> B["序列化器<br/>对象 → 字节"]
    B --> C["分区器<br/>决定去哪个分区"]
    C --> D["消息累加器<br/>按分区攒批缓冲"]
    D --> E["Sender 线程<br/>真正发往 Broker"]
    E --> F[("Broker<br/>对应分区的 leader")]
```

关键点（零基础先记住这 4 个角色）：

1. **序列化器（Serializer）**：把对象转成字节。发字符串要用 `StringSerializer`，发 JSON 要自定义序列化。
2. **分区器（Partitioner）**：决定消息进哪个分区（知识点 2 详讲）。
3. **消息累加器（RecordAccumulator）**：按分区把消息**攒成一批（batch）**再发，这是 Kafka 高吞吐的关键——「批量发货」比「一件一送」快得多。
4. **Sender 线程**：真正把攒好的批次发到对应分区的 leader Broker。

> 💡 重点：`send()` 是**异步**的，它把消息放进累加器就返回了，真正发网是 Sender 线程在后台干。所以「send 返回」和「Broker 收到」之间有时间差——这就是为什么后面要讲 acks（确认机制）。

#### 一句话记住

**生产者 = 序列化打包 → 分区选路 → 攒批暂存 → Sender 线程异步发出，四道工序。send 返回 ≠ 已落地。**

---

### 知识点 2：分区策略

#### 直觉建立（类比）

货进仓库前，发货部门要决定放哪条传送带。规则就像「按快递单号分配快递柜」：

- 单号上有「片区编号」的，永远投进**固定的那格**（同一用户永远同一格，方便按顺序取）；
- 没写片区编号的，就**轮流投**，保证每格都差不多满。

> 💡 **类比的边界**：真实快递柜你可以「按货的大小」分格；Kafka 的分区只看三样东西——**有没有指定分区、有没有指定 key、两者都没有**，不看消息内容本身。

#### 概念与原理

生产者决定消息去哪个 Partition，只有三种情况（按优先级）：

```mermaid
flowchart TD
    A["发消息"] --> B{"显式指定了<br/>partition？"}
    B -- 是 --> C["直接发到该分区"]
    B -- 否 --> D{"指定了 key？"}
    D -- 是 --> E["hash(key) % 分区数<br/>同 key 永远同分区"]
    D -- 否 --> F["轮询 / 粘性分区<br/>尽量均匀分布"]
```

1. **显式指定 partition**：代码里直接写死去第 2 个分区（`ProducerRecord` 带分区号），优先级最高。
2. **指定了 key（最常见）**：按 `hash(key) % 分区数` 计算（Kafka 默认用 **murmur2 哈希**）。**同一个 key 永远落到同一个分区**——这就是「保证顺序」的钥匙：同一用户的订单用 `userId` 当 key，就天然有序了。
3. **两者都没有**：老版本是**轮询（round-robin）**，一条换一个分区；**Kafka 2.4 起默认改为「粘性分区（sticky partitioning）」**——把连续的一批消息尽量发到同一个分区，减少「切换分区」的开销，吞吐更高（核查于 2026-08）。

> 💡 这里直接回答了第 4 课留下的那个问题：「同一用户的订单严格先后」怎么办？——**用 userId 当 key**，这些消息就都进同一个分区，顺序就有保证了。

#### 一句话记住

**分区三选一：有 partition 直发，有 key 就 hash 取模（同 key 同分区），都没有就轮询/粘性。**

---

### 知识点 3：acks 与发送可靠性

#### 直觉建立（类比）

你寄一封重要快递，快递公司给你三种「签收标准」：

- **投出去就不管**：往邮筒一塞，不查有没有送到。最快，但丢了也不知道。
- **签收人本人签收**：收件人（leader）签字就当你送到了。但如果签收人签字后、还没来得及转交给仓库（follower），他自己突然消失了，快递还是可能丢。
- **签收 + 所有仓库都登记完**：不仅收件人签收，还要所有「备份仓库」都登记入册，才告诉你「送到了」。最慢，但最稳。

> 💡 **类比的边界**：这个「签收标准」就是 Kafka 的 `acks` 参数。它控制的是**生产者要等多少个副本确认，才算发送成功**——本质是在「快」和「不丢」之间做取舍。

#### 概念与原理

`acks` 有三个取值，可靠性递增、性能递减：

| acks | 含义 | 可靠性 | 性能 | 一句话 |
|------|------|--------|------|--------|
| **0** | 发出去就不等任何确认 | 最差，可能丢 | 最快 | 丢了也不管 |
| **1** | leader 写进本地日志就返回 | 中（leader 挂了可能丢） | 中 | 只认「头儿」签收 |
| **all（-1）** | 所有 ISR 副本都确认才返回 | 最强 | 最慢 | 全员签收才算数 |

三个关键补充：

1. **为什么 `acks=1` 会丢？** 因为 leader 返回确认时，数据可能还没同步到 follower。若 leader 在这时宕机，已确认的消息就丢了（这正是第 7 课要讲的副本机制的坑）。
2. **`acks=all` 就绝对不丢吗？** 还不够。要配合 **`min.insync.replicas`**（最小同步副本数）：它规定「ISR 至少要有几个副本，才接受写入」。如果设 `acks=all` 但 `min.insync.replicas=1`，那么 ISR 只有一个副本时照样写、照样丢。所以「不丢」= `acks=all` + `min.insync.replicas≥2` 一起用。
3. **默认值**：早期 Kafka 默认 `acks=1`，**Kafka 3.0 起默认改为 `all`**（更安全，但更看重吞吐的场景要自己调回 1）（核查于 2026-08）。

```mermaid
flowchart LR
    subgraph acks1["acks=1"]
        P1["生产者"] --> L1["leader"]
        L1 -.还没同步.-> F1["follower"]
    end
    subgraph acksall["acks=all"]
        P2["生产者"] --> L2["leader"]
        L2 --> F2["follower 1"]
        L2 --> F3["follower 2"]
    end
    style F1 stroke:#f85149,stroke-width:2px
```

> 左图：`acks=1` 时 leader 先返回确认，follower 还「没同步」——这段空档就是丢消息的窗口。右图：`acks=all` 等所有副本都同步完才确认，窗口消失。

#### 一句话记住

**acks 是「要几个副本确认」：0 最快最易丢，1 只认 leader，all 全员确认才不丢（还得配 min.insync.replicas）。**

---

## 第四幕：实操验证

> 我们用第 3 课的真集群，亲手验证「同 key 同分区」这条最关键的结论。先确保 Kafka 在跑、`orders` 有 3 个分区（没有就重建）：

```bash
# 1. 若容器已停，重新起（第 3 课的命令）
docker run -d --name kafka -p 9092:9092 \
  -e KAFKA_NODE_ID=1 -e KAFKA_PROCESS_ROLES='broker,controller' \
  -e KAFKA_CONTROLLER_QUORUM_VOTERS='1@kafka:29093' \
  -e KAFKA_LISTENERS='PLAINTEXT://0.0.0.0:9092,CONTROLLER://0.0.0.0:29093' \
  -e KAFKA_ADVERTISED_LISTENERS='PLAINTEXT://localhost:9092' \
  -e KAFKA_CONTROLLER_LISTENER_NAMES='CONTROLLER' \
  -e KAFKA_LISTENER_SECURITY_PROTOCOL_MAP='CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT' \
  -e KAFKA_LOG_DIRS='/tmp/kraft-logs' \
  -e CLUSTER_ID='MkU3OEVBNTcwNTJENDM2Qk' apache/kafka:4.0.0

# 2. 建 3 分区的 topic（若已存在可跳过）
docker exec -it kafka /opt/kafka/bin/kafka-topics.sh --create \
  --topic orders --partitions 3 --replication-factor 1 --bootstrap-server localhost:9092
```

**验证「同 key 同分区」**：生产端用 `--property parse.key=true` 让 CLI 支持 `key:value` 格式：

```bash
docker exec -it kafka /opt/kafka/bin/kafka-console-producer.sh \
  --topic orders --property parse.key=true --property key.separator=: \
  --bootstrap-server localhost:9092
# 逐行输入（key:value），Ctrl+C 退出：
> user1:第一条订单
> user1:第二条订单
> user1:第三条订单
> user2:另一条订单
```

再开一个消费端，**打印每条消息的 key 和它所在的分区号**：

```bash
docker exec -it kafka /opt/kafka/bin/kafka-console-consumer.sh \
  --topic orders --from-beginning \
  --property print.key=true --property print.partition=true \
  --bootstrap-server localhost:9092
```

预期输出大致是（分区号可能不同，但**关键在规律**）：

```
Partition:1  user1  第一条订单
Partition:1  user1  第二条订单
Partition:1  user1  第三条订单
Partition:2  user2  另一条订单
```

> ✅ **回扣场景**：你看，`user1` 的三条消息**全部落在同一个 Partition（1）**，`user2` 落在另一个（2）。这就是「hash(key) % 分区数」在起作用——同一 key 永远同分区，顺序天然有保证。这也正是第 4 课「同一用户订单严格先后」的答案，现在你亲手验证了它。

---

## 第五幕：体系收束

> 📍 **全局定位**：故事主线是「消息的流动」。上一课（第 4 课）讲的是消息「住在哪」（存储骨架：Topic / Partition / Broker），这一课讲的是消息「怎么进来」——生产者是 Kafka 的**入口**。发送流程（怎么送）、分区策略（送到哪）、acks（送到没送到）三者合起来，就是一个「负责任的发货方」。
> 🔗 **下一步**：消息进来了，总得有人取。下一课《第 6 课：消费者与消费者组》讲「收货方」——多个消费者怎么分工、怎么记住「读到哪了」（offset）、换人时怎么交接（再均衡）。

---

## 🐞 常见误区

1. **「send() 返回就代表发送成功了」**：错。`send()` 是异步的，只把消息放进缓冲区，真正发送由 Sender 线程完成。想确认成功，要等返回的 `Future` / 回调（或设 `acks` 并检查结果）。
2. **「分区是随机选的」**：错。有 key 时是 `hash(key) % 分区数`，**确定性**的——同 key 必同分区。只有「既没 key 又没指定分区」时才轮询/粘性。
3. **「acks=all 就绝对不会丢」**：错。`acks=all` 还要搭配 `min.insync.replicas≥2` 才真正「不丢」。否则 ISR 只剩一个副本时照样可能丢（这是第 7 课的伏笔）。
4. **「多建几个分区，顺序问题就解决了」**：错。分区越多，key 越容易「散」，反而更难保证顺序。保证顺序靠「同 key 同分区」，不靠「多分区」。

## 📚 官方文档

- [Kafka 生产者配置](https://kafka.apache.org/documentation/#producerconfigs)：`acks`、`key.serializer`、`linger.ms` 等生产者参数完整参考
- [Kafka 快速开始](https://kafka.apache.org/quickstart)：官方 Quickstart，含 console-producer 的 key 用法

## 一图总结

```mermaid
flowchart TD
    A["生产者 Producer"] --> B["序列化"]
    B --> C["分区器<br/>有key→hash取模 / 无key→轮询"]
    C --> D["攒批 + Sender 异步发送"]
    D --> E[("Broker<br/>leader 分区")]
    E -.acks 确认.-> A
    subgraph 可靠性["acks 取舍"]
        F["0=不管 1=只认leader all=全员确认"]
    end
    E --- F
    style A stroke:#3fb950,stroke-width:2px
```

## 课后小测

**Q1**：生产者发送消息时，若指定了 `key="user123"`，这条消息会进入哪个分区？
- A. 随机选一个分区
- B. 永远进入 `hash("user123") % 分区数` 算出的那个固定分区
- C. 轮询到下一个分区
- D. 进入所有分区各一份

<details><summary>答案与解析</summary>

**答案：B**。指定 key 时，Kafka 用 murmur2 哈希对 key 取模得到固定分区，所以同 key 必同分区（保证顺序）；A/C 是「未指定 key」时的行为，D 是错的（一条消息只进一个分区）。

</details>

**Q2**：关于 `acks=1` 的说法，正确的是？
- A. 消息被所有副本确认后才返回，绝不丢
- B. leader 写入本地日志后即返回，若 leader 此时宕机且数据未同步，消息可能丢
- C. 与 `acks=0` 完全一样
- D. 必须等待 follower 同步才返回

<details><summary>答案与解析</summary>

**答案：B**。`acks=1` 只等 leader 写本地日志就返回，不等 follower 同步；这段「未同步窗口」正是 leader 宕机时丢消息的根源。A/D 描述的是 `acks=all`，C 明显错（`acks=0` 连确认都不等）。

</details>

**Q3**：要想「真正不丢消息」，最可靠的配置是？
- A. `acks=0`
- B. `acks=1`
- C. `acks=all` 且 `min.insync.replicas≥2`
- D. 只提高分区数量

<details><summary>答案与解析</summary>

**答案：C**。`acks=all` 等所有 ISR 副本确认，再配合 `min.insync.replicas≥2` 保证至少有两个副本在线才写入，才能做到「不丢」。A/B 都可能丢，D 与可靠性无关。

</details>

## 🚀 下一批接力提示词

> 学完本批后，**复制下面这段文字发给 AI**，即可无缝进入下一批（无需重新描述上下文）：

```
继续学 Kafka。我的学习档案在 kafka-basics/00-学习档案.md，
刚学完阶段 2《Kafka 核心架构》的课《生产者 Producer》知识点 生产者发送流程、分区策略、acks与发送可靠性，
请按大纲继续讲解下一批知识点（课6：消费者与消费者组）。
```
