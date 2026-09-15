# 阶段 6：排障 · 运维 · 扩展

> 所属课程：Kubernetes 系统学习 ｜ 故事章节：**出事了怎么办，以及它从哪来** ｜ 上一阶段：[阶段 5《安全体系》](../5-安全体系/overview.md)

## 🎯 本阶段目标

- 形成**可复用的排障动作序列**：排障不靠灵感，靠分层定位
- 掌握节点维护的标准动作（cordon / drain / PDB），理解「安全地摘掉一台机器」为什么需要三者配合
- 理解生产集群的运维成本：kubeadm 搭建、版本升级、etcd 备份恢复、HA 控制平面
- 理解 k8s 的扩展机制（CRD / Operator / CNI / CSI / CRI），明白它为什么能长成今天这样
- **收口最初的决策问题**：该不该用 k8s

## 📍 学习重点

- **排障是分层定位**：节点 → 控制面 → 工作负载 → 网络 → 存储。逐层排除，而不是到处乱看日志
- **drain 为什么需要 PDB**：cordon 只是标记不可调度，drain 会驱逐 Pod —— 若不控制，可能一次性驱逐掉某服务的全部副本
- **⚠️ 实操边界**：kubeadm 搭建、版本升级、etcd 备份恢复、HA 控制平面**无法在 kind 上真实操**（kind 节点是容器，没有真正的 systemd 与多机网络）。这些内容作为**原理课**撰写，显式标注边界并给出生产环境对照
- **扩展接口是 k8s 生态的根**：CNI（网络）/ CSI（存储）/ CRI（运行时）三个接口把实现交给生态，这是 k8s 能成为标准的关键设计决策
- **CRD 与 Operator 是「把运维知识写进软件」**：理解 Operator 不是某个工具，而是一种模式
- **决策收口**：回到课 1 埋下的问题 —— 现在有足够的证据回答「该不该用 k8s」

## ✅ 必须掌握的知识点

| 知识点 | 所属课 | 学完应能 |
|--------|--------|----------|
| 排障方法论（分层定位） | 课 18 | 按固定分层序列定位故障，能说清每层的排查命令与判据 |
| 集群与节点排障 | 课 18 | 定位节点 NotReady、控制面组件异常、证书过期等故障 |
| 工作负载与网络排障 | 课 18 | 定位 Pending / CrashLoopBackOff / ImagePullBackOff / 服务不通；**含 finalizer 卡删除、EndpointSlice 无后端两个判据** |
| 节点维护（cordon / drain / PDB） | 课 19 | 安全摘除节点，用 PDB 保证驱逐期间服务不中断 |
| 节点关闭处理（原理课） | 课 19 | 区分计划内 drain 与非计划关机（断电/系统关机）两套机制，说清 graceful shutdown 的时限博弈 |
| 集群搭建与 kubeadm（原理课） | 课 19 | 说清 kubeadm 做了什么，以及生产环境还缺哪些步骤 |
| 升级与 etcd 备份恢复（原理课） | 课 19 | 说清升级顺序与版本偏差策略，能描述 etcd 备份恢复流程 |
| HA 控制平面（原理课） | 课 19 | 说清 HA 拓扑（堆叠 vs 外部 etcd）与各自的故障域 |
| CRD 与自定义资源 | 课 20 | 定义并使用 CRD，说清它与内置资源的关系 |
| Operator 模式 | 课 20 | 解释 Operator 是什么（模式而非工具），能举例说明它解决了什么 |
| API 聚合层 | 课 20 | 区分扩展 API 的两条路（CRD vs Aggregated APIServer），说清各自适用前提 |
| 扩展接口 CNI / CSI / CRI | 课 20 | 说清三个接口各自的职责与生态实现 |
| 该不该用 k8s：决策清单 | 课 20 | 给出判断条件与对比表，能对具体场景给出选型建议 |

## 🗺️ 本阶段路径图

![阶段 6 路径](./assets/stage-06-ops-path.svg)

> SVG 展示三课递进：课 18（怎么查问题）→ 课 19（怎么维护集群）→ 课 20（它从哪来、该不该用）。

## ✅ 课 18 完成情况（2026-09-14）

**讲义**：[lesson-18-系统化排障分层定位法.md](lessons/lesson-18-系统化排障分层定位法.md)

**阶段状态**：课 18 已完成。下一课为课 19《集群运维与生命周期》（cordon / drain / PDB + 4 个原理课知识点）。

**本课核心结论（除标注项外全部本机实测，共 20+ 项）**：

1. **分层定位五层模型**：L0 集群整体 → L1 节点 → L2 控制面 → L3 工作负载 → L4 网络与存储，**逐层排除，证明上一层没问题才进下一层**
2. **三条排障纪律**：**先取证后动手**（重启会销毁 CrashLoop 现场）、**一次只改一处**、**读懂原文再下结论**
3. **节点看四项条件**：`MemoryPressure` / `DiskPressure` / `PIDPressure` 全 False + `Ready=True` 才算健康（实测）
4. **控制面是静态 Pod**：`/etc/kubernetes/manifests/` 下 4 个 yaml，改文件即重启；**`kubectl get componentstatuses` 已废弃**（v1.19+）
5. ⚠️ **证书过期会让集群"突然全挂"**——`kubeadm certs check-expiration` 实测可用（本集群剩 **361d**），**应作为第一条排除命令**
6. **kubelet 是第一现场**：`journalctl -u kubelet` 能看到 `Error syncing pod` + `back-off 1m20s` 原文（**本环境无 `/var/log/kubelet.log`**）
7. **Pending 判据**：`FailedScheduling` 后跟 `Insufficient cpu` / `didn't match node affinity/selector` / `untolerated taint`
8. **镜像判据**：`ErrImagePull`（重试中）→ `ImagePullBackOff`（退避等待）；按 `not found` / `unauthorized` / `timeout` 分诊
9. **CrashLoopBackOff 看退出码**：1=应用错误、137=OOM、143=SIGTERM、127=命令找不到（**本课只实测了 1**）
10. ⚠️ **`--previous` 的精确规律**：**state 为空（容器重建中）取不到；state=CrashLoopBackOff（退避等待）稳定可取**（120 秒 12 次采样全部符合）
11. **EndpointSlice `endpoints: null`** = Service 无后端（**v1 Endpoints 已在 v1.33+ 弃用**）
12. 🎯 **三种"不通"报错**：`Connection refused`=无后端 / `bad address`=DNS 失败 / `download timed out`=被丢弃（**第三种我原预判是 refused，实测是 timed out**）
13. 🎯 **finalizer 卡删除**：`kubectl delete` 返回 `deleted` 是**假成功**；看 `deletionTimestamp` 有值 + `finalizers` 非空；修复用 `patch` 移除 finalizer（**不要 `--force`**）
14. 🎯 **nslookup 的假警报**：busybox `nslookup` 查短名报 NXDOMAIN（补域不完整），但 **FQDN 可解析、应用（wget）能访问**——**诊断工具 ≠ 应用行为**

> ⚠️ **两处诚实标注**：
> ① 退出码 **137（OOMKilled）/ 143 / 127 本环境未实测**（只实测了退出码 1），讲义按文档结论列出供对照。
> ② nslookup NXDOMAIN 在 **busybox 1.36 稳定复现 3 次**，但属**工具实现行为**，不同镜像可能不同；普适表述收敛为"**诊断工具与应用可能表现不一致**"。

## ✅ 课 19 完成情况（2026-09-14）

**讲义**：[lesson-19-集群运维与生命周期.md](lessons/lesson-19-集群运维与生命周期.md)

**阶段状态**：课 19 已完成。下一课为课 20《扩展机制与决策收口》—— CRD / Operator / API 聚合层 / CNI·CSI·CRI + 「该不该用 k8s」决策清单（**全课程收官**）。

**本课结构**：5 个知识点中**只有知识点 1（cordon/drain/PDB）能在 kind 上真实操**，知识点 2-5 为**原理课**（已在讲义中显式标注边界，区分「✅ 已实测」与「📄 文档结论」）。

**本课核心结论（除标注项外全部本机实测，共 15+ 项）**：

1. **节点维护三件套**：**cordon 只封新不管旧** → **drain 用 eviction API 驱逐存量**（自动先 cordon）→ **uncordon 恢复（不会迁回旧 Pod）**
2. 🎯 **PDB 只管「自愿驱逐」，挡不住 `kubectl delete pod`** —— 实测：PDB `minAvailable=3` 时 drain 全部被拒（3 个 Pod 全在），但 `kubectl delete pod` 照样删掉（3→2）。**PDB 是协商机制，不是保护罩**
3. **`ALLOWED = currentHealthy - desiredHealthy`（下限 0）** —— 验证前必须等副本 Ready，否则会误以为"PDB 算错了"（**复验时踩到的坑**）
4. **PDB 五种配置实测**：`minAvailable=2`/`maxUnavailable=1`/`60%` → ALLOWED=1、DESIRED=2；**`100%` → ALLOWED=0（完全锁死，节点永远维护不了）**
5. **百分比向上取整**：3×60%=1.8 → DESIRED=2
6. **drain 的三个坑**：DaemonSet（`--ignore-daemonsets`）/ emptyDir（`--delete-emptydir-data`）/ **裸 Pod**（实测报错 `cannot delete Pods that declare no controller`）
7. **PDB conditions** `DisruptionAllowed=False / reason=InsufficientPods` 是诊断金矿
8. ⚠️ **优雅关闭默认 `shutdownGracePeriod: 0s` = 未启用**（实测），生产需配 30s/10s（前 20s 普通 Pod、后 10s 关键 Pod）
9. ⚠️ **非计划关机靠 5 分钟容忍兜底**（实测 `tolerationSeconds: 300`），**StatefulSet 会卡 Terminating**，需手动加 `out-of-service` 污点
10. **kubeadm 只交付控制面 + 节点接入**，CNI/存储/Ingress/监控/备份一律自己来
11. **CA 10 年（87600h）、组件证书 1 年（8760h）**（实测）
12. **升级不能跳次版本**；**kubelet 不能比 apiserver 新**；顺序：控制面 → worker
13. 🎯 **etcd 3.6 起 `etcdctl snapshot restore` 被移除，改用 `etcdutl`** —— 本集群实测 etcd 3.6.4，**老教程的恢复命令跑不通**
14. **HA 最少 3 节点**（etcd 需 (N/2)+1 票，**偶数无意义**）；**必须 L4 负载均衡**（L7 破坏 mTLS 与流式连接）；**HA 不替代备份**

> ⚠️ **三处诚实标注**：
> ① **知识点 2-5 的流程未在本环境跑通**（需多机/真实关机/集群升级/多控制面节点），凡标 📄 的均为文档结论，凡标 ✅ 的配置值与字段均为本机实测。
> ② **`disruptionsAllowed` 瞬时观察会失真**（Deployment 自愈会掩盖缺口），要看稳态。
> ③ **单节点 drain 无法完整演练**：PDB 的"阻止驱逐"验证成功，但"驱逐后在别处重建"单节点看不到。

## ✅ 课 20 完成情况（2026-09-14 · 全课程收官）

**讲义**：[lesson-20-扩展机制与决策收口.md](lessons/lesson-20-扩展机制与决策收口.md)

**阶段状态**：**阶段 6 完成，全课程 20 课已全部交付。**

**本课结构**：知识点 1（CRD）、2（Operator）、3（聚合层）**可实操**；知识点 4（CNI/CRI/CSI）**部分可验**（CNI、CRI 已实测，**CSI 本集群无驱动**）；知识点 5（该不该用 k8s）为**决策课**。

**本课核心结论（除标注项外全部本机实测，共 16 项）**：

1. 🎯 **CRD 是"菜单"不是"后厨"** —— 建好 CRD 后 kubectl 立刻认识（含 shortNames），**但什么都不会发生**；**CRD + 控制器 = Operator**
2. **schema 校验服务端生效**：报错原文 `spec.target in body must be of type string`
3. 🎯 **kubectl 客户端会先做 strict decoding** —— 未知字段在发出前就被拒，`strict decoding error`。**要测服务端 pruning 必须用 `--validate=false` 绕过**（**最容易被误判为"pruning 没生效"的坑**）
4. **服务端 pruning 生效**（两种方式验证：`--validate=false`、API 直调）；用 `x-kubernetes-preserve-unknown-fields: true` 可保留未知字段
5. **CRD 命名规则**：`metadata.name` 必须 = `<plural>.<group>`（**实测报错原文** `must be spec.names.plural+"."+spec.group`）
6. **status 子资源保护**：`--subresource=status` 可写；普通 patch 返回 `no change` 且值不变 —— **分离 spec/status，避免控制器写 status 触发死循环**
7. **generation 只在 spec 变化时递增**（改 status 1→1，改 spec 1→2）—— 这是控制器判断"要不要干活"的依据
8. 🎯 **`observedGeneration` 未在 schema 声明会被 pruning 静默移除** —— **我实际踩的坑**，证明"schema 不是可选装饰，是契约"
9. **finalizer 卡删除**与课 18 完全同构（`deletionTimestamp` + finalizers 非空）
10. **Operator 的核心是 level-triggered reconcile**（读状态→比较→行动→写 status），**幂等且最终一致**；mini-operator 实测第二遍直接 idle
11. **聚合层不是抽象概念** —— 本集群 metrics-server 就是（`SVC=kube-system/metrics-server`、AVAILABLE=True），**`kubectl top nodes` 真的取到数据**（112m CPU / 1517Mi）
12. **CRD vs 聚合层**：CRD 简单、存 etcd、零运维；聚合层灵活、可自定义存储、但要自己维护一个可能挂的服务
13. **CNI=kindnet（ptp + host-local）**、**CRI=containerd 2.1.3**（均已实测）；**本集群无 CSI 驱动**（`csidriver` 为空，local-path 非 CSI）
14. 🎯 **该不该用 k8s 的判据**：**消除的复杂度 > 引入的复杂度**，不是"能不能"；"以后可能会扩展"是**愿望不是负载**

> ✅ **原三处诚实标注，2026-09-14 补做两处**（见补充讲义）：
> ① **知识点 5（该不该用 k8s）无命令可跑** —— 判据来自多篇业界分析与官方文档生产考量（标 📄）。**维持标注**。
> ② ~~**CSI 无法在本集群演练**~~ → **已补上**：安装 `csi-driver-host-path`（真 CSI 驱动，支持快照），
>    实测动态供给、卷快照 `readyToUse=true`、**从快照恢复出数据**、扩容 1Gi→2Gi。
> ③ ~~**聚合层只"观察"未"搭建"**~~ → **已补上**：自写 extension-apiserver（Go 标准库），
>    注册 APIService 并 `Available=True`，`kubectl get hellos` 完整 CRUD，**非 CRD**。
>
> 补充讲义：[lesson-20-补充-三大未竟实践.md](lessons/lesson-20-补充-三大未竟实践.md)（CSI / Webhook / 聚合层，全部实测）
> 补充讲义：[lesson-20-补充-三大未竟实践.md](lessons/lesson-20-补充-三大未竟实践.md)（CSI / Webhook / 聚合层，全部实测）
>
> 🔍 **2026-09-14 独立复审**（P0×2 + P1×1，均已修复并复验）：
> ① **P0-1**：「认知冲突 2」原证据无效——实验是在**已扩到 2Gi** 的卷上写 1.5G（本就在额度内）。复审重建环境重做：**真·1Gi 卷（PV capacity=1Gi，从未扩容）写 1.5G，`dd_exit=0` 无报错** → **结论成立，证据已换新**。
> ② **P0-2**：急救命令原用 `jq`，**实测本机 `jq: command not found`**；且第一版改的 `kubectl patch ns` 在真卡死时**无效**（返回 `patched (no change)`、仍 Terminating）——必须走 `/finalize` 子资源，已按实测订正。
> ③ **P1**：删 APIService 后**需等 30 秒以上**才释放（实测第 20 秒仍在 Terminating）。
> **确认属实**：坏 APIService 拖死 ns（`NamespaceDeletionDiscoveryFailure=True`）、SA token 可绕过 RBAC 直连（401/200）、聚合层非 CRD（CRD 数为 0），均已实测复现。

## 本阶段产出

- [x] `lessons/lesson-18-系统化排障分层定位法.md`（2026-09-14 完成；双视角评审 P0 清零）
- [x] `lessons/lesson-19-集群运维与生命周期.md`（2026-09-14 完成；双视角评审 P0 清零）
- [x] `lessons/lesson-20-扩展机制与决策收口.md`（2026-09-14 完成；双视角评审 P0 清零 · **全课程收官**）
- [x] `lessons/lesson-20-补充-三大未竟实践.md`（2026-09-14 完成 · **补齐 CSI 快照 / Admission Webhook / 聚合层搭建三处空缺**）
- [x] `assets/lesson-19-节点维护三件套.svg`（2026-09-14 完成）
- [x] `assets/lesson-20-扩展机制与决策.svg`（2026-09-14 完成）

### 课级入口要素补齐（2026-09-15）

按 topic-teach 最新 skill 的「课级入口要素」硬约束，本阶段课 18-20（本轮补本质 + 处境对照 + 地图 + 衔接句），课 20-补充（全项补齐）已全部补齐六项要素（一句话本质 / 处境对照 / 一眼全局图 + 读图指引 / 本课地图 / 📖 文档核对 / 🧭 知识点衔接句），经 `verify.sh` 全量核验 P0=0。

**本阶段新增全局图**：lesson-20-补充-三处补完.svg

**真实性纪律**：处境对照一律不给编造数字，全部为机制层面对照，无把握处标 ⏳；📖 留痕仅在确认真实引用官方文档后补写。
