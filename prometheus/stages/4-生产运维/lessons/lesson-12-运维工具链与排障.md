# 课 12：运维工具链与排障

> 所属阶段：[阶段 4 生产运维](../overview.md) ｜ 上一课：[课 11 容量规划与调优](./lesson-11-容量规划与调优.md)
> 数据底稿：[TOOLING-DATA.md](../../../labs/lesson-12/TOOLING-DATA.md)

---

## 🎬 第一幕：场景引入

凌晨三点，告警响了：`PrometheusTargetDown`。你打开浏览器，看到 `/targets` 页面一片红。

更糟的是另一个场景：你发现某个指标把基数搞爆了，紧急用 `delete_series` 删掉了 20000 条序列，
API 返回 204（成功）。你松了口气去看磁盘——**一点没少**。

再看 `scrape_duration_seconds`，显示 1.0009 秒。你想："才 1 秒啊，没道理超时。"

这两个场景里，**工具都告诉你"成功了"或"没问题"，但真相恰恰相反**。

这就是本课要解决的问题：**当 Prometheus 自己的反馈不可信时，你靠什么排障？**

课 10 讲了基数从哪来，课 11 讲了要多少资源。本课讲第三件事：
**用什么工具在变更前验证、在出事后安全处置，以及怎么从症状倒查回根因。**

本课还清课 10、课 11 挂下的一批账——那些当时"测不出来"或"来不及测"的东西。

---

## ⚡ 第二幕：认知冲突

先建立直觉：Prometheus 的运维工具分三类，你大概率**只会用第一类**。

**第一类：事前校验**（promtool check 家族）
改配置前跑一下，能拦住语法错误。这是多数人的全部认知。

**第二类：事后处置**（admin API / tsdb 子命令）
出事后删数据、做快照、清理墓碑。多数人**不知道这些操作有前置条件**。

**第三类：主动分析**（tsdb analyze / bench / query）
没出事时主动体检。用的人最少。

**冲突点在第三幕揭晓**。

---

## 🔍 第三幕：层层揭示

### 知识点 1：promtool 工具链

> **一句话定义**：promtool 是 Prometheus 自带的命令行工具，覆盖"配置校验 → 规则单测 →
> 指标体检 → 查询调试 → TSDB 分析"五件事，核心用途是**在变更前把问题拦在本地**。

#### 直觉建立：它是"编译器"，不是"解释器"

写代码要编译，改 Prometheus 配置却常常直接重启看日志。promtool 就是把这步提前：

| 子命令 | 类比 | 拦什么 |
|---|---|---|
| `check config` | 语法检查 | 配置能不能启动 |
| `check rules` | 语法检查 | 规则文件对不对 |
| `test rules` | **单元测试** | 规则行为对不对 |
| `check metrics` | lint | 暴露端指标规不规范 |
| `query instant/range` | 调试器 | 查询返回什么 |
| `tsdb *` | 体检工具 | TSDB 内部状态 |

注意 `test rules` 和 `check rules` 的区别：
**`check` 只管能不能跑，`test` 才管跑得对不对**。这是很多人忽略的分界。

#### 核心原理：`check config` 到底查什么、不查什么

实测四个配置文件（本机 v3.14.0）：

| 配置 | 结果 | 说明 |
|---|---|---|
| 正确配置 | ✅ SUCCESS | — |
| `scrape_timeout: 60s` > `scrape_interval: 15s` | ❌ FAILED | 报 `scrape timeout greater than scrape interval` |
| YAML 缩进错误 | ❌ FAILED | 报 `yaml: line 5: mapping values are not allowed` |
| relabel 引用 `__meta_nonexistent__` | ✅ **SUCCESS** | **放行了** |

前三行符合预期。**第四行是关键**：

```bash
# 这个配置能通过 check config，但 relabel 永远不会生效
relabel_configs:
  - source_labels: [__meta_nonexistent__]
    target_label: foo
```

> **常见误区**：以为 `promtool check config` 过了就万事大吉。
> 它只查**语法**和**静态语义**（比如 timeout 与 interval 的大小关系），
> **不查标签是否真实存在、target 是否可达、relabel 逻辑是否符合业务预期**。
> 这就是为什么很多配置"过了 CI，上了生产才发现没生效"。

**一句话记住**：check config 是拼写检查，不是作文批改。

#### 示例演示：`test rules` 真的能拦错吗

光看它"跑通"没意义——**必须验证它会不会 FAIL**。

被测规则（磁盘 6 小时内将满）：

```yaml
# rules/disk.yml
groups:
  - name: disk
    rules:
      - alert: DiskWillFillIn6h
        expr: predict_linear(node_filesystem_free_bytes[1h], 6*3600) < 0
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "disk will fill in 6h"
```

单测（注入 1 小时下降趋势）：

```yaml
# rules/disk_test.yml
rule_files:
  - disk.yml
evaluation_interval: 1m
tests:
  - interval: 1m
    input_series:
      # 从 100GB 每分钟掉 1GB，共 60 个点
      - series: 'node_filesystem_free_bytes{mountpoint="/"}'
        values: '100000000000-1000000000x59'
    alert_rule_test:
      - eval_time: 10m
        alertname: DiskWillFillIn6h
        exp_alerts:
          - exp_labels:
              severity: warning
              mountpoint: "/"
            exp_annotations:
              summary: "disk will fill in 6h"
```

```bash
promtool test rules disk_test.yml   # SUCCESS
```

**反向验证**（把期望改成"不该触发"）：

```
  FAILED:
    alertname: DiskWillFillIn6h, time: 10m,
        exp:[],
        got:[
            0:
              Labels:{alertname="DiskWillFillIn6h", mountpoint="/", severity="warning"}
              Annotations:{summary="disk will fill in 6h"}
            ]
exit=1
```

它准确报出"你期望没有告警，但实际触发了"，exit=1。

**再测一个边界**：磁盘恒定时（`values: '100000000000+0x59'`）不触发 → SUCCESS。

> **这才是可信的验证**：正向能过、反向能拦、边界能分。
> 只跑正向就说"单测有效"，和没测一样。

#### 示例演示：`check metrics` 的基数分析

这是对课 10 基数治理的直接支援——**不用等数据进 TSDB，在暴露端就能看基数**。

```bash
curl -s http://localhost:9090/metrics | promtool check metrics --extended
```

实测输出（运行中 Prometheus 自身指标，截取）：

```
Metric                                    Cardinality    Percentage
prometheus_http_requests_total            63             8.41%
prometheus_http_request_duration_seconds  36             4.81%
prometheus_http_response_size_bytes       33             4.41%
prometheus_engine_query_duration_...      28             3.74%
```

**顺带发现**：它还报出 Prometheus **自己**的 5 条命名违规：

```
prometheus_engine_query_duration_histogram_seconds metric name should not include type 'histogram'
prometheus_rule_evaluation_duration_histogram_seconds metric name should not include type 'histogram'
prometheus_rule_group_duration_histogram_seconds metric name should not include type 'histogram'
prometheus_target_interval_length_histogram_seconds metric name should not include type 'histogram'
prometheus_target_sync_length_histogram_seconds metric name should not include type 'histogram'
```

连官方自己都没过 lint——**说明这条规则常被忽略，但工具确实会查**。

**一个使用限制**：`check metrics` **遇错即停**。实测重复 HELP 行报错后，
后面其他问题**不会再报**：

```
error while linting: text format parsing error in line 5: second HELP line for metric name "http_requests_total"
```

所以修 lint 是"一次修一个"的循环，不是一次看全。

> **常见误区**：`--extended` 是"更严格"的意思。
> 实际它是**增加基数分析输出**，lint 规则本身不变。

#### 示例演示：TSDB 子命令

```bash
# 列出所有 block
promtool tsdb list /prometheus

# 分析 churn 与标签基数
promtool tsdb analyze /prometheus [block-id]

# 从 OpenMetrics 文本离线造 block（用于测试/回填）
promtool tsdb create-blocks-from openmetrics input.om ./out
```

实测 `create-blocks-from` 生成 60 个 block 后 `tsdb analyze` 输出：

```
Block ID: 01M1XF70X6JTGMSM7WPR4G6Q89
Duration: 1ms
Total Series: 200
Label names: 3
Postings (unique label pairs): 204
Postings entries (total label pairs): 600

Label pairs most involved in churning:
200 __name__=l12_demo
67 zone=z0
67 zone=z1
66 zone=z2
```

**踩坑实测**：`create-blocks-from openmetrics` **必须**以 `# EOF` 结尾，否则：

```
getting min and max timestamp: next: data does not end with # EOF
```

这是 OpenMetrics 格式的硬性要求，不是 promtool 的怪癖。

#### ⚠️ 一个反直觉的发现：`check healthy` 探不了远端

你可能以为 `promtool check healthy <url>` 能探活远端 Prometheus。实测：

```bash
$ promtool check healthy http://l12-prom2:9090
promtool: error: unexpected http://l12-prom2:9090, try --help
```

查 `--help` 确认：**这个子命令没有 `<server>` 位置参数**，只有 `--http.config.file`。
用空配置文件实测，它连的是**硬编码的 `localhost:9090`**：

```
Get "http://localhost:9090/-/healthy": dial tcp [::1]:9090: connect: connection refused
```

对照 `query instant`，后者**确实**接受 server 参数：

```bash
$ promtool query instant http://l12-prom2:9090 'up'
up{instance="localhost:9090", job="prometheus"} => 1 @[1788769351.478]
up{instance="l12-slow:8000", job="slowapp"} => 0 @[1788769351.478]
```

> **一句话记住**：`check healthy/ready` 只在 Prometheus **本机**好用；
> 探远端请用 `curl /-/healthy` 或 `query instant`。

**知识点 1 一句话记住**：promtool 能拦语法和规则行为，但拦不住"逻辑上没意义"的配置——
**它替你省的是重启的时间，不是思考的时间**。

---

### 知识点 2：TSDB 管理与 admin API

> **一句话定义**：admin API 提供快照、删除序列、清理墓碑三类高危操作，
> 共同点是**返回 204 不代表达到了你想要的效果**。

#### 直觉建立：204 是"我收到了"，不是"我做完了"

先启用（默认关闭，这是安全设计）：

```bash
prometheus --web.enable-admin-api --web.enable-lifecycle
```

三个操作：

| 操作 | 端点 | 破坏性 |
|---|---|---|
| 快照 | `POST /api/v1/admin/tsdb/snapshot` | 无（只增） |
| 删除序列 | `POST /api/v1/admin/tsdb/delete_series` | **高，不可逆** |
| 清理墓碑 | `POST /api/v1/admin/tsdb/clean_tombstones` | 中（重写 block） |

#### 核心原理：删除是"记账"，不是"擦除"

这是本课最反直觉的部分。

**实测全过程**（干净环境，2 万序列）：

| 阶段 | `count(l12_series)` | headSeries | 磁盘 |
|---|---|---|---|
| 基线 | 20 000 | 20 736 | 676 KB |
| 删除后 | **empty** | 20 782 | 1 236 KB |
| `clean_tombstones` 后 | empty | 20 830 | 1 236 KB |
| 重启后 | **empty** | 20 830 | 1 108 KB |

三个结论：

1. **数据查不到了** ✅ 删除生效
2. **headSeries 没降**（20 782）— 索引条目还在
3. **磁盘没释放**（1 236 → 1 236）

为什么？看目录结构就懂了：

```
/prometheus/
├── chunks_head/     # 0 KB
├── wal/             # 3 376 KB   ← 数据在这里
└── (没有 01* block)
```

**blocks = 0**。所有数据都还在 head + WAL 里，没有落盘成 block。
而 `clean_tombstones` 只清理**已落盘 block** 的墓碑——对 head 数据无效。

> **常见误区**：以为 `delete_series` 返回 204 = 磁盘腾出来了。
> 实际它只是**追加了一条 tombstone 记录**（"这些序列从某时刻起不算数"），
> 原数据还在磁盘上，甚至因为多了墓碑记录而**不会变小**。
> 真正的空间回收要等：数据落盘成 block → `clean_tombstones` 重写 block。

#### 一次严谨性自查：磁盘到底涨没涨？

上表看起来"删除后磁盘从 676 涨到 1236 KB"，很容易写成"删除导致磁盘反涨"。

**但这个结论站不住**——因为 self-scrape 一直在产生新数据。

做了对照实验：两个完全相同的实例，**A 删除、B 不删除**，同期对比：

```
A(删除) = 1 172 KB    B(不删) = 1 172 KB
差值 = 0 KB
```

**净增 0 KB**。所以正确结论是**不释放**，而不是"反涨"。

> 这是本课的实验方法教训：**看到数字变化，先问有没有对照组**。
> 没有对照组的"前后对比"，测到的往往只是时间流逝。

#### 一个差点写错的结论：删除后数据"复活"了吗？

实验中一度观察到：删除后 count 变 empty，**重启后又变成 20000**。

第一反应是"tombstone 没持久化，重启丢了"。**这是误判。**

真因：**app 还在跑**。`delete_series` **只删删除时点之前的历史**，
不阻止新样本入库。重启后新一轮抓取完成，count 自然回到 20000。

**验证方法**：停掉 app 切断数据源，再做删除 → 重启后仍是 empty。

**更精确的验证**（决定性证据）：只删一部分序列（`idx=~"00000.*"`，1000 条），
用 range 查询对比 A（删）/ B（未删）：

| 实例 | `00000.*` 数据点数 |
|---|---|
| A（已删） | **1**（在删除时点截断） |
| B（未删） | **3** |

A 的序列在删除时刻**从 3 个点截断到 1 个点**，B 保持 3 个。**删除确实精准生效**。

> **方法论**：判断"删除是否生效"，**必须先切断数据源**。
> 否则你看到的"复活"只是新数据回填，与删除本身无关。

#### ⚠️ 挂账清偿：`max-series-per-*` 在 3.14.0 已不存在

课 10 和课 11 各挂了一笔：`--storage.tsdb.max-series-per-*` 的触发行为。

实测：

```bash
$ prometheus --storage.tsdb.max-series-per-metric=1000
Error parsing command line arguments: unknown long flag '--storage.tsdb.max-series-per-metric'
prometheus: error: unknown long flag '--storage.tsdb.max-series-per-metric'
```

**这个 flag 在 3.14.0 根本不存在**。查 `--help` 确认，当前 tsdb flag 只剩 6 个：

```
--storage.tsdb.path
--storage.tsdb.retention.time
--storage.tsdb.retention.size
--[no-]storage.tsdb.no-lockfile
--storage.tsdb.head-chunks-write-queue-size
--storage.tsdb.delay-compact-file.path
```

**没有任何序列数硬限制**。

> **这意味着什么**：Prometheus 不再提供"序列数超过 N 就拒绝写入"的全局兜底。
> 防基数爆炸只能靠**抓取端**的三件套（课 10 已实测）：
> `metric_relabel_configs`（drop）、`sample_limit`、`label_limit`。
> **别指望存储端兜底了。**

#### 快照：唯一"安全"的操作

```bash
curl -XPOST http://localhost:9090/api/v1/admin/tsdb/snapshot
# {"status":"success","data":{"name":"20260907T081354Z-1c2d1d7b596620c8"}}
```

实测落盘：`/prometheus/snapshots/<name>/`，2.8 MB，内含一个 block 目录。

> **前置条件**：快照只含**已落盘的 block 和 head 的当前状态**。
> 它是"硬链接"实现，所以快且不额外占空间（直到原数据被改）。
> **做危险操作（删除）之前先快照**，这是唯一后悔药。

**知识点 2 一句话记住**：`delete_series` 是记账不是擦除，
**磁盘不会因为删除而变小**，想回收空间得等落盘 + `clean_tombstones`。

---

### 知识点 3：排障方法论

> **一句话定义**：按"症状 → 子系统 → 参数"倒查，
> 每一步都用**不依赖前一层的手段**交叉验证。

#### 直觉建立：不要相信单一指标

排障最大的坑是**用可能出错的工具去验证可能出错的组件**。

Prometheus 排障分三层，每层有独立的验证手段：

| 层 | 症状 | 验证手段 | 独立性 |
|---|---|---|---|
| 采集层 | target down | `/api/v1/targets` 的 `lastError` | 不依赖 TSDB |
| 存储层 | 查不到数据 | `/api/v1/status/tsdb` | **不依赖抓取链路** |
| 查询层 | 查询慢/报错 | `promtool query instant` | 绕过 UI |

课 11 已证明第二层的重要性：self-scrape 挂了，`prometheus_*` 指标全没，
但 `/api/v1/status/tsdb` 仍然可用。**每层要能独立验证**。

#### 核心原理：一个真实故障的完整倒查

**构造故障**：app 响应要 3 秒，但 `scrape_timeout: 1s`。

```yaml
global:
  scrape_interval: 5s
  scrape_timeout: 1s      # 小于实际响应耗时
scrape_configs:
  - job_name: slowapp
    static_configs:
      - targets: ["l12-slow:8000"]
```

**第 1 步：看症状（targets 页面）**

```
job=prometheus  health=up     err=
job=slowapp     health=down   err=Get "http://l12-slow:8000/metrics": context deadline exceeded
```

`lastError` 直接告诉你：`context deadline exceeded` = 超时。

**第 2 步：用指标确认范围**

```
up=1  job=prometheus
up=0  job=slowapp
```

只有 slowapp 挂，说明**不是 Prometheus 自身问题**，定位到单个 target。

**第 3 步：比对该 target 的耗时与超时阈值**

```
duration=0.005304745  job=prometheus
duration=1.000991574  job=slowapp      ← 关键
```

#### ⚠️ 这里有个陷阱

`scrape_duration_seconds = 1.0009s`。如果你只看这个数字，会想：
**"才 1 秒，配置里 timeout 也是 1 秒，刚好卡在边界，应该没问题吧？"**

**错。**

`1.0009s` 不是真实耗时，是**被 timeout 截断后的值**。
真实耗时要用**绕过 Prometheus 的手段**测：

```bash
$ time wget -q -O /dev/null http://l12-slow:8000/metrics
real    0m 5.99s
```

**真实 5.99 秒，是指标显示的 6 倍。**

> **常见误区（本课最重要的一条）**：
> **超时发生时，`scrape_duration_seconds` 记录的是 timeout 阈值，不是真实耗时。**
> 所以"抓取耗时没超"这句话，**在 target 已经 down 的情况下永远成立**——
> 它是个自证循环，不能用来排除超时。

**正确的排障顺序**（实测有效）：

```
1. /-/healthy + /-/ready     → Prometheus 自身活着吗？
2. /api/v1/targets 的 err     → 哪个 target、什么错？
3. up 指标                    → 影响范围多大？
4. 配置里 scrape_timeout 是多少 → 与实测耗时比对
5. 绕过 Prometheus 直接测源站   → 拿真实耗时（关键！）
```

第 5 步是关键——**用不依赖 Prometheus 的手段拿到 ground truth**。

#### 示例演示：把倒查链串起来

对本次故障：

| 步骤 | 观察到 | 推论 |
|---|---|---|
| 1 | healthy/ready 正常 | 故障在采集侧，不在存储/查询侧 |
| 2 | `context deadline exceeded` | 是超时，不是连接拒绝 |
| 3 | `up=0` 仅 slowapp | 单 target 问题，非全局 |
| 4 | duration 1.0009s ≈ timeout 1s | **被截断，不可信** |
| 5 | 源站真实 5.99s | 5.99s > 1s → 确认超时 |

**修复**：把 `scrape_timeout` 调到大于真实耗时（如 10s），
或优化源站响应速度。

#### 常见误区汇总

**误区 1**：`up=0` 就是服务挂了。
实际可能是超时、DNS、认证、relabel 后 target 消失等。`up=0` 只说"没抓到"，**原因看 `lastError`**。

**误区 2**：`scrape_duration_seconds` 能反映真实耗时。
超时时它被截断（本课实测 1.0009s vs 真实 5.99s）。**target down 时这个指标不可信**。

**误区 3**：删了数据磁盘就会变小。
见知识点 2，删除是记账不是擦除。

**误区 4**：`check config` 过了配置就没问题。
它不查元标签是否存在（实测放行 `__meta_nonexistent__`）。

**知识点 3 一句话记住**：**target down 时，`scrape_duration_seconds` 是假的**——
要拿真实耗时，必须绕过 Prometheus 直接测源站。

---

## 🛠 第四幕：实操验证

> 以下命令均在本机 v3.14.0 逐字执行通过。端口 `19500` 为本课实验实例。

### 准备：起一个带 admin API 的实例

```bash
docker run -d --name l12-prom --network l12net \
  -v $PWD/cfg:/cfg:ro -v $PWD/data:/prometheus -p 19500:9090 \
  prom/prometheus:v3.14.0 \
  --config.file=/cfg/prometheus-l12.yml \
  --storage.tsdb.path=/prometheus \
  --storage.tsdb.retention.time=1h \
  --web.enable-admin-api --web.enable-lifecycle
```

> `--web.enable-admin-api` 是 admin API 的前提，默认关闭。
> `--web.enable-lifecycle` 用于热加载（`POST /-/reload`）。

### 步骤 1：配置校验

```bash
promtool check config /cfg/good.yml
# SUCCESS: /cfg/good.yml is valid prometheus config file syntax

promtool check config /cfg/bad-timeout.yml
# FAILED: parsing YAML file ...: scrape timeout greater than scrape interval ...
```

### 步骤 2：规则单测（正向 + 反向）

```bash
promtool test rules disk_test.yml       # SUCCESS
promtool test rules disk_test_neg.yml   # FAILED: exp:[] / got:[...]
```

> 反向用例很重要：**只跑正向等于没测**。

### 步骤 3：指标体检与基数

```bash
curl -s http://localhost:19500/metrics | promtool check metrics --extended
```

### 步骤 4：TSDB 状态（不依赖抓取链路）

```bash
curl -s http://localhost:19500/api/v1/status/tsdb
```

### 步骤 5：快照（危险操作前的后悔药）

```bash
curl -XPOST http://localhost:19500/api/v1/admin/tsdb/snapshot
```

### 步骤 6：删除序列

```bash
# 注意：用 --data-urlencode，直接拼 URL 会被 shell 吃掉引号
curl -XPOST -G http://localhost:19500/api/v1/admin/tsdb/delete_series \
  --data-urlencode 'match[]=l12_series'
```

> **两个实测踩坑**
> 1. 直接拼 `?match[]={__name__="x"}` 会报 `parse error: unexpected "="`，
>    引号被 shell 吞掉了。用 `--data-urlencode`。
> 2. `match[]` **不支持 `<` `>` 比较符**，只支持 `=` `!=` `=~` `!~`。
>    要按范围删请用正则，如 `match[]=l12_series{idx=~"00000.*"}`。

### 步骤 7：验证删除效果（先停数据源！）

```bash
docker stop l12-app          # 关键：切断新数据，否则会误判"复活"
curl -s 'http://localhost:19500/api/v1/query?query=count(l12_series)'
```

### 步骤 8：故障倒查——拿真实耗时

```bash
# Prometheus 说的（可能是截断值）
curl -s 'http://localhost:19500/api/v1/query?query=scrape_duration_seconds'

# 真实耗时（绕过 Prometheus）
time curl -s http://l12-slow:8000/metrics > /dev/null
```

---

## 📚 第五幕：体系收束

### 本课三个知识点的关系

```
变更前 ──→ promtool check/test  ──→ 把问题拦在本地
                                        │
出事后 ──→ admin API（快照→删除→清理）  │
                                        │
                                        ▼
                        排障：症状 → 子系统 → 参数
                        （每层用独立手段验证）
```

### 与前后课的连接

- **课 10（基数治理）**：本课 `check metrics --extended` 是基数治理的**上游工具**；
  `max-series-per-*` 的移除结论，把防爆炸的责任推回了课 10 的抓取端三件套。
- **课 11（容量规划）**：本课"删除不释放磁盘"清偿了课 11 的挂账；
  课 11 的"self-scrape 必须有"是本课 `/api/v1/status/tsdb` 之外的重要补充。
- **阶段 4 收官**：课 10 管"别让它爆"，课 11 管"给多少资源"，
  本课管"爆了怎么办"。

### 本课还清的挂账

| 挂账来源 | 内容 | 结论 |
|---|---|---|
| 课 10、课 11 | 删除后磁盘未释放 | ✅ 对照实验实测**净增 0 KB = 不释放**，要等落盘 + clean |
| 课 10、课 11 | `max-series-per-*` 触发行为 | ✅ **3.14.0 已移除**，只能靠抓取端 |
| 课 11 | compaction 后 block 磁盘占用 | ⚠️ **仍未拿到**（见下） |

### 诚实标注：本课没测出来的

1. **运行中实例的 block 落盘后磁盘占用**。
   本课用 `tsdb create-blocks-from` 离线造了 block 并分析，
   但**运行中实例要 2 小时才落盘**，3.14.0 又移除了 `max-block-duration`
   （无法强制触发），所以**课 11 的 WAL 口径磁盘数字仍未升级为 block 口径**。
   建议：长期运行的实例上观察，或在后续实战项目中补测。
2. **`clean_tombstones` 在真实 block 上的回收效果**。
   本课实验中 blocks=0，只证明了"对 head 无效"，
   **没测到"对 block 有效"**。这是不同的两件事。
3. **`tsdb bench write` 的写入基准**。
   子命令存在，但本机为 WSL + 挂载盘，IO 数字参考价值有限，未纳入结论。

### 一句话记住本课

> **工具告诉你"成功"的时候，先问一句：成功的定义是什么？**
> 204 不等于腾了空间，1 秒不等于没超时，check 通过不等于配置有意义。

---

## 📖 速览卡

| 项 | 结论 |
|---|---|
| `check config` 拦什么 | 语法、`timeout > interval`；**不查元标签是否存在** |
| `check rules` vs `test rules` | 前者查能不能跑，后者查跑得对不对 |
| `test rules` 可信吗 | ✅ 反向验证确实 FAIL（`exp:[]` vs `got:[...]`） |
| `check metrics` 特点 | **遇错即停**；`--extended` 出基数 Top 表 |
| `check healthy/ready` | **只连 `localhost:9090`**，不接受 URL |
| `delete_series` 效果 | 只删**删除时点之前**的历史；不阻止新数据 |
| 删除后 headSeries | **不降** |
| 删除后磁盘 | **不释放**（对照实验净增 0 KB） |
| `clean_tombstones` | 对 head 数据**无效**，需先落盘成 block |
| 重启后删除 | ✅ 仍生效 |
| `max-series-per-*` | **3.14.0 已移除** |
| 超时时 `scrape_duration_seconds` | **截断值**（实测 1.0009s vs 真实 5.99s） |

---

## ✅ 小测

**1.** `promtool check config` 通过了，配置就一定能按预期生效吗？举一个反例。

**2.** 你执行 `delete_series` 返回 204，但磁盘没变小。为什么？怎样才能真正回收空间？

**3.** 某 target `up=0`，`scrape_duration_seconds` 显示 0.9s，
配置的 `scrape_timeout` 是 1s。能排除超时吗？为什么？

<details>
<summary>参考答案</summary>

**1.** 不能。反例：relabel 中 `source_labels: [__meta_nonexistent__]` 引用了一个不存在的元标签，
`check config` 返回 SUCCESS，但该 relabel 永远不会生效（实测放行）。
它只查语法和静态语义，不查标签是否真实存在。

**2.** 因为 `delete_series` 是**追加 tombstone 记账**，不是擦除数据。
原数据还在磁盘上（本例中还在 head + WAL），索引条目也没删，所以 headSeries 不降、磁盘不释放
（对照实验实测净增 0 KB）。
真正回收需要：数据落盘成 block → `clean_tombstones` 重写 block 去掉已删序列。
本实验中 blocks=0，所以 clean 无效。

**3.** **不能排除**。超时发生时 `scrape_duration_seconds` 记录的是**被截断的 timeout 值**，
不是真实耗时——所以只要 target 已经 down，这个数字必然"看起来没超"。
本课实测：指标显示 1.0009s，源站真实 5.99s。
正确做法是**绕过 Prometheus 直接测源站**（`time curl <target>/metrics`）。

</details>

---

## 🧭 课程导航

- **上一课**：[课 11 容量规划与调优](./lesson-11-容量规划与调优.md)
- **下一阶段**：阶段 4 已收官，可进入综合实战或回顾 [阶段 4 总览](../overview.md)
- **数据底稿**：[TOOLING-DATA.md](../../../labs/lesson-12/TOOLING-DATA.md)
- **返回**：[课程目录](../../../02-课程目录.md) ｜ [学习路径总览](../../../01-学习路径总览.md)

---

## 🔍 本课评审结论

**评审方式**：主 agent 内联双视角（pedagogy + learner），P0 清零后交付。

**P0 = 0**。

**本轮修正的三个实验设计缺陷**：

1. **对照实验首版无效**：两个实例都无数据（app 已停导致删除空集），
   改为"先起 app 攒数据 → 停 app → 再删"。
2. **`match[]` 不支持比较符**：`<` 报 `parse error: unexpected character inside braces`，
   改用正则 `=~`。
3. **查询 URL 被 shell 破坏**：`<`、`=~` 在 URL 中被截断，
   改用 Python 直接发请求。

**一个被推翻的自我结论**：

初判"删除导致磁盘反涨（676→1236 KB）"。
做 A/B 对照实验后**推翻**——净增 0 KB，真实结论是**不释放**，
之前的"涨幅"是 self-scrape 自然增长。

**一个被纠正的误判**：

实验中一度判"删除后重启，数据复活"。
**误判**——真因是 app 持续产生新数据（`delete_series` 只删历史，不阻止新样本）。
停掉 app 后验证：删除正常生效，重启后仍生效。
此教训已写入讲义知识点 2。

**未强行下结论的三处**：运行中实例的 block 磁盘口径、
`clean_tombstones` 对真实 block 的效果、`tsdb bench write` 的 IO 数字。
均在讲义中显式标注，未用推测填补。
