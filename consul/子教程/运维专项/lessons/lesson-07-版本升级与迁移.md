# 课 7：版本升级与迁移

> 面向：运维 / SRE
> 前置：课 2（集群健康）、课 5（备份、恢复与灾备演练）
> 本课所有**集群行为类**数字均来自本机 WSL Ubuntu 24.04 + Consul 2.0.2 三节点集群实测（2026-09-20）；**版本策略与兼容矩阵**引自 HashiCorp 官方文档（引用处已标注，非本机推断）。

---

## 引子：升级失败那天，你按下回滚键

凌晨两点，Consul 升级到新版本后服务大面积报 TLS 握手失败。你判断是版本不兼容，决定回滚。

回滚方案你早就准备好了——**恢复升级前的快照**。

你执行 `consul snapshot restore pre-upgrade.snap`，集群回到了旧版本的数据状态。但几秒钟后你意识到一件事：

> **过去 40 分钟里新注册的服务、新写入的配置、迁移脚本产生的中间状态，全部消失了。**

这不是意外，这是设计的必然。课 5 已经证明过：**恢复是全量覆盖，不是合并**。

本课要讲的就是这件事的另一面——**正因为回滚有代价，所以升级必须一次做对**。而"一次做对"的前提，是理解版本线、跳跃限制和兼容矩阵。

---

## 一、版本线与支持策略

### 1.1 当前版本（本机实测）

```console
$ consul version
Consul v2.0.2
Revision ca5bc12b
Build Date 2026-07-08T09:22:50Z
Protocol 2 spoken by default, understands 2 to 3
```

### 1.2 必须先分清的两个"protocol"

这是升级时最容易混淆的地方，我实测确认了它们确实是两个东西：

```console
gossip(CLI version 行): understands 2 to 3
gossip(members):        2→5
raft:                   3
```

| 名称 | 本机实测值 | 在哪看 | 作用 |
|---|---|---|---|
| **Gossip protocol**（serf LAN） | 默认说 2，懂 2~3 | `consul version` / `consul members` | 节点间成员发现与故障检测 |
| **Raft protocol** | 3 | `consul operator raft list-peers` | 一致性层，决定写 quorum |

**为什么必须分清**：
- `consul version` 说 "understands 2 to 3"，这是 **gossip**。
- `consul members` 报告的 `Protocol=2→5` 是 **gossip** 的 `Cur→Max`。
- `raft list-peers` 的 `RaftProtocol=3` 是 **Raft**。

**三者数值不同是正常的**，不要拿 gossip 的号去套 Raft。升级时要分别确认。

### 1.3 支持策略（官方文档）

| 版本类型 | 维护周期 | 升级频率要求 |
|---|---|---|
| **社区版（CE）** | — | 官方建议**每 4 个月**升级到最新 major，才能持续获得 bug/安全修复 |
| **企业版 Standard** | 约 1 年 | 平均每 12 个月一次 major 升级 |
| **企业版 LTS** | 约 2 年 | 平均每 12 个月一次 major 升级 |

**支持范围**（Envoy 兼容页定义）：最新版（N）、企业版的 N-1 与 N-2、以及最近 2 个企业 LTS major。

> 📌 本课环境为 **社区版 2.0.2**。企业版专属的自动化升级（Automated Upgrades）不在本课实测范围。

---

## 二、不支持跨多版本跳跃

### 2.1 官方规则

> "Each upgrade should jump **at most 2 major versions**, except where dedicated instructions are provided for a larger jump between specific versions."
> —— [Upgrade Instructions](https://docs.hashicorp.com/consul/docs/v1.21.x/upgrade/instructions)

**社区版：一次最多跳 2 个 major。**
**企业版 LTS：一次最多跳 3 个 major**（LTS → 下一个 LTS）。

### 2.2 举例（官方原文示例）

从 1.12 升到 1.15：

```
1.12 → 1.14（中间步骤，+2）→ 1.15（+1）
```

不能直接 1.12 → 1.15（跳 3 个，超出限制）。

**极端落后场景**有专用路径（官方表）：

| 起始版本范围 | 目标版本 |
|---|---|
| 1.8.0 - 1.9.17 | 1.10.12 |
| 1.6.9 - 1.8.18 | 1.8.19 |
| 1.2.4 - 1.6.9 | 1.6.10 |
| 0.8.5 - 1.2.3 | 1.2.4 |

从 1.3.1 升到 1.12 需要**四步**：1.3.1 → 1.6.10 → 1.8.19 → 1.10.12 → 1.12.x。

### 2.3 为什么要逐级走

官方的兼容性承诺（[Protocol Compatibility Promise](https://www.consul.io/docs/compatibility.html)）：

> "We promise that every subsequent release of Consul will remain backwards compatible with **at least one prior version**."

**只保证向后兼容一个版本**。所以跨多个 major 时，中间每一步都必须能互相"说上话"。

**逐级走的真实代价**：每个中间版本都要做一轮滚动重启 + 健康检查。从 1.8 到 2.0 意味着**多轮完整的集群滚动**。这是升级窗口必须预留的时间。

---

## 三、升级流程与 quorum 约束

### 3.1 滚动升级的顺序（官方 FAQ）

```
Follower 节点 → Leader 节点 → Client 节点
```

**先 follower、最后 leader**，是为了让 leader 选举只发生一次（在最后），而不是每次停 follower 都触发一次。

### 3.2 quorum 约束（本机实测）

滚动升级的物理约束是 **quorum 必须一直保住**。实测计算：

```console
3 节点: quorum=2, 可同时停 1 台
5 节点: quorum=3, 可同时停 2 台
7 节点: quorum=4, 可同时停 3 台
```

**同时停机上限 = n - quorum。**

### 3.3 实测：破坏 quorum 会发生什么

我在 3 节点集群上做了真实实验：

**停 1 台（node3）**：

```console
存活进程 = 2
新 leader = "127.0.0.2:8302"
写操作 → HTTP 200  (写成功)
```

**再停 1 台（node2，共停 2 台）**：

```console
存活进程 = 1
leader = ""          ← 没有 leader 了
写操作 → HTTP 000   ← 超时/失败
```

**结论**：3 节点集群**一次只能停 1 台**。停 2 台就直接失去写能力。

> ⚠️ **这解释了为什么"一次停多台加快升级"是致命的**。你以为在节省时间，实际是在制造一次写中断事故。3 节点集群的升级窗口 = 单台重启时间 × 3（或更多，因为要等每台 rejoin 并健康）。

### 3.4 标准升级流程（官方）

1. **查目标版本的 upgrade notes**，确认无影响工作负载的兼容性问题
2. 在每个 server 上**安装**新版本二进制（先不重启）
3. **一次一台** server：`consul leave` → 用新版本重启 → **等它健康并重新加入集群**后再动下一台
4. 所有 server 升级完，再滚动 client
5. **若有 Envoy**：停 client → 停其 Envoy → 起新 client → 起兼容版本的 Envoy
6. 验证：`consul members` 确认所有成员都是最新 build 与最高 protocol

**第 3 步的"等待"不能省**。跳过等待继续停下一台，等于同时停机。

### 3.5 不兼容升级的两阶段法

官方保留了一个后备手段：

> "start version B with the `-protocol=PREVIOUS` flag, where PREVIOUS is the protocol version of version A"

**流程**：
1. 所有节点装 B，用 `-protocol=PREVIOUS` 启动（禁用新特性，保证兼容）
2. 全部跑起来后，**再逐台去掉 `-protocol` 重启一次**

这是**两次全集群滚动**，代价翻倍——只在官方明确声明"backward incompatible"时才用。

---

## 四、回滚：为什么它不是免费的

### 4.1 实测：回滚到底抹掉了什么

我在真实集群上模拟了一次完整的"升级 → 失败 → 回滚"：

**第 1 步：写基线数据，然后存快照**

```console
app/version = v1-before-upgrade
app/oldsvc  = existing-service
→ 存快照（index 90）
```

**第 2 步：模拟升级过程中的数据变更**

```console
app/version  = v2-after-upgrade                    ← 版本标记已升
app/newsvc   = new-service-registered-during-upgrade  ← 升级中新增
app/migration= migration-artifact                     ← 升级中新增
```

**第 3 步：升级失败 → 回滚（恢复基线快照）**

```console
Restored snapshot
```

**第 4 步：清点代价**

```console
app/version  = 'v1-before-upgrade'   ✅ 回到升级前
app/oldsvc   = 'existing-service'   ✅ 老数据还在
app/newsvc   = ''                   ❌ 升级中新增的，没了
app/migration= ''                   ❌ 升级中新增的，没了
```

### 4.2 这个结果意味着什么

| 你的预期 | 实际 |
|---|---|
| 回滚 = 撤销升级这个动作 | 回滚 = **把整个集群回退到快照那一刻** |
| 升级期间新注册的服务会保留 | **全部消失** |
| 可以边升级边让业务继续写入 | 那些写入在回滚后**不存在** |

**回滚不是"撤销"，是"回到过去"。**

### 4.3 一个必须记住的事故模型

```
02:00  升级前快照
02:10  开始升级，业务持续写入新服务注册
02:40  升级失败，决定回滚
02:45  回滚完成
       ↓
   ✅ Consul 版本回到旧版
   ❌ 02:00-02:45 之间的所有新服务注册、配置变更 全部消失
```

**如果你在升级窗口内允许业务写入，回滚就会丢业务数据。**

### 4.4 降低回滚代价的三个做法

1. **升级窗口内冻结写入**（最有效）。如果业务必须写入，那么这些写入就是回滚时会被抹掉的部分——**提前告知业务方**。
2. **回滚前先存当前状态**：
   ```bash
   consul snapshot save emergency-$(date +%s).snap
   ```
   即使当前状态是"坏的"，也先存。给自己留后悔药——万一回滚后发现有别的问题，还能回去。
3. **尽量缩短升级窗口**。回滚代价 ≈ 窗口内的写入量。窗口越短，代价越小。

### 4.5 回滚前必查清单

| 检查项 | 为什么 |
|---|---|
| 快照是否**在升级前、且在基线数据写入之后**存的 | 我第一次实验就犯了这个错：快照存早了，导致连基线数据都丢了 |
| 是否先存了当前状态（紧急快照） | 回滚不可逆 |
| 窗口内业务写入是否已冻结/已告知 | 决定会丢多少 |
| 旧版本二进制是否还在 | 回滚需要能起旧版本 agent |
| 是否已确认 quorum 完整 | 恢复本身需要 quorum |

---

## 五、Consul 与 Envoy 版本兼容矩阵

### 5.1 社区版（官方文档）

| Consul 版本 | 兼容 Envoy 版本 |
|---|---|
| **2.0.x CE** | 1.38.x, 1.37.x, 1.35.x |
| 1.22.x CE | 1.38.x, 1.37.x, 1.35.x |
| 1.21.x CE | 1.38.x, 1.37.x, 1.35.x |
| 1.20.x CE | 1.33.x, 1.32.x, 1.31.x, 1.30.x |
| 1.19.x CE | 1.33.x, 1.32.x, 1.29.x, 1.28.x, 1.27.x, 1.26.x |
| 1.18.x CE | 1.33.x, 1.32.x, 1.31.x, 1.30.x, 1.29.x, 1.28.x, 1.27.x, 1.26.x, 1.25.x |

**注意 2.0.x / 1.22.x / 1.21.x 三者 Envoy 兼容完全一致**（1.38/1.37/1.35）——这意味着这三个 Consul 版本之间升级时，Envoy 可以不动。

### 5.2 关键规则

> "Every major Consul release initially supports **four major Envoy releases**."

**每个 Consul major 初始支持 4 个 Envoy major**。LTS 版本会在 minor 中扩展窗口。

**另一条硬规则**：

> "Support for newer versions of Envoy will **not** be added to existing releases."

**新 Envoy 版本的支持不会回加到旧 Consul 上**。所以想用新 Envoy，必须升 Consul。

### 5.3 consul-dataplane（K8s/无 client 场景）

Consul 1.14 引入的 dataplane 组件把 Envoy 与 dataplane 二进制打进同一个镜像。

| Consul 版本 | 默认 dataplane | 其他兼容 |
|---|---|---|
| 1.22.x CE | 1.9.x (Envoy 1.35.x) | 1.8.x, 1.7.x |
| 1.21.x CE | 1.8.x (Envoy 1.34.x) | 1.7.x, 1.6.x |
| 1.20.x CE | 1.7.x (Envoy 1.33.x) | 1.6.x, 1.5.x |

**规则**：每个 Consul major 支持**上一个和下一个** dataplane 版本，以便平滑升级。

### 5.4 升级顺序（官方）

如果 client 带 Envoy sidecar：

```
停 client agent → 停其 Envoy → 用新版本起 client → 用兼容版本起 Envoy
```

**顺序不能反**。先起 Envoy 再起 client，Envoy 拿不到 bootstrap 配置。

### 5.5 xDS 协议的历史教训（1.10 案例）

这是"为什么不能跳版本"的一个具体案例：

- Consul ≤1.9 只支持 xDS **v2 State of the World**
- Consul 1.10 增加 **v3 Incremental** 支持，**同时保留 v2**
- Consul 1.11 **移除** v2 支持

**官方的阶梯路径**：
1. 先把 Envoy 升到「当前 Consul」和「1.10」**都支持**的最新版
2. 若用了 escape hatch，用 xDS v3 语法重写并重新注册服务
3. 正常升级 Consul 到 1.10（此时旧 Envoy 仍用 v2 通信，没问题）
4. client 升级后，`consul connect envoy` 重新 bootstrap 并重启 Envoy（切到 v3）

**这四步不能压缩**。如果直接从 1.9 跳到 1.11，v2 已被移除，Envoy 会失联。

> ⚠️ **本课实测边界**：本机为**无 Connect、无 Envoy** 的裸集群。以上 Envoy/dataplane/xDS 内容**引自官方文档，未经本机实测**。本机仅实测了 Consul server 侧的 quorum 约束与回滚代价。

---

## 六、本课核心结论

1. **两个 protocol 要分清**：gossip（本机默认 2、懂 2~3）与 Raft（本机 3）是不同东西，升级时分别确认。
2. **社区版一次最多跳 2 个 major**，企业 LTS 最多 3 个。官方只承诺**向后兼容一个版本**。
3. **滚动顺序：follower → leader → client**，且**一次只能停 n-quorum 台**（实测 3 节点只能停 1 台）。
4. **停超会立刻失去写能力**：实测停 2 台后 leader 为空、写操作 HTTP 000。
5. **回滚不是免费的**（本课实测）：回滚 = 全量回退，老数据回来，但**升级窗口内的新数据全丢**。
6. **Envoy 必须跟着 Consul 走**：每个 Consul major 初始支持 4 个 Envoy major，且新 Envoy 支持**不回加**到旧 Consul。

---

## 七、与课 8 的衔接

本课讲的是**单 DC 内**的版本升级。课 8（多机房与 K8s 运维视角）会把这个复杂度再翻一倍：

> 多 DC 联邦时，**各 DC 可以跑不同版本**吗？升级要不要全 DC 同步？K8s 上 consul-k8s 组件的版本怎么跟 Consul 对齐？

---

## 课尾导航

- **上一课**：[课 6 监控指标与告警](lesson-06-监控指标与告警.md)
- **回索引**：[运维专项 overview](../overview.md)
- **下一课**：[课 8 多机房与 K8s 运维视角](lesson-08-多机房与K8s运维视角.md)
- **相关**：主线[课 2 Consul 是什么与能力全景](../../../stages/1-认识Consul/lessons/lesson-02-Consul是什么与能力全景.md)、主线[课 11 许可证成本与风险](../../../stages/4-决策落地/lessons/lesson-11-许可证成本与风险.md) 缺口 #5
- **急用**：回滚后数据倒退 → 查 [09-排障速查手册](../../../09-排障速查手册.md) 症状 11

### 小测

1. 3 节点集群做滚动升级，一次最多能停几台？停多了会发生什么？
2. 社区版 Consul 一次升级最多能跳几个 major？企业 LTS 呢？
3. 回滚（恢复升级前快照）之后，升级窗口内新注册的服务还在吗？为什么？
4. 你在 1.9 上跑着 Envoy，想直接跳到 1.11，为什么不行？
5. `consul version` 显示 "understands 2 to 3"，`raft list-peers` 显示 RaftProtocol=3。这两个数字是同一个东西吗？

<details>
<summary>答案</summary>

1. **1 台**（`n - quorum = 3 - 2 = 1`）。停 2 台就失去 quorum：实测 leader 变为空、写操作返回 HTTP 000（超时失败）。
2. 社区版**最多跳 2 个 major**；企业版 LTS **最多跳 3 个**（LTS → 下一个 LTS）。官方只承诺向后兼容一个版本，所以必须逐级走。
3. **不在了。** 因为恢复是**全量覆盖**（课 5 已证明），回滚 = 把集群回退到快照那一刻，快照之后的所有写入（包括升级窗口内的新注册）全部丢弃。实测中 `app/newsvc` 与 `app/migration` 回滚后均为空。
4. 因为 Consul ≤1.9 只支持 **xDS v2**，而 **1.11 移除了 v2 支持**。1.10 是过渡版本（同时支持 v2/v3）。必须从 1.9 → 1.10（Envoy 仍用 v2 可用）→ 重新 bootstrap Envoy 切 v3 → 再升 1.11。
5. **不是。** "understands 2 to 3" 是 **gossip/serf protocol**；`RaftProtocol=3` 是 **Raft 一致性层协议**。两者独立版本化，升级时需分别确认，不能互相套用。

</details>
