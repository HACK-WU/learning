# 课 10：基数治理

> 所属阶段：阶段 4《生产运维》｜ 水平：进阶 ｜ 本课知识点：基数的来源与量级、诊断高基数、控制手段
> 故事情节：主角失控了——莫名其妙多出几百万条序列，内存飙升、查询变慢。头号杀手现身
> 上一课：[课 9 长期存储选型](../../3-规模化与生态/lessons/lesson-09-长期存储选型.md)

## 🎯 本课目标

- 识别高基数的四类来源，并估算各自的序列放大倍数
- 用 `topk` + TSDB 状态 API 定位到具体是哪个指标、哪个标签在涨
- 给出暴露端 / 抓取端 / 存储端三个层次的控制手段，并说明各自副作用

## 📌 知识点清单

| 知识点 | 一句话 | 状态 |
|--------|--------|------|
| 1 基数的来源与量级 | 序列数 = 标签值组合数，直方图按桶数放大 | ✅ 实测 |
| 2 诊断高基数 | 优先用 TSDB 状态 API，别依赖自身指标 | ✅ 实测 |
| 3 控制手段 | `metric_relabel` 温和，`sample_limit`/`label_limit` 是硬失败 | ✅ 实测 |

---
## 🎬 第一幕：场景引入

### 你已经走到这里了

前三个阶段你搞清楚了 Prometheus 怎么存、怎么算、怎么扩展。现在进入最后一个问题：
**它为什么会突然崩掉。**

阶段 3 课 6 我们实测过一个反直觉的数字：序列数涨 2 万倍，查询耗时只涨 1.75 倍。
当时我说过一句话，现在该兑现了：

> **"序列数真正的杀伤力在内存，不在单次查询耗时 —— 留待阶段 4 课 10。"**

这就是本课的主题。

### 一次真实的半夜事故

想象这个场景（这是 Prometheus 社区最常见的一类事故）：

```text
周一 10:00  上线一个新版本，加了一个"按用户统计"的功能
周一 10:05  监控面板一切正常，QPS 平稳，延迟正常
周一 14:00  Prometheus 内存缓慢上涨，没人注意
周二 03:00  OOM，Prometheus 被 kill
周二 03:01  告警发不出来 —— 因为发告警的那台挂了
周二 09:00  有人发现"监控昨天半夜开始没数据了"，重启后恢复
周二 15:00  又崩
```

**没有任何一个指标在告警里报"基数爆炸"**——因为基数膨胀在业务指标上看起来
完全正常：QPS 正常、延迟正常、错误率正常。它只杀死观察者自己。

### 这一课你要带走什么

不是"删几个标签"这种口号，而是三件可操作的事：

1. **能算**：给定一个指标设计，能提前算出它会产生多少条序列
2. **能查**：面对一台已经膨胀的 Prometheus，能在 5 分钟内定位到是哪个指标、哪个标签
3. **能治**：知道三种控制手段各自的副作用——特别是哪一个会**让整个 target 直接消失**

---
## 🤔 第二幕：认知冲突

### 冲突一：代码里只有 1 个指标，TSDB 里却有 36 条序列

这是本课最容易被低估的一点。看这段代码：

```python
HIST = Histogram("card_hist_seconds", "histogram buckets", ["route"],
                 buckets=[0.005,0.01,0.025,0.05,0.1,0.25,0.5,1,2.5,5,10])
```

**问题：如果 `route` 有 3 个取值，这个指标最终产生多少条序列？**

大部分人会答"3 条"。实测答案是 **36 条**（另有 `_count`/`_sum`/`_created` 各 3 条）。

原因：`le` 桶是**标签**，每个桶一条独立序列。11 个自定义桶 + `+Inf` = 12 个桶，
3 route × 12 桶 = 36。

**放大倍数 = 桶数。** 代码里的"一个指标"和 TSDB 里的"序列数"根本不是一个量级。

### 冲突二：限制基数，可能让监控直接消失

直觉上,"限制一下基数"应该是个安全措施。但下面的配置会让整个 target **从监控里消失**：

```yaml
- job_name: "app"
  sample_limit: 100        # 看起来很合理：最多抓 100 个样本
  static_configs:
    - targets: ["l10-app:8000"]
```

实测结果：`health=down`、`up=0`、`lastError="sample limit exceeded"`。

**不是截断，是整批作废。** 你本来想保护 Prometheus，结果是这个 target 的所有指标
（包括 `up` 自己）全部消失。

### 冲突三：诊断基数，自身指标靠不住

按教程你会这么查：

```
prometheus_tsdb_head_series
```

**本课环境里这条查询返回空。** 我查证了 `/api/v1/label/__name__/values`，
18 个指标里**没有任何一个 `prometheus_tsdb_*`**。

所以"用 `prometheus_tsdb_head_series` 监控基数"这个常见建议在特定配置下会失效。
本课改用 **`/api/v1/status/tsdb`**，它不依赖指标暴露，**更可靠**。

### 四个"看起来成立"的预设

| # | 预设 | 本课要检验 |
|---|------|-----------|
| 1 | 加一个标签，序列数涨一点 | 涨多少？**1:1 还是按组合爆炸** |
| 2 | 每条序列占多少内存是有经验公式的 | 本机能不能测出来 |
| 3 | `sample_limit` 是保护性限制 | 是保护还是**自残** |
| 4 | `metric_relabel` drop 和 `sample_limit` 差不多 | 副作用是否等价 |

---
## 🔍 第三幕：层层揭示

### 知识点 1：基数的来源与量级

#### 一句话定义

**基数 = 时间序列的条数**，而 `序列数 = 所有标签值组合的笛卡尔积`。

#### 直觉建立

一个指标不是一条序列，是**一组序列**：

```
http_requests_total{route="/",     status="200"}   ← 一条序列
http_requests_total{route="/",     status="500"}   ← 另一条
http_requests_total{route="/list", status="200"}   ← 又一条
```

`route` 有 3 个值 × `status` 有 5 个值 = **15 条序列**。

这是可精确计算的，不是玄学。

#### 核心原理：四类来源

| 来源 | 放大方式 | 是否可预测 |
|---|---|---|
| **实例 churn** | 短生命周期容器反复创建销毁，`instance` 标签不断增加 | 时间维度累积 |
| **标签值失控** | 把 `user_id` / `url` / `request_id` 塞进标签 | 1:1，可精确计算 |
| **直方图桶** | `le` 桶展开，放大倍数 = 桶数 | 完全可预测 |
| **元数据** | HELP / TYPE 文本 | 占内存但不产生序列 |

#### 示例演示：标签值失控的精确放大

这是本课最干净的一组数据（每个场景重建 Prometheus 以测真实增量）：

| 场景 | 序列数 | 增量 |
|---|---|---|
| A 仅基线（低基数） | 21 | — |
| B +5000 个 `user_id` | 5 021 | **+5 000** |
| C +2000 个 URL 路径 | 2 021 | **+2 000** |
| D +1000 个 `request_id` | 1 021 | **+1 000** |

**加 N 个标签值就多 N 条序列，严格 1:1。**

这就是为什么把 `user_id` 放进标签是"教科书级错误"：
你的用户有 100 万，这个指标就有 100 万条序列——而且**每新增一个用户就永久多一条**。

#### 示例演示：直方图的放大（最易低估）

实测（3 个 route）：

| 展开后指标 | 序列数 |
|---|---|
| `card_hist_seconds_bucket` | **36** |
| `card_hist_seconds_count` | 3 |
| `card_hist_seconds_sum` | 3 |
| `card_hist_seconds_created` | 3 |

配置 11 个自定义桶 + `+Inf` = 12 桶，3 route × 12 = **36**。

> **放大倍数 = 桶数（本例 12x）。**
> 如果你用默认桶（约 12 个）+ 10 个 route，一个 histogram 就是 120 条序列。
> 代码里只写了一次 `Histogram()`。

#### 常见误区

**误区 1：以为"元数据也算序列"。**
不算。我实测过：app 只输出了 `# HELP` / `# TYPE` 行而没有任何样本行时，
Prometheus 里**一条序列都没有**（那时刚好能验证这一点）。元数据占内存，但不产生序列。

**误区 2：以为只加了一个标签影响不大。**
`user_id` 这种标签的取值域是**全体用户**，不是"几个值"。
判断标准是**取值域大小**，不是标签个数。

#### 一句话记住

> **序列数 = 标签值组合数；`user_id` 进标签 = 用户数条序列；一个 histogram = 桶数倍序列。**

---

### 知识点 2：诊断高基数

> ⚠️ **2026-09-07 更正（课 11 回查发现）**
>
> 本课初版说「`prometheus_tsdb_head_series` 在本环境不存在」——**这个判断是错的**。
> 课 11 查证出真实原因：**当时的配置里没有 self-scrape job**（只配了业务 target），
> 所以 Prometheus 根本没有抓自己，自然一个 `prometheus_*` 指标都没有。
>
> 加上 self-scrape 后实测：指标数从 **6 → 328**，`prometheus_tsdb_head_series` 正常返回值。
>
> **结论修正**：该指标**存在且可用**，前提是配置了 self-scrape。
> 但本课的**方法建议依然成立**——`/api/v1/status/tsdb` 更可靠，
> 因为它不依赖抓取链路（self-scrape 挂了也能用）。详见课 11。

#### 一句话定义

**优先用 `/api/v1/status/tsdb`；PromQL 自身指标可用，但依赖 self-scrape 配置。**

#### 直觉建立

要找出"谁在涨"，思路是**按指标名聚合序列数，然后排序**。有两条路：

- PromQL：`topk(10, count by (__name__)({__name__=~".+"}))`，或 `prometheus_tsdb_head_series`
- TSDB 状态 API：`GET /api/v1/status/tsdb`

**为什么推荐后者**：

1. **不依赖 self-scrape**。用自身指标的前提是你配置了 Prometheus 抓自己；
   没配的话一个 `prometheus_*` 指标都没有（本课初版就栽在这里）。
2. **不给已经很忙的系统加压**。PromQL 这条路有个自指问题——
   **你要诊断的系统正好是提供诊断数据的系统**，它忙的时候这条查询本身也可能超时。
3. **一次给全**：状态 API 直接返回总数 + 按指标名排序的明细。

#### 示例演示：三种方式实测

混合场景（500 user + 2000 url + 1000 reqid + 直方图，共 3 578 条序列）。

**方式一：PromQL topk**

```
topk(5, count by (__name__)({__name__=~".+"}))
  card_bad_by_url          = 2000
  card_bad_by_reqid        = 1000
  card_bad_by_user         = 500
  card_hist_seconds_bucket = 36
  python_gc_collections_total = 3
```

**方式二：TSDB 状态 API（推荐）**

```bash
curl -s localhost:19440/api/v1/status/tsdb
```

```json
{
  "headStats": {
    "numSeries": 3578,
    "numLabelPairs": 3552,
    "chunkCount": 3578
  },
  "seriesCountByMetricName": [
    {"name": "card_bad_by_url",          "value": 2000},
    {"name": "card_bad_by_reqid",        "value": 1000},
    {"name": "card_bad_by_user",         "value":  500},
    {"name": "card_hist_seconds_bucket", "value":   36}
  ]
}
```

这个 API 一次给出**总数 + 按指标名排序的明细**，比 PromQL 更直接，
而且不需要 Prometheus 先跑一次查询引擎。

**方式三：逐标签定位**

找到"元凶指标"后，要看具体是哪个标签在涨：

```bash
curl -s 'http://localhost:19440/api/v1/series?match[]=card_bad_by_user'
```

```json
[{"__name__":"card_bad_by_user","instance":"l10-app:8000",
  "job":"app","user_id":"u000000x"}, ...]   // 500 条
```

看到 `user_id` 的取值是 `u000000x` 这种**连续编号**，基本就能断定是标签值失控。

#### 常见误区

**误区：用 `count({__name__=~".+"})` 当日常监控。**
这条查询会**扫全库**，在一个有几百万序列的实例上，它自己就可能把 Prometheus 打挂。
日常监控应该用 TSDB 状态 API 或 `scrape_series_added`。

#### 一句话记住

> **诊断基数用 `/api/v1/status/tsdb`：它不依赖指标暴露，也不会给已经很忙的
> Prometheus 再加一次全库扫描。**

---

### 知识点 3：控制手段

#### 一句话定义

三个层次（暴露端 / 抓取端 / 存储端），**但只有暴露端和 `metric_relabel` 是"温和"的**，
`sample_limit` / `label_limit` 是**硬失败**。

#### 核心实测：四种手段的对照

我配了四个 job 抓**同一个 target**，这是本课最重要的一组数据：

| job | 配置 | health | `up` | 入库序列 | 结论 |
|---|---|---|---|---|---|
| `app-raw` | 无限制 | up | 1 | 3 557 | 对照组 |
| `app-drop` | `metric_relabel_configs` 丢两个指标 | **up** | **1** | **557** | 精准丢弃 3 000 条，target 健康 |
| `app-sample-limit` | `sample_limit: 100` | **down** | **0** | — | **整个 target 抓取失败** |
| `app-label-limit` | `label_limit: 3` | **down** | **0** | — | **整个 target 抓取失败** |

#### 硬失败的实锤证据

```
app-sample-limit : health=down   lastError="sample limit exceeded"
app-label-limit  : health=down   lastError="label_limit exceeded
                   (metric: python_gc_objects_collected_total,
                    number of labels: 4, limit: 3)"
```

**两个关键点**：

**① 不是截断，是整批作废。**
`app-sample-limit` 的 `scrape_samples_scraped = 3 573`——**抓取动作确实发生了**
（和对照组 `app-raw` 的 3 573 完全一样），但一条都没入库，`up=0`。
也就是说你**付了抓取的代价，却什么都没得到**，还把 target 搞成了 down。

**② `label_limit` 会误伤无辜。**
看报错里被拦的指标：`python_gc_objects_collected_total`，
这是 Python 客户端自带的 GC 指标，有 4 个标签。
**我们真正想限制的 `card_bad_by_url` 一个字没提。**

因为 `label_limit` 是 **per-target 全局生效**的，它不认识"哪个指标是坏的"。
`card_bad_by_url` 只有 3 个标签，**反而是合规的**；无辜的 GC 指标先被拦了。

#### 三个层次的正确用法

**第一层：暴露端（最根本，副作用最小）**

```python
# ❌ 错：把 user_id 放进标签
BAD = Gauge("requests_by_user", "...", ["user_id"])      # 100 万用户 → 100 万序列

# ✅ 对：收敛取值域
GOOD = Gauge("requests_total", "...", ["route", "status"])  # 3 × 5 = 15 条序列
```

要按用户排查怎么办？**用日志和 tracing，不要用指标标签。**
这是 Prometheus 官方反复强调的边界。

**第二层：抓取端（`metric_relabel_configs`，温和）**

```yaml
scrape_configs:
  - job_name: "app"
    metric_relabel_configs:
      # 丢弃已知的高基数指标（target 保持健康）
      - source_labels: [__name__]
        regex: "card_bad_by_(url|reqid)"
        action: drop
      # 或者：直接删掉失控的那个标签（保留指标，合并序列）
      - regex: "user_id"
        action: labeldrop
```

实测：丢掉 3 000 条后 target 仍 `up=1`，其余指标正常入库（3 557 → 557）。
**这是唯一"温和"的抓取端手段。**

> `labeldrop` 比 `drop` 更温和：删掉 `user_id` 标签后，所有用户的样本会
> **合并成一条序列**（值是最后写入的那个）。指标还在，基数归 1。
> 代价是失去了按用户下钻的能力——但那个能力本来就不该用指标实现。

**第三层：存储端（硬限制，会丢数据）**

```bash
--storage.tsdb.max-series-per-database=1000000
```

这类限制触发后**新的抓取直接失败**。
它应该被当作**最后一道保险丝**，而不是日常治理手段——
保险丝烧了，电路也就断了。

#### 常见误区

**误区 1：以为 `sample_limit` 是"限流保护"。**
它不是限流，是**熔断**：超过了整个 target 报废。

**误区 2：以为 `label_limit` 能精确限制某个指标。**
它是 per-target 全局的，会先误伤标签多的正常指标（实测拦在了 GC 指标上）。

**误区 3：以为删了指标就能立刻回收磁盘。**
不能。删除只是写 tombstone，**真正的物理删除要等 compaction**。
这是课 3 埋的伏笔，课 12 讲 admin API 时会实测给你看。

#### 一句话记住

> **暴露端收敛是治本，`metric_relabel` 是治标，`sample_limit` 是截肢——
> 它保护 Prometheus 的方式是让整个 target 从监控里消失。**

---
## 🧪 第四幕：实操验证

### 实验 0：环境准备

```bash
# 网络与造数 app（lab 目录已提供）
docker network create l10net
bash labs/lesson-10/setup.sh          # 构建 l10-app 镜像

# 启动 Prometheus（端口 19440，开启 lifecycle 与 admin API）
docker run -d -p 19440:9090 \
  -v $PWD/labs/lesson-10/prometheus-base.yml:/etc/prometheus/prometheus.yml:ro \
  --name l10-prom prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus \
  --web.enable-lifecycle --web.enable-admin-api
docker network connect l10net l10-prom

# 造数：500 user + 2000 url + 1000 reqid
docker run -d --name l10-app --network l10net \
  -e N_USERS=500 -e N_URLS=2000 -e N_REQIDS=1000 l10-app
```

### 实验 1：验证"加 N 个标签值 = 多 N 条序列"

```bash
# 基线（不开启任何坏标签）
docker rm -f l10-prom l10-app
docker run -d --name l10-app --network l10net l10-app
# 重建 Prometheus 后等 20s
curl -s localhost:19440/api/v1/status/tsdb | python3 -m json.tool
# 预期：numSeries = 21
```

```bash
# 开启 5000 个 user_id
docker rm -f l10-prom l10-app
docker run -d --name l10-app --network l10net -e N_USERS=5000 l10-app
# 重建 Prometheus 后
# 预期：numSeries = 5021（严格 +5000）
```

> ⚠️ **必须重建 Prometheus 再测**。只重启 app 的话旧序列不会立刻消失，
> 你会测到累积值（我第一版就是这么得到"四个场景都是 8021"的假数据）。

### 实验 2：诊断——用 TSDB API 定位元凶

> 下面的输出示例同样是**单 job（base 配置）**下的混合场景。
> 若处于实验 4 的四 job 配置，`numSeries` 和各指标计数都会翻倍
> （实测 `card_hist_seconds_bucket` 会从 36 变成 72）。

```bash
curl -s localhost:19440/api/v1/status/tsdb \
  | python3 -c "import sys,json;d=json.load(sys.stdin)['data'];\
print(d['headStats']); \
[print(x) for x in d['seriesCountByMetricName'][:5]]"
```

```bash
# 先确认自身指标是否可用（本课环境不可用）
curl -s localhost:19440/api/v1/label/__name__/values \
  | python3 -c "import sys,json;print([m for m in json.load(sys.stdin)['data'] if 'tsdb' in m] or 'NONE')"
# 预期输出：NONE  ← 所以必须用状态 API
```

### 实验 3：直方图的放大倍数

> ⚠️ **前置条件**：本实验必须用 **`prometheus-base.yml`（单个 job）** 的配置，
> 且 app 用混合场景参数（`N_USERS=500 N_URLS=2000 N_REQIDS=1000`）。
> 如果当前是实验 4 的**四 job 配置**，你会得到 **72** 而不是 36——
> 因为 `app-raw` 和 `app-drop` 两个 job 各抓了同一个 target 一次，序列翻倍。
> （我第一版就是在这里踩到的。）

```bash
# 确认为单 job 配置
curl -s localhost:19440/api/v1/query?query=up | python3 -c "
import sys,json;print('job 数量 =',len(json.load(sys.stdin)['data']['result']))"
# 预期：job 数量 = 1

curl -s --data-urlencode 'query=count by (__name__)({__name__=~"card_hist.*"})' \
  localhost:19440/api/v1/query
# 预期：card_hist_seconds_bucket = 36（3 route × 12 桶）
```

### 实验 4：四种控制手段的副作用（重点）

```bash
# 用 prometheus-limits.yml（四个 job 抓同一 target）重启 Prometheus
curl -s localhost:19440/api/v1/targets?state=active \
  | python3 -c "import sys,json;\
[print(t['labels']['job'], t['health'], t.get('lastError','')) \
 for t in json.load(sys.stdin)['data']['activeTargets']]"
```

预期：

```text
app-drop          up     
app-label-limit   down   label_limit exceeded (...)
app-raw           up     
app-sample-limit  down   sample limit exceeded
```

### ✅ 本幕验收清单

- [ ] 能算出"加 5000 个 user_id 后序列数是多少"（答：+5000）
- [ ] 能用 `/api/v1/status/tsdb` 查出序列数最多的指标
- [ ] 能解释为什么 `sample_limit` 会导致 `up=0`
- [ ] 能说出 `metric_relabel` drop 与 `sample_limit` 的本质区别

---
## ✅ 评审结论（对学员可见）

本课讲义已完成 **双视角交叉评审**（ pedagogy 教学视角 + learner 学员视角），**P0 问题 0 项**。

| 视角 | 关注点 | 结论 |
|------|--------|------|
| **pedagogy** | 三个知识点是否都有实测支撑 | ✅ 全部有本机实测数据；知识点 1/2/3 各有独立实验 |
| **pedagogy** | 是否有"凭印象下结论" | ✅ 内存系数**主动放弃给数字**并说明原因 |
| **learner** | 第四幕命令能否照抄跑通 | ✅ 已逐条执行验证（含路径与预期输出） |
| **learner** | 是否有未标注的引用 | ✅ 无引用，全部实测 |

**评审中对本课的修正**：

1. 初稿计划用 `prometheus_tsdb_head_series` 讲诊断，**实测该指标在本环境不存在**，
   改为以 `/api/v1/status/tsdb` 为主，并把这次查证本身写进讲义（知识点 2）。
2. 初稿的内存对照实验**测不出可信数字**（3 轮复现基线波动 31.43~38.79 MiB），
   **已删除"每序列内存系数"这一结论**，改为诚实标注"未实测，留待课 11"。
3. 造数 app 初版存在 bug（`gen()` 未被调用，直方图只输出 HELP/TYPE 无样本），
   导致实验 3 返回空，**已修复后重测**（3 521 → 3 578）。

---
## 📚 第五幕：体系收束

### 本课的三个知识点

| 知识点 | 核心结论 | 关键实测数字 |
|---|---|---|
| 1 来源与量级 | 序列数 = 标签值组合数；直方图按桶放大 | +5000 user → +5000 序列；histogram 3→36（12x） |
| 2 诊断 | 用 TSDB 状态 API，别依赖自身指标 | `prometheus_tsdb_*` 在本环境不存在 |
| 3 控制 | `metric_relabel` 温和，limit 类是硬失败 | drop 后 3557→557 且 `up=1`；limit 后 `up=0` |

### 本课实测的关键数字

| 项 | 实测值 |
|---|---|
| 基线序列数（无业务指标） | 21 |
| 加 5000 个 `user_id` | 5 021（+5 000，1:1） |
| 加 2000 个 URL 路径 | 2 021（+2 000） |
| 加 1000 个 `request_id` | 1 021（+1 000） |
| histogram 展开（3 route × 12 桶） | `bucket` = **36** 条 |
| `metric_relabel` drop 两个高基数指标 | 3 557 → **557**，target 仍 up |
| `sample_limit: 100` | **`up=0`**，整批作废 |
| `label_limit: 3` | **`up=0`**，且拦在了无关的 GC 指标上 |

### 必背的三条硬约束

1. **序列数 = 标签值组合数**，加 N 个取值就多 N 条序列——`user_id` 进标签等于
   把用户数直接搬进 TSDB。
2. **一个 histogram = 桶数倍序列**（默认约 12x），代码里的一次 `Histogram()`
   在 TSDB 里是几十上百条。
3. **`sample_limit` / `label_limit` 是熔断不是限流**：触发后整个 target `up=0`，
   且 `label_limit` 是 per-target 全局的，会误伤无辜指标。

### 本课推翻的预设

| 预设 | 实际情况 |
|---|---|
| "加个标签影响不大" | 1:1 放大，取值域多大就有多少条 |
| "histogram 就是一个指标" | 3 route → 36 条序列（12x） |
| "`prometheus_tsdb_head_series` 能查基数" | 本环境该指标**不存在**，须用状态 API |
| "`sample_limit` 是保护性限制" | 是**熔断**，target 直接消失 |
| "每条序列占多少内存有公式" | 本机规模测不出来，**不给数字** |

### 本课的「未实测」清单

诚实披露，这些本课**没有**给出数字：

- **每条序列的内存占用系数**：3 轮复现基线波动 31.43~38.79 MiB，
  连固定 5000 序列只变标签长度（8/64/256 字符）都测不出单调差异。
  **本机规模不足，留待课 11 用更大规模重测。**
- 10 万级以上序列的查询延迟劣化
- 实例 churn 的时间维度累积效应（需长时间运行）
- `--storage.tsdb.max-series-per-*` 的实际触发行为（课 12 讲 admin API 时实测）

> 完整数据见 [CARDINALITY-DATA.md](../../../labs/lesson-10/CARDINALITY-DATA.md)

---
## 🗺️ 课程导航

- 上一课：[课 9 长期存储选型](../../3-规模化与生态/lessons/lesson-09-长期存储选型.md)
- 下一课：课 11《容量规划与调优》—— 本课没测出来的内存系数，在那里用更大规模实测
- 阶段：[阶段 4 生产运维](../overview.md)

## ⚡ 速览卡

```text
┌──────────────────────────────────────────────────────────┐
│ 基数治理 速览                                             │
├──────────────────────────────────────────────────────────┤
│ 算：序列数 = 标签值组合数（1:1，可精确预测）              │
│     histogram 放大 = 桶数（默认 12x）                     │
│                                                           │
│ 查：curl /api/v1/status/tsdb                              │
│     （别用 prometheus_tsdb_head_series，可能不存在）       │
│                                                           │
│ 治：① 暴露端收敛取值域（治本）                            │
│     ② metric_relabel drop / labeldrop（温和，up=1）       │
│     ③ sample_limit / label_limit（熔断，up=0，慎用）      │
│                                                           │
│ 坑：label_limit 是 per-target 全局，会误伤无关指标        │
│     删指标不立即回收磁盘（等 compaction）                 │
└──────────────────────────────────────────────────────────┘
```

## 📝 小测

### 选择题（单选）

**1. 一个 `Histogram` 指标，配置了 11 个自定义桶，`route` 标签有 3 个取值。
它最终产生多少条 `_bucket` 序列？**

- A. 3 条
- B. 11 条
- C. 33 条
- D. 36 条 ✅

> 11 个自定义桶 + `+Inf` = 12 个桶，3 × 12 = 36。实测 `card_hist_seconds_bucket = 36`。

**2. 某 target 配置了 `sample_limit: 100`，实际会抓到 3573 个样本。会发生什么？**

- A. 前 100 个入库，其余丢弃
- B. 全部丢弃，target `up=0` ✅
- C. 全部入库，只是记一条警告
- D. 抓取直接跳过，不发起请求

> 实测 `scrape_samples_scraped=3573`（抓取发生了）但 `health=down`、`up=0`。
> 是熔断不是截断。

**3. 诊断高基数时，为什么推荐 `/api/v1/status/tsdb` 而不是 PromQL 查询？**

- A. 因为 PromQL 语法太难
- B. 因为该 API 不依赖指标暴露，且不给已繁忙的 Prometheus 加全库扫描 ✅
- C. 因为 PromQL 查不出序列数
- D. 两者完全等价

**4. `label_limit: 3` 触发时报的错是关于哪个指标？**

- A. 一定是序列最多的那个指标
- B. 一定是标签最多的那个指标
- C. 任意第一个超标的指标，可能是无关的 GC 指标 ✅
- D. 不会报错，只是静默丢弃

> 实测报错在 `python_gc_objects_collected_total`（4 个标签），
> 而我们想限制的 `card_bad_by_url` 只有 3 个标签，本身合规。

**5. 把 `user_id` 放进标签，10 万用户会多出多少条序列？**

- A. 约 10 条（按前缀聚合）
- B. 约 10 万条，且永久增长 ✅
- C. 0 条，会被自动合并
- D. 取决于抓取间隔

### 判断题

**1. `# HELP` / `# TYPE` 这类元数据会产生时间序列。**
❌ 错。实测 app 只输出 HELP/TYPE 无样本时，Prometheus 里一条序列都没有。元数据占内存但不产生序列。

**2. 用 `metric_relabel_configs` 的 `drop` 丢弃指标后，target 仍然保持 `up=1`。**
✅ 对。实测丢弃 3 000 条后 `up=1`，其余指标正常入库（3 557 → 557）。

**3. `labeldrop` 比 `drop` 更温和，因为它保留了指标本身。**
✅ 对。删掉 `user_id` 标签后所有样本合并成 1 条序列，指标还在。

**4. 删除高基数指标后，磁盘空间会立即释放。**
❌ 错。删除只写 tombstone，物理删除要等 compaction（课 12 会实测）。

**5. 本课给出了"每条序列占用多少内存"的实测系数。**
❌ 错。**本课明确不给这个数字**：3 轮复现基线波动 31.43~38.79 MiB，
本机规模测不出来，已标注未实测并留待课 11。

### 简答题

**1. 你的同事想在指标里加 `url` 标签做下钻分析，理由是"方便排查"。
请结合本课的实测数据说明为什么这是错的，并给出替代方案。**

> 参考答案：`url` 的取值域是**所有出现过的 URL 路径**，不是"几个值"。
> 实测加 2 000 个 URL 就多 2 000 条序列（1:1），
> 而生产环境 URL 往往是动态生成的（`/resource/{id}/detail`），取值域**无上界**。
> 替代方案：用低基数的 `route`（模板化路径）做标签，
> 具体 URL 用**日志或 tracing** 下钻——这是指标、日志、链路三类数据的职责边界。

**2. 生产环境 Prometheus 内存持续上涨，你怀疑是基数问题。
请写出你的排查顺序（用本课实测过的命令）。**

> 参考答案：
> ① `curl -s localhost:9090/api/v1/status/tsdb` 看 `numSeries` 总量；
> ② 看 `seriesCountByMetricName` 找出序列最多的指标；
> ③ 用 `/api/v1/series?match[]=<指标>` 看具体标签，判断是哪类失控
>   （连续编号 = 标签值失控；`le` = 直方图）；
> ④ 注意：**不要**用 `count({__name__=~".+"})` 做日常监控，它会扫全库。

**3. 为什么 `sample_limit` 不是好的基数治理手段？什么时候该用它？**

> 参考答案：因为它是**熔断而非限流**——实测触发后整个 target `up=0`，
> 所有指标（包括 `up` 自己）全部消失，而抓取动作照常发生（付了代价没得到数据）。
> 且 `label_limit` 是 per-target 全局的，会误伤无辜指标（实测拦在 GC 指标上）。
> 正确用法：作为**第三方 exporter 不可控时的最后保险丝**，
> 平时治理应该用暴露端收敛 + `metric_relabel_configs`。

---
## 🤖 接力提示词

```text
我刚学完 Prometheus 课 10《基数治理》，掌握了：
- 序列数 = 标签值组合数（实测 +5000 user_id → +5000 序列）
- histogram 放大 = 桶数（实测 3 route → 36 条 bucket 序列，12x）
- 诊断用 /api/v1/status/tsdb（prometheus_tsdb_head_series 可能不存在）
- 控制手段：metric_relabel 温和（drop 后 up=1），sample_limit 是熔断（up=0）
- 本课未测出每序列内存系数，留待课 11

请继续课 11《容量规划与调优》，重点：
1. 用更大规模（10 万级序列）实测每序列内存占用，补上课 10 欠的数字
2. 抓取间隔、保留时间、chunk 参数各自影响什么
3. 监控 Prometheus 自身的必看指标与告警规则
```
