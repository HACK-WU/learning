# 课 14：该不该用 ES

> 阶段 5《生产与选型》· **收官课** ｜ 3 个知识点 ｜ 约 60 分钟
>
> 前 13 课教你怎么用 ES，本课回答一个更难的问题——**什么时候不该用**。
> 学完这一课，你不仅能操作 ES，还能在技术方案评审会上说清楚"为什么选它"和"为什么不选它"。

---

## 🎯 本课目标

| 学完你能做到 | 对应知识点 |
|---|---|
| 拿到一个需求，能在 5 分钟内判断该不该上 ES，并说出理由 | ① 选型决策清单 |
| 清楚 Elastic 认证考什么、怎么准备、本机环境覆盖多少 | ② 认证备考指南 |
| 把 42 个知识点串成一张可查阅的地图，知道遇到问题去哪查 | ③ 知识体系收束 |

---

## 🧭 贯穿全课的类比：ES 是一辆"消防车"

想象 ES 是一辆**消防车**：

- 它的**水炮**（全文检索）威力巨大，能穿透浓烟精准命中火点——普通水管（数据库 `LIKE`）做不到
- 它自带**水箱和水泵**（分布式、副本、自愈），开到哪都能独立作业
- 但它的**油耗惊人**（资源开销），**转弯半径大**（不支持事务、跨表关联），**不能当通勤车**开去买菜

这个类比会在三个知识点里反复回扣。同时我们会明确标注**它在哪些地方会失效**——任何类比都有边界，知道边界比记住类比更重要。

---

## 第一幕 · 场景引入：一个真实的评审会

假设你在技术方案评审会上，同事提出：

> "我们的订单系统现在用 MySQL，用户抱怨搜索慢。我把订单数据同步到 ES 里，然后**直接让业务系统读写 ES**，MySQL 那边就不维护了。"

听起来很有道理——ES 查询快、能分词、还能聚合。

**但这个方案有个致命问题。** 你能看出来吗？

先别急着往下看，花 10 秒想想：如果 ES 里的订单数据因为某种原因丢了一条，会发生什么？

（答案在本课结尾揭晓，但学完知识点 1 你就能自己判断了。）

---

## 第二幕 · 认知冲突：三个"想当然"的坑

大多数教程上来就讲"ES 很强大"。但真正值钱的能力是**知道它什么时候不行**。

我们直接看本机实测。下面四组实验，全部在 `http://localhost:9201` 上真实跑出来。

### 想当然 ①：分片越多，查询越快 ❌

课 10 建了三个索引 `l10_shard_1` / `l10_shard_3` / `l10_shard_50`，**各 3000 条完全相同的数据，唯一变量是主分片数**——这是天然的控制变量实验。

**想当然 ②：ES 和数据库一样有事务** ❌

**想当然 ③：写入之后立刻能搜到** ❌

**想当然 ④：分片多一点没关系，反正结果一样** ❌

下面逐条用实测打脸。

---

# 知识点 1：选型决策清单

## 第三幕 · 层层揭示

### 1.1 实测 A：分片不是越多越好

#### 查询延迟（30 次采样取分位数）

| 主分片数 | p50 | p95 | min |
|---|---|---|---|
| 1 | 15.23 ms | **16.58 ms** | 4.51 ms |
| 3 | 15.41 ms | 16.48 ms | 13.62 ms |
| 50 | 15.62 ms | **35.90 ms** | 9.59 ms |

> 📊 **p50 / p95 是什么**：把 30 次查询耗时从小到大排序，p50 是第 50% 位置的值（中位数），**p95 是第 95% 位置的值——意思是 95% 的请求都快于它**。p95 专门用来暴露"偶尔特别慢"的长尾问题，比平均值敏感得多。
>
> 脚本：[04-benchmark.js](/D:/projects/learning/elasticsearch/playground/l13-client/04-benchmark.js)

**p50 几乎没差别，但 p95 差了 2.2 倍。** 为什么？

一次搜索要**扇出**到每个分片（即把查询请求分发给所有分片并行执行），再在**协调节点**（接收你请求的那个节点）合并结果。50 个分片意味着 50 次扇出，任何一次慢都会拖累整体。

#### 存储开销（同样 3000 条）

| 主分片数 | 存储大小 | 段数量 |
|---|---|---|
| 1 | 77.3 kb | 1 |
| 3 | 88.9 kb | — |
| 50 | **361.9 kb** | **50** |

**50 分片的存储是 1 分片的 4.7 倍**，**段**（segment，Lucene 底层的最小存储单元，一个分片由若干段组成）数量是 50 倍。每个分片都有固定开销，数据量小时这些开销占比极高。

#### 最致命的一条：多分片会让聚合结果不准

同样的 `terms` 聚合，在 1 分片和 50 分片上对比：

```
l10_shard_1（1 分片）：
  doc_count_error_upper_bound : 0        ← 完全精确
  sum_other_doc_count : 2500
  BRAND-0  → 100    BRAND-1 → 100    BRAND-10 → 100

l10_shard_50（50 分片）：
  doc_count_error_upper_bound : 82       ← 误差上界 82！
  sum_other_doc_count : 2544
  BRAND-0  → 95     BRAND-1 → 90     BRAND-10 → 90
```

**同一份数据，单分片每个桶精确 100，50 分片时 BRAND-0 只剩 95、BRAND-1 只剩 90。**

原理：每个分片各自算出自己的 top N 再交给协调节点合并，某个分片里排不进前 N 的桶就被截断了。分片越多，截断越多，**聚合越不准**。

> 📌 **官方文档建议单个分片 20–50 GB**。你的 `l10_shard_50` 里每个分片只有约 60 条 / 7 kb，属于典型的分片过度 —— 这就是官方建议的现实依据。

**类比回扣**：消防车有 50 个水枪接口，不等于能同时喷 50 股水——水泵功率就那么大，接口开太多，每个都软绵绵。

---

### 1.2 实测 B：ES 没有事务，只有单文档乐观锁

用 `l9_orders` 实测（脚本：[05-limits.js](/D:/projects/learning/elasticsearch/playground/l13-client/05-limits.js)）：

```
取到真实文档：_id=2  _seq_no=0  _primary_term=1
✅ 用【正确】的 _seq_no=0 更新 → 成功，新 _seq_no=8
✅ 用【过期】的 _seq_no=0 再更新 → HTTP 409 冲突
   错误类型：version_conflict_engine_exception
```

**乐观锁**是什么：不加锁，而是在更新时带上版本号；如果期间有人改过，版本对不上就拒绝（返回 409），由调用方决定重试还是放弃。

关键在最后一句：**ES 唯一的事务保障就是"单文档乐观锁"**。

- ✅ 能保证：同一文档的并发更新不会互相覆盖（靠 `_seq_no` + `_primary_term`）
- ❌ 不能保证：多个文档的原子性。改了 A 文档再改 B 文档，中间崩了，**A 不会回滚**
- ❌ 没有：跨文档事务、隔离级别、外键约束

**意味着什么**：如果你的业务是"扣库存 + 生成订单"必须同时成功或同时失败，ES 给不了这个保证。

---

### 1.3 实测 C：ES 不支持跨表关联（JOIN）

同一个脚本里，我用 ES|QL 尝试 SQL 风格的 JOIN：

```
FROM l9_orders o JOIN l11_shop_v2 s ON o.shop_id = s.id LIMIT 3

→ HTTP 400 | parsing_exception
  原因：line 1:16: mismatched input 'o' expecting {<EOF>, '|', '::', ',', 'metadata'}
```

对照，不带 JOIN 的普通 ES|QL 完全正常：

```
FROM l9_orders | LIMIT 3 | KEEP amount

    amount
---------------
800.0
1200.0
100.0
```

**ES 没有关系型 JOIN。** 想表达关联关系，只有四条路：

| 方案 | 做法 | 代价 |
|---|---|---|
| **反范式冗余**（最常用） | 把关联字段直接写进主文档，用空间换关联 | 数据冗余，更新要同步改多处 |
| `nested` 类型 | 同索引内嵌对象数组 | 查询慢，父子需同分片 |
| `parent-child` join | 同索引内建父子关系 | 性能代价大，官方不推荐滥用 |
| 应用层拼装 | 查两次，代码里组装 | 丧失数据库端的关联优化 |

> 注：9.x 的 `LOOKUP JOIN` 要求被关联的索引标记为 `lookup` 索引，且是**左连接语义**，不能替代任意关系型 join。

---

### 1.4 实测 D：写入不是实时的（近实时）

这是把 ES 当数据库用时**最容易踩的坑**。脚本：[06-nrt.js](/D:/projects/learning/elasticsearch/playground/l13-client/06-nrt.js)

```
① 默认写入后【立刻】搜索        → 命中 0 条
② 等待 1.2 秒后搜索             → 命中 1 条 ✅
③ 用 refresh=true 写入后立刻搜  → 命中 2 条 ✅
④ 对照：GET 单个文档（按 _id）  → 实时可读 ✅
⑤ refresh_interval=-1 后写 1 条，等 1.5s 搜 → 命中 2 条（搜不到新写的）
```

**第 ① 和 ④ 的对比是全课最容易被忽略的分界点**：

| 操作 | 读什么 | 是否实时 |
|---|---|---|
| `GET /index/_doc/{id}` | **translog**（事务日志，写入时先落的可靠日志） | ✅ **实时** |
| `POST /index/_search` | **段**（segment，要 refresh 才生成） | ⏱ **近实时**（默认 1 秒） |

**近实时**（Near Real-Time，NRT）：不是实时，但延迟很短。ES 用这个换取写入吞吐。

**这不是 bug，是设计取舍。** 但如果你要的是"写入后立刻能查到"的强一致读，ES 默认给不了。

**实操建议**：

| 场景 | 怎么做 |
|---|---|
| 常规业务 | 接受 1 秒延迟，别动默认值 |
| 批量导入 | 设 `refresh_interval=-1`，导完再 `POST /_refresh`（第 ⑤ 条印证） |
| 单元测试 | 用 `?refresh=true`，别用 `sleep`（第 ③ 条） |
| ❌ 生产高频写入 | **千万别**每条都 `refresh=true`，会疯狂产生小段 |

---

## 第四幕 · 实操验证

把上面的结论变成你能自己跑的命令。

### 验证 1：复现分片数的性能差异

```powershell
# 在 PowerShell 中运行（数据已存在，直接跑脚本）
Set-Location "D:\projects\learning\elasticsearch\playground\l13-client"
node 04-benchmark.js
```

不想跑脚本，用命令直接看存储差异：

```powershell
curl.exe -s "http://localhost:9201/_cat/indices/l10_shard_*?v&h=index,pri,rep,docs.count,store.size"
```

你会看到三个索引文档数都是 3000，但 `store.size` 从 77.3kb 涨到 361.9kb。

### 验证 2：复现聚合精度差异

建两个 JSON 文件再引用（**本机 PowerShell / CMD 都不认内联单引号 JSON，必须用文件写法**）：

`agg.json`：
```json
{"size":0,"aggs":{"by_brand":{"terms":{"field":"brand","size":5}}}}
```

```powershell
curl.exe -s -X POST "http://localhost:9201/l10_shard_1/_search" -H "Content-Type: application/json" --data-binary "@agg.json"
curl.exe -s -X POST "http://localhost:9201/l10_shard_50/_search" -H "Content-Type: application/json" --data-binary "@agg.json"
```

对比两次返回的 `doc_count_error_upper_bound`：一个是 0，一个是 82。

### 验证 3：复现近实时

```powershell
Set-Location "D:\projects\learning\elasticsearch\playground\l13-client"
node 06-nrt.js
```

会依次输出"立刻搜 0 条 → 等 1.2 秒 1 条 → refresh=true 立刻可见 → GET 实时 → 关掉刷新搜不到"。

### 验证 4：复现乐观锁冲突

```powershell
Set-Location "D:\projects\learning\elasticsearch\playground\l13-client"
node 05-limits.js
```

会输出"正确 seq_no 更新成功 → 过期 seq_no 返回 409 → JOIN 语法解析失败"。

---

## 第五幕 · 体系收束：决策清单

### ✅ 适合上 ES 的信号

| 信号 | 原因 |
|---|---|
| 需要**全文检索**（分词、相关性打分、高亮） | 倒排索引是 ES 的看家本领，数据库 `LIKE` 会全表扫 |
| 需要**复杂聚合分析**（多维分组、分位数、时序） | 列存 + 聚合框架，课 9 实测过 |
| 数据量**持续增长的时序数据**（日志、指标、埋点） | Data Stream + ILM 自动滚动、自动过期（课 13 实测） |
| 能接受**秒级延迟** | 近实时特性，1.4 节实测 |
| 查询模式**多变**、难以预先建索引优化 | 即时聚合比固定 BI 报表灵活 |
| 需要**语义检索 / RAG**（向量 + 关键词混合） | 课 13 实测：关键词搜「宠物」1 条 vs 向量 3 条 |

### ❌ 不该上 ES 的信号

| 信号 | 后果 | 替代方案 |
|---|---|---|
| 需要**多文档事务** | ES 只有单文档乐观锁（1.2 节） | 关系型数据库 |
| 需要**强一致读**（写完立刻查到） | 近实时，默认 1 秒延迟（1.4 节） | 关系型数据库 / KV 存储 |
| 数据是**高度关联的关系模型** | 无跨表关联（1.3 节） | 关系型数据库 / 图数据库 |
| 把 ES 当**唯一数据源**（没有源头） | 数据丢了难恢复，重建代价大 | ES 必须是"可重建的副本" |
| 频繁**单行更新**、按主键点查为主 | ES 的强项是检索不是点查 | KV 存储（Redis）/ 关系型数据库 |
| 数据量小（< 百万级）且只有简单查询 | 杀鸡用牛刀，运维成本 > 收益 | PostgreSQL 全文检索够用 |

### 🔑 一句话判断标准

> **ES 应该是你数据的"索引副本"，不是"原始账本"。**
> 原始数据放在关系型数据库或对象存储里，ES 从那里同步过来、丢了能重建。
> 如果你的设计方案里 ES 挂了数据就没了——这个设计是错的。

**回到开场那个评审会**：同事的方案错在"**MySQL 那边就不维护了**"。订单数据是原始账本，一旦把 ES 当唯一数据源，丢一条就是丢一笔订单，且无法对账。正确做法是 ES 作为 MySQL 的只读副本，随时可从源头重建。

### 分片规划建议

| 场景 | 建议 |
|---|---|
| 单个分片目标大小 | **20–50 GB**（官方建议） |
| 日志类（Data Stream） | 让 ILM 自动滚动，别手动分 |
| 小数据量（< 10 GB） | **1 个主分片就够**，别学 `l10_shard_50` |
| 分片数改不了怎么办 | 用 `reindex` 迁到新索引，或用 `shrink` API 收缩 |
| 副本数 | 至少 1（高可用），读多场景可加到 2–3 |

> ⚠️ **主分片数创建后不可更改**。课 10 强调过，规划时宁小勿大 —— 分片太少可以后来 `split`，太多只能 `shrink` 或重建。

### 类比失效的地方

"消防车"类比到这里要收一下，明确它**不能**解释的三件事：

1. **ES 不是只能"灭火"**：它做聚合分析、时序指标同样强，不只是全文检索。消防车类比会让人低估它的分析能力。
2. **"油耗大"不是绝对劣势**：ES 的资源开销换来的是检索性能。在搜索场景里这个交换是划算的——**只有当你要的是事务时，它才是纯浪费**。
3. **"不能当通勤车"有例外**：很多团队确实把 ES 当主存储用（尤其日志场景，数据本来就可重建）。这不是错的，前提是**接受丢数据可重建**，这又回到上面的判断标准。

---

# 知识点 2：认证备考指南

## 2.1 先说最重要的：考纲刚换了

Elastic 认证工程师考试（Elastic Certified Engineer）于 **2026-09-01 正式从 8.15 升级到 9.3**。今天（2026-09-01）正是切换生效日。

**双源确认**（Elastic 官方考试页 + 官方 FAQ 原文）：

> An update to the Elastic Certified Engineer exam, bringing it from Elastic 8.15 to 9.3 is coming on September 1, 2026. Exams taken in August will use the current 8.15 version. All exams on or after September 1 will reflect the updated 9.3 content.

**直接影响**：网上绝大多数备考攻略（包括很多 2025 年的）都是按 8.15 写的，**不要在 9.3 考试里套用它们的重点**。

---

## 2.2 考试基本盘

| 项目 | 内容 |
|---|---|
| 形式 | **纯实操**（performance-based），无选择题 |
| 时长 | **3 小时** |
| 题量 | 约 10–12 个任务 |
| 环境 | 远程监考（摄像头 + 共享屏幕），Linux 环境 + Kibana Dev Tools |
| 开卷 | ✅ **可用官方文档**，❌ 无外网、无笔记、无第二块显示器 |
| 费用 | **$500 USD / 次**（以官方 FAQ 为准） |
| 有效期 | 通过后 2 年 |
| 重考 | 有等待期（14 天 holding period），需重新付费 |
| 评分 | **按任务给分，部分正确也有分** → 每题都写，别空着 |

> ⚠️ 网上二手信息互相矛盾（有的说 $400、有的说通过率 50–60%），**费用以官方 FAQ 的 $500 为准**。

---

## 2.3 9.3 考纲：新增 / 保留 / 移除

官方用 `*` 标记新增、`-` 标记移除。以下是**官方原文清单**：

### 🆕 新增（官方标 `*`）

| 考点 | 说明 |
|---|---|
| **`Elasticsearch Architecture`（整个大类）** | 全新板块：Elastic Stack 架构、节点角色、分片分布、集群拓扑 |
| **`Describe shard sizing and allocation strategies`** | 分片大小规划与分配策略 ← **正好是 1.1 节实测的内容** |
| **`Implement semantic search`** | 语义搜索 ← 课 13 的向量检索 |
| **`Write and execute ES\|QL queries`** | ES\|QL 查询 ← 课 9 学过 |
| **`Ingest and process data using Streams`** | 9.x 新数据接入方式 |
| **`Define and use index aliases`** | 索引别名（从旧考纲挪到 Data Management，升为必考） |
| **`Select and configure appropriate ingest methods`** | 摄入方式选型 |
| **`Monitor and maintain cluster health`** | 集群健康监控 |
| **`Security & Access Control`（整个大类）** | 新增：RBAC、生产环境安全加固 ← 课 13 学过 |

### ✅ 保留

`Define an index` / `dynamic template` / `ILM policy` / `index template` 创建 data stream / `mapping` / `multi-fields` / `Reindex` & `Update By Query` / `ingest pipeline` / `term & phrase` 查询 / `bool` 组合查询 / `async search` / `metric & bucket aggregations` / `sub-aggregations` / `RBAC`

### ❌ 移除（官方标 `-`）

| 移除的考点 | 备注 |
|---|---|
| `runtime fields`（定义 + 搜索时用它） | API 还在，只是不考了 |
| `cross-cluster search` / `cross-cluster replication` / 跨集群操作 | 整块移除 |
| `searchable snapshot` | 移除 |
| `Developing Search Applications` 整个大类（排序、分页） | 排序和分页**知识点本身还在考**，只是不单列 |
| `Define and use appropriate field data types...` | 部分内容并入 mapping |

> **备考含义**：按 8.15 攻略复习，会在 runtime fields、跨集群搜索上浪费大量时间——**这些 9.3 不考了**。反过来，Architecture 和 semantic search 是全新的，旧攻略完全没覆盖。

---

## 2.4 本机环境能覆盖多少考点？（逐条实测）

我逐条探测了 9.3 考纲的每个考点在你本机能不能练。脚本：[07-syllabus.js](/D:/projects/learning/elasticsearch/playground/l13-client/07-syllabus.js)

### 新增考点

| 考点 | 本机 | 说明 |
|---|---|---|
| Architecture：节点角色 | ✅ | 实测三节点均为 `dim` 角色 |
| Architecture：分片分配策略 | ✅ | 分配类设置项可读可改 |
| ES\|QL | ✅ | `FROM l9_orders \| LIMIT 2` 正常返回 |
| semantic search（kNN） | ✅ | `l13_vector_demo` 上命中 3 条 |
| **`semantic_text`（自动推理）** | ❌ | **basic license 限制**（详见下文） |
| Streams | ❌ | 需要额外配置，本机未启用 |

### 保留考点

| 考点 | 本机 | 证据 |
|---|---|---|
| Index aliases | ✅ | API 可用 |
| Ingest pipeline | ✅ | API 可用 |
| ILM policy | ✅ | 现有 48 个策略 |
| Index template（含 data stream） | ✅ | `l13_logs_template`，`data_stream=true` |
| Async search | ✅ | 提交成功，`is_running=false` |
| Snapshot / SLM | ✅ | `l11_repo` 存在 |
| RBAC | ✅ | `l13_readonly` 角色 + `l13_reader` 用户，读 `l8_orders` 得 24 条 |
| IK 中文分词 | ✅ | 「苹果手机」→ `苹果 / 手机` |

### 9.3 已移除考点（本机表现）

| 考点 | 本机 | 说明 |
|---|---|---|
| runtime fields | ✅ 能跑 | API 仍在，只是不考了（实测 `amount=1 → dbl=2`） |
| cross-cluster search | ❌ | `illegal_argument_exception`，未配置远程集群 |
| searchable snapshot | ❌ | 需 enterprise license，本机 basic |

### ⚠️ 最重要的坑：`semantic_text` 在本机练不了

课 13 已经踩过，这里再强调，因为它是**新增考点**：

```
semantic_text 字段：
  ✅ 能建索引
  ✅ 能建映射
  ❌ 一写入就报：current license is non-compliant for [inference]
```

**狡猾在"建时不报错、写时才炸"。** 两个集群 license 都是 **basic**，而 inference（推理端点，即调用模型把文本转成向量的服务）是付费功能。

**备考对策**（三选一）：

1. 用**手动挡**练：`dense_vector` 字段 + 自己算向量 + `knn` 查询 —— 本机完全可用，且**考点 `Implement semantic search` 用手动挡同样能答对**
2. 起一个 30 天 trial license 的临时集群专门练这个点
3. 只把 `semantic_text` 的语法背下来，实操靠手动挡

> 💡 推荐方案 1。考试考的是"实现语义搜索"，不是"必须用 `semantic_text` 字段类型"。

---

## 2.5 备考中我踩到的两个坑（真实记录）

写这一课时，我在探测脚本里踩了两个坑，值得当作备考教训。

### 坑 1：kNN 字段名写错会**静默返回 0 条**

我探测时把向量字段写成 `my_vector`，实际是 `embedding`：

```
query_vector=[1,0,0]  → 命中 0 条        ← 字段名错，不报错！
```

改成正确字段名后：

```
query_vector=[1,0,0]  → 3 条: 猫是一种宠物(0.9969)  狗是人类的朋友(0.9958)  披萨是意大利美食(0.5279)
```

**kNN 查询对错误的字段名不报错，直接返回空结果。** 考试时遇到"向量查询没结果"，第一件事是查映射确认字段名。

### 坑 2：runtime field 偶发 `script_exception`

我第一次用 `doc['amount'].value` 时报错，一度以为是字段缺值。但换索引重跑、又重跑一次，**四个索引全部成功**：

```
l10_shard_1  amount  value_count=3000  ✅ 成功，amount=1 → doubled=2
```

**首次脚本编译的偶发失败，重试即可。** 不要像我一样先怀疑数据结构。

> 📌 **但有一条真实规律要记住**：`doc[...]` 读的是**列存**（列式存储，聚合和脚本用的数据结构），只能读映射中声明且有值的字段；`params._source` 读原始 JSON，不受映射限制但更慢。用 `value_count` 聚合可以探出字段在列存里到底有没有值。

---

## 2.6 备考策略：3 小时怎么分配

综合多位通过者的经验（NetEye 博客、George Bridgeman、Biplab Gautam）：

### 时间分配

| 阶段 | 时长 | 做什么 |
|---|---|---|
| 前 20 分钟 | 通读全部任务 | 标出"秒杀题"和"硬骨头" |
| 接下来 90 分钟 | 先做会做的 | 建立信心，把确定分拿到手 |
| 再 60 分钟 | 攻难题 | 卡住超过 5 分钟就跳 |
| 最后 10 分钟 | 复查 | 用查询验证自己的改动真的生效了 |

> ⏱️ **单题不要超过 15–18 分钟。** 很多人是在最后 2–3 题上耗光时间的。

### 三条硬经验

1. **用 Kibana Dev Tools，不要用 curl** —— Dev Tools 有自动补全、能上下键复用历史请求，比 curl 快得多
2. **每题做完都要验证** —— 查一下确认改动生效。评分看的是集群最终状态，不是你敲了什么命令
3. **部分给分，所以别空着** —— 做一半也有分，跳过就是 0

### 高频考点（多位通过者一致提到）

- dynamic template / 自定义 analyzer
- 多层聚合（sub-aggregation）
- bool 组合查询、multi_match、function_score
- ILM + data stream（hot/warm/cold/delete）
- ingest pipeline（grok / date / script）
- reindex / update_by_query
- **新增**：ES|QL、semantic search、节点角色与分片分配

---

## 2.7 你的优势：这 14 课 × 9.3 考纲对照

| 9.3 考纲大类 | 对应本课 | 覆盖情况 |
|---|---|---|
| Elasticsearch Architecture | 阶段 4（课 9–10） | ✅ 节点角色、分片、集群拓扑都学过 |
| Data Management | 课 3、5、11、13 | ✅ 映射、模板、ILM、data stream、别名 |
| Data Processing | 课 5、11 | ✅ ingest pipeline、reindex、update_by_query |
| Searching Data | 课 6–9、13 | ✅ 全文检索、bool、聚合、ES\|QL、向量 |
| Cluster Management | 课 10–11、13 | ✅ 分片诊断、快照、SLM、集群健康 |
| Security & Access Control | 课 13 | ✅ RBAC、角色、用户 |

**结论：考纲六大类，本课程全部覆盖。** 你需要补的主要是：

1. **`Streams`**（9.x 新特性，本机练不了）
2. **`semantic_text`**（license 限制，用手动挡替代）
3. **考试环境下的手速** —— 建议按 2.6 节的时间分配做 2–3 次限时模拟

### 推荐的模拟练习（用本机现成数据自编考题）

| 模拟题 | 用到的数据 | 对应考点 |
|---|---|---|
| 建一个带自定义 analyzer 的索引，要求中文分词 | `news_ik`（9200，IK 已装） | mapping + analyzer |
| 建 ILM 策略：7 天滚动、30 天删除，应用到 data stream | `l13-logs-app` 可参考 | ILM + data stream |
| 写 bool 查询 + 多层聚合 | `l9_orders` / `l9_hi` | Query DSL + 聚合 |
| 用 ES\|QL 完成同样的聚合 | `l9_orders` | ES\|QL |
| 诊断并修复一个 yellow 集群 | 手动停掉一个节点 | 集群健康 |
| 建只读用户并验证权限边界 | `l13_reader` 已建好 | RBAC |

---

# 知识点 3：知识体系收束

## 3.1 42 个知识点的全景地图

到这里，**5 个阶段、14 节课、42 个知识点全部完成**。先看全景：

```
阶段 1：为什么需要 ES（课 1–2）        ← 是什么、为什么
  ↓
阶段 2：核心原理与上手（课 3–5）        ← 数据怎么存
  ↓
阶段 3：查询与聚合（课 6–9）            ← 数据怎么查
  ↓
阶段 4：分布式与工程实践（课 10–12）    ← 怎么扛住生产
  ↓
阶段 5：生产与选型（课 13–14）          ← 用在哪、值不值
```

这个顺序不是随便排的，它**沿着一条主线**：从"认识它"到"用它"到"用好它"再到"判断要不要用它"。

---

## 3.2 一张表收束全部 14 课

| 阶段 | 课 | 主题 | 一句话记住 |
|---|---|---|---|
| 1 基础 | 1 | 为什么数据库搞不定搜索 | 数据库 `LIKE` 全表扫，ES 倒排索引直接命中 |
| | 2 | ES 是谁、凭什么 | 索引≈表，文档≈行，字段≈列，分片是水平切分 |
| 2 建模 | 3 | 把 ES 跑起来 | 装、启、配置，安全与 path.repo 是关键 |
| | 4 | 倒排索引——快到离谱的秘密 | 中文必须装 IK，`ik_max_word` / `ik_smart` 二选一 |
| | 5 | 映射：给数据定规矩 | text 要分词，keyword 不分词；选错查询就失效 |
| 3 检索 | 6 | Query DSL：问问题的语言 | match 走分词，term 不分词；搞混是头号错误 |
| | 7 | 为什么这条排在前面 | bool 四子句：must/should/must_not/filter |
| | 8 | 聚合：不做搜索，做统计 | bucket 分桶 + metric 计算，可多层嵌套 |
| | 9 | ES\|QL | 管道式语法，与 DSL 结果互证（实测一致） |
| 4 分布式 | 10 | 分片：ES 分布式的基石 | 主分片数不可改，分片不是越多越好（本课实测） |
| | 11 | 集群健康与排障 | yellow/red 归因，有副本转 yellow、0 副本转 red |
| | 12 | 接入真实项目 | bulk 部分失败要逐项检查；深分页用 search_after |
| 5 生产 | 13 | 三大主战场 | 日志用 data stream；向量解决意图匹配；RBAC 管权限 |
| | 14 | **该不该用 ES** | **ES 是索引副本，不是原始账本** |

---

## 3.3 十个"一辈子受用"的结论

从 42 个知识点里提炼最该记住的十条，每一条都来自你的本机实测。

### ① ES 是索引副本，不是原始账本
丢了要能从源头重建。这是本课核心结论，也是所有选型判断的锚点。

### ② 倒排索引决定了一切能力边界
能做的（全文检索、聚合）和不能做的（事务、跨表关联、强一致读），都源于这个数据结构。

### ③ text 分词、keyword 不分词
选错类型，查询会静默失效——**不报错，只是查不到**。

### ④ match 走分词，term 不分词
```
查 keyword 字段用 term，查 text 字段用 match
反过来：term 查 text 字段的"iPhone 15" → 0 条（因为被分词了）
```

### ⑤ filter 不打分且可缓存
能用 `filter` 就别用 `must`。相关性打分是纯开销。

### ⑥ 深分页用 search_after，别用 from/size
课 12 实测：`Result window is too large`，且根因藏在 `root_cause` 里。

### ⑦ bulk 失败要逐项检查，不能只看 errors
课 12 实测：`errors=true` 但成功项**已经落库**了。

### ⑧ 主分片数创建后不可改，且不是越多越好
本课实测：50 分片存储 4.7 倍、p95 延迟 2.2 倍、聚合误差上界 82。

### ⑨ 报错看 root_cause，不看外层
课 12、13、14 反复验证：外层是 `search_phase_execution_exception`，真因在 `root_cause` 里。

### ⑩ ES 没有事务，只有单文档乐观锁
`_seq_no` + `_primary_term` 是唯一保障。多文档原子性请交给关系型数据库。

---

## 3.4 遇到问题怎么查：四层排查法

这是把 42 个知识点变成"可查阅能力"的关键。

### 第 1 层：查不到数据

```
1. 字段名写对了吗？      → GET /index/_mapping
2. 字段类型对吗？        → text 用 match，keyword 用 term
3. 分词器对吗？          → POST /index/_analyze 看实际切分
4. 真的写进去了吗？      → 等 1 秒（近实时）或 ?refresh=true
5. 有别名/路由干扰吗？   → GET /_alias
```

> 本课教训：kNN 字段名写错**静默返回 0 条**，第一步永远是查映射。

### 第 2 层：查询结果不对

```
1. 聚合不准？            → 分片太多？看 doc_count_error_upper_bound
2. 相关性排序奇怪？      → 看 _score 和 explain
3. 中文搜不到？          → IK 装了吗？analyzer 指定了 ik 吗？
4. 大小写/空格问题？     → 看 normalizer 和 keyword 类型
```

### 第 3 层：报错了

```
1. 直接读 root_cause     → 外层 type 通常是包装（search_phase_execution_exception）
2. 维度不匹配？          → 向量 dims 检查（课 13 实测）
3. 权限问题？            → 401 是"你是谁"，403 是"你没权限"，403 末尾会列出所需权限名
4. license 问题？        → non-compliant for [xxx] = 该功能要付费
```

### 第 4 层：慢

```
1. 分片数合理吗？        → 单分片 20-50GB
2. 用了 filter 吗？      → 能 filter 就别 must
3. 取回太多字段吗？      → 用 _source 过滤
4. 深分页了吗？          → 换 search_after
5. 聚合基数爆炸？        → terms 的 size 别太大，看 sum_other_doc_count
```

---

## 3.5 你的本机环境：可查阅清单

学完之后，这套环境本身就是你的实验室。

### 9201 三节点集群（无安全，`http://localhost:9201`）

| 索引 | 文档数 | 用途 |
|---|---|---|
| `l9_orders` | 24 | 订单数据，聚合/查询练习 |
| `l9_hi` | 300 | 大一点的聚合练习数据 |
| `l9_trap2` | 1287 | 陷阱题数据 |
| `l10_shard_1/3/50` | 各 3000 | **分片数对照实验**（本课 1.1 节） |
| `l11_shop_v2` | 3 | 快照/还原练习 |
| `l13-logs-app` | 5（2 个后备索引） | Data Stream + ILM |
| `l13_vector_demo` | 6 | 向量检索（字段名 `embedding`，dims=3） |
| `l13_rag_kb` | 5 chunks | RAG 检索 |

> ⚠️ `l9_orders` 的 `amount` 字段是后来动态映射加的，`value_count=23`（共 24 条），有一条没值。做精确计算时注意。

### 9200 单节点（有安全，`https://localhost:9200`）

| 索引 | 文档数 | 用途 |
|---|---|---|
| `news_ik` | 5 | **IK 中文分词**（`ik_max_word`） |
| `l8_orders` | 24 | RBAC 权限验证 |
| `l6_shop` / `l7_news` | 8 / 6 | 早期练习数据 |

已配置：`l13_readonly` 只读角色、`l13_reader` 用户（密码 `l13Readonly2026`）

### 客户端环境

- 仅 Node.js v22.14.0（Python 是 Store 存根，Java/Go/.NET 未装）
- `@elastic/elasticsearch@9.5.1` 已装在 `playground/l13-client/`
- 本课新增脚本：`04-benchmark.js`（分片基准）、`05-limits.js`（事务/关联）、`06-nrt.js`（近实时）、`07-syllabus.js`（考纲探测）

### 两个集群的已知限制

| 限制 | 表现 | 绕行方案 |
|---|---|---|
| license = **basic** | `semantic_text` 写入报 `non-compliant for [inference]` | 用 `dense_vector` + 手动算向量 |
| license = basic | 字段级/文档级安全不可用（需付费） | 只用索引级权限（够练 RBAC） |
| 未配远程集群 | 跨集群搜索不可用 | 该考点 9.3 已移除，不影响备考 |
| Streams 未启用 | `/_streams` 不可用 | 该考点需另建环境练 |

---

## 3.6 类比收束：消防车的最终答案

| 类比 | 对应 | 边界 |
|---|---|---|
| 水炮威力大 | 全文检索、相关性打分 | 但做不了精细的点查 |
| 自带水箱水泵 | 分布式、副本、自愈 | 换来的代价是资源开销大 |
| 油耗惊人 | 分片/段/内存的固定开销 | 搜索场景下这个交换是划算的 |
| 转弯半径大 | 无事务、无跨表关联 | 这是设计取舍，不是缺陷 |
| 不能当通勤车 | 不适合做交易主存储 | **但可以做可重建的分析副本** |

**最终一句话**：

> ES 是一辆 specialized 的消防车。
> 把它开去火场（搜索、日志、分析），它无可替代；
> 把它开去菜市场（事务、强一致、关系建模），你会又费油又难停车。
> **判断标准只有一个：这份数据丢了能不能重建？能，就大胆用 ES；不能，就别把 ES 当唯一数据源。**

---

## ✅ 本课小结

| 知识点 | 核心结论 |
|---|---|
| ① 选型决策清单 | ES 适合全文检索/聚合/时序/语义检索；不适合事务/强一致/关系模型。**ES 是索引副本，不是原始账本**。分片不是越多越好（实测：存储 4.7×、p95 2.2×、聚合误差 82） |
| ② 认证备考指南 | **2026-09-01 考纲升 9.3**：新增 Architecture / semantic search / ES\|QL / Security；移除 runtime fields / 跨集群 / searchable snapshot。3 小时纯实操、$500、开卷。本机可练绝大部分考点，只有 `semantic_text`（license）和 Streams 练不了 |
| ③ 知识体系收束 | 42 个知识点串成"认识→使用→生产→选型"一条主线；十个结论 + 四层排查法 + 本机环境清单 |

---

## 🎉 你已经学完全部课程

**5 个阶段 · 14 课 · 42 个知识点，全部完成。**

想继续深入，三个方向：

1. **考认证** —— 按知识点 2 的备考指南，用本机环境做 2–3 次限时模拟，重点补 Streams 和 `semantic_text`
2. **做项目** —— 找一个真实场景（给自己的博客加全文搜索、给项目日志搭 ELK），把 42 个知识点用一遍
3. **追新特性** —— ES 9.x 在 AI 检索方向迭代很快，`semantic_text`、Streams、ES|QL 都值得跟进

---

## 📚 参考来源

- [Elastic Certified Engineer Exam（官方）](https://www.elastic.co/training/elastic-certified-engineer-exam)
- [Elastic Certification FAQ（官方）](https://www.elastic.co/training/certification/faq)
- [Elastic 认证工程师考试换版本通知（中文解读）](https://www.modb.pro/db/2082303731979849728)
- [My path to Elastic Certified Engineer in 2026](https://biplabgautam.com.np/blog/elastic-certified-engineer-certification)
- [Inside Elastic Certifications（NetEye 博客）](https://www.neteye-blog.com/?p=60954/)
- [Elastic Certified Engineer（George Bridgeman）](https://georgebridgeman.com/posts/elastic-certified-engineer)

---

## 🚀 下一批接力提示词

> 课程已全部完结。若你想继续深化，可复制下面任一段发给 AI。

**方向 A · 备考冲刺**：

```
我已完成 Elasticsearch 全部课程（5 阶段 / 14 课 / 42 知识点），
学习档案在 elasticsearch/00-学习档案.md，最后一课是课 14《该不该用 ES》。

现在准备考 Elastic Certified Engineer（9.3 考纲，2026-09-01 起生效）。
请用我本机环境为我出一套限时模拟题，要求：
- 覆盖 9.3 六大类（Architecture / Data Management / Data Processing /
  Searching Data / Cluster Management / Security）
- 每题给出任务描述、验证命令、参考答案
- 标注哪些题本机可练、哪些需要另建环境

本机环境：
- 3 节点集群 http://localhost:9201（node-1/9201, node-2/9202, node-3/9203，
  cluster.name=l9-cluster，无安全，green）
  索引：l9_orders(24)、l9_hi(300)、l9_trap2(1287)、
  l10_shard_1/3/50(各 3000)、l11_shop_v2(3)、
  l13-logs-app(data stream)、l13_vector_demo(6, 字段 embedding, dims=3)、
  l13_rag_kb(5)
- 单节点集群 https://localhost:9200（密码 9PvhcGNNc86uFZb_ePAN，IK 9.5.1 已装）
  索引：l6_shop(8)、l7_news(6)、l8_orders(24)、l8_orders_v2(24)、
  l8_text_demo(24)、news_ik(5)
- 两集群 license 均 basic（semantic_text 写入报 non-compliant for [inference]）
- 仅 Node.js v22.14.0 可用，@elastic/elasticsearch@9.5.1 已在
  playground/l13-client/
- 9200 已有只读角色 l13_readonly、只读用户 l13_reader（密码 l13Readonly2026）
```

**方向 B · 实战项目**：

```
我已学完 Elasticsearch 全部课程（5 阶段 / 14 课 / 42 知识点），
学习档案在 elasticsearch/00-学习档案.md。

想做一个真实项目把知识用起来，请帮我规划一个端到端方案：
（可选题目：给个人博客加全文搜索 / 给应用日志搭 ELK /
 做一个带向量检索的文档问答系统）

要求：
- 明确 ES 在架构中的位置，且说明"数据源在哪、ES 挂了怎么重建"
  （我学过：ES 是索引副本，不是原始账本）
- 给出索引设计（mapping、分片数、别名、ILM）
- 给出同步方案与代码骨架（用 Node.js，本机只有 Node.js v22.14.0）
- 标出可能踩的坑

本机环境：
- 3 节点集群 http://localhost:9201（cluster.name=l9-cluster，无安全，green）
- 单节点集群 https://localhost:9200（密码 9PvhcGNNc86uFZb_ePAN，IK 9.5.1 已装）
- 两集群 license 均 basic
- 仅 Node.js v22.14.0，@elastic/elasticsearch@9.5.1 已装在
  playground/l13-client/
```

---

## 🧭 课程导航

| 上一课 | 本课 | 返回 |
|--------|------|------|
| [课13 三大主战场](lesson-13-三大主战场.md) | **课14 该不该用 ES**（全课收官） | [课程目录](../../02-课程目录.md) ｜ [学习档案](../../00-学习档案.md) ｜ [学习路径总览](../../01-学习路径总览.md) |
