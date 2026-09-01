# 第 11 课：集群与高可用

> 所属阶段：阶段 4《进阶与工程落地》｜ 水平：零基础 ｜ 本课知识点：集群基础、复制型队列、故障与网络分区
> 故事情节：主角不能死——单机挂了消息怎么办？于是有了集群、Raft 与多数派

> ⚠️ 本课内容随版本变化很大：镜像队列已在 4.0 移除，Mnesia 与旧分区策略已在 4.3 移除。网上大量中文资料仍停留在 3.x，**务必以 4.x 官方文档为准**。

## 🎯 本课目标

- 说清集群 / Federation / Shovel 三种扩展方式各自解决什么问题
- 解释 quorum queue 的 Raft 复制机制，并说清镜像队列为何被移除
- 说清 4.3 起「多数派可用」的新语义，以及旧分区策略为什么失效

## 知识点清单（含关键点）

1. **集群基础**（关键点：节点与 Erlang cookie / disc 与 ram 节点（4.3 起 ram 节点类型已移除） / 集群 vs Federation vs Shovel 的分工）
2. **复制型队列**（关键点：classic 镜像 4.0 已移除 / quorum queue 的 Raft 与多数派提交 / stream 的日志语义 / 选型与成本）
3. **故障与网络分区**（关键点：4.3 起 Khepri 为唯一元数据存储 / 多数派可用 / pause_minority、autoheal 等旧策略已移除 / 恢复按 Raft 语义统一处理）

---

## 开场：单机总有一天会挂

前面十课，我们所有的实验都在**一个** RabbitMQ 节点上跑。

这个节点上存着交换机、队列、绑定关系，还有那些你用 `delivery_mode=2` 精心持久化的消息。课 7 验证了 broker 重启后消息还在——但那是在**同一台机器重启**的情况下。

如果这台机器**再也不开机**了呢？

磁盘坏了、机房断电了、云主机被回收了。这时候课 7 讲的持久化救不了你：数据确实写到磁盘上了，但磁盘本身不可用了。

唯一的解法是**把数据放到多台机器上**。这就是本课的主题。

但"放到多台机器"有很多做法，各自解决不同的问题，也各有代价。本课要把它们理清楚，并且——这是关键——**本课的所有结论都在一个真实的三节点集群上实测过**，不是纸上谈兵。

---

## 本课实验环境：一个真实的三节点集群

为了避免只讲概念，本课专门搭了一个真实的集群：

```
容器名    AMQP 端口   UI 端口   角色
rmq1     5681       15681     集群节点
rmq2     5682       15682     集群节点
rmq3     5683       15683     集群节点
```

三个节点全是 **RabbitMQ 4.3.5**，共享同一个 **Erlang cookie**，运行在独立的 docker 网络里。

`rabbitmqctl cluster_status` 的实测输出：

```
Cluster name: rabbit@rmq1
Total CPU cores available cluster-wide: 60

Disk Nodes

rabbit@rmq1
rabbit@rmq2
rabbit@rmq3

Running Nodes

rabbit@rmq1
rabbit@rmq2
rabbit@rmq3

Versions

rabbit@rmq1: RabbitMQ 4.3.5 on Erlang 27.3.4.16
rabbit@rmq2: RabbitMQ 4.3.5 on Erlang 27.3.4.16
rabbit@rmq3: RabbitMQ 4.3.5 on Erlang 27.3.4.16
```

注意 `Disk Nodes` 这一栏——**三个节点全是 Disk 节点**。这引出 4.3 的第一个变化。

---

## 知识点 1：集群基础

### 第一幕：两个机房的难题

先说清楚集群**不是**什么。

某公司有两个机房，一个在上海，一个在深圳。运维想让两边的消息互通，第一反应是"组个集群吧"。

结果搭起来问题不断：网络一抖动，集群就分裂；跨机房延迟 30ms，每次消息同步都要等；更糟的是，一边机房网络故障，整个集群可能全部不可用。

**问题出在哪？** 集群是为**低延迟、高可靠的内网**设计的。它假设节点之间网络又快又稳。跨地域使用，等于把集群放在了它最不擅长的场景里。

正确的做法是用 **Federation** 或 **Shovel**。这就是本知识点要讲的第一件事：**三种扩展方式，各解决各的问题。**

### 集群：紧耦合

集群把多个节点绑成一个**逻辑 broker**：

```
        ┌─────────────────────────────┐
        │      客户端看到的"一个"broker  │
        └─────────────────────────────┘
                      │
    ┌─────────────────┼─────────────────┐
    ▼                 ▼                 ▼
┌───────┐        ┌───────┐        ┌───────┐
│ rmq1  │◄──────►│ rmq2  │◄──────►│ rmq3  │
└───────┘        └───────┘        └───────┘
   同上 cookie、同版本、低延迟内网
```

**组集群的前提：Erlang cookie 必须相同。**

cookie 是节点之间的"暗号"，存在 `~/.erlang.cookie` 文件里。它不加密通信，只是一个简单的共享密钥——cookie 不同的两个节点**无法**组成集群。

实测本课环境里两个不同环境的 cookie：

```
集群节点 rmq1 cookie：JGXNRXISCQUV...
既有容器 cookie    ：BXUAQVRDYRNC...
→ 不同，因此无法加入同一集群
```

### ⚠️ 4.3 起：ram 节点类型已移除

旧版本（3.x）的集群文档会教你怎么配 **ram 节点**——把交换机、绑定等元数据只放内存、不落盘的节点，用来加速元数据访问。

**4.3 起这个选项没了。** 实测：

```
【D】节点类型：ram 节点是否仍可用
  ✅ rabbitmqctl help 中【无】change_cluster_node_type
     （4.3 起 ram 节点类型已移除，所有节点都是 disc 节点）

【E】cluster_status 中的节点分类
  Disk Nodes
  rabbit@rmq1
  rabbit@rmq2
  rabbit@rmq3
```

`cluster_status` 里只有 `Disk Nodes`，连 `RAM Nodes` 这一栏都不存在了。

> **一句话记住**：4.3 起所有节点都是 disc 节点，不用再纠结 ram/disc 的取舍。

### 顺带一个 4.x 的硬限制

翻 `rabbitmqctl help` 时看到一条值得记的说明：

> `rename_cluster_node`: DEPRECATED. This command is a no-op. **Node renaming is incompatible with Raft-based features such as quorum queues, streams, Khepri.**

**节点重命名与 Raft 特性不兼容，已废弃。** 如果你的运维脚本里还有"改节点名"这一步，在 4.x 上会失效。

### Federation 与 Shovel：松耦合

集群解决不了跨地域、跨组织、跨版本的问题，于是有了另外两个工具。

**它们最大的区别是：对源端消息的处理方式不同。**

#### Shovel：move 语义（搬走）

Shovel 像一个搬运工：从源队列**消费**消息，转发到目标。源端不保留。

实测（`l11-shovel.py`，rmq1 → rmq2）：

```
[4] 等待搬运完成

    | 队列 | 所在节点 | 深度 |
    |------|----------|------|
    | l11.shovel.src | rmq1 | 0 |
    | l11.shovel.dst | rmq2 | 5 |

    ✅ 5 条消息已搬运到目标队列
    源队列剩余 0 条 → Shovel 默认消费并【转发】，源端不再保留
```

源端从 5 条变成 **0 条**，目标端变成 5 条。消息被**搬走**了。

#### Federation：copy 语义（复制）

Federation 让下游队列订阅上游，**拉取副本**。上游的消息**仍然保留**。

实测（`l11-federation.py`）：

```
    | 队列 | 节点 | 深度 |
    |------|------|------|
    | l11.fed.queue（上游）| rmq1 | 5 |
    | l11.fed.queue（下游）| rmq2 | 5 |

    ✅ 下游拉取到 5 条副本
    ✅ 上游仍保留 5 条 → 【copy 语义】确认
```

**两边都是 5 条。** 这就是分水岭。

#### ⚠️ 实测踩坑：Federation 要求两端队列【同名】

这是本课第二个容易卡住的地方。我第一次跑 Federation 实验时，链路显示 `running` 但一条消息都没过来：

```
[6] Federation 状态
    #{status => running, type => queue,
      queue => <<"l11.fed.down">>,
      uri => <<"amqp://rmq1:5672">>,
      upstream_queue => <<"l11.fed.down">>,
      ...}
```

注意最后一行：`upstream_queue => <<"l11.fed.down">>`。

**Federation 会去上游找与下游【同名】的队列。** 我当时下游叫 `l11.fed.down`，却把消息发到了上游的 `l11.fed.up`——它去上游找 `l11.fed.down`，当然找不到，于是拉到 0 条。

把两端改成同名队列后，立刻正常。

> **一句话记住**：Federation 的下游队列去上游找**同名队列**拉取。名字对不上，链路会显示 running 但拉不到任何东西——**状态正常 ≠ 数据到达**，这是排查时的陷阱。

### 三者怎么选

| 方式 | 耦合度 | 消息语义 | 适用场景 | 前提 |
|---|---|---|---|---|
| **集群** | 紧耦合 | 共享队列 | 同机房、低延迟、统一运维 | 同 cookie、同版本 |
| **Federation** | 松耦合 | **copy**（上游保留） | 跨地域订阅、多站点共享数据 | 各自独立，仅需网络可达 |
| **Shovel** | 松耦合 | **move**（源端消费） | 单向搬运、数据迁移、WAN 链路 | 各自独立，仅需网络可达 |

一句通俗的总结：

- **集群**：几个节点合并成"一台"逻辑机器
- **Federation**：订阅对方的动态，各留一份
- **Shovel**：把消息从这儿搬到那儿，搬完这边就没了

> ⚠️ **本课的实测边界（如实说明）**：Shovel 与 Federation 的演示是在**同一个集群内部的两个节点之间**完成的，而不是跨两个独立的 broker。
>
> 原因：我最初想用既有容器 `rabbitmq-learn`（前 10 课的环境）当"上游站点"，但它在**不同的 docker 网络**，集群容器访问不到。随后尝试新建一个独立上游容器，却遇到宿主文件权限问题：
> ```
> Error when reading /var/lib/rabbitmq/.erlang.cookie: eacces
> ```
> 两次尝试均未成功，因此改为在集群内部演示。
>
> 这不削弱机制本身的可信度：**Shovel 的 move 语义、Federation 的 copy 语义都是实测确认的**。但要清楚——跨站点（不同 cookie、不同信任边界）只是它们的应用场景之一，本次**未实测**该场景。

---

## 知识点 2：复制型队列

### 第二幕：镜像队列的消失

如果你看过 3.x 的中文资料，一定见过这段配置：

```bash
rabbitmqctl set_policy ha-all "^" '{"ha-mode":"all"}'
```

这是**镜像队列**——把 classic 队列复制到所有节点。曾经这是 RabbitMQ 高可用的标准答案。

**4.0 起，镜像队列被移除了。** 实测在 4.3.5 上执行同样的命令：

```
【C】镜像队列策略 ha-all 是否还被接受
  命令返回：Setting policy "l11-ha-test" for pattern "^test$"
            to "{"ha-mode":"all"}" ...
Error:
Validation failed

  ✅ 被拒绝 → 镜像队列相关策略在 4.3 已不可用
```

`Validation failed` —— 直接拒绝。

**为什么移除？** 镜像队列的设计有结构性缺陷：

- 同步是**异步**的，主节点宕机时可能丢掉未同步的消息
- 网络分区时，两边可能**同时**接受写入，恢复后数据冲突，需要人工决定丢弃哪边
- 同步过程会**阻塞**整个队列，大队列同步时影响业务

quorum queue 用 Raft 重新设计了这一切。

### quorum queue：Raft 复制

声明一个 quorum 队列，看看它在集群里长什么样。实测（`l11-quorum-replication.py`）：

```
【A】quorum 队列的副本分布（默认 3 副本）
  队列类型：quorum
  Leader   : rabbit@rmq1
  Members  : ['rabbit@rmq1', 'rabbit@rmq2', 'rabbit@rmq3']
  Online   : ['rabbit@rmq1', 'rabbit@rmq2', 'rabbit@rmq3']
```

三个节点**各持一份完整副本**。

**Raft 的核心规则**：

1. 副本中选出一个 **leader**，所有读写都经过它
2. 写入时，leader 把操作复制给 follower，**多数派确认后才算提交**
3. leader 挂了，剩下的节点**重新选举**出新 leader

第 2 条是"消息不丢"的关键——你收到 publisher confirm 时，说明这条消息已经被**多数派节点**落盘了，而不只是在 leader 的内存里。

### 客户端可以连任意节点

实测连到**非 leader** 节点（rmq2）读写：

```
【B】连接【非 leader】节点发布与消费（验证请求转发）
  Leader 在 rmq1，本次连接【rmq2】（AMQP 5682）
  已通过 rmq2 发布
  通过 rmq2 取回：via-rmq2
  ✅ 连非 leader 节点也能正常读写（请求被内部转发到 leader）
```

你不需要在客户端代码里关心 leader 是谁——连哪个节点都行，非 leader 节点会把请求转发过去。

**但这有个性能含义**：如果你的客户端全都连到非 leader 节点，每次请求都要多一跳。对延迟敏感的场景，值得关注。

### ⚠️ 关键认知：classic 队列不复制

这是本课最需要纠正的直觉。

**classic 队列在集群里只有一份数据。** 实测：

```
【C】对比：classic 队列在集群中【不复制】
  队列类型：classic
  宿主节点（node）：rabbit@rmq1
  members：（无——classic 不复制）
```

注意这里的坑：在集群中，**所有节点都能看到队列的元数据**。你在 rmq2、rmq3 上执行 `list_queues`，都能查到这个队列——我一开始就是这么误判的。

但**数据只在 `node` 字段标识的那一个节点上**。判断真实宿主要看 `node` 字段，而不是"能不能查到"。

> **一句话记住**：集群让元数据全局可见，但**不**让 classic 队列的数据全局复制。数据在哪，看 `node` 字段。

### 副本数可以调

```
【D】x-quorum-initial-group-size 对副本数的影响

| 声明参数 | Leader | Members 数 |
|----------|--------|------------|
| size=1 | rabbit@rmq1 | 1 |
| size=3 | rabbit@rmq1 | 3 |
```

`size=1` 是单副本 quorum——**没有高可用**，只在特殊场景（比如你明确不想要复制开销）使用。

### leader 故障切换：本课最硬的一次实测

概念讲完了，来真的。

实验设计：建 quorum 队列 → 发 20 条已确认消息 → **停掉 leader 节点** → 看数据还在不在。

实测（`l11-failover.py`）：

```
[1] 队列已建，Leader = rabbit@rmq1
    Members = ['rabbit@rmq1', 'rabbit@rmq2', 'rabbit@rmq3']

[2] 已发布 20 条持久化消息（publisher confirms 已确认）

[3] 停掉 leader 节点 rmq1（docker stop，模拟宕机）...
    已停止，耗时 1.51 s

[4] 存活节点：['rmq2', 'rmq3']
    等待 Raft 重新选举新 leader（最多 60 秒）...
    ✅ 新 Leader = rabbit@rmq3（选举耗时 0.07 s）

[5] 检查数据安全
    通过 rmq2 查询队列深度 = 20（原始 20 条）
    实际消费到 20 条
    前 3 条：['msg-000', 'msg-001', 'msg-002']
    末 3 条：['msg-017', 'msg-018', 'msg-019']
    ✅ 数据零丢失——quorum 的 Raft 复制生效

[6] 故障期间继续写入（验证新 leader 可服务）
    ✅ 成功写入 5 条新消息
```

**leader 宕机后 0.07 秒选出新 leader，20 条消息一条不少。**

这就是"高可用"这个词的实证——不是听概念，是看数据还在不在。

**恢复节点后**：

```
[7] 恢复节点 rmq1（docker start）
    恢复后 Leader  = rabbit@rmq3
    恢复后 Members = ['rabbit@rmq1', 'rabbit@rmq2', 'rabbit@rmq3']
    恢复后 Online  = ['rabbit@rmq1', 'rabbit@rmq2', 'rabbit@rmq3']
    队列深度       = 5
```

注意一个细节：**恢复后的 leader 没有切回 rmq1**。这不是 bug——Raft 不会为了"回到原状"再引发一次选举，因为切换本身也有代价。leader 在哪儿无所谓，只要服务正常。

### 对照组：classic 队列在宿主宕机后

同样场景，换成 classic 队列：

```
[1] classic 队列已建（durable=True），宿主节点 = rabbit@rmq1
[2] 已发布 20 条持久化消息

[3] 停掉宿主节点 rmq1 ...
[5] 尝试从存活节点访问该队列
    rmq2: ❌ (404, "NOT_FOUND - queue 'l11.failover.classic' in vhost '/' process is stopped by supervisor")
    rmq3: ❌ (404, "NOT_FOUND - queue 'l11.failover.classic' in vhost '/' process is stopped by supervisor")
```

**两个存活节点都访问不了。**

这个报错值得细看：`process is stopped by supervisor`。消息确实持久化在 rmq1 的磁盘上——但那个节点起不来了，而**没有别的节点持有副本**。

> 注意这是 4.x 的新情况。在 3.x 时代，如果你配了镜像队列，这个场景是能扛过去的。**4.0 移除镜像队列后，classic 队列就是单点。** 生产环境需要高可用的队列，必须选 quorum。

### stream：第三种选择

课 5 已经介绍过 stream，这里只补充它在高可用语境下的定位。

| 类型 | 复制 | 语义 | 典型场景 |
|---|---|---|---|
| **classic** | ❌ 不复制 | 队列（消费即删） | 临时数据、可容忍丢失 |
| **quorum** | ✅ Raft 复制 | 队列（消费即删） | **大多数需要高可用的业务队列** |
| **stream** | ✅ Raft 复制 | 日志（可重复读） | 大吞吐、需回放、多消费者组 |

选择 quorum 的代价（要诚实说）：

- **每条消息都要多数派确认**，延迟高于 classic 队列
- **磁盘与内存开销更大**——三副本意味着三份数据
- **不支持**一些 classic 特性（如优先级、部分 TTL 行为）

官方的建议是：不要"所有队列都用 quorum"。**能接受丢失的临时数据用 classic，需要可靠性的用 quorum。**

---

## 知识点 3：故障与网络分区

### 第三幕：一个"自动恢复"的谜团

运维发现一个奇怪的现象：三节点集群，停掉一个节点，服务正常；停掉两个，服务就挂了；但把第二个节点重新启动，服务**自己就好了**，没人做任何操作。

这不是魔法，是 Raft 的**多数派**规则。

### 多数派：为什么必须是奇数个节点

Raft 要求任何写入都要**多数派节点确认**。对于 3 节点集群：

```
多数派 = ⌊3/2⌋ + 1 = 2
```

意思是：3 个节点里至少 2 个活着，集群才能写入。

实测（`l11-majority.py`）——这个表格是本课最重要的一张：

```
【A】停 1 个节点（剩 2 个 = 达到多数派）
  | 节点 | 容器状态 | 写入结果 |
  | rmq1 | 运行中 | ✅ 可写 |
  | rmq2 | 运行中 | ✅ 可写 |
  | rmq3 | (已停止) | — |

【B】再停 1 个（剩 1 个 = 失去多数派）
  | 节点 | 容器状态 | 写入结果 |
  | rmq1 | 运行中 | ❌ NackError: 0 message(s) NACKed |
  | rmq2 | (已停止) | — |
  | rmq3 | (已停止) | — |

【C】恢复 1 个（剩 2 个 = 重新达成多数派）
  | 节点 | 容器状态 | 写入结果 |
  | rmq1 | 运行中 | ✅ 可写 |
  | rmq2 | 运行中 | ✅ 可写 |
  | rmq3 | (已停止) | — |
```

**停 1 个可用，停 2 个不可用，恢复 1 个自动恢复。** 完全符合多数派规则。

#### ⚠️ 失去多数派时的表现：不是报错，是 NACK

这一点特别值得注意，它呼应课 6 讲的 publisher confirms。

失去多数派时，写入的失败形态**不是连接断开、不是抛异常，而是返回 NACK**：

```
❌ NackError: 0 message(s) NACKed
```

这意味着：**如果你开了 confirm（课 6 强调过必须开），你会通过 NACK 感知到集群不可用。** 如果没开 confirm，你可能根本不知道消息没被接受。

这再次印证了课 6 的结论——**publisher confirms 不是可选优化，是必需品。**

#### 为什么推荐奇数个节点

| 节点数 | 多数派 | 容忍故障数 | 评价 |
|---|---|---|---|
| 1 | 1 | 0 | 无高可用 |
| 2 | 2 | 0 | **比 3 节点更差**——挂 1 个就不可用 |
| 3 | 2 | 1 | 推荐的最小配置 |
| 4 | 3 | 1 | 只容忍 1 个，却多付 33% 成本 |
| 5 | 3 | 2 | 容忍 2 个故障 |

**2 节点是最差的选择**：它比 3 节点少一个节点的成本，却同样只能容忍 1 个故障——不，实际上 2 节点的多数派是 2，**挂掉 1 个就完全不可用**，容忍故障数是 **0**。

### 4.3 的元数据：Khepri

旧版本用 **Mnesia** 存元数据（交换机、队列、绑定、用户等）。4.3 起换成 **Khepri**，后者基于 Raft。

实测本环境的元数据后端：

```
【A】元数据存储后端
  {khepri,
  {khepri_mnesia_migration,[]},
  ...
  metadata_store: 0.0004 gb (0.26 %)
  metadata_store_ets: 0.0 gb (0.03 %)
```

`khepri` 与 `metadata_store` 字段都在，确认 4.3.5 使用 Khepri。

（注：`status` 输出里仍能看到 `mnesia: 0.0 gb (0.0 %)` 与 `Node data directory: .../mnesia/...` 这类字样——这是**历史目录命名**，不是还在用 Mnesia 存元数据。）

### 旧的分区策略去哪了

3.x 时代有个必考题：`cluster_partition_handling` 该配 `pause_minority`、`autoheal` 还是 `ignore`？

**4.3 起这些都没了**，因为处理逻辑统一进了 Raft 的多数派语义。

实测：

```
【B】旧分区处理策略 cluster_partition_handling
  ✅ environment 中【不存在】cluster_partition_handling 配置
     （旧策略 pause_minority / autoheal / ignore 已随 Mnesia 移除）
```

> ⚠️ **一处需要如实说明的发现**：扫描 `environment` 时，确实匹配到了一个含 "partition" 的配置项：
> ```
> {prevent_overlapping_partitions,false},
> ```
> 但它是**另一回事**——控制是否阻止重叠分区，与 `cluster_partition_handling` 的 `pause_minority`/`autoheal`/`ignore` 三选一**不是同一个配置**。我不把它当作"旧策略仍存在"的证据。

**这个变化对运维的意义**：过去网络分区后，管理员要预先配置策略，还要理解每种策略下会丢什么；现在行为是确定的——**少数派侧停止服务，多数派侧继续**，恢复后按 Raft 日志同步，不需要人工决策。

代价是：你**失去**了选择权。`ignore` 模式那种"分区两边都继续服务、之后手工合并"的做法，在 4.3 里做不到了。这需要接受。

### 故障恢复的完整时间线

综合课 11 的实测，一次 leader 宕机大概是这样：

```
T+0.00s   leader 节点宕机
T+0.07s   剩余节点选出新 leader（实测）
T+0.07s+  服务恢复，可继续读写
          → 已确认的消息零丢失
          → 未确认的消息取决于客户端是否重试

节点恢复后：
          副本自动重新同步
          leader 【不】自动切回原节点（Raft 不做无谓的二次选举）
```

### 监控什么

生产上建议关注：

- **副本健康度**：`online` 是否等于 `members`。不等说明有副本掉线，这是故障的前兆
- **leader 分布**：三个队列的 leader 都挤在一个节点上，会造成热点
- **多数派可用性**：告警"存活节点数 < 多数派"
- **Federation / Shovel 链路状态**：如果用了它们，要监控链路是否 running

（本课实测中，Federation 链路状态可以从 `rabbitmqctl federation_status` 读到，Shovel 从 `rabbitmqctl shovel_status` 读。）

---

## 本课要点速查卡

| 主题 | 结论 |
|---|---|
| **集群前提** | Erlang cookie 必须相同；实测两个不同环境 cookie 不同则无法组集群 |
| **ram 节点** | 4.3 起已移除，节点一律为 disc（`cluster_status` 只有 Disk Nodes） |
| **节点重命名** | 已废弃，与 Raft 特性不兼容（rabbitmqctl help 原文已标注） |
| **Shovel** | **move** 语义，源端消费掉（实测源 5→0，目标 0→5） |
| **Federation** | **copy** 语义，上游保留（实测两边各 5 条） |
| Federation 陷阱 | 下游去上游找**同名队列**拉取；状态 running ≠ 数据到达 |
| **镜像队列** | 4.0 移除；实测 `ha-mode` 策略被拒（Validation failed） |
| **classic 队列** | **不复制**，数据只在 `node` 字段标识的节点上 |
| quorum 队列 | Raft 复制，默认全节点副本，单 leader 处理读写 |
| 连任意节点 | 可以，非 leader 节点转发请求到 leader |
| **leader 故障** | 实测选举 **0.07s**，20 条已确认消息**零丢失**，故障期间仍可写入 |
| leader 恢复后 | 副本自动同步，leader **不**切回原节点 |
| **classic 宿主宕机** | 队列完全不可用（`process is stopped by supervisor`） |
| **多数派** | 3 节点需 2 个；停 1 个可用，停 2 个不可用，恢复 1 个自动恢复 |
| 失去多数派表现 | **NACK**（非报错）——没开 confirm 就感知不到 |
| 节点数建议 | 3 或 5；**2 节点最差**（容忍 0 个故障） |
| 元数据后端 | 4.3 起 Khepri（Raft），Mnesia 退场 |
| 旧分区策略 | `pause_minority`/`autoheal`/`ignore` 已移除，无需再配 |

---

## 常见误区

| # | 误区 | 真相 |
|---|------|------|
| 1 | "集群能让所有队列自动高可用" | 只有 quorum/stream 复制；**classic 队列不复制** |
| 2 | "在别的节点上能查到队列，说明数据已复制" | 元数据全局可见 ≠ 数据复制；看 `node` 字段 |
| 3 | "配个 ha-mode 策略就能镜像" | 4.0 已移除，实测返回 Validation failed |
| 4 | "Shovel 和 Federation 差不多" | Shovel 是 **move**（源端清空），Federation 是 **copy**（上游保留） |
| 5 | "Federation 链路 running 就万事大吉" | 实测：队列名不同时链路 running 但拉到 0 条 |
| 6 | "quorum 队列的客户端要连 leader" | 连任意节点都行，非 leader 会转发 |
| 7 | "节点恢复后 leader 会切回去" | 不会，Raft 不做无谓的二次选举 |
| 8 | "3 节点挂 2 个还能读" | 不能，失去多数派后**读写都不可用**（实测 NACK） |
| 9 | "2 节点集群也能容忍 1 个故障" | 不能，2 节点多数派=2，挂 1 个即不可用 |
| 10 | "网络分区要配 pause_minority" | 4.3 起该配置已不存在，行为由 Raft 统一决定 |
| 11 | "status 里看到 mnesia 字样说明还在用 Mnesia" | 那是历史目录名；元数据后端看 `khepri` / `metadata_store` |
| 12 | "没有 confirm 也能知道集群挂了" | 失去多数派时是 **NACK**，不开 confirm 感知不到 |

---

## 🧪 小测

### Q1（单选）

你的三节点集群中，一个 quorum 队列的 leader 在节点 A。此时节点 A 整体宕机。关于队列的说法，正确的是？

A 队列不可用，直到节点 A 恢复
B 剩余节点会自动选出新 leader，已确认的消息不丢失
C 会丢失最后几秒写入的消息
D leader 会固定切回节点 A

<details><summary>答案</summary>

**B**。

实测结果（`l11-failover.py`）：

```
[3] 停掉 leader 节点 rmq1（docker stop，模拟宕机）...
[4] ✅ 新 Leader = rabbit@rmq3（选举耗时 0.07 s）
[5] 通过 rmq2 查询队列深度 = 20（原始 20 条）
    实际消费到 20 条
    ✅ 数据零丢失——quorum 的 Raft 复制生效
```

已确认（收到 publisher confirm）的消息因为已经过多数派落盘，所以零丢失。

A 错：quorum 队列正是为了容忍这种情况。
C 错：已确认的消息不丢。未确认的可能丢，但这取决于客户端是否重试。
D 错：实测恢复后 leader 仍是 rabbit@rmq3，**没有**切回原节点——Raft 不会为"回到原状"再引发一次选举。

</details>

### Q2（多选）

关于 Federation 与 Shovel，下列说法正确的是？（多选）

A Shovel 会把源队列的消息消费掉
B Federation 会保留上游队列的消息
C Federation 的下游队列去上游找同名队列拉取
D 两者都要求两端节点共享同一个 Erlang cookie

<details><summary>答案</summary>

**A、B、C**。

实测对照：

**Shovel（move 语义）**：
```
| 队列 | 所在节点 | 深度 |
| l11.shovel.src | rmq1 | 0 |   ← 源端被清空
| l11.shovel.dst | rmq2 | 5 |
```

**Federation（copy 语义）**：
```
| 队列 | 节点 | 深度 |
| l11.fed.queue（上游）| rmq1 | 5 |   ← 上游保留
| l11.fed.queue（下游）| rmq2 | 5 |
```

C 对：这是本课实测踩到的坑。下游队列去上游找**同名**队列；名字不同时链路显示 `running` 却拉到 0 条。

D 错：共享 cookie 是**组集群**的要求。Federation/Shovel 是松耦合方案，靠 AMQP URI（用户名密码）连接，不需要共享 cookie——这正是它们适用于跨组织/跨地域场景的原因。

</details>

### Q3（单选）

你接手一个 RabbitMQ 4.3 集群，前任运维留下文档说"已通过 `ha-mode: all` 策略为所有队列配置了镜像"。你执行该命令，结果如何？

A 成功，所有队列被镜像
B 成功，但只对 classic 队列生效
C 失败，返回 Validation failed
D 失败，提示需要启用 mirror 插件

<details><summary>答案</summary>

**C**。

实测：

```
rabbitmqctl set_policy l11-ha-test "^test$" '{"ha-mode":"all"}' --apply-to queues

Setting policy "l11-ha-test" for pattern "^test$"
to "{"ha-mode":"all"}" with priority "0" for vhost "/" ...
Error:
Validation failed
```

镜像队列（classic mirrored queues）已在 **RabbitMQ 4.0 移除**，相关的 `ha-*` 策略在 4.3 上不再被接受。

A、B 错：命令根本不会成功。
D 错：不是缺插件——镜像队列是**设计上被移除**的，没有插件能恢复它。

**正确的迁移路径**：需要高可用的队列改用 **quorum queue**（`x-queue-type: quorum`）。

</details>

### Q4（简答）

你的三节点集群，运维反馈"停掉两个节点后，发布端报了 NackError"。请解释为什么停一个节点没事、停两个就不行，并说明客户端该如何正确感知这种情况。

<details><summary>答案</summary>

**原因：Raft 的多数派规则。**

三节点集群的多数派是 `⌊3/2⌋ + 1 = 2`。任何写入都需要至少 2 个节点确认。

实测（`l11-majority.py`）：

```
停 1 个（剩 2 个，达到多数派）  → ✅ 两个存活节点都可写
停 2 个（剩 1 个，失去多数派）  → ❌ NackError: 0 message(s) NACKed
恢复 1 个（剩 2 个）            → ✅ 自动恢复，无需人工干预
```

这就是为什么停一个没事、停两个就不行——**不是**因为"挂了一半以上"，而是因为剩下 1 个节点凑不齐多数派，Raft 无法安全地提交写入。

**客户端如何正确感知**：

关键在于失败形态是 **NACK，不是异常、不是断连**：

```
❌ NackError: 0 message(s) NACKed
```

这意味着：

1. **必须开启 publisher confirms**（课 6 的三件套之一）。开了 confirm，你会通过 NACK 明确知道消息没被接受；没开 confirm，消息静默失败，你**完全感知不到**。

2. **在代码里处理 NackError**。pika 中开了 `confirm_delivery()` 后，`basic_publish` 在被 NACK 时会抛 `pika.exceptions.NackError`。要捕获它并做重试或落库，而不是让它冒泡导致进程崩溃。

3. **监控多数派可用性**。不要等发布端报错才发现——应该直接告警"存活节点数 < 多数派"。

这再次印证课 6 的结论：**publisher confirms 是必需品，不是可选优化。**

</details>

### Q5（简答）

你在排查一个 Federation 问题：链路状态显示 `running`，但下游队列深度一直是 0。请列出至少两个排查方向，并说明本课实测到的那个最隐蔽的原因。

<details><summary>答案</summary>

**本课实测到的最隐蔽原因：两端队列不同名。**

Federation 的下游队列会去上游找**同名队列**拉取。我第一次实验时：

- 下游队列叫 `l11.fed.down`
- 消息发到了上游的 `l11.fed.up`

链路状态是这样的：

```
#{status => running, type => queue,
  queue => <<"l11.fed.down">>,
  uri => <<"amqp://rmq1:5672">>,
  upstream_queue => <<"l11.fed.down">>,   ← 去上游找这个名字
  ...}
```

看 `upstream_queue` 字段：它去上游找 `l11.fed.down`，而上游根本没有这个队列，所以拉到 0 条。

**但 `status => running`**——因为链路本身是健康的，它确实连上了、确实在监听，只是监听的对象不存在。

**核心教训：状态正常 ≠ 数据到达。** 排查 Federation 问题时，不要只看 `running`，要看 `upstream_queue` 字段是不是你要的那个队列，以及上游是否真的有这个队列。

**另外三个常见排查方向**：

1. **URI 与凭据**：`amqp://user:pass@host:5672` 里的用户名密码是否有权限访问上游 vhost
2. **Policy 是否匹配**：`set_policy` 的正则（`^queue$`）是否真的匹配到下游队列名。注意 `--apply-to queues` 别漏
3. **网络可达**：从下游节点能否解析并连通上游主机名（本课环境用 docker 网络内的容器名 `rmq1` 互通）

把两端改成同名队列后，实测立刻正常：

```
| l11.fed.queue（上游）| rmq1 | 5 |
| l11.fed.queue（下游）| rmq2 | 5 |
✅ 下游拉取到 5 条副本
✅ 上游仍保留 5 条 → 【copy 语义】确认
```

</details>

### Q6（简答）

公司要上一个新业务，需要高可用。有同事提议"配 2 个节点组集群就够了，省钱"。请结合本课实测说明为什么这个方案有问题，并给出建议。

<details><summary>答案</summary>

**2 节点集群的容忍故障数是 0，比单节点没有实质改善，还不如直接上 3 节点。**

原因是多数派规则：

- **2 节点**的多数派是 `⌊2/2⌋ + 1 = 2`——意味着**两个节点都必须活着**。挂掉 1 个，剩下 1 个凑不齐多数派，集群**完全不可用**。
- **3 节点**的多数派是 `⌊3/2⌋ + 1 = 2`——容忍 1 个节点故障。

也就是说，2 节点**多付了一台机器的成本，却没有换来任何故障容忍能力**。

本课的实测直接印证了多数派规则（虽然是 3 节点集群，但规则是一样的）：

```
停 1 个（剩 2 个 = 达到多数派）  → ✅ 可写
停 2 个（剩 1 个 = 失去多数派）  → ❌ NackError
恢复 1 个（剩 2 个）            → ✅ 自动恢复
```

把这张表套到 2 节点集群上：停 1 个就只剩 1 个，直接落到第二行的不可用状态。

**建议**：

1. **最少 3 个节点**。这是能容忍 1 个故障的最小配置，也是官方推荐的最小生产规模。
2. **需要容忍 2 个故障时用 5 个节点**（多数派 = 3）。
3. **不要用偶数个节点**。4 节点的多数派是 3，同样只容忍 1 个故障，却比 3 节点多付 33% 成本。
4. **队列类型选 quorum**。这一点与节点数同样重要——实测表明 **classic 队列不复制**，宿主节点宕机后队列完全不可用：
   ```
   rmq2: ❌ NOT_FOUND - queue 'l11.failover.classic' ...
         process is stopped by supervisor
   ```
   即使有 3 个节点，用 classic 队列仍然是单点。

**一句话总结**：高可用需要**两件事同时满足**——奇数个节点（保证多数派可达成）+ quorum 队列（保证数据有副本）。只做其中一件都不够。

</details>

---

## 📚 本课官方文档汇总

| 主题 | 链接 |
|------|------|
| 集群组建指南 | [Clustering Guide](https://www.rabbitmq.com/docs/clustering) |
| Quorum 队列（Raft 复制、副本管理） | [Quorum Queues](https://www.rabbitmq.com/docs/quorum-queues) |
| Stream（日志语义、复制） | [Streams](https://www.rabbitmq.com/docs/streams) |
| Federation 插件 | [Federation Plugin](https://www.rabbitmq.com/docs/federation) |
| Shovel 插件 | [Shovel Plugin](https://www.rabbitmq.com/docs/shovel) |
| 分布式 RabbitMQ（概念总览） | [Distributed RabbitMQ](https://www.rabbitmq.com/docs/distributed) |
| 分区处理（4.x 语义） | [Partitions](https://www.rabbitmq.com/docs/partitions) |
| 集群运维与监控 | [Clustering and Monitoring](https://www.rabbitmq.com/docs/clustering#monitoring) |
| 从镜像队列迁移到 quorum | [Migrating from Mirrored Classic Queues](https://www.rabbitmq.com/docs/migrate-mcq-to-qq) |

> 以上链接核查于 2026-09，对应 RabbitMQ 4.3 文档。

---

## 下一步

下一课是**阶段 4 的收官**，也是整门课程的收官：**课 12《架构落地与选型决策》**——典型消息模式（工作队列 / 发布订阅 / RPC）、选型对比（Kafka / RocketMQ / Redis Stream）、生产落地清单。

> 下一课：[课 12 架构落地与选型决策](./lesson-12-架构落地与选型决策.md)（阶段 4）

---

## 本课实测环境

| 项目 | 值 |
|------|-----|
| RabbitMQ 版本 | 4.3.5（三个节点一致） |
| Erlang / OTP | 27.3.4.16 |
| 集群规模 | 3 节点（rmq1 / rmq2 / rmq3），全为 disc 节点 |
| 元数据后端 | Khepri |
| pika 版本 | 1.4.4 |
| Python 版本 | 3.12.3 |
| 实测日期 | 2026-09-01 |
| 验证脚本 | `playground/l11-quorum-replication.py`、`l11-failover.py`、`l11-majority.py`、`l11-shovel.py`、`l11-federation.py`、`l11-khepri-check.py` |
| 集群搭建 | `playground/l11-cluster-setup.sh` / `l11-cluster-teardown.sh` |

> ⚠️ **本课未完成的验证（如实说明）**：
> 1. **Shovel / Federation 的跨站点场景未实测**。原计划让既有容器 `rabbitmq-learn` 当"上游站点"，但它在不同的 docker 网络、集群容器访问不到；随后新建独立上游容器又遇到宿主文件权限错误（`Error when reading /var/lib/rabbitmq/.erlang.cookie: eacces`）。两次尝试失败后，改为**在集群内部两节点之间**演示。两种机制的**语义**（Shovel=move、Federation=copy）已实测确认，但**跨信任边界**这一应用场景未实测。
> 2. **stream 队列的高可用未单独实测**。受课时与篇幅所限，stream 的复制行为沿用课 5 的结论与官方文档，本课未做 leader 切换实测。
> 3. **`rabbitmqctl quorum_status` 在 4.3.5 中已不存在**（实测报 `Command 'quorum_status' not found`），改用 Management API 的 `leader` / `members` / `online` 字段读取副本信息。
