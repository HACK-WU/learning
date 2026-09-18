# Kubernetes 应用实战索引

> **一键跳转**：本课程全部应用实战——学到哪课就点哪篇；复习时从这里横向挑着练。
> **按需配套**：仅收录有实战场景的课（课 1《为什么需要 k8s》、课 2《声明式 API 与调谐循环》、第 0 课《环境搭建》为纯概念 / 原理 / 环境准备课，不配实战）；课程正文在课里，本目录只放实战。
> **定位**：`会用，不上生产`——课里学完，在这里动手；需要真实跑通的完整工程见 [结课项目](../projects/三层Web应用生产化部署/README.md)。
> 活文档：随课程进度更新（与 `02-课程目录.md` 同节奏）。

## 阶段 1：心智模型与架构

| 课 | 实战场景 | 覆盖知识点 | 应用实战 |
|----|---------|-----------|---------|
| 课 3：[Pod：最小调度单元](../stages/1-心智模型与架构/lessons/lesson-03-Pod最小调度单元.md) | 给一个假死的 Web 服务配齐三探针 | Pod 生命周期与状态机、探针三兄弟 | [03 · 探针三件套](03-Pod最小调度单元.md) |
| 课 4：[多容器 Pod 与优雅终止](../stages/1-心智模型与架构/lessons/lesson-04-多容器Pod与优雅终止.md) | 等依赖就绪 + 日志外挂 + 更新不丢请求 | init 容器、sidecar、优雅终止与生命周期钩子 | [04 · 多容器协作与优雅退场](04-多容器Pod与优雅终止.md) |

## 阶段 2：工作负载与控制器

| 课 | 实战场景 | 覆盖知识点 | 应用实战 |
|----|---------|-----------|---------|
| 课 5：[Deployment 无状态应用](../stages/2-工作负载与控制器/lessons/lesson-05-Deployment无状态应用.md) | 上线不中断、出问题一键回到上一版 | 滚动更新、回滚与版本历史、垃圾回收 | [05 · 上线不中断与一键回退](05-Deployment无状态应用.md) |
| 课 6：[StatefulSet / DaemonSet / Job](../stages/2-工作负载与控制器/lessons/lesson-06-StatefulSet与DaemonSet与Job.md) | 有状态服务 + 节点级采集 + 批处理任务 | StatefulSet、DaemonSet、Job 与 CronJob、TTL 清理 | [06 · 三种命运的工作负载](06-StatefulSet与DaemonSet与Job.md) |

## 阶段 3：网络与服务暴露

| 课 | 实战场景 | 覆盖知识点 | 应用实战 |
|----|---------|-----------|---------|
| 课 7：[Service 与 CoreDNS](../stages/3-网络与服务暴露/lessons/lesson-07-Service与CoreDNS.md) | 让前端稳定找到后端，Pod 换了也不受影响 | Service 类型选型、EndpointSlice、CoreDNS 服务发现 | [07 · 让前端稳定找到后端](07-Service与CoreDNS.md) |
| 课 8：[Ingress 七层路由](../stages/3-网络与服务暴露/lessons/lesson-08-Ingress七层路由与灰度发布.md) | 一个域名挂多个服务 + 灰度放量 | Ingress 规则与路径匹配、灰度发布与流量切分 | [08 · 一个入口收敛多服务与灰度放量](08-Ingress七层路由与灰度发布.md) |
| 课 9：[Gateway API](../stages/3-网络与服务暴露/lessons/lesson-09-GatewayAPI下一代入口标准.md) | 多团队共用一个入口，各管各的路由 | Gateway API 三层模型、HTTPRoute 流量治理、从 Ingress 迁移 | [09 · 多团队共用入口与标准灰度](09-GatewayAPI与流量治理.md) |
| 课 10：[NetworkPolicy](../stages/3-网络与服务暴露/lessons/lesson-10-NetworkPolicy集群内防火墙.md) | 只让该连的连上，数据库不再裸奔 | 默认全通的隐患、NetworkPolicy 语义、CNI 支持与验证 | [10 · 只让该连的连上](10-NetworkPolicy微隔离.md) |

## 阶段 4：配置 · 存储 · 资源 · 工程化

| 课 | 实战场景 | 覆盖知识点 | 应用实战 |
|----|---------|-----------|---------|
| 课 11：[ConfigMap 与 Secret](../stages/4-配置存储资源工程化/lessons/lesson-11-ConfigMap与Secret.md) | 配置拿出来了，改完还得能生效 | 配置与代码分离、checksum 自动滚动、Secret 注入方式 | [11 · 配置与密钥管理](11-配置与密钥管理.md) |
| 课 12：[Volume / PV / PVC](../stages/4-配置存储资源工程化/lessons/lesson-12-Volume与PVPVC.md) | 数据活过容器：从重启即丢到各存各的 | 存储层次选择、StatefulSet 独立盘、RWO 节点级语义 | [12 · 数据活过容器](12-数据活过容器.md) |
| 课 13：[资源 · 调度 · 扩缩容](../stages/4-配置存储资源工程化/lessons/lesson-13-资源调度扩缩容.md) | 不设资源边界，一个应用能吃掉整台机器 | requests/limits 分工、HPA 扩缩、账本与裸奔 Pod | [13 · 资源边界与自动扩缩容](13-资源边界与自动扩缩容.md) |
| 课 14：[Helm · Kustomize · 可观测性](../stages/4-配置存储资源工程化/lessons/lesson-14-Helm与Kustomize与可观测性.md) | 12 个服务 × 3 套环境，改一处要改 36 遍 | 一份源头+版本台账、配置哈希自动生效、日志边界 | [14 · 一份源头多套环境](14-一份源头多套环境.md) |

## 阶段 5：安全体系

| 课 | 实战场景 | 覆盖知识点 | 应用实战 |
|----|---------|-----------|---------|
| 课 15：[RBAC 与 ServiceAccount](../stages/5-安全体系/lessons/lesson-15-RBAC与ServiceAccount.md) | 一个日志采集器，差点让整个集群失守 | 认证/授权/准入三段式、RBAC 最小权限、Role 不跨区、SA token 挂载 | [15 · 最小权限授权](15-最小权限授权.md) |
| 课 16：[PSA 与 securityContext](../stages/5-安全体系/lessons/lesson-16-Pod安全PSA与securityContext.md) | 合规检查把应用卡住了 | Pod 安全标准三档、securityContext 四件套、warn 与 enforce、假成功陷阱 | [16 · 合规检查把应用卡住了](16-合规检查把应用卡住了.md) |
| 课 17：[Secret 加固 · etcd 加密 · 审计](../stages/5-安全体系/lessons/lesson-17-Secret加固与etcd加密与审计.md) | 密钥放在哪才算安全 | Secret 编码本质、etcd 静态加密、存量重写、审计策略降噪 | [17 · 密钥放在哪才算安全](17-密钥放在哪才算安全.md) |

## 阶段 6：排障 · 运维 · 扩展

| 课 | 实战场景 | 覆盖知识点 | 应用实战 |
|----|---------|-----------|---------|
| 课 18：[系统化排障](../stages/6-排障运维与扩展/lessons/lesson-18-系统化排障分层定位法.md) | 应用明明在跑，服务为什么不通 | 五层定位模型、四态判据、`Running` vs `0/1`、症状层≠根因层 | [18 · 应用起不来怎么排查](18-应用起不来怎么排查.md) |
| 课 19：[集群运维与生命周期](../stages/6-排障运维与扩展/lessons/lesson-19-集群运维与生命周期.md) | 一次维护引发的连锁故障 | cordon/drain/uncordon、PDB 下限保护、副本分散软硬策略、探测工具假警报 | [19 · 一次维护引发的连锁故障](19-一次维护引发的连锁故障.md) |
| 课 20：[扩展机制与决策收口](../stages/6-排障运维与扩展/lessons/lesson-20-扩展机制与决策收口.md) | 要不要自建一个资源类型 | CRD 定义与命名规矩、schema 校验、status 子资源、选型判断表 | [20 · 要不要自建一个资源类型](20-要不要自建一个资源类型.md) |

## 汇总

- ✅ **已编写 18 / 18 篇，全部完成（2026-09-18 收官）**：阶段 1 两篇为样板批（2026-09-16）；阶段 2–4 于 2026-09-17~18 完成；阶段 5 三篇于 2026-09-18 完成（其中课 17 为本机**真实开启 etcd 加密与审计**后实测）；阶段 6 三篇于 2026-09-18 完成（课 19 含**真实 drain 演练**与 DNS 中断对照实测）。实测环境为集群 `k8s-c1-calico`
- 未列入的课（第 0 课、课 1、课 2）为纯概念 / 原理 / 环境准备课，**不配实战**是常态，不是缺漏
