# 课 7 实测数据汇总（本机 Prometheus v3.14.0 / VM v1.151.0，2026-09-04）

> 本文件是讲义的数据底稿。所有数字均来自本机实测，供写作时引用，避免前后不一致。

## 环境

| 组件 | 镜像 | 端口 | 作用 |
|---|---|---|---|
| l7-app | 自建 python:3.11-slim | 容器内网 8080 | 数据源，507 条序列（500 cards + 4 requests + up + runtime + build_info） |
| l7-receiver | 自建 python:3.11-slim | 19099 | 可控 remote write 后端，可注入 ok/500/503/429/slow/drop |
| l7-prom | prom/prometheus:v3.14.0 | 19100 | 主实例，server 模式，remote write → receiver |
| l7-prom-rr | 同上 | 19102 | remote write/read → VM |
| l7-prom-ro | 同上 | 19103 | 仅 remote read → VM |
| l7-backend | 同上 | 19105 | 后端 Prometheus，抓 l7-app，原生支持 remote read |
| l7-reader | 同上 | 19106 | 仅 remote read → backend，本地无 l7-app 数据 |
| l7-agent | 同上 | 19107 | `--agent` 模式 |
| l7-vm | victoriametrics/victoria-metrics:v1.151.0 | 19101 | 真实后端（**注意：单节点版不支持 /api/v1/read**） |

## 知识点 1：remote write 队列

### 指标名（v3.14.0 实测，旧名已失效）

| 旧名（网上常见，已不存在） | v3.14.0 真名 |
|---|---|
| `prometheus_remote_storage_samples_out_total` | `prometheus_remote_storage_samples_total` |
| `prometheus_remote_storage_samples_dropped_total` | **已移除**，改用 `samples_failed_total` + `enqueue_retries_total` |
| `prometheus_remote_storage_bytes_sent_total` | `prometheus_remote_storage_bytes_total` |

新增：`histograms_*` / `exemplars_*` 各一组（v3 原生直方图支持）、`shard_capacity`、`shards_desired`。

注意：`samples_in_total` **无** `remote_name` 标签，`samples_total` **有**。两者口径不同（实测恒定偏移约 -1450），**不可相减算丢失**。

### E1 队列行为（后端 500，60 秒）

```
阶段      pending   failed  retried  enqRetry  shards
正常        ~55        0       0        0        1
500 故障    1199       0      500→700   14→16     1 (max=10)
恢复        1199→26    0      800      95        1
```

- `pending` 峰值 **1199 > capacity 1000**（超出 199，19.9%）
- `failed_total` **始终为 0** —— 500 是可重试错误，不计永久失败
- `enqueue_retries` 持续上涨 → 队列满的直接信号

### E2 决定性对照（receiver 侧真值）

| 阶段 | 时长 | 请求速率 | sent 速率 |
|---|---|---|---|
| 正常基线 | 40s | 6.62 次/秒 | 662.4 样本/秒 |
| 500 故障 | 60s | 12 次（全部被拒） | — |
| 恢复 | 60s | **13.27 次/秒（2.00x）** | **1299.9 样本/秒（1.96x）** |

**恢复期速率恰好是正常的 2 倍** —— 60 秒积压在 60 秒内以 2 倍速率追平，积压被完整补发。

### WAL 兜底

- remote write **没有独立 WAL 目录**，复用 TSDB 的 `/prometheus/wal`（通过 WAL watcher 读取）
- 实测 WAL 截断 `truncations_total = 0`（观察 3 分钟未截断），截断由 TSDB 保留期（本例 2h）驱动，**与发送确认解耦**
- 目录结构：`/prometheus/wal` + `/prometheus/chunks_head`，无 remote write 专属目录

## 知识点 2：remote read

### 配置字段（promtool 校验确认存在）

`read_recent`、`required_matchers`（类型 LabelSet，非 bool）、`filter_external_labels`、`remote_timeout`（默认 1m）、`chunked_read_limit`（默认 50000000）

### 关键坑：失败是静默的

VictoriaMetrics **单节点版不支持** `/api/v1/read`，返回 400：

```json
{"status":"success","data":{"resultType":"vector","result":[]},
 "warnings":["remote_read: remote server http://l7-vm:8428/api/v1/read
              returned http status 400 Bad Request: unsupported path requested"]}
```

**`status` 仍是 `success`**，空结果只在 `warnings` 里说明。这是"remote read 配了却查不到"的头号原因。

### 生效验证（后端换成 Prometheus）

- `l7-reader` 本地**不抓** l7-app（其 `up` 里只有 reader-self）
- 却查到 **500 条** `l7_card_balance` → remote read 生效

### 代价

| 目标 | 中位耗时 |
|---|---|
| backend（本地查） | 1.6 ms |
| reader（remote read） | 4.4 ms |
| **倍数** | **2.69x** |

### external_labels 的三段式行为（实测）

1. **remote write 时**：external_labels 被**附加**到样本
   - VM 实际标签：`{__name__, cluster="l7-lab", idx, instance, job, region, replica="0"}`
2. **remote read 时**：external_labels 被**附加**到选择器（只取回自己写的）
3. **返回 PromQL 前**：external_labels 被**剥离**
   - reader 返回：`{__name__, idx, instance, job, region}` ← cluster/replica 消失了
4. **用户显式指定该 label 时**：跳过自动处理
   - `l7_card_balance` → 500 条
   - `l7_card_balance{cluster="l7-lab"}` → **0 条**

## 知识点 3：Agent 模式

### 两个必须纠正的预设

1. **`--agent` 是独立 flag**，不是 `--enable-feature=agent`。后者是 3.0 之前的写法（实测 `--help` 输出：`--[no-]agent  Run Prometheus in 'Agent mode'`）
2. **Agent 拒绝任何 `rule_files`，包括 recording rules**
   - 实测：`err="field rule_files is not allowed in agent mode"`，进程退出
   - 官方文档原文：*"Recording rules are not possible. You can not pre-summarize data for sending to remote write."*
   - **课 7 原规划写的"保留 recording rules"是错的**

### 能力边界（HTTP 状态码实测）

| 能力 | Agent | Server |
|---|---|---|
| `/api/v1/query` | **422** | 200 |
| `/api/v1/labels` | **422** | 200 |
| `/api/v1/rules` | **422** | 200 |
| `/api/v1/alertmanagers` | **422** | 200 |
| `/api/v1/targets` | 200 | 200 |
| `/api/v1/status/config` | 200 | 200 |
| `/api/v1/status/flags` | 200 | 200 |
| `/api/v1/metadata` | 200 | 200 |
| `/metrics` | 200 | 200 |

**422 而非 404** —— 路径存在但当前模式禁用。

### 本地 TSDB 指标

| 指标 | Agent | Server |
|---|---|---|
| `prometheus_tsdb_head_series` | **不存在** | 1507 |
| `prometheus_tsdb_head_chunks` | **不存在** | 10091 |
| `prometheus_tsdb_wal_storage_size_bytes` | 276507 | 8261972 |

### 资源占用（同起点、同配置、507 条序列）

> ⚠️ 首次测量（Server 43 分钟 vs Agent 13 分钟）得出 -37% / -97% / 32 倍，
> **已作废**——那比的是运行时长，不是模式差异。以下为同起点修正值。

| 项 | Server | Agent | 差异 |
|---|---|---|---|
| 内存（15 分钟） | 60.49 MiB | 45.17 MiB | **-25%** |
| 磁盘（15 分钟） | 3980 KB | 3392 KB | -15%（1.2x） |
| 磁盘（45 分钟） | 27800 KB | 17024 KB | **-39%（1.63x）** |

**40 分钟连续观测**（每 5 分钟采样，单位 KB）：

```text
时刻    server总  server_wal  chunks_head  agent总   倍数
21:17    13128      9004        4100       7872    1.67x
21:27    15776     11652        4100      10176    1.55x
21:42    19736     15612        4100      13632    1.45x
21:47    25156     16936        8196      14784    1.70x
21:57    27800     19580        8196      17024    1.63x
```

**关键观察**：45 分钟内**两侧都没有回收磁盘**。WAL 只增不减，直到保留期触发截断。
倍数在 1.45x~1.70x 之间波动（随 chunks_head 从 4100→8196 跳变而跳变）。

### 故障场景对照（503 持续 420 秒，配置已统一）

| 阶段 | Server | Agent |
|---|---|---|
| 基线 | 4112 KB | 3584 KB |
| 故障 420s | 5924 KB（+1812） | 5120 KB（+1536） |
| 恢复 240s | 6984 KB（较峰值 +1060） | 6016 KB（较峰值 +896） |

故障期队列（**两侧完全一致**，证明 pending 上限由 `capacity` 决定而非模式）：

```text
server pending = 1199
agent  pending = 1199      ← 配置统一后一致
agent  enqueue_retries_total = 26
agent  samples_failed_total  = 0      ← 503 可重试
```

> 修正前测到 agent pending=2999，是因为 agent.yml 用了 `capacity: 2000`
> 而 prometheus.yml 用 `capacity: 1000`。**不是模式差异。**

### Agent 的存储参数（实测 flags）

```
--storage.agent.path=/data-agent
--storage.agent.retention.max-time=4h
--storage.agent.retention.min-time=5m
--storage.agent.wal-compression=true  (type=snappy)
```

即：Agent 的 WAL 最多保留 **4 小时**，断网超过 4 小时就会丢数据。

### 自监控悖论

Agent 禁用了查询 API，所以**无法查自己的 remote write 指标**。
解法：**从 /metrics 直接读，或从外部 Prometheus 抓**。
实测 Agent `/metrics` 可访问，702 条指标，含完整 `prometheus_remote_storage_*` 系列。
