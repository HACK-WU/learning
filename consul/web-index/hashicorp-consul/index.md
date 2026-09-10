# Consul Docs 网页索引

> 起始 URL：https://developer.hashicorp.com/consul/docs
> 生成日期：2026-09-10 · 范围（scope）：/consul/docs · 条目数：562 · 一次性快照
> 只索引不镜像：需要正文时用 web_fetch 打开对应 URL（带锚点直达）

## 怎么用

1. 按「我要…」列定位条目（不确定先看下方分区索引）
2. 用 web_fetch 打开该条 URL 取细节
3. 本表是快照，链接大面积失效时整站重跑重建（脚本与中间地图见仓库 `temp/`）

## 高频直达

| 我要… | 去哪一页 | 分区 |
|-------|----------|------|
| 理解 Agent 是什么、Client 与 Server 两种模式 | [fundamentals/agent](https://developer.hashicorp.com/consul/docs/fundamentals/agent) | fundamentals |
| 理解共识协议 Raft 怎么工作 | [concept/consensus](https://developer.hashicorp.com/consul/docs/concept/consensus) | concept |
| 理解 Gossip 协议怎么传播成员信息 | [concept/gossip](https://developer.hashicorp.com/consul/docs/concept/gossip) | concept |
| 三种一致性模式（default/consistent/stale）怎么选 | [concept/consistency](https://developer.hashicorp.com/consul/docs/concept/consistency) | concept |
| 查 Agent 配置文件全量参数（HCL） | [reference/agent/configuration-file](https://developer.hashicorp.com/consul/docs/reference/agent/configuration-file) | reference-agent |
| 查健康检查对象字段参考（各类型参数） | [reference/service/health-check](https://developer.hashicorp.com/consul/docs/reference/service/health-check) | reference-misc |
| 查版本兼容矩阵（Consul ↔ consul-k8s ↔ Envoy） | [upgrade/compatibility](https://developer.hashicorp.com/consul/docs/upgrade/compatibility) | upgrade |
| 查 Consul 需要的全部端口清单 | [reference/architecture/ports](https://developer.hashicorp.com/consul/docs/reference/architecture/ports) | reference-misc |
| 手动备份与恢复（snapshot） | [manage/disaster-recovery/backup-restore](https://developer.hashicorp.com/consul/docs/manage/disaster-recovery/backup-restore) | manage |
| 企业版许可证的安装与管理 | [enterprise/license](https://developer.hashicorp.com/consul/docs/enterprise/license) | enterprise |
| 用 dev 模式一分钟起一个本地 Consul | [fundamentals/install/dev](https://developer.hashicorp.com/consul/docs/fundamentals/install/dev) | fundamentals |

## 分区索引

| 分区 | 文件 | 条数 | 覆盖内容 |
|------|------|------|----------|
| overview | [topics/overview.md](./topics/overview.md) | 11 | 站点入口、术语表、各平台落地页（散页人工归并，非站点原结构） |
| fundamentals | [topics/fundamentals.md](./topics/fundamentals.md) | 11 | Agent、服务、config-entry、安装、API/CLI/UI |
| concept | [topics/concept.md](./topics/concept.md) | 6 | catalog、一致性、Raft、Gossip、可靠性 |
| architecture | [topics/architecture.md](./topics/architecture.md) | 12 | 控制面/数据面、Connect 架构、网关架构 |
| use-case | [topics/use-case.md](./topics/use-case.md) | 6 | 服务发现/DNS/配置管理/服务网格/API 网关五大场景 |
| discover | [topics/discover.md](./topics/discover.md) | 15 | DNS 接口、注册查询、负载均衡集成 |
| register | [topics/register.md](./topics/register.md) | 26 | 各平台服务注册与健康检查配置 |
| connect | [topics/connect.md](./topics/connect.md) | 25 | sidecar/透明代理/自定义代理、K8s 注入 |
| secure | [topics/secure.md](./topics/secure.md) | 48 | ACL 体系、gossip/TLS 加密、安全模型、SSO |
| secure-mesh | [topics/secure-mesh.md](./topics/secure-mesh.md) | 17 | 网格证书管理、Intentions、零信任 |
| deploy | [topics/deploy.md](./topics/deploy.md) | 46 | Server/Client 部署、K8s Helm、Vault 后端、WAL |
| manage | [topics/manage.md](./topics/manage.md) | 23 | 灾备、DNS 转发、限流、规模化 |
| manage-traffic | [topics/manage-traffic.md](./topics/manage-traffic.md) | 14 | discovery chain、故障转移、灰度发布 |
| automate | [topics/automate.md](./topics/automate.md) | 28 | KV、Session、watch、consul-template、CTS |
| monitor | [topics/monitor.md](./topics/monitor.md) | 11 | 告警、日志/审计、遥测导出 |
| observe | [topics/observe.md](./topics/observe.md) | 13 | Grafana 看板、分布式追踪、访问日志 |
| east-west | [topics/east-west.md](./topics/east-west.md) | 21 | cluster peering、WAN federation、mesh gateway |
| north-south | [topics/north-south.md](./topics/north-south.md) | 28 | API/Ingress/Terminating 三类网关 |
| multi-tenant | [topics/multi-tenant.md](./topics/multi-tenant.md) | 12 | admin partition、namespace、网络分段（企业版） |
| upgrade | [topics/upgrade.md](./topics/upgrade.md) | 21 | 升级步骤、兼容性矩阵、LTS |
| release-notes | [topics/release-notes.md](./topics/release-notes.md) | 39 | Consul 核心 1.9–2.0 各版本 + 各组件版本变更 |
| enterprise | [topics/enterprise.md](./topics/enterprise.md) | 8 | 许可证、降级、支持矩阵 |
| envoy-extension | [topics/envoy-extension.md](./topics/envoy-extension.md) | 9 | WASM/Lua/OTel/ext-authz 等过滤器 |
| troubleshoot | [topics/troubleshoot.md](./topics/troubleshoot.md) | 5 | FAQ、网格与服务通信排障、故障注入 |
| error-messages | [topics/error-messages.md](./topics/error-messages.md) | 4 | 核心/K8s/API 网关/CTS 报错原文 |
| integrate | [topics/integrate.md](./topics/integrate.md) | 5 | consul-tools、NIA、hcdiag、Vault 集成 |
| reference-agent | [topics/reference-agent.md](./topics/reference-agent.md) | 21 | Agent 配置文件各章节参数、遥测 |
| reference-config-entry | [topics/reference-config-entry.md](./topics/reference-config-entry.md) | 21 | 21 种 config entry 字段参考 |
| reference-k8s | [topics/reference-k8s.md](./topics/reference-k8s.md) | 12 | Helm values、注解标签、API 网关 CRD |
| reference-proxy | [topics/reference-proxy.md](./topics/reference-proxy.md) | 9 | 内置代理、Envoy 集成、sidecar 参考 |
| reference-misc | [topics/reference-misc.md](./topics/reference-misc.md) | 35 | ACL 对象、CLI、CTS、DNS、端口、容量、健康检查 |
