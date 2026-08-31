# 服务概览页 · 面板规格表

> **一块面板一个业务问题**。图例里每一行都应该能回答「谁、怎么样了」（L12 黄金法则）。
> 演练场能验证 expr，但**没有单位换算与阈值线**——那两件属于 Grafana，本表按 Grafana 规格写全。

## 页面级配置

| 项 | 值 |
|----|-----|
| 页面标题 | demo 服务概览（SLO 视图） |
| 时间范围默认 | Last 6 hours |
| 刷新间隔 | 30s（**不用 5s**——见下方成本说明） |
| 变量 | `$path`（下拉，取自 `label_values(path)`，含 All 选项） |

> 💡 **为什么刷新 30s 而不是 5s**：L12 实测 P95 面板每 5 秒刷新 = 每分钟 12 次 × 506 万样本 ≈ **每分钟 6,000 万样本读取**。改成 30s 后降到 1,200 万——人眼根本看不出 5s 与 30s 的差异，但服务器账单差 5 倍。**面板刷新频率是最容易被忽略的成本阀门**。

---

## 面板清单（7 块）

### 面板 1 · 总 QPS

| 项 | 值 |
|----|-----|
| 标题 | 请求速率（QPS） |
| 类型 | Time series |
| expr | `sum(rate(demo_api_request_duration_seconds_count{job="demo",path=~"$path"}[5m]))` |
| 图例 | 无（单序列） |
| 单位 | req/s |
| 阈值线 | 无 |
| 为什么 | 总量本身无「超标」概念，阈值留给错误率与延迟 |

> 实测：约 130 QPS（1h 区间 129.6~236.5）

---

### 面板 2 · 分路径 QPS

| 项 | 值 |
|----|-----|
| 标题 | 各路径请求速率 |
| 类型 | Time series（堆叠可选） |
| expr | `sum by (path) (rate(demo_api_request_duration_seconds_count{job="demo"}[5m]))` |
| 图例 | `{{path}}` |
| 单位 | req/s |
| 阈值线 | 无 |
| 为什么 | 看流量结构：哪个接口扛主要流量（容量规划与故障影响面判断） |

> 实测：foo 量级最大，bar 次之，nonexistent 约 4 QPS

---

### 面板 3 · 错误率（分方法×路径）

| 项 | 值 |
|----|-----|
| 标题 | 5xx 错误率 |
| 类型 | Time series |
| expr | `sum by (method, path) (rate(demo_api_request_duration_seconds_count{job="demo",status=~"5.."}[5m])) / sum by (method, path) (rate(demo_api_request_duration_seconds_count{job="demo"}[5m])) * 100` |
| 图例 | `{{method}} {{path}}` |
| 单位 | percent (0-100) |
| 阈值线 | 1% 黄色（SLO）/ 5% 红色（critical） |
| 为什么 | 图例到 method×path 才能定位坏接口；双阈值对应 warning/critical 两级告警 |

> 实测：POST /api/foo 2.56%、POST /api/bar 2.24%、GET /api/foo 0.74%、GET /api/bar 0.38%
> ⚠️ **不要用全站一条**——全站 0.83% 会把 2.56% 的短板稀释掉（设计决策 3）

---

### 面板 4 · 延迟 P95（分路径）

| 项 | 值 |
|----|-----|
| 标题 | 延迟 P95 |
| 类型 | Time series |
| expr | `histogram_quantile(0.95, sum by (le, path) (rate(demo_api_request_duration_seconds_bucket{job="demo"}[5m])))` |
| 图例 | `{{path}}` |
| 单位 | **seconds → milliseconds** |
| 阈值线 | 100ms 红色（SLO 目标线） |
| 为什么 | 「秒」太小人读不了，毫秒是延迟面板的标准单位；100ms 是 L11 定下的 SLO |

> 实测：/api/bar ≈ 62.5ms、/api/foo ≈ 27.2ms、/api/nonexistent ≈ 0.1ms
> 📌 单位换算后显示 62.5 而非 0.0625——这是 Grafana 相对演练场的关键增值

---

### 面板 5 · 延迟 SLO 合规率（分路径）

| 项 | 值 |
|----|-----|
| 标题 | 延迟 SLO 合规率（≤100ms 请求占比） |
| 类型 | Time series |
| expr | `sum by (path) (rate(demo_api_request_duration_seconds_bucket{job="demo",le="0.09852612533569335"}[5m])) / sum by (path) (rate(demo_api_request_duration_seconds_count{job="demo"}[5m])) * 100` |
| 图例 | `{{path}}` |
| 单位 | percent (0-100) |
| 阈值线 | 99% 绿色下限（SLO 目标） |
| 为什么 | **本项目核心面板**：P95 看趋势，合规率做判定。分路径后短板无处可藏 |

> 实测：/api/foo 100%、/api/nonexistent 100%、**/api/bar 97.66%**（唯一不达标）
> 💡 用 `le="0.09852612533569335"` 而非 `le="0.1"`——后者桶不存在，会返回空表（静默失败）

---

### 面板 6 · 资源饱和度（CPU + 磁盘）

| 项 | 值 |
|----|-----|
| 标题 | CPU 使用率 / 磁盘水位 |
| 类型 | Time series（双 Y 轴或两块相邻面板） |
| expr A（CPU） | `sum by (instance) (rate(demo_cpu_usage_seconds_total{mode!="idle"}[5m])) / on (instance) group_left demo_num_cpus * 100` |
| expr B（磁盘） | `sum by (instance) (demo_disk_usage_bytes) / on (instance) group_left sum by (instance) (demo_disk_total_bytes) * 100` |
| 图例 | CPU: `{{instance}} cpu` / 磁盘: `{{instance}} disk` |
| 单位 | percent (0-100) |
| 阈值线 | CPU 80% 黄；磁盘 85% 黄 |
| 为什么 | 饱和度回答「还能撑多久」；两张放一起看资源瓶颈是 CPU 还是 IO |

> 实测：CPU 49.4%~50.0%（3 实例）、磁盘 82.0%~82.1%（已接近预警线）

---

### 面板 7 · 活跃告警数

| 项 | 值 |
|----|-----|
| 标题 | 当前活跃告警 |
| 类型 | Time series（或 Stat） |
| expr | `count(ALERTS{alertstate="firing"})` |
| 图例 | 无 |
| 单位 | short |
| 阈值线 | 无 |
| 为什么 | 数量突变（2→8）本身就是事故信号；Stat 类型一眼看当前值 |

> 实测：1 小时内在 1~3 波动；按名称看是 DemoServiceHighErrorRate(2) + DemoServiceHighLatency(1)

---

## 📐 页面布局（12 栅格）

```text
┌──────────────┬──────────────┬──────────────┬──────────────┐
│  1 总 QPS    │  3 错误率    │  4 延迟 P95  │  7 告警数    │  行1（高3）
├──────────────┴──────────────┼──────────────┴──────────────┤
│  5 SLO 合规率（核心，宽）   │  2 分路径 QPS               │  行2（高4）
├─────────────────────────────┴─────────────────────────────┤
│  6 资源饱和度（CPU + 磁盘）                                │  行3（高4）
└───────────────────────────────────────────────────────────┘
```

> 💡 布局逻辑：**第一行是「现在健康吗」的四块速读**（Stat 式的直觉判断），第二行是「哪里不健康」的定位面板，第三行是「还能撑多久」的容量面板。值班员扫第一行的 3 秒决定要不要往下看。

---

## 💰 面板成本预算表

按 L12 实测口径（6h 范围、60s 步长、单步读取样本数）：

| 面板 | 单步样本 | 6h 点数 | 刷新 30s 时每分钟成本 | 处置 |
|------|------|------|------|:---:|
| 4 延迟 P95 | 14,040 | 361 | 5,068,440 × 2 = ~1,014 万 | ⚠️ 必预聚合 |
| 5 SLO 合规率 | ~1,080 | 361 | ~39 万 × 2 = ~78 万 | 建议预聚合 |
| 3 错误率 | ~1,080 | 361 | ~78 万 | 建议预聚合 |
| 1/2 QPS | 540 | 361 | ~39 万 | 建议预聚合 |
| 6 饱和度 | ~30 | 361 | 极小 | 直算 |
| 7 告警数 | 个位数 | 361 | 极小 | 直算 |

> 📌 预聚合后，面板 4/5/3/1/2 的成本从「每次刷新几十万到 500 万样本」降到「读 1 行预聚合序列」——降幅 2~3 个数量级。详见 [recording-rules.yaml](recording-rules.yaml)。

---

## ✅ 面板验收自查

- [ ] 每块面板的图例每行都能读出业务结论（不是技术标签拼接）
- [ ] 延迟面板单位已换算为毫秒
- [ ] 阈值线来自 SLO（100ms / 99% / 1% / 5%），不是拍脑袋
- [ ] 刷新间隔 ≥ 30s
- [ ] 没有出现 700+ 行的图例（L12 事故标准）
- [ ] 变量 `$path` 已在各面板 expr 中生效
