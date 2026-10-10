# kind 专项（Kubernetes · 子教程）

> 定位：面向**用 kind 做本地集群的人**——把「kind 到底是什么、怎么配置出你要的集群形状、镜像怎么进去、坏了怎么救」这摊事说清。
> 前置：主线**阶段 1（心智模型与架构）**的基础知识（容器 = 节点、kubeconfig、context 三个概念）；子教程**不重复主线内容**，只讲 kind 这一层。
> 怎么进入：① 已学主线 → 直接按下面的课清单学；② 只想搞懂 kind → 先补主线课 1-2，或按各课课首的「前置提示」按需回看。

## 为什么有这个专项

主线教程里 kind 只是"建集群的那条命令"——散落在 [00-环境准备](../../00-环境准备.md) 的速查卡（`create` / `get clusters` / `delete`）、以及课 15 / 运维专项课 5 的 `kind load` 救急记录里。

但真实使用中，kind 的问题几乎从不发生在"建一个默认集群"这一步，而是发生在后面：

- 想要**多节点**（验证 DaemonSet 每节点一个、StatefulSet 的节点亲和），默认单节点不够用 —— 主线只在课 6 提了句"用 `--config`"。
- 想把**本地构建的镜像**跑进集群，发现 `kubectl run` 一直 `ErrImagePull` —— 因为 kind 节点看不见宿主机的 Docker 镜像。
- 想把 **NodePort / Ingress** 从宿主机浏览器访问，发现 `localhost:30080` 连不上。
- WSL 睡一觉 / Docker 重启后，`kubectl` 突然报 `The connection to the server 127.0.0.1:45145 was refused` —— 而且**报的端口号看着像乱码**，不知道该查什么。

本专项把这四类问题背后的机制一次讲透。它**不是命令大全**——命令大全主线已经有了；它补的是"**为什么**，以及出问题时**往哪儿看**"。

## 与主线的关系

主线走的是**集群使用者视角**（我要跑一个应用，怎么写 YAML、怎么暴露、怎么排障）；本教程走的是**本地集群搭建者视角**（这个 kind 集群是怎么造出来的、我要的拓扑怎么配、镜像怎么送进去、它为什么会坏）。

| 主线已讲（不重复） | 本教程补的 kind 视角 |
|--------------------|---------------------|
| [00-环境准备](../../00-环境准备.md)：`kind create/delete/get clusters` 速查卡 + "别用 `docker rm` 删节点" | 课 1：这三个命令**为什么**长这样（容器即节点、kubeconfig 是产物、删除的正确姿势从何而来） |
| 课 6：一句话"用 `kind create cluster --config` 建多节点集群" | 课 2：配置文件**怎么写**（nodes / role / 版本钉死 / 端口映射 / 挂载 / 网络），以及改配置为什么要重建 |
| 课 15、运维专项课 5：`kind load docker-image curlimages/curl` 救急记录；运维专项注明 `kind load` 在本机对多架构镜像失败、改用节点内 `ctr pull` | 课 3：镜像**为什么进不去**（两个 containerd 存储、多架构 manifest list 的坑），五种送镜像方式的取舍 |
| 课 18：分层排障五层模型（应用视角）；`00-环境准备` 误区 11："WSL 休眠后集群大概率失联，先看节点容器在不在" | 课 4：把这条经验**变成判据**——容器 Exited 137 / 端口拒绝 / kubeconfig 僵尸条目三者的因果链，以及现场怎么一步步走 |
| 运维专项课 8：WSL2 内 KVM 真虚机 + kubeadm 真集群 | 本教程与之**互补**：那课讲"真机长什么样"，本课讲"kind 为什么能假装成真机，以及在哪些地方假装不了" |

- 主线"提及级"带过、未展开的 kind 话题，在本教程逐条兑现（上表右列）。
- 与 Phase 5（[实战经验](../../08-实战经验.md) / [排障速查手册](../../09-排障速查手册.md)）的分工：本教程是**系统学**（机制 / 配置 / 体系），Phase 5 是**经验与急用**（坑 / 止血 / 判据）——按需互引，不重复。

## 故事主线

- **主角**：一个从"`kind create cluster` 一把梭"走向"按需定制本地集群"的使用者
- **冲突**：默认集群能建起来，但一旦需要多节点、需要跑自己的镜像、需要从宿主机访问服务，就处处碰壁——而报错信息往往指向错误的方向（端口号、镜像名、kubeconfig 全是"替罪羊"）
- **收束**：学完后能回答"**kind 这条命是怎么活着的、我怎么让它长成我要的形状、它坏的时候先看哪一处**"

## 课清单

| 课 | 知识点（关键点） | 对应主线提及 |
|----|-----------------|-------------|
| 课 1：kind 是什么：容器伪装的集群 | 容器即节点（node 镜像里跑着什么 / 与 VM 方案的本质差异）；集群的组装物（控制面容器、`kind` 网络、kubeconfig 条目、集群名与容器名前缀）；命令面与生命周期（七个命令的职责边界 / 命名规律 / 删除为什么必须用 `kind delete`） | 环境准备速查卡（补机制） |
| 课 2：配置文件与集群形状 | `kind: Cluster` 配置文件语义（apiVersion 与字段地图 / nodes 数组与 role / 集群名与 context 名）；节点镜像与 k8s 版本（`kindest/node` 镜像 / 版本钉死 / 与 kubectl 客户端偏差约束）；端口映射与挂载（`extraPortMappings` 与 `listenAddress` / `extraMounts` / NodePort 与 Ingress 的本地可达）；网络与 CNI（`disableDefaultCNI` / `podSubnet` / 本机 Calico 实例）；改配置为什么要重建（kind 不支持动态改拓扑） | 主线课 6、课 10（NetworkPolicy 前置确认 CNI 类型） |
| 课 3：镜像怎么进集群 | 两个镜像存储（宿主机 Docker vs 节点 containerd、`ctr -n k8s.io` 命名空间）；`kind load` 三种用法与它的坑（docker-image / image-archive / 多架构 manifest list 失败）；替代路径（`docker save` + `ctr import` 的失败边界 / **节点自己 `ctr pull`** / 本地 registry + `containerdConfigPatches`）；怎么选（五种方式对照与取舍表） | 课 15、运维专项课 5（把救急变系统） |
| 课 4：kind 集群的排障与坑 | 控制面容器一死全死（`Exited (137)` 的含义 / 端口映射随容器消失 / kubeconfig 端点残留成僵尸）；`connection refused` 的完整因果链（**本机真实事故复盘**）；三分钟现场判据（`docker ps` → `docker inspect` 端口 → `ss` 监听 → `kind get clusters` 对照）；WSL / Docker 生命周期与集群的存活（休眠 / Docker 重启 / `inotify` 耗尽 / 重建 or 重启的取舍）；其他高频坑（`Too many open files` / `LoadBalancer` 永远 pending / 删节点容器 vs 删集群） | 环境准备误区 3/5/10/11、课 18 |

## 学习路径

```text
课 1 是什么（容器即节点 → 集群组装物 → 命令面）
      └→ 课 2 怎么配置（配置文件 → 版本 / 端口 / 网络）
           └→ 课 3 怎么送镜像（两个存储 → load 的坑 → 替代路径）
                └→ 课 4 坏了怎么救（137 → 端口 → 僵尸 kubeconfig → 判据）
```

依赖顺序：课 1 是地基（不知道"节点是容器"，后面三课都会理解错）；课 2 与课 3 可**按需跳课**（只做单机实验的可跳过课 2，只用公共镜像的可跳过课 3）；课 4 建议放在最后，因为它同时依赖课 1（容器名与集群名的对应）与课 2（端口从哪来）。

## 学习进度

> 子教程进度独立记录于此（不混主线进度表）；课文件生成并学完后勾选。

- [x] 课 1：kind 是什么：容器伪装的集群（✅ 2026-10-09 完成 · P0=0 · 八组实测验证）
- [x] 课 2：配置文件与集群形状（✅ 2026-10-09 完成 · P0=0 · 真实建集群验证）
- [x] 课 3：镜像怎么进集群（✅ 2026-10-09 完成 · P0=0 · 十组真实实验验证）
- [x] 课 4：kind 集群的排障与坑（✅ 2026-10-09 完成 · P0=0 · 真实事故现场复盘 + 十一条复审验证）

## 边界声明

- **不重复主线**：kind 的"建 / 删 / 查"命令主线已讲，本教程只补机制、配置、镜像链路与排障。
- **不做 Phase 3 / Phase 5**：本子教程不收口综合项目、不产领域三产物（那是全课程收尾，主线已完成）。
- **不配课级应用实战 / 源码解析**：按子教程轻量口径，`应用实战/`、`源码解析/` 只收主线课。
- **实测口径**：本教程的结论一律以**本机实测**为准（kind v0.30.0 / `kindest/node:v1.34.0` / WSL2 Ubuntu 24.04 上的 Docker）；**未能实测的项逐条标 `⚠️ 未实测（原因）`**，不凭文档推断。
- **环境改动纪律**：课 2（建多节点集群）、课 3（拉镜像 / 起本地 registry）、课 4（重启或重建集群）都会**真实改动本机环境**——执行前逐项确认环境并征得同意，不擅自替你决定。

## 评审记录

| 日期 | 评审节点 | 方式 | 结论 |
|------|----------|------|------|
| 2026-10-09 | 子教程大纲（课清单 + 故事主线） | 主 agent 内联（course-reviewer 未创建，独立性受限） | P0=0 |
| 2026-10-09 | 课 1 讲义 + 八组实测验证 | 主 agent 内联双视角（pedagogy + learner）+ 脚本复验 | P0=0（复验一次全通过；发现"两个镜像仓库独立"的差异比讲义描述更极端：`k8s.io` 命名空间 33 个镜像 vs `default` 命名空间 0 个） |
| 2026-10-09 | 课 2 讲义 + 真实建集群验证 | 主 agent 内联双视角 + 真实 `create`/`delete` 验证 + 脚本复验 | P0=0（实建 `kind-lab2` 两节点集群；逐条核对四个集群端口归属；实测同名重建报错原文 `node(s) already exist for a cluster with the name "kind-lab2"`） |
| 2026-10-09 | 课 3 讲义 + 十组真实实验 | 主 agent 内联双视角 + 真实 build/run/load/import/pull + 独立复审脚本 | P0=0（复现 `ErrImagePull` 与 `ErrImageNeverPull` 的区别；实测 `kind load` 1.398s 送所有节点 vs `ctr import` 只进单节点；`extraPortMappings` 宿主机 `curl` 返回 `NODEPORT-OK`；复审 8 项全通过） |
| 2026-10-09 | 课 4 讲义 + 真实事故现场复盘 | 主 agent 内联双视角 + 真复现僵尸/恢复/删除 + 独立复审脚本（11 组） | P0=1→已修（**复审抓出讲义把 otel-l11 的 namespace 数写成 7，实测 8 个**——根因是查看时用了 `head -8`，首行是表头导致只显示 7 条数据，误把截断当全部；已修正并在讲义内补「数资源条数请用 `--no-headers`」自查提醒。其余 10 组全通过：假绿灯 5 vs 3、`OOMKilled=false`、`docker start` 后端口 36757 不变、`kind delete` 3 节点耗时 1m51.711s 且幂等退出码 0、`docker rm` 造成半僵尸、LB 无控制器、ulimit 10240 vs 1024、重启策略 `on-failure`） |

## 口径校正记录

| 日期 | 校正项 | 说明 |
|------|--------|------|
| 2026-10-09 | 课 2 讲义实际覆盖范围小于大纲原定范围 | 大纲原拟课 2 覆盖"配置文件 + 版本钉死 + 端口映射与挂载 + 网络与 CNI + 改配置需重建"五块。实际撰写时**只把 `name` 与 `nodes[].role` 做到了实测**（并用真建 `kind-lab2` 验证），其余字段（`extraPortMappings` / `apiServerPort` / `extraMounts` / `networking.*` / `featureGates` / `kubeadmConfigPatches`）**仅以字段地图形式给出并全部标 `⚠️ 未实测`**。`extraPortMappings` 的完整实操（需真起 Pod 才有意义）移交课 3 与镜像链路合并做。这样课 2 篇幅可控且每条结论都有实测支撑，代价是大纲里的"网络与 CNI""版本钉死实操"未在本课兑现。 |
| 2026-10-09 | 课 2 遗留的 `extraPortMappings` 已在课 3 兑现 | 课 3 第四幕第 9 步建了一次性集群 `kind-lab3port`，用固定 `nodePort: 30080` 与映射端口对齐，宿主机 `curl http://127.0.0.1:30080/` 实测返回 `NODEPORT-OK`，验完即删。**同时暴露一个反直觉点：映射端口与 Service 实际分配的 NodePort 不对齐时，映射等于没做**（首次验证时分配为 `30585` 而映射的是 `30080`，`curl` 失败）。 |
| 2026-10-09 | 课 3 未兑现大纲中的"本地 registry"与"多架构 manifest list 的坑" | 大纲原拟课 3 覆盖"两个存储 / `kind load` 三种用法与多架构 manifest list 失败 / 替代路径 / 五种方式对照"。实际做到：`kind load docker-image`、`ctr import`、`ctr pull` 三条路径全部实测，五种方式给出对照表（其中 `image-archive` 与"本地 registry"标 `⚠️ 未实测`，前者机制同 `docker-image` 只是输入换 tar，后者需起 registry 容器属环境改动本课未做）。**运维专项课 5 记录过的"`kind load` 对多架构镜像失败"这一坑本课未复现**（当前环境未遇到多架构镜像触发场景），未写入讲义。 |
| 2026-10-09 | 课 4 环境变更：删除 `k8s-c1-calico`、恢复 `otel-l11` | 课 4 为排障课，需真实事故现场。经用户同意后做了三项环境改动：① `docker start otel-l11-control-plane` 将已 Exited 的 `otel-l11` 恢复运行（数据完整，8 个 namespace 全 Active，AGE 35d）；② `kind delete cluster --name k8s-c1-calico` 删除 3 节点 Calico 实验集群（创建于 2026-09-17，实测耗时 1m51.711s，kubeconfig 条目同步清除，5→4 context）；③ 建一次性集群 `kind-zombie` 复现 `docker rm` 半僵尸后用 `kind delete` 清除（kind 目录与 kubeconfig 两处均归零）。**当前存活集群 4 个**：`k8s-c1`、`k8s-c2`、`kind-lab2`、`otel-l11`。 |
| 2026-10-09 | 课 4 未兑现：metallb 与 inotify 调参 | 大纲原拟课 4 覆盖"其他高频坑（`Too many open files` / `LoadBalancer` 永远 pending / 删节点容器 vs 删集群）"。实际做到：LoadBalancer pending **已实测并定位根因**（集群内确实无任何 metallb / cloud-controller），但**装 metallb 解决属额外环境改动，本课未做，标 `⚠️ 未实测`**；`Too many open files` **只测到限制值**（宿主机 `ulimit -n` 10240 vs 节点容器内 1024，`inotify max_user_instances` 512），**未实际触发该错误，也未调参**（属系统参数改动需用户授权）。 |
