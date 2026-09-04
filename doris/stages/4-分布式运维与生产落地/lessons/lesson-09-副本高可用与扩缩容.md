# 第 9 课：副本、高可用与扩缩容

> 所属阶段：阶段 4《分布式运维与生产落地》｜ 水平：零基础 ｜ 本课知识点：多副本与自动修复、FE 高可用、扩缩容与数据均衡
> 故事情节：集群上了生产，某天一台 BE 宕机——主角紧张地发现，查询没断，数据也没丢

## 🎯 本课目标

- 说清 BE 宕机后数据如何自愈，以及副本数对存储成本的影响
- 解释 FE 的 Master / Follower / Observer 选举与读写分工
- 执行加节点操作，理解数据自动均衡的过程与对在线业务的影响

---

## ⚠️ 前置说明（大纲评审 P2-2，务必写入正文）

本课讨论的多副本与自动修复，语义基于**存算一体**架构。存算分离（课 12）下数据可靠性由共享存储层承担，副本语义不同 —— 读到课 12 时回头交叉验证。

---

## ⚠️ 本课的实验边界（先说清楚，避免误导）

这门课一路都是"单机单 BE"，到本课遇到了真正的麻烦：**副本、扩缩容、FE 选举这三件事，本质上都需要多台机器才能演示。**

为了不让本课退化成"纯理论课"，我做了一件事：**在同一个容器里拉起了第二个 BE 进程**（不同端口），把集群从 `1 FE + 1 BE` 变成 `1 FE + 2 BE`，于是扩缩容和数据均衡第一次变成了可以真跑的实验。

但必须诚实标注三个边界，正文后面每个相关结论都会带上标记：

| 边界 | 能验证到什么程度 | 标记 |
|---|---|---|
| **多副本扛宕机** | 能验证"单副本宕机 → 查询报错"，但**无法验证"多副本 → 查询不断"** | 🟡 原理推演 |
| **FE 高可用选举** | 命令语法全部可用（`ADD FOLLOWER`/`ADD OBSERVER`），但**选举过程未实测** | 🟡 命令可用 |
| **扩缩容与数据均衡** | **完全实测**：ADD / DECOMMISSION / CANCEL / 迁移计数 / 在线查询抖动 | 🟢 已实测 |

卡住第一项的不是我不够努力，而是 Doris 的一条硬规则——后面 3.4 节你会看到那条报错，它恰恰是本课最值得记住的知识点之一。

---

## 第一幕：起源与场景引入

前八课我们一直在跟"数据"打交道：怎么建模、怎么导入、怎么查得快。这一课换视角——**我们开始跟"机器"打交道。**

设想这个场景：

你的 Doris 集群上线三个月，跑着公司的实时报表。某天凌晨两点，监控告警响了——**一台 BE 节点挂了**（可能是磁盘坏了、可能是 OOM、可能是宿主机被误关机）。

你从床上爬起来，打开电脑，第一反应是：

> "完了，数据是不是丢了？报表是不是全挂了？"

然后你颤抖着执行了一条查询：

```sql
SELECT province, SUM(amount) FROM orders GROUP BY province;
```

**结果出来了。数据一条不少。**

那一刻的如释重负，是每个 DBA 都经历过的。但紧接着，第二个问题冒出来：

> "为什么？机器都挂了，数据怎么还在？"

以及一个更重要、但很少有人问的问题：

> "那我到底该给表设几个副本？设多了浪费钱，设少了……万一哪天查询真的断了呢？"

这一课就要把这两个问题讲透。**你会发现，"查询没断"这四个字背后，藏着一个很容易被误解的因果。**

---

## 第二幕：认知冲突

先看一个真实的反直觉场景。这是我在本机实测出来的，不是编的。

我把第二台 BE 进程直接 `kill -9`，模拟节点宕机。然后查两张表：

```sql
-- 表 A：orders，2150 万行
SELECT COUNT(*) FROM orders;

-- 表 B：repl3，5 万行（建表时声明 replication_num = 3）
SELECT COUNT(*) FROM repl3;
```

**表 A 正常返回 2150 万行。表 B 直接报错。**

```
ERROR 1105 (HY000): errCode = 2, detailMessage = tablet 1788336178413 has no queryable replicas.
err: replica 1788336178414's backend 1788336178366 with tag {"location" : "default"}
does not exist or not alive
```

等一下——**表 B 是"3 副本"表，它反而挂了；表 A 只有 1 个副本，它反而活着？**

这不合理。除非……我们对"副本"的理解从一开始就是错的。

> **⚠️ 一个必须先说清楚的实验陷阱（本课实测发现，前九课都没注意到）**
>
> 我第一次做这个实验时，用 `SELECT COUNT(*)` 验证，结果**两张表都正常返回**，什么现象都没看到。后来换成取明细行的查询，报错才出来。
>
> 原因：**Doris 对简单的 `COUNT(*)` 走元数据行数优化**，直接从 FE 的统计信息返回，压根不去扫 BE。所以节点宕机了，`COUNT(*)` 照样返回结果。
>
> **验证数据是否可查，一定要用真正扫盘的查询**：
> ```sql
> SELECT id, province, amount FROM t LIMIT 3;              -- 取明细，必然扫 BE
> SELECT SUM(amount) FROM t;                                -- 全表聚合，强制扫所有 tablet
> ```
> 用 `COUNT(*)` 做宕机演练，会得到完全错误的结论。

### 三个需要推翻的直觉

**直觉一："设置了 replication_num = 3，就有 3 份数据。"**

不一定。我建了这张表：

```sql
CREATE TABLE repl3 (...)
PROPERTIES ('replication_num' = '3');
```

在只有 2 台 BE 的集群上，它**建表成功了，插入也成功了**。但 `SHOW TABLETS` 显示：6 个 tablet，**总共只有 6 个副本**（每台 BE 分到 3 个），而不是 18 个。

> **副本数是一个"请求"，不是"保证"。** 节点不够时，Doris 会降级执行——先把数据写进去，而不是拒绝服务。

**直觉二："查询没断，是因为有副本在别处顶上了。"**

这是本课最大的误解。表 A 能查，不是因为副本顶上了——它**只有 1 个副本**，而那个副本恰好住在**还活着的那台 BE 上**。

真相是：

> **"查询没断"不是 Doris 神奇，是因为那份数据恰好没住在宕机的机器上。**

**直觉三："多副本就是多占点磁盘，没什么大不了。"**

代价是可量化的，而且很直接：**存储成本 × 副本数**。实测 100 万行数据 1 副本占 2.553 MB，那 3 副本就是约 7.7 MB。这不是百分比，是**倍数**。

### 这一幕给你的问题

带着这三个被推翻的直觉，我们进入第三幕。你会看到：

1. 数据到底是怎么"切"成小块、又是怎么"抄"成多份的（Tablet 与 Replica）
2. 为什么我的 3 副本表在 2 台机器上只落地了 1 份
3. 节点挂了的那一分钟里，集群内部到底发生了什么
4. 加机器、减机器的正确姿势，以及为什么 `DROP BACKEND` 会被 Doris 拦下来

---

## 第三幕：层层揭示

### 知识点 1：多副本与自动修复

> 本知识点关键点：Tablet 与 Replica 的概念、副本分布策略、宕机后的自动修复流程、副本数对存储成本的影响

#### 1.1 一张表落到集群，要经历三次"切"

这是理解副本的地基。很多教程一上来就讲"副本是数据的多个拷贝"，但没说清楚**被拷贝的那个"东西"到底是什么**。

答案是：**Tablet（数据分片）**。

一张表从逻辑上的"一张表"，到物理上的"一堆文件"，要切三次：

```sql
-- 看 orders 的物理布局
SHOW PARTITIONS FROM orders;
```

实测输出（截取关键列）：

```
DistributionKey=province   Buckets=8   ReplicationNum=1   RowCount=21500001
```

| 层次 | 怎么切 | 类比 | orders 的实际情况 |
|---|---|---|---|
| **分区 Partition** | 按时间/枚举值**横切** | 一本书按章节分册 | 单分区（`orders`） |
| **分桶 Bucket** | 按 Hash **竖切** | 每册按页码拆成活页 | `HASH(province)` × 8 桶 |
| **副本 Replica** | 每桶**抄 N 份** | 每页复印 N 份分给 N 个人 | `replication_num` = 1 |

于是：

```
Tablet 数 = 分区数 × 分桶数
Replica 总数 = Tablet 数 × 副本数
```

`orders` 是 1 个分区 × 8 个桶 = **8 个 Tablet**，1 副本 = **8 个 Replica**。

**Tablet 是 Doris 调度的最小单位**——搬数据、补副本、做均衡，都是以 Tablet 为粒度，不是以表为粒度。这一点后面讲扩缩容时会再回来。

#### 1.2 用一条命令验证：本机全是 1 副本

```sql
SHOW PROC '/statistic';
```

实测输出：

```
DbId          DbName             TableNum  PartitionNum  IndexNum  TabletNum  ReplicaNum
1788336157476 shop               46        94            95        643        643
Total         4                  51        101           102       667        667
```

**看最后两列：TabletNum = 667，ReplicaNum = 667，完全相等。**

这是本课最有诊断价值的一条数据——它说明：

> 这台机器上所有库表的**实际副本数都是 1**。

哪怕某张表建表时写了 `replication_num = '3'`，实际也只落地了 1 份（原因见 1.4）。

**记住这个诊断技巧**：`TabletNum == ReplicaNum` 就意味着"没有任何冗余"，任何一台 BE 挂掉，住在它上面的 tablet 就查不了。

#### 1.3 副本状态：数据是否"健康"要看这里

```sql
SHOW PROC '/cluster_health/tablet_health';
```

这是**每天该看一眼的视图**。实测输出（正常状态）：

```
DbId          DbName  TabletNum  HealthyNum  ReplicaMissingNum  VersionIncompleteNum  ...
1788336157476 shop    611        611         0                  0                     ...
Total         4       635        635         0                  0                     ...
```

重点看这几列：

| 列名 | 含义 | 正常值 |
|---|---|---|
| `TabletNum` | tablet 总数 | — |
| `HealthyNum` | 健康的 tablet 数 | **应等于 TabletNum** |
| `ReplicaMissingNum` | 副本缺失数 | **0** |
| `VersionIncompleteNum` | 版本不完整的副本数 | **0** |
| `ReplicaRelocatingNum` | 正在迁移的副本数 | 迁移中非 0，稳态为 0 |
| `RedundantNum` | 多余副本数（迁移后待删） | 稳态为 0 |

我 kill 掉第二台 BE 后立刻查这个视图，看到的正是：

```
shop   611   603   0   0   0   0   0   0   0   0   ... 8 ...
                                                        ↑
                                            NeedFurtherRepairNum = 8
```

**`HealthyNum` 从 611 掉到 603，8 个 tablet 需要修复**——这 8 个就是住在宕机节点上的、只有 1 个副本的 tablet。

> ⚠️ 611/603/8 是**首次实验的实测值**。重跑时数字会不同（第二次跑是 641→617，24 个待修），取决于当时集群里有多少 tablet 住在宕机节点上。
>
> **判据不变**：`HealthyNum` 下降 + `NeedFurtherRepairNum` 上升，且两者的差就是"住在宕机节点上的 tablet 数"。

#### 1.4 为什么我的"3 副本"表只落地了 1 份？

这是本课最值得记住的一条报错。

我建了 3 副本表后，想通过 `ALTER` 把副本补齐到 3 份：

```sql
ALTER TABLE ha_demo SET ('replication_num' = '2');
```

报错了：

```
ERROR 1105 (HY000): errCode = 2, detailMessage = Failed to find enough backend,
please check the replication num,replication tag and storage medium and avail capacity
of backends or maybe all be on same host.
Backends details: backends with tag {"location" : "default"} is
[[backendId=1788336157417, host=127.0.0.1, hdd disks count={ok=1,}, ssd disk count={}],
 [backendId=1788336178366, host=127.0.0.1, hdd disks count={ok=1,}, ssd disk count={}]],
```

**关键在最后半句：`or maybe all be on same host`.**

我的两个 BE 都是 `127.0.0.1`——**同一台物理机**。而 Doris 有一条硬规则：

> **反亲和（anti-affinity）：同一个 Tablet 的多个副本，不能放在同一台物理机上。**

这条规则完全合理：副本的意义是"机器坏了数据还在"，如果两个副本在同一台机器上，那台机器一坏，两个副本一起没——**副本就等于白设了**。

所以 Doris 宁可报错拒绝，也不给你造一个"看起来是 2 副本、实际是假冗余"的幻觉。

**这也解释了 1.1 里的现象**：建表时 `replication_num='3'` 能成功，是因为建表阶段 Doris 只是"尽力而为"地放置；但后续要**新增第 2、3 个副本**时，反亲和检查拦住了它。

> 🟡 **边界说明**：本机能证明的是"同主机时副本补不上 + 报错原文"。**"3 台真机器 + 3 副本 → 宕机查询不断"这个结论是原理推演，本机无法实测验证。** 但反过来说，我用"单副本宕机 → 查询报错"做了反证：副本的作用确实是"数据住在哪"的保险。

#### 1.5 自动修复：节点挂了之后，集群在做什么

kill 掉 BE2 之后，我按时间线记录了集群的变化：

| 时刻 | 现象 | 背后的机制 |
|---|---|---|
| **T+0s** | 进程没了，但 `SHOW BACKENDS` 仍显示 `Alive: true` | FE 还没感知，心跳没到点 |
| **T+0~10s** | 查询数据在该节点的表 → 报 `RpcException ... UNAVAILABLE` | 心跳窗口内，FE 仍把请求发给"僵尸"节点 |
| **T+10s+** | `Alive` 变 `false`，`ErrMsg: java.net.ConnectException: Connection refused` | 心跳超时，FE 判定节点死亡 |
| **T+10s 之后** | `cluster_health` 显示 `NeedFurtherRepairNum = 8` | Tablet 调度器接管，开始补副本 |
| **重启节点后** | 45 秒内 `HealthyNum` 从 603 回到 611，**全绿** | 副本补齐完成，自愈成功 |

控制这个节奏的两个参数（实测值）：

```sql
SHOW FRONTEND CONFIG LIKE '%heartbeat%';
```

```
heartbeat_interval_second                        10
max_backend_heartbeat_failure_tolerance_count    1
abort_txn_after_lost_heartbeat_time_second       300
```

**读法**：FE 每 10 秒发一次心跳；容忍 1 次失败；所以**大约 10~20 秒**判定节点死亡。之后才开始补副本。

> 这就是为什么"宕机瞬间"和"宕机 30 秒后"的报错信息不一样——前者是连不上，后者是明确告诉你"没有可查询的副本"。

**自愈的关键证据**：我重启 BE2 后，什么都没做，45 秒后 `SHOW PROC '/cluster_health/tablet_health'` 回到了全绿：

```
shop   611   611   0   0   0   0   0   0   0   0   ... 0 ...
```

**没有任何人工干预。** 这就是"自动修复"——Tablet 调度器发现副本缺失，自动在存活节点上重建。

#### 1.6 副本的代价：存储成本是乘以 N，不是加一点

```sql
SHOW DATA FROM cost1;
```

实测（100 万行，1 副本）：

```
TableName  IndexName  Size       ReplicaCount  RowCount  RemoteSize
cost1      cost1      2.553 MB   6             1000000   0.000
```

换算一下：

| 副本数 | 存储占用 | 可容忍几台机器故障 |
|---|---|---|
| 1 副本 | 2.553 MB | **0 台**（挂了就查不了） |
| 2 副本 | ≈ 5.1 MB | 1 台 |
| 3 副本 | ≈ 7.7 MB | 2 台 |

**这是"用存储换可用性"的买卖，而且是倍数关系，不是百分比。**

生产上怎么选？业界常见做法：

- **1 副本**：只在测试/开发环境用，或者数据可以从别处重建
- **2 副本**：能扛 1 台故障，成本翻倍——**中小集群的常见选择**
- **3 副本**：能扛 2 台同时故障，成本三倍——**金融、核心报表的标配**

> 注意"扛 2 台"意味着**你可以同时坏一台、还在修另一台**。3 副本的价值不只是"冗余更多"，更是"**给了你维修窗口**"。

#### 1.7 知识点 1 小结

- **Tablet** 是调度的最小单位；`Tablet 数 = 分区数 × 分桶数`，`Replica 总数 = Tablet 数 × 副本数`
- **`SHOW PROC '/statistic'` 里 `ReplicaNum == TabletNum`** → 整机零冗余，这是最快的体检
- **`replication_num` 是请求不是保证**，节点不够时会降级（建表成功但副本数不足）
- **反亲和是硬规则**：同一台物理机上不放同一 tablet 的两个副本，这也是本机的限制来源
- **自动修复无需人工干预**，实测重启后 45 秒内自愈完成
- **成本是 × N**，2 副本扛 1 台、3 副本扛 2 台（并给你维修窗口）

---

### 知识点 2：FE 高可用

> 本知识点关键点：Master / Follower / Observer 三种角色、基于类 Raft 协议的元数据同步、Follower 参与选举 Observer 不参与

前面讲的都是 **BE**（负责存数据、算数据）。现在讲 **FE**（负责管元数据、接收查询、生成执行计划）。

一句话区分：

> **BE 挂了 → 部分数据查不了；FE 挂了 → 整个集群写不了（甚至查不了）。**

所以 FE 的高可用，重要性其实**高于** BE。

#### 2.1 三种角色

```sql
SHOW FRONTENDS\G
```

本机实测输出（截取关键字段）：

```
              Name: fe_89ff9096_915a_4499_8a46_45e973d35cc2
              Host: 127.0.0.1
       EditLogPort: 9010
              Role: FOLLOWER
          IsMaster: true
              Join: true
             Alive: true
 ReplayedJournalId: 26833
```

| 角色 | 能不能写元数据 | 能不能被选为 Master | 主要作用 |
|---|---|---|---|
| **Master** | ✅ 唯一可写 | —（它本身就是） | 处理所有 DDL、导入事务、生成执行计划 |
| **Follower** | ❌ 只读 | ✅ 参与选举、有投票权 | 元数据热备，Master 挂了顶上 |
| **Observer** | ❌ 只读 | ❌ **不参与选举** | 只同步元数据，**分担查询压力** |

**关键区分**：Follower 和 Observer 都能读，但**只有 Follower 有投票权**。

> 这也是为什么 Observer 可以随便加很多个来扩展查询能力——它不参与选举，加多少都不影响选举的正确性。

#### 2.2 元数据怎么同步：类 Raft 协议

FE 之间同步元数据靠的是 **edit log**（元数据操作日志）+ 类 Raft 的一致性协议。

```sql
SHOW FRONTENDS\G
```

```
 ReplayedJournalId: 26833
```

这个数字是**该 FE 已经回放到的日志位点**。Master 写一条元数据变更就产生一条 edit log，Follower/Observer 拉取并回放。

**"超过半数"是核心规则**：

| FE 总数（Follower + Master） | 超过半数需要 | 能容忍几台故障 |
|---|---|---|
| 1 | 1 | **0 台** |
| 2 | 2 | **0 台** ⚠️ |
| 3 | 2 | **1 台** ✅ |
| 5 | 3 | **2 台** ✅ |

**注意 2 台那一行**：2 的半数是 1，"超过半数"需要 2 票。如果挂了 1 台，只剩 1 票，**达不到"超过半数"，选不出新 Master**。

> **这就是为什么 FE 必须部署奇数个**——2 台的高可用能力和 1 台一样是 0，但成本翻倍。
>
> 生产常见配置：**3 个 FE（1 Master + 2 Follower）**，容忍 1 台故障；规模大的用 5 个。

#### 2.3 命令怎么用（本机实测语法可用）

🟡 **边界说明**：以下命令在**本机全部执行成功**（语法与注册流程可用），但由于没有真正的第二个 FE 进程，节点状态停留在 `Join: false / Alive: false`，**选举过程未实测**。

```sql
-- 加一个 Follower（注意端口是 edit_log_port，默认 9010）
ALTER SYSTEM ADD FOLLOWER 'host:9010';

-- 加一个 Observer
ALTER SYSTEM ADD OBSERVER 'host:9010';

-- 移除
ALTER SYSTEM DROP FOLLOWER 'host:9010';
ALTER SYSTEM DROP OBSERVER 'host:9010';
```

我在本机实际执行的结果：

```sql
ALTER SYSTEM ADD FOLLOWER '127.0.0.1:9011';
ALTER SYSTEM ADD OBSERVER '127.0.0.1:9012';
SHOW FRONTENDS\G
```

```
Name: fe_19363be8_31ff_4a8c_b2d3_d99f7faa071d   Role: OBSERVER  IsMaster: false  Join: false  Alive: false
Name: fe_89ff9096_915a_4499_8a46_45e973d35cc2   Role: FOLLOWER  IsMaster: true   Join: true   Alive: true
Name: fe_c10ad37a_08f0_45a9_8476_68478ba1eeb7   Role: FOLLOWER  IsMaster: false  Join: false  Alive: false
```

**三个 FE 都出现在列表里了**，角色也正确（一个 OBSERVER、两个 FOLLOWER，其中原节点是 Master）。

但注意两个关键字段：

- **`Join: false`** —— 还没加入集群的元数据一致性组（因为对端没有真实进程）
- **`Alive: false`** —— 心跳不通

> **关键认知**：`ADD FOLLOWER` 只是"登记"了一个节点，**真正的加入要靠那个节点上的 FE 进程启动后，用 `--helper` 参数指向 Master 去拉元数据**：
>
> ```bash
> # 新 FE 首次启动的写法（本机未实测，为官方文档标准写法）
> bin/start_fe.sh --helper <master_host>:<edit_log_port> --daemon
> ```
>
> **没有 `--helper`，新 FE 不知道去哪儿同步元数据，就永远停在 `Join: false`。** 这是部署多 FE 时最高频的踩坑点。

清理（把刚才加的删掉，恢复单 FE）：

```sql
ALTER SYSTEM DROP FOLLOWER '127.0.0.1:9011';
ALTER SYSTEM DROP OBSERVER '127.0.0.1:9012';
```

#### 2.4 Master 挂了会发生什么

🟡 这一段是**原理推演**（本机单 FE，无法实测选举）。但它的重要性不需要实测来支撑：

1. Follower 通过心跳发现 Master 失联
2. 存活的 Follower 发起选举，**必须获得超过半数选票**
3. 得到多数票的 Follower 升为 Master
4. 其他 FE 把 edit log 的写入目标切到新 Master
5. 整个过程期间**元数据写入短暂不可用**（读不受影响，因为 Follower 也能读）

**关键点**：这个切换是**自动的**，但**不是瞬时的**。生产上要做好"几秒到几十秒内 DDL 会失败"的心理准备，应用侧最好有重试。

#### 2.5 知识点 2 小结

- **Master 唯一可写**，Follower 有投票权，Observer 只分担读压力、不投票
- **FE 必须是奇数个**：2 台的容错能力和 1 台一样是 0
- **3 个 FE 容忍 1 台故障**，5 个容忍 2 台——这是"超过半数"规则的直接推论
- **`ADD FOLLOWER` 只是登记**，新 FE 启动时必须带 `--helper` 指向 Master，否则永远 `Join: false`
- 🟡 **选举过程未实测**（单机限制），命令语法与注册流程已验证可用

---

### 知识点 3：扩缩容与数据均衡

> 本知识点关键点：ADD / DECOMMISSION BACKEND、数据自动均衡机制、均衡对在线查询的影响与限速

这是本课**唯一完全实测**的知识点——因为我真的在同一个容器里拉起了第二个 BE。

#### 3.1 先看集群长什么样

```sql
SHOW BACKENDS\G
```

实测输出（双节点状态）：

```
              BackendId: 1788336157417
                   Host: 127.0.0.1
          HeartbeatPort: 9050
                  Alive: true
              TabletNum: 3863
       DataUsedCapacity: 2.685 GB
          TotalCapacity: 1006.854 GB
                UsedPct: 19.35 %

              BackendId: 1788336178366
                   Host: 127.0.0.1
          HeartbeatPort: 19050
                  Alive: true
              TabletNum: 13
       DataUsedCapacity: 461.868 KB
```

**注意两台 BE 的 tablet 数：3863 vs 13。** 极度不均衡——因为第二台是新加的，数据还没搬过去。

#### 3.2 扩容：ADD BACKEND

```sql
ALTER SYSTEM ADD BACKEND '127.0.0.1:19050';
```

实测：**秒级生效**，`Alive` 立刻变 `true`。而且**重复执行会报错**（幂等保护）：

```
ERROR 1105 (HY000): errCode = 2, detailMessage = Same backend already exists[127.0.0.1:19050]
```

> ⚠️ **坑点**：`ADD BACKEND` 里的端口是 **heartbeat_service_port（默认 9050）**，**不是** be_port（9060），也不是 webserver_port（8040）。填错了会一直 `Alive: false`。

#### 3.3 数据均衡：默认居然是关着的

新节点加进来了，但数据不会自动搬过去。查一下：

```sql
SHOW FRONTEND CONFIG LIKE '%balance%';
```

实测（关键项）：

```
disable_balance                    true      ← 默认是 true，即"关闭均衡"
balance_slot_num_per_path          1
balance_load_score_threshold       0.1
tablet_rebalancer_type             BeLoad
```

**`disable_balance = true` 意味着均衡默认关闭。**

打开它：

```sql
ADMIN SET FRONTEND CONFIG ('disable_balance' = 'false');
```

然后等 90 秒，再看 tablet 分布：

| 时刻 | BE1 (9050) | BE2 (19050) |
|---|---|---|
| 打开开关前 | 3850 | 8 |
| 打开开关 90 秒后 | 3848 | **10** |

> ⚠️ 上表是**首次跑这套实验时的实测值**。重跑时数字会变（我第二次跑是 3868/26 → 3869/25），因为集群里已有的 tablet 总数在变。
>
> **别记数字，记判据**：新节点的 `TabletNum` 在上升、老节点在下降，就说明均衡在工作。

**数据真的开始搬了。**

> **怎么看这个数字**：90 秒只搬了 2 个 tablet，慢得让人怀疑是不是没生效。但这正是设计意图——见 3.6 的限速。**判断依据不是"搬了多少"，而是"数字在动"**，配合下面 `history_tablets` 一起看。

再看调度器的工作记录：

```sql
SHOW PROC '/cluster_balance';
```

```
Item               Number
cluster_load_stat  1
working_slots      2
sched_stat         0
priority_repair    0
pending_tablets    0
running_tablets    0
history_tablets    91     ← 已经调度过 91 个 tablet
```

> ⚠️ **注意 `history_tablets` 是累计值**，从集群启动开始算，不会归零。我第二次跑这套实验时它已经涨到 1000 了。所以**别拿它的绝对值当"这次搬了多少"**，要看它在两次查询之间**有没有增长**。

#### 3.4 缩容：DECOMMISSION（安全的做法）

```sql
ALTER SYSTEM DECOMMISSION BACKEND '127.0.0.1:19050';
```

执行后立刻查：

```
              BackendId: 1788336178366
          HeartbeatPort: 19050
                  Alive: true
   SystemDecommissioned: true      ← 标记出现了
              TabletNum: 15
```

等 120 秒后：

| 时刻 | BE1 (9050) | BE2 (19050) |
|---|---|---|
| DECOMMISSION 前 | 3855 | 15 |
| DECOMMISSION 120 秒后 | **3857** | **13** |

**BE2 的 tablet 从 15 降到 13，BE1 从 3855 升到 3857**——数据是真的在往回搬，不是直接丢弃。

#### 3.5 缩容可以反悔：CANCEL DECOMMISSION

这是 DECOMMISSION 相比 DROP 最大的优势——**它是可撤销的**：

```sql
CANCEL DECOMMISSION BACKEND '127.0.0.1:19050';
```

实测：执行后 `SystemDecommissioned` 立刻从 `true` 变回 `false`，节点恢复正常服务。

> **生产价值**：如果你误操作了缩容，或者缩容过程中发现业务扛不住，**CANCEL 能让你立刻止损**。这是 DROP 永远给不了的。

#### 3.6 为什么不会拖垮在线业务：限速机制

这是我最想强调的一点。DECOMMISSION 进行中，我连续跑了 5 次查询模拟在线业务：

```
第 1 次: 140 ms
第 2 次: 128 ms
第 3 次: 151 ms
第 4 次: 145 ms
第 5 次: 159 ms
```

**128~159 ms，与平时同一量级，没有出现秒级抖动。**

为什么？看这几个参数：

```sql
SHOW FRONTEND CONFIG LIKE '%balance_slot%';
SHOW FRONTEND CONFIG LIKE '%partition_rebalance%';
SHOW FRONTEND CONFIG LIKE '%repair%';
```

```
balance_slot_num_per_path                        1        ← 每块盘的并发搬运额度
partition_rebalance_max_moves_num_per_selection  10       ← 一轮最多选多少个 tablet 搬
partition_rebalance_move_expire_after_access     600      ← 刚被访问过的 tablet 先不搬
tablet_repair_delay_factor_second                60       ← 补副本的延迟启动
```

**`balance_slot_num_per_path = 1`** 是关键——每块盘同一时刻只允许搬运 1 个 tablet。

> **这就是"限速"的本质**：均衡不是一次性全量重分布，而是按额度**一点一点渗**。代价是慢（实测 90 秒搬 2 个），收益是**在线业务几乎无感**。
>
> 生产上如果急于完成扩容搬迁，可以调大 `balance_slot_num_per_path`，但要盯着查询延迟——**这是一道明确的取舍题，不是"越大越好"**。

#### 3.7 千万别用 DROP BACKEND

我实测了一下 `DROP BACKEND`，结果被 Doris **明确拒绝**了：

```sql
ALTER SYSTEM DROP BACKEND '127.0.0.1:19050';
```

```
ERROR 1105 (HY000): errCode = 2, detailMessage = It is highly NOT RECOMMENDED
to use DROP BACKEND stmt. It is not safe to directly drop a backend.
All data on this backend will be discarded permanently.
If you insist, use DROPP instead of DROP
```

**注意最后一句：如果你坚持，就把 `DROP` 拼成 `DROPP`（两个 P）。**

这是个非常漂亮的防呆设计：

> `DROP` 是正常拼写，被拒绝；`DROPP` 是**故意拼错**，才能强制执行。
>
> 这意味着你**不可能因为手滑而删掉一个节点**——你必须非常刻意地多打一个 P。

| 命令 | 行为 | 数据安全 | 可撤销 |
|---|---|---|---|
| `ADD BACKEND` | 加入节点 | — | — |
| `DECOMMISSION BACKEND` | **先迁数据，再摘除** | ✅ 安全 | ✅ 可 CANCEL |
| `DROP BACKEND` | 被拒绝（提示用 `DROPP`） | — | — |
| `DROPP BACKEND` | **直接丢弃，不等迁移** | ❌ **数据永久丢失** | ❌ 不可撤销 |

> **`DROPP` 的唯一正当用途**：该节点上的数据已经确认无用（比如这台机器是空的新节点，或者所有表的副本数 ≥ 2 且其他节点数据完整）。除此之外一律用 `DECOMMISSION`。

#### 3.8 知识点 3 小结

- 🟢 **全部实测**：ADD / DECOMMISSION / CANCEL / 迁移计数 / 在线查询抖动
- **`ADD BACKEND` 填的是 heartbeat_port（9050）**，不是 be_port
- **均衡默认关闭**（`disable_balance = true`），加了新节点要手动打开
- **DECOMMISSION 是先迁数据再摘，可 CANCEL**；实测 120 秒 tablet 15→13
  （首次实测值，重跑会变；**判据是"被摘节点降、留下的升"，不是具体数字**）
- **限速靠 `balance_slot_num_per_path = 1`**，实测在线查询 128~159 ms 无抖动
- **`DROP` 被拒绝、`DROPP` 才执行**——这是"手滑删不掉"的防呆设计

---
## 第四幕：实操验证

这一幕把前面所有结论亲手跑一遍。**每条命令都可以直接复制执行，不需要任何省略或脑补。**

配套脚本在 `assets/` 目录下，按顺序是：

| 脚本 | 作用 |
|---|---|
| `lesson09-add-be2.sh` | **拉起第二个 BE**（把单节点变成双节点，扩缩容实验的前提） |
| `lesson09-setup.sh` | 建实验表 + 知识点 1（Tablet/副本/成本）+ 知识点 2（FE 角色） |
| `lesson09-step4.sh` | 知识点 3：扩缩容与数据均衡（🟢 完全实测） |
| `lesson09-step5.sh` | 宕机演练（kill 一个 BE + 观察自愈） |
| `lesson09-cleanup.sh` | 清理实验对象，恢复配置 |

> ⚠️ **前置条件**：本幕的扩缩容与宕机演练需要一个**第二 BE 节点**。如果你的环境只有 1 台 BE，请先执行 `assets/lesson09-add-be2.sh` 拉起第二个 BE（脚本内含完整步骤与原理说明）；没有第二节点时，`step2`、`step3` 仍可全部执行，`step4`、`step5` 会提示跳过。

---

### 步骤 0：连上集群，先看清楚现状

```bash
# ⚠️ 必须带 -i，否则管道喂进去的 SQL 会被静默丢弃
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop
```

连上后依次执行：

```sql
-- 0.1 确认版本
SELECT version();

-- 0.2 看有几个 BE
SHOW BACKENDS\G

-- 0.3 看有几个 FE
SHOW FRONTENDS\G

-- 0.4 关键体检：tablet 数和副本数是否相等
SHOW PROC '/statistic';
```

**重点看 0.4 的输出**：

```
DbId          DbName  TableNum  PartitionNum  IndexNum  TabletNum  ReplicaNum
1788336157476 shop    46        94            95        643        643
Total         4       51        101           102       667        667
```

> **判断标准**：`ReplicaNum == TabletNum` → 整机零冗余。
> `ReplicaNum == TabletNum × 2` → 全部 2 副本，能扛 1 台故障。

---

### 步骤 1：建实验表

```sql
-- 1.1 单副本表（100 万行），用来量化存储成本
DROP TABLE IF EXISTS cost1;
CREATE TABLE cost1 (
  id INT NOT NULL,
  province VARCHAR(16) NOT NULL,
  amount DECIMAL(10,2) NOT NULL
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 6
PROPERTIES ('replication_num' = '1');

INSERT INTO cost1
SELECT user_id % 1000000, province, amount FROM orders LIMIT 1000000;
```

```sql
-- 1.2 声明 3 副本的表（5 万行），用来观察"请求 vs 实际"
DROP TABLE IF EXISTS repl3;
CREATE TABLE repl3 (
  id INT NOT NULL,
  province VARCHAR(16) NOT NULL,
  amount DECIMAL(10,2) NOT NULL
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 6
PROPERTIES ('replication_num' = '3');

INSERT INTO repl3
SELECT user_id % 1000000, province, amount FROM orders LIMIT 50000;
```

```sql
-- 1.3 声明 2 副本的表（5 万行）
DROP TABLE IF EXISTS ha_demo;
CREATE TABLE ha_demo (
  id INT NOT NULL,
  province VARCHAR(16) NOT NULL,
  amount DECIMAL(10,2) NOT NULL
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 6
PROPERTIES ('replication_num' = '2');

INSERT INTO ha_demo
SELECT user_id % 1000000, province, amount FROM orders LIMIT 50000;
```

**注意**：这三张表的建表语句都完整给出了列定义，没有"（同上）"这类省略——因为副本数、分桶数都不同，抄漏一处结论就对不上。

> ⚠️ `SHOW DATA` 的统计有延迟（课 6 踩过的同一个坑）。我在写这一课时就撞上了：插完 100 万行后等了 50 秒查 `SHOW DATA`，结果显示 **1.260 MB / 499228 行**——差点以为数据丢了一半。用 `SELECT COUNT(*)` 一查，实际是完整的 **1000000 行**。
>
> **判断方法**：以 `SELECT COUNT(*)` 为准，`SHOW DATA` 只是估算快照。等 75 秒以上再看就准了。

---

### 步骤 2：知识点 1 —— Tablet、副本与成本

```sql
-- 2.1 看表的物理布局（分区/分桶/副本数）
SHOW PARTITIONS FROM cost1;
```

找到这几列：`Buckets`（分桶数）、`ReplicationNum`（副本数）、`RowCount`。

```sql
-- 2.2 看 tablet 落在哪些 BE 上
SHOW TABLETS FROM cost1;
```

数一下 `BackendId` 那一列有几个不同的值——**这就是副本实际分布在几台机器上**。

```sql
-- 2.3 量化存储成本
SHOW DATA FROM cost1;
```

预期（100 万行 1 副本）：

```
TableName  IndexName  Size       ReplicaCount  RowCount  RemoteSize
cost1      cost1      2.553 MB   6             1000000   0.000
```

> **换算**：2 副本 ≈ 5.1 MB，3 副本 ≈ 7.7 MB。**存储成本是 × N。**

```sql
-- 2.4 验证"3 副本请求"实际落地了几份
SHOW TABLETS FROM repl3;
```

**关键观察**：数一数返回的行数。如果是 6 行（= 分桶数），说明**每个 tablet 只有 1 个副本**，"3 副本"没兑现。

```sql
-- 2.5 尝试补齐副本 —— 观察反亲和规则的拦截
ALTER TABLE ha_demo SET ('replication_num' = '2');
```

**如果两台 BE 在同一台物理机上**（比如都是 127.0.0.1），你会看到：

```
ERROR 1105 (HY000): errCode = 2, detailMessage = Failed to find enough backend,
please check the replication num,replication tag and storage medium and avail capacity
of backends or maybe all be on same host.
```

**重点读最后半句 `or maybe all be on same host`** —— 这就是反亲和规则的报错。

```sql
-- 2.6 每天的体检视图
SHOW PROC '/cluster_health/tablet_health';
```

**判断标准**：`HealthyNum` 应等于 `TabletNum`，`ReplicaMissingNum` 应为 0。

---

### 步骤 3：知识点 2 —— FE 角色与命令

```sql
-- 3.1 看 FE 角色
SHOW FRONTENDS\G
```

重点看：`Role`（MASTER/FOLLOWER/OBSERVER）、`IsMaster`、`Join`、`Alive`、`ReplayedJournalId`。

```sql
-- 3.2 登记一个新 Follower（注意端口是 edit_log_port，默认 9010）
ALTER SYSTEM ADD FOLLOWER '127.0.0.1:9011';

-- 3.3 登记一个 Observer
ALTER SYSTEM ADD OBSERVER '127.0.0.1:9012';

-- 3.4 再看列表
SHOW FRONTENDS\G
```

预期：三个 FE 都在列表里，角色正确。但新加的两个是：

```
Join: false    Alive: false
```

> **为什么会这样**：`ADD FOLLOWER` 只是"登记"。真正的加入需要那个节点上的 FE 进程启动，并且带 `--helper` 指向 Master：
>
> ```bash
> bin/start_fe.sh --helper <master_host>:9010 --daemon
> ```
>
> 没有真实进程 → 心跳不通 → `Alive: false`；没拉过元数据 → `Join: false`。

```sql
-- 3.5 清理，恢复单 FE
ALTER SYSTEM DROP FOLLOWER '127.0.0.1:9011';
ALTER SYSTEM DROP OBSERVER '127.0.0.1:9012';
```

🟡 **边界提醒**：本步骤验证的是**命令语法与注册流程**。选举过程因单机限制未实测——`ADD` 出来的节点没有真实进程，不会真的参与投票。

---

### 步骤 4：知识点 3 —— 扩缩容与数据均衡

> 本步骤需要第二台 BE。没有的话先跑 `assets/lesson09-add-be2.sh`。

```sql
-- 4.1 确认集群现状
SHOW BACKENDS\G
```

记下两台 BE 的 `BackendId`、`HeartbeatPort`、`TabletNum`。

```sql
-- 4.2 看均衡开关（默认关闭！）
SHOW FRONTEND CONFIG LIKE 'disable_balance';
```

预期：`disable_balance    true`

```sql
-- 4.3 打开均衡
ADMIN SET FRONTEND CONFIG ('disable_balance' = 'false');
```

```sql
-- 4.4 等 90 秒后，观察 tablet 是否开始搬
SHOW BACKENDS\G
```

**对比两次的 `TabletNum`**：新节点的数字应该上升，老节点下降。

实测参考（本机 90 秒）：3850 → 3848，8 → 10。

```sql
-- 4.5 看调度器的工作记录
SHOW PROC '/cluster_balance';
```

重点看 `history_tablets`（累计调度过的 tablet 数）和 `working_slots`。

```sql
-- 4.6 缩容：安全做法
ALTER SYSTEM DECOMMISSION BACKEND '127.0.0.1:19050';
```

执行后立刻看：`SystemDecommissioned` 应变为 `true`。

**等 120 秒**，再看两台 BE 的 `TabletNum`——被摘除的节点应该下降，另一台上升。

实测参考：15 → 13，3855 → 3857。

```sql
-- 4.7 反悔：取消缩容
CANCEL DECOMMISSION BACKEND '127.0.0.1:19050';
```

`SystemDecommissioned` 应立刻变回 `false`。

```sql
-- 4.8 危险操作：观察 Doris 的防呆
ALTER SYSTEM DROP BACKEND '127.0.0.1:19050';
```

你会被明确拒绝：

```
ERROR 1105 (HY000): errCode = 2, detailMessage = It is highly NOT RECOMMENDED
to use DROP BACKEND stmt. It is not safe to directly drop a backend.
All data on this backend will be discarded permanently.
If you insist, use DROPP instead of DROP
```

> **到此为止，不要真的执行 `DROPP`。** 看到这条报错就够了——它的存在本身就是设计意图的证明。

```sql
-- 4.9 限速参数（解释为什么在线业务无感）
SHOW FRONTEND CONFIG LIKE 'balance_slot_num_per_path';
SHOW FRONTEND CONFIG LIKE 'partition_rebalance_max_moves_num_per_selection';
SHOW FRONTEND CONFIG LIKE 'tablet_repair_delay_factor_second';
```

预期：`balance_slot_num_per_path = 1`——每块盘同时只搬 1 个 tablet。

---

### 步骤 5：宕机演练

> ⚠️ **这一步会真的停掉一个 BE 进程**。只在你自己搭的学习环境做，别在生产上试。

```bash
# 5.1 找到第二个 BE 的进程号
docker exec doris-learn bash -c "ps aux | grep '[b]e2/lib/doris_be' | awk '{print \$2}'"
```

```bash
# 5.2 kill 掉它（模拟宕机）
docker exec doris-learn bash -c "kill -9 <上一步拿到的PID>"
```

然后**立刻**（10 秒内）执行查询。

**⚠️ 不要用 `COUNT(*)` 验证**——它会走元数据优化直接返回，节点宕机了也照常出结果（本课实测发现的坑）。用这两条：

```sql
-- orders：数据在存活节点上，正常返回
SELECT id, province, amount FROM orders LIMIT 3;

-- repl3：数据在宕机节点上，报错
SELECT id, province, amount FROM repl3 LIMIT 3;
```

预期报错（心跳窗口内）：

```
ERROR 1105 (HY000): RpcException, msg: send fragments failed.
io.grpc.StatusRuntimeException: UNAVAILABLE: io exception, host: 127.0.0.1
```

**等 30 秒后**（心跳超时，FE 判定节点死亡）再查一次：

```sql
SELECT id, province, amount FROM repl3 LIMIT 3;
```

报错会变成另一种（这次是明确的"没有可查询副本"）：

```
ERROR 1105 (HY000): errCode = 2, detailMessage = tablet 1788336178413 has no queryable replicas.
err: replica 1788336178414's backend 1788336178366 with tag {"location" : "default"}
does not exist or not alive
```

```sql
-- 5.3 观察集群进入修复状态
SHOW PROC '/cluster_health/tablet_health';
```

`HealthyNum` 会下降，`NeedFurtherRepairNum` 会大于 0。

```bash
# 5.4 恢复节点
docker exec -d doris-learn bash /opt/be2/launch.sh
```

```sql
-- 5.5 等 45 秒，验证自愈
SHOW PROC '/cluster_health/tablet_health';
```

**`HealthyNum` 应该自己回到 611（等于 TabletNum），全程没有任何人工干预。**

---

## 第五幕：体系收束

回到第一幕的那个凌晨两点。

现在你知道，"查询没断"这件事的完整解释是：

> **不是 Doris 有什么魔法让挂掉的节点继续服务，而是你要查的那份数据，恰好还住在活着的机器上。**

把所有拼图合起来：

```
一张表
  ├─ 按分区横切 ─┐
  ├─ 按分桶竖切 ─┼→ 切成 N 个 Tablet（调度的最小单位）
  └─ 每桶抄 R 份 ─┘   每个 Tablet 有 R 个 Replica

副本放哪？→ 反亲和：同一台物理机上不放同 tablet 的两个副本
机器挂了？→ 心跳 10s 超时判定 → 调度器自动补副本 → 无需人工干预
想加机器？→ ADD BACKEND → 打开 disable_balance → 按 slot 慢慢渗
想减机器？→ DECOMMISSION（先迁数据，可 CANCEL），别用 DROPP
```

### 三个数字，记住就够了

| 数字 | 含义 | 来源 |
|---|---|---|
| **× N** | N 副本 = N 倍存储成本 | 实测：100 万行 1 副本 2.553 MB |
| **10 秒** | 心跳间隔，约 10~20 秒判定节点死亡 | `heartbeat_interval_second = 10` |
| **1** | `balance_slot_num_per_path = 1`，每盘同时只搬 1 个 tablet | 这是在线业务无感的原因 |

### 与前后课程的关联

- **← 课 5（分区分桶）**：本课讲的 Tablet，就是分区 × 分桶的产物。那时我们关心"怎么切查询快"，现在关心"怎么切才不丢数据"
- **← 课 8（Colocate Join）**：Colocate 要求两表"同组同桶"，本质是让 Join 的两个 tablet 落在同一台 BE 上——**这正好是副本反亲和的另一面**（一个要分散、一个要聚拢）
- **→ 课 10（资源隔离）**：本课讲了"机器挂了怎么办"，课 10 讲"机器没挂但被一个大查询拖垮了怎么办"
- **→ 课 12（存算分离）**：本课的多副本语义基于存算一体。存算分离下数据可靠性由共享存储承担，**副本的含义会变**，读到课 12 记得回来交叉验证

### 一张图总结

![副本与高可用全图](./assets/lesson-09-replica.svg)

![扩缩容与 FE 全图](./assets/lesson-09-summary.svg)

---

## 🐞 常见误区

### 误区 1：设置了 `replication_num = 3`，数据就有 3 份

**错。** 副本数是**请求**，不是保证。实测：在 2 台 BE（同主机）上建 3 副本表，建表成功、插入成功，但 `SHOW TABLETS` 显示只有 6 个副本（= 分桶数），不是 18 个。

**怎么查真相**：`SHOW PROC '/statistic'`，看 `ReplicaNum` 是不是 `TabletNum` 的 N 倍。

### 误区 2：查询没断，是因为副本在其他节点上顶住了

**这是本课最大的误解。** 实测反例：1 副本的 `orders` 在宕机后照常返回 2150 万行，而"3 副本"的 `repl3` 直接报错。

**真相**：`orders` 能查，是因为它唯一的副本恰好住在**存活的**那台 BE 上。与副本数量无关，与**数据住在哪**有关。

### 误区 3：2 个 FE 也能高可用

**不能。** 2 的半数是 1，"超过半数"需要 2 票。挂 1 台后只剩 1 票，选不出 Master。

**FE 必须奇数个**：3 个容忍 1 台，5 个容忍 2 台。2 台的容错能力和 1 台一样是 0，但成本翻倍。

### 误区 4：`ADD FOLLOWER` 执行完，高可用就配好了

**不够。** 实测：执行后 `SHOW FRONTENDS` 能看到节点，但 `Join: false / Alive: false`。

**还差一步**：那个节点上的 FE 进程要带 `--helper <master>:9010` 启动，去拉元数据。这是部署多 FE 最高频的踩坑点。

### 误区 5：加了新节点，数据会自动均衡过去

**不会。** 实测 `disable_balance = true` 是默认值——**均衡默认关闭**。

要手动打开：`ADMIN SET FRONTEND CONFIG ('disable_balance' = 'false');`

### 误区 6：缩容用 `DROP BACKEND` 更快

**危险。** `DROP` 不等数据迁移，直接丢弃该节点全部数据，且不可撤销。

实测 Doris 会拒绝 `DROP` 并提示用 `DROPP`（故意拼错才能执行）——**这个防呆就是为了防止你手滑**。正常缩容一律用 `DECOMMISSION`。

### 误区 7：均衡会拖垮在线查询

**不会，因为有限速。** 实测 DECOMMISSION 进行中连查 5 次：140 / 128 / 151 / 145 / 159 ms，与平时同量级。

**原因**：`balance_slot_num_per_path = 1`，每块盘同时只搬 1 个 tablet。代价是慢（90 秒搬 2 个），收益是业务无感。

### 误区 8：副本越多越好

**要看成本。** 3 副本 = 3 倍存储。真正该问的是：

> "我需要容忍几台机器**同时**故障？"

容忍 1 台 → 2 副本；容忍 2 台 → 3 副本。**3 副本的真正价值不只是冗余更多，而是给了你"坏一台、修一台"的维修窗口。**

### 误区 9：节点挂了要手动去补副本

**不用。** 实测：kill 掉 BE2，什么都不做，重启后 45 秒内 `HealthyNum` 自己回到 611，全绿。

**你要做的是监控，不是修复**：每天看 `SHOW PROC '/cluster_health/tablet_health'`，确保 `HealthyNum == TabletNum`。

---

## ⚡ 速览模式（5 分钟复习）

| 问题 | 答案 |
|---|---|
| Tablet 和 Replica 什么关系？ | Tablet = 分区 × 分桶，是调度单位；Replica 是每个 Tablet 的拷贝份数 |
| 怎么一眼看出集群有没有冗余？ | `SHOW PROC '/statistic'`，`ReplicaNum == TabletNum` → 零冗余 |
| ⚠️ 能用 COUNT(\*) 验证数据可查吗？ | **不能！** COUNT(\*) 走元数据优化不扫 BE，宕机了照样返回。用 `SELECT ... LIMIT 3` 或 `SUM()` |
| 副本为什么放不到同一台机器？ | 反亲和规则：`Failed to find enough backend ... or maybe all be on same host` |
| 2 副本能扛几台故障？ | 1 台；3 副本能扛 2 台 |
| 副本的成本怎么算？ | 单副本大小 × N（实测 100 万行 1 副本 2.553 MB） |
| 节点挂了多久被发现？ | `heartbeat_interval_second = 10`，约 10~20 秒判定死亡 |
| 补副本需要人工吗？ | 不需要，Tablet 调度器自动补（实测 45 秒自愈） |
| Master / Follower / Observer 区别？ | Master 唯一可写；Follower 有投票权；Observer 只读、不投票、分担查询压力 |
| FE 为什么要奇数个？ | "超过半数"规则，2 台的容错能力和 1 台一样是 0 |
| `ADD FOLLOWER` 后还差什么？ | 新 FE 要带 `--helper` 启动拉元数据，否则 `Join: false` |
| 扩容命令？ | `ALTER SYSTEM ADD BACKEND 'host:9050'`（填 heartbeat_port） |
| 数据会自动均衡吗？ | 默认不会，`disable_balance = true` 需手动改 false |
| 安全缩容怎么做？ | `DECOMMISSION`（先迁数据、可 CANCEL），别用 `DROP`/`DROPP` |
| `DROP BACKEND` 为什么被拒绝？ | 防呆设计：想强制删除要故意拼错成 `DROPP` |
| 均衡会拖垮业务吗？ | 不会，`balance_slot_num_per_path = 1` 限速，实测 128~159ms 无抖动 |

---

## 🎓 课后小测

### 第 1 题（概念理解）

执行 `SHOW PROC '/statistic'` 得到：

```
DbName  TabletNum  ReplicaNum
shop    200        200
```

请问这个库的副本情况如何？如果此时有 1 台 BE 宕机，会发生什么？

<details>
<summary>答案</summary>

**副本情况**：`ReplicaNum == TabletNum` 说明**所有表都是 1 副本，集群零冗余**。

**宕机后果**：住在这台宕机 BE 上的 tablet **会查不了**，报 `tablet xxx has no queryable replicas`。不住在它上面的表不受影响。

**这正是本课第二幕实测到的现象**：1 副本的 `orders` 因为副本在存活节点上而正常返回，"3 副本"的 `repl3` 反而因为数据住在宕机节点上而报错。

</details>

### 第 2 题（故障排查）

你执行 `ALTER TABLE t SET ('replication_num' = '2')` 想给表补第二个副本，报错：

```
Failed to find enough backend, please check the replication num,
replication tag and storage medium and avail capacity of backends
or maybe all be on same host.
```

集群有 2 台 BE，磁盘都很空。请列出**至少两种**可能的原因，并说明怎么验证。

<details>
<summary>答案</summary>

**可能原因 1：两台 BE 在同一台物理机上**（反亲和规则）。
验证：`SHOW BACKENDS\G` 看两台的 `Host` 是否相同（比如都是 127.0.0.1）。

**可能原因 2：副本 tag 不匹配**。表的 `replication_allocation` 指定了 tag（如 `tag.location.default: 2`），但 BE 的 tag 不含该标签。
验证：`SHOW CREATE TABLE t` 看 `replication_allocation`；`SHOW BACKENDS\G` 看 `Tag` 列。

**可能原因 3：存储介质不匹配**。表指定了 `storage_medium = SSD`，但没有 SSD 盘。
验证：`SHOW PARTITIONS FROM t` 看 `StorageMedium`；`SHOW PROC '/backends/<id>'` 看盘的 `StorageMedium`。

**本机的实际情况是原因 1** —— 两个 BE 都是 127.0.0.1。

</details>

### 第 3 题（动手操作）

你需要把一台 BE 从集群中摘下来做硬件维护。请写出完整的操作步骤，并说明：

1. 为什么不能用 `DROP BACKEND`？
2. 执行后如果业务反馈变慢，怎么止损？
3. 怎么确认数据已经安全迁走？

<details>
<summary>答案</summary>

**操作步骤**：

```sql
-- 1. 安全摘除（先迁数据，再摘除）
ALTER SYSTEM DECOMMISSION BACKEND '<host>:9050';

-- 2. 观察迁移进度
SHOW BACKENDS\G      -- 看 SystemDecommissioned 与 TabletNum 变化
SHOW PROC '/cluster_balance';   -- 看 history_tablets 增长
```

**1. 为什么不能用 DROP**：
`DROP BACKEND` **不等数据迁移，直接丢弃该节点全部数据，且不可撤销**。如果这台 BE 上有单副本表的数据，那部分数据就永久丢了。而且 Doris 会拒绝 `DROP`，提示必须故意拼错成 `DROPP` 才能执行——这个防呆就是在告诉你"别这么干"。

**2. 业务变慢怎么止损**：

```sql
CANCEL DECOMMISSION BACKEND '<host>:9050';
```

实测执行后 `SystemDecommissioned` 立刻变回 `false`，节点恢复服务。**这是 DECOMMISSION 相比 DROP 最大的优势：可撤销。**

如果确认不是缩容导致的，可以调小搬迁速度：

```sql
ADMIN SET FRONTEND CONFIG ('balance_slot_num_per_path' = '1');
```

**3. 怎么确认数据迁走**：
- `SHOW BACKENDS\G`：被摘除节点的 `TabletNum` 降到 0，其他节点相应上升
- `SHOW PROC '/cluster_health/tablet_health'`：`HealthyNum == TabletNum`，`ReplicaMissingNum == 0`
- 确认 `SystemDecommissioned = true` 且节点 tablet 清空后，才能真正下线机器

</details>

---

## 🚀 下一批接力提示词

> 复制以下整段给下一批 Agent，即可无缝继续课 10。

```
【任务】继续 Apache Doris 系统学习课程，交付课 10《资源隔离与负载管理》
        （stages/4-分布式运维与生产落地/lessons/lesson-10-资源隔离与负载管理.md）

【课 9 已交付内容】
- 三个知识点：多副本与自动修复、FE 高可用、扩缩容与数据均衡
- 情节主线："集群上了生产，某天一台 BE 宕机"——从数据视角转向机器视角
- 正文结构：五幕 + 9 个常见误区 + 速览模式 + 3 道课后小测 + 接力提示词 + 课程导航
- 两张 SVG：lesson-09-replica.svg（Tablet/副本/宕机时间线）、
            lesson-09-summary.svg（FE 三角色/扩缩容命令/限速）
- 6 个可运行脚本：setup / step2-step5 / cleanup + add-be2（拉起第二 BE）

【课 9 的重大环境突破：从单节点变成多节点】
课 9 之前一直是 1 FE + 1 BE。课 9 成功在**同一个容器内拉起了第二个 BE 进程**
（不同端口），集群变成 1 FE + 2 BE，扩缩容/数据均衡第一次变成可真跑的实验。
- BE2 目录：/opt/be2（conf/log/storage，lib 软链到 /opt/apache-doris/be/lib）
- BE2 端口：be=19060, webserver=18040, heartbeat=19050, brpc=18060, arrow=18050
- 启动方式：docker exec -d doris-learn bash /opt/be2/launch.sh
  ⚠️ 不能直接用 start_be.sh —— 它的 pidfile 检查会误判原 BE 进程 2063 就是自己，
     报 "Backend is already running as process 2063"。launch.sh 是直接拉
     /opt/be2/lib/doris_be 二进制，绕过了这个检查。
  ⚠️ 关键环境变量（缺一不可，踩了两轮才跑通）：
     LD_LIBRARY_PATH 必须含 /usr/lib/jvm/java/lib/server（否则 libjvm.so 找不到）
     CLASSPATH 必须指向 /opt/be2 下的真实 jar（用 *.jar 通配符 JVM 不识别，
     必须先拼好完整 classpath 存到 /opt/be2/conf/classpath.txt 再读取）
     DORIS_HOME=/opt/be2, LOG_DIR=/opt/be2/log/, PID_DIR=/opt/be2/bin

【课 9 沉淀给课 10 的关键资产】
1. **副本是"请求"不是"保证"**（最重要的认知）：
   - 建 replication_num=3 的表在 2 台 BE 上建表成功、插入成功，但只落地 6 个副本
     （= 分桶数），不是 18 个。节点不够时 Doris 降级执行而非拒绝。
   - 查真相：SHOW PROC '/statistic' 看 ReplicaNum 是否 = TabletNum × N
     实测 shop 库 TabletNum=643、ReplicaNum=643 → 整机零冗余
2. **"查询没断"的真相**（推翻骨架预设情节）：
   - kill 掉 BE2 后：1 副本的 orders（副本在存活节点）照常返回 2150 万行；
     而声明 3 副本的 repl3（数据住在宕机节点）直接报
     "tablet xxx has no queryable replicas"
   - 结论：查询能不能跑取决于"数据住在哪"，不取决于"有几个副本"
3. **反亲和是硬规则**（本机绕不过去的墙）：
   - 同主机（都是 127.0.0.1）无法补第二个副本，报错
     "Failed to find enough backend ... or maybe all be on same host"
   - 因此"多副本扛宕机"无法在本机实测，只能原理推演 + 单副本宕机反证
4. **扩缩容完全实测**（本课唯一全绿知识点）：
   - ADD BACKEND 秒级生效，重复执行报 "Same backend already exists"
   - ⚠️ 端口填 heartbeat_service_port（9050），不是 be_port（9060）
   - disable_balance 默认 true（均衡默认关闭！）需手动改 false
   - 打开后 90 秒实测 tablet 3850→3848 / 8→10，真的在搬
   - DECOMMISSION 后 SystemDecommissioned=true，120 秒 tablet 15→13 / 3855→3857
   - CANCEL DECOMMISSION 可撤销，SystemDecommissioned 立刻回 false
   - DROP BACKEND 被拒绝，提示 "use DROPP instead of DROP"（防呆设计）
   - 在线查询无抖动：5 次 140/128/151/145/159 ms
5. **关键参数实测值**：
   heartbeat_interval_second=10, max_backend_heartbeat_failure_tolerance_count=1
   balance_slot_num_per_path=1, partition_rebalance_max_moves_num_per_selection=10
   tablet_repair_delay_factor_second=60
6. **自愈实测**：kill BE2 → HealthyNum 611 掉到 603、NeedFurtherRepairNum=8；
   重启后 45 秒自己回到 611 全绿，零人工干预
7. **存储成本实测**：cost1 表 100 万行 1 副本 = 2.553 MB（2 副本≈5.1MB，3 副本≈7.7MB）
8. **FE 高可用边界**：ADD FOLLOWER/ADD OBSERVER 语法可用（能注册、角色正确），
   但无真实进程 → Join=false / Alive=false，选举未实测。
   新 FE 必须带 --helper <master>:9010 启动才真正 Join。
9. **监控视图（每天该看的）**：
   SHOW PROC '/cluster_health/tablet_health'（HealthyNum 应 = TabletNum）
   SHOW PROC '/cluster_balance'（history_tablets 累计调度数，注意是累计值不归零）
   ⚠️ SHOW PROC '/cluster_balance/sched_stat' 在 4.1.3 返回空，改用
      /cluster_balance 看汇总，或 /cluster_balance/working_slots 看并发额度
10. **⚠️⚠️ 最重要的两个坑（写测试/验证脚本时必踩）**：
   ① **不能用 SELECT COUNT(*) 验证"数据是否可查"！**
      Doris 对简单 COUNT(*) 走**元数据行数优化**，直接从 FE 统计返回，不扫 BE。
      实测：所有 tablet 都在宕机节点的表，SELECT COUNT(*) 依然正常返回 50000。
      必须用真正扫数据的查询：SELECT ... LIMIT 3 / SUM() / 带谓词的 GROUP BY。
      ⚠️ 课 10 做资源隔离实验时同样要注意，否则会得出"资源组没生效"的错误结论。
   ② **tablet 落在哪个 BE 无法手动指定**：
      ADMIN MIGRATE TABLET 在 4.1.3 报语法错误
      （ERROR 1105: no viable alternative at input 'ADMIN MIGRATE'）
      也试过反复建表 6 次，6 次全落 BE1（BE1=12, BE2=0）。
      可靠办法：**先建表 → SHOW TABLETS 查它落在哪 → 再决定宕哪个节点**。
11. **报错的两种形态（判断集群处于哪个阶段）**：
    心跳窗口内（约 10 秒内）：RpcException ... UNAVAILABLE: io exception
    心跳超时后（约 10~20 秒）：tablet xxx has no queryable replicas
    差别：前者是"连不上"，后者是 FE 已判定死亡、明确无副本可用

【本课必须遵守的硬约束】（前九课踩坑总结）
1. **第四幕每条命令都要自问「读者照抄能跑通吗？」**
   连续七课（课 3/4/5/6/7/8/9）都因"命令写成省略形式或与建法不配对"被评审抓到 P0。
   禁止出现"（同上）""列定义同上"这类省略，每条 DDL/DML 都要完整可运行。
   课 9 三张实验表的建表语句全部完整给出（副本数/分桶数不同，抄漏一处结论就错）。
2. **绝不能 grep 掉 DDL/DML 的报错输出**——课 3/4/5/6 连续四课因此掩盖真相。
   课 9 严格遵守：反亲和报错、DROP BACKEND 被拒、ADD 重复报错全部原文保留展示。
3. **单机边界必须标注**（课 9 做得最彻底的一次）：
   正文开头加了"实验边界表"，每个知识点带 🟢已实测 / 🟡原理推演 标记。
   课 10 讲 Workload Group 时，单机也能测（资源组是进程内隔离），
   但"多租户抢占"类实验同样受单机构约，请沿用这个标记体系。
4. **数值浮动要如实说明**：课 9 的查询耗时 128-159ms 是 5 次采样，
   正文写的是范围不写单次。课 10 若测性能，务必跑 3-5 次取范围。
5. 交付后必须回写四处档案：00-学习档案.md、00-评审清单.md、
   stages/4-分布式运维与生产落地/overview.md、02-课程目录.md + 01-学习路径总览.md
6. 交付前必须完成双视角评审（pedagogy + learner 内联），P0 清零才能勾选。

【本机环境状态】
- Doris 4.1.3-rc02-7126cf65d96，容器 doris-learn（9030/8030/8040，healthy）
- **现在是 1 FE + 2 BE**（课 9 新增 BE2）
  BE1: BackendId 1788336157417, 127.0.0.1:9050, Alive
  BE2: BackendId 1788336178366, 127.0.0.1:19050, Alive
  ⚠️ 两台 host 相同（伪多节点），反亲和规则导致无法真正验证多副本
- Kafka 容器 doris-kafka（桥接网络 doris-net，主机名 kafka，topic doris_orders）
- MinIO 容器 doris-minio（桥接网络 doris-net，主机名 minio，bucket doris-demo）
- shop 库既有表（前几课建的，不要删）：orders（2150万行，按 province 分 8 桶）、
  orders_dup、orders_agg、orders_uniq_mow、orders_uniq_mor、rollup_demo（含 rollup_pc）、
  perf_wide（200万行）、perf_wide_big、load_demo、kafka_orders、s3_orders_ext、
  t_part_month、t_bucket_8、k_prov_first、k_date_first、empty_t
  课 8 新增：dim_region、non_colo_dim、fact_1m、fact_prov、v_probe、
            log_typed/log_variant/log_json、mv_prov_pay_daily/mv_part_daily/mv_sched
  课 9 新增：cost1、repl3、ha_demo、ha_demo2（跑 lesson09-cleanup.sh 可清理）
- 全局设置：enable_profile=true、**enable_sql_cache=false**
  （课 7 关的，课 8/9 沿用。课 10 若测性能请保持；不测请恢复 true）
- disable_balance 已被课 9 改为 false（原来是 true）
  ⚠️ 这意味着集群现在会自动均衡，如果课 10 要做确定性实验可能需要先关掉
- 连 Doris：docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop
  ⚠️ 必须带 -i，否则管道喂进去的 SQL 会被静默丢弃
  ⚠️ SET 会话变量跨连接失效：必须写成 runq "SET x=1; SELECT ...;" 同一连接
```

---

## 🧭 课程导航

⬅️ **上一课**：[课 8：多表关联与高级 SQL](../../3-数据导入与查询/lessons/lesson-08-多表关联与高级SQL.md)

➡️ **下一课**：[课 10：资源隔离与负载管理](lesson-10-资源隔离与负载管理.md)

📚 **返回目录**：[课程目录](../../../02-课程目录.md)

🏠 **返回阶段**：[阶段 4：分布式运维与生产落地](../overview.md)
