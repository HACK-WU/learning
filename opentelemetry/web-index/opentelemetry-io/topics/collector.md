# Collector（OpenTelemetry Docs · 共 40 条）

> 范围：https://opentelemetry.io/docs/collector · 生成日期：2026-09-10

| 我要… | 去哪一页 | 关键词 | 相关 |
|-------|----------|--------|------|
| 十分钟跑起第一个 Collector（命令行直启） | [collector/quick-start](https://opentelemetry.io/docs/collector/quick-start) | Collector、快速 | |
| 选 Collector 安装方式（入口） | [collector/install](https://opentelemetry.io/docs/collector/install) | 安装 | |
| 选 Collector 部署形态（agent vs gateway） | [collector/deploy](https://opentelemetry.io/docs/collector/deploy) | 部署形态 | |
| 写 Collector 配置文件（receivers/processors/exporters/pipelines 四段） | [collector/configuration](https://opentelemetry.io/docs/collector/configuration) | 配置、yaml | |
| 了解组件体系（五类组件与注册表） | [collector/components](https://opentelemetry.io/docs/collector/components) | 组件 | |
| Collector 生命周期管理（升级/配置下发） | [collector/management](https://opentelemetry.io/docs/collector/management) | 管理 | |
| 理解发行版差异（core/contrib/k8s 各含什么组件） | [collector/distributions](https://opentelemetry.io/docs/collector/distributions) | 发行版 | |
| 监控 Collector 自身的指标（ 自我观测） | [collector/internal-telemetry](https://opentelemetry.io/docs/collector/internal-telemetry) | 自监控 | |
| Collector 排障入口（数据没到后端先看这） | [collector/troubleshooting](https://opentelemetry.io/docs/collector/troubleshooting) | 排障 | |
| Collector 规模化（水平扩展与负载均衡） | [collector/scaling](https://opentelemetry.io/docs/collector/scaling) | 扩容 | |
| 用 transform 改写/过滤/脱敏遥测数据 | [collector/transforming-telemetry](https://opentelemetry.io/docs/collector/transforming-telemetry) | transform、过滤 | |
| 理解 Collector 架构（pipeline：receiver→processor→exporter） | [collector/architecture](https://opentelemetry.io/docs/collector/architecture) | 架构、pipeline | |
| 扩展 Collector 入口（自有组件怎么加） | [collector/extend](https://opentelemetry.io/docs/collector/extend) | 扩展 | |
| 看 Collector 性能基准（吞吐参考） | [collector/benchmarks](https://opentelemetry.io/docs/collector/benchmarks) | 基准、性能 | |
| 两级拓扑：Agent 前置 + Gateway 集中（生产常见） | [collector/deploy/other/agent-to-gateway](https://opentelemetry.io/docs/collector/deploy/other/agent-to-gateway) | agent、gateway | |
| 写 authenticator extension（对接鉴权） | [collector/extend/custom-component/extension/authenticator](https://opentelemetry.io/docs/collector/extend/custom-component/extension/authenticator) | authenticator | |
| 从源码构建 Collector | [collector/extend/build-from-source](https://opentelemetry.io/docs/collector/extend/build-from-source) | 源码 | |
| 用 Docker 跑 Collector（本课程实操方式） | [collector/install/docker](https://opentelemetry.io/docs/collector/install/docker) | Collector、Docker | |
| 查在 Linux 上以二进制方式安装 Collector | [collector/install/binary/linux](https://opentelemetry.io/docs/collector/install/binary/linux) | 安装、Linux | |
| 写自定义 receiver | [collector/extend/custom-component/receiver](https://opentelemetry.io/docs/collector/extend/custom-component/receiver) | receiver | |
| Agent 模式部署（贴近应用、每机一个） | [collector/deploy/agent](https://opentelemetry.io/docs/collector/deploy/agent) | agent | |
| 用 OCB（构建器）拼自定义发行版 | [collector/extend/ocb](https://opentelemetry.io/docs/collector/extend/ocb) | OCB | |
| 写自定义 connector | [collector/extend/custom-component/connector](https://opentelemetry.io/docs/collector/extend/custom-component/connector) | connector | |
| K8s 上安装 Collector | [collector/install/kubernetes](https://opentelemetry.io/docs/collector/install/kubernetes) | Collector、K8s | |
| 查在 macOS 上以二进制方式安装 Collector | [collector/install/binary/macos](https://opentelemetry.io/docs/collector/install/binary/macos) | 安装、macOS | |
| 不用 Collector 直发后端的取舍（什么时候可以） | [collector/deploy/other/no-collector](https://opentelemetry.io/docs/collector/deploy/other/no-collector) | no-collector | |
| 理解 Collector 是什么、为什么生产上数据都过它 | [collector](https://opentelemetry.io/docs/collector) | Collector | |
| 查「Collector、安装、二进制」的官方说明（用法/配置/注意事项） | [collector/install/binary](https://opentelemetry.io/docs/collector/install/binary) | Collector、安装、二进制 | |
| 写自定义组件总览 | [collector/extend/custom-component](https://opentelemetry.io/docs/collector/extend/custom-component) | 自定义组件 | |
| 写自定义 extension（Collector 扩展） | [collector/extend/custom-component/extension](https://opentelemetry.io/docs/collector/extend/custom-component/extension) | 自定义组件、extension | |
| Gateway 模式部署（集中处理、独立扩缩） | [collector/deploy/gateway](https://opentelemetry.io/docs/collector/deploy/gateway) | gateway | |
| 查组件注册表（registry.opentelemetry.io） | [collector/registry](https://opentelemetry.io/docs/collector/registry) | registry | |
| 查在 Windows 上以二进制方式安装 Collector | [collector/install/binary/windows](https://opentelemetry.io/docs/collector/install/binary/windows) | 安装、Windows | |
| 查有哪些 receiver（数据从哪进来：OTLP/filelog/hostmetrics…） | [collector/components/receiver](https://opentelemetry.io/docs/collector/components/receiver) | receiver | |
| 查有哪些 processor（batch/memory_limiter/tail_sampling/transform…） | [collector/components/processor](https://opentelemetry.io/docs/collector/components/processor) | processor | |
| 查有哪些 exporter（往哪去：OTLP/Prometheus/调试输出…） | [collector/components/exporter](https://opentelemetry.io/docs/collector/components/exporter) | exporter | |
| 查 connector（信号间桥接，如 spanmetrics） | [collector/components/connector](https://opentelemetry.io/docs/collector/components/connector) | connector | |
| 查 extension（health_check/pprof 等辅助组件） | [collector/components/extension](https://opentelemetry.io/docs/collector/components/extension) | extension | |
| 其他部署形态总览 | [collector/deploy/other](https://opentelemetry.io/docs/collector/deploy/other) | 部署 | |
| Collector 韧性（队列/重试/内存限制，防数据丢失） | [collector/resiliency](https://opentelemetry.io/docs/collector/resiliency) | 韧性、队列 | |
