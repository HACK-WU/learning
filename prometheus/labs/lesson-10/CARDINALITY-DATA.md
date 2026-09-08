# 课 10 实测数据底稿：基数治理

> 所有数值均为本机实测（Prometheus v3.14.0 + 自建造数 app），非引用经验公式。
> 环境：WSL Ubuntu + Docker，网络 `l10net`，Prometheus 端口 19440。

## 0. 环境说明与一处查证

- Prometheus：`prom/prometheus:v3.14.0`
- 造数 app：Python + `prometheus_client==0.21.1`，可分别开启四类基数来源

> ⚠️ **2026-09-07 更正**：上面这个判断是**错的**。课 11 查证出真实原因是
> **当时配置里没有 self-scrape job**——Prometheus 没抓自己，所以一个 `prometheus_*`
> 指标都没有。加上 self-scrape 后实测指标数 6 → 328，该指标正常返回。
> **方法建议仍成立**（状态 API 不依赖抓取链路），但"指标不存在"这个说法必须撤回。

**查证 1（原记录，已作废）**：`prometheus_tsdb_head_series` 指标在本环境**查询返回空**。
实测 `/api/v1/label/__name__/values` 中**不存在**任何 `prometheus_tsdb_*` 指标
（返回的 18 个指标里只有 `up`、`scrape_*`、`process_*`、`python_*`）。

→ 原结论：改用 `/api/v1/status/tsdb` 取序列数。
→ **修正后**：状态 API 依然推荐（不依赖 self-scrape），但**不是因为指标不存在**。

## 1. 实验 1：标签值失控的序列放大（确定性数据）

每个场景**重建 Prometheus**（清空 TSDB）以测真实增量（重要：不重建会测到累积值，
我曾因此得到四个场景都是 8021 的假数据）。

| 场景 | 序列数 | 说明 |
|---|---|---|
| A 仅基线（低基数） | 21 | 只有 `up`/`scrape_*`/`process_*`/`python_*` |
| B +5000 个 `user_id` | 5 021 | +5 000 |
| C +2000 个 URL 路径 | 2 021 | +2 000 |
| D +1000 个 `request_id` | 1 021 | +1 000 |

**序列数是确定性、可精确预测的**：加 N 个标签值就多 N 条序列（1:1）。
这正是基数治理的第一个可计算事实——`序列数 = 标签值组合数`。

## 2. 实验 1b：内存测不准（诚实记录失败）

同一实验重复 3 轮，取内存：

| 轮次 | A 基线 | B +5000 user | C +2000 url | D +1000 reqid |
|---|---|---|---|---|
| 1 | 33.91 | 36.20 | 34.01 | 34.36 |
| 2 | 31.43 | 36.23 | 34.85 | 33.84 |
| 3 | **38.79** | 38.55 | 33.79 | 32.94 |

**结论：测不出可信结论。** 基线自身在 31.43 ~ 38.79 MiB 之间波动（GC 时机），
第 3 轮基线（38.79）甚至高于 B 场景（38.55）。

进一步做**受控实验**：固定 5000 条序列，只改标签值长度（8 / 64 / 256 字符）：

| 标签值长度 | 序列数 | 内存 MiB |
|---|---|---|
| 8 字符 | 5 021 | 38.61 |
| 64 字符 | 5 021 | 40.05 |
| 256 字符 | 5 021 | **35.11** |

256 字符反而最低——**连标签长度这一因子都淹没在噪声里**。

→ **本课不给"每条序列占多少内存"的数字**。要测出它需要 10 万级以上序列 + 多次采样 +
关闭 GC 干扰，本机规模不够。宁可标注"未实测"，也不编造系数。
（课 11《容量规划与调优》会专门用更大规模重测这一项。）

## 3. 实验 2：诊断高基数（知识点 2，全部实测可用）

混合场景：500 user + 2000 url + 1000 reqid + 直方图。

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

```
curl -s localhost:19440/api/v1/status/tsdb
  numSeries     = 3578
  numLabelPairs = 3552
  chunkCount    = 3578
  seriesCountByMetricName:
    card_bad_by_url          2000
    card_bad_by_reqid        1000
    card_bad_by_user          500
    card_hist_seconds_bucket   36
    card_hist_seconds_created   3
```

**方式三：逐标签定位**

```
curl -s 'http://localhost:19440/api/v1/series?match[]=card_bad_by_user'
  -> 500 条，每条形如
  {__name__="card_bad_by_user", instance="l10-app:8000", job="app", user_id="u000000x"}
```

## 4. 实验 3：直方图桶的放大效应（实测）

单个 histogram 指标 `card_hist_seconds`：

| 展开后指标 | 序列数 |
|---|---|
| `card_hist_seconds_bucket` | **36** |
| `card_hist_seconds_count` | 3 |
| `card_hist_seconds_sum` | 3 |
| `card_hist_seconds_created` | 3 |

配置：3 个 route × 11 个自定义 bucket = 33，加上 `+Inf` 共 12 个桶/route → 3×12 = **36**。

→ **放大倍数 = 桶数**（本例 12x）：1 个 histogram 指标 × 3 route = 3 条逻辑序列，
  实际展开成 **36 条物理序列**（+ `_count`/`_sum`/`_created` 各 3 条）。

**这是最容易被低估的一类放大**：代码里只写了一个 `Histogram()`，
TSDB 里却是几十上百条序列。

## 5. 实验 4：四种控制手段的效果与副作用（核心）

配置四个 job 抓同一个 target，对比效果：

| job | 配置 | health | `up` | 入库序列 | 结论 |
|---|---|---|---|---|---|
| `app-raw` | 无限制 | up | 1 | 3 557 | 对照组，全量 |
| `app-drop` | `metric_relabel_configs` 丢 `card_bad_by_(url\|reqid)` | **up** | **1** | **557** | 精准丢弃 3000 条，target 健康 |
| `app-sample-limit` | `sample_limit: 100` | **down** | **0** | — | **整个 target 抓取失败** |
| `app-label-limit` | `label_limit: 3` | **down** | **0** | — | **整个 target 抓取失败** |

**关键证据（硬失败的实际报错）**：

```
app-sample-limit : health=down  lastError="sample limit exceeded"
app-label-limit  : health=down  lastError="label_limit exceeded
                   (metric: python_gc_objects_collected_total,
                    number of labels: 4, limit: 3)"
```

**两点必须讲清的副作用**：

1. **`sample_limit` / `label_limit` 是硬失败**：不是"截断后继续"，
   而是**整个 target 的这次抓取全部作废**（`up=0`，该 target 所有指标都消失）。
   实测 `app-raw` 抓到 3 573 个样本，`app-sample-limit` 的
   `scrape_samples_scraped` 同样抓了 3 573（说明**抓取动作发生了**），
   但**一条都没入库**。
2. **`label_limit` 会误伤无辜指标**：报错里的指标是
   `python_gc_objects_collected_total`（4 个标签），
   而我们真正想限制的 `card_bad_by_url` 一个字没提。
   **限制是 per-target 全局生效的，不针对某个指标**。

3. **`metric_relabel_configs` 是唯一"温和"的手段**：实测丢掉 3 000 条序列后
   target 仍然 `up=1`，其余指标正常入库（3 557 → 557）。

## 6. 本课数据边界（未实测）

- 每条序列的内存占用系数（规模不足，见第 2 节）
- 10 万级以上序列的查询延迟劣化
- 实例 churn 的时间维度放大（需要长时间运行）
- `--storage.tsdb.max-series-per-*` 系列硬限制的实际触发行为（课 12 用 admin API 时再测）
