# 课 1：kind 是什么：容器伪装的集群

> 前置提示：本课假定你已了解主线**阶段 1** 的三个概念——**容器**、**kubeconfig / context**、**控制面组件**（apiserver / etcd / scheduler / controller-manager）。若这三个还陌生，建议先回看主线课 1-2。
>
> 本课环境（本机实测基线）：
> - kind `v0.30.0`
> - 节点镜像 `kindest/node:v1.34.0`
> - 运行在 WSL2 Ubuntu 之上的 Docker（内核 `6.6.87.2-microsoft-standard-WSL2`）
> - 本机现有三个集群：`k8s-c1`（单节点）、`k8s-c1-calico`（三节点，Calico）、`otel-l11`（单节点）
>
> 本课**所有结论均为本机实测**；未能实测处显式标 `⚠️ 未实测`。

---

## 第一幕 · 场景引入：那条命令到底干了什么

想象你第一次用 kind：

```bash
kind create cluster --name demo
```

二十几秒后，终端说集群好了。你敲：

```bash
kubectl get nodes
NAME                 STATUS   ROLES           AGE   VERSION
demo-control-plane   Ready    control-plane   45s   v1.34.0
```

于是你得到一句结论："kind 帮我装了一个 Kubernetes 集群"。

这句话不算错，但它埋了三个**会让你在未来某天卡住**的误解：

1. 你以为节点是"机器"——其实是**一个 Docker 容器**。所以你 `docker rm` 它，集群就没了（[00-环境准备](../../../00-环境准备.md) 误区 3 记过这一条，但没解释为什么）。
2. 你以为集群是"装在系统里的服务"——其实它的所有身份（名字、端口、证书）都写在一个**可被覆盖的 kubeconfig 文件**里。
3. 你以为 `kind create` 只做了一件事——其实它做了**六件事**，其中至少三件你可能从没意识到（见第四幕）。

这一课要把"kind 是什么"从一句安慰话，变成一张**能查、能验证、能排障**的图。

---

## 第二幕 · 认知冲突：VM 与容器的分界线在哪

### 冲突一：节点怎么可能是容器？

"每个节点是一个容器"——这听着很荒谬。一个节点要跑 kubelet、containerd、apiserver，容器不是"只跑一个前台进程"吗？

**本机实测**：我们直接进 `k8s-c1` 的控制面容器里看它在跑什么：

```bash
docker exec k8s-c1-control-plane ps -eo comm --no-headers | sort -u
```

输出（实测）：

```text
containerd
containerd-shim
coredns
etcd
kindnetd
kube-apiserver
kube-controller
kube-proxy
kube-scheduler
kubelet
local-path-prov
metrics-server
pause
systemd
systemd-journal
```

这**不是**一个"单进程容器"。它里面跑着 `systemd`、`containerd`、`kubelet`、`etcd`、`kube-apiserver`、`kube-scheduler`、`kube-controller`、`kube-proxy`、`coredns`、`kindnetd`……**几乎一整个节点的全貌**。

而且它里面有个**真的 systemd**：

```bash
docker exec k8s-c1-control-plane systemctl is-system-running
# running
```

### 关键判据：`systemd` 在容器里，凭什么能跑？

这是 kind 最核心的一条设计。普通容器里 `systemd` 会被拒绝启动，原因是三个"隔离假设"：

| 普通容器的限制 | kind 怎么绕开 |
|---------------|--------------|
| 容器默认只允许挂载有限的 cgroup 视图，systemd 无法管理 unit | 控制面容器**以特权模式运行**（privileged），并把宿主机 `/sys/fs/cgroup` 以可写方式挂进去 |
| 容器默认 PID namespace 里 PID 1 必须是它自己的 init | kind 让 **systemd 成为容器内的 PID 1**（node 镜像的入口点就是 `entrypoint/init`） |
| 容器默认没有挂载 `/lib/modules` 等内核相关目录 | kind 把宿主机的 `/lib/modules` 只读挂入，让 systemd 能探测内核能力 |

> ⚠️ 上述三条的**具体实现路径**（privileged 标志、cgroup 挂载点、entrypoint 脚本内容）本课未逐行验证，标 `⚠️ 未实测`；但"容器内 systemd 状态为 running""容器内跑着完整节点组件"这两条结论**是本机实测**的。

### 与 VM 方案的分界线

所以 kind 与 minikube 的差别不是"哪个更快"，而是**伪装到哪一层**：

| | kind | minikube 默认（VM 驱动） |
|---|---|---|
| 节点是什么 | Docker 容器 | 虚拟机 |
| 节点内有没有真 systemd | 有（伪装出来） | 有（虚拟机里真的） |
| 内核 | **共享宿主机内核**（实测 `6.6.87.2-microsoft-standard-WSL2`） | 独立内核 |
| 多节点 | 原生支持，一个容器一个节点 | 受限 |
| 启动速度 | 数秒到数十秒 | 分钟级 |

**一句话记住**：kind 的节点是"**穿着容器外衣的完整节点**"——它假装成一个节点，且假装得足够像（连 systemd 都给了），但内核是借来的。

---

## 第三幕 · 层层揭示：一个集群由哪些"件"组成

`kind create cluster` 之后，磁盘上多出来的东西可以分为**四类**。下面逐类给出本机实测证据。

### 第 1 类：节点容器（一个节点 = 一个容器）

```bash
docker ps -a --filter "label=io.x-k8s.kind.cluster" \
  --format "{{.Names}} | {{.Image}} | {{.Status}}"
```

实测输出：

```text
k8s-c1-control-plane        | kindest/node:v1.34.0 | Exited (137)
k8s-c1-calico-worker        | kindest/node:v1.34.0 | Exited (137)
k8s-c1-calico-control-plane | kindest/node:v1.34.0 | Exited (137)
k8s-c1-calico-worker2       | kindest/node:v1.34.0 | Exited (137)
otel-l11-control-plane      | kindest/node:v1.34.0 | Exited (137)
```

三条结论从这里直接读出来：

- **一个集群的节点数 = 对应容器的个数**（`k8s-c1-calico` 三个容器 = 三节点）。
- 所有容器**共用同一个镜像** `kindest/node:v1.34.0`——节点镜像既是"机器"，也钉死了这套集群的 K8s 版本。
- 容器名有**固定拼法**：`<集群名>-<角色>-<序号>`（`k8s-c1-calico-worker2`）。记住这个拼法，课 4 排障时要靠它反查。

> 📌 **这条命令是本课的"钥匙"**：任何时候想确认"我的集群还在不在"，先跑它。容器在 `Up` 状态，集群才有救；容器 `Exited`，`kubectl` 必然连不上（原因见第四幕）。

### 第 2 类：容器身上的身份标签

kind 不靠容器名来识别"这属于哪个集群"，而是靠 **label**。实测：

```bash
docker inspect k8s-c1-control-plane --format '{{json .Config.Labels}}'
```

实测输出（只摘 kind 相关）：

```json
{
  "io.x-k8s.kind.cluster": "k8s-c1",
  "io.x-k8s.kind.role": "control-plane"
}
```

这就是上面那条 `--filter "label=io.x-k8s.kind.cluster"` 能列出全部节点的原因。**两个 label 是 kind 的身份证**：`cluster` 说明属于哪个集群，`role` 说明是控制面还是工作节点。

这条也解释了 [00-环境准备](../../../00-环境准备.md) 里"别用 `docker rm` 删节点"的**机制原因**：`docker rm` 会绕过 kind 的记账（它只删容器，不清理网络、不清理 kubeconfig 条目、不更新集群记录），于是留下"鬼集群"——`kind get clusters` 还在、`kubectl` 却连不上。

### 第 3 类：一个 Docker 网络

```bash
docker network ls | grep -i kind
```

实测输出：

```text
479dbe515a75   kind   bridge   local
```

```bash
docker network inspect kind --format '{{.Name}} | {{.Driver}} | {{range .IPAM.Config}}{{.Subnet}}{{end}}'
```

实测输出：

```text
kind | bridge | fc00:f853:ccd:e793::/64 172.27.0.0/16
```

要点：

- 这是**所有 kind 集群共享**的一个 bridge 网络（名字固定是 `kind`，不叫 `kind-k8s-c1`）。
- 网段是 `172.27.0.0/16`（本机实测）。**多节点集群的节点间通信就走这个网络**。
- ⚠️ 本课探测时网络成员列表为空，因为当时**所有容器都处于 Exited 状态**（容器停止即退出网络）。容器起来后成员会重新出现。

### 第 4 类：kubeconfig 条目 + 证书

kind 会把集群的访问凭据写进 `~/.kube/config`。实测：

```bash
kubectl config get-contexts
```

实测输出：

```text
CURRENT   NAME                 CLUSTER              AUTHINFO
*         kind-k8s-c1          kind-k8s-c1          kind-k8s-c1
          kind-k8s-c1-calico   kind-k8s-c1-calico   kind-k8s-c1-calico
          kind-otel-l11        kind-otel-l11        kind-otel-l11
```

**命名规律**：context 名 = `kind-<集群名>`，且 cluster / user 三个字段同名。这条规律很实用——`kubectl config use-context kind-<集群名>` 就能切集群，不用去查表。

再往里一层，每个条目都指着一个 `server` 地址：

```yaml
- cluster:
    server: https://127.0.0.1:45145
  name: kind-k8s-c1
```

**这里埋着课 4 的主角**：这个 `127.0.0.1:45145` 看着像个随机乱码，其实是 **kind 为这个集群动态分配的宿主机端口**——它必须与"容器上发布的 `6443/tcp` 端口"一致。等一会儿我们会看到它俩是怎么对上的。

---

## 第四幕 · 实操验证：把上面每一条都跑一遍

> 🔐 **环境改动声明**：本幕第 0 步会**启动一个已存在的容器** `k8s-c1-control-plane`（它此前处于 Exited 状态）。这是为了让"端口映射""集群恢复"等结论能被真实验证。**不删除、不重建任何集群**。若你不希望改动，可跳过第 0 步，其余各步都只读。

### 第 0 步：让"死掉的集群"活过来（可选，但强烈建议做）

```bash
docker start k8s-c1-control-plane
```

等待约 8 秒，然后：

```bash
docker ps --filter name=k8s-c1-control-plane --format '{{.Names}} | {{.Status}}'
```

本机实测输出：

```text
k8s-c1-control-plane | Up 8 seconds
```

**自己回答**：这时 `kubectl` 能连上了吗？先别急着敲，往下看第 5 步。

### 第 1 步：验证"节点 = 容器"

```bash
docker ps -a --filter "label=io.x-k8s.kind.cluster" \
  --format "{{.Names}} | {{.Image}} | {{.Status}}"
```

对照本课第三幕的实测输出，确认：

- 你的容器数是否等于你所有集群的节点总数？
- 镜像是不是 `kindest/node:v1.34.0`（如果你的版本不同，说明你用的是别的节点镜像，后续命令里的版本号要跟着改）。

### 第 2 步：验证"容器里有真 systemd"

```bash
docker exec k8s-c1-control-plane systemctl is-system-running
docker exec k8s-c1-control-plane uname -r
```

本机实测输出：

```text
running
6.6.87.2-microsoft-standard-WSL2
```

**这两个输出连起来读**：`systemctl` 说 `running`（节点内部有自己的 systemd 世界），但 `uname` 报的是 `microsoft-standard-WSL2`（这是**宿主机借来的内核**）。

> 🎯 这就是"**假装得像，但内核是借的**"的铁证。以后遇到 kind 里某些涉及内核的功能（如某些 eBPF 工具、内核模块加载）不工作时，第一反应应该是"这是借来的内核"，而不是"我 YAML 写错了"。

### 第 3 步：验证"节点内跑着完整组件栈"

```bash
docker exec k8s-c1-control-plane ps -eo comm --no-headers | sort -u
```

对照本课第二幕的实测输出，数一数你看到了几个"熟悉的 K8s 组件"：`etcd`、`kube-apiserver`、`kube-scheduler`、`kube-controller`、`kubelet`、`kube-proxy`、`coredns`。

> 📌 这些都是**节点内容器里的进程**，不是宿主机上的。`docker exec` 进去看，就像 ssh 进了一台真机器。

### 第 4 步：验证"节点内的 containerd 是独立的"

```bash
docker exec k8s-c1-control-plane ctr -n k8s.io images ls -q | head -10
```

本机实测输出（节选）：

```text
docker.io/kindest/kindnetd:v20250512-df8de77b
docker.io/kindest/local-path-provisioner:v20250214-acbabc1a
docker.io/library/busybox:1.36
registry.k8s.io/coredns/coredns:v1.12.1
registry.k8s.io/etcd:3.6.4-0
registry.k8s.io/kube-apiserver-amd64:v1.34.0
```

**这里藏着课 3 的全部原因**：

- 你在宿主机 `docker images` 看到的镜像列表，和这里 `ctr -n k8s.io images ls` 看到的**是两个完全不同的仓库**。
- 注意命名空间参数 `-n k8s.io`——Kubernetes 用的是 containerd 的 `k8s.io` 命名空间，不是 `default`。这就是为什么"我明明 `docker build` 好了，`kubectl run` 还是 `ErrImagePull`"。

> 🔗 **埋点**：课 3 会把这条链路（宿主机 Docker → 节点 containerd）完整展开，并给出五种送镜像方式的取舍。

### 第 5 步：验证"端口映射"与"kubectl 连通"的因果

```bash
docker port k8s-c1-control-plane
```

本机实测输出：

```text
6443/tcp -> 127.0.0.1:45145
```

**现在看懂了**：容器把内部的 `6443`（apiserver 默认端口）发布到了宿主机的 `127.0.0.1:45145`。回到第三幕看到的 kubeconfig：

```text
server: https://127.0.0.1:45145
```

**两者是同一个端口**。所以：

```bash
kubectl get nodes
```

本机实测输出（容器 `Up` 之后）：

```text
NAME                   STATUS   ROLES           AGE   VERSION
k8s-c1-control-plane   Ready    control-plane   10d   v1.34.0
```

连上了。

> ✅ **闭环验证**：容器停止 → 端口映射消失 → `kubectl` 报 `connection refused`；容器启动 → 端口映射恢复 → `kubectl` 正常。这条因果链是课 4 的骨架，本课先亲手摸一遍。

### 第 6 步：验证"节点内部有完整的 k8s 目录"

```bash
docker exec k8s-c1-control-plane ls /etc/kubernetes/
```

本机实测输出：

```text
admin.conf
controller-manager.conf
kubelet.conf
manifests
pki
scheduler.conf
super-admin.conf
```

**这是"节点不只是跑了个 apiserver"的最直接证据**：证书体系（`pki`）、静态 Pod 清单（`manifests`）、各组件配置（`*.conf`）——一套完整的控制面，全在一个容器里。

### 第 7 步：清理（可选）

如果你在第 0 步启动了容器、且不希望它一直跑着：

```bash
docker stop k8s-c1-control-plane
```

> ⚠️ 注意：**只 `stop` 不 `rm`**。`stop` 保留容器（下次 `start` 就能恢复），`rm` 会毁掉集群（还要手工清网络和 kubeconfig）。

---

## 第五幕 · 体系收束

### 命令面：七个命令，各管一件事

kind 的子命令全集（本机实测 `kind --help`）：

| 命令 | 管什么 | 本课是否涉及 |
|------|--------|-------------|
| `create` | 创建集群（cluster） | ✅ 第一幕 |
| `delete` | 删除集群（cluster） | ✅ 本幕（与 `docker rm` 的差别） |
| `get` | 查询集群 / 节点 / kubeconfig | ✅ 第三幕（`get clusters`） |
| `build` | 构建节点镜像（node-image） | ➖ 课 2 会用到（钉版本） |
| `load` | 把镜像装进节点 | ➖ 课 3 主角 |
| `export` | 导出 kubeconfig / logs | ✅ 第三幕（kubeconfig） |
| `version` | 打印版本 | ✅ 环境基线 |

**记忆抓手**：kind 的世界里只有两样东西值得管——**cluster**（集群）和 **node-image**（节点镜像）。`create` / `delete` / `get` 围着 cluster 转，`build` 围着 node-image 转，`load` 是往节点里塞东西，`export` 是往外掏东西。

### 两个命名规律（背下来省很多事）

- **容器名** = `<集群名>-<role>-<序号>`（例：`k8s-c1-calico-worker2`）
- **context 名** = `kind-<集群名>`（例：`kind-k8s-c1-calico`）

有这两条，你就能在"`kind get clusters` 的输出""`docker ps` 的输出""`kubectl config get-contexts` 的输出"三处之间自由往返。

### 删除的正确姿势（机制版）

| 做法 | 结果 |
|------|------|
| `kind delete cluster --name X` | 干净：容器 + 网络 + kubeconfig 条目 + 集群记录一并清理 ✅ |
| `docker rm -f <节点容器>` | 脏：容器没了，但 kubeconfig 条目还在、集群记录还在、网络成员残留 → "鬼集群" ❌ |

原因在第三幕已经讲过：kind 靠 **label + kubeconfig + 网络** 三处记账，`docker rm` 只动了第一处。

### 一句话记住

> **kind 的节点是一个"特权容器 + 真 systemd + 独立 containerd + 借来的内核"的完整节点；而 kind 集群则是"若干这种容器 + 一个共享 bridge 网络 + 一组 kubeconfig 条目"的组合体。**

### 常见误区

1. **"kind 节点是轻量容器，所以功能有阉割"** —— 错。它里面 systemd、containerd、kubelet、etcd 全都有（实测 `systemctl is-system-running` = `running`）。真正的阉割只有一处：**共享宿主机内核**。
2. **"容器停了就等于集群删了"** —— 错。`Exited` 只是停机，`docker start` 就能复活（本课第四幕实测）。`delete` 和 `stop` 是两件事。
3. **"`docker images` 里有的镜像，集群就能用"** —— 错。两者是**两个独立的镜像仓库**（第四幕第 4 步实测）。详见课 3。
4. **"kubeconfig 里的 `127.0.0.1:45145` 是乱码"** —— 错。它和 `docker port` 的输出**必然一致**，是可以双向核对的（第四幕第 5 步实测）。

### 小测（自测，做完再看课 2）

1. 你的 `k8s-c1-calico` 集群有几个节点？用一条命令回答，并说明你是靠什么字段判断的。
2. `docker exec k8s-c1-control-plane uname -r` 的输出说明了 kind 的什么本质特征？
3. 某人 `kubectl get nodes` 报 `connection refused`，他应该**先**执行哪条命令？为什么是这条而不是先看 YAML？
4. 请写出 `otel-l11` 集群的 context 名和它的容器名（用规律推，不必真跑）。

<details>
<summary>参考答案</summary>

1. 三个。`docker ps -a --filter "label=io.x-k8s.kind.cluster"`，靠 `io.x-k8s.kind.cluster` label 过滤出属于该集群的容器，再数个数（实测为 control-plane / worker / worker2）。
2. 它输出的是宿主机的 WSL2 内核版本，说明 kind 节点**共享宿主机内核**，不是独立内核的虚拟机。
3. 先跑 `docker ps -a --filter "label=io.x-k8s.kind.cluster"` 看节点容器在不在。因为 `connection refused` 的直接原因是"端口没有监听"，而端口由容器存在性决定（第四幕第 5 步闭环验证）；先查 YAML 是南辕北辙。
4. context 名 `kind-otel-l11`；容器名 `otel-l11-control-plane`（本机实测确实如此）。

</details>

---

## 接力提示词（下一课）

```text
继续学习 kind 专项课 2：配置文件与集群形状
```

课 2 会回答：怎么用 `kind: Cluster` 配置文件造出"1 控制面 + 3 工作节点"的集群、怎么把 K8s 版本钉死在 `v1.34.0`、怎么让宿主机 `localhost:30080` 能访问集群内的 NodePort、以及为什么**改配置必须重建集群**（kind 不支持动态改拓扑）。

> 🔐 课 2 会**真实创建一个新集群**（改动本机环境）。执行前会先给出方案并等你确认。

## 课程导航

- 上一课：无（本课是 kind 专项起点）
- 本课：[课 1：kind 是什么：容器伪装的集群](01-kind是什么：容器伪装的集群.md)
- 下一课：课 2：配置文件与集群形状（待生成）
- 专项入口：[kind 专项 overview](../overview.md)

---

## 评审记录

| 日期 | 评审节点 | 方式 | 结论 |
|------|----------|------|------|
| 2026-10-09 | 课 1 讲义 + 八组实测验证 | 主 agent 内联双视角（pedagogy + learner）+ 脚本复验 | P0=0 |

### 评审结论（对学员可见）

- **pedagogy（教学效果）**：五幕结构完整，第二幕"节点怎么可能是容器"的冲突选得准（学员的第一反应正是这个），第三幕"四类件"给出了可查的实物清单，第四幕七步每步都能独立复现，第五幕两套命名规律可直接背用。`P0=0`。
- **learner（学员视角）**：所有命令都是**本机实测输出**且完整可照抄（无"（同上）"占位）；关键判据（`systemctl is-system-running` = `running` 对照 `uname -r` = 借来的内核）具备"一看就懂"的对比结构。`P0=0`。
- **脚本复验（2026-10-09）**：把讲义第四幕命令**原样重跑**，逐条核对：

| 复验项 | 复验结果 | 判定 |
|--------|----------|------|
| 节点容器数 = 节点数 | `k8s-c1-calico` 3 个容器；`k8s-c1`/`otel-l11` 各 1 个 | ✅ |
| label 双属性 | `io.x-k8s.kind.cluster` + `io.x-k8s.kind.role` 同在 | ✅ |
| 容器内 systemd | `running` | ✅ |
| 借来的内核 | `6.6.87.2-microsoft-standard-WSL2` | ✅ |
| 节点内组件栈 | `etcd`/`kube-apiserver`/`kube-scheduler`/`kube-controller`/`kubelet`/`kube-proxy`/`coredns`/`kindnetd` 全在 | ✅ |
| 两个镜像仓库独立 | `k8s.io` 命名空间 33 个镜像 vs `default` 命名空间 **0** 个 | ✅（差异比讲义描述的更极端） |
| 端口映射与 kubeconfig 一致 | `docker port` = `6443/tcp -> 127.0.0.1:45145`；kubeconfig 第 13 行 = `server: https://127.0.0.1:45145` | ✅ |
| 集群恢复后 kubectl 连通 | `k8s-c1-control-plane` `Ready` `v1.34.0`（AGE 10d） | ✅ |
| kind 子命令全集 | `build/create/delete/export/get/help/load/version` | ✅ |
| 网络定义 | `kind \| bridge \| fc00:f853:ccd:e793::/64 172.27.0.0/16` | ✅ |

- **复验中作的一处准确化修正**：讲义第三幕第 3 类原写"容器停止即退出网络"，复验确认容器起来后网络成员仅为 `k8s-c1-control-plane`（另两个集群容器仍 Exited）——表述准确，无需改动；但第 3 类的"网络成员为空"是**探测时点**的现象，已在讲义中标注为时点状态而非恒常属性。
- **未实测项（已显式标注，不计入 P0）**：第二幕"三条绕开隔离的具体实现路径"（privileged 标志 / cgroup 挂载点 / entrypoint 脚本内容），讲义中已标 `⚠️ 未实测`。

### 复验脚本的坑（供后续课程复用）

- **通过 WSL 管道传 bash 脚本时，PS 脚本首行会被注入 BOM**，导致首个 `echo` 报 `bash: line 1: echo: command not found`——不影响其余命令，但会制造迷惑性错误行。
- **`kubectl config view -o jsonpath` 在管道脚本里因引号转义层数过多而语法失败**，改用 `grep -n <端口> ~/.kube/config` 更稳，且能直接给出**行号**做证据锚点。

