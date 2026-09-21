# 课 5：备份、恢复与灾备演练

> 面向：运维 / SRE
> 前置：课 1（生产部署）、课 2（集群健康）、课 4（证书与密钥生命周期）
> 本课所有数字均来自本机 WSL Ubuntu 24.04 + Consul 2.0.2 三节点集群实测（2026-09-20），**含一次完整的"全毁—重建—恢复"实验**。

---

## 引子：备份做了三年，恢复从没验证过

这是运维界最经典的谎言之一：**"我们有备份。"**

然后真出事的那天，你 `consul snapshot restore` 完，发现：
- KV 数据回来了
- 服务目录回来了
- 但所有服务的 mTLS 全部失败

或者更糟：恢复完了，你发现**恢复后比恢复前丢的数据更多**。

Consul 的快照有三件事，任何一件不知道都会让你在灾备现场翻车：

1. 快照**包含什么**（比你以为的多）
2. 快照**不包含什么**（比你以为的少）
3. 恢复是**全量覆盖**，不是合并（这条最要命）

---

## 一、快照包含什么

### 1.1 用 inspect 看到真实内容

不要猜。Consul 自带 `snapshot inspect`：

```console
$ consul snapshot inspect full.snap
   ID           2-2103-1789905954217
   Size         11398
   Index        2103
   Term         2
   Version      1

   Type                        Count      Size
   ----                        ----       ----
   Register                    9          6.8KB
   ConnectCA                   1          1.2KB
   ConnectCAProviderState      1          1.1KB
   Index                       22         668B
   CoordinateBatchUpdate       3          522B
   Autopilot                   1          199B
   ConnectCAConfig             1          195B
   SystemMetadata              3          191B
   FederationState             1          142B
   KVS                         1          96B
   ChunkingState               1          12B
   ----                        ----       ----
   Total                                  11.1KB
```

**注意这三行**：

```
ConnectCA                   1          1.2KB
ConnectCAProviderState      1          1.1KB
ConnectCAConfig             1          195B
```

**CA 的根证书、provider state、配置，三样全在快照里。**

### 1.2 一个必须纠正的流行说法

很多资料（包括 HashiCorp 官方 K8s 灾备教程）会说：

> "恢复主数据中心需要四个 secret：ACL bootstrap token、Consul CA cert、**Consul CA key**、gossip 加密密钥。缺了这些无法恢复。"

这句官方表述让很多人理解成"**快照不含 CA 私钥，所以必须另外备份 CA key**"。

但我的实测给出了**相反的证据**。解压快照直接搜私钥：

```
真 EC PRIVATE KEY 出现 1 次 @ [10542]
内容: -----BEGIN EC PRIVATE KEY-----
      MHcCAQEEIO/pktNPkFomvxVxFLM/gQEOnSIeNTU6K7uCICwTjJfaoAoGCCqGSM49
      AwEHoUQDQgAE55ndI1IigjtwPSkSvP4wMYd8wh7WeJfWh3uGk4OuF+gGwW2xnxQB
      8E8Sie3PFNYYP1qUlvWt70cpSHh5aykKxw==
      -----END EC PRIVATE KEY-----
```

**快照里有一把真实的 EC 私钥。**

### 1.3 决定性实验：全毁 → 重建 → 恢复

关键字搜索只能证明"有私钥字符串"，不能证明"这把私钥能让 CA 复活"。所以我做了决定性实验。

**实验设计**：
1. 记录原集群 CA 指纹
2. 写数据标记 `lesson5/marker = before-snap`
3. 保存快照
4. **杀掉全部节点 + 删除全部 data_dir**（彻底全毁）
5. 起一个全新集群（必然生成全新 CA）
6. 用旧快照恢复
7. 看 CA 指纹是否回到原样

**实测结果**：

```console
快照前   ActiveRootID = 1f:fd:0a:49:34:84:f5:5e:99:bb:51:5c:53:7a:8e:0e:3e:8a:3d:a4
新集群   ActiveRootID = a0:4e:bd:d3:7d:06:60:32:2e:ff:3f:e4:65:3a:97:29:93:08:75:2f
恢复后   ActiveRootID = 1f:fd:0a:49:34:84:f5:5e:99:bb:51:5c:53:7a:8e:0e:3e:8a:3d:a4
================================================================
恢复后 == 快照前 ? True
RootCert 内容一致? True
marker(KV) = before-snap
```

**三个判据全部指向同一结论**：

| 判据 | 结果 | 说明 |
|---|---|---|
| ActiveRootID | `1f:fd:0a...` 完全还原 | CA 身份回来了 |
| RootCert 内容 | 逐字节一致 | 不只是 ID，证书本体也一样 |
| KV marker | `before-snap` 回来了 | 数据面同时恢复 |

**结论：在本实测环境（Consul 2.0.2 + 内置 CA）下，快照恢复会让 CA 完整复活。**

### 1.4 那官方为什么要单独备份 CA key？

这不是官方错了，而是**场景不同**。官方 K8s 灾备教程说的是：

> "为了使新的部署能够与联合的辅助数据中心通信，恢复的数据中心必须使用**相同的 CA 证书、CA 密钥、Gossip 加密密钥**。"

关键词是**联合的辅助数据中心（WAN federation）**。在联邦场景下，辅助 DC 持有主 DC CA 签发的证书；如果主 DC 重建后 CA 变了，跨 DC 信任链就断了。

而且还有一个**实践层面的硬理由**：快照本身是**加密敏感数据**。官方文档明确警告：

> "Consul snapshots contain extremely sensitive data (e.g. credentials in recoverable form) and therefore should only be stored on an encrypted medium with sufficiently strict access controls in place."

**"credentials in recoverable form"** —— 这句话本身就承认了快照里有可恢复的凭证。

**所以正确的理解是**：

| 说法 | 适用性 |
|---|---|
| "快照不含 CA 私钥，必须另外备份 CA key" | ❌ 不准确。实测快照含 CA provider state（含私钥） |
| "快照含 CA，恢复后 CA 会复活" | ✅ 本实测证实（单 DC、内置 CA、同版本） |
| "仍应单独备份 CA key 和 gossip key" | ✅ 作为**深度防御**仍然推荐。理由：①联邦场景需要 ②快照可能损坏/版本不兼容 ③快照泄露等于全套凭证泄露，单独备份不是为恢复，而是为保险 |

**一句话收束**：**快照能恢复 CA，但你仍然应该单独备份密钥**——不是为了"能不能恢复"，而是为了"万一丝毫差池时还有退路"。

---

## 二、快照不包含什么

这才是真正的坑。实测同样说明问题。

### 2.1 反直觉第一层：快照是压缩的

第一次探测时我直接 grep 压缩文件：

```console
$ grep -c "PRIVATE KEY" probe.snap
0
$ grep -c "consul" probe.snap
0
```

**全是 0。** 如果我在这里下结论，就会写出"快照不含任何私钥"的错误结论。

实际上：

```console
$ file probe.snap
probe.snap: gzip compressed data, original size modulo 2^32 15360
```

**快照是 gzip 压缩的 tar 包**，直接 grep 当然什么都搜不到。解压后 15360 字节，私钥就在里面。

> 📌 **方法论教训**：这次差点犯的错，正是"凭表面证据下结论"。**先确认你的检测手段有效，再相信检测结果。**

### 2.2 真正不包含的东西

快照是 **Raft 状态机（FSM）的序列化**，只含有状态机里的东西。**以下都不在快照里**：

| 不在快照里的东西 | 在哪 | 丢了怎么办 |
|---|---|---|
| **agent 本地配置**（hcl 文件） | 各节点磁盘 | 配置管理（Ansible/K8s ConfigMap）负责 |
| **gossip 加密密钥** | 配置文件 `encrypt` | 必须单独备份 |
| **TLS 证书/私钥文件** | 磁盘 pem | 必须单独备份 |
| **client agent 的 ACL token**（若未持久化） | agent 内存/配置 | 恢复后 client 无法注册 |
| **Raft 日志中快照点之后的写入** | 日志 | 见 2.4 |

### 2.3 client agent 的 token 陷阱

官方文档明确列了这个行为表：

| Token 持久化已启用 | 配置里直接写了 ACL token | 恢复后 client 需要重新配置？ |
|---|---|---|
| Yes | No | No |
| Yes | Yes | No |
| No | Yes | No |
| **No** | **No** | **Yes** |

**命中最后一行**：如果 client 的 token 是通过 API/CLI 设置的（没写进配置文件、没开 token 持久化），恢复后 **client 会失去注册权限，静默失效**。

这又是一个"进程还在但不工作"的场景。

### 2.4 快照点之后的写入会丢

快照是**某个 Raft index 的时间点**。我保存时：

```console
$ consul snapshot save full.snap
Saved and verified snapshot to index 2103
```

index 2103 之后的所有写入，恢复后**不存在**。这就是 RPO（Recovery Point Objective）的物理来源——**你的备份频率直接决定了你最多丢多少数据**。

---

## 三、恢复是全量覆盖，不是合并

这是本课最重要、也最容易在生产上捅娄子的一条。

### 3.1 实测证明

```console
# 恢复后的集群上，写一个新 KV
$ curl -X PUT -d 'after-restore' .../v1/kv/lesson5/after
当前 lesson5/marker = before-snap     ← 快照里带的
当前 lesson5/after  = after-restore   ← 新写的

# 再恢复一次同一个旧快照（该快照只含 marker，不含 after）
$ consul snapshot restore full.snap
Restored snapshot

# 检查
lesson5/marker = before-snap     ← 回来了
lesson5/after  =                 ← 空了！没了！
```

**`after` 被抹掉了。**

### 3.2 这意味着什么

恢复**不是**"把快照里的数据合并进现有集群"，而是：

```
集群状态 := 快照状态
```

**完全替换。原子替换。**

所以：

| 你以为 | 实际 |
|---|---|
| 恢复 = 把丢的数据补回来 | 恢复 = 把整个集群**回退**到快照那一刻 |
| 快照后新写的数据会保留 | **快照后新写的全部丢弃** |
| 可以在线恢复修数据 | 恢复会让集群**回到过去**，包括删掉你不小心写错的东西，也删掉正确的新数据 |

### 3.3 一个真实的事故模型

```
09:00  定时快照
10:00  运维误删了一批 KV
11:00  开发上线了一批新服务注册
12:00  发现 10:00 的误删，决定"恢复一下"
       ↓
       恢复到 09:00
       ↓
   ✅ 误删的 KV 回来了
   ❌ 11:00 上线的全部服务注册 消失了
```

**你在修一个错误的同时制造了另一个错误。**

### 3.4 正确的姿势

1. **恢复前先保存当前状态**（即使它是错的）：`consul snapshot save emergency-$(date +%s).snap`。给自己留后悔药。
2. **恢复是最后手段**，不是常规工具。单条 KV 误删应该重写那条 KV，而不是恢复整个集群。
3. **恢复窗口要公告**。恢复是回退，影响面是全量。

---

## 四、灾备演练：怎么验证一次真恢复

"我们有备份"和"我们能恢复"之间，隔着一次**真实的演练**。

### 4.1 演练的完整流程（本课实际执行过的）

```bash
# 阶段 1：记录恢复前的指纹（CA、KV 抽样）
curl -s $CONSUL_HTTP_ADDR/v1/connect/ca/roots > roots_before.json

# 阶段 2：打数据标记
curl -s -X PUT -d 'before-snap' .../v1/kv/lesson5/marker

# 阶段 3：保存 + 验证快照
consul snapshot save full.snap
consul snapshot inspect full.snap      # 必做：确认内容符合预期

# 阶段 4：全毁（演练环境专用）
pkill -f 'consul agent'
rm -rf data/node1 data/node2 data/node3

# 阶段 5：起全新集群
# （注意：新集群会生成全新 CA，这是正常现象）

# 阶段 6：恢复
consul snapshot restore full.snap

# 阶段 7：验证（三条缺一不可）
#   7.1 CA 指纹是否还原
#   7.2 数据标记是否回来
#   7.3 集群是否健康（leader/quorum）
```

### 4.2 演练必查清单

| 检查项 | 怎么验 | 本课实测值 |
|---|---|---|
| 快照能否 inspect | `consul snapshot inspect` | ✅ 11 种类型，11.1KB |
| CA 是否还原 | 对比 `ActiveRootID` | ✅ `1f:fd:0a...` 一致 |
| 数据是否回来 | 读标记的 KV | ✅ `before-snap` |
| 集群是否健康 | `consul operator raft list-peers` | ✅ 3 voter，有 leader |
| **恢复是否全量覆盖** | 写新 KV 再恢复，看是否被抹 | ✅ 已证实会抹 |

### 4.3 备份策略建议

| 维度 | 建议 | 理由 |
|---|---|---|
| 频率 | 生产至少**每小时** | RPO 直接由频率决定（课内实测：快照点后写入全丢） |
| 存储 | **异地 + 加密介质** | 官方明确警告快照含 "credentials in recoverable form" |
| 保留 | 至少 7 天，含跨天/跨周 | 误删可能几天后才发现 |
| 一致性模式 | 常规用 `stale`，关键变更后用 default | `stale` 减轻 leader 负担，但可能丢最后 100ms 写入 |
| 演练 | **至少每季度一次真恢复** | 官方原话："regularly test and validate the restore process" |

**关于 stale 模式**（官方原文）：

> "To reduce the burden on the leader, it is possible to run the snapshot command on any server in stale consistency mode. For scheduled backups or other non-critical procedures, stale consistency mode is an appropriate backup solution. Not having full consistency means that a small number of recent writes may be omitted, although these writes are typically limited to data written in the last 100ms or less. However, we still recommend you take consistent snapshots for write-heavy production use cases..."

**解读**：定时备份用 stale 没问题（最多丢 100ms 写入），但**写密集的生产场景必须用 consistent 模式**。

---

## 五、本课核心结论

1. **快照包含 CA 全套**（`ConnectCA` + `ConnectCAProviderState` + `ConnectCAConfig`），实测全毁重建后 CA 完整复活（ActiveRootID 与 RootCert 逐字节一致）。
2. **"快照不含 CA 私钥"的说法不准确**——快照里实测存在真实 EC 私钥。但**仍应单独备份密钥**作为深度防御（联邦场景、快照损坏、快照泄露）。
3. **快照是 gzip 压缩的**，直接 grep 会得到假阴性。**先验证检测手段，再相信结论**。
4. **恢复是全量覆盖**（实测：快照后新写的 KV 被抹掉）。恢复 = 回退到过去，不是合并。
5. **不在快照里**：agent 配置、gossip key、TLS 文件、未持久化的 client token。
6. **快照点之后的写入会丢**，RPO = 备份频率。

---

## 六、与课 7 的衔接

本课结论直接决定了课 7（版本升级）的**回滚代价**：

> 升级失败想回滚？回滚手段是"恢复升级前的快照"。
> 而恢复是**全量覆盖**——意味着回滚会**同时抹掉升级过程中产生的一切数据**。
>
> **所以：回滚不是无代价的。** 这是课 7 的核心认知之一。

---

## 课尾导航

- **上一课**：[课 4 证书与密钥生命周期](lesson-04-证书与密钥生命周期.md)
- **回索引**：[运维专项 overview](../overview.md)
- **下一课**：[课 6 监控指标与告警](lesson-06-监控指标与告警.md)（✅ 已交付）
- **相关**：主线[课 11 许可证成本与风险](../../../stages/4-决策落地/lessons/lesson-11-许可证成本与风险.md) 缺口 #3
- **急用**：恢复后数据倒退 → 查 [09-排障速查手册](../../../09-排障速查手册.md) 症状 11

### 小测

1. 我看到某资料说"快照不含 CA 私钥"，于是在灾备方案里只备份快照。这个方案够吗？为什么？
2. 你 `grep "PRIVATE KEY" backup.snap` 返回 0，能否得出"快照不含私钥"的结论？
3. 恢复快照后，快照时刻之后写入的数据会怎样？
4. 为什么恢复前应该先对当前（哪怕是错误的）状态做一次快照？
5. 定时备份用 `stale` 模式最多可能丢多少数据？什么场景必须用 consistent？

<details>
<summary>答案</summary>

1. **不够。** ①实测快照确实含 CA（全毁重建后 CA 复活），但**单独备份密钥仍是必要的深度防御**：联邦场景需要相同 CA 才能跨 DC 通信；快照可能损坏或版本不兼容；快照泄露等于全套凭证泄露。②另外 gossip key 和 TLS 文件**根本不在快照里**，只备份快照必然丢这两样。
2. **不能。** 快照是 gzip 压缩的 tar 包（实测 `file` 输出 `gzip compressed data`），直接 grep 必然是 0，这是假阴性。必须先解压再搜。这是"先验证检测手段再相信结论"的典型案例。
3. **全部丢失。** 恢复是全量覆盖（实测：恢复后新写的 `lesson5/after` 变成空），集群状态被完整替换为快照时刻的状态。
4. 因为恢复是不可逆的全量回退。先保存当前状态，万一恢复后发现问题（比如意识到回退过头了），还有机会回到恢复前。**给自己留后悔药。**
5. `stale` 模式通常最多丢**最后 100ms 以内**的写入。但**写密集的生产场景、以及刚做完关键变更要立即快照时，必须用 consistent 模式**（官方建议）。

</details>
