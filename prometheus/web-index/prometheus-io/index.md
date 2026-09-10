# Prometheus Docs 网页索引

> 起始 URL：https://prometheus.io/docs/
> 生成日期：2026-09-10 · 范围（scope）：/docs（无版本页 + prometheus/latest + alerting/latest；已排除 prometheus/3.14、3.13、3.5 与 alerting/0.34 版本副本共 95 条） · 条目数：110 · 一次性快照
> 只索引不镜像：需要正文时用 web_fetch 打开对应 URL（带锚点直达）
> 课程对齐：课程基线 Prometheus 3.x，PromQL 与告警为两大主线

## 怎么用

1. 按「我要…」列定位条目（不确定先看下方分区索引）
2. 用 web_fetch 打开该条 URL 取细节
3. 本表是快照，链接大面积失效时整站重跑重建（脚本与中间地图见仓库 `temp/`：`build_prometheus-io_web_index.py` / `web-index-prometheus-io-map.md`）

## 高频直达

| 我要… | 去哪一页 | 分区 |
|-------|----------|------|
| 理解四种指标类型（Counter/Gauge/Histogram/Summary） | [concepts/metric_types](https://prometheus.io/docs/concepts/metric_types/) | getting-started |
| 理解 PromQL 基础（选择器/向量/区间） | [querying/basics](https://prometheus.io/docs/prometheus/latest/querying/basics/) | prometheus |
| 查 PromQL 全部函数 | [querying/functions](https://prometheus.io/docs/prometheus/latest/querying/functions/) | prometheus |
| 查 prometheus.yml 全量配置项 | [configuration/configuration](https://prometheus.io/docs/prometheus/latest/configuration/configuration/) | prometheus |
| 写告警规则 | [configuration/alerting_rules](https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/) | prometheus |
| 查 alertmanager.yml 路由树配置 | [alerting/latest/configuration](https://prometheus.io/docs/alerting/latest/configuration/) | alerting |
| 查指标命名规范（命名决定查询效率） | [practices/naming](https://prometheus.io/docs/practices/naming/) | practices-ops |
| 何时用 histogram 还是 summary | [practices/histograms](https://prometheus.io/docs/practices/histograms/) | practices-ops |
| 理解本地存储（TSDB）与保留策略 | [prometheus/latest/storage](https://prometheus.io/docs/prometheus/latest/storage/) | prometheus |
| 查 exporter 清单（接现有中间件） | [instrumenting/exporters](https://prometheus.io/docs/instrumenting/exporters/) | instrumenting |

## 分区索引

| 分区 | 文件 | 条数 | 覆盖内容 |
|------|------|------|----------|
| getting-started | [topics/getting-started.md](./topics/getting-started.md) | 14 | 总览/FAQ/术语/数据模型/指标类型 |
| guides | [topics/guides.md](./topics/guides.md) | 14 | node-exporter/TLS/OTel 对接等场景向导 |
| tutorials-specs | [topics/tutorials-specs.md](./topics/tutorials-specs.md) | 14 | 上手教程 + OpenMetrics/remote write 规范 |
| prometheus | [topics/prometheus.md](./topics/prometheus.md) | 30 | 安装/配置/PromQL/存储/联邦（latest） |
| alerting | [topics/alerting.md](./topics/alerting.md) | 11 | Alertmanager 路由/分组/静默/高可用 |
| instrumenting | [topics/instrumenting.md](./topics/instrumenting.md) | 9 | 客户端库/暴露格式/exporter 体系 |
| practices-ops | [topics/practices-ops.md](./topics/practices-ops.md) | 13 | 命名/histogram/告警实践/安全加固 |
| visualization | [topics/visualization.md](./topics/visualization.md) | 5 | Grafana/consoles/browser |
