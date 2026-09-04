# 阶段 3 · 指标与日志

> **故事章节**：「补齐拼图」——主角获得"量化"与"叙事"的能力。指标告诉你系统**发生了什么**，日志告诉你系统**说了什么**，而两者都得挂回同一把钥匙。

[← 返回课程目录](../../02-课程目录.md)

---

## 一、阶段目标

学完本阶段你应该能够：

1. **选出**合适的 Instrument 类型（六种里选哪个不是任意的），并为服务设计一套指标方案
2. **打通**日志与链路：让日志自动带上 `trace_id`，能从一条日志跳回它所属的那次请求
3. **避开**语义约定的坑——尤其是 HTTP 属性大批弃用这件事，以及 Cardinality 爆炸这个成本杀手

---

## 二、本阶段在故事主线中的位置

| 叙事要素 | 内容 |
|----------|------|
| **承接** | 阶段 2 已把链路讲透，`trace_id` 这把钥匙在手 |
| **转折** | 可另外两个信号呢？指标怎么挂上这把钥匙？日志怎么自动关联过来？ |
| **冲突升级** | 当你真正开始用，会发现两个拦路虎：① 属性命名版本混乱（`http.method` 已弃用）② 一个不当心的属性就能让成本翻十倍 |
| **阶段出口** | 三信号互通，且你知道命名与 Cardinality 这两条底线在哪 |

---

## 三、必须掌握的知识点

### 课 7：指标模型与六种 Instruments

| # | 知识点 | 关键点 | 状态 |
|---|--------|--------|------|
| 6.1 | 指标模型：Instruments 全家桶 | OTel 指标模型分层（Instrument → Stream → Point）/ 与 Prometheus 模型的差异 / push 与 pull | ✅ |
| 6.2 | 六种 Instruments 与聚合视角 | Counter / UpDownCounter / Gauge / Histogram / 以及两类 Observable（异步）版本 / 怎么选 | ✅ |
| 6.3 | Exponential Histogram：P99 精度问题 | 传统 Histogram 的 bucket 困境 / 指数桶如何动态适配 / 与 Prometheus Native Histogram 的殊途同归 | ✅ |
| 6.4 | Exemplar：从指标跳回链路 | Exemplar 是什么 / 它如何携带 `trace_id` / 从 P99 尖刺直接跳到具体某次请求 | ✅ |

### 课 8：日志桥接与信号关联

| # | 知识点 | 关键点 | 状态 |
|---|--------|--------|------|
| 7.1 | 日志桥接 API：不替换你的日志库 | Bridge API 的定位 / 为什么它"不该被终端用户直接调用" / 与既有 logging 框架的关系 | ✅ |
| 7.2 | 日志关联：`trace_id` 自动注入 | 关联原理 / 注入后的日志长什么样 / 从日志反查链路、从链路下钻日志 | ✅ |
| 7.3 | 日志采集的两条路径 | 路径 A：应用直发 OTLP / 路径 B：采集器读文件（Fluent Bit / filelog receiver）/ 各自的适用场景 | ✅ |

### 课 9：语义约定：命名的战争

| # | 知识点 | 关键点 | 状态 |
|---|--------|--------|------|
| 8.1 | 语义约定是什么：可观测性的通用词汇表 | 为什么需要它 / 覆盖哪些域 / 它带来的真正价值（跨团队看板可直接复用） | ✅ |
| 8.2 | HTTP 属性的弃用与迁移 | `http.method`→`http.request.method` / `http.status_code`→`http.response.status_code` / `http.url`→`url.full` / `http.target`→`url.path`+`url.query` / 数据库属性同样在变 / 迁移策略 | ✅ |
| 8.3 | 稳定性等级：Stable / Beta / Alpha 怎么读 | 五级生命周期（Draft / Experimental / Stable / Deprecated / Removed）/ **规范稳定 ≠ SDK 稳定** / 生产该用哪一级 | ✅ |
| 8.4 | 自定义属性与 Cardinality 爆炸 | 什么是 Cardinality / 一个用户 ID 字段如何毁掉指标 / 高基数字段该放哪儿（属性 vs 日志） | ✅ |

**合计**：11 个知识点

---

## 四、认知阶梯

| 层 | 覆盖知识点 |
|----|-----------|
| **感知层** | 6.1 指标模型（先看清它和 Prometheus 的模型差异） |
| **概念层** | 6.2 六种 Instruments、7.1 日志桥接、8.1 语义约定 |
| **机制层** | 6.3 Exponential Histogram、6.4 Exemplar、7.2 关联原理、8.3 稳定性等级 |
| **实操层** | 7.3 采集两条路径、8.2 属性迁移 |
| **定位层** | 8.4 Cardinality（成本意识的起点） |

---

## 五、本阶段的高频困惑点（预判）

> 学习时若遇到以下问题属正常，课内会正面回应：

1. **"六种 Instrument 我该用哪个？"** → 判据只有两条：值**只增还是可增可减**（Counter vs UpDownCounter）、**同步采集还是异步回调**（普通 vs Observable）
2. **"我照着老教程写的 `http.method` 为什么告警说弃用了？"** → 因为确实弃用了。新名是 `http.request.method`，本阶段课 9 会给完整迁移对照表
3. **"Exponential Histogram 和 Prometheus histogram 冲突吗？"** → 不冲突，是同一结论的两种实现；Collector 可做转换
4. **"指标里加个 user_id 方便排障，有什么问题吗？"** → ⚠️ 大问题。一万个用户就是一万个时间序列，成本与后端压力会失控。高基数字段应放进**日志或链路属性**，不是指标标签

---

## 六、阶段状态

| 项 | 值 |
|---|---|
| 状态 | ✅ **已完成**（课 7、课 8、课 9 全部完成，11 / 11） |
| 已完成知识点 | **11 / 11** |
| 开始日期 | 2026-09-03 |
| 完成日期 | **2026-09-03** |

**课 7 核心结论（2026-09-03）**：

1. **指标永不采样，exemplar 跟着采样走** —— 10000 次请求、trace 采样率 0.1% 实测：被采样 span 仅 11 条，而 Histogram 的 `count` 仍是 10000（全量）。这回答了课 6 埋下的伏笔，并把「采样率怎么定」转化为「要多少条可跳转链接」的问题。
2. **P99 精度：显式桶最坏 −50.0%，指数桶最坏 −2.2%** —— 5 场景 × 10000 样本真实 SDK 聚合。E 场景（极端长尾）显式桶把 20s 砍成 10s，且方向是**低估**，监控上看起来还行，最危险。
3. **六种 Instrument 与 Prometheus 类型不是一一对应** —— `UpDownCounter` 出口是 `gauge` 而非 `counter`；加不加 `_total` 取决于「能否减少」而非「是否异步」；Histogram 一个变 **18 条**序列，与指数桶成本比 **18:1**。
4. **选择判据只有两条** —— 值只增还是可增可减、同步还是异步回调（阶段高频困惑点第 1 条已正面回应）。

**课 8 核心结论（2026-09-03）**：

1. **采样切不断日志关联，只切得断 exemplar** —— `always_off`（0% 采样）实测：200 条日志**仍 100% 带 trace_id**，而 exemplar 归零。判据不同：日志关联看"span context 是否有效"，exemplar 看"SAMPLED 位"。
2. **Python Logs SDK 仍是 Development** —— `import opentelemetry.sdk.logs` 报 `ModuleNotFoundError`，只有私有的 `sdk._logs`；而 `metrics` / `trace` 都是公开包。规范层 Stable ≠ 实现层 Stable。
3. **Collector 收到 ≠ 后端收到** —— Jaeger 对 `/v1/logs` 返回 **404 Unimplemented**（实测 `n_spans=1 / n_logs=0`），数据在 Collector 之后被静默丢弃，应用侧全程无感知。这是本课程第六个静默失败。
4. **Bridge API 是转接头不是新插座** —— 业务代码 `logger.info()` 一行不改，多挂一个 `LoggingHandler` 即可；原文件 handler 全部保留，双写是推荐做法。

**课 9 核心结论（2026-09-03）**：

1. **骨架的「五级生命周期」是过时说法，官方现为七级，且 `stability` 字段只有五个取值** —— 核对规范原文 `maturity-levels.md` 与 `versioning-and-stability.md`：现行为 Development / Alpha / Beta / **Release Candidate** / Stable / Deprecated / Unmaintained 七级，`Experimental` 已于 2023 年更名 `Development`（原文第 90 行），`Removed` 不是等级、对应的是 `Unmaintained`。扫描官方 `model/` 全目录 2772 处 `stability:` 字段，实际取值只有五个：**development 2262 / stable 260 / release_candidate 231 / experimental 14 / alpha 5**——**没有 beta 取值，且 `deprecated` 是独立字段不是等级**（弃用属性的 stability 被重置为 development）。三个可操作结论：stable 仅占 9.4% 是稀缺资源；RC（231 处）是被普遍忽略的"准稳定"级；development 占 81.6%，多数属性仍可变更。
2. **弃用 ≠ 不能用，且完全静默** —— Flask 插桩 5 档实测：default 档出 **13 个属性、11 个是旧名**（数据完全正常）；`http` 档出 **10 个全新名**；`http/dup` 档出 **22 个（13 旧 + 9 新）**；**`database` 档对 HTTP 属性毫无影响**（证明开关分域独立）。弃用属性不打任何 warning，只有在升级插桩库后发现看板数据少一半时才暴露——这是静默失败在命名层的形态，也是本课程第七个静默失败。
3. **Cardinality 是乘法，倍数恒等于加进去的维度基数** —— 真实 SDK 聚合实测：5 路由 × 3 状态码 = **15 条**序列，加 10000 个 `user.id` 后 = **150,000 条**，**放大 10,000 倍**（正好等于加进去的维度基数）。5 维推演：15 → 150,000 → 600,000 → **1.2 亿**。根因：指标每个序列**常驻内存**且只要还在上报就永不释放，而日志/Span 是按条存储、查完可删。**判据：能列进一张表的字段才能放进指标标签**（`http.route` 能，`url.path` 不能）。
4. **规范稳定 ≠ SDK 稳定 ≠ 插桩稳定（本课第三次回应）** —— 本机 `opentelemetry-semantic-conventions 0.65b0`（**版本号里的 b0 = beta**），对应 schema **1.43.0**，而官方 main 分支 CHANGELOG 已到 **v1.44.0**——**规范稳定了，装规范的盒子还在 beta，且落后一个版本**。三次回应的完整链条：课 7 的 Python 第 7 个 `create_gauge` → 课 8 的 Python Logs SDK 仍 Development → 本课的 semconv 包仍是 beta。

---

## 七、与其他阶段的关联

- **前置依赖**：阶段 2 课 4（`trace_id` 与上下文传播是 6.4 Exemplar、7.2 日志关联的共同前提）
- **后续依赖**：阶段 4 课 10 的 Processor 是 8.2 属性迁移的**最佳落地处**（可以在 Collector 层统一改写旧属性名，不必改应用代码）；课 11 的成本治理直接承接 8.4
- **与既有课程对照**：`promql/` 课程的四种指标类型可与此处的六种 Instruments 对照理解；`influxdb/` 与 `victoriametrics/` 是 OTel 指标的候选后端

---

## 课程导航

- 上一阶段：[阶段 2 · 一次请求的完整旅程](../2-一次请求的完整旅程/overview.md)
- 阶段概览：[阶段 3](./overview.md)
- 下一阶段：[阶段 4 · 生产落地](../4-生产落地/overview.md)
- [← 返回课程目录](../../02-课程目录.md)
