# 阶段 4：配置 · 存储 · 资源 · 工程化

> 所属课程：Kubernetes 系统学习 ｜ 故事章节：**从能用到敢上生产** ｜ 上一阶段：[阶段 3《网络与服务暴露》](../3-网络与服务暴露/overview.md)
> 下一阶段：[阶段 5《安全体系》](../5-安全体系/overview.md)

## 🎯 本阶段目标

- 实现配置与代码分离，理解 Secret 的安全边界（它**不是**加密）
- 给有状态应用挂上持久化存储，理解为什么要分 Volume / PV / PVC / StorageClass 四层
- 能设置合理的资源配额，并**预判**节点资源紧张时谁会被杀
- 掌握扩缩容三件套的适用前提，以及多租户资源治理手段
- 能用 Helm / Kustomize 管理应用，理解可观测性是自动化的前提

## 📍 学习重点

- **Secret 只是 base64**：它防的是「误看」，不是「被拿」。真正的安全要靠 RBAC + etcd 加密 + 外部密钥管理（阶段 5 展开）
- **存储为什么要四层抽象**：把「用什么存储」（基础设施关注）与「要多少存储」（应用关注）解耦 —— 与 Ingress/Controller 是同一种设计套路
- **QoS 决定生死**：节点内存不足时，BestEffort 先死、Guaranteed 最后死。这不是配置细节，是容量规划的核心
- **requests 影响调度、limits 影响运行**：两者语义不同，只配 limits 是常见错误
- **扩缩容三件套各有前提**：HPA 扩副本（需 metrics-server）、VPA 调资源（与 HPA 共存需谨慎）、Cluster Autoscaler 加节点（依赖云厂商）
- **多租户需要双重约束**：ResourceQuota 限制命名空间总量，LimitRange 为单个容器兜底默认值 —— 没有 LimitRange 的 Quota 容易被单个 Pod 打满
- **Helm 与 Kustomize 是两种哲学**：Helm 是模板化打包（适合分发），Kustomize 是声明式覆盖（适合多环境差异）。二者不是互斥关系
- **可观测性是自动化的前提**：没有 metrics-server，HPA 无法工作；没有日志架构，排障只能靠 `kubectl logs` 单点查看

## ✅ 必须掌握的知识点

| 知识点 | 所属课 | 学完应能 |
|--------|--------|----------|
| ConfigMap | 课 11 | ~~用 ConfigMap 注入配置（环境变量 / 挂载文件两种形式）~~ ✅ 已完成 |
| Secret | 课 11 | ~~创建并注入 Secret，说清 base64 与加密的区别及正确加固方式~~ ✅ 已完成 |
| 投射卷 projected volume | 课 11 | ~~把 ConfigMap/Secret/downward API 多个来源合并挂载到同一目录，说清它解决了什么问题~~ ✅ 已完成 |
| 配置变更与滚动更新联动 | 课 11 | ~~说清配置更新后 Pod 是否自动重启，以及如何主动触发~~ ✅ 已完成 |
| Volume 基础 | 课 12 | 区分 emptyDir / hostPath 的生命周期与适用场景 |
| PV / PVC / StorageClass | 课 12 | 说清三层抽象各自解决什么问题，能写 PVC 并观察绑定 |
| 有状态应用落地 | 课 12 | 给有状态应用挂持久化卷，验证 Pod 重建后数据仍在 |
| requests 与 limits | 课 13 | 正确设置二者，说清各自影响调度还是运行时 |
| QoS 与驱逐顺序 | 课 13 | 判定 Pod 的 QoS 等级，预判节点压力时的驱逐顺序 |
| 调度、亲和性与污点容忍 | 课 13 | 用 nodeSelector / 亲和性 / 污点容忍控制 Pod 落点 |
| HPA / VPA / Cluster Autoscaler | 课 13 | 区分三者扩什么，说清各自依赖与共存注意事项 |
| ResourceQuota 与 LimitRange | 课 13 | 用 Quota + LimitRange 做多租户资源治理，说清二者配合关系 |
| PriorityClass 优先级与抢占 | 课 13 | 用优先级表达"谁更重要"，分清抢占（调度阶段）与驱逐（运行阶段） |
| Helm 与 Chart | 课 14 | 用 Helm 安装、升级、回滚一个应用 |
| Kustomize | 课 14 | 用 Kustomize 做多环境配置覆盖，说清与 Helm 的取舍 |
| 可观测性（metrics-server 与日志架构） | 课 14 | 部署 metrics-server 使 `kubectl top` 可用，说清集群日志架构 |

## 🗺️ 本阶段路径图

![阶段 4 路径](./assets/stage-04-production-path.svg)

> SVG 展示四课顺序：配置 → 存储 → 资源与扩缩容 → 工程化与可观测。

## ✅ 课 11 完成情况（2026-09-11）

**讲义**：[lesson-11-ConfigMap与Secret.md](lessons/lesson-11-ConfigMap与Secret.md)（1600 行）

**阶段状态**：课 11 已完成，课 12（存储）待开始。

**本课核心结论（全部本机实测）**：

1. ConfigMap 让镜像跨环境复用；**环境变量永不更新**（创建时固化），**卷挂载会更新**但延迟 50~100 秒
2. **Secret 不是加密，只是 base64** —— 一行 `base64 -d` 还原明文，防误看不防被拿
3. Secret 卷挂载**默认 0644，任何用户可读**；必须显式 `defaultMode: 0400`
4. **Secret 走 tmpfs 不落盘，ConfigMap 走磁盘会落盘**（实测推翻了"都是 tmpfs"的常见说法）
5. 改配置**不触发**滚动更新（ConfigMap 不在 Pod 模板里，hash 不变）
6. **subPath 挂载放弃自动更新** —— 最隐蔽的坑
7. 投射卷解决"同一目录挂多来源"（ConfigMap + Secret + downward API）
8. immutable 是**单向门**：防误改 + 降 API Server 压力，但设了改不回来

> **阶段 5 待展开**：etcd 静态加密、RBAC 最小授权保护 Secret（本课只讲清边界，不越界）。

## ✅ 课 12 完成情况（2026-09-11）

**讲义**：[lesson-12-Volume与PVPVC.md](lessons/lesson-12-Volume与PVPVC.md)（约 900 行）

**阶段状态**：课 11 ~ 课 14 全部完成（阶段 4 已收官）。

**本课核心结论（全部本机实测）**：

1. **"数据不丢"是程度问题** —— 先问需要活过什么：容器重启 / Pod 删除 / 节点故障
2. **容器根文件系统活不过容器重启**，emptyDir 可以 —— 用**标记法**实测验证，避免"重启后重写一遍"的假象
3. **emptyDir 活过容器重启，活不过 Pod 删除**（生命周期绑定 Pod，不是容器）
4. **hostPath 活过 Pod 删除，但把 Pod 钉死在单节点** —— 只适合节点级 agent；挂载 `/` 是提权捷径
5. **PV/PVC 两层抽象**：管理员管资源、开发者管申请；**一对一绑定，容量向上取**（申请 50Mi 拿到 100Mi）
6. **`WaitForFirstConsumer` 延迟绑定**：PVC 单独创建时**不生成 PV**（Pending + 0 个 PV），等 Pod 调度后才建 —— 避免"PV 建错节点"
7. **默认 `Delete` 回收策略：删 PVC = 删数据**（实测删后 PV 报 NotFound）；`Retain` 保留但变 `Released`，需手工清 `claimRef` 才能复用
8. **PVC 有删除保护**：被 Pod 使用时有 `kubernetes.io/pvc-protection` finalizer

**单节点局限（已标注，未实测）**：`ReadWriteMany`（local-path 只支持 RWO）、hostPath 跨节点调度陷阱。

**⚠️ 环境注意**：kind 节点的 `/tmp` 本身是 tmpfs，用 `hostPath: /tmp/x` 会误判为"走内存"；本机 `allowVolumeExpansion` 未开启，扩容实测报 Forbidden。

## ✅ 课 13 完成情况（2026-09-11）

**讲义**：[lesson-13-资源调度扩缩容.md](lessons/lesson-13-资源调度扩缩容.md)

**阶段状态**：课 11、12、13 已完成，课 14（Helm · Kustomize · 可观测性）待开始。

**本课核心结论（除标注项外全部本机实测）**：

1. **requests 是"座位预约"（调度器用），limits 是"天花板"（kubelet/cgroup 用）** —— 两者作用在不同阶段、由不同组件执行
2. **只写 limits 不写 requests → k8s 自动把 requests 补齐为同值**，Pod 变成 Guaranteed；想表达"平时少、偶尔冲"必须两个都写且值不同
3. **CPU 超限只限速不死，内存超限必死** —— 实测：CPU 压满 4 核（limit 0.5 核）→ `Succeeded`；内存写 200Mi（limit 100Mi）→ `OOMKilled` / exitCode 137
4. **cgroup 内存上限精确生效**：容器内读 `memory.max` = `104857600`（= 100Mi）
5. **QoS 三档判定正确**（Guaranteed/Burstable/BestEffort 实测验证）；多容器 Pod 取**最差容器**
6. ⚠️ **重要更正**：官方文档明确 **kubelet 不使用 QoS 类决定驱逐顺序**，QoS 只能用于**估计**；真实排序依据是「用量是否超 requests」+ 优先级 + 超出程度
7. **调度失败要分资格 vs 容量**：`had untolerated taint` / `didn't match node affinity` 是资格问题（扩容无用），只有 `Insufficient cpu` 才是容量问题
8. **toleration ≠ 会去那个节点**，只是"允许"；指定节点要用 nodeSelector/affinity
9. **HPA 实测 1 → 5 → 9 副本**：CPU 137% → 扩容 → 降至 49% 停止；副本未缩回是**缩容 300 秒稳定窗口**在起作用
10. **ResourceQuota 超额是"拒绝创建"（Forbidden），不是 Pending** —— 与调度失败是两种完全不同的失败模式
11. **设了 quota 后 Pod 必须写全资源声明**，否则连第一个都创建不了（`must specify limits.cpu...`）
12. **LimitRange 给裸奔 Pod 注入默认值**，实测 QoS 从 BestEffort 变 Burstable

**未实测标注**：驱逐顺序（BestEffort→Burstable→Guaranteed）—— 单节点 kind 制造节点级内存压力会连带打死 control-plane（API server/etcd/scheduler 同机），风险不可控且不具生产代表性。该节为官方文档结论，已在讲义中显式标注。

**⚠️ 环境注意**：metrics-server 的 `master` 分支 manifest 路径已失效（实测 404），须用 `releases/latest/download/components.yaml`；kind 环境需加 `--kubelet-insecure-tls`（生产不应加）。

**实测踩坑（已写入讲义）**：`restartPolicy: Never` 时终止信息在 `state` 而非 `lastState`（查 OOM 易读错字段）；容器内 `/dev/shm` 默认仅 64Mi，测内存压力应用 `emptyDir: {medium: Memory}`。

## ✅ 课 14 完成情况（2026-09-11 · 阶段收官）

**讲义**：[lesson-14-Helm与Kustomize与可观测性.md](lessons/lesson-14-Helm与Kustomize与可观测性.md)

**阶段状态**：**阶段 4 全部完成（课 11、12、13、14）**，下一阶段为《安全体系》。

**本课核心结论（除标注项外全部本机实测）**：

1. **Helm = 模板引擎 + 版本台账**；Kustomize = 补丁叠加，**无状态无台账**（回滚靠 Git）
2. **Helm 3 移除 Tiller**，直接用你的 kubeconfig 权限——你的权限就是 Helm 的权限
3. **release 存为 `sh.helm.release.v1.<name>.v<N>` Secret**（类型 `helm.sh/release.v1`），**每次 upgrade/rollback 新增一个**
4. ⚠️ **release Secret 不是加密，只是 gz + base64**，一行命令解出明文 → **不要把真密码写进 values**
5. **回滚不是删除历史，是新增一条 REVISION**（历史只增不减，可再滚回去）
6. **values 优先级**：`values.yaml` < `-f`（多文件时后者胜）< `--set`（实测 1 → 3 → 5 → 7）
7. **点号陷阱在 KEY 不在 VALUE**：VALUE 里点号转不转义结果相同；**KEY 里不转义会静默生成嵌套结构且不报错**（ingress 注解高频踩坑）
8. **三向合并不是"保留所有手工改动"**：Helm 管着的字段且**新旧值变了** → 覆盖手工改动；值没变 → 保留；Helm 不管的字段（sidecar）→ 保留
9. **`configMapGenerator` 名字带内容哈希**（实测 `k8kd87hbgm` → `kfg5445g62`）——**这是课 11「配置更新不重启」问题的自动化答案**
10. **可观测性三支柱，k8s 各带了一半**：指标有 API 但**不存历史**（`window: 20s` 是快照）；日志有落盘但**会轮转会消失**；链路**完全空白**
11. **日志真实路径** `/var/log/pods/<ns>_<pod>_<uid>/<容器>/<重启次数>.log`——`0.log` 的 `0` 就是重启次数，这正是 `--previous` 的原理
12. **`/var/log/containers/*.log` 是符号链接层**（供日志采集器从文件名解析元数据，历史约定）
13. **CRI 日志头**：`<RFC3339Nano时间戳> <stdout/stderr> <F/P> <原始内容>`，`F`=完整行、`P`=超 16KB 被截断
14. ⏰ **Pod 删除后日志进入"随时消失"状态**（实测删除后仍可读，但目录已在清理队列）→ **删前先捞日志**
15. **选型判断标准一句话**：改一处配置要同步改几份？一份 → 不用工具；多份 → 需要工具

**未实测标注**：① `--set-string` 与 `--set` 的真实差异场景（本例模板为字符串拼接，类型差异被抹平，未构造出有效场景）；② 日志轮转默认值 10Mi × 5 为 kubelet 默认值——**本机 kind 未显式配置**（已实测确认 kubelet config 与进程参数均无该项），生产集群须实际查。

**⚠️ 环境注意**：`kubectl` 从 v1.14 起**内置 Kustomize**（v5.7.1），无需单独装 `kustomize` CLI。

## 本阶段产出

- [x] `lessons/lesson-11-ConfigMap与Secret.md`（1600 行，2026-09-11 完成）
- [x] `lessons/lesson-12-Volume与PVPVC.md`（约 900 行，2026-09-11 完成；第四幕 22 项断言实测通过）
- [x] `lessons/lesson-13-资源调度扩缩容.md`（2026-09-11 完成；双视角评审 P0 清零）
- [x] `lessons/lesson-14-Helm与Kustomize与可观测性.md`（2026-09-11 完成；双视角评审 P0 清零）

## 🎉 阶段 4 总结

**故事线闭环**：从"能跑起来"到"跑得稳、跑得省"——

| 课 | 解决的问题 | 一句话 |
|---|---|---|
| 课 11 | 配置从哪来 | ConfigMap/Secret，以及"改了为什么不生效" |
| 课 12 | 数据放哪 | Volume/PV/PVC，让数据活过容器重启 |
| 课 13 | 怎么不拖垮邻居 | requests/limits、QoS、调度、HPA |
| 课 14 | 怎么规模化交付 + 怎么知道健康 | Helm/Kustomize、可观测性三支柱 |

**两条贯穿暗线**：① **requests 的三重身份**（调度器用它决定放哪、HPA 用它当分母、kubelet 用它判断驱逐）；② **k8s 只提供接口不提供实现**（指标有 API 无存储、日志有落盘无收集、链路全空白）——理解这点就不会奇怪"为什么装了 k8s 还要装一堆东西"。

### 课级入口要素补齐（2026-09-15）

按 topic-teach 最新 skill 的「课级入口要素」硬约束，本阶段课 11-12（课 13-14 已有全局图，本轮补处境对照 + 地图 + 衔接句）已全部补齐六项要素（一句话本质 / 处境对照 / 一眼全局图 + 读图指引 / 本课地图 / 📖 文档核对 / 🧭 知识点衔接句），经 `verify.sh` 全量核验 P0=0。

**本阶段新增全局图**：lesson-11-设置从成品里拿出来.svg、lesson-12-写的东西能活多久.svg

**真实性纪律**：处境对照一律不给编造数字，全部为机制层面对照，无把握处标 ⏳；📖 留痕仅在确认真实引用官方文档后补写。
