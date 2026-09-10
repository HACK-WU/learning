# OpenTelemetry Docs 网页索引

> 起始 URL：https://opentelemetry.io/docs
> 生成日期：2026-09-10 · 范围（scope）：/docs（已排除 /docs/specs 规范 402 条、contributing 12 条；languages 仅保留 Python 相关 + SDK 通用配置；demo 仅保留遥测特性页） · 条目数：183 · 一次性快照
> 只索引不镜像：需要正文时用 web_fetch 打开对应 URL（带锚点直达）
> 课程对齐：OTel 课程实操语言为 Python，Collector 用 Docker 跑，后端对接 Prometheus/Grafana

## 怎么用

1. 按「我要…」列定位条目（不确定先看下方分区索引）
2. 用 web_fetch 打开该条 URL 取细节
3. 本表是快照，链接大面积失效时整站重跑重建（脚本与中间地图见仓库 `temp/`：`build_opentelemetry-io_web_index.py` / `web-index-opentelemetry-io-map-sitemap.md`）

## 高频直达

| 我要… | 去哪一页 | 分区 |
|-------|----------|------|
| 十分钟理解 OTel 是什么、解决什么问题 | [what-is-opentelemetry](https://opentelemetry.io/docs/what-is-opentelemetry) | overview |
| 理解 Trace/Span/Metrics/Logs/Baggage 概念 | [concepts/signals](https://opentelemetry.io/docs/concepts/signals) | concepts |
| Python 十分钟跑出第一条 Trace | [languages/python/getting-started](https://opentelemetry.io/docs/languages/python/getting-started) | languages |
| 查 OTLP exporter 全部环境变量 | [languages/sdk-configuration/otlp-exporter](https://opentelemetry.io/docs/languages/sdk-configuration/otlp-exporter) | languages |
| 用 Docker 跑 Collector | [collector/install/docker](https://opentelemetry.io/docs/collector/install/docker) | collector |
| 查 Collector 配置文件全量组件写法 | [collector/configuration](https://opentelemetry.io/docs/collector/configuration) | collector |
| 给 Collector 配批处理/内存限制/重试 | [collector/best-practices](https://opentelemetry.io/docs/collector/best-practices) | collector |
| OTel 与 Prometheus 怎么对接 | [compatibility/prometheus](https://opentelemetry.io/docs/compatibility/prometheus) | compatibility |
| 用 Java Agent 零代码插桩（对照 Python 手动插桩） | [zero-code/java-agent](https://opentelemetry.io/docs/zero-code/java-agent) | zero-code |
| 查采样（sampling）怎么配 | [concepts/sampling](https://opentelemetry.io/docs/concepts/sampling) | concepts |

## 分区索引

| 分区 | 文件 | 条数 | 覆盖内容 |
|------|------|------|----------|
| overview | [topics/overview.md](./topics/overview.md) | 7 | OTel 定位、入门、可观测性全景 |
| concepts | [topics/concepts.md](./topics/concepts.md) | 20 | 信号（trace/metrics/logs）、采样、语义约定、数据模型 |
| languages | [topics/languages.md](./topics/languages.md) | 18 | Python 插桩/SDK、SDK 通用配置（各语言共用） |
| zero-code | [topics/zero-code.md](./topics/zero-code.md) | 42 | Java Agent/.NET/Node 等零代码插桩、OBI |
| collector | [topics/collector.md](./topics/collector.md) | 40 | Collector 安装/配置/组件/best-practices、自定义组件 |
| platforms | [topics/platforms.md](./topics/platforms.md) | 29 | K8s operator、FaaS（Lambda/Cloud Functions）、serverless |
| demo | [topics/demo.md](./topics/demo.md) | 6 | 官方 Demo 的遥测特性页 |
| guidance | [topics/guidance.md](./topics/guidance.md) | 8 | 蓝图与参考实现 |
| compatibility | [topics/compatibility.md](./topics/compatibility.md) | 7 | Prometheus/Zipkin/Jaeger 等生态兼容 |
| security | [topics/security.md](./topics/security.md) | 6 | 安全响应与最佳实践 |
