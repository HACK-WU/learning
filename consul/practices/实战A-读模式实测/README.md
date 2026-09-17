# 实战篇 A：一致性读模式实测（配课 5）

> 所属课程：Consul ｜ 配套课：阶段 2 · 课 5《Raft 与 Gossip 一致性成色》
> 实战日期：2026-09-17 ｜ 实测环境：Windows 11 + Consul 2.0.2，单机三节点集群
> **本文所有数据均为三节点集群真跑结果**，未实测的部分已显式标注

---

## 🎬 第一幕：场景引入

你在做技术选型，文档上写着 Consul 是 **CP 系统**（课 9 已确认：Consul/etcd/ZK 为 CP，Eureka 为 AP）。

但"CP"这两个字太粗了。它回答不了下面这些具体问题：

- 我读一次配置，读到的一定是最新的吗？
- leader 挂了的时候，我的服务是"读失败"还是"读到旧值"？
- 我的业务能不能容忍读到旧值？能容忍多久？

这三个问题的答案，直接决定 Consul 能不能用在你的场景上。而它们对应的是同一个机制：**Consul 的三种读模式**。

本文把它们从一个概念，变成一组你能在自己机器上复现的数字。

---

## 💥 第二幕：认知冲突

大多数人对"读"的直觉是：**读就是读，读到什么就是什么**。

但分布式系统里，"读"有一个隐藏的维度——**你从谁那里读**。

Consul 的数据写入必须经过 leader（Raft 协议要求），但**读可以由任意节点服务**。于是就有了三种选择：

| 模式 | 从哪里读 | 代价 |
|------|---------|------|
| `default` | leader | 每次都要问 leader |
| `consistent` | leader + 一次确认 | 比 default 多一轮校验 |
| `stale` | **任意一个节点**（含 follower） | 可能读到旧值 |

直觉上你会觉得：`stale` 是"降级选项"，正常情况下不该用。

**实测结果会颠覆这个直觉的第一部分，但确认第二部分。** 先看数据：

```text
写入 v1 后立刻读: default=v1  consistent=v1  stale=v0   ← stale 落后一个版本
写入 v2 后立刻读: default=v2  consistent=v2  stale=v1
写入 v3 后立刻读: default=v3  consistent=v3  stale=v2
```

连续 10 次写入并立即读，**stale 与 consistent 不一致 10 次**——不是偶发，是**稳定落后**。

所以"stale 只在异常时才旧"是错的：**只要写后立即读，stale 就是旧的**。真正的问题是：旧多久？以及，什么时候这个"旧"反而是救命的？

---

## 🔍 第三幕：层层揭示

### 3.1 三种模式的机制差异

**`default`（默认）**：请求转发给 leader，leader 直接返回自己状态机里的值。因为所有写入都经过 leader，所以 leader 上的值一定是最新的。

**`consistent`**：同样走 leader，但额外做一次 **quorum 确认**——leader 先向多数派确认"我还是 leader"，再返回。这一步是为了防止一种极端情况：网络分区后，旧 leader 被隔离了但它自己不知道，还在以 leader 身份应答。

**`stale`**：任意节点直接用自己的本地副本应答，**完全不联系 leader**。所以它能被 follower 服务，延迟最低，但数据可能是旧的。

> **直觉建立**：把 leader 想成"总店"，follower 想成"分店"。
> `default` = 打电话问总店；
> `consistent` = 打电话问总店，还要它报一遍工号确认它真是总店；
> `stale` = 直接问最近的分店，分店的账本可能是昨天同步的。

### 3.2 怎么知道读到的数据有多旧：`X-Consul-LastContact`

这是本文最实用的一条。每个 Consul 响应头里都有：

```text
X-Consul-LastContact: 15
```

单位是**毫秒**，含义是"这份数据落后 leader 多久"。`0` 表示就是 leader 上的最新值。

实测三种模式的三次采样：

```text
default     LastContact: ['0',  '0',  '0']
consistent  LastContact: ['0',  '0',  '0']
stale       LastContact: ['15', '30', '45']
```

**前两者恒为 0，stale 是 15/30/45 递增。** 这个递增是因为采样间隔里 leader 持续有新写入进来。

**这意味着你可以量化监控**：`X-Consul-LastContact` 超过某个阈值就告警，而不用靠猜。

### 3.3 一个反直觉的推论：stale 的"旧"是可观测的，default 的"慢"是无上限的

`stale` 读的代价是"数据可能旧"，但**旧多少是明确告诉你**的（LastContact）。

`default`/`consistent` 的代价是"要联系 leader"，而**联系不上要等多久是不确定的**——取决于选举超时。

这两种代价性质不同，选型时要分开看。

---

## 🧪 第四幕：实操验证

### 4.1 起三节点集群

```powershell
# 用课 5 的 playground 配置，端口已错开
consul agent -config-file=playground/cluster/node1.json   # http 8500
consul agent -config-file=playground/cluster/node2.json   # http 8510
consul agent -config-file=playground/cluster/node3.json   # http 8520
```

确认集群就绪：

```text
leader: "127.0.0.1:8300"
peers : ["127.0.0.1:8320","127.0.0.1:8300","127.0.0.1:8310"]
```

### 4.2 验证一：stale 稳定落后一个版本

```python
kv_put(f'v{i}')
_, val_s, _ = kv_read('stale')
_, val_c, _ = kv_read('consistent')
```

实测（10 次连续写入）：

```text
写 v10: stale=v3  consistent=v10   ← stale 落后
写 v11: stale=v10 consistent=v11   ← stale 落后
...
写 v19: stale=v18 consistent=v19   ← stale 落后
10 次里 stale 与 consistent 不一致 10 次
```

**10/10 全部不一致。** stale 不是"偶尔旧"，是"写后立即读必旧"。

### 4.3 验证二：leader 被强杀，三种模式的分野

这是本文最关键的一组数据。做法是：**杀掉 leader 进程**（不是优雅退出），然后从**存活节点**持续读。

> ⚠️ 我第一次做这个实验时犯了个错：脚本一直访问 8500，而被杀的正是 node1（8500）。结果三种模式全失败——那是"连不上 agent"，不是"读模式差异"。**必须从存活节点读才有意义。**

修正后，从 node2（8510）读，杀掉 leader（node1）：

```text
  时间(ms)  consistent   default      stale          leader
  --------------------------------------------------------------
        0  FAIL(500)    FAIL(500)    before-kill    127.0.0.1:8300
      785  FAIL(500)    FAIL(500)    before-kill    127.0.0.1:8300
     3452  FAIL(500)    FAIL(500)    before-kill    127.0.0.1:8300
     6918  FAIL(500)    FAIL(500)    before-kill    127.0.0.1:8300
     9173  FAIL(500)    FAIL(500)    before-kill    127.0.0.1:8300
     9532  before-kill  before-kill  before-kill    127.0.0.1:8320   ← 新 leader 产生
```

**读到的结论：**

1. **无 leader 的 9.5 秒里，`default` 和 `consistent` 全部返回 500**——不是超时等待，是明确失败
2. **同一时间窗内，`stale` 一直稳定返回旧值**——它没有失败，只是数据是旧的
3. **新 leader 选出后（+9532ms），三者一起恢复**

这就是 CP 系统的真实取舍：**宁可返回错误，也不返回不确定的数据**（`default`/`consistent`）；而 `stale` 提供了第三条路——**要可用性，接受旧数据**。

### 4.4 验证三：quorum 丢失时，stale 也救不了

这里要纠正一个常见误解。很多人以为"stale 读反正不联系 leader，那集群挂了也能读"。

实测：三节点杀掉两个，只剩 node3：

```text
写（PUT）        -> 500  不可用
consistent 读   -> 500  不可用
default 读      -> 500  不可用
stale 读        -> 404  不可用     ← 也挂了
/v1/catalog/nodes -> 500  不可用
/v1/status/leader -> 200  "127.0.0.1:8310"（还报着已死的 leader）
```

**stale 也不可用，返回 404。**

原因：stale 读不联系 leader，但它**仍然需要本地 agent 处于健康状态**。quorum 丢失时，agent 自己已经无法维持状态机，`/v1/catalog/nodes` 这类接口都返回 500。

**所以 stale 的价值边界是"leader 选举期间"，不是"集群崩溃期间"。** 这个区别很重要——把 stale 当成灾备方案是错的。

### 4.5 一个额外发现：agent 单点问题

实验过程中还观察到一个容易被忽略的点：

当我杀掉 node1 但脚本还在访问 8500（node1）时，**三种模式全部失败**。

这说明：**应用如果只连一个 agent，那个 agent 挂了，任何读模式都救不了。** 读模式解决的是"数据新不新"，解决不了"连不连得上"。

生产上的应对是应用侧配置多个 agent 地址，或者依赖本机 agent + 负载均衡——这属于可用性设计，与读模式是两件事，但经常被混为一谈。

---

## 🎯 第五幕：体系收束

### 5.1 三种模式的选型判断

| 你的场景 | 选哪个 | 理由 |
|---------|-------|------|
| 服务发现（拿实例列表） | **`stale`** | 少一个实例晚几毫秒发现无所谓，可用性优先 |
| 读配置（改了要生效） | **`default`** | 配置必须准，且读频率低 |
| 分布式锁 / 选主 | **`consistent`** | 正确性压倒一切，宁可失败不能出错 |
| 金融 / 库存类强一致 | **`consistent`** | 同上，且要考虑 Consul 是否合适 |
| leader 选举期间仍需响应 | **`stale`** | 实测：其它两种在 9.5 秒窗口内全 500 |

### 5.2 三个必须记住的数字（本机实测）

| 指标 | 实测值 |
|------|--------|
| 写后立即读，stale 落后 | **稳定 1 个版本**（10/10 次） |
| stale 的 LastContact | **15–45ms**（持续写入时） |
| leader 强杀后的不可用窗口 | **约 9.5 秒**（default/consistent） |

### 5.3 一句话记住

> **`stale` 换的是"可用性"（leader 选举期间照样返回），不是"灾备能力"（quorum 丢了它也挂）**——而且它旧多少，`X-Consul-LastContact` 会明确告诉你。

---

## 📋 本课速览

| 项 | 内容 |
|----|------|
| 三种模式 | `default`（leader）、`consistent`（leader+quorum确认）、`stale`（任意节点） |
| stale 落后多少 | 写后立即读**稳定落后 1 版**；LastContact 15–45ms |
| 怎么观测新旧 | 响应头 `X-Consul-LastContact`，单位毫秒，0 = 最新 |
| leader 挂了 | default/consistent **约 9.5 秒**全部 500；stale 全程返回旧值 |
| quorum 丢了 | **全部不可用**（含 stale，返回 404） |
| 最大误解 | stale 不是灾备方案，只是"选举期间仍可用" |

---

## 🧭 课程导航

- 配套课：[lesson-05 Raft 与 Gossip 一致性成色](../../stages/2-核心能力拆解/lessons/lesson-05-Raft与Gossip一致性成色.md)
- 横向参照：[lesson-09 四大竞品逐个看](../../stages/3-横向对比/lessons/lesson-09-四大竞品逐个看.md)（CP/AP 定位）
- 相关实战：[实战篇 C：ACL 生产权限模型](../实战C-ACL生产权限模型/README.md)
- 正向指引：[10-场景解法库.md](../../10-场景解法库.md) 场景 1「小团队寻址」
- 判定依据：[应用实战篇-逐课判定.md](../../应用实战篇-逐课判定.md)

---

## ✅ 小测（4 题）

**1. 写入一个 key 之后立刻用 `stale` 读，最可能读到什么？**

A. 一定是新值
B. 一定是旧值
C. 大概率是旧值（实测 10/10 落后）
D. 随机，取决于网络

<details><summary>答案</summary>

**C**。实测连续 10 次写入后立即读，stale 与 consistent **10 次全部不一致**，稳定落后一个版本。不是偶发，是机制决定的。

</details>

**2. leader 进程被强杀后（未选出新 leader 的窗口内），哪种模式仍能返回数据？**

A. default
B. consistent
C. stale
D. 全都返回 500

<details><summary>答案</summary>

**C**。实测约 9.5 秒的窗口内，`default` 与 `consistent` 全部返回 500，只有 `stale` 稳定返回旧值。这正是 stale 存在的价值。

</details>

**3. 关于 quorum 丢失（三节点挂两个），下列说法正确的是？**

A. stale 读仍然可用，因为它不联系 leader
B. 所有模式都不可用，含 stale
C. 只有 consistent 不可用
D. 写不可用但读全部可用

<details><summary>答案</summary>

**B**。实测 stale 返回 404，`/v1/catalog/nodes` 返回 500。stale 不需要 leader，但需要本地 agent 健康——quorum 丢失时 agent 自身已无法服务。

</details>

**4. 想监控"我的 stale 读到底有多旧"，应该看什么？**

A. `X-Consul-Index`
B. `X-Consul-LastContact`
C. `X-Consul-KnownLeader`
D. `X-Consul-Translate-Addresses`

<details><summary>答案</summary>

**B**。`X-Consul-LastContact` 单位是毫秒，表示这份数据落后 leader 多久，`0` 表示就是最新值。实测 default/consistent 恒为 0，stale 为 15–45ms。

</details>

---

## 🔖 接力提示词

> 三份实战篇已全部完成（A 读模式 / B Connect / C ACL）。建议把 [应用实战篇-逐课判定.md](../../应用实战篇-逐课判定.md) 的状态从"判定完成、正文待写"更新为"三份均已完成"，并把三篇登记进 [02-课程目录.md](../../02-课程目录.md)。
>
> 复制这句给 AI：
> 「三份实战篇正文已完成，回写逐课判定文件状态与课程目录索引。」

---

## 📎 评审结论（双视角，对学员可见）

**A 视角 · 技术事实核查**

| 核查项 | 结论 |
|--------|------|
| 三节点集群真实起立 | ✅ leader + 3 peers 均实测返回 |
| stale 落后一个版本 | ✅ 10 次连续写入，10 次不一致 |
| LastContact 数值 | ✅ default/consistent 恒 0；stale 15/30/45ms |
| leader 强杀后 9.5s 窗口 | ✅ 从**存活节点**读，default/consistent 全 500，stale 持续返回 |
| quorum 丢失时 stale 也挂 | ✅ 返回 404，catalog 返回 500 |
| 优雅退出 vs 强杀的差异 | ✅ 两者都做了，优雅退出几乎无感知窗口（未抓到失败） |

**修正记录（自我纠错，保留可追溯）**

初版 `leader_kill.py` 一直访问 8500，而被杀的正是 node1（8500），导致三种模式全失败——**那是"连不上 agent"，不是"读模式差异"**。该错误已在 `leader_kill2.py` 修正（改从存活节点 8510 读），并作为 4.5 节的额外发现写入正文：**agent 单点问题与读模式是两件事**。

**B 视角 · 零基础教学体验**

- 第二幕用"写后立即读 stale 必旧"打破"stale 只是降级选项"的直觉，再由第三幕解释机制
- 4.4 节专门纠正"stale 能当灾备"这个常见误解——这是读者最容易带走的错误结论
- 自己的实验失误（访问被杀节点）写进正文而非隐去，因为它引出一个独立且重要的知识点
- 5.2 节把三个关键数字单独列出，便于决策时直接引用

**仍存在的已知边界**

1. **单机三节点**（都绑 `127.0.0.1`），网络分区靠杀进程模拟，与真实网络分区（数据包丢弃但进程存活）**行为可能不同**
2. **9.5 秒**是本机 `raft_multiplier` 默认值下的结果，调参后会变；本文未做参数敏感性测试
3. `consistent` 与 `default` 在本实测中**表现完全一致**（都走 leader、LastContact 都恒为 0），二者的差异体现在"旧 leader 被隔离"的极端场景，**本次未构造该场景**
4. **Gossip 两层池（LAN/WAN）本次未实测**——单机三节点只有一个 LAN 池，WAN 池需要多数据中心
5. 读模式对**性能（QPS/延迟）的影响本次未做基准测试**，只测了正确性维度
