# 第 3 课：本地起 Kafka + CLI 快速上手

> 所属阶段：阶段 2《Kafka 核心架构》｜ 水平：零基础 ｜ 本课知识点：KRaft 一键起（Docker） / 创建 Topic + 生产消费 / CLI 观察 Partition
> 故事情节：主角从纸上走进现实——把 Kafka 跑起来，亲眼看它"建通道、发消息、收消息"
> 适用版本：Kafka 4.x（KRaft 模式，无需 ZooKeeper）；命令基于官方镜像 `apache/kafka:4.0.0`

## 🎯 本课目标

- 用 Docker 一条命令把 Kafka 跑起来（KRaft 单节点）
- 会创建 Topic、生产一条消息、消费一条消息
- 会用 `--describe` 亲眼看 Partition / 副本，回扣第 4 课的分片概念

---

## 第一幕：起源与场景引入

前两课你一直在"纸上谈兵"——聊为什么需要 Kafka、四大角色是什么。现在，我们**把那个物流中心真的建到你电脑上**，亲手投一票货、再亲手取出来。

只要本机装了 **Docker**，30 秒就能起一个 Kafka，不需要装 Java、不需要配一堆配置文件。

> 🎬 **场景**：你要在本地搭一个 Kafka，用来练习后面几课的生产者、消费者代码。以前的教程总要你先装 ZooKeeper 再装 Kafka，两个服务、一堆配置。现在呢？

> 📌 **一句话本质**：本课做的事，是把**「自己一件件买零件、照说明书拼装」**改成**「整份打包好、一句话端上来直接用」**。
>
> ⚖️ **处境对照**（沿用第二幕的对比：旧方式 vs KRaft 单节点）：
> - **不这么做（手工拼装）**：要先后装好 Java 运行环境、再装并启动 ZooKeeper、最后才装 Kafka，三处配置要互相**对上版本与端口**；任一处配错，就是"起不来 + 不知道哪错了"。
> - **这么做（整份打包 + 一条命令）**：**一条 `docker run`** 拉起即用，内部组件版本已互相配好；练完手 **一条 `docker rm`** 收走，本机不留残余。
>
> ⏳ **数字来源说明**：以上为**定性对比 + 步骤数推算**（按"要装几样、配几处"得出），不是实测耗时。真实启动耗时取决于网络拉取镜像的速度与本机资源，"30 秒起"是镜像已在本机时的经验量级，首次拉取会明显更久。

---

## 第二幕：认知冲突

你可能会担心："装 Kafka 是不是很麻烦？是不是还得先弄个 ZooKeeper？"

好消息是——**不用了**。这正是第 2 课提过的 KRaft 变革：

- **旧时代**：Kafka 依赖 ZooKeeper 存元数据，你要维护两个分布式系统；
- **Kafka 4.0 起**：ZooKeeper 被彻底移除，Kafka 用内置的 **KRaft** 自己管自己，单机一键起。

> ❓ **问题**：既然如此，我能不能用**一条 Docker 命令**就把整个 Kafka 拉起来，然后立刻开始发消息？

---

## 第三幕：层层揭示

### 一眼全局图（进入细节前先看一眼）

![手工拼装 vs 一条命令端上来](../assets/lesson03-global-assemble-vs-onecmd.svg)

> 看图：**左边**是以前的做法——运行环境、协调服务、它自己，三样东西要**一件件装、一处处配**，还得两两对上版本，配错一个就起不来；**右边**是现在的做法——所有东西**打包成一整份**，一句话说完就自己跑起来，不想用了也是一句话收走。差别在于：**把"自己拼装"换成了"整份拿来就用"**，你不用管里面到底有几样零件。

**四条硬约束**说明：① 本图只回答"本课要解决什么问题、靠什么思路"；② 图上不出现术语（Kafka、KRaft、ZooKeeper、Docker 这些词都在下面才出场）；③ 已带读图指引；④ 图旁文字能独立说清同一件事。

### 本课地图（分几步走）

| 步 | 这一步要解决什么（人话） | 对应知识点 |
|:--:|------------------------|-----------|
| 1 | 先把整份东西拉起来，确认它真的活着 | 知识点 1：KRaft 一键起（Docker） |
| 2 | 学会"开通道 → 投一条 → 取一条"这套基本动作 | 知识点 2：创建 Topic + 生产消费 |
| 3 | 透过命令看一眼底层到底分了几段 | 知识点 3：用 CLI 观察 Partition |

> 只回答"分几步走、现在在哪"；不写机制、不写结论；**不标学习状态**（进度以 `00-学习档案.md` 为准）。

### 知识点 1：KRaft 一键起（Docker）

> 🧭 第 1/3 步｜承接：第一幕里"想练手却要自己拼一堆零件"这个麻烦 → 本步：用一条命令把整份东西拉起来，并确认它真的活着

#### 直觉建立（类比）

`docker run` 就像**点一份"Kafka 全家桶外卖"**——镜像是菜谱，环境变量是"口味偏好"，容器跑起来就是一家现成的 Kafka 店，你不用自己搭。

#### 概念与原理

用官方镜像 `apache/kafka:4.0.0`，配好 KRaft 所需的环境变量，一条命令启动：

```bash
docker run -d \
  --name kafka \
  -p 9092:9092 \
  -e KAFKA_NODE_ID=1 \
  -e KAFKA_PROCESS_ROLES='broker,controller' \
  -e KAFKA_CONTROLLER_QUORUM_VOTERS='1@kafka:29093' \
  -e KAFKA_LISTENERS='PLAINTEXT://0.0.0.0:9092,CONTROLLER://0.0.0.0:29093' \
  -e KAFKA_ADVERTISED_LISTENERS='PLAINTEXT://localhost:9092' \
  -e KAFKA_CONTROLLER_LISTENER_NAMES='CONTROLLER' \
  -e KAFKA_LISTENER_SECURITY_PROTOCOL_MAP='CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT' \
  -e KAFKA_LOG_DIRS='/tmp/kraft-logs' \
  -e CLUSTER_ID='MkU3OEVBNTcwNTJENDM2Qk' \
  apache/kafka:4.0.0
```

> 这些环境变量你不用逐条背，只需看懂 3 个关键点：
> - `KAFKA_PROCESS_ROLES='broker,controller'`：这一个节点**既当仓库又当管理员**（单节点 KRaft 的典型玩法）；
> - `KAFKA_CONTROLLER_QUORUM_VOTERS` + `CLUSTER_ID`：KRaft 集群的身份标识；
> - `KAFKA_ADVERTISED_LISTENERS='PLAINTEXT://localhost:9092'`：客户端从 `localhost:9092` 连进来。

启动后确认它活着：

```bash
docker logs kafka
# 看到类似 "Kafka Server started" 就说明起来了（首次启动会先格式化，稍等几秒）
```

> 💡 **类比的边界**：这条命令起的是"单节点演示版"——副本数只能是 1，不适合生产；生产要起 3 个以上 controller + 多 broker。但拿来学习足够了。

#### 🗣️ 行话对照

> 讲透后对标：下面这些是你在文档和现场能直接搜到的标准叫法。

- **KRaft（Kafka Raft）**：就是本课说的"它自己管自己、不用再养一个协调服务"。在哪遇到：配置项 `process.roles` / `controller.quorum.voters`；**Kafka 4.0 起是唯一模式**，旧教程里的 ZooKeeper 已彻底移除。
- **ZooKeeper（ZK）**：就是本课说的"以前那个要单独装、单独养的协调服务"。在哪遇到：2025 年之前的旧教程与老集群；**现在遇到它基本意味着你要处理的是历史系统**。
- **Broker / Controller 两种角色 `process.roles`**：就是本课说的"既当仓库又当管理员"。在哪遇到：KRaft 配置项 `process.roles=broker,controller`（单机）或拆成两类节点（生产）。
- ** advertised 监听地址 `advertised.listeners`**：就是本课说的"对外公布从哪进来"。在哪遇到：**连不上集群的第一嫌疑**——客户端拿到的是这个地址，写错就会出现"能 ping 通但连不上"。

#### 一句话记住

**一条 `docker run` + KRaft 环境变量，30 秒起一个单节点 Kafka。**

---

### 知识点 2：创建 Topic + 生产消费一条消息

> 🧭 第 2/3 步｜承接：上一步已经把整份东西拉起来、确认它活着 → 本步：学会"开通道 → 投一条 → 取一条"这套最基本的手上动作

#### 直觉建立（类比）

Topic = 你给物流中心**开一条专用传送带**；生产 = 往传送带**投一件货**；消费 = 从传送带**取一件货**。

#### 概念与原理

Kafka 的 CLI 工具都在容器内的 `/opt/kafka/bin/` 下。三步走：

**① 建 Topic**（开传送带）：

```bash
docker exec -it kafka /opt/kafka/bin/kafka-topics.sh --create \
  --topic orders --partitions 3 --replication-factor 1 \
  --bootstrap-server localhost:9092
# 预期输出：Created topic orders.
```

**② 生产消息**（投货，回车后输入文字，Ctrl+C 退出）：

```bash
docker exec -it kafka /opt/kafka/bin/kafka-console-producer.sh \
  --topic orders --bootstrap-server localhost:9092
# 输入几行，例如：
> 第一个订单来了
> 第二个订单来了
```

**③ 消费消息**（取货，`--from-beginning` 表示从第 0 条开始读）：

```bash
docker exec -it kafka /opt/kafka/bin/kafka-console-consumer.sh \
  --topic orders --from-beginning --bootstrap-server localhost:9092
# 预期输出：刚才发的那两行文字原样打印出来
```

#### 🗣️ 行话对照

> 讲透后对标：三个脚本是运维现场最常用的"三板斧"，名字要记准。

- **`kafka-topics.sh`（Topic 管理工具）**：就是本课说的"开传送带"。在哪遇到：`--create` 建、`--list` 查、`--describe` 看详情、`--delete` 删；**排障第一站**。
- **`kafka-console-producer.sh` / `kafka-console-consumer.sh`（控制台收发工具）**：就是本课说的"投一件货 / 取一件货"。在哪遇到：**验证链路通不通的最快手段**，不用写一行代码。
- **`--from-beginning`**：就是本课说的"从第 1 条开始取"。在哪遇到：**新手最常漏的参数**——不加它，默认只读"启动之后新来的"，会误以为"消息丢了"。
- **`--bootstrap-server`（连接地址）**：就是本课说的"告诉工具去哪找这个集群"。在哪遇到：**所有新版 CLI 都用它**；旧的 `--zookeeper` 写法在 4.0 已失效。

#### 一句话记住

**`kafka-topics.sh --create` 开通道，`console-producer` 投，`console-consumer --from-beginning` 取。**

---

### 知识点 3：用 CLI 观察 Partition

> 🧭 第 3/3 步｜承接：上一步已经能投能取了 → 本步：不写代码、纯靠一条命令，看穿这个通道底下到底分了几段、各在哪

#### 直觉建立（类比）

第 4 课会细讲 Partition（分片）。现在先**偷看一眼**：你刚才建的 `orders` 有 3 个分区，它们长什么样？

#### 概念与原理

用 `--describe` 看一个 Topic 的分区详情：

```bash
docker exec -it kafka /opt/kafka/bin/kafka-topics.sh --describe \
  --topic orders --bootstrap-server localhost:9092
```

预期会看到类似这样的**三行**（每行一个 Partition）：

```
Topic: orders  PartitionCount: 3  ReplicationFactor: 1
Topic: orders  Partition: 0  Leader: 1  Replicas: 1  Isr: 1
Topic: orders  Partition: 1  Leader: 1  Replicas: 1  Isr: 1
Topic: orders  Partition: 2  Leader: 1  Replicas: 1  Isr: 1
```

再看所有 Topic：

```bash
docker exec -it kafka /opt/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092
# 预期：orders 以及系统内部的 __consumer_offsets
```

> 💡 现在你只需看懂一件事：`orders` 这一个 Topic，底层其实是 **3 个 Partition（0/1/2）**。这就是"逻辑一个、物理三个"的分片雏形，第 4 课会把它讲透。

#### 🗣️ 行话对照

> 讲透后对标：`--describe` 输出里的每个字段都有固定叫法，看懂它们就等于会看 Kafka 的体检报告。

- **Partition（分区）**：就是本课说的"通道底下分成的那几段"。在哪遇到：`--describe` 的 `Partition: 0/1/2`；也是第 4 课的主角。
- **Leader**：就是本课说的"这一段当前归谁管"。在哪遇到：`--describe` 的 `Leader:` 列；**值为 -1 表示该分区暂无主，属于异常信号**。
- **Replicas（AR）**：就是本课说的"这一段一共存了几份、都在哪"。在哪遇到：`--describe` 的 `Replicas:` 列。
- **Isr**：就是本课说的"这几份里，现在跟得上的是哪几个"。在哪遇到：`--describe` 的 `Isr:` 列；**Replicas 与 Isr 不一致 = 有副本掉队**（第 7 课细讲）。
- **`__consumer_offsets`（系统内置 Topic）**：就是本课说的"系统自己留的进度本"。在哪遇到：`--list` 里总会看到它；**别手贱删**。

#### 一句话记住

**`--describe` 一眼看穿 Topic 底下的 Partition 分布，是理解分片的第一手证据。**

---

## 第四幕：实操验证

把上面三步串成一条完整链路，亲手验证"生产 → 存储 → 消费"：

```bash
# 1. 起 Kafka
docker run -d --name kafka -p 9092:9092 \
  -e KAFKA_NODE_ID=1 \
  -e KAFKA_PROCESS_ROLES='broker,controller' \
  -e KAFKA_CONTROLLER_QUORUM_VOTERS='1@kafka:29093' \
  -e KAFKA_LISTENERS='PLAINTEXT://0.0.0.0:9092,CONTROLLER://0.0.0.0:29093' \
  -e KAFKA_ADVERTISED_LISTENERS='PLAINTEXT://localhost:9092' \
  -e KAFKA_CONTROLLER_LISTENER_NAMES='CONTROLLER' \
  -e KAFKA_LISTENER_SECURITY_PROTOCOL_MAP='CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT' \
  -e KAFKA_LOG_DIRS='/tmp/kraft-logs' \
  -e CLUSTER_ID='MkU3OEVBNTcwNTJENDM2Qk' \
  apache/kafka:4.0.0

# 2. 建一个 3 分区的 topic
docker exec -it kafka /opt/kafka/bin/kafka-topics.sh --create \
  --topic orders --partitions 3 --replication-factor 1 --bootstrap-server localhost:9092

# 3. 观察分区
docker exec -it kafka /opt/kafka/bin/kafka-topics.sh --describe \
  --topic orders --bootstrap-server localhost:9092
```

> ✅ **回扣场景**：从"纸上谈兵"到"亲手看到 3 个 Partition"，你已经迈出关键一步。后面第 4 课讲分片、第 5 课讲生产者、第 6 课讲消费者时，**随时能用这个真集群做实验**，不用再干看文字。

用完可以这样收尾：

```bash
docker stop kafka && docker rm kafka   # 停掉并删除容器
```

---

## 第五幕：体系收束

> 📍 **全局定位**：从本课起，你手里有了一个**随时可用的真 Kafka**。这是整个"动手实操"目标的地基——之后的每一课，讲概念时都能配真命令验证。
> 🔗 **下一步**：下一课《第 4 课：Topic、Partition 与 Broker》会把你刚才看到的"3 个 Partition"背后的原理讲透——分片、顺序写、零拷贝、Broker 集群。

---

## 🐞 常见误区

1. **"忘了 `--from-beginning` 看不到旧消息"**：`kafka-console-consumer` 默认只读**启动之后新来的消息**；要读历史消息必须加 `--from-beginning`。
2. **"脚本路径找不到"**：命令工具在**容器内** `/opt/kafka/bin/`，必须用 `docker exec -it kafka /opt/kafka/bin/xxx.sh`，而不是直接敲 `kafka-topics.sh`（除非你宿主机也装了 Kafka）。
3. **"把 `-p 9092:9092` 端口改了就忘了 advertised 监听"**：对外监听地址由 `KAFKA_ADVERTISED_LISTENERS` 决定，客户端要连它，端口不匹配会连不上。

## 📋 命令速查卡

| 动作 | 命令 |
|------|------|
| 起 Kafka（KRaft 单节点） | `docker run -d --name kafka -p 9092:9092 -e KAFKA_NODE_ID=1 -e KAFKA_PROCESS_ROLES='broker,controller' -e KAFKA_CONTROLLER_QUORUM_VOTERS='1@kafka:29093' -e KAFKA_LISTENERS='PLAINTEXT://0.0.0.0:9092,CONTROLLER://0.0.0.0:29093' -e KAFKA_ADVERTISED_LISTENERS='PLAINTEXT://localhost:9092' -e KAFKA_CONTROLLER_LISTENER_NAMES='CONTROLLER' -e KAFKA_LISTENER_SECURITY_PROTOCOL_MAP='CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT' -e KAFKA_LOG_DIRS='/tmp/kraft-logs' -e CLUSTER_ID='MkU3OEVBNTcwNTJENDM2Qk' apache/kafka:4.0.0` |
| 看日志/是否启动 | `docker logs kafka` |
| 建 Topic | `docker exec -it kafka /opt/kafka/bin/kafka-topics.sh --create --topic orders --partitions 3 --replication-factor 1 --bootstrap-server localhost:9092` |
| 列出 Topic | `docker exec -it kafka /opt/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092` |
| 看分区/副本 | `docker exec -it kafka /opt/kafka/bin/kafka-topics.sh --describe --topic orders --bootstrap-server localhost:9092` |
| 生产消息 | `docker exec -it kafka /opt/kafka/bin/kafka-console-producer.sh --topic orders --bootstrap-server localhost:9092` |
| 消费消息 | `docker exec -it kafka /opt/kafka/bin/kafka-console-consumer.sh --topic orders --from-beginning --bootstrap-server localhost:9092` |
| 停止并删除容器 | `docker stop kafka && docker rm kafka` |

## 📚 官方文档

- [Kafka 快速开始（4.3）](https://kafka.apache.org/43/getting-started/quickstart/)：官方 Quickstart，含单节点 KRaft 启动与命令行生产/消费
- [Kafka 基础运维操作（4.3）](https://kafka.apache.org/43/operations/basic-kafka-operations/)：`kafka-topics.sh`、`kafka-configs.sh`、console 工具等命令参考

## 一图总结

```mermaid
flowchart LR
    A[起 Kafka<br/>docker run KRaft] --> B[建 Topic<br/>kafka-topics --create]
    B --> C[生产消息<br/>console-producer]
    C --> D[消费消息<br/>console-consumer --from-beginning]
    D --> E[观察分区<br/>--describe]
    style A stroke:#3fb950,stroke-width:2px
```

> 看图：**从左到右是一条完整的操作链**——先把整份东西拉起来（绿色第一步），然后开通道，再投一条、取一条，最后用一条命令看穿底下的分段。**箭头是单向的**：必须按顺序做，跳一步后面就跑不通。

> **与课首入口的分工（勿混，三方视角）**：「一眼全局图」在课首、问题视角、零术语，给没学过的人看（回答"为什么需要它、靠什么思路"）；「本课地图」在课首、路线视角（回答"分几步走、现在在哪"），是表格不是图；本图在课末、知识视角，给刚学完的人复习用（回答"本课讲了什么"）。三者不可替代、不雷同。

## 课后小测

**Q1**：Kafka 4.0 单节点快速启动，关于 ZooKeeper 的说法正确的是？
- A. 必须先启动一个独立的 ZooKeeper 才能跑 Kafka
- B. 不需要 ZooKeeper，Kafka 用内置 KRaft 自己管理元数据
- C. ZooKeeper 仍然必须和 Kafka 一起启动，但可以单节点
- D. 需要启动两个 ZooKeeper 实例

<details><summary>答案与解析</summary>

**答案：B**。Kafka 4.0 已彻底移除 ZooKeeper，默认 KRaft 模式；单节点用 `KAFKA_PROCESS_ROLES='broker,controller'` 即一个节点同时承担 broker 和 controller 角色。

</details>

**Q2**：想看到 Topic 里"历史已有的消息"，`kafka-console-consumer.sh` 必须加哪个参数？
- A. `--from-beginning`
- B. `--all`
- C. `--offset 0`
- D. 不需要加，默认就能看到全部

<details><summary>答案与解析</summary>

**答案：A**。默认 console-consumer 只消费启动后新产生的消息；加 `--from-beginning` 才会从 offset 0 开始读历史消息。

</details>

## 🚀 下一批接力提示词

> 学完本批后，**复制下面这段文字发给 AI**，即可无缝进入下一批（无需重新描述上下文）：

```
继续学 Kafka。我的学习档案在 kafka/00-学习档案.md，
刚学完阶段 2《Kafka 核心架构》的课《本地起 Kafka + CLI 快速上手》知识点 KRaft一键起、创建Topic生产消费、CLI观察Partition，
请按大纲继续讲解下一批知识点（课4：Topic、Partition 与 Broker）。
```

## 🧭 课程导航

⬅️ **上一课**：[课 2：Kafka 是什么 & 起源与定位](../../1-为什么需要Kafka/lessons/lesson-02-Kafka是什么与起源定位.md)

➡️ **下一课**：[课 4：Topic、Partition 与 Broker](lesson-04-Topic、Partition与Broker.md)

📚 **返回目录**：[课程目录](../../../02-课程目录.md)
