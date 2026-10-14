# 对象体系专项（Kubernetes · 子教程）

> 定位：面向**已经会写 YAML、却说不清 k8s 里到底有哪些对象**的人——把「对象长什么样、分几类、谁创建谁、改动谁来落实」这摊事一次说清。
> 前置：主线**阶段 1（心智模型与架构）**的课 2（声明式 API）与课 3（Pod）；本专项**不重复主线的用法教学**，只讲「对象」这一层。
> 怎么进入：① 主线 20 课学完 → 直接按下面课清单学；② 只想搞懂对象体系 → 先补主线课 2、课 3，或按各课课首「前置提示」回看。

## 为什么有这个专项

主线教程里「对象」是**隐形的**——Pod、Deployment、Service、Event 各讲各的，但**从没有一课把它们放在一起讲**。实测核查（2026-10-14）：

| 核查项 | 实测结果 |
|--------|---------|
| 全仓 grep `对象全景｜对象总览｜对象速查｜对象关系图｜对象一览` | **0 命中** |
| 全仓 grep `kind=Event｜kind: Event｜Event 对象｜Event TTL` | **0 命中** |
| `final-课程手册.md` 速查表合订本 | 只有 5.1 端口 / 5.2 时间 / 5.3 默认行为 / 5.4 数字 / 5.5 排障，**无对象清单表** |
| Event 在主线的出场方式 | 仅在课 18 当**排障工具**用（`describe` 的 Events 段、`get events`），**从未当对象讲** |
| Lease 在主线的出场方式 | 仅 Python 客户端专项「多副本选主」用到，**主线从未把它当对象介绍** |
| 「命名空间级 vs 集群级」的说法 | 散在课 15、kubectl 专项课 1、课 20，且三处数字不一致（10/58、35/33、36/34，因集群 CRD 不同） |

对象体系是**横切知识**——塞进任何一课都会打断该课主线（讲 Service 时插一半讲「Service 和 EndpointSlice 谁管谁」，两边都讲不透）。故单独立项。

本专项**不是 API 参考**（`kubectl api-resources` + `kubectl explain` 就是参考）。它讲四件参考不讲的事：

- **统一长相**：为什么所有对象都是同一套四段式，spec 与 status 各自归谁写。
- **两类住址**：哪些对象在命名空间里、哪些不在，以及判断依据是什么。
- **谁生谁**：ownerReference 是怎么把对象串成一棵树的，删一个会带走谁。
- **长什么样**：每个常用对象的**最小可运行 YAML** 长什么样（见下方「硬承诺」）。

## 与主线的关系

主线走的是**「我要跑一个应用」的任务视角**（要部署无状态服务 → 写 Deployment）；本专项走的是**「这些东西都是什么」的体系视角**（Deployment 是一个对象，它和 ReplicaSet、Pod 是同一个模型的不同实例）。

| 主线已讲（不重复） | 本专项补的对象视角 |
|--------------------|--------------------|
| [课 2：声明式 API 与调谐循环](../../stages/1-心智模型与架构/lessons/02-声明式API与调谐循环.md)：对象四段式与 `api-resources` 的 NAMESPACED 列（为讲声明式服务） | 课 1：把四段式**拆到字段级**，逐个说清每段的职责边界与「谁有权写」 |
| [课 3：Pod 最小调度单元](../../stages/1-心智模型与架构/lessons/03-Pod最小调度单元.md)：Pod YAML 怎么写 | 课 1：Pod 只是**万千对象中的一个样例**，抽象出通用于所有对象的模型 |
| [课 5：Deployment](../../stages/2-工作负载与控制器/lessons/05-Deployment无状态应用.md)：Deployment→RS→Pod 归属链（讲副本管理时带出） | 课 3：把 ownerReference **当成独立机制**讲透（字段长相 / 三种级联策略 / 孤儿 / finalizer 卡住） |
| [课 7：Service 与 CoreDNS](../../stages/3-网络与服务暴露/lessons/07-Service与CoreDNS.md)：Service 怎么用 | 课 4、课 6：Service **不直接管 Pod**——它生成 EndpointSlice，这是「控制器生成对象」的另一条链 |
| [课 18：系统化排障](../../stages/6-排障运维与扩展/lessons/18-系统化排障分层定位法.md)：Event 当取证工具 | 课 4：Event **本身是个对象**——`v1/Event`、命名空间级、kubelet 与控制器写、默认 1h 过期、不在 ownerReference 链上 |
| [课 15：RBAC](../../stages/5-安全体系/lessons/15-RBAC与ServiceAccount.md)：命名空间级 vs 集群级对比表（为讲授权） | 课 2：把两级划分**讲成对象体系的通律**，并给可查清单与判断方法 |
| [课 20：扩展机制](../../stages/6-排障运维与扩展/lessons/20-扩展机制与决策收口.md)：CRD / API 聚合 | 课 6：CRD 与 APIService 作为**「对象种类本身也是对象」**的收束点 |

- 主线「提及级」带过、未展开的对象话题，在本专项逐条兑现（上表右列）。
- 与 [Python 客户端专项](../Python客户端专项/overview.md) 的分工：那门专项讲 **GVK → Python 类名怎么映射**（写代码时用）；本专项讲 **对象本身是什么、彼此什么关系**（读 YAML 时用）。两门互补，不重叠。
- 与 [09-排障速查手册](../../09-排障速查手册.md) 的分工：手册是**出事时翻**（症状 → 命令）；本专项是**平时学**（模型 → 清单 → YAML）。

## 故事主线

- **主角**：一个能照着模板写出 Deployment YAML、跑通就交差，但被问「集群里到底有哪些对象」时只能数出三四个的人
- **冲突**：对象见过几十个，却没见过它们的**统一长相**；知道 Deployment 会生出 Pod，却不知道这层关系写在哪个字段里；`kubectl get all` 明明叫 all，却漏掉了 ConfigMap、Secret、PVC；Event 天天看，从没想过它也是个对象
- **收束**：学完后能回答"**k8s 的对象分几类、每一类长什么样、谁创建谁、我写的那段 YAML 最终由谁去落实**"

## 课清单

| 课 | 知识点（关键点） | 对应主线提及 |
|----|-----------------|-------------|
| [课 1：一切皆对象——四段式与 YAML 解剖](lessons/01-一切皆对象：四段式与YAML解剖.md) | 对象是「意图 + 现状」的双栏表（spec 你写 / status 系统写 / **status 是子资源，改了不生效**）；四段式逐字段（apiVersion=group/version、**core 组为什么省略组名**、kind、metadata、spec）；metadata 通用字段逐个拆（**uid 是 ownerReference 的锚** / resourceVersion 乐观锁 / finalizers / managedFields 谁改过哪字段） | 课 2（四段式概念）、课 3（Pod YAML） |
| [课 2：两个住址——命名空间级与集群级](lessons/02-两个住址：命名空间级与集群级.md) | 为什么分两级（租户内 vs 全集群共享）；怎么查（`api-resources` 的 NAMESPACED 列，**实测数字随集群 CRD 而变**）；集群级对象完整清单 + YAML（Node / Namespace / PV / StorageClass / ClusterRole / CRD…）；**坑：集群级对象加 `-n` 不报错**；**删命名空间会连带清空里面所有对象** | 课 2（资源模型）、课 15（两级对比表） |
| [课 3：谁生谁——ownerReference 与级联删除](lessons/03-谁生谁：ownerReference与级联删除.md) | ownerReference 字段长什么样（实测从 Pod 上抓真值）；三种级联策略（Foreground / Background / **Orphan 实测留下孤儿 Pod**）；**Event 和 Lease 为什么不在链上**（避免级联爆炸）；删除卡住与 finalizer（命名空间 Terminating） | 课 5（Deployment→RS→Pod）、课 18（查 Event 取证） |
| [课 4：自己冒出来的对象——Event 与 Lease](lessons/04-自己冒出来的对象：Event与Lease.md) | Event 作为对象（`v1/Event` / 命名空间级 / **不是 Pod 的子对象** / 默认 1h TTL / `count` 聚合 / 谁写的它 / 完整 YAML）；Lease（`coordination.k8s.io/v1` / 节点心跳 + 选主 / **为什么不用 ConfigMap 而单独造一个** / YAML）；控制器生成对象全景链（Service→EndpointSlice、CronJob→Job→Pod、Deployment→RS→Pod） | 课 18（Event 当工具）、课 12（PV/PVC 绑定）、课 7（Service） |
| [课 5：对象总表（上）——工作负载 · 配置 · 存储](lessons/05-对象总表上：工作负载·配置·存储.md)（✅ 已完成 · 2026-10-14 · **YAML 实测 12/12**） | 三类工作负载的**爹不同**：Deployment 的 Pod 认 **ReplicaSet**、StatefulSet 的 Pod **直接认 StatefulSet**（实测对照）；CronJob 三层 spec 嵌套；**Job 的 restartPolicy 不能是 Always**；**StatefulSet 的 serviceName 必填**；`stringData` vs `data`（免手动 base64）；**Secret 是编码不是加密**；PVC/PV/StorageClass 三者对照（PVC 实测 Pending 属正常） | 课 3、课 5、课 6、课 11、课 12 |
| [课 6：对象总表（下）——网络 · 安全 · 策略 · 扩展](lessons/06-对象总表下：网络·安全·策略·扩展.md)（✅ 已完成 · 2026-10-14 · **YAML 实测 14/14**） | 网络组（Service→**EndpointSlice** 实测爹是 Service / Ingress 需控制器才生效 / NetworkPolicy **默认全通**）；安全组（**ClusterRole+RoleBinding = 把集群权限收窄到单租户**）；策略组（ResourceQuota 管总量 vs LimitRange 管个体 / HPA 需 metrics-server / PDB **只挡自愿中断**）；**CRD 闭环实测**：建 CRD → `api-resources` 多出 `widgets` → 用它建 `Widget` 对象成功，证明**对象种类本身也是对象** | 课 7-10、课 13、课 15、课 16、课 19、课 20 |

> 📌 **课 5、课 6 是本专项的重点交付**：两个课合计覆盖 **30+ 个常用对象**，每个都给一份**最小可运行 YAML**（`kubectl apply` 实测通过），并标注「谁创建它 / 命名空间级还是集群级 / 归哪个 API 组」。

## 学习路径

```text
课 1 统一长相（四段式 → spec/status 分工 → metadata 通用字段）
      └→ 课 2 两个住址（命名空间级 vs 集群级 → 怎么查 → 坑）
           └→ 课 3 谁生谁（ownerReference → 级联删除 → finalizer 卡住）
                └→ 课 4 自己冒出来的（Event / Lease / 控制器生成对象链）
                     ├→ 课 5 对象总表上（工作负载 · 配置 · 存储 · 30+YAML）
                     └→ 课 6 对象总表下（网络 · 安全 · 策略 · 扩展 · 30+YAML）
```

依赖顺序：课 1 是地基（不知道「对象长什么样」，后面每课都得回头补）；课 2 承接课 1 的 metadata.namespace；课 3 承接课 1 的 metadata.uid；课 4 承接课 3 的「不在链上」；课 5、课 6 是**总表**，可按需跳查，但每份 YAML 的字段都依赖课 1 的四段式。

## 学习进度

> 子教程进度独立记录于此（不混主线进度表）；课文件生成并学完后勾选。

- [x] 课 1：一切皆对象——四段式与 YAML 解剖（✅ 2026-10-14 · P0=0）
- [x] 课 2：两个住址——命名空间级与集群级（✅ 2026-10-14 · P0=0）
- [x] 课 3：谁生谁——ownerReference 与级联删除（✅ 2026-10-14 · P0=0）
- [x] 课 4：自己冒出来的对象——Event 与 Lease（✅ 2026-10-14 · P0=0）
- [x] 课 5：对象总表上——工作负载 · 配置 · 存储（✅ 2026-10-14 · P0=0 · YAML 实测 12/12）
- [x] 课 6：对象总表下——网络 · 安全 · 策略 · 扩展（✅ 2026-10-14 · P0=0 · YAML 实测 14/14）

## 边界声明

- **不重复主线**：主线已系统讲过的用法（Deployment 滚动更新怎么配、Service 怎么选后端、RBAC 怎么授权）不重讲，只补**对象层**的视角、字段与清单。
- **不做 API 参考**：`kubectl api-resources` / `kubectl explain` / [官方 API 参考](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.34/) 已经做得很好，本专项讲**参考不讲的东西**（统一模型、归类逻辑、关系链、实测 YAML）。
- 🟢 **硬承诺：每个对象都给可运行 YAML**。凡是本专项列为「对象」的条目，**必配一份最小可运行 YAML**，且满足三条：① 在 kind 集群 `kubectl apply` 实测通过；② 能从集群 `get -o yaml` 抓回真实对象并贴出关键片段；③ 标注「命名空间级 / 集群级」+「谁创建它」。**未实测的模板一律标 `⚠️ 未实测（原因）`**，不凭文档拼凑。
- **不配课级应用实战 / 源码解析**：按子教程轻量口径，`应用实战/`、`源码解析/` 只收主线课。
- **实测口径**：结论一律以**本机实测**为准（kubectl v1.34.0 / kind 集群 `k8s-c1` 3 节点 / k8s v1.34.0 / WSL2 Ubuntu 24.04 / bash 5.2.21）。**未能实测的项逐条标 `⚠️ 未实测（原因）`**。
- **环境改动纪律**：本专项以**创建对象 → 取证 → 清理**为主；全部写操作隔离在**一次性命名空间 `obj-lab`**，课后清理并断言零残留；**不改动既有集群的系统组件与 kube-system 命名空间**。

## 参考资料

已索引的官方文档（见 [k8s/web-index](../../web-index/INDEX.md)）：

| 用途 | 文档 |
|------|------|
| 对象模型总纲 | [Kubernetes 对象](https://kubernetes.io/zh-cn/docs/concepts/overview/working-with-objects/kubernetes-objects/) |
| 命名空间 | [命名空间](https://kubernetes.io/zh-cn/docs/concepts/overview/working-with-objects/namespaces/) |
| 标签与注解 | [标签和选择算符](https://kubernetes.io/zh-cn/docs/concepts/overview/working-with-objects/labels/) |
| 属主与级联 | [属主引用与垃圾回收](https://kubernetes.io/zh-cn/docs/concepts/architecture/garbage-collection/) |
| API 约定 | [API 约定](https://kubernetes.io/docs/reference/using-api/api-concepts/) |

> 💡 索引自身的建议：**字段级细节优先 `kubectl explain`**，比 fetch 文档快。本专项遵循此建议——凡能用本机 `explain` / `get -o yaml` 验证的，一律实测而非抄文档。

## 评审记录

| 日期 | 评审节点 | 方式 | 结论 |
|------|----------|------|------|
| 2026-10-14 | **教学效果推演（Step 1.2a rehearsal）** | 主 agent 内联推演 | **无 🔴 零覆盖**。提取 12 个高频场景（写新应用 YAML 不知字段 / 判断要不要写 namespace / 删 Deployment 后 Pod 还在 / `get all` 漏 ConfigMap·Secret·PVC / Event 为何 1h 消失 / Lease 是什么 / 删命名空间卡住 Terminating / 改 status 不生效 / 哪些对象不能备份 / 自己写 CRD 归哪个组 / 查命名空间里有哪些对象 / 判断某对象归谁管）+ 5 个理论问题（status 为何不由用户写 / Event 为何不是 Pod 子对象 / Node 为何集群级 / uid 的用途 / 级联删除靠什么机制）。覆盖矩阵：课 1 承接 3 场景 + 2 理论，课 2 承接 3 场景 + 1 理论，课 3 承接 3 场景 + 2 理论，课 4 承接 2 场景，课 5/6 承接 3 场景 + 1 设计决策。**结论：推演通过（未实测）** |
| 2026-10-14 | **专项大纲评审（Step 1.2b pedagogy）** | 主 agent 内联（course-reviewer 子 agent 未创建，独立性受限） | **P0=0**。前置链 课1→课2→课3→课4→课5/6 无缺口；与主线边界清晰（主线讲用法、本专项讲对象层）；按子教程轻量口径判定**不设独立环境准备课**（读者已有主线环境，前置在 overview 声明）、**不配应用实战与源码解析**（子教程豁免）。**需用户确认**：故事主线方向（主角：会写 YAML 但说不清对象体系的人 / 冲突：见过几十个对象却没见过统一长相 / 收束：能回答对象分几类、谁创建谁）是否合适——不合适可调整，其余结构已落盘 |
| 2026-10-14 | **专项交付验收（课 1–6 全部完成 · 环境卫生）** | 主 agent 交叉核对 + 实跑验证 | **P0=0 · 六课全部交付**。**YAML 硬承诺兑现**：课 5 实测 **12/12**、课 6 实测 **14/14**（合计 **26 份最小可运行 YAML** 全部 `kubectl apply` 通过），验证脚本留档 `assets/课5-YAML验证.sh` / `assets/课6-YAML验证.sh`。**环境卫生核验通过**：6 个一次性命名空间 + 6 个集群级对象（PV / StorageClass / CRD / ClusterRole / ClusterRoleBinding / IngressClass）**全部 NotFound 零残留**。**关键实测结论（本专项补齐的主线缺口）**：① Event 有 `involvedObject` 但 **ownerReferences 为空**（它不是 Pod 子对象）；② Lease **反而有 ownerReference 指向 Node**，与 Event 形成反直觉对照；③ Pod 的爹是 **ReplicaSet** 而 StatefulSet 的 Pod **直接认 StatefulSet**；④ Service 自动生成的 **EndpointSlice 爹是 Service**；⑤ **CRD 闭环**——建 CRD → `api-resources` 多出 `widgets` → 建 `Widget` 成功，证明「对象种类本身也是对象」 |
| 2026-10-14 | **课 2–课 6（批次内容评审）** | 主 agent 内联双视角（pedagogy + learner 全维度，子 agent 未创建，独立性受限） | **P0=0**。逐课核：五幕齐备、**每课「一眼全局图」SVG 齐备**（课 2「两级住址」/ 课 3「血缘链」/ 课 4「没有爹的对象」/ 课 5「谁直接管 Pod」/ 课 6「四组叠加」共 5 张，加课 1 共 6 张）；术语双轨落地；敏感信息扫描通过（示例一律 `example.com` / 虚构用户 / 一次性命名空间取值）。**课 2 实测**：本集群集群级 **33** / 命名空间级 **35**（随 CRD 变化，已标注"别当常数"）、集群级加 `-n` **退出码 0 静默忽略**、**`get all` 在只有 ConfigMap/Secret 时输出 `No resources found`**、删 ns 连带清空。**课 3 实测**：**`--cascade=orphan` 留下的是整棵子树（RS 也活着，Pod 不是真孤儿）**、finalizer 卡住后 `deletionTimestamp` 存在。**课 4 实测**：一个 Pod 8 秒内产生 **4 条 Event**（kubelet 3 + scheduler 1）、节点 Lease `leaseDurationSeconds: 40` |
| 2026-10-14 | **课 1「一切皆对象：四段式与 YAML 解剖」** | 主 agent 内联双视角（pedagogy + learner 全维度，子 agent 未创建，独立性受限） | **P0=0**。pedagogy 逐项核：五幕齐备、四段式拆解有实测真值支撑、**`--subresource=status` 报 patched 却被 kubelet 抢回**这一反直觉结论已实测取证（写入正文第二幕作认知冲突）、乐观锁 Conflict 报错原文照抄实测、managedFields 两行真值（`kubectl-client-side-apply` + `kubelet`）实证「status 有唯一作者」；术语双轨落地；**敏感信息扫描通过**。learner 视角：第一幕以「抄了三个月 YAML 却答不上三个问题」开场、非定义式（锚点通过）；认知阶梯 感知→概念→机制→定位 递进，无骤增。🟡 **P1 待办 1 项已修**：课 1 原称 Pod YAML「11 行」为计数自述，已改为「约 11 行」。环境：写操作隔离 `obj-lab`，课后删除并断言 NotFound 零残留 |
