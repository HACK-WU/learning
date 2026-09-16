# 课 19：协议版本与兼容性

> 所属阶段：阶段 7（实现原理）· 第 3 课
> 实测环境：3 节点 KRaft 集群（`apache/kafka:4.0.0`），Windows WSL Docker
> 全部数值均为本机实测

---

## 第一幕：场景引入——「升级 broker 要不要停业务？」

你要把 Kafka 集群从 3.x 升到 4.0。老板问：

> 「升级要不要停业务？先升 broker 还是先升客户端？」

这是个价值百万的问题。如果答案是「必须全停一起升」，那意味着一次全站停服；如果答案是「可以滚动升级」，风险和时间成本天差地别。

**Kafka 给出的答案是什么？**

官方在 [Protocol](https://kafka.apache.org/43/design/protocol/) 页面的 *Compatibility* 一节开头，第一句话就是：

> Kafka has a **"bidirectional" client compatibility policy**. In other words, **new clients can talk to old servers, and old clients can talk to new servers**. This allows users to upgrade either clients or servers without experiencing any downtime.

**双向兼容**：新客户端能连老 broker，老客户端也能连新 broker。所以可以**先升一边，再升另一边，全程不停服**。

这个承诺是怎么兑现的？这就是本课要讲的：**协议版本与兼容性**。

> 📌 **一句话本质**：本课做的事，是把「换版就得所有人一起停着换（或者新旧两套长期并行）」改成「**先开口问一句拿到清单，两边各退一步取都会的那一级，对面照这一级回话**」——于是可以先换一头、再换另一头，全程不停。
>
> ⚖️ **处境对照**（沿用第一幕老板那句"升级要不要停业务"）：
> - **不这么做（强绑定 / 多套并行）**：要么**必须全停一起升**（一次全站停服）；要么服务端同时维护多套接口，**每加一版就多一套代码路径**，越搬越沉。
> - **这么做（建连时协商）**：客户端用最低版本问一句 brokers 的能力集（**无需认证**，否则无法自举），之后每个请求都带"双方都支持的最高版本"，**broker 按这个版本构造响应**——老客户端和新客户端连同一个 broker，拿到的字节格式不同，各自都能解析。**先升一边，全程不停服。**
>
> ⏳ **数字来源说明**：**183 个 API**、**33 个 UNSUPPORTED**、`Produce(0): 0 to 12`、`Fetch(1): 4 to 17`、`Metadata(3): 0 to 13`、实际使用版本 `Fetch=17 / Metadata=13 / ApiVersions=4` 均为**本课 3 节点实验环境实测值**（`apache/kafka:4.0.0`）。**这些数字随 Kafka 版本变化**（本环境就有 33 个较新能力尚未实现），且 `Fetch` 起点是 4 而非 0——说明**极旧版本已被移除**。请以自己环境中 `kafka-broker-api-versions.sh` 的实际输出为准。

---

## 第二幕：认知冲突——「协议只能有一个版本」的直觉

### 2.1 你的直觉

通常我们理解「协议版本」是这样的：

```text
服务提供 v1 接口 → 客户端用 v1 调用
服务升级到 v2   → v1 接口下线 → 客户端必须跟着改
```

要么是**强绑定**（必须同时升级），要么服务端**同时维护多套接口**（`/v1/xxx`、`/v2/xxx`）。

后者的成本很高：每加一个版本，服务端就要多一套代码路径。

### 2.2 Kafka 的做法：版本是「协商」出来的

Kafka 没有 `/v1`、`/v2` 这样的路径。它是这样工作的：

```text
客户端连上来 → 问 broker「你支持 Produce 的哪些版本？」
broker 回答  → 「我支持 0 到 12」
客户端      → 我最高支持 12，那咱就用 12
```

**每次请求都带着版本号**，broker 按这个版本解析和响应。

这就引出了一个关键问题：客户端怎么知道 broker 支持哪些版本？

### 2.3 自举难题

「问 broker 支持哪些版本」这个请求本身，也需要一个版本啊——**先有鸡还是先有蛋**？

Kafka 的解法是：**`ApiVersions` 请求本身用最低版本（v0）发送**，它是所有版本的公约数。拿到响应后，客户端就知道了 broker 的全部能力，之后的请求按需选用。

官方原文：

> In order to work against multiple broker versions, clients need to know what versions of various APIs a broker supports. The broker exposes this information **since 0.10.0.0** as described in **KIP-35**.

> 📖 **KIP 是什么**：KIP = **Kafka Improvement Proposal**（Kafka 改进提案）。Kafka 的**任何行为变更都要先写一份 KIP** 并经社区讨论通过，所以它是**最权威的"为什么这么设计"出处**——本课提到的 `ApiVersions` 就是 KIP-35 引入的。查资料时看到 `KIP-848` 这类编号，直接搜 "KIP-848" 就能找到原始设计文档。

以及官方给出的完整握手序列：

> - Client sends **ApiVersionsRequest** to a broker after connection has been established with the broker. If SSL is enabled, this happens after SSL connection has been established.
> - On receiving ApiVersionsRequest, a broker returns its full list of supported ApiKeys and versions **regardless of current authentication state** (e.g., before SASL authentication).
> - Supported API versions obtained from a broker are **only valid for the connection** on which that information is obtained. In the event of disconnection, the client should obtain the information from the broker again, as the broker might have been upgraded/downgraded.

**三点注意**：

1. 在连接建立后（SSL 则在 SSL 握手后）立即发送。
2. **不要求认证**——这是刻意设计，未认证的客户端也要能问（否则无法自举）。
3. **只对本次连接有效**，断线重连要重新问（因为 broker 可能已经升降级了）。

### 2.4 冲突的核心

| 你的直觉 | Kafka 的设计 |
|---------|-------------|
| 一个 API 一个版本 | 一个 API **同时支持一个版本区间**（如 `Produce: 0 to 12`） |
| 版本写死在客户端 | 版本在**建连时协商**，取双方交集的最高版 |
| 服务端维护多套代码 | 每个 API 有版本化的 schema，broker 按请求携带的版本解析 |
| 版本信息全局有效 | **只对当前连接有效**，断线必须重问 |

---

## 第三幕：层层揭示

### 一眼全局图（进入细节前先看一眼）

![换版要不要全停](../assets/lesson19-global-ask-first.svg)

> 看图：**左右两边是同一个难题——规矩要换新，已经在外面跑着的那些怎么办**。左边两条路都不好走：要么**旧规矩立刻作废、没跟上的一律挡在门外**（于是只能挑夜深人静一起停、一起换），要么**新旧两套并行摆着**（每加一版多一套，越搬越沉，还得一直给旧的留位置）。右边是第三种：**先用最朴素的那种问法开口**（谁都听得懂，问到了才敢往细了说）→ 对面回一张**清单**（这项我会 1 到 8 级、那项我还不会）→ **两边各退一步，取都会的那一级**（取最高的那级）。**下面两格是配套的好处**：对面**照你说的那一级回话**（你说几级他就用几级的规矩答你）；想加个小规定又不想换版，就写成"**可选**"的，**没写就不占地方**。**最下面那句是代价**：能先换一头再换另一头，是因为那张清单和这些老规矩都得一直留着。

**四条硬约束**说明：① 本图只回答"本课要解决什么问题、靠什么思路"；② 图上不出现术语（`ApiVersions`、ApiKey、版本协商、Tagged Fields、双向兼容这些词都在下面才出场）；③ 已带读图指引；④ 图旁文字能独立说清同一件事。

### 本课地图（分几步走）

| 步 | 这一步要解决什么（人话） | 对应知识点 |
|:--:|------------------------|-----------|
| 1 | 先问一句：怎么开口问、问到的清单长什么样 | `ApiVersions` 自举与能力表 |
| 2 | 取交集：双方各退一步，最后到底用哪一级 | 版本协商规则 |
| 3 | 亲眼验一遍：对面真的按说好的那一级在回话吗 | 实测：能力表与实际使用版本 |
| 4 | 老规矩为什么还留着：这个"不用停"的承诺代价是什么 | 兼容的真实代价与演进的两条路 |

> 只回答"分几步走、现在在哪"；不写机制、不写结论；**不标学习状态**（进度以 `00-学习档案.md` 为准）。

### 3.1 一句话定义

> 🧭 第 1/4 步｜承接：第一幕老板那句"升级要不要停业务" → 本步：先看怎么开口问、问到的清单长什么样

> Kafka 的协议由**一组带编号的 API（ApiKey）**构成，每个 API 支持一个**版本区间**。客户端建连后先发 `ApiVersions` 询问 broker 的能力集，之后每个请求都携带「双方都支持的最高版本」，broker 按该版本解析并响应。

### 3.2 直觉建立：多语言会议

想象一场国际会议：

```text
参会者（客户端）入场时问主办方（broker）：
  「你会哪些语言？每种语言熟练度多少？」
主办方递上一张表：
  「中文：1-10 级（我最高 10 级）」
  「英文：1-8 级」
  「日文：我不会」
参会者看表，选一个双方都懂的最高等级开始交谈
```

`ApiVersions` 就是那张能力表。每个 API 的 `min_version` 到 `max_version` 就是「熟练度区间」。

### 3.3 核心原理：版本协商

> 🧭 第 2/4 步｜承接：上一步学会了怎么开口问 → 本步：说清"各退一步"到底怎么取——规则与它的边界

```mermaid
sequenceDiagram
sequenceDiagram
    participant C as 客户端
    participant B as Broker

    Note over C,B: ① TCP 连接建立（+SSL 握手，若启用）
    C->>B: ApiVersionsRequest (v0，最低版本)
    Note right of B: 无需认证即可响应<br/>（KIP-35，自举设计）
    B-->>C: ApiVersionsResponse v0~4<br/>{ApiKey: 0(Produce), min:0, max:12}<br/>{ApiKey: 1(Fetch), min:4, max:17}<br/>...共 183 项
    Note over C: ② 取 min(客户端max, broker max)<br/>Produce → 12，Fetch → 17
    C->>B: ProduceRequest (version=12)
    B-->>C: ProduceResponse (version=12)
    Note over C,B: ③ 连接断开 → 版本信息作废
    Note over C: 重连后必须重新 ApiVersions
```

协商规则官方原文：

> The intention is that clients will support a range of API versions. When communicating with a particular broker, a given client should use **the highest API version supported by both** and indicate this version in their requests.
>
> The server will **reject requests with a version it does not support**, and will always respond to the client with **exactly the protocol format it expects** based on the version it included in its request.

**第二条极其重要**：broker 不只是「接受」请求，而是**用请求中声明的版本格式来构造响应**。这意味着：老客户端（用 v3）和新客户端（用 v13）连同一个 broker，拿到的**响应字节格式是不同的**，各自都能正确解析。

> 看图（上图）：**分三段看**。第一段是"**开口问**"——连接刚建好，客户端先用**最朴素的那种问法**（最低版本）发一句"你会哪些"，对面**不用报身份也答**（这是刻意的，否则还没开口就被拦住了）。第二段是"**取交集**"——对方回一张清单（每项标明从几级到几级），客户端**两边各退一步，取都会的那一级**（取最高的那级）。第三段是"**照办**"——之后每个请求都带着这个级别，对面**按这个级别回话**。**最后那行别漏**：这个约定**只对这一次连线有效**，断了就得重新问一遍。

### 3.4 实测：broker 的能力表长什么样

> 🧭 第 3/4 步｜承接：上一步讲清了协商规则 → 本步：亲眼验一遍——对面真按说好的那一级在回话吗？先看能力表长什么样

我们用 `kafka-broker-api-versions.sh` 查询真实 broker。

```bash
docker exec l15-kafka-1 bash -c 'export PATH=/opt/kafka/bin:$PATH; unset KAFKA_JMX_OPTS
kafka-broker-api-versions.sh --bootstrap-server kafka-1:9092'
```

实测输出（截取）：

```text
kafka-1:9092 (id: 1 rack: null isFenced: false) -> (
	Produce(0): 0 to 12 [usable: 12],
	Fetch(1): 4 to 17 [usable: 17],
	ListOffsets(2): 1 to 10 [usable: 10],
	Metadata(3): 0 to 13 [usable: 13],
	OffsetCommit(8): 2 to 9 [usable: 9],
	OffsetFetch(9): 1 to 9 [usable: 9],
	FindCoordinator(10): 0 to 6 [usable: 6],
	JoinGroup(11): 2 to 9 [usable: 9],
	Heartbeat(12): 0 to 4 [usable: 4],
	ApiVersions(18): 0 to 4 [usable: 4],
	...
	ConsumerGroupHeartbeat(68): 0 to 1 [usable: 1],
	ShareGroupHeartbeat(76): UNSUPPORTED,
	...
)
```

**统计 API 总数**：

```bash
kafka-broker-api-versions.sh --bootstrap-server kafka-1:9092 | grep -c 'usable:'
```

实测：**183 个 API**。

这个输出里藏着四个必看的信息：

| 字段 | 示例 | 含义 |
|------|------|------|
| API 名与编号 | `Produce(0)` | ApiKey = 0，即 Produce |
| 支持区间 | `0 to 12` | broker 能解析 v0~v12 |
| 可用版本 | `[usable: 12]` | **当前客户端实际会用的版本** |
| 不支持 | `ShareGroupHeartbeat(76): UNSUPPORTED` | broker 完全不认识这个 API |

`UNSUPPORTED` 这一行很重要——它真实展示了「broker 不认识的 API」长什么样。这和「认识但版本不匹配」是两种不同的情况。

本环境实测 **UNSUPPORTED 共 33 个**（均为较新的 Share Group、Telemetry 等能力），举例：

```text
GetTelemetrySubscriptions(71): UNSUPPORTED,
PushTelemetry(72): UNSUPPORTED,
ShareGroupHeartbeat(76): UNSUPPORTED,
ShareGroupDescribe(77): UNSUPPORTED,
ShareFetch(78): UNSUPPORTED,
ShareAcknowledge(79): UNSUPPORTED,
InitializeShareGroupState(83): UNSUPPORTED,
ReadShareGroupState(84): UNSUPPORTED,
WriteShareGroupState(85): UNSUPPORTED,
DeleteShareGroupState(86): UNSUPPORTED,
ReadShareGroupStateSummary(87): UNSUPPORTED
```

而 `ConsumerGroupHeartbeat(68): 0 to 1 [usable: 1]` 则是**支持**的新协议——说明 UNSUPPORTED 反映的是「该 broker 版本尚未实现」，不是「编号大就不支持」。

### 3.5 实测：客户端真的用了协商后的版本吗

光看 `usable` 还不够有说服力。我们直接查 broker 侧记录的**实际请求版本**。

```bash
curl -s http://localhost:17071/metrics | grep -E 'requestspersec_count_total' | grep -v '^#'
```

实测输出（截取）：

```text
kafka_network_requestmetrics_requestspersec_count_total{request="ApiVersions",version="4"} 18.0
kafka_network_requestmetrics_requestspersec_count_total{request="Fetch",version="17"} 706.0
kafka_network_requestmetrics_requestspersec_count_total{request="FetchFollower",version="17"} 706.0
kafka_network_requestmetrics_requestspersec_count_total{request="Metadata",version="13"} 7.0
kafka_network_requestmetrics_requestspersec_count_total{request="AlterPartition",version="3"} 8.0
kafka_network_requestmetrics_requestspersec_count_total{request="BrokerHeartbeat",version="1"} 281.0
kafka_network_requestmetrics_requestspersec_count_total{request="BrokerRegistration",version="4"} 18.0
```

**对照验证**：

| 请求类型 | broker 支持区间 | 客户端实际使用 | 是否等于上界 |
|---------|---------------|--------------|-------------|
| `Fetch` | `4 to 17` | **17** | ✅ |
| `Metadata` | `0 to 13` | **13** | ✅ |
| `ApiVersions` | `0 to 4` | **4** | ✅ |

**完美印证官方规则**：客户端用的正是「双方都支持的最高版本」。

这就是「协商」的实证——不是猜的，是 broker 侧真实记录下来的。

### 3.6 老版本为什么还在：兼容的真实代价

> 🧭 第 4/4 步｜承接：上一步亲眼验证了协商结果 → 本步：回答"老规矩为什么还留着"——这个"不用停"的承诺，代价是什么

你可能注意到 `Produce: 0 to 12` —— **为什么要保留 v0？v0 是 2013 年的格式了**。

因为**双向兼容承诺**：

```text
老客户端（只懂 v0~v3）连新 broker（支持 0~12）
  → 协商结果 v3
  → broker 必须能用 v3 格式解析和响应
```

如果 broker 删掉 v0~v3 的支持，所有老客户端立刻报废。所以：

- **版本只增不减**（废弃版本会保留很久，直到确认无人使用）
- 代价是 broker 侧要维护**多套 schema 转换逻辑**

这就是「双向兼容」的真实成本——不是免费的设计，是用 broker 的复杂度换来的运维自由度。

### 3.7 演进的另一种武器：Tagged Fields（标记字段）

如果每加一个字段都要升版本号，版本号会爆炸。官方给了另一个方案：

> The intended upgrade path is that new features would first be rolled out ... **without incrementing the version number**. This offers an additional way of evolving the message schema without breaking compatibility. **Tagged fields do not take up any space when the field is not set.** Therefore, if a field is rarely used, it is more efficient to use a tagged field than to add a new version.

**Tagged Fields（可选标记字段）** 的精髓：

```text
传统做法：加字段 → 必须升版本 → 所有客户端都要跟进
标记字段：加可选字段 → 不升版本 → 老客户端自动忽略（不认识就跳过）
```

而且**未设置时完全不占空间**——对稀疏字段极其高效。

对比总结：

| 演进方式 | 何时用 | 代价 |
|---------|-------|------|
| **升版本号** | 结构性变更（字段语义变、必填字段增删） | 客户端必须适配 |
| **Tagged Fields** | 新增**可选**的稀疏字段 | 无需升版，老客户端自动兼容 |

这也是为什么 Kafka 的很多新特性（如 KIP-848 新消费组协议的相关字段）能平滑引入。

### 3.8 API 版本区间为什么起点不是 0

注意 `Fetch(1): 4 to 17` —— **起点是 4 不是 0**。

为什么？因为 **v0~v3 已被彻底移除**。Kafka 在 4.0 中做了一次大清理，删掉了极旧的版本。

这引出一个重要判断：**「双向兼容」不是无限的**。官方有明确的废弃策略，过老的版本最终会被移除。所以「老客户端」的定义是有边界的——不是 2013 年的客户端还能连 4.0。

#### 🗣️ 行话对照（本课说法 → 行业术语）

本课用"问一句 / 清单 / 取交集"打比方，读协议文档、查 `kafka-broker-api-versions.sh` 输出、排查升级问题时会遇到下面这些行话——**同一件事的另一套名字**：

| 本课说法（人话） | 行业标准叫法 | 典型配置 / 在哪遇到 | 代价 / 注意 |
|---|---|---|---|
| 先问一句 | **`ApiVersionsRequest` / `ApiVersionsResponse`**（本文自拟译"接口版本查询请求/响应"，非通用译名） | 建连后自动发起；**KIP-35**，自 0.10.0.0 起 | 用**最低版本 v0** 发送（自举）；**无需认证**；**只对当前连接有效**，断线必须重问 |
| 那张清单 | **ApiKey 及其版本区间**（本文沿用"A​​piKey"；本文自拟译"接口编号"，非通用译名） | `kafka-broker-api-versions.sh` | 实测 **183 个 API**；每个形如 `Produce(0): 0 to 12` |
| 我会到哪一级 | `min_version` ~ `max_version` | 同上 | 区间**起点可能不是 0**（如 `Fetch: 4 to 17`，v0~v3 已移除） |
| 实际会用哪一级 | **`usable:`** 标记 | 输出里的 `[usable: 12]` | 这是**当前客户端协商后实际使用**的版本 |
| 这项我还不会 | **`UNSUPPORTED`** | 同上 | 实测 **33 个**（较新的 Share Group / Telemetry 等）；与"认识但版本不匹配"是**两回事** |
| 各退一步取交集 | **版本协商**（本文沿用"版本协商"） | 客户端自动完成 | 规则：**取双方都支持的最高版本** |
| 照你说的那一级回话 | broker **按请求声明的版本构造响应** | 官方原文明确 | 老客户端与新客户端连同一 broker，**拿到的字节格式不同**，各自都能解析 |
| 双向兼容 | **bidirectional client compatibility policy**（本文自拟译"双向客户端兼容策略"，非通用译名） | [Protocol · Compatibility](https://kafka.apache.org/43/design/protocol/) | 新客户端连老 broker、老客户端连新 broker → **可先升一边、不停服**；代价是 broker 维护多套 schema |
| 想加个小规定又不换版 | **Tagged Fields**（本文自拟译"标记字段"，社区常用译法、官方未定中文名） | 协议规范中的可选字段 | **未设置时完全不占空间**；老客户端遇到不认识的标记字段**自动跳过** |
| 加字段的两条路 | **升版本号** vs **Tagged Fields** | — | 结构性变更 → 升版本号（客户端必须适配）；可选稀疏字段 → Tagged Fields（不升版） |
| 报一下自己是谁 | `client_software_name` / `client_software_version` | `ApiVersions` **v3+** 才有 | 供可观测性用；老版本请求里没有这两个字段 |

> 📖 **关于译名**：本表带"本文自拟译"字样的中文名是**为便于阅读自拟的、非通用译名**；带"社区常用译法、官方未定中文名"的是社区在用但官方未定名的译法；`ApiKey` / `ApiVersions` 等**沿用英文原名**。**标注只在首次登场给一次**，后文不再重复括注。
>
> 🔎 **别把两层搞混**：课 13 讲的是**消息体的二进制格式**（货长什么样），本课讲的是**请求/响应的版本协商**（用哪套规矩解读）。前者是 payload，后者是 protocol。

---

## 第四幕：实操验证

### 4.1 步骤 1：查看 broker 完整能力表

```bash
docker exec l15-kafka-1 bash -c 'export PATH=/opt/kafka/bin:$PATH; unset KAFKA_JMX_OPTS
kafka-broker-api-versions.sh --bootstrap-server kafka-1:9092'
```

预期：输出 183 个 API 及其版本区间。重点看：

```text
Produce(0): 0 to 12 [usable: 12],
Fetch(1): 4 to 17 [usable: 17],
Metadata(3): 0 to 13 [usable: 13],
ApiVersions(18): 0 to 4 [usable: 4],
```

### 4.2 步骤 2：统计 API 总数

```bash
docker exec l15-kafka-1 bash -c 'export PATH=/opt/kafka/bin:$PATH; unset KAFKA_JMX_OPTS
kafka-broker-api-versions.sh --bootstrap-server kafka-1:9092 | grep -c "usable:"'
```

预期：`183`（本文实测值；不同 Kafka 版本数量会不同）

### 4.3 步骤 3：找一个 UNSUPPORTED 的 API

```bash
docker exec l15-kafka-1 bash -c 'export PATH=/opt/kafka/bin:$PATH; unset KAFKA_JMX_OPTS
kafka-broker-api-versions.sh --bootstrap-server kafka-1:9092 | grep UNSUPPORTED'
```

预期（本环境实测 **33 个**，此处仅列前几项）：

```text
	GetTelemetrySubscriptions(71): UNSUPPORTED,
	PushTelemetry(72): UNSUPPORTED,
	ShareGroupHeartbeat(76): UNSUPPORTED,
	ShareGroupDescribe(77): UNSUPPORTED,
	...
```

统计数量：

```bash
kafka-broker-api-versions.sh --bootstrap-server kafka-1:9092 | grep -c UNSUPPORTED
```

预期：`33`

### 4.4 步骤 4：验证客户端实际使用的版本

先产生流量：

```bash
docker exec l15-kafka-1 bash -c 'export PATH=/opt/kafka/bin:$PATH; unset KAFKA_JMX_OPTS
kafka-producer-perf-test.sh --topic net-demo --num-records 8000 --record-size 512 \
  --throughput -1 --producer-props bootstrap.servers=kafka-1:9092 acks=1'
```

再查实际版本：

```bash
curl -s http://localhost:17071/metrics | grep -E 'requestspersec_count_total\{request="(Fetch|Metadata|ApiVersions)"' | grep -v '^#'
```

预期：`Fetch version=17`、`Metadata version=13`、`ApiVersions version=4`，**与 broker 的 usable 上界一致**。

### 4.5 步骤 5：查看客户端软件名（v3+ 特性）

`ApiVersions` 从 **v3** 起支持客户端上报自己的软件名与版本：

```text
ApiVersions Request (Version: 3) => { client_software_name client_software_version }
```

这是官方协议规范里记录的结构。它让 broker 能知道「连上来的到底是什么客户端」——用于可观测性和问题排查。

实测查客户端版本：

```bash
docker exec l15-kafka-1 bash -c 'export PATH=/opt/kafka/bin:$PATH; unset KAFKA_JMX_OPTS
kafka-broker-api-versions.sh --bootstrap-server kafka-1:9092 --version'
```

实测输出：`4.0.0`

---


### 4.2 应用实战（动手篇 · 独立成册）

> 📘 **[→ 打开应用实战：协议版本与兼容性](../../../应用实战/19-协议版本与兼容性.md)**
>
> 课里讲的是「双向兼容 + 建连协商 + Tagged Fields」，实战篇让你自己把承诺证明一遍：① 基础版——以为版本写死、升级就得一起停（或新旧两套并行）；② 综合版——用 `kafka-broker-api-versions.sh` 查能力表与 UNSUPPORTED、说清 `usable` 是怎么取交集算出来的、并用 broker 侧实际记录到的请求版本验证"对面真的按说好的那一级在回话"。

---

## 第五幕：体系收束

### 5.1 一图总结

```mermaid
flowchart TD
    subgraph HANDSHAKE["① 建连协商"]
        A1["TCP 连接建立"] --> A2["ApiVersionsRequest v0<br/>（最低版本自举）"]
        A2 --> A3["broker 返回 183 个 API<br/>的版本区间<br/>无需认证"]
        A3 --> A4["客户端取<br/>min(自己max, broker max)"]
    end
    subgraph REQ["② 请求携带版本"]
        B1["ProduceRequest<br/>version=12"] --> B2["broker 按 v12 解析"]
        B2 --> B3["broker 按 v12 格式<br/>构造响应"]
    end
    subgraph COMPAT["③ 双向兼容承诺"]
        C1["新客户端 ↔ 老 broker"]
        C2["老客户端 ↔ 新 broker"]
        C3["→ 先升一边，不停服"]
    end
    subgraph EVOLVE["④ 演进方式"]
        D1["升版本号<br/>结构性变更"]
        D2["Tagged Fields<br/>可选稀疏字段<br/>不占空间"]
    end
    A4 --> B1
    B3 --> C1
    B3 --> C2
    C1 --> C3
    C2 --> C3
    style A2 stroke:#d29922,stroke-width:2px
    style C3 stroke:#238636,stroke-width:2px
    style D2 stroke:#0969da,stroke-width:2px
```

> 读法：**四块按顺序走**——① 建连后先用最低版本问一句（黄色那格），拿到清单后取双方都会的最高级；② 之后每个请求带着这个级别，broker **按它解析、也按它构造响应**；③ 于是两个方向都能通（绿色那格），**先升一边也不停服**；④ 演进有两条路：结构性变更升版本号，可选稀疏字段走标记字段（蓝色那格，不升版且不占空间）。

> **与课首入口的分工（勿混，三方视角）**：「一眼全局图」在课首、问题视角、零术语，给没学过的人看（回答"为什么需要它、靠什么思路"）；「本课地图」在课首、路线视角（回答"分几步走、现在在哪"），是表格不是图；本图在课末、知识视角，给刚学完的人复习用（回答"本课讲了什么"）。三者不可替代、不雷同。

### 5.2 核心结论（记住这五句）

1. **Kafka 承诺双向兼容**：新客户端能连老 broker、老客户端能连新 broker，因此可以**先升一边、全程不停服**。
2. **版本在建连时协商**，取双方都支持的最高版本——实测 `Fetch version=17`、`Metadata version=13` 均等于 broker 上界。
3. **`ApiVersions` 用最低版本 v0 发送，且无需认证**，这是自举设计（KIP-35，自 0.10.0.0 起）；**版本信息只对当前连接有效**，断线必须重问。
4. **broker 按请求声明的版本构造响应**——不同版本的客户端连同一个 broker，拿到的字节格式不同，各自都能解析。
5. **演进有两条路**：结构性变更升版本号；可选稀疏字段用 **Tagged Fields**（不升版、未设置时不占空间）。

### 5.3 常见误区

| # | 误区 | 正解 |
|---|------|------|
| 1 | 升级必须 broker 和客户端同时进行 | 双向兼容允许先升一边；官方原话 "without experiencing any downtime" |
| 2 | 版本号是客户端写死的 | 建连时协商，取双方交集的最高版；实测值等于 broker usable 上界 |
| 3 | `ApiVersions` 结果可以缓存复用 | **只对当前连接有效**，断线重连后必须重新获取（broker 可能已升降级） |
| 4 | 所有 API 都从 v0 开始 | 实测 `Fetch(1): 4 to 17`，v0~v3 已被移除；「兼容老客户端」有边界 |
| 5 | 加字段就必须升版本号 | 可选稀疏字段可用 Tagged Fields，不升版且未设置时不占空间 |
| 6 | broker 只接受/拒绝版本 | 官方明确：broker 会**按请求声明的版本格式构造响应** |

### 5.4 官方文档

- [Protocol · Compatibility](https://kafka.apache.org/43/design/protocol/)（本课本源）
- [KIP-35 - Retrieving protocol version](https://cwiki.apache.org/confluence/display/KAFKA/KIP-35+-+Retrieving+protocol+version)（`ApiVersions` 的由来）
- [Apache Kafka 官方文档 · 4.3](https://kafka.apache.org/43/documentation.html)
- 完整路由表见 [web-index/kafka/index.md](../../../web-index/kafka/index.md)

### 5.5 与既有课程的关系

```mermaid
flowchart LR
    L13["课 13<br/>消息格式<br/>RecordBatch 二进制"] --> L19["课 19<br/>协议版本<br/>API 协商与兼容"]
    L17["课 17<br/>网络层<br/>请求处理链路"] --> L19
    L16["课 16<br/>集群运维<br/>滚动升级"] --> L19
    style L19 stroke:#d29922,stroke-width:2px
```

课 13 讲的是**消息体的二进制格式**（RecordBatch 长什么样），本课讲的是**请求/响应信封的版本协商**（用哪套格式解读）。两者是不同层次：课 13 是 payload，本课是 protocol。课 17 的请求解析环节正是用本课的版本号来选 schema。课 16 的「不停服升级」之所以可行，底层依据就是本课的双向兼容。

### 5.6 课后小测

**Q1.** 客户端连上 broker 后，为什么要先用 v0 发 `ApiVersions` 而不是直接用高版本？
<details><summary>答案</summary>自举难题：客户端还不知道 broker 支持哪些版本，无法选择「合适的高版本」。v0 是所有版本都支持的公约数，保证请求一定被理解。拿到能力表后，后续请求才能选双方都支持的最高版本。另外官方明确该响应**不要求认证**，正是为了让未认证的客户端也能完成自举。</details>

**Q2.** 你的客户端从 v9 升级到 v13，但 broker 只支持到 v12。会发生什么？
<details><summary>答案</summary>协商结果是 v12（取 `min(客户端13, broker12)`），客户端会用 v12 发请求，功能正常。这正是双向兼容的体现。若客户端**强制**要求 v13 特性而 broker 不支持，则该特性不可用或请求失败——官方明确 broker 会**拒绝不支持的版本**。</details>

**Q3.** 什么情况下该用 Tagged Fields 而不是升版本号？
<details><summary>答案</summary>新增**可选的、稀疏使用**的字段时。Tagged Fields 不需要升版本号，老客户端遇到不认识的标记字段会自动跳过（不破坏兼容），且**未设置时完全不占空间**，对很少用到的字段比新增版本更高效。若是结构性变更（必填字段增删、字段语义变化），则必须升版本号。</details>

---

**下一课**：阶段 7 完结，返回 [阶段 7 概览](../overview.md)

**上一课**：[课 18：消费者位移与协调者](lesson-18-消费者位移与协调者.md)

**返回目录**：[课程目录](../../../02-课程目录.md)
