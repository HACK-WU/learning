# kubectl 专项（Kubernetes · 子教程）

> 定位：面向**每天敲 kubectl 的人**——把「这条命令怎么找到集群、输出怎么看、改对象有几种改法、怎么敲得快又不踩坑」这摊事说清。
> 前置：主线**阶段 1（心智模型与架构）**的基础知识（Pod / 声明式 API / 资源模型）；子教程**不重复主线内容**，只讲 kubectl 这一层。
> 怎么进入：① 已学主线 → 直接按下面的课清单学；② 只想搞懂 kubectl → 先补主线课 1-2，或按各课课首的「前置提示」按需回看。

## 为什么有这个专项

主线教程里 kubectl 是**隐形的**——它出现在 816 次 `get`、240 次 `apply`、202 次 `exec` 里，但**从没有一课系统讲过它自己**。实测核查（2026-10-09）：

| 核查项 | 实测结果 |
|--------|---------|
| 文件名含 `kubectl` 的课程文件 | **0 个** |
| 标题级专门章节 | **1 处**（课 2「kubectl 与 API 资源模型」，讲的是资源模型不是命令用法） |
| 完全没讲过的子命令 | `certificate`（0 次）、`api-versions`（0 次） |
| 几乎没讲过的子命令 | `edit`（4）、`expose`（4）、`proxy`（4）、`autoscale`（4）、`annotate`（5） |

kubectl 是**横切工具**——塞进任何一课都会打断该课主线（讲 Service 时插一半讲 `-o jsonpath`，两边都讲不透）。故单独立项。

本专项**不是命令大全**（`kubectl --help` 就是命令大全）。它讲三件 `--help` 不讲的事：

- **为什么**：为什么敲 `kubectl get pods` 就能找到集群（kubeconfig → context → 认证三段式）。
- **怎么看**：`get` 的输出体系有几种、什么时候该用 `-o jsonpath` 而不是 `grep`。
- **怎么不踩坑**：`apply` 的三方合并、`patch` 的三种语义、`--dry-run` 的边界。

## 与主线的关系

主线走的是**集群使用者视角**（我要跑一个应用，怎么写 YAML）；本教程走的是**命令行操作者视角**（我怎么把这条命令敲对、敲快、看懂输出）。

| 主线已讲（不重复） | 本教程补的 kubectl 视角 |
|--------------------|------------------------|
| [00-环境准备](../../00-环境准备.md)：装 kubectl / kind / helm 三件套 | 课 1：kubectl 怎么**找到**集群（kubeconfig 三段式、context 切换、多集群）、命令结构解剖 |
| 课 2：kubectl 与 API 资源模型（GVK/GVR 概念） | 课 1：把概念变成**能敲的命令**（`api-resources` / `api-versions` / `explain` 自查字段） |
| 课 7：标签与选择算符（概念） | 课 2：`-l` 标签选择器与 `--field-selector` 的**实操差异**与坑 |
| 课 2：`kubectl apply` 与声明式（概念层） | 课 3：apply 的**三方合并**机制、`patch` 三种语义的实测对比、`edit`/`replace` 取舍 |
| 课 18：分层排障（用 kubectl 取证） | 课 4：`kubectl debug` 临时容器、`--request-timeout`、高频坑与效率配置 |

- 主线"提及级"带过、未展开的 kubectl 话题，在本教程逐条兑现（上表右列）。
- 与 [09-排障速查手册](../../09-排障速查手册.md) 的分工：手册是**出事时翻**（症状 → 命令），本教程是**平时学**（机制 → 用法 → 坑）。
- 与 [kind 专项](../kind专项/overview.md) 的分工：kind 专项讲「集群怎么造出来」，本专项讲「造出来之后怎么操作它」。

## 故事主线

- **主角**：一个会敲 `kubectl get pods`，但每次遇到新需求都要搜命令的人
- **冲突**：命令能跑通，但不知道为什么；输出看得懂，但不知道怎么只取想要的字段；改对象只会 `apply`，不知道还有 `patch`/`edit`/`replace` 三种改法及其后果
- **收束**：学完后能回答"**kubectl 这条命令从敲下到返回，中间发生了什么；以及我要的字段/改法/效率，分别该用什么**"

## 课清单

| 课 | 知识点（关键点） | 对应主线提及 |
|----|-----------------|-------------|
| [课 1：kubectl 怎么找到集群](lessons/01-kubectl怎么找到集群.md)（✅ 已完成 · 2026-10-09） | 命令四段式解剖；kubeconfig 三段式（clusters/users/contexts）与 context 切换（实测 4 个 context、地址 `127.0.0.1:45145`）；资源模型落地（`api-resources` **68 条随集群而变** / `api-versions` 24 条 / 四种 TYPE 写法等价实测 9=9=9 / **同名不同组** `pods` vs `pods.metrics.k8s.io`）；**集群级资源加 `-n` 不报错**；`explain` 自查字段（无 `FIELD:` 行即不存在）；**`version --short` 在 v1.34 已移除** | 环境准备（装工具）、课 2（GVK/GVR 概念） |
| [课 2：查看与筛选](lessons/02-查看与筛选.md)（✅ 已完成 · 2026-10-09） | 五种输出实测**体积对比**（默认 126 B / wide 259 B / yaml 5889 B / json 12374 B / jsonpath 24 B → **默认仅是完整对象的约 1%**）；jsonpath 七种语法逐条实测（**`[*]` 输出末尾无换行，`wc -l` 数不到行**）；**jsonpath 不支持正则**（实测报错 `unrecognized character in action: U+007E '~'`）；custom-columns vs jsonpath 选型（前者带表头不可过滤、后者可过滤）；`-l` 六种运算符实测；**`--field-selector` 与 `-l` 本质区别**（筛固有字段 vs 筛标签，不支持的字段报 `field label not supported`）；**反测法**（用必然不匹配的值确认 selector 生效而非被静默忽略）；**`-A` 首列是 NAMESPACE 不是 NAME** | 课 7（标签概念）、课 18（取证） |
| [课 3：改写与调试](lessons/03-改写与调试.md)（✅ 已完成 · 2026-10-09） | **apply 三方合并**（`last-applied` 注解是它的"记忆"，实测含空 `"annotations":{}`）；**删字段要走两步**——别人 patch 加的字段 apply 删不掉（实测 `c` 三次 apply 仍在），须先声明收归再删；**patch 三种语义天差地别**：strategic 按 mergeKey 合并（追加成功但**新元素排最前**）、merge **数组整体替换**（实测报 `image: Required value`，补上 image 后 ports 被**整体替换只剩一个**）、json RFC6902 按路径精确操作（`/-` 追加在**末尾**）；官方 `explain` 自带警告"ports 数组 strategic patch 可能损坏数据"（issue #108255）；**`diff` 有差异退出码=1**（`set -e` 脚本会中断，须 `|| true`）；**`--dry-run=server` 能拦 unknown field**（client 通过、server 报 `strict decoding error`）；**`replace` 全量覆盖缺必填字段直接崩**、**`--force` = 删除+重建**（实测 uid 前后不同 + 输出含 `deleted from`）；**SSA 不用 last-applied 改用 managedFields**，字段级冲突检测（实测 `conflict with "kubectl-patch"`，`--force-conflicts` 强接管） | 课 2（声明式概念）、课 14（Kustomize） |
| [课 4：效率与坑](lessons/04-效率与坑.md)（✅ 已完成 · 2026-10-09） | **补全入口函数是 `__start_kubectl`，不是网上流传的 `__kubectl_get_resource`**（实测后者在本机 v1.34 补全脚本里 grep 计数为 0）；**`alias k` 会丢补全**，须补 `complete -o default -F __start_kubectl k`；**`explain --recursive` 输出 1216 行**，正确用法是配 grep 靠缩进判层级；**多容器 `logs` 不写 `-c` 不报错、静默选一个**（实测提示 Defaulted container）；**`--previous` 需 `restartPolicy≠Never`**（实测两轮时间戳差 6 秒证明是不同实例）；**`events` 默认不排序且只留 1h**；**`debug --copy-to` 不动原 Pod**，**节点调试 Pod 落在 `default` 且必须手动删**（本课复验实测残留 1 个，标签选择器删不掉）；**`create --save-config` 根治 apply 首次告警**；**`-v=6` 统计请求数的正确关键词是 verb="GET"** | 全部已交付课（专项收尾） |

| [课 5：进到容器里](lessons/05-进到容器里.md)（✅ 2026-10-09 · 复验 26/26） | **exec 每次是新起进程**（实测 PID 1805→1811，破 SSH 登录直觉）；SPDY 升级链路（kubectl → API Server → kubelet → 容器 namespace）；**退出码原样透传**（`exit 42`→42，可进脚本判断）；**不写 `--` 有两类报错**（`not supported anymore` / 带 flag 时 `unknown shorthand flag: 'l'` 被 kubectl 吃掉）；多容器不写 `-c` **不报错静默选第一个**（`exec`/`logs`/`cp` 三者同坑）；**`-i` 才是 stdin 开关**（无 `-i` 管道输入为空）；**纠正速查一处错误**：`-t` 无 CRLF 污染（`od -c` 跑三次实测均为 `\n`，原说法凭推断未实测）；attach 连 PID 1 且**会话内容会被记进容器日志**（含凭证） | 课 18（取证）、参数速查（exec 参数级） |
| [课 6：发布与回滚](lessons/06-发布与回滚.md)（✅ 2026-10-09 · 复验 32/32） | **revision 存在 RS 上、Deployment 只记一个数字**（核心心智模型）；**`undo` 创建新 revision 号**而非退回旧号（回滚到 rev4 内容，当前号变 26）；revision 号**不连续**（3→4→5→8→14，非 template 改动消耗号）；`revisionHistoryLimit=10` 淘汰旧版本；**`pause` 攒改动**（generation 涨、RS 不变，resume 后合并成一次发布）；**`restart` 改 `restartedAt` 注解不改镜像**；`--record` 已废弃致 `CHANGE-CAUSE` 恒 `<none>`；**两个"退出码 0 不代表成功"**：`skipped rollback`（回滚到当前版）、**已淘汰版本是明确报错退出码 1**（我一度凭印象写成静默失败，单独验证后更正） | 课 2（声明式）、课 3（apply 触发发布） |

## 📚 配套速查（非课）

四课讲**机制与取舍**，参数全集在 `kubectl --help`。为补二者之间的空隙，另出一本**详细参数速查**：

| 文档 | 内容 | 状态 |
|------|------|------|
| [参数速查.md](参数速查.md) | 补四课未覆盖的 **80 项 flag/命令**，每条含「是什么 → 实测输出 → 什么时候用 → 坑」；7 章含退出码表与 8 条反直觉结论 | ✅ 已完成 · 2026-10-09 · 复验 31/31 |

**为什么需要它**：覆盖度实测显示四课的子命令覆盖率 **51%（22/43）**、全局 flag **29%（10/35）**，`exec` **0%**（主线却出现 202 次）。`drain`/`cordon`/`taint` 等影响节点调度的命令在速查中**全程 dry-run 演示**。

> 分工：本专项解决「为什么」与「怎么选」，速查解决「这个参数到底怎么用」，二者互补而非替代。

## 学习路径

```text
课 1 找到集群（命令结构 → kubeconfig → 资源模型）
      └→ 课 2 查看筛选（输出体系 → jsonpath → 选择器）
           └→ 课 3 改写调试（apply → patch → diff/dry-run）
                └→ 课 4 效率与坑（补全 → debug → 高频坑）
                     ├→ 课 5 进到容器里（exec → attach → 改了有用吗）
                     └→ 课 6 发布与回滚（revision → undo → pause）
                          └→ 参数速查（按需查阅，不必通读）
```

依赖顺序：课 1 是地基（不知道"命令怎么找到集群"，后面都是死记命令）；课 2 与课 3 相对独立，可按需跳课；课 4 建议随后学（它的坑同时依赖前三课的概念）；**课 5、课 6 是 2026-10-09 覆盖度核查后补的扩课**——`exec` / `rollout` 在四课中覆盖率均为 **0%**（`exec` 在主线出现 202 次），二者相对独立，可在课 3 之后任意位置学。

## 学习进度

> 子教程进度独立记录于此（不混主线进度表）；课文件生成并学完后勾选。

- [x] 课 1：kubectl 怎么找到集群（✅ 2026-10-09 完成 · P0=0 · 复验 26/26 全通过）
- [x] 课 2：查看与筛选（✅ 2026-10-09 完成 · P0=0 · 复验 33/33 全通过）
- [x] 课 3：改写与调试（✅ 2026-10-09 完成 · P0=0 · 复验 36/36 全通过）
- [x] 课 4：效率与坑（✅ 2026-10-09 完成 · P0=0 · 复验 54/54 全通过）

## 边界声明

- **不重复主线**：主线已系统讲过的概念（声明式、标签、Service、RBAC 等）不重讲，只补 kubectl 侧的操作与坑。
- **不做命令大全**：`kubectl --help` 与[官方快速参考](https://kubernetes.io/zh-cn/docs/reference/kubectl/quick-reference/)已经做得很好，本教程讲**文档不讲的东西**（机制、取舍、坑、实测边界）。
- **不配课级应用实战 / 源码解析**：按子教程轻量口径，`应用实战/`、`源码解析/` 只收主线课。
- **实测口径**：本教程结论一律以**本机实测**为准（kubectl v1.34.0 / kind v1.34.0 集群 / WSL2 Ubuntu 24.04 / bash 5.2.21）；**未能实测的项逐条标 `⚠️ 未实测（原因）`**，不凭文档推断。
  > ⚠️ **版本偏差提示**：本机 kubectl 为 **v1.34.0**，而[官方快速参考](https://kubernetes.io/zh-cn/docs/reference/kubectl/quick-reference/)标注适用于 **v1.37**。官方文档中部分命令在本机**已不适用**（实测 `kubectl version --short` 在 v1.34 报 `unknown flag`），凡文档与本机实测冲突处，**一律以实测为准并显式标注**。
- **环境改动纪律**：本教程以**只读查询**为主（`get` / `describe` / `explain` / `api-resources`）；涉及创建对象（`apply` / `patch`）的部分使用**一次性命名空间并在课后清理**，不污染既有集群。

## 参考资料

已索引的官方文档（见 [k8s/web-index](../../web-index/INDEX.md)）：

| 用途 | 文档 |
|------|------|
| 命令速记 | [kubectl 快速参考](https://kubernetes.io/zh-cn/docs/reference/kubectl/quick-reference/) |
| kubectl 是什么 | [kubectl 简介](https://kubernetes.io/zh-cn/docs/reference/kubectl/introduction/) |
| 命令约定 | [conventions](https://kubernetes.io/zh-cn/docs/reference/kubectl/conventions/) |
| jsonpath 语法 | [jsonpath](https://kubernetes.io/zh-cn/docs/reference/kubectl/jsonpath/) |
| docker 用户迁移 | [docker-cli-to-kubectl](https://kubernetes.io/zh-cn/docs/reference/kubectl/docker-cli-to-kubectl/) |
| kubectl 定位 | [kubectl](https://kubernetes.io/zh-cn/docs/concepts/overview/kubectl/) |

> 💡 索引自身的建议：**命令类细节优先 `kubectl explain` / `kubectl --help`，比 fetch 文档快**。本教程遵循此建议——凡能用本机 `--help` 验证的，一律实测而非抄文档。

## 📎 配套资产

| 资产 | 用途 | 用法 |
|------|------|------|
| [课1-复验.sh](assets/课1-复验.sh) | 课 1 讲义全命令照抄复验（26 项） | `wsl -- bash -c "bash '/mnt/d/projects/learning/k8s/子教程/kubectl专项/assets/课1-复验.sh'"` |
| [课4-复验.sh](assets/课4-复验.sh) | 课 4 讲义全命令照抄复验（54 项，含 node-debugger 清理与断言） | `wsl -- bash -c "bash '/mnt/d/projects/learning/k8s/子教程/kubectl专项/assets/课4-复验.sh'"` |
| [课3-复验.sh](assets/课3-复验.sh) | 课 3 讲义全命令照抄复验（36 项，含自动清理与清理断言） | `wsl -- bash -c "bash '/mnt/d/projects/learning/k8s/子教程/kubectl专项/assets/课3-复验.sh'"` |
| [课6-复验.sh](assets/课6-复验.sh) | 课 6 讲义全命令照抄复验（32 项，含 undo 两边界、pause 攒改动、restart 改注解） | `wsl -- bash -c "bash '/mnt/d/projects/learning/k8s/子教程/kubectl专项/assets/课6-复验.sh'"` |
| [课6-淘汰revision验证.sh](assets/课6-淘汰revision验证.sh) | 连改 13 次镜像把 rev1 挤出 history，验证「回滚到已淘汰版本」的真实报错与退出码 | `wsl -- bash -c "bash '/mnt/d/projects/learning/k8s/子教程/kubectl专项/assets/课6-淘汰revision验证.sh'"` |
| [课5-复验.sh](assets/课5-复验.sh) | 课 5 讲义全命令照抄复验（26 项，含 PID 递增、退出码透传、`-i` stdin 开关、`-t` 无 CRLF） | `wsl -- bash -c "bash '/mnt/d/projects/learning/k8s/子教程/kubectl专项/assets/课5-复验.sh'"` |
| [课2-复验.sh](assets/课2-复验.sh) | 课 2 讲义全命令照抄复验（33 项） | `wsl -- bash -c "bash '/mnt/d/projects/learning/k8s/子教程/kubectl专项/assets/课2-复验.sh'"` |

> ⚠️ 复验脚本会**切换 context** 到 `kind-k8s-c1` 并在结束后还原。若你的环境无此集群，请先改脚本里的基线 context 名。

## 评审记录

| 日期 | 评审节点 | 方式 | 结论 |
|------|----------|------|------|
| 2026-10-10 | **卫生处理（交付后收尾）** | 主 agent 交叉核对 + 实跑验证 | **P0=0**。**抓出并修复 3 处内部矛盾（均为此前遗漏）**：① **课 6 讲义 4.4 节残留矛盾**——同一份文档里一处写「`undo --to-revision=1` 回滚到已淘汰版本＝静默失败、退出码 0」，另一处已更正为「退出码 1 + 明确报错」，两处自相矛盾；已按实测统一为**明确报错 + 退出码 1**。② **转正资产 `课6-淘汰revision验证.sh` 判定分支仍按旧结论写**——断言 `RC=0 且镜像未变` 才通过，实测 RC=1 会走「与预期不符」分支；已改为断言 `RC≠0 + 镜像未变 + 报错含 unable to find specified revision`，并**实跑复验通过**（history 最小号=2，rev1 已淘汰，退出码 1）。③ **参数速查.md 遗留错误条目未同步**——「`-t` 污染输出为 CRLF」经课 5 `od -c` 三次实测推翻，但速查原文未修正；已改写该条并标注旧结论作废，同时把 `--to-revision`（未实测→已实测）、`attach vs exec`（未测→已实测）同步更新，新增「📌 更正记录」表。**另核对并纠正引用细节**：速查引用的实测命令原写 `-c app` 加 `sh -c` 包装，与课 5 讲义原文（`-c side`，无包装）不一致，已逐字对齐。**环境**：零残留核验通过（5 个 lab 命名空间全部 NotFound）；本轮 2 个临时脚本已删；`default/web` 经核查为 10-09 08:32 创建的历史遗留（非本轮产物），**未擅自删除** |
| 2026-10-09 | **课 5「进到容器里」+ 课 6「发布与回滚」**（覆盖度核查后**扩课**） | 主 agent 内联双视角 + 脚本复验 26 / 32 项 + 单独验证 1 项 | **P0=0（课5 26/26、课6 32/32 全通过）**。**立项依据**：`exec` 与 `rollout` 在四课中覆盖率**均为 0%**（`exec` 主线出现 202 次），故各扩一课。**课 5 自我纠错 1 处**：参数速查里「`-t` 污染输出为 CRLF」经 `od -c` 三次实测**推翻**（均为 `\n`）——该说法**凭推断未实测**，课 5 已明示纠正。**课 6 复验抓出 7 FAIL**，真缺陷 2 处（4.4 用 `--to-revision=1` 在多轮改动后 rev1 被 `revisionHistoryLimit=10` 淘汰；4.7 已完成状态下测不出 `status` 超时）+ 脚本断言 2 处，均已修正。**课 6 我一度写错并自行更正**：断言 FAIL 后**凭印象**写成「退出码 0 静默失败」，单独连改 13 次镜像实测为**明确报错 + 退出码 1**（`unable to find specified revision 1 in history`），已更正并保留更正记录。**两课共 13 项未实测**已列诚实声明。**纪律**：写操作隔离在 `kce-lab`/`kcr-lab`/`kcr2-lab` 并逐轮清理断言；无节点级操作；终态零残留 |
| 2026-10-09 | **参数速查.md（配套文档）+ 覆盖度核查** | 主 agent 内联双视角 + 独立复验 31 项 | **P0=0（复验 31/31 全通过）**。**立项依据是实测覆盖度**：子命令 **51%（22/43）**、全局 flag **29%（10/35）**、`exec` **0%**（主线出现 202 次）、`patch`/`debug` 21%。**独立复验抓出 3 个真缺陷，全部已修**：① **`--warnings-as-errors` 首测以偏概全**——只跑客户端告警就断言「无效」，复验补测服务端告警（`v1 Endpoints is deprecated`）**退出码=1、是生效的**；已改为「服务端生效 / 客户端无效」对照表，并把这次测量错误写进文档作反面教材；② **`scale --current-replicas` 报错原文凭印象写错**（我写 `expected 99 replicas, was 3`，实测 `Expected replicas to be 99, was 1`）；③ **`--request-timeout=1ms` 存在两种报错文案**（`context deadline exceeded` / `Client.Timeout exceeded while waiting for connection`），取决于超时发生在建连接前还是等连接时。**复验脚本自身修正 3 处断言缺陷**（`-L app` 取末列避免表头干扰、管道退出码改用 `PIPESTATUS[0]`、补建 `web-pod` 依赖环境）。**新增实测结论**：`--token` 被 client-cert **静默覆盖**（假 token 也能成功，须 `auth whoami` 验证）；`--prune` 删除依据是 `last-applied` 注解**而非标签**（`create` 建的对象永不 prune）；`--prune-allowlist` 格式必须 `group/version/kind`（`v1/ConfigMap` 报错，须 `core/v1/ConfigMap`）；`--validate` 默认已等价 strict、`ignore` 会静默丢弃字段；`exec`/`logs`/`cp` 三者多容器不写 `-c` **都不报错、静默选第一个**。**纪律**：全部写操作隔离在 4 个专用命名空间并逐轮清理断言；`drain`/`cordon`/`taint` 全程 dry-run；**10 项未实测在第六章逐条声明** |
| 2026-10-09 | 专项大纲（课清单 + 故事主线 + 覆盖度核查） | 主 agent 内联 + 脚本核查 | P0=0。覆盖度核查实证立项必要：文件名含 kubectl 的课程文件 **0 个**、标题级专门章节 **1 处**（且讲的是资源模型非命令用法）、`certificate`/`api-versions` **0 次**、`edit`/`expose`/`proxy` 各 4 次 |
| 2026-10-09 | 课 1 讲义 + 复验 26 项 | 主 agent 内联双视角（pedagogy + learner）+ 脚本复验 | **P0=0（复验 26/26 全通过）**。**复验抓出 4 处不一致，逐条核验后判定：3 处是我复验脚本自身缺陷，1 处是讲义真实缺陷**。① `api-resources` 67≠68 → 根因是复验时 context 漂到 `k8s-c2`，回 `k8s-c1` 复测即 68（脚本缺陷）；② `api-versions` 23≠24 同源（脚本缺陷）；③ `pods` 缩写匹配出两行 → awk 未限定组，匹配到 `pods.metrics.k8s.io`（脚本缺陷）；④ `get pods` 未落到空 default → `k8s-c2` 的 default 恰有 2 个 Pod（脚本缺陷）。**讲义真实缺陷**：把"68 条/24 条"写成常数而未说明依赖集群——实测四集群分别为 68/67/65/75，差异源为 `k8s-c1` 多一个 `widgets` CRD、`otel-l11` 装了 OTel Operator。已补四集群对比表 + "别当常数记、用途是前后对比"的说明。**另修正复验脚本二次缺陷**：`kubectl get --no-headers` 无资源时输出 `No resources found` 提示行，`wc -l` 计为 1（既有铁律「统计别把提示行计入」在本轮重犯，已修正判据后清零）。**新增教学点 2 处**：同名不同组（`pods` vs `PodMetrics`）、`explain` 查不存在字段**不报错**而靠有无 `FIELD:` 行判断 |

| 2026-10-09 | **课 2 讲义 + 复验 33 项** | 主 agent 内联双视角（pedagogy + learner）+ 脚本复验 | **P0=0（复验 33/33 全通过）**。**复验抓出 4 处 FAIL，逐条核验判定：3 处是我复验脚本判据缺陷，1 处是讲义真实坏链**。① `[*]` 一行 `wc -l`=0 → **讲义说法正确**，实测 `od -c` 证实 jsonpath 输出**末尾无换行**故 `wc -l` 数不到行（脚本判据错，已改为判「无换行符且含空格」）；② `-l` AND 无匹配、③ 反测 IP 返回空 → 两者实际输出均为 `No resources found`，是我在 `--no-headers` + `2>/dev/null` 组合下 grep 匹配不到（脚本判据错，已改为取原样输出判定）；④ **讲义真坏链**：课 7 路径写成 `stages/2-工作负载与网络/lessons/07-服务发现Service与Ingress.md`，实测目录不存在，真实路径为 `stages/3-网络与服务暴露/lessons/07-Service与CoreDNS.md`（**目录名与文件名双错**，已修）。**另修正课 1 讲义基线失效**：课 1 写「`k8s-c1` 的 default 有 0 个 Pod」，实测同日下午变为 2 个（`web-*` Deployment，nginx:alpine，08:32 创建），已改为「集群状态会随时间变化」并补充 `No resources found` 提示行污染 `wc -l` 的统计坑。**新增教学点 3 处**：默认输出仅占完整对象约 1%（126 B vs 12374 B 实测）、jsonpath 输出末尾无换行、`--field-selector` 的**反测法**（用必然不匹配的值确认生效而非被静默忽略） |

| 2026-10-09 | **课 3 讲义 + 复验 36 项** | 主 agent 内联双视角（pedagogy + learner）+ 脚本复验 | **P0=0（复验 36/36 全通过）**。**首轮探测脚本出现 2 处严重方法缺陷，被第二轮核验纠正，未污染讲义**：① **patch 三种语义的对比是在污染状态下跑的**——探测脚本用 `apply` 做「重置」，但实测证明 **apply 清不掉 strategic patch 加进去的数组元素**（因为 patch 加的字段不在 last-applied 里，apply 不会删它，这正是三方合并的定义），导致 5B/5C 都在「已追加过 metrics」的对象上执行，5C 甚至报 `Duplicate value: "metrics"`。**纠正**：改用 `delete` + `create` 重置，结论全部重测；② 探测脚本用 `2>&1 >/dev/null` 把关键报错吞掉了，只看到「结果没变」而不知道**为什么**没变。**纠正后抓出真知**：`--type=merge` 的真实行为不是「追加失败」而是**报 `spec.template.spec.containers[0].image: Required value`**——因为 JSON merge patch 对**数组整体替换**，把 containers 换成了不含 image 的元素。补上 image 后成功，但 **ports 被整体替换只剩一个**。**另有 1 处推翻我的原始预期**：我以为 `apply` 能用 last-applied 把缺失的 `image` 补回来，实测**同样报 `image: Required value`**（讲义已如实标注「未进一步取证」，未编造解释）。**其余新增实测点**：`diff` 有差异退出码=1（`set -e` 脚本陷阱）、`--dry-run=server` 报 `strict decoding error: unknown field`（client 通过）、`replace --force` 后 uid 变化 + 输出含 `deleted from`、SSA 无 last-applied 注解改用 managedFields 且冲突时报 `conflict with "kubectl-patch"`。**环境纪律**：全部写操作隔离在一次性命名空间 `kc-l3-lab`，复验脚本第 11 步自动清理并断言删除成功 |

| 2026-10-09 | **课 4 讲义 + 复验 54 项** | 主 agent 内联双视角（pedagogy + learner）+ 脚本复验 | **P0=0（复验 54/54 全通过）**。**首轮复验 4 处 FAIL：1 处是讲义硬伤、3 处是我的断言写错、1 处是真环境问题**。① **讲义硬伤（已修正）**：验证补全是否生效，我写了 `type __kubectl_get_resource`——**实测 v1.34 补全脚本里根本没有这个函数**（grep 计数为 0），真实入口是 **`__start_kubectl`**。这是凭旧版记忆写的：学员照抄会得到 not found 然后误判补全没装上。首轮复验第 2 步 FAIL 也是同一个错误函数名导致的。**修正**：讲义四处验证命令全部改为 `__start_kubectl` / `complete -p kubectl`，并新增「不要用 __kubectl_get_resource」的显式警告 + 实测函数全名清单；② **3 处断言写错**（非讲义问题）：`grep -c` 返回计数，我却把期望值写成 1（events 实际筛出 3 条、Warning 3 条），已改为 `>= 1` 并补一条反向断言；③ **真环境问题**：`node-debugger` Pod 残留 1 个（第二轮探测留下）。我的清理命令用标签选择器 `-l app.kubernetes.io/name=node-debugger` **没匹配上**，**这正好实证了讲义里「节点调试 Pod 必须按名字删」的警告**。已改为遍历名字删除，复验脚本也加了该清理步骤。**另有 2 处推翻自身预期并如实标注**：① 我以为 `--previous` 总能拿到上一轮，实测 `restartPolicy: Never` 时报 `previous terminated container not found`；② 我以为 `-v=6` 用 `grep GET https` 能统计请求数，实测**恒为 0**（kubectl 日志格式是 `verb="GET" url=...`），**前两轮探测都因此得出错误计数**，第四轮才发现。**纪律**：全部写操作隔离在一次性命名空间 `kc4-lab`，复验脚本第 12 步自动清理并断言删除成功；**补全安装属环境改动，讲义只给命令、不代为写入 `~/.bashrc`** |

## 📌 实测要点（供后续课程复用）

- **`kubectl version --short` 在 v1.34.0 已移除**（实测 `error: unknown flag: --short`），改用 `-o yaml`。⚠️ 既有讲义 [00-环境准备.md:181](../../00-环境准备.md) 仍写"加 `--short`"，**属待修正项**（不属于本专项范围，已记录待用户定夺）。
- **`kubectl --help` 的 `Available Commands` 段落**用 `sed -n '/Available Commands/,/^$/p'` 抓不到（v1.34 输出格式变化），需改用 `/Available Commands/,/Flags:/p`。
- **kind 集群容器被销毁后**，`kind get clusters` 立即不再列出（kind 靠容器 label 认集群），但 **kubeconfig 条目不会自动清理**——除非重建同名集群覆盖。
