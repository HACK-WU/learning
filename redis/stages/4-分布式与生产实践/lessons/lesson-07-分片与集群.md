# 课 7：分片与集群

> 阶段 4《分布式与生产实践》第 1 课
> 前置：课 6《主从复制与哨兵》(全量与增量复制、哨兵故障转移、哨兵解决不了的丢数据)
> 环境：WSL Ubuntu 24.04 + Redis 8.10.1（本机实测，核查于 2026-09）

---

## 本课要解决的三个问题

课 5 解决了"重启后数据还在"，课 6 解决了"主库挂了有人接管"。但有一类问题前两课都没碰：

**如果数据量超过一台机器的内存呢？**

主从复制让数据在**多台机器上有相同的副本**。它解决的是"副本不够"，不是"容量不够"。10 个从库，每个都存全量数据——容量还是一台机器的量。

还有第二个压力：**写入**。所有写操作都打到主库，主库是单点。数据量涨、QPS 涨，单机的 CPU 和网络都会先到瓶颈。

本课要回答三个问题：

1. **数据怎么分到多台机器上？** —— 哈希槽与 CRC16
2. **加机器 / 减机器时数据怎么搬？** —— 集群伸缩与重定向
3. **分片之后，哪些操作做不了了？** —— 多 key 与 Lua 限制

---

## 第一幕：场景引入 —— 三个真实困境

### 困境一：单机内存撑爆，加内存也没用

业务涨到 800 GB 数据，已经超过单机能稳定承载的规模。

更大的机器确实买得到，但即使你买到 1 TB 的机器，还有别的问题：

- **fork 时间变长**：课 5 讲过，RDB 持久化要 fork。数据越大，页表越大，fork 越慢。800 GB 数据的 fork 可能要几秒，期间主线程阻塞。
- **重启恢复慢**：AOF 重放 800 GB 数据要几十分钟。
- **主从全量同步代价高**：每次从库上线，主库都要传 800 GB。

容量问题不是加内存能解决的，得**分到多台机器**。

### 困境二：写 QPS 打满，从库帮不上忙

写请求 20 万 QPS，单主库已到瓶颈。你加了 10 个从库做读写分离——但**从库只能分担读，写还是全部打到主库**。

主从复制是"一份数据，多个副本"，不是"一份数据，切成多份"。写压力不会因为有从库而减少。

### 困境三：手动分片，改一次配置脱层皮

团队自己在应用层做分片：

```python
shard_id = hash(key) % 4          # 4 个 Redis 实例
redis_client = clients[shard_id]
redis_client.set(key, value)
```

跑了一年，要扩容到 8 个实例。问题来了：

```
hash(key) % 4  →  hash(key) % 8
```

**绝大部分 key 的归属都变了**。你要么停机迁移全量数据，要么写双写逻辑、灰度切流、最后清旧数据。整个团队折腾两周。

这就是**取模分片的致命伤：节点数变化会导致几乎所有 key 重新分布**。

---

## 第二幕：认知冲突 —— 三个"想当然"的崩塌

### 冲突一：Redis 不直接把 key 映射到节点，中间多了一层"槽"

你可能以为分片就是 `hash(key) % 节点数`。**Redis 不是这么做的。**

Redis 引入了一个中间层：

```
key ──CRC16──> 槽(slot, 0~16383) ──分配──> 节点(node)
```

槽的数量**固定 16384 个**，不随节点数变化。节点只负责"我拥有哪些槽"。

这个设计的关键价值：**扩缩容时，key → 槽 的映射完全不变，只改 槽 → 节点 的映射**。

```
3 个节点时：槽 0-5460 → A，槽 5461-10922 → B，槽 10923-16383 → C
加一个 D： 槽 0-5460 → A，槽 5461-8000 → D，槽 8001-10922 → B，...
```

`user:1001` 始终在槽 5712，只是这个槽从 B 搬到了 D。

**为什么是 16384？** 官方文档和作者 antirez 在 GitHub issue #2576 的解释：

1. **心跳包大小**：集群节点间通过 gossip 协议互发心跳，心跳里携带槽位图（bitmap）。16384 bit = 2 KB，刚好塞进一个以太网帧；65536 bit 就要 8 KB，会造成 IP 分片。
2. **集群规模**：设计上限约 1000 个主节点。16384 个槽分给 1000 个节点，平均每节点 16 个槽，粒度足够；再多只会徒增网络开销。

> 📌 **实测核对**：官方文档明确写的是 "16384 slots, effectively setting an upper limit for the cluster size of 16384 master nodes (however, the suggested max size of nodes is on the order of ~ 1000 nodes)"。

### 冲突二：多 key 命令在集群下大面积失效

单机上随手就用的命令，在集群下直接报错：

```
127.0.0.1:7001> MGET user:1001:profile user:1001:orders
(error) CROSSSLOT Keys in request don't hash to the same slot
```

本机实测，这些常用命令**全部**跨槽失败：

| 命令 | 跨槽结果 |
|------|---------|
| `MGET k1 k2` | `CROSSSLOT` |
| `MSET kx 1 ky 2` | `CROSSSLOT` |
| `SINTER sk1 sk2` | `CROSSSLOT` |
| `SUNIONSTORE dst sk1 sk2` | `CROSSSLOT` |
| `RENAME k1 k2` | `CROSSSLOT` |

**原因**：集群没有跨节点的多 key 原子性。要保证原子，所有 key 必须在同一节点——Redis 的做法是要求它们在**同一个槽**。

解法是**哈希标签**（hash tag），本课第三幕知识点 1 会细讲。

### 冲突三：`--pipe` 批量导入在集群下会静默丢数据

这是我在备课实测里踩的坑，值得单独说。

用 `--pipe` 往集群灌 3000 条数据：

```
$ redis-cli -c -p 7001 --pipe < data.txt
All data transferred. Waiting for the last reply...
Last reply received from server.
errors: 1878, replies: 3000        ← 1878 条失败！
```

**1878 条失败，但退出码是 0，不看那行 errors 根本发现不了。**

原因：`--pipe` 是纯管道批处理，它把命令一股脑塞给连上的那个节点，**不解析 MOVED、不跟随重定向**。落到其他槽的命令全部失败。

而逐条用 `-c` 执行就能全成功（实测 3000/3000），但慢：耗了 4.78 秒。

正确做法见本课知识点 2 的"实验 2"，按槽分组后各节点 `--pipe`，实测 **9 毫秒**完成——比逐条快 **531 倍**。

---

## 第三幕：层层揭示 —— 三个知识点

## 知识点 1：哈希槽与 CRC16

### 1.1 槽分配的实际形态

本机实测搭建的 3 主 3 从集群：

```
127.0.0.1:7001@17001 myself,master  -  0-5460        (5461 slots)
127.0.0.1:7002@17002 master         -  5461-10922    (5462 slots)
127.0.0.1:7003@17003 master         -  10923-16383   (5461 slots)
127.0.0.1:7004@17004 slave          -  replicates 7003
127.0.0.1:7005@17005 slave          -  replicates 7001
127.0.0.1:7006@17006 slave          -  replicates 7002
```

注意端口后面的 `@17001`——这是**集群总线端口**（客户端端口 + 10000）。节点间的心跳、gossip、故障检测都走这条独立的 TCP 连接，不占用客户端端口。

```
cluster_state:ok
cluster_slots_assigned:16384      ← 全部槽已分配
cluster_slots_ok:16384
cluster_slots_fail:0
cluster_known_nodes:6
cluster_size:3                    ← 3 个主节点
```

`cluster_size` 是**主节点数**，不含从库。

### 1.2 CRC16 算法：能自己手算的那种简单

官方文档给出的规范：

| 项 | 值 |
|---|---|
| 名称 | XMODEM（也称 ZMODEM / CRC-16/ACORN） |
| 宽度 | 16 位 |
| 多项式 | `0x1021`（即 x¹⁶ + x¹² + x⁵ + 1） |
| 初始值 | `0x0000` |
| 输入反射 | 否 |
| 输出反射 | 否 |
| 输出异或 | `0x0000` |
| 校验值 | `"123456789"` → `0x31C3` |

计算公式：

```
HASH_SLOT = CRC16(key) mod 16384
```

因为 16384 = 2¹⁴，取模等价于按位与：`CRC16(key) & 16383`。

**Python 实现（20 个 key 全部与 `CLUSTER KEYSLOT` 吻合）**：

```python
def crc16(data: bytes) -> int:
    """CRC16-XMODEM: 多项式 0x1021, 初值 0, 无反射"""
    crc = 0
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            if crc & 0x8000:
                crc = ((crc << 1) ^ 0x1021) & 0xFFFF
            else:
                crc = (crc << 1) & 0xFFFF
    return crc

def hash_slot(key: bytes) -> int:
    """Redis 哈希槽：先处理哈希标签，再 CRC16 & 16383"""
    s = key.find(b'{')
    if s != -1:
        e = key.find(b'}', s + 1)
        if e != -1 and e != s + 1:   # {} 之间至少要有 1 个字符
            key = key[s+1:e]
    return crc16(key) & 16383
```

本机实测一致性校验（`prep-lesson-07-crc16-verify.sh`）：

```
key                      KEYSLOT   手写实现   一致?
foo                      12182     12182      YES
bar                      5061      5061       YES
hello                    866       866        YES
user:1001                5712      5712       YES
user:{1001}              15391     15391      YES
user:{1001}:profile      15391     15391      YES
{}abc                    5980      5980       YES
a{b}c{d}                 3300      3300       YES
abc{                     3048      3048       YES
x{}y                     16116     16116      YES
...
结果：一致 20 个，不一致 0 个
```

**为什么能自己算？** 因为客户端需要它。Redis Cluster **没有代理层**——客户端自己算槽、自己维护槽到节点的映射表、自己直连正确的节点。这就是"智能客户端"的含义。

### 1.3 哈希标签：让多个 key 落进同一个槽

规则（官方文档原文）：

> IF the key contains a `{` character
> AND IF there is a `}` character to the right of `{`
> AND IF there are one or more characters between the first occurrence of `{` and the first occurrence of `}`
> THEN instead of hashing the key, only what is between the first occurrence of `{` and the following first occurrence of `}` is hashed.

翻译成人话：**取第一个 `{` 与其后第一个 `}` 之间的内容；若这对括号不存在、为空、或中间没字符，则整个 key 参与计算。**

**边界 case 实测**（这段最容易搞错，建议对照着记）：

| key | 槽 | 实际参与 CRC16 的部分 | 说明 |
|-----|-----|---------------------|------|
| `user:{1001}` | 15391 | `1001` | 标准用法 |
| `{1001}` | 15391 | `1001` | 标签在开头也可以 |
| `user:{1001}:profile` | 15391 | `1001` | 前后都能有内容 |
| `a{b}c{d}` | 3300 | `b` | **只取第一对**，`{d}` 被忽略 |
| `{}abc` | 5980 | `{}abc` | 空标签，不生效 |
| `user:{}:x` | 14781 | `user:{}:x` | 空标签，不生效 |
| `abc{` | 3048 | `abc{` | 没有闭合，不生效 |
| `}{abc` | 15680 | `}{abc` | `}` 在 `{` 之前，不生效 |
| `x{}y` | 16116 | `x{}y` | 空标签，不生效 |

⚠️ **一个重要的推论**：如果 key 以 `{}` 开头，则**保证**整个 key 参与哈希。官方文档说这在处理二进制 key 名时很有用。

**哈希标签的实用价值**——实测对比：

```
不带标签（分散，无法原子操作）：
  user:1001:profile      -> slot 2549
  user:1001:orders       -> slot 4492
  user:1001:cart         -> slot 6577

带标签（全部同槽，可 MGET / 事务 / Lua）：
  user:{1001}:profile    -> slot 15391
  user:{1001}:orders     -> slot 15391
  user:{1001}:cart       -> slot 15391
```

对应的操作结果：

```
# 跨槽
127.0.0.1:7001> MGET user:1001:profile user:1001:orders user:1001:cart
(error) CROSSSLOT Keys in request don't hash to the same slot

# 同槽
127.0.0.1:7001> MGET user:{1001}:profile user:{1001}:orders user:{1001}:cart
1) "p1"
2) "o1"
3) "c1"
```

### 1.4 哈希标签的陷阱：过度使用会制造热点

标签把所有带该标签的 key 钉在同一个槽，也就是**同一个节点**。

实测：

```
{global}:a       -> slot 10408
{global}:b       -> slot 10408
{global}:c       -> slot 10408
```

如果所有 key 都用 `{global}`，那 16383 个槽空闲，全部流量打到一个节点——**集群失去分片意义**。

典型坏例子：按租户打标签。

```
{tenant_A}:user:1
{tenant_A}:user:2
...
{tenant_A}:user:10000000     ← 一个大租户 = 一个打不散的热点节点
```

**原则：标签粒度取"多 key 操作真正需要的最小范围"**。需要一起操作的 key 才共享标签，不要图省事全用同一个。

### 1.5 一个 Redis 8 的新优化：含标签的 SCAN 只扫对应槽

官方文档（Redis 8.0+）说明：`KEYS` / `SCAN` / `SORT` 等接受 glob pattern 的命令，若 pattern 含哈希标签、标签前无通配符、标签内无通配符，则**只扫描该槽**。

本机实测（3999 个 key，其中 2000 个带 `{tag1}` 标签）：

| 扫描方式 | 匹配数 | 耗时 |
|---------|-------|------|
| `SCAN MATCH '{tag1}*'` | 2000 | 11 ms |
| `SCAN MATCH 'plain:*'` | 746 | 15 ms |

数据量小时差异不明显，但大规模集群下，能定位到单槽 vs 必须扫全部 16384 个槽，差别是数量级的。

> 📌 这也说明：**key 设计里的哈希标签，不只是为了多 key 操作，也影响扫描效率。**

---

## 知识点 2：集群伸缩与重定向

### 2.1 扩容的完整流程

本机实测：从 3 主扩到 4 主，迁移 1000 个槽。

**第 1 步：启动新节点**（此时是空节点，不持有任何槽）

```bash
redis-server /path/7007/redis.conf      # cluster-enabled yes
```

**第 2 步：加入集群**

```bash
redis-cli --cluster add-node 127.0.0.1:7007 127.0.0.1:7001
# [OK] New node added correctly.
```

加入后 `cluster_known_nodes` 从 6 变 7，但 `cluster_size` 仍是 3——**新节点还没有槽，不承载数据**。

**第 3 步：迁移槽**

```bash
redis-cli --cluster reshard 127.0.0.1:7001 \
  --cluster-from all \
  --cluster-to <新节点ID> \
  --cluster-slots 1000 \
  --cluster-yes
```

实测输出与耗时：

```
Moving 333 slots from 127.0.0.1:7001 to 127.0.0.1:7007
Moving 334 slots from 127.0.0.1:7002 to 127.0.0.1:7007
Moving 333 slots from 127.0.0.1:7003 to 127.0.0.1:7007
迁移耗时: 3.01 秒
```

迁移后槽分布（注意 7007 的槽是**不连续**的三段）：

```
127.0.0.1:7002  master  5795-10922
127.0.0.1:7003  master  11256-16383
127.0.0.1:7001  master  333-5460
127.0.0.1:7007  master  0-332 5461-5794 10923-11255    ← 三段
```

**这是正常的**。槽是分配单位，不要求连续。多次 reshard 后槽必然碎片化。

### 2.2 缩容：先把槽搬空，再删节点

顺序不能反——**有槽的节点删不掉**。

```bash
# 第 1 步：把 7007 的 1000 个槽迁回 7001
redis-cli --cluster reshard 127.0.0.1:7001 \
  --cluster-from <7007的ID> \
  --cluster-to <7001的ID> \
  --cluster-slots 1000 --cluster-yes
# 迁移耗时: 1.01 秒

# 第 2 步：确认 7007 已空（无槽）
redis-cli -p 7001 cluster nodes | grep 7007

# 第 3 步：删除节点
redis-cli --cluster del-node 127.0.0.1:7001 <7007的ID>
# 删除后 known_nodes 从 7 回到 6
```

### 2.3 MOVED 重定向：槽已永久易主

客户端把命令发给了错误的节点，节点**不转发**，而是回一个重定向：

```
$ redis-cli -p 7001 get foo
(error) MOVED 12182 127.0.0.1:7003
```

含义：**槽 12182 现在归 7003 了，永久的**。客户端应该：

1. 更新本地槽映射表（把 12182 映射到 7003）
2. 重新向 7003 发送这条命令

用 `redis-cli -c` 时会自动跟随，且跟随后再访问就不再有重定向（路由已更新）。

**实测重定向比例**（连到固定节点访问随机 key）：

```
总计 300 次，MOVED 187 次（62.3%），直接命中 113 次
```

约 62% ≈ 2/3，符合"3 节点集群中 2/3 的 key 不属于任一特定节点"的预期。

**为什么客户端必须缓存槽映射表？** 如果不缓存，62% 的请求要两次网络往返，延迟翻倍。这就是"智能客户端"存在的原因。

获取映射表的命令：

```bash
CLUSTER SLOTS      # 传统方式，返回槽区间 + 主从地址
CLUSTER SHARDS     # Redis 7+ 推荐，信息更全（含 endpoint / role / health）
```

### 2.4 ASK 重定向：槽迁移中的临时态

这是本课最容易和 MOVED 混淆的概念。

**ASK 只在迁移过程中出现**。此时槽的归属还标记在源节点，但**这个具体的 key 已经搬到目标节点了**。

**本机实测复现**（手动制造迁移中间态）：

```bash
# 第 1 步：目标节点标记 IMPORTING
redis-cli -p 7001 cluster setslot 12706 importing <源节点ID>
# 目标节点槽状态: [12706-<-<源ID>]

# 第 2 步：源节点标记 MIGRATING
redis-cli -p 7003 cluster setslot 12706 migrating <目标节点ID>
# 源节点槽状态: [12706->-<目标ID>]

# 第 3 步：此时 k1 还在源节点，访问正常
redis-cli -p 7003 get k1
"v-k1"

# 第 4 步：把 key 迁走
redis-cli -p 7003 migrate 127.0.0.1 7001 k1 0 5000
OK

# 第 5 步：key 已搬走，但槽还标记在源 → ASK
redis-cli -p 7003 get k1
(error) ASK 12706 127.0.0.1:7001
    ↑ 这就是 ASK

# 第 6 步：迁移完成，槽正式易主 → MOVED
redis-cli -p 7003 cluster setslot 12706 node <目标ID>
redis-cli -p 7001 cluster setslot 12706 node <目标ID>
redis-cli -p 7003 get k1
(error) MOVED 12706 127.0.0.1:7001
    ↑ 这就是 MOVED
```

### 2.5 MOVED 与 ASK 的本质区别

| | MOVED | ASK |
|---|---|---|
| 含义 | 槽已永久归属另一节点 | 槽迁移中，这个 key 可能已搬走 |
| 出现时机 | 稳态 / 迁移完成后 | 仅迁移过程中 |
| 客户端行为 | **更新**本地槽映射表 | **不更新**，仅本次请求去目标节点 |
| 后续请求 | 直连新节点 | 仍发往原节点 |
| 执行前需要 | 无 | 先发 `ASKING` 命令 |

**为什么 ASK 不能更新映射表？**

因为迁移未完成，槽里**还有一部分 key 留在源节点**。如果客户端把槽 12706 映射到新节点，那么访问**尚未迁走**的 key 时就会被路由到错误位置。

官方规范原文：

> ASK means to send only the next query to the specified node. This is needed because the next query about hash slot 8 can be about a key that is still in A, so we always want the client to try A and then B if needed.

**`ASKING` 是干什么的？**

目标节点在 IMPORTING 状态下，会拒绝关于该槽的普通请求（返回 MOVED 指回源节点）。只有当客户端**先发 `ASKING`** 再发命令时，目标节点才会执行。

这是一道保护：**防止路由表损坏的客户端，误把还没迁完的 key 写进目标节点**，造成新旧两份数据。

官方文档的原文：

> This guarantees that clients with a broken hash slots mapping will not write for error in the target node, creating a new version of a key that has yet to be migrated.

实际开发中，这些细节由客户端库（Lettuce / redis-py-cluster / go-redis / ioredis）处理，你不需要手写。但**排查问题时必须懂**——"缓存了 ASK 目标"是经典的客户端 bug。

### 2.6 集群批量导入的正确姿势

回顾第二幕冲突三的坑，这里给出可复用的解法。

**错误做法**：`redis-cli --pipe` 直连单节点 → 1878/3000 失败

**可行但慢**：逐条 `redis-cli -c set` → 3000/3000 成功，4.78 秒

**正确做法**：按槽分组，各节点各自 `--pipe`

```python
import subprocess, sys

def slot_of(key): ...                    # 用前面的 hash_slot 实现

# 1. 拉取槽→节点映射
nodes = subprocess.run(["redis-cli","-p","7001","cluster","nodes"],
                       capture_output=True, text=True).stdout
slot2port = {}
for line in nodes.splitlines():
    f = line.split()
    if len(f) < 8 or 'master' not in f[2]:
        continue
    port = f[1].split('@')[0].split(':')[1]
    # f[0]=id  f[1]=addr  f[2]=flags  ... 槽区间从下标 8 开始
    # 注意：槽有两种表示 —— 区间 "0-332" 与单槽 "5795"，两种都要处理
    for tok in f[8:]:
        tok = tok.strip('[]')
        if tok.startswith('[') or tok.startswith('-'):
            continue                      # 跳过迁移态标记
        if '-' in tok:                    # 区间
            a, b = tok.split('-')
            if a.isdigit() and b.isdigit():
                for s in range(int(a), int(b) + 1):
                    slot2port[s] = port
        elif tok.isdigit():               # 单个槽
            slot2port[int(tok)] = port

# 2. 按槽分组
groups = {}
for k in all_keys:
    p = slot2port.get(slot_of(k))
    if p:
        groups.setdefault(p, []).append(k)

# 3. 各节点各自 --pipe
for port, keys in groups.items():
    with open(f"/tmp/pipe-{port}.txt", "w") as fh:
        for k in keys:
            fh.write(f"SET {k} v\n")
    subprocess.run(["redis-cli","-p",port,"--pipe"],
                   stdin=open(f"/tmp/pipe-{port}.txt"))
```

**实测对比（3000 个 key）**：

| 方式 | 成功数 | 耗时 |
|------|-------|------|
| `--pipe` 直连单节点 | 1122 / 3000 | — |
| 逐条 `-c` | 3000 / 3000 | 4780 ms |
| 分组 `--pipe` | 2999 / 3000 | **9 ms** |

分组 `--pipe` 比逐条快 **531 倍**。

### 2.7 集群下的其他限制

**`SELECT` 被禁用**——集群只有 db 0：

```
127.0.0.1:7001> SELECT 1
(error) ERR SELECT is not allowed in cluster mode
```

**`FLUSHALL` 只清当前节点**——实测：

```
执行前:     7001=1122  7002=940  7003=937
flushall 7001 后: 7001=0  7002=940  7003=937    ← 其他节点数据还在！
```

集群清库要逐节点执行，或用：

```bash
redis-cli --cluster call 127.0.0.1:7001 flushall
```

**运维常用命令**：

```bash
CLUSTER KEYSLOT <key>              # 查 key 属于哪个槽
CLUSTER COUNTKEYSINSLOT <slot>     # 查某槽有多少 key
CLUSTER GETKEYSINSLOT <slot> <n>   # 列出某槽的 n 个 key
CLUSTER SLOTS / CLUSTER SHARDS     # 获取完整路由表
```

---

## 知识点 3：集群下的多 key 与 Lua 限制

### 3.1 多 key 命令必须同槽

已在冲突二实测过，这里补充完整的判断规则：

| 场景 | 结果 |
|------|------|
| 单 key 命令（GET / SET / HGETALL…） | 始终可用，客户端自动路由 |
| 多 key 且**所有 key 同槽** | 可用 |
| 多 key 且**跨槽** | `CROSSSLOT` 错误 |
| 用哈希标签强制同槽 | 可用 |

### 3.2 Lua 脚本的两道检查

这是本课**最重要、也最容易误解**的部分。我在备课中先后做了三轮实验才把机制搞清楚，这里直接给结论。

**第一道检查（路由层）**：Redis 根据 `numkeys` 和 `KEYS[]` 计算槽，若跨槽直接拒绝。

```
127.0.0.1:7001> EVAL "return redis.call('MGET', KEYS[1], KEYS[2])" 2 k1 k2
(error) CROSSSLOT Keys in request don't hash to the same slot
```

**第二道检查（执行层）**：脚本执行时，若访问了**不在本节点负责范围内**的 key，报错拦截。

```
127.0.0.1:7001> EVAL "redis.call('SET','nodeclared',1); return 'ok'" 1 "{s1}:a"
(error) ERR Script attempted to access a non local key in a cluster node script
```

**关键澄清**：两道检查都是**报错拦截**，不是静默返回错误数据。

我最初以为"脚本里硬编码 key 会静默读到脏数据"，实测发现**不会**——Redis 会明确报错。这比想象中安全。

### 3.3 但有一个"碰巧可行"的陷阱

这个陷阱极具迷惑性，看实测：

```bash
# k1 的槽 12706 归属 7001
# 连到 7001（槽恰好在本地）→ 成功
$ redis-cli -c -p 7001 eval "return redis.call('GET','k1')" 0
"local-value"                          ← 成功了！

# 连到 7002（同一脚本、同一 key）→ 报错
$ redis-cli -c -p 7002 eval "return redis.call('GET','k1')" 0
(error) ERR Script attempted to access a non local key in a cluster node script
```

**同一个脚本、同一个 key，换个连接节点就从"成功"变成"报错"。**

原因：`numkeys=0` 时，脚本**不按槽路由**，而是发到你连上的那个节点。如果 key 的槽恰好归该节点，就正常执行；否则报错。

**这带来两个后果**：

1. 开发时用 `numkeys=0` + 硬编码 key 可能"跑通了"，让你误以为这样写没问题
2. 上线后因为客户端连接池连到不同节点，**行为随机变化**

**正确做法：所有 key 一律写进 `KEYS[]`。**

```
# 错误
EVAL "return redis.call('GET','mykey')" 0

# 正确
EVAL "return redis.call('GET', KEYS[1])" 1 mykey
```

实测对照：

```
numkeys=0 硬编码（key=probe:key，槽归属 7003）：
  连到 7001 → ERR Script attempted to access a non local key
  连到 7002 → ERR Script attempted to access a non local key
  连到 7003 → REAL-VALUE          ← 只有连对节点才行

声明 KEYS：
  连到 7001 → REAL-VALUE
  连到 7002 → REAL-VALUE
  连到 7003 → REAL-VALUE          ← 连哪个节点都行
```

### 3.4 同槽的 key 即使不在 KEYS 里也允许

规则补充：只要**同槽**，脚本内访问未声明的 key 是允许的。

```
# 声明 {s1}:a（槽 15224），脚本内访问 {s1}:zzz（也是槽 15224）
127.0.0.1:7001> EVAL "redis.call('SET','{s1}:zzz','ok'); return redis.call('GET','{s1}:zzz')" 1 "{s1}:a"
"ok"                                   ← 允许
```

所以准确的说法是：**脚本内访问的 key 必须与声明的 KEYS 同槽**。

### 3.5 EVALSHA 的坑：脚本缓存是每节点独立的

`SCRIPT LOAD` 只在**当前节点**缓存脚本。实测：

```
SCRIPT LOAD 返回 SHA = d3c21d0c2b9ca22f82737626a27bcaf5d288f99f

在 7001 上 SCRIPT EXISTS: 1     ← 有
在 7002 上 SCRIPT EXISTS: 0     ← 没有
在 7003 上 SCRIPT EXISTS: 0     ← 没有
```

于是：

```
# 连到没缓存该脚本的节点执行 EVALSHA
127.0.0.1:7003> EVALSHA d3c21d0c... 1 "{s1}:a"
(error) NOSCRIPT No matching script. Please use EVAL.
```

**应对方式**（成熟客户端库已内置）：

1. 捕获 `NOSCRIPT` 错误 → `SCRIPT LOAD` 重新加载 → 重试 `EVALSHA`
2. 或者直接用 `EVAL` 传完整脚本（牺牲一点带宽换取简单）

Redis 7+ 还有 `FUNCTION LOAD`（函数即服务），支持跨节点自动传播，适合需要分发的脚本。

### 3.6 集群下的 Lua 编写规范

综合以上，集群环境写 Lua 的硬性要求：

| 要求 | 原因 |
|------|------|
| 声明的 key 必须同槽 | 跨槽直接 `CROSSSLOT` |
| **所有要操作的 key 尽量写进 `KEYS[]`** | `numkeys=0` 时脚本不按槽路由，行为随连接节点变化 |
| 脚本内访问的 key 必须与声明的 KEYS **同槽** | 跨槽会触发 `ERR Script attempted to access a non local key` |
| 需要多 key 时用哈希标签 | 保证同槽 |
| `EVALSHA` 要处理 `NOSCRIPT` | 脚本缓存按节点独立 |

> 📌 **关于"硬编码 key"的准确说法**：真正的问题不是"硬编码"这个动作，而是**路由依据**。`numkeys=0` 时脚本没有路由依据，会被发到你连上的任意节点——这才是行为随机的根源。
>
> 如果已经声明了至少一个 key（脚本被正确路由到某个节点），那么脚本内访问**与之同槽**的其他 key 是允许的（见 3.4 节实测）。但从可维护性和客户端分析的角度，仍建议把 key 都写进 `KEYS[]`。

**一个正确范例**：

```lua
-- 扣库存：商品库存与订单记录必须同槽
-- key 设计：{sku_1001}:stock  与  {sku_1001}:orders
local stock = tonumber(redis.call('GET', KEYS[1]))
if stock and stock > 0 then
    redis.call('DECR', KEYS[1])
    redis.call('LPUSH', KEYS[2], ARGV[1])
    return 1
end
return 0
```

调用：

```bash
EVAL "<脚本>" 2 "{sku_1001}:stock" "{sku_1001}:orders" "order_9527"
```

两个 key 共享 `{sku_1001}` 标签 → 同槽 → 单节点原子执行。

---

## 第四幕：实操验证 —— 动手跑一遍

> 以下脚本在 `redis/playground/` 目录，WSL 下直接执行即可。

### 实验 1：搭建集群并观察槽分配

```bash
bash redis/playground/prep-lesson-07-cluster-setup.sh
```

产出：3 主 3 从集群，槽分配 7001=0-5460、7002=5461-10922、7003=10923-16383，合计 16384。

**你会看到**：

```
cluster_state:ok
cluster_slots_assigned:16384
cluster_known_nodes:6
cluster_size:3
```

### 实验 2：手算 CRC16 并与 Redis 对账

```bash
bash redis/playground/prep-lesson-07-crc16-verify.sh
```

产出：20 个 key 的 `CLUSTER KEYSLOT` 与手写 Python 实现全部吻合，以及 9 个哈希标签边界 case。

**重点观察**：`a{b}c{d}` 只取 `b`，`{}abc` 整个 key 参与计算。

### 实验 3：完整扩缩容 + ASK 重定向复现

```bash
bash redis/playground/prep-lesson-07-reshard.sh     # 扩缩容流程与耗时
bash redis/playground/prep-lesson-07-ask.sh         # ASK 重定向专项
```

产出：

```
迁移 1000 槽耗时: 3.01 秒
迁移中间态 → ASK 12706 127.0.0.1:7001
迁移完成   → MOVED 12706 127.0.0.1:7001
```

### 实验 4：Lua 限制与 numkeys 陷阱

```bash
bash redis/playground/prep-lesson-07-lua.sh
bash redis/playground/prep-lesson-07-lua2.sh
bash redis/playground/prep-lesson-07-verify2.sh
```

产出：CROSSSLOT 错误、`ERR Script attempted to access a non local key`、以及"同一脚本连不同节点结果不同"的对照实验。

### 实验 5：批量导入与 SCAN 优化

```bash
bash redis/playground/prep-lesson-07-scan.sh
```

产出：三种导入方式的对比（9 ms vs 4.78 秒），以及 `SELECT` / `FLUSHALL` 的集群限制。

---

## 第五幕：体系收束

### 本课核心结论

**知识点 1：哈希槽与 CRC16**

Redis 不把 key 直接映射到节点，中间插了一层固定 16384 个槽。`key → 槽` 永不变化，`槽 → 节点` 可随时调整——这是能在线扩缩容的根本原因。CRC16-XMODEM（多项式 `0x1021`，初值 0）简单到可以自己实现，因为客户端需要自己算路由。哈希标签 `{}` 让相关 key 强制同槽，但过度使用会制造热点。

**知识点 2：集群伸缩与重定向**

扩缩容的实质是搬槽，槽不要求连续（reshard 后必然碎片化）。MOVED 是永久重定向，客户端应更新路由表；ASK 只在迁移中出现，是一次性的，**不能**更新路由表，且执行前要发 `ASKING`。客户端不缓存路由表的话，约 62% 的请求要两次往返。

**知识点 3：多 key 与 Lua 限制**

多 key 操作必须同槽，否则 `CROSSSLOT`。Lua 脚本有两道检查：路由层查 `KEYS[]` 是否跨槽，执行层查脚本内访问的 key 是否归本节点。`numkeys=0` 时脚本发到连接节点，会出现"连对节点能跑、连错节点报错"的迷惑行为——**所有 key 必须写进 `KEYS[]`**。`EVALSHA` 的脚本缓存按节点独立，要处理 `NOSCRIPT`。

### 与前面课程的连接

| 概念 | 课 5 / 课 6 | 本课 |
|------|-----------|------|
| 数据冗余 | 持久化（磁盘副本） | — |
| 高可用 | 主从复制 + 哨兵（多机副本） | 集群内置故障转移 |
| 容量扩展 | — | **分片（本课）** |
| 写性能扩展 | — | **分片（本课）** |

集群**包含**了主从复制——每个分片的主节点有自己的从库。所以集群 = 分片 + 每分片的主从高可用。

课 6 讲的"异步复制可能丢数据"，在集群里同样成立：集群的故障转移也是异步复制，也会丢最后几秒的写入。

### 常见误区

1. **"集群能解决容量问题，也能解决所有性能问题"** —— 集群解决容量和写扩展，但**跨槽多 key 操作做不了**。设计 key 时必须提前考虑访问模式。

2. **"哈希标签随便用，能跑就行"** —— 标签把所有相关 key 钉在一个节点。按大租户打标签 = 制造一个打不散的热点。

3. **"MOVED 和 ASK 都是重定向，处理成一样就行"** —— 完全不同。缓存 ASK 的目标节点会导致迁移期间路由错乱，是经典客户端 bug。

4. **"Lua 脚本里硬编码 key，测试能跑通就没问题"** —— `numkeys=0` 时行为取决于连到哪个节点。测试连对了，生产连错了。

5. **"`--pipe` 批量导入很快，集群也这么用"** —— 实测 1878/3000 静默失败，退出码还是 0。

6. **"槽数是 65536 吧，CRC16 是 16 位的"** —— 是 16384，只取低 14 位。原因在心跳包大小。

### 决策参考：什么时候用集群

| 场景 | 建议 |
|------|------|
| 数据量 < 单机内存，写 QPS 不高 | **不要上集群**，主从 + 哨兵够用，运维简单得多 |
| 数据量超过单机内存 | 必须分片，用集群或客户端分片 |
| 写 QPS 打满单主库 | 用集群分摊写入 |
| 强依赖跨 key 事务，且无法用哈希标签改造 | 慎用集群，考虑业务侧拆分 |
| 需要多数据库（SELECT） | **不能用集群**（集群只有 db 0） |

---

## 小测（5 题）

### Q1

关于 Redis Cluster 的 16384 个哈希槽，下列说法正确的是？

A. 槽数会随集群节点数变化，加节点时自动从 16384 改成更大值
B. 选定 16384 主要是为了让心跳包中的槽位图控制在 2 KB，避免 IP 分片
C. CRC16 产生 16 位输出，所以槽数必须是 65536 才能避免哈希冲突
D. 每个主节点必须持有连续编号的槽区间

<details>
<summary>答案</summary>

**B**

A 错误：槽数固定 16384，永远不变。变化的只是"槽分配给哪个节点"。这正是能在线扩缩容的原因。

B 正确：节点间 gossip 心跳携带槽位图，16384 bit = 2 KB 可塞进一个以太网帧；若用 65536 bit 则需要 8 KB，会造成 IP 分片。作者 antirez 在 GitHub issue #2576 中说明，另一考虑是集群设计上限约 1000 个主节点，16384 个槽平均每节点 16 个，粒度足够。

C 错误：槽数 16384 = 2¹⁴，只用 CRC16 输出的**低 14 位**（`CRC16(key) & 16383`）。高 2 位被丢弃，这是有意为之的取舍。

D 错误：槽区间**不要求连续**。实测中 reshard 后节点 7007 持有 `0-332 5461-5794 10923-11255` 三段不连续的槽，这是正常状态。
</details>

### Q2

以下哪个 key 与 `user:{1001}:profile` **不**落在同一个槽？

A. `user:{1001}:orders`
B. `user:{1001}:{orders}`
C. `{user:1001}:orders`
D. `user:1001:{1001}`

<details>
<summary>答案</summary>

**C**

哈希标签规则：取第一个 `{` 与其后第一个 `}` 之间的内容参与 CRC16；若这对括号不存在、为空或中间无字符，则整个 key 参与计算。

`user:{1001}:profile` → 取 `1001`（实测槽 15391）

- A `user:{1001}:orders` → 取 `1001` → 同槽
- B `user:{1001}:{orders}` → **只取第一对** `{}`，仍是 `1001`，后面的 `{orders}` 被忽略 → 同槽
- C `{user:1001}:orders` → 取 `user:1001` → 与 `1001` 不同 → **槽不同** ✅
- D `user:1001:{1001}` → 取 `1001` → 同槽

**关键要点**：只有**第一对非空** `{}` 生效。这也是 B 选项的考点——很多人会以为有两对括号就要特殊处理，其实第二对完全被忽略。

**另一条易错规则**：`{}` 里为空（如 `user:{}:x`）或没有闭合（如 `abc{`）时，标签**不生效**，整个 key 参与计算。
</details>

### Q3

客户端收到 `ASK 3999 127.0.0.1:7002` 后，正确的处理方式是？

A. 更新本地槽映射表，把槽 3999 指向 7002，之后该槽的请求都发往 7002
B. 向 7002 发送 `ASKING`，然后重发这条命令；本地槽映射表保持不变
C. 直接向 7002 重发这条命令，不需要 `ASKING`
D. 忽略该响应，继续向原节点重试

<details>
<summary>答案</summary>

**B**

ASK 是**迁移中间态**的一次性重定向。

- **不更新映射表**：迁移未完成，槽里还有一部分 key 留在源节点。若把槽 3999 映射到 7002，访问尚未迁走的 key 就会被路由到错误位置。
- **必须先发 `ASKING`**：目标节点在 IMPORTING 状态下会拒绝关于该槽的普通请求（返回 MOVED 指回源节点）。`ASKING` 设置一次性标志，让目标节点接受这条命令。这是保护机制，防止路由表损坏的客户端把还没迁完的 key 写进目标节点造成双份数据。

A 错误：这是 MOVED 的处理方式。把 ASK 当 MOVED 处理是经典的客户端 bug。

C 错误：不发 `ASKING` 会被目标节点用 MOVED 指回源节点。

D 错误：忽略重定向会导致该 key 一直读不到。

**（MOVED 的处理才是 A）**：MOVED 表示槽已永久易主，应更新映射表并直连新节点。
</details>

### Q4

在 Redis Cluster 中执行以下脚本，结果是？

```
EVAL "return redis.call('GET', KEYS[1])" 1 "{u1}:profile"
```

假设 `{u1}:profile` 的槽归属节点 B，客户端连的是节点 A。

A. 返回 `(error) CROSSSLOT`
B. 返回节点 A 上 `{u1}:profile` 的值（可能不是最新的）
C. 客户端路由到节点 B 执行，返回正确值
D. 返回 `(error) ERR Script attempted to access a non local key`

<details>
<summary>答案</summary>

**C**

脚本正确地把 key 声明在 `KEYS[]` 中，Redis 会根据该 key 的槽把脚本**路由到正确的节点（B）**执行，返回正确值。

这是集群客户端的标准行为——无论初始连到哪个节点，只要声明了 KEYS，就会被路由到槽的归属节点。

- A 错误：`CROSSSLOT` 只在多个 key 跨槽时出现。这里只有一个 key。
- B 错误：不会读到本地脏数据。正确声明 KEYS 时会路由到归属节点。
- D 错误：这个报错出现在**脚本内访问了非本节点负责的 key** 时（例如 `numkeys=0` 却在脚本里硬编码 key）。正确声明 KEYS 不会触发。

**对照**：如果写成 `EVAL "return redis.call('GET','{u1}:profile')" 0`（numkeys=0 + 硬编码），则脚本会发到你连上的节点 A，此时会返回 D 的错误——除非 A 恰好是该槽的归属节点，那就会"碰巧成功"。这正是本课强调"所有 key 必须写进 `KEYS[]`"的原因。
</details>

### Q5

关于 Redis Cluster 的限制，下列说法**错误**的是？

A. 集群只支持 db 0，`SELECT` 命令被禁用
B. `FLUSHALL` 在集群下只清空当前连接的节点
C. 用哈希标签可以让 `SINTER` 这类多 key 命令正常工作
D. `EVALSHA` 的脚本缓存在集群所有节点间自动同步

<details>
<summary>答案</summary>

**D**

D 错误：`SCRIPT LOAD` 只在**当前节点**缓存脚本。实测：

```
SCRIPT LOAD 返回 SHA = d3c21d0c2b9ca22f82737626a27bcaf5d288f99f
在 7001 上 SCRIPT EXISTS: 1
在 7002 上 SCRIPT EXISTS: 0     ← 没有
在 7003 上 SCRIPT EXISTS: 0     ← 没有
```

所以在没缓存的节点执行 `EVALSHA` 会得到 `NOSCRIPT No matching script. Please use EVAL.`。应对方式是捕获 `NOSCRIPT` 后重新 `SCRIPT LOAD` 再重试（成熟客户端库已内置），或改用 `EVAL` 传完整脚本。Redis 7+ 的 `FUNCTION LOAD` 支持跨节点自动传播。

A 正确：实测 `SELECT 1` 返回 `ERR SELECT is not allowed in cluster mode`。

B 正确：实测 flushall 7001 后，7002/7003 的数据仍在。集群清库要逐节点执行或用 `redis-cli --cluster call`。

C 正确：哈希标签让多个 key 落进同一槽，同槽即可执行 SINTER / MGET / 事务等。实测 `SINTER {set}:a {set}:b` 正常返回。
</details>

---

## 🚀 下一批接力提示词

复制以下内容发给 AI 即可继续下一课：

```
继续学 Redis。我的学习档案在 redis/00-学习档案.md，
刚学完阶段 4《分布式与生产实践》的课 7《分片与集群》知识点「哈希槽与 CRC16、集群伸缩与重定向、集群下的多 key 与 Lua 限制」，
请按大纲继续讲解阶段 4 的课 8《缓存设计》的知识点：穿透 / 击穿 / 雪崩、缓存与数据库一致性、内存淘汰与过期策略。
```

---

## 🧭 课程导航

- **上一课**：[课 6：主从复制与哨兵](../3-持久化与高可用/lessons/lesson-06-主从复制与哨兵.md)
- **下一课**：课 8：缓存设计（待编写）
- **返回**：[课程目录](../../../02-课程目录.md) ｜ [学习档案](../../../00-学习档案.md)
