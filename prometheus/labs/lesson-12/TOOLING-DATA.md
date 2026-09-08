# 课 12 数据底稿：运维工具链与排障

> 所有数字均为本机（WSL + Docker，Prometheus **v3.14.0**）实测。
> 复现脚本：`labs/lesson-12/exp*.sh`。

---

## 0. 环境

| 项 | 值 |
|---|---|
| Prometheus 版本 | v3.14.0（revision d7598b7141418fa35be2b5ec5d0fefb634199610，go1.26.6） |
| 实验网络 | `l12net` |
| 主实例端口 | 19500（l12-prom）、19501（l12-prom2 故障实例） |
| 对照实验端口 | 19510（A，删除）、19511（B，不删） |
| 造数 app | `l12-app`（手写文本格式，2 万序列，指标名 `l12_series`） |
| 慢响应 app | `l12-slow`（sleep 3s 后返回，用于超时故障） |
| 启动参数 | `--web.enable-admin-api --web.enable-lifecycle --storage.tsdb.retention.time=1h` |

> **注意**：`l12-renderer`、`l12-pg`、`l12-final` 是**其他课程占用**的容器
> （已运行 3 天/5 小时），与课 11 遇到的 `l11` 前缀冲突同类，不影响本课实验。

---

## 1. 知识点 1：promtool 工具链

### 1.1 `check config` 拦截能力（exp1-checkconfig.sh）

| 配置文件 | 内容 | 结果 | exit |
|---|---|---|---|
| `good.yml` | 正确 | `SUCCESS: ... is valid prometheus config file syntax` | 0 |
| `bad-timeout.yml` | `scrape_timeout: 60s` > `scrape_interval: 15s` | `FAILED: scrape timeout greater than scrape interval for scrape config with job name "demo"` | 1 |
| `bad-yaml.yml` | 缩进错误 | `FAILED: yaml: line 5: mapping values are not allowed in this context` | 1 |
| `bad-relabel.yml` | relabel 引用 `__meta_nonexistent__` | **`SUCCESS`** | **0** |

**结论**：拦语法与静态语义；**不查标签是否真实存在**。

### 1.2 `check rules`（exp2-test-rules.sh）

```
Checking /r/disk.yml
  SUCCESS: 1 rules found
```

### 1.3 `test rules` 拦错能力（exp2 / exp2b）

| 用例 | 期望 | 结果 |
|---|---|---|
| 正向（磁盘每分钟掉 1GB） | 10m 时触发 | `SUCCESS` |
| **反向**（故意写成"不触发"） | `exp_alerts: []` | **FAILED**，报 `exp:[]` vs `got:[DiskWillFillIn6h...]`，exit=1 |
| 边界（磁盘恒定 `+0x59`） | 不触发 | `SUCCESS` |

反向用例的完整报错：

```
  FAILED:
    alertname: DiskWillFillIn6h, time: 10m,
        exp:[],
        got:[
            0:
              Labels:{alertname="DiskWillFillIn6h", mountpoint="/", severity="warning"}
              Annotations:{summary="disk will fill in 6h"}
            ]
```

**结论**：`test rules` 有真实拦错能力，不是"能跑通"而已。

**踩坑**：`input_series` 的 values 格式写错会报
`parse error: unexpected " " in series values`。
正确格式：`'100000000000-1000000000x59'`（起始值 + 负步长 x 次数）。

### 1.4 `check metrics`（exp3 / exp3b）

| 样本 | 结果 |
|---|---|
| 含重复 HELP 行 | `error while linting: text format parsing error in line 5: second HELP line for metric name "http_requests_total"`，exit=1 |
| 同上，`--extended` | **同样在第 5 行报错，后续问题不再输出** |
| 干净样本 | exit=0（无输出） |
| 干净样本 `--extended` | 输出基数表：`rpc_duration_seconds 4 (57.14%)` / `http_requests_total 3 (42.86%)` / `Total 7` |

对运行中 Prometheus 自身指标（1253 行）跑 `--extended`：

- 先报 5 条命名违规：
  - `prometheus_engine_query_duration_histogram_seconds` metric name should not include type 'histogram'
  - `prometheus_rule_evaluation_duration_histogram_seconds` （同上）
  - `prometheus_rule_group_duration_histogram_seconds` （同上）
  - `prometheus_target_interval_length_histogram_seconds` （同上）
  - `prometheus_target_sync_length_histogram_seconds` （同上）
- 再出基数 Top 表，前三：
  - `prometheus_http_requests_total` 63 (8.41%)
  - `prometheus_http_request_duration_seconds` 36 (4.81%)
  - `prometheus_http_response_size_bytes` 33 (4.41%)

**结论**：`--extended` 增加基数分析输出；lint **遇错即停**；
连 Prometheus 自身也有 5 条命名违规。

### 1.5 `check healthy` / `check ready`（exp14 / exp14b / exp14c / exp14d）

| 调用 | 结果 |
|---|---|
| `check healthy http://l12-prom2:9090` | `promtool: error: unexpected http://l12-prom2:9090, try --help` |
| `check healthy --help` | 只有 `--http.config.file`、`--query.lookback-delta`；**无 `<server>` 位置参数** |
| `check healthy --http.config.file=<空>` | `Get "http://localhost:9090/-/healthy": dial tcp [::1]:9090: connect: connection refused` |
| `check healthy --http.config.file=<带 http_client_config>` | `yaml: unmarshal errors: line 1: field http_client_config not found in type config.plain` |
| 对照 `query instant http://l12-prom2:9090 'up'` | ✅ 正常返回两条 |

**结论**：`check healthy/ready` **只连硬编码的 `localhost:9090`**，不接受 URL；
`query instant/series` 才接受 server 参数。

### 1.6 TSDB 子命令（exp10 / exp11）

| 命令 | 结果 |
|---|---|
| `tsdb list /data` | 空表（只有表头）——运行中实例 head 未落盘，blocks=0 |
| `tsdb create-blocks-from openmetrics` **缺 `# EOF`** | `getting min and max timestamp: next: data does not end with # EOF` |
| 同上，**补 `# EOF` 后** | 成功生成 **60 个 block**，每个 200 序列 / 200 样本 / 20 760 bytes |
| `tsdb analyze` | `Total Series: 200` / `Label names: 3` / `Postings (unique label pairs): 204` / `Postings entries: 600`；churn Top：`__name__=l12_demo 200`、`zone=z0 67`、`zone=z1 67`、`zone=z2 66` |

---

## 2. 知识点 2：TSDB 管理与 admin API

### 2.1 snapshot（exp4）

```
POST /api/v1/admin/tsdb/snapshot
→ {"status":"success","data":{"name":"20260907T081354Z-1c2d1d7b596620c8"}}
落盘：/prometheus/snapshots/20260907T081354Z-1c2d1d7b596620c8   2.8M
内容：01M1XEWMZ9B2BMQZMN12ZNS951（一个 block 目录）
```

### 2.2 delete_series 全过程（exp8，干净环境 2 万序列）

| 阶段 | `count(l12_series)` | headSeries | 磁盘 (KB) |
|---|---|---|---|
| 基线（app 在跑） | 20 000 | 20 736 | 676 |
| 停 app 后 | 20 000 | 20 782 | — |
| **删除后** | **empty** | 20 782 | 1 236 |
| **clean_tombstones 后** | empty | 20 830 | 1 236 |
| **重启后** | **empty** | 20 830 | 1 108 |

### 2.3 为什么磁盘不释放（exp6）

```
/prometheus/
├── chunks_head/   0 KB
├── wal/           3 376 KB
└── (无 01* block)
```

`blocks = 0` —— 数据全在 head + WAL，`clean_tombstones` 只处理**已落盘 block**。

### 2.4 对照实验：删除到底让磁盘涨了多少（exp15b）

两个**完全相同**的实例，app 已停，只有 self-scrape：

| 实例 | 操作 | 磁盘 |
|---|---|---|
| A | 执行 `delete_series` | 1 172 KB |
| B | 不删 | 1 172 KB |
| **差值** | | **0 KB** |

> **推翻初判**：早期观察"删除后 676 → 1236 KB"一度被解读为"删除导致磁盘反涨"。
> 对照实验证明**净增 0 KB**，之前的涨幅是 self-scrape 自然增长。
> 正确结论：**不释放**。

### 2.5 "数据复活"误判的纠正（exp7 / exp7b / exp16 / exp16b / exp17）

**现象**：删除后 count = empty，重启后 count = 20 000，一度判为"tombstone 未持久化"。

**真因**：app 仍在运行。`delete_series` **只删删除时点之前的历史**，
不阻止新样本入库，重启后新一轮抓取使 count 回填。

**决定性验证**（exp17，停 app 后用 **range 查询**绕开 staleness）：

只删 `idx=~"00000.*"`（1000 条），A 删 / B 不删：

| 实例 | `count(l12_series)` | `count(idx=~"00000.*")` 数据点数 |
|---|---|---|
| A（已删） | 20 000（last） | **1**（在删除时点截断） |
| B（未删） | 20 000（last） | **3** |

A 的序列在删除时刻从 3 点截断到 1 点 → **删除确实精准生效**。

> **方法论**：验证删除是否生效，**必须先切断数据源**；
> 且停掉 target 后要用 **range 查询**（instant 会因 staleness 返回空）。

### 2.6 `match[]` 的两个实测限制

| 写法 | 结果 |
|---|---|
| `?match[]={__name__="l12_series"}`（URL 直接拼） | `invalid parameter "match[]": 1:9: parse error: unexpected "="` —— 引号被 shell 吞掉 |
| `--data-urlencode 'match[]=l12_series'` | ✅ HTTP 204 |
| `match[]=l12_series{idx<"00001000"}` | `parse error: unexpected character inside braces: '<'` —— **不支持比较符** |
| `match[]=l12_series{idx=~"00000.*"}` | ✅ HTTP 204 |

**结论**：只支持 `=` `!=` `=~` `!~`；范围删除请用正则。

### 2.7 `--storage.tsdb.max-series-per-*` 已移除（exp9 / exp9b）

```
$ prometheus --storage.tsdb.max-series-per-metric=1000
Error parsing command line arguments: unknown long flag '--storage.tsdb.max-series-per-metric'
prometheus: error: unknown long flag '--storage.tsdb.max-series-per-metric'
```

3.14.0 的 `storage.tsdb.*` flag **只剩 6 个**：

```
--storage.tsdb.path
--storage.tsdb.retention.time
--storage.tsdb.retention.size
--[no-]storage.tsdb.no-lockfile
--storage.tsdb.head-chunks-write-queue-size
--storage.tsdb.delay-compact-file.path
```

**无任何序列数硬限制**。防基数爆炸只能靠抓取端
（`metric_relabel_configs` / `sample_limit` / `label_limit`）。

---

## 3. 知识点 3：排障方法论

### 3.1 构造的故障（exp13）

- app：`/metrics` 先 `time.sleep(3)` 再返回
- 配置：`scrape_interval: 5s`，`scrape_timeout: 1s`

### 3.2 倒查链实测

| 步骤 | 观察 | 数值 |
|---|---|---|
| 1. targets | `job=slowapp health=down` | `err=Get "http://l12-slow:8000/metrics": context deadline exceeded` |
| 2. `up` | `up=0 job=slowapp`（`up=1 job=prometheus`） | 影响范围为单 target |
| 3. `scrape_duration_seconds` | `1.000991574` (slowapp) / `0.005304745` (prometheus) | **≈ timeout 阈值，被截断** |
| 4. 源站真实耗时 | `time wget` → `real 0m 5.99s` | 真实 5.99s ≫ 1s |

### 3.3 核心陷阱

> **超时发生时 `scrape_duration_seconds` 记录的是 timeout 阈值，不是真实耗时。**
> 实测：指标 1.0009s vs 真实 5.99s（差 6 倍）。
> 因此 target down 时，该指标**不能用来排除超时**——它是自证循环。

### 3.4 倒查顺序（实测有效）

```
1. /-/healthy + /-/ready        → Prometheus 自身活着吗
2. /api/v1/targets 的 lastError  → 哪个 target、什么错
3. up 指标                       → 影响范围
4. 配置里的 scrape_timeout       → 与实测耗时比对
5. 绕过 Prometheus 直接测源站     → ground truth（关键）
```

---

## 4. 挂账清偿汇总

| 来源 | 挂账内容 | 本课结论 | 状态 |
|---|---|---|---|
| 课 10 | 删除高基数指标后磁盘未释放的 tombstone 实测 | 对照实验净增 **0 KB = 不释放**；需落盘 + clean | ✅ 清偿 |
| 课 11 | tombstone / `cleanTombstones` 后磁盘何时真正释放 | 对 head 数据**无效**（blocks=0）；block 场景未测到 | ✅ 部分清偿 |
| 课 10 | `--storage.tsdb.max-series-per-*` 触发行为 | **3.14.0 已移除**（unknown long flag） | ✅ 清偿 |
| 课 11 | `--storage.tsdb.max-series-per-*` 硬限制行为 | 同上 | ✅ 清偿 |
| 课 11 | compaction 后 block 的真实磁盘占用 | **未拿到**（运行中实例需 2h 落盘，`max-block-duration` 已移除） | ⚠️ 继续挂账 |

---

## 5. 诚实标注：本课未测出的

1. **运行中实例的 block 落盘后磁盘占用**
   —— 用 `tsdb create-blocks-from` 离线造了 block 并 `analyze`，
   但运行中实例 2 小时才落盘，3.14.0 又移除了 `max-block-duration` 无法强制触发。
   课 11 的磁盘数字仍是 **WAL 口径**。
2. **`clean_tombstones` 对真实 block 的回收效果**
   —— 本课 blocks=0，只证明了"对 head 无效"，**未证明"对 block 有效"**。
3. **`tsdb bench write` 的写入基准**
   —— 子命令存在，但本机 WSL + 挂载盘 IO 参考值有限，未纳入结论。

---

## 6. 复现脚本索引

| 脚本 | 内容 |
|---|---|
| `setup.sh` | 构建 `l12-app` 造数镜像 |
| `up.sh` | 启动主实例（19500，带 admin API） |
| `exp1-checkconfig.sh` | check config 四类配置 |
| `exp2-test-rules.sh` / `exp2b-negative.sh` | 规则检查与正/反向单测 |
| `exp3-checkmetrics.sh` / `exp3b-metrics2.sh` | check metrics lint 与基数 |
| `exp4-tsdb.sh` | TSDB 状态 + snapshot |
| `exp5-delete.sh` / `exp8-clean-e2e.sh` | delete_series 全流程 |
| `exp6-why.sh` | 查证磁盘不释放的原因 |
| `exp7-restart.sh` / `exp7b-restart2.sh` | 重启行为（初判"复活"） |
| `exp9-serieslimit.sh` / `exp9b-flags.sh` | max-series-per-* 查证 |
| `exp10-tsdbtools.sh` / `exp11-analyze.sh` | tsdb list / create-blocks-from / analyze |
| `exp13-fault-timeout.sh` | 构造超时故障 |
| `exp14*-healthy*.sh` | check healthy/ready 行为查证 |
| `exp15*-control*.sh` | 磁盘对照实验 |
| `exp16*-partial.sh` / `exp17-decisive.sh` | 部分删除的决定性验证 |
| `verify-l12.sh` | 交付终验 |
