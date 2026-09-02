# 阶段 3 · 数据模型与查询

> 所属课程：[InfluxDB 3 系统学习](../../02-课程目录.md) ｜ 水平：零基础 → 入门
> 本阶段：**4 课 / 12 知识点** ｜ 状态：✅ **已完成**（12 / 12 知识点，L6-L9 全部交付）

![阶段 3 路径图](assets/stage-03-path.svg)

## 🎬 本阶段在故事主线中的章节定位

| 章节 | 本阶段任务 | 主角的状态变化 |
|------|-----------|---------------|
| **第三章 · 学会设计** | schema 与 SQL 写对 | 能操作它 → **能用对它** |

**为什么现在学**：阶段 2 你已经能写能查，但"能跑"和"跑得好"是两回事。本阶段解决两个会长期影响成本与性能的决策：**tag 怎么设计**、**SQL 怎么写**。

## 🎯 阶段目标

学完本阶段，你应该能够：

1. 说清 table / tag / field / timestamp 四要素，以及 measurement 与 table 的关系
2. 理解基数（cardinality）的本质，设计出基数可控的 schema
3. 用 DataFusion SQL 写出时间分组聚合查询（重点是 `DATE_BIN`）
4. 读懂老代码的 InfluxQL 与 Flux，并知道怎么迁到 SQL

## 📚 必须掌握的知识点

### L6 · 数据模型：table、tag、field、timestamp ✅

| 知识点 | 关键点 |
|--------|--------|
| ① 四要素 | table（原 measurement）· tag set（仅字符串、进主键、字典编码）· field set（≥1、默认 float）· timestamp（纳秒 UTC、永不为空） |
| ② schema-on-write 与类型冲突 | 自动建库建表；**首次写入即定型**，列类型不可改；tag 列定义 immutable |
| ③ 命名限制与特殊字符 | 保留键三类后果不同；转义规则不对称；**大小写写入与查询两套规则** |

> 🎯 **本课最重要的一条**：**主键 = timestamp + tag set**，且 **null tag 不进主键** —— `host=`（空值）和"干脆不写 host"会**塌缩成同一行**。
>
> 🔢 **Core 硬限制（官方原文）**：**数据库 5 个** / **表 2000 个**（跨所有库）/ **每表 500 列**（1 个 time + 499）。→ 分库策略不能按实例、按天、按客户划分。
>
> 🚫 **保留键后果分三类**：`time` → 写入**被拒绝**（可作表名）；`_field` / `_measurement` → **整个点被静默丢弃**；`_` 开头 / `iox_` 前缀 → 系统保留，可能冲突。
>
> 💡 **本课的实操补充**：含一个**本机实跑验证过的命名自检脚本**（不依赖 Docker 即可运行，可接 CI），见[课件实验 E](lessons/lesson-06-数据模型-table-tag-field-timestamp.md)。

### L7 · Schema 设计与基数陷阱 ✅

| 知识点 | 关键点 |
|--------|--------|
| ① 基数（cardinality）本质 | series 数 ≈ 各 tag 取值数的**乘积**——这是会爆炸的乘法 |
| ② tag vs field 的抉择 | 过滤/分组用 tag，计算用 field；**放错维度是致命的** |
| ③ schema 设计反模式 | 高基数做 tag、把 ID 类字段当 tag、tag 值里塞变量 |

> 🔗 **回扣 L2 误区 4**：3.x 支持无限基数 ≠ 可以随便设计 tag。技术上存得下，不等于查得快、成本低。
>
> 🎯 **本课最重要的一条**：**基数是乘法不是加法**。加一个 tag，series 数乘以它的取值数；而**点数量不会因此变多** → **点密度（点/series）趋近 0，字典编码彻底失效**。场景对照：3,000 series / 点密度 1000（健康）vs **3 亿 series / 点密度 0.01**（危险），**点数完全相同**。
>
> 🔴 **推翻 1.x 老经验**：Core 官方 schema-design 页面**全文 0 次提及「索引」**（本机抓取核实）；Clustered 版明文 *"It doesn't index tag values or field values"*。→ **需要按某字段查询 ≠ 该字段必须是 tag**，ID 类（trace_id / user_id / UUID）**一票否决进 field**。
>
> 🔒 **一次性决策**：**首次写入决定物理列顺序，且不可更改**（官方原文）。建表时须按查询频率排 tag 顺序。
>
> 🚫 **基数类元查询很可能不被 3.x 支持**（官方原文）→ 用 SQL `COUNT(DISTINCT ...)` 自己数，别指望 `SHOW SERIES CARDINALITY`。
>
> 💡 **本课的实操补充**：含一个**本机实跑验证的基数估算器**（4 场景真实输出，不依赖 Docker，可接 CI），见[课件实验 A](lessons/lesson-07-Schema设计与基数陷阱.md)。

### L8 · SQL 查询：从 SELECT 到窗口函数 ✅

| 知识点 | 关键点 |
|--------|--------|
| ① DataFusion SQL 基础查询 | 标准 SQL + 时序扩展函数 |
| ② `DATE_BIN` 与时间分组 | 时序查询的核心：把连续时间切成桶 |
| ③ 聚合、窗口函数与 CTE | 同比环比、移动平均、累计值 |

> 🕐 **本课最重要的一条**：**UTC+8 用户按天分桶，默认 origin 会让「一天」从北京时间 08:00 开始**。`DATE_BIN(INTERVAL '1 day', time)` 的第三个参数 `origin_timestamp` 默认 Unix epoch（UTC 1970-01-01 00:00），对 UTC+8 就是**北京时间 08:00** → 凌晨与清晨的数据被算进前一天。**查询不报错、数字不缺失，只是每天的结果都错位 8 小时**。修法：显式 `TIMESTAMP '1970-01-01T16:00:00Z'`，或用 `date_bin_wallclock`。
>
> ⚠️ **`LAG` 是「前一行」不是「前一小时」**。数据规律时两者等价，**有缺失即分家**。要精确时间偏移（恰好 1 小时前）用官方给的自连接写法。
>
> 🕳️ **`date_bin` 不补桶，缺失时段整段消失**（不是显示 0，是没有行）。补桶要用 `date_bin_gapfill`，且**必须带时间上下界**；补值三选一：`interpolate`（插值）/ `locf`（沿用前值）/ `COALESCE(COUNT(...), 0)`（填 0）。
>
> 🚫 **3.x 没有 `increase()` / `NON_NEGATIVE_DIFFERENCE()`**（官方明文）。迁移时用 `GREATEST` + `LAG` + CTE 三段式——这正是 L9 迁移最常撞的墙。
>
> 💡 **本课的实操补充**：含一个**本机实跑验证的 `DATE_BIN` 分桶模拟器**（4 场景真实输出，不依赖 Docker，可接 CI），见[课件实验 A](lessons/lesson-08-SQL查询-从SELECT到窗口函数.md)。

### L9 · InfluxQL 与 Flux：遗产与迁移 ✅

| 知识点 | 关键点 |
|--------|--------|
| ① InfluxQL 兼容层 | 3.x 仍支持，老代码能跑 |
| ② Flux 为何被弃 | 学习曲线陡 + 高基数未根治 |
| ③ SQL 迁移对照表 | 常用 InfluxQL / Flux 写法 → SQL 对照 |

> 🔴 **本课最重要的一条（且修正了 L8）**：**「3.x 没有 `NON_NEGATIVE_DIFFERENCE()`」这句话严格限定在 SQL 语境**。官方 InfluxQL feature support 表里，`NON_NEGATIVE_DIFFERENCE()` 与 `NON_NEGATIVE_DERIVATIVE()` **都标 ✅ 受支持**（在 24 个全支持的变换函数内）。→ **SQL 没有 ≠ 3.x 没有**，换到 `/query` 端点即可用。**引用官方结论时必须带上语境限定词。**
>
> 🗣️ **语言格局**：**3.x 只有 SQL 与 InfluxQL 两种查询语言**。Core 官方 Query data 页**只列这两条路径，没有 Flux**。官方出路是 **Flux to SQL converter（beta，随 Explorer 1.9 发布）**——连转换器都做了，就是最明确的弃用信号。
>
> ⚠️ **迁移头号陷阱**：**带 `tz()` 的按天 InfluxQL 查询不能直译成 `DATE_BIN(INTERVAL '1 day', time)`**。InfluxQL 的 `tz('Asia/Shanghai')` 让"一天"按北京时间 00:00 切分，而 SQL 默认 origin 是 Unix epoch → "一天"从**北京时间 08:00** 开始，**静默错位 8 小时**。→ **迁移前先 grep 一遍 `tz(`。**
>
> 🚧 **InfluxQL 是「重建中」不是「完整移植」**（官方原文 *"rearchitected... ongoing"*）：❌ `SLIMIT`/`SOFFSET`、`SAMPLE()`、10 个技术分析函数、`SHOW DATABASES`/`SHOW SERIES`、**全部 4 个 CARDINALITY 类**。基数类官方明说 **"likely not supported"**，理由：*基数不再是性能瓶颈*（此为 L7 结论的官方铁证）。
>
> 🔌 **两个端点仅路径不同**：SQL → `/api/v3/query_sql`；InfluxQL → `/query`。三者参数（`db=`、`q=`、`Authorization: Token`）**完全一致** → **灰度迁移成本极低**。
>
> 💡 **本课的实操补充**：含一个**本机实跑验证的 InfluxQL↔SQL 语义对照模拟器**（4 场景真实输出），见[课件实验 A](lessons/lesson-09-InfluxQL与Flux-遗产与迁移.md)。

## 🧭 导航

⬅️ **上一阶段**：[阶段 2《上手篇》](../2-上手篇/overview.md)
➡️ **下一阶段**：[阶段 4《存储引擎与性能》](../4-存储引擎与性能/overview.md)
📚 **返回**：[课程目录](../../02-课程目录.md) ｜ [学习路径总览](../../01-学习路径总览.md)
