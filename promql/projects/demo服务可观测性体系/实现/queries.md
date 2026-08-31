# 查询清单 · demo 服务可观测性体系

> **全部条目已在演练场实测**（备课当场抓取，数值随环境流量呼吸波动，看量级与形态）。
> 打开 https://demo.promlens.com/ 逐条粘贴执行。
> 约定：所有查询都带 `job="demo"` 收窄——不带会把监控组件自己的序列算进来（`up` 全局实测 6 行，只有 3 行是 demo）。

## 第 0 组：先摸清家底

```promql
# 0.1 服务有几个实例、都活着吗
up{job="demo"}
# 预期：3 行，值均为 1（demo-service-0/1/2）

# 0.2 序列总量（基数审计基线）
count(demo_api_request_duration_seconds_count{job="demo"})
# 预期：27 行值 = 27

# 0.3 基数按路径分布
count by (path) (demo_api_request_duration_seconds_count{job="demo"})
# 预期：/api/foo=12  /api/bar=12  /api/nonexistent=3
# 解读：foo/bar 各 12 = 3 实例 × 2 method × 2 status；nonexistent 只有 GET（无 POST）

# 0.4 桶边界摸底（本项目最关键的一步）
count by (le) (demo_api_request_duration_seconds_bucket{job="demo"})
# 预期：26 个 le 取值，各 27 行
# ⚠️ 重点确认：le=0.09852612533569335 与 le=0.14778918800354002 之间**没有 0.1**
```

> 💡 **为什么先做 0.4**：SLO 想定「100ms」，但桶是 ×1.5 递增的，**没有 100ms 这一档**。先摸清桶边界，才能决定 SLO 用什么口径表达（见设计决策 1）。

---

## 第 1 组：流量（Traffic）

```promql
# 1.1 总 QPS
sum(rate(demo_api_request_duration_seconds_count{job="demo"}[5m]))
# 预期：约 130（实测区间 129~237，随环境呼吸）

# 1.2 分路径 QPS（面板图例用）
sum by (path) (rate(demo_api_request_duration_seconds_count{job="demo"}[5m]))
# 预期：3 行，foo ≈ 129 量级最大，bar 次之，nonexistent 约 4

# 1.3 分方法 × 路径 QPS（告警降噪的主体维度）
sum by (method, path) (rate(demo_api_request_duration_seconds_count{job="demo"}[5m]))
# 预期：5 行（nonexistent 无 POST）
```

---

## 第 2 组：错误（Errors）

```promql
# 2.1 全站错误率（%）
sum(rate(demo_api_request_duration_seconds_count{job="demo",status=~"5.."}[5m]))
  / sum(rate(demo_api_request_duration_seconds_count{job="demo"}[5m])) * 100
# 预期：约 0.83%
# ⚠️ 这个数字看着很安全——但它是被稀释过的，继续看 2.2

# 2.2 分方法×路径错误率（%）——本项目的核心洞察
sum by (method, path) (rate(demo_api_request_duration_seconds_count{job="demo",status=~"5.."}[5m]))
  / sum by (method, path) (rate(demo_api_request_duration_seconds_count{job="demo"}[5m])) * 100
# 预期：4 行
#   POST /api/foo = 2.56%   POST /api/bar = 2.24%
#   GET  /api/foo = 0.74%   GET  /api/bar = 0.38%
# 💡 全站 0.83% 风平浪静，POST 类接口却已 2.5% —— 这就是"聚合过度把信号也降没了"

# 2.3 错误请求绝对量（判断是"比例高"还是"量也大"）
sum by (method, path) (rate(demo_api_request_duration_seconds_count{job="demo",status=~"5.."}[5m]))
# 预期：4 行 QPS 值。配合 2.2 看：比例高但绝对量小 → 优先级可下调
```

> 📌 **知识点**：`status=~"5.."`（L5 正则）｜两侧 `by` 标签必须一致（L9）｜`rate` 窗口 `[5m]`（L8）

---

## 第 3 组：延迟（Latency）

```promql
# 3.1 全站 P95（毫秒，面板主曲线）
histogram_quantile(0.95, sum by (le) (rate(demo_api_request_duration_seconds_bucket{job="demo"}[5m]))) * 1000
# 预期：约 52 ms（实测 1h 区间 51.2~54.9）
# ⚠️ 必须 sum by (le) 先聚合 —— 否则 27 行各自算分位数且不可加总（L10）

# 3.2 分路径 P95（毫秒）
histogram_quantile(0.95, sum by (le, path) (rate(demo_api_request_duration_seconds_bucket{job="demo"}[5m]))) * 1000
# 预期：/api/bar ≈ 62.5  /api/foo ≈ 27.2  /api/nonexistent ≈ 0.095
# 💡 bar 比 foo 慢一倍多，但全站 52ms 把两者混在一起看不出结构

# 3.3 平均延迟（毫秒）—— 与 P95 对照看分布右偏
sum(rate(demo_api_request_duration_seconds_sum{job="demo"}[5m]))
  / sum(rate(demo_api_request_duration_seconds_count{job="demo"}[5m])) * 1000
# 预期：约 17.4 ms
# 💡 平均 17.4 < P95 52 → 右偏分布：少数慢请求把尾部拉长（L10）

# 3.4 P99（毫秒）
histogram_quantile(0.99, sum by (le) (rate(demo_api_request_duration_seconds_bucket{job="demo"}[5m]))) * 1000
# 预期：约 65.3 ms
```

---

## 第 4 组：SLO 合规率（桶占比口径）

> 用 `le="0.09852612533569335"` 近似「100ms」——这是**最接近且真实存在**的桶（实测阶梯无 0.1）。

```promql
# 4.1 全站合规率（%）
sum(rate(demo_api_request_duration_seconds_bucket{job="demo",le="0.09852612533569335"}[5m]))
  / sum(rate(demo_api_request_duration_seconds_count{job="demo"}[5m])) * 100
# 预期：99.12%

# 4.2 全站违规率（%）—— 4.1 的互补，告警用这个
100 - sum(rate(demo_api_request_duration_seconds_bucket{job="demo",le="0.09852612533569335"}[5m]))
  / sum(rate(demo_api_request_duration_seconds_count{job="demo"}[5m])) * 100
# 预期：0.88%

# 4.3 分路径合规率（%）—— 找出不达标的那一个
sum by (path) (rate(demo_api_request_duration_seconds_bucket{job="demo",le="0.09852612533569335"}[5m]))
  / sum by (path) (rate(demo_api_request_duration_seconds_count{job="demo"}[5m])) * 100
# 预期：/api/foo = 100%  /api/nonexistent = 100%  /api/bar = 97.66%
# 🎯 只有 /api/bar 不达标 —— 全站 P95 52ms 完全看不出这件事

# 4.4 违规请求的绝对 QPS（判断影响面）
sum(rate(demo_api_request_duration_seconds_count{job="demo"}[5m]))
  - sum(rate(demo_api_request_duration_seconds_bucket{job="demo",le="0.09852612533569335"}[5m]))
# 预期：约 1.14 QPS
# 💡 违规率 0.88% 听着小，但每秒有 1.14 个真实用户在等超时
```

> 📌 **为什么用桶占比而不是 P95 判 SLO**：① 桶占比**可加**，任意维度切片都对得上；② P95 受桶边界精度限制（100ms 无对应桶）。详见 [设计决策.md](../设计决策.md) 决策 1。

---

## 第 5 组：饱和度（Saturation）

```promql
# 5.1 CPU 使用率（%）—— group_left 多对一广播
sum by (instance) (rate(demo_cpu_usage_seconds_total{mode!="idle"}[5m]))
  / on (instance) group_left demo_num_cpus * 100
# 预期：3 行，均约 49.4%~50.0%
# 💡 这是 L7 的 group_left 主力场景：左边按 instance 聚合（3 行），右边 demo_num_cpus 每实例 1 条（值 4）

# 5.2 磁盘水位（%）—— 默认匹配（标签天然对齐）
sum by (instance) (demo_disk_usage_bytes) / on (instance) group_left sum by (instance) (demo_disk_total_bytes) * 100
# 预期：3 行，均约 82.0%~82.1%
# ⚠️ 82% 已是需要关注的水平（容量告警阈值通常设 80~85%）

# 5.3 内存占用（按 type 看构成）
demo_memory_usage_bytes{job="demo"}
# 预期：12 行（3 实例 × used/free/cached/buffers）
```

> 📌 **知识点**：`group_left` 广播（L7）｜`{mode!="idle"}` 排除空闲（L5）｜Gauge 不用 rate（L3/L8 反例）

---

## 第 6 组：告警与成本审计

```promql
# 6.1 当前 firing 的告警（按名称计数）
count by (alertname) (ALERTS{alertstate="firing"})
# 预期：DemoServiceHighErrorRate = 2  DemoServiceHighLatency = 1

# 6.2 告警全貌（含 pending）
ALERTS
# 预期：4 行，能看到 alertname/alertstate/job/method/path/severity 全套标签
# 💡 演练场预置规则正是分路径粒度 —— 与本项目决策 3 一致

# 6.3 规则评估耗时（Prometheus 自身健康度）
prometheus_rule_evaluation_duration_seconds{quantile="0.99"}
# 预期：约 0.0063 秒

# 6.4 基数爆炸检测（告警用）
count(demo_api_request_duration_seconds_count{job="demo"}) > 50
# 预期：0 行（当前 27，安全）。若某天返回非空 → 有人往标签里塞了高基数字段
```

---

## 📊 成本审计表（L12 口径）

对上面每条查询问一句「它有多贵」。核心数字（L12 实测）：

| 查询类型 | 单步读取样本 | 6h@60s 面板单次 | 处置 |
|------|------|------|:---:|
| P95 流水线 | **14,040** | **5,068,440** | ⚠️ 必须预聚合 |
| 分路径错误率（分子+分母） | ~1,080 | ~390,000 | ⚠️ 建议预聚合 |
| QPS | 540 | ~195,000 | ⚠️ 建议预聚合 |
| 单条 rate 查询 | 540 | ~195,000 | 可直算 |
| `count(ALERTS)` | 个位数 | 极小 | 可直算 |
| 内存/磁盘（Gauge） | 12 条序列 | 极小 | 可直算 |

> 💡 判断口诀：**看单步读取样本数，不看输出行数**。P95 只输出 1 行，却是全场最贵（L12 成本第一定律）。

> ⚠️ **口径说明（别和 L12 的数字搞混）**：
> - 本表的「5,068,440」= **服务端读取的样本数**（`?stats=all` 的 `totalQueryableSamples`）= 单步 14,040 × 361 步
> - L12 里「253,422 点 / 1,011,582 点」= **返回给客户端的数据点数**（行数 × 每序列点数）
> 两者是**两笔不同的账**：前者是厨房翻了多少菜（服务器成本），后者是你端走多少盘（传输与渲染成本）。
> 优化查询时盯前者，优化面板卡顿时盯后者。

---

## 🚀 下一批接力提示词

> 完成本项目后，**复制下面这段文字发给 AI**，即可进入 Phase 5（实战经验与排障速查手册）：

```
继续学 PromQL。我的学习档案在 promql/00-学习档案.md，
已完成全部 12 课与结课实战项目（demo 服务可观测性体系），
请生成实战经验与排障速查手册（Phase 5）。
```
