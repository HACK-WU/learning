# 课 6：主从复制与哨兵

> 阶段 3《持久化与高可用》第 2 课
> 前置：课 5《RDB 与 AOF 持久化》(RDB fork 与写时复制、AOF 刷盘策略、持久化选型)
> 环境：WSL Ubuntu 24.04 + Redis 8.10.1（本机实测，核查于 2026-09）

---

## 本课要解决的三个问题

课 5 解决了"进程重启后数据还在"。但有一类问题它无能为力：

**如果整台机器挂了呢？**

持久化把数据写在**本机磁盘**上。机器宕机、磁盘损坏、机房断电——这些情况下，数据再怎么持久化也读不出来，因为**能读它的进程和机器都一起没了**。

本课要回答三个问题：

1. **怎么让数据在另一台机器上也有？** —— 主从复制，全量与增量两种同步方式
2. **主库挂了谁来接管？** —— 哨兵自动故障转移
3. **有了哨兵就能高枕无忧吗？** —— 哨兵解决不了的丢数据

---

## 第一幕：场景引入 —— 三个真实困境

### 困境一：主库宕机，服务中断两小时

凌晨，Redis 主库所在机器硬件故障。运维被叫醒，手动登录备用机，执行 `REPLICAOF NO ONE` 提升为主库，再修改所有应用的配置文件指向新地址，逐个重启应用。

从故障到恢复，**两小时**。

问题不在于数据丢了（课 5 的持久化保证了这点），而在于——**切换是人做的**。人需要被叫醒、需要登录、需要改配置、需要重启。

### 困境二：每个从库上线，主库内存就飙升一次

你给主库挂了 5 个从库做读写分离。某次批量上线后，主库内存告警，然后被 OOM 杀掉。

为什么？因为**每个从库首次连接都要触发一次全量复制，主库就要 fork 一次**，每次 fork 都伴随课 5 讲的 COW 内存放大。

如果 5 个从库**恰好同时**上线，Redis 会让它们共享一次 fork（本课 1.3 节会讲）。但如果它们**陆续**上线——间隔超过了主库的等待窗口——就是 5 次独立的 fork、5 份 COW 内存峰值。

这正是课 5 讲的 COW 机制——它在复制场景同样会发生，而且**比持久化场景更频繁**：从库重启、网络抖动导致 backlog 撑爆，都会触发一次全量复制。

### 困境三：故障转移后，用户刚下的订单不见了

哨兵正常工作，主库挂掉后 8 秒完成切换，服务恢复。但客服收到投诉：**用户在故障前几秒刚支付的订单，查不到了**。

你查日志确认：支付成功的响应确实返回给了用户。但新主库上没有这条数据。

为什么？因为**复制是异步的**——主库返回 OK 时，数据还没到从库。这是哨兵架构的固有缺陷，本课第三幕会详细解释。

---

## 第二幕：认知冲突 —— 三个"想当然"的崩塌

### 冲突一：Redis 8 的复制默认不落盘了

你可能学过"全量复制时主库执行 BGSAVE 生成 RDB 文件，再发给从库"。

**这在 Redis 8 已经不是默认行为了。**

本机实测（Redis 8.10.1）：

```
repl-diskless-sync: yes          ← 默认开启无盘复制
repl-diskless-sync-delay: 5      ← 默认等待 5 秒
```

主库日志证实了这一点：

```
* Starting BGSAVE for SYNC with target: replicas sockets (rdb-channel)
* Background RDB transfer started by pid 2562416 to replica socket
```

注意关键词是 **`replicas sockets`**——RDB 数据直接通过 socket 流式发给从库，**不落主库磁盘**。

为什么改？因为落盘要多一次磁盘 I/O，而从库往往只需要数据本身。无盘复制省掉了这一跳。

> 📌 **这个改动带来的副作用**：`repl-diskless-sync-delay` 默认 5 秒。主库会**故意等 5 秒**，看是否有更多从库同时来同步，好让它们共享同一份 RDB。
>
> 我在这上面踩了个坑：备课初期所有同步测试都"失败"——从库 dbsize 一直是 0。原因是我在发起 `REPLICAOF` 后只等了 3 秒，**同步还没开始**。日志里那句 `Delay next BGSAVE for diskless SYNC` 到 `Starting BGSAVE` 之间，恰好就是 5 秒。
>
> 实测把 delay 设为 0 后，同步耗时从 5+ 秒降到 **0.21 秒**。

### 冲突二："断线重连会自动增量同步"——不一定

你可能听说"从库断线重连后，只同步缺失的部分"。这句话**有条件**。

主库维护一个**环形缓冲区**（replication backlog），只保留最近写入的一定字节。从库重连时报上自己的 offset：

- offset **还在** backlog 范围内 → 增量同步（partial resync）✅
- offset **已被挤出** backlog → 全量同步（full resync）❌

本机实测 backlog 的环形特性（设为 1 MB）：

| 阶段 | master_repl_offset | backlog_histlen | 说明 |
|------|-------------------|-----------------|------|
| 初始 | 0 | 0 | 空 |
| 写入 5000 条 | 1,168,916 | 1,066,716 | 接近满 |
| 再写 2 万条 | 5,857,810 | 1,054,410 | **已满，不再增长** |
| 再写 5 万条 | 32,596,704 | 1,057,784 | **稳定在上限** |

**关键观察**：`master_repl_offset` 涨到 3200 万，但 `backlog_histlen` 始终卡在 ~1 MB。这就是"环形"的含义——写满后覆盖最旧的数据。

两者的差值，就是**已经挤出 backlog、无法再增量同步的字节数**。

**1 MB 的默认 backlog 能撑多久？**（本机实测 SET 吞吐 204,081 ops/s，按每条 100 字节估算）

| backlog 大小 | 满载写入下的耗尽时间 |
|-------------|-------------------|
| 1 MB（默认） | **0.05 秒** |
| 16 MB | 0.82 秒 |
| 64 MB | 3.29 秒 |
| 256 MB | 13.15 秒 |

**默认配置在高写入场景下只能容忍 50 毫秒的断线**。网络和 GC 抖动轻易就能超过这个数。

### 冲突三：从库默认只读，而且这个设计是有意的

从库写入会报错：

```
READONLY You can't write against a read only replica.
```

`replica-read-only` 默认 `yes`。

为什么不让写？因为**从库上的本地写入不会同步回主库**。一旦主库有新数据推过来，或者从库重新全量同步，这些本地写入就会被**静默丢弃**。

只读是一个保护机制——它用明确的报错，替你避免了"数据写进去了但随时会消失"的更糟情况。

---

## 第三幕：层层揭示 —— 三个知识点

## 知识点 1：全量与增量复制

### 1.1 主从复制的基本形态

```
        ┌─────────────┐
        │   主库       │  ← 所有写操作
        │  (master)   │
        └──────┬──────┘
               │ 复制流（单向）
       ┌───────┼───────┐
       ▼       ▼       ▼
   ┌───────┐┌───────┐┌───────┐
   │从库   ││从库   ││从库   │  ← 只读，可分担读
   │(slave)││(slave)││(slave)│
   └───────┘└───────┘└───────┘
```

建立方式（两种等价）：

```bash
# 运行时
redis-cli -p 6402 REPLICAOF 127.0.0.1 6401

# 配置文件
replicaof 127.0.0.1 6401
```

> 📌 Redis 5.0 之前命令叫 `SLAVEOF`，现在 `REPLICAOF` 是标准写法，两者仍兼容。

查看状态：

```bash
redis-cli -p 6401 info replication | grep connected_slaves
# connected_slaves:2

redis-cli -p 6402 info replication | grep -E "role:|master_link_status:"
# role:slave
# master_link_status:up
```

### 1.2 全量复制：完整流程

从库首次连接主库时，必然触发全量复制。三个阶段：

```
阶段 1：主库 BGSAVE
  ├─ 主库 fork 子进程生成 RDB
  ├─ ⚠️ fork 瞬间主线程阻塞（课 5 讲过）
  ├─ ⚠️ 期间写入触发 COW，内存可能翻倍
  └─ Redis 8 默认无盘：RDB 直接写 socket，不落主库磁盘

阶段 2：传输 RDB
  └─ 主库把 RDB 流式发给从库

阶段 3：从库加载 + 追增量
  ├─ 从库清空自己的旧数据（Flushing old data）
  ├─ 加载 RDB 到内存（Loading DB in memory）
  └─ 主库把「阶段 1~3 期间的新写入」补发给从库
```

本机实测的从库日志，完整对应了三个阶段：

```
* MASTER <-> REPLICA sync: receiving streamed RDB from master with EOF to disk
* MASTER <-> REPLICA sync: Loading DB in memory
* MASTER <-> REPLICA sync: Flushing old data
* Done loading RDB, keys loaded: 1001, keys expired: 0.
* MASTER <-> REPLICA sync: Finished with success
```

**阶段 3 是关键**：为什么需要"补发"？因为阶段 1 的 BGSAVE 耗时几秒到几十秒，期间主库仍在接受写入。这些新写入不能丢，所以主库会把它们缓存在**复制客户端缓冲区**里，等从库加载完 RDB 再补发。

### 1.3 复制风暴：多个从库同时全量

如果多个从库同时首次连接，主库会不会 fork 多次？

**不会**——这正是 `repl-diskless-sync-delay` 存在的原因。主库收到第一个从库的同步请求后，会**故意等待**（默认 5 秒），攒够一批从库，然后**只 fork 一次**，把同一份 RDB 流式发给所有等待中的从库。

本机实测（同时挂 3 个从库）：

```
主库 latest_fork_usec: 701 us
BGSAVE for SYNC 次数: 2
```

3 个从库只触发了 2 次 BGSAVE（第一次是单个从库，第二次是三个一起）。

**反面情况**：如果 `delay` 设为 0，每个从库都会触发独立的一次 fork，3 个从库就是 3 次 fork、3 份 COW 开销。

> 💡 生产建议：批量上线从库时保持默认 delay（5 秒），让它们共享一次 fork。单个从库临时重连时可以临时调小。

### 1.4 增量复制：backlog 机制

全量复制很贵（fork + COW + 网络传输全量数据）。短暂停顿后就全量一次，代价太大。所以 Redis 设计了增量复制。

核心是三个概念：

| 概念 | 含义 |
|------|------|
| `master_replid` | 主库身份标识（40 字节随机串） |
| `master_repl_offset` | 主库复制流的**全局字节偏移**，单调递增 |
| `replication backlog` | 主库维护的**环形缓冲**，缓存最近的复制流 |

从库定期（默认每秒）向主库上报自己的 `slave_repl_offset`。主库据此判断：

```
从库重连，带上 (replid, offset)
  │
  ├─ replid 不匹配            → 全量复制
  │   （说明主库换过，数据流不可续接）
  │
  ├─ replid 匹配，但 offset
  │   已不在 backlog 范围内   → 全量复制
  │   （缺失的数据已被覆盖）
  │
  └─ replid 匹配，offset 在
      backlog 范围内          → 增量复制 ✅
      从库日志：Successful partial resynchronization with master.
```

### 1.5 增量复制实测：怎么正确测

这一节的**测试方法**本身值得单独讲，因为我踩了两次坑。

**失败方法一：用 `REPLICAOF NO ONE` 模拟断线**

我最初的做法：从库执行 `replicaof no one` 脱离，主库写入，然后 `replicaof` 重连。结果：**无论写入多少，永远走全量复制**，即使只写了 100 条。

从库日志说明了原因：

```
* Discarding previously cached master state.
```

执行 `no one` 后，从库**丢弃了缓存的主库状态**（replid + offset）。重新 `replicaof` 时它无法提供有效的断点信息，PSYNC 只能失败走全量。

> 📌 补充一个实测发现：我原本猜测 `replicaof no one` 会让主库更换 replid，但本机实测（Redis 8.10.1）**主库的 `master_replid` 并未改变**。真正失效的是**从库侧缓存的状态**，不是主库的身份标识。这个细节不影响结论，但能帮你理解机制。

**失败方法二：用 `DEBUG SLEEP` 阻塞从库**

从库被冻结期间无法处理命令，但恢复后直接追平了，没触发重新同步——因为**连接没断**，数据都堆积在内核 socket 缓冲区里。

**成功方法：在主库上 `CLIENT KILL` 掉从库连接**

这才是真实网络中断的等价操作。实测结果：

| 场景 | 结果 |
|------|------|
| 断线期间写 100 条 | ✅ 增量复制 |
| 断线期间写 5000 条 | ✅ 增量复制 |
| 断线期间写 10 万条 | ✅ 增量复制 |

三个都成功了——因为**本机回环网络重连太快（毫秒级）**，从库在被 kill 后立刻重连，主库根本来不及把 backlog 撑爆。

> ⚠️ **如实说明**：本机环境无法测出"backlog 被撑爆导致全量复制"的临界点。这是 WSL 回环网络的固有限制（延迟 < 1ms），真实生产网络的断线是秒级以上。
> 我改用**机制性观测**（第二幕冲突二的 backlog 环形缓冲数据）来证明这个行为：histlen 卡在上限不动，而 offset 持续增长到 3200 万——这个差值就是理论上的"已丢失可增量范围"。
> 完整脚本见 `playground/prep-lesson-06-backlog.sh` 和 `prep-lesson-06-partial4.sh`。

### 1.6 backlog 调优

```conf
# 默认 1 MB，高写入场景必须调大
repl-backlog-size 64mb

# 最后一个从库断开后，backlog 保留多久（默认 3600 秒）
repl-backlog-ttl 3600
```

**怎么估算合适的 backlog？**

```
backlog_size ≈ 平均写入速率(bytes/s) × 你能接受的最长断线时间(s)
```

举例：峰值写入 5 MB/s，希望容忍 30 秒断线 → backlog 至少 150 MB。

对照前面那张表：默认 1 MB 在满载写入下只够 0.05 秒。**这是生产环境最常见的"频繁全量同步"根因**。

### 1.7 无盘复制的取舍

```conf
repl-diskless-sync yes          # Redis 8 默认 yes
repl-diskless-sync-delay 5      # 攒从库的等待时间
repl-diskless-sync-max-replicas 0   # 0 = 不限制
```

| 维度 | 无盘（默认） | 落盘 |
|------|------------|------|
| 磁盘 I/O | 省掉一次写盘 | 需要写 RDB 文件 |
| 内存 | RDB 在内存中流式发送 | 同样 fork，但可边写边发 |
| 多从库共享 | 好（delay 期间来的都能共享） | 也好 |
| 慢从库影响 | 差（socket 缓冲占用内存） | 好（文件可慢慢读） |

**什么时候该关掉无盘？** 从库网络很慢时。因为无盘模式下，RDB 要一直存在 socket 缓冲区里等慢从库读完，占用主库内存。

### 1.8 完整脚本

> 📌 `playground/prep-lesson-06-replica-basic.sh`（拓扑搭建与只读验证）、`prep-lesson-06-sync.sh`（全量流程）、`prep-lesson-06-backlog.sh`（backlog 环形特性与调优量化）、`prep-lesson-06-partial4.sh`（增量复制验证）。

```bash
bash playground/prep-lesson-06-replica-basic.sh
bash playground/prep-lesson-06-backlog.sh
```

---

## 知识点 2：哨兵故障转移

### 2.1 哨兵是什么

哨兵（Sentinel）是**独立的进程**，不存数据、不做代理，只做三件事：

1. **监控**：持续检查主从库是否存活
2. **通知**：故障时通知管理员或其他程序
3. **自动故障转移**：主库挂了，选一个从库提升为新主库

```
┌──────────┐ ┌──────────┐ ┌──────────┐
│ 哨兵 1   │ │ 哨兵 2   │ │ 哨兵 3   │  ← 独立进程，互相通信
└────┬─────┘ └────┬─────┘ └────┬─────┘
     └────────────┼────────────┘
                  │ 监控
        ┌─────────┴─────────┐
        ▼                   ▼
   ┌─────────┐         ┌─────────┐
   │  主库   │────────▶│  从库   │
   └─────────┘  复制   └─────────┘
```

> 📌 **启动方式**：本机 Redis 8.10.1 的安装**没有 `redis-sentinel` 命令**（`which redis-sentinel` 返回空）。要用：
> ```bash
> redis-server /path/to/sentinel.conf --sentinel
> ```
> 启动时日志会显示 `Running mode=sentinel`，可据此确认。

### 2.2 哨兵配置

```conf
# sentinel.conf
port 26401
daemonize yes
dir /var/lib/redis-sentinel
logfile /var/log/redis/sentinel.log

# 核心：监控名为 mymaster 的主库，quorum=2
sentinel monitor mymaster 127.0.0.1 6401 2

# 5 秒无响应判为主观下线
sentinel down-after-milliseconds mymaster 5000

# 故障转移超时
sentinel failover-timeout mymaster 10000

# 转移后，同时向新主库发起全量同步的从库数量
sentinel parallel-syncs mymaster 1
```

**为什么至少要 3 个哨兵？**

`quorum=2` 意味着至少 2 个哨兵同意才能判定主库客观下线。如果只有 2 个哨兵，其中 1 个挂了，剩下 1 个永远凑不齐 2 票——**无法完成故障转移**。

3 个哨兵能容忍 1 个故障，5 个能容忍 2 个。**奇数个是标准做法**。

### 2.3 哨兵怎么发现彼此

哨兵不需要互相配置地址。它们通过主库的 **Pub/Sub 频道**自动发现：

```
__sentinel__:hello
```

每个哨兵每秒向主库的这个频道广播自己的 IP、端口、runid。其他哨兵订阅该频道，就能发现新伙伴。

本机实测确认该频道存在：

```bash
redis-cli -p 6401 pubsub channels
# __sentinel__:hello
```

哨兵视角能看到伙伴数量：

```bash
redis-cli -p 26401 sentinel master mymaster | paste - - | grep num-other-sentinels
# num-other-sentinels	2
```

### 2.4 故障转移的完整流程

两个阶段的判定：

| 阶段 | 名称 | 判定条件 |
|------|------|---------|
| 1 | **主观下线（SDOWN）** | 单个哨兵在 `down-after-milliseconds` 内收不到主库有效响应 |
| 2 | **客观下线（ODOWN）** | 达到 `quorum` 数量的哨兵都认为主库下线 |

之后：

```
1. 哨兵们通过 Raft 式投票，选出一个「领头哨兵」
2. 领头哨兵从从库中挑一个最优的，执行 REPLICAOF NO ONE 提升为主库
3. 其他从库改为复制新主库
4. 旧主库恢复后被降级为新主库的从库
5. 哨兵持续监控新拓扑
```

**从库选择优先级**（领头哨兵的决策依据）：

1. 排除已下线、断线的从库
2. 按 `replica-priority` 配置（默认 100，越小越优先；设为 0 表示永不参与选举）
3. 优先级相同则选 **offset 最大**的（数据最新）
4. 再相同则选 runid 最小的

### 2.5 故障转移实测

本机实测（1 主 + 2 从 + 3 哨兵，down-after=5000ms，quorum=2）：

```
转移前主库: 127.0.0.1:6401
kill -9 主库 (pid=2580518)
    t=0.0s  主库仍为 127.0.0.1:6401
    t=1.0s  主库仍为 127.0.0.1:6401
    t=2.0s  主库仍为 127.0.0.1:6401
    t=3.0s  主库仍为 127.0.0.1:6401
    t=4.0s  主库仍为 127.0.0.1:6401
    t=5.0s  主库仍为 127.0.0.1:6401
    t=6.0s  主库仍为 127.0.0.1:6401
    t=7.1s  ✅ 新主库 = 127.0.0.1:6402

⏱️  故障转移总耗时: 7.06 秒
```

**耗时构成**：约 5 秒是 `down-after-milliseconds` 的等待（判定主观下线），剩余约 2 秒是客观下线确认 + 领头选举 + 提升切换。

哨兵日志完整记录了事件链：

```
# +sdown master mymaster 127.0.0.1 6401              ← 主观下线
# +vote-for-leader 61c0774257b847120fa246011a25aed31ff0e07c 1   ← 投票选领头
# +odown master mymaster 127.0.0.1 6401 #quorum 3/2  ← 客观下线（3票/需要2票）
# +switch-master mymaster 127.0.0.1 6401 127.0.0.1 6402   ← 完成切换
```

转移后状态验证：

```
新主库 6402: role=master, dbsize=10000, connected_slaves=1
6403: role=slave, master_port=6402, dbsize=10000
```

**数据完整**（dbsize 保持 10000），**拓扑自动重配**（6403 自动指向 6402）。

> 📌 结论：**故障转移耗时 ≈ down-after-milliseconds + 2~3 秒**。想让切换更快，就调小 `down-after-milliseconds`——但太小会因网络抖动误判（本节末会讲）。
> 完整脚本见 `playground/prep-lesson-06-sentinel2.sh`。

### 2.6 down-after-milliseconds 的取舍

```conf
sentinel down-after-milliseconds mymaster 5000   # 文档默认值是 30000（30 秒）
```

**设得太小**：网络抖动就误判下线，触发不必要的切换。切换本身也有代价——从库要重新全量同步，期间主库 fork + COW。

**设得太大**：真故障时发现慢，服务中断时间长。

**经验值**：5~10 秒。文档默认 30 秒，生产上通常调小到 5~10 秒。

### 2.7 客户端怎么连

**关键点：客户端不通过哨兵读写数据。**

```
1. 客户端启动时，问哨兵「mymaster 当前主库在哪」
2. 哨兵返回地址，客户端直连主库读写
3. 故障转移时，客户端通过订阅 +switch-master 事件感知变化，重连新主库
```

这要求使用**支持哨兵的客户端库**（JedisSentinelPool、Lettuce、Redisson 等），并配置**多个哨兵地址**和 masterName。

**最常见的坑**：应用配置里硬编码了主库 IP。故障转移后，哨兵切了，但应用还在连旧地址。

### 2.8 完整脚本

> 📌 `playground/prep-lesson-06-sentinel2.sh`（完整故障转移实测，含日志事件链）。

```bash
bash playground/prep-lesson-06-sentinel2.sh
```

---

## 知识点 3：哨兵解决不了的丢数据

### 3.1 核心问题：复制是异步的

这是本课最重要的一句话：

> **主库返回 OK，不代表数据已经到从库。**

异步复制的完整时序：

```
客户端                主库                    从库
  │                   │                       │
  ├─ SET order paid ─▶│                       │
  │                   ├─ 写入内存             │
  │◀──── OK ──────────┤                       │
  │   （已确认！）     │                       │
  │                   ├──── 异步发送 ────────▶│
  │                   │                       ├─ 写入内存
  │                   │◀─── ACK(offset) ──────┤
```

如果在"返回 OK"和"到达从库"之间主库挂了——**这条已确认的写入永久丢失**。

哨兵会把从库提升为新主库，但新主库从未收到过这条数据。

### 3.2 为什么 Redis 选择异步

因为**同步复制的代价太高**：

| 模式 | 延迟 | 数据安全性 |
|------|------|-----------|
| 异步（默认） | 只有主库处理时间 | 故障时可能丢 |
| 同步 | 主库 + 最慢从库的往返 | 不丢 |

Redis 的核心卖点是快。同步复制会把从库的网络延迟加到每条写命令上——从库跨机房时，这个延迟可能是几十毫秒。

**这是一个明确的取舍：Redis 选择用极低延迟换"极小概率丢少量数据"。**

### 3.3 三种丢数据场景

**场景一：主库宕机（最常见）**

主库写入后返回 OK，还没来得及发给从库就挂了。新主库缺少这部分数据。

**场景二：脑裂（split-brain）**

```
      ┌── 网络分区 ──┐
      │              │
   主库 A         哨兵们 + 从库 B
      │              │
   继续接受写入     判定 A 下线，提升 B 为新主
      │              │
   写入 X=1          B 接受写入 X=2
      │              │
      └── 网络恢复 ──┘
              │
      A 被降级为 B 的从库
      ↓
   A 分区期间的所有写入（X=1）被清空
```

**这是最危险的场景**：客户端以为写成功了（主库 A 返回了 OK），但数据最终被丢弃。

**场景三：从库被提升后，旧主库恢复**

旧主库上有一些从库没有的数据。它被降级为从库时，会执行一次全量同步，**清空自己的数据重新加载**——那些数据就没了。

### 3.4 缓解手段一：min-replicas-to-write

让主库在"从库不够"时**主动拒绝写入**。

本机实测：

```bash
# 默认值（保护是关闭的）
min-replicas-to-write = 0
min-replicas-max-lag  = 3

# 开启保护
config set min-replicas-to-write 1
config set min-replicas-max-lag 3

# 从库在线时
127.0.0.1:6401> SET safe:test 1
OK

# 停掉从库后
127.0.0.1:6401> SET unsafe:test 1
(error) NOREPLICAS Not enough good replicas to write.
```

**主库主动拒绝写入**，而不是让数据冒险。

| 参数 | 含义 | 默认 |
|------|------|------|
| `min-replicas-to-write` | 至少要有 N 个健康从库才接受写入 | **0（关闭）** |
| `min-replicas-max-lag` | 从库 ACK 延迟超过 N 秒就不算健康 | **3** |

> 📌 注意：`min-replicas-max-lag` 默认是 **3 秒**（不是 0）。但只有 `min-replicas-to-write > 0` 时它才生效。

**代价**：从库全挂时，整个 Redis **完全不可写**。这是典型的**可用性换一致性**。

### 3.5 缓解手段二：WAIT 命令

让客户端**显式等待**复制完成。

```bash
SET order:1001 paid
WAIT 1 1000      # 等至少 1 个从库确认，最多等 1000 毫秒
```

本机实测：

```
普通 SET:       OK    <- 命令返回即视为完成
SET 后 WAIT 1 0: 1 个从库确认
```

`WAIT` 返回**实际确认的从库数量**，客户端应该检查返回值是否达到要求：

- 返回值 >= 要求 → 数据已到 N 个从库
- 返回值 < 要求 → 超时了，仍有丢失风险

### 3.6 WAIT 的局限性（重要）

**`WAIT` 不能让 Redis 变成强一致系统。** 这是 Redis 官方文档的明确说法（核查于 2026-09）：

> *Note that WAIT does not make Redis a strongly consistent store... However this is just a best-effort attempt so it is possible to still lose a write synchronously replicated to multiple replicas.*

原因有两个：

1. **WAIT 只保证"从库收到了"，不保证"从库持久化了"**。从库收到后还在内存里，从库自己宕机同样会丢。
2. **故障转移时，哨兵只是"尽力"挑一个最优从库**，不保证挑中的就是收到最新数据的那个。

同理，`min-replicas` 也只是**收窄风险窗口**，不是逐条写入的法定人数确认（官方文档：*bound risk rather than prove a per-write quorum commit*）。

### 3.7 三个手段的对比

| 维度 | `min-replicas-to-write` | `WAIT` 命令 | 什么都不做（默认） |
|------|------------------------|------------|------------------|
| 作用层 | 服务端（主库配置） | 客户端（每次调用） | - |
| 触发 | 从库不足时拒绝写入 | 阻塞等待 N 个从库确认 | - |
| 粒度 | 全局，一刀切 | 可精确到每条命令 | - |
| 失败表现 | 返回 `NOREPLICAS` 错误 | 超时返回实际确认数 | 静默接受 |
| 代价 | 从库全挂时完全不可写 | 每条命令增加一次往返延迟 | 可能丢数据 |
| 保证强度 | 收窄风险窗口 | 收窄风险窗口 | 无 |

### 3.8 选型建议

```
先问：这份数据丢了会怎样？
│
├─ 丢了无所谓（缓存）
│   └─ ✅ 保持默认（异步复制，最快）
│       不需要 min-replicas，不需要 WAIT
│
├─ 丢了要紧，但可接受极小概率
│   └─ ✅ min-replicas-to-write 1 + min-replicas-max-lag 10
│       防止「从库全挂还继续写」这种最糟情况
│       代价可控（只在从库故障时不可用）
│
├─ 关键数据，必须尽力保住
│   └─ ✅ 在关键写入后加 WAIT
│       例如：SET order:1001 paid; WAIT 1 1000
│       只给关键操作加，不要全量加（延迟代价大）
│
└─ 要求零丢失、强一致
    └─ ❌ Redis 主从 + 哨兵做不到
       考虑其他方案（如关系型数据库、分布式共识系统）
       或者接受「应用层做补偿」
```

### 3.9 哨兵能解决什么，不能解决什么

| 能力 | 哨兵是否提供 |
|------|------------|
| 机器宕机后服务自动恢复 | ✅ 提供（7 秒左右完成切换） |
| 数据冗余（多台机器有副本） | ✅ 提供（主从复制） |
| 读扩展（从库分担读） | ✅ 提供 |
| **保证已确认写入不丢失** | ❌ **不提供** |
| **脑裂时数据不冲突** | ❌ **不提供** |
| 写扩展（分担写压力） | ❌ 不提供（所有写仍走主库） |
| 数据分片（突破单机内存） | ❌ 不提供（那是 Redis Cluster，课 7） |

**一句话总结**：哨兵解决的是**可用性（Availability）**，不是**一致性（Consistency）**。

### 3.10 完整脚本

> 📌 `playground/prep-lesson-06-guard.sh`（min-replicas 与 WAIT 验证）、`prep-lesson-06-loss3.sh`（SIGSTOP 模拟断线的尝试与本机关限说明）。

---

## 第四幕：实操验证 —— 跟着做一遍

### 实验 1：搭建一主两从，观察全量复制

```bash
bash playground/prep-lesson-06-replica-basic.sh
```

重点观察：
- 从库的 `master_link_status` 从 `down` 变 `up`
- 从库写入被拒绝：`READONLY You can't write against a read only replica.`
- 主库日志里的 `Starting BGSAVE for SYNC with target: replicas sockets`（无盘复制）

### 实验 2：亲眼看 backlog 被写满

```bash
bash playground/prep-lesson-06-backlog.sh
```

重点观察这个表：`histlen` 卡在 1 MB 不动，而 `master_offset` 涨到 3200 万。

```bash
# 手动观察
redis-cli -p 6401 info replication | grep -E "master_repl_offset|repl_backlog_histlen"
```

### 实验 3：完整故障转移

```bash
bash playground/prep-lesson-06-sentinel2.sh
```

重点观察：
- 耗时约 7 秒（5 秒 down-after + 2 秒切换）
- 哨兵日志的四个事件：`+sdown` → `+vote-for-leader` → `+odown #quorum 3/2` → `+switch-master`
- 转移后从库自动指向新主库

> 💡 本机没有 `redis-sentinel` 命令，脚本里用的是 `redis-server <conf> --sentinel`。

### 实验 4：验证 min-replicas 的保护

```bash
bash playground/prep-lesson-06-guard.sh
```

重点观察停掉从库后的 `NOREPLICAS` 错误：

```bash
redis-cli -p 6401 config set min-replicas-to-write 1
redis-cli -p 6402 shutdown nosave
redis-cli -p 6401 set test 1
# (error) NOREPLICAS Not enough good replicas to write.
```

---

## 第五幕：体系收束 —— 本课与前后课的联系

### 与课 5 的联系：COW 在复制场景复现

课 5 讲的 fork + 写时复制，在本课**完整复现了一次**：

| 场景 | 课 5（持久化） | 课 6（复制） |
|------|--------------|------------|
| 触发 | `BGSAVE` / AOF 重写 | 从库全量同步 |
| fork 阻塞 | ✅ 有 | ✅ 有 |
| COW 内存放大 | ✅ 有 | ✅ 有 |
| 触发频率 | 按 `save` 配置，分钟级 | 从库每次上线 / backlog 撑爆 |

**关键差异**：复制场景的 fork 更容易被触发——从库重启、网络抖动导致 backlog 撑爆，都会触发全量复制。

这也是 1.6 节强调"调大 backlog"的原因：**减少全量复制次数，就是减少 fork 和 COW 的次数**。

另外注意，Redis 8 主库日志里有这个新指标：

```
* Fork CoW for RDB: current 0 MB, peak 0 MB, average 0 MB
```

可以直接观察复制的 COW 开销。

### 持久化和复制的分工

```
持久化（课 5）：把数据写到磁盘
   → 解决：进程重启后数据还在

复制（课 6）：把数据传到另一台机器
   → 解决：机器挂了数据还在

哨兵（课 6）：自动切换主库
   → 解决：机器挂了服务不停
```

**三者缺一不可，但不能互相替代**：

- 只有持久化 → 机器挂了数据读不出来
- 只有复制 → 主库挂了要人工切换
- 都有 → 但异步复制仍可能丢少量数据

### 与课 7 的联系（预告）

下一阶段是《分片与集群》，核心是 Redis Cluster。这里先说明哨兵的边界：

**哨兵不能突破单机内存限制。**

无论挂多少个从库，每个从库都是主库的**完整副本**。主库有 64 GB 数据，每个从库也要 64 GB。

如果你的数据量超过单机内存，或者写吞吐量超过单主库能力——**哨兵帮不了你**，需要 Redis Cluster 做数据分片（16384 个哈希槽）。

另一个伏笔：Redis Cluster **内部也用类似的主从复制 + 故障转移机制**，同样受异步复制的丢数据限制。本课讲的原理在那里完全适用。

### 本课必须记住的五个数字

| 数字 | 含义 |
|------|------|
| **7.06 秒** | 本机实测故障转移总耗时（down-after=5s + 切换 2s） |
| **1 MB / 0.05 秒** | 默认 backlog 大小，满载写入下的容忍断线时间 |
| **5 秒** | `repl-diskless-sync-delay` 默认等待（Redis 8，攒从库共享 fork） |
| **3 / 2** | 3 个哨兵、quorum=2，可容忍 1 个哨兵故障 |
| **3 秒** | `min-replicas-max-lag` 默认值（但 `to-write=0` 时不生效） |

---

## 常见误区

### 误区 1："全量复制时主库会生成 RDB 文件"

**在 Redis 8 不准确**。默认 `repl-diskless-sync yes`，RDB 通过 socket **直接流式发给从库，不落主库磁盘**。

主库日志为证：`Starting BGSAVE for SYNC with target: replicas sockets`。

### 误区 2："从库断线重连会自动增量同步"

**有条件**。只有从库报的 offset 还在主库 backlog 范围内才行。backlog 是**环形缓冲**，写满后覆盖旧数据。

默认 1 MB 的 backlog 在满载写入下只能容忍 **0.05 秒**断线。生产环境频繁全量同步，多半是 backlog 太小。

### 误区 3："有了哨兵就不会丢数据"

**错，这是本课最重要的认知**。复制是异步的——主库返回 OK 时数据还没到从库，此时主库挂掉，数据永久丢失。

哨兵解决的是**可用性**，不是**一致性**。官方文档明确说 `WAIT` 也不能让 Redis 变成强一致系统。

### 误区 4："哨兵是代理，客户端通过它读写数据"

**错**。哨兵只负责告诉客户端"当前主库在哪"，客户端拿到地址后**直连**主库。哨兵不在数据路径上。

### 误区 5："2 个哨兵就够了，quorum 设为 2"

**错**。2 个哨兵时，挂掉 1 个就永远凑不齐 2 票，无法故障转移。

标准做法是 **3 个或以上奇数个**哨兵，且分布在不同故障域。

### 误区 6："从库可以写，只要我不需要它同步回主库"

**不建议**。从库默认只读是有意的保护。即使手动关闭 `replica-read-only`，从库的本地写入也会在下一次全量同步时被**静默清空**。

---

## 本课小结

| 知识点 | 核心结论 |
|--------|---------|
| 全量与增量复制 | 首次必全量（fork+COW，Redis 8 默认无盘走 socket）；增量靠 backlog 环形缓冲，默认 1MB 在满载写入下仅容忍 0.05 秒断线，生产需按「写入速率 × 可容忍断线时长」调大；批量上线从库时保持 diskless delay 让它们共享一次 fork |
| 哨兵故障转移 | 主观下线(SDOWN)→客观下线(ODOWN,需 quorum)→领头选举→提升从库；本机实测 7.06 秒完成（5 秒 down-after + 2 秒切换），日志事件链 +sdown→+vote-for-leader→+odown→+switch-master 完整可查；至少 3 个奇数哨兵分布在不同故障域 |
| 哨兵解决不了的丢数据 | 异步复制导致「主库返回 OK 但数据未到从库」，实测可用 min-replicas-to-write 让主库返回 NOREPLICAS 拒绝写入、用 WAIT 让客户端等确认；但两者都只收窄风险窗口，官方明确不保证强一致；哨兵管可用性不管一致性 |

---

## 📝 本课小测

**Q1**：关于 Redis 8 的全量复制，下列说法正确的是？
- A. 主库一定会先执行 BGSAVE 生成 RDB 文件到磁盘，再发给从库
- B. 默认开启无盘复制，RDB 通过 socket 直接流式发给从库，不落主库磁盘
- C. 无盘复制意味着完全不需要 fork 子进程
- D. 所有从库上线时都会各自触发一次独立的 fork

<details><summary>答案与解析</summary>

**答案：B**。Redis 8.10.1 实测 `repl-diskless-sync` 默认为 `yes`，主库日志显示 `Starting BGSAVE for SYNC with target: replicas sockets`——RDB 走 socket 不落盘。

A 错——这是 Redis 7 之前的默认行为，8 已改变；C 错——无盘复制**仍需 fork**，日志里的 `Background RDB transfer started by pid` 就是 fork 出的子进程，只是它把数据写进 socket 而非文件；D 错——`repl-diskless-sync-delay` 默认 5 秒，主库会故意等待攒从库，让它们**共享一次 fork**（实测 3 个从库只触发 2 次 BGSAVE）。

</details>

**Q2**：某 Redis 主库写入速率约 5 MB/s，`repl-backlog-size` 保持默认 1 MB。从库因网络抖动断线 3 秒后重连，最可能发生什么？
- A. 增量复制，因为 backlog 足够覆盖 3 秒的写入
- B. 全量复制，因为 3 秒写入约 15 MB，远超 backlog 容量
- C. 取决于从库的 `replica-priority` 配置
- D. 不会触发任何同步，从库自动追平

<details><summary>答案与解析</summary>

**答案：B**。backlog 需求 = 写入速率 × 断线时长 = 5 MB/s × 3 s = **15 MB**，远超默认 1 MB 的 backlog。断线期间的数据已被环形缓冲覆盖，只能全量复制。

A 错——1 MB 在 5 MB/s 下只能撑 **0.2 秒**；C 错——`replica-priority` 只影响**哨兵选主**时的优先级，与同步方式无关；D 错——断线必然触发重新同步。

**生产启示**：backlog 应按「峰值写入速率 × 可接受的最长断线时间」配置。本课实测满载（204,081 ops/s）下，1 MB 只够 0.05 秒，256 MB 才够 13 秒。

</details>

**Q3**：关于哨兵的部署与配置，下列说法**错误**的是？
- A. 至少需要 3 个哨兵（奇数个），且应分布在不同故障域
- B. quorum=2 意味着至少 2 个哨兵同意才能判定主库客观下线
- C. 故障转移耗时约等于 `down-after-milliseconds` 加上 2~3 秒的选举切换时间
- D. 客户端通过哨兵读写数据，哨兵是数据访问的代理层

<details><summary>答案与解析</summary>

**答案：D**。哨兵**不在数据路径上**。客户端先问哨兵"当前主库在哪"，拿到地址后**直连主库**读写。哨兵只负责监控、通知和故障转移。

A 对——2 个哨兵时挂掉 1 个就凑不齐 quorum，无法故障转移；B 对——quorum 就是客观下线的票数门槛，实测日志显示 `+odown ... #quorum 3/2`（3 票达成，需要 2 票）；C 对——本机实测 down-after=5000ms 时总耗时 **7.06 秒**。

</details>

**Q4**：主库已向客户端返回 `OK`，随后立即宕机，哨兵将从库提升为新主库。关于这条已确认的写入，下列说法正确的是？
- A. 一定不丢，因为主库已经返回了 OK
- B. 一定不丢，因为开启了 AOF 持久化
- C. 可能丢失，因为复制是异步的，主库返回 OK 时数据可能还没到从库
- D. 可能丢失，但只要配置了 `min-replicas-to-write 1` 就绝不会丢

<details><summary>答案与解析</summary>

**答案：C**。这是本课的核心结论：**主库返回 OK ≠ 数据已到从库**。异步复制下，主库写入内存后就返回，复制是之后的事。

A 错——OK 只代表主库本地写入成功；B 错——AOF 保证的是**本机重启**后能恢复，但机器宕机时磁盘上的数据读不出来（这正是需要复制的原因）；D 错——官方文档明确说明 `min-replicas` 只是**收窄风险窗口**（bound risk），不是逐条写入的法定人数确认，而且它防的是"从库全挂还继续写"，不防"写入瞬间主库宕机"。

**补救手段**：关键写入后用 `WAIT 1 1000` 等待从库确认，但官方文档同样明确 `WAIT` 不能让 Redis 变成强一致系统。

</details>

**Q5**：关于 `min-replicas-to-write` 与 `WAIT` 命令，下列说法正确的是？
- A. `min-replicas-to-write` 默认已开启，值为 1
- B. 开启 `min-replicas-to-write 1` 后，从库全部下线时主库会拒绝写入并返回 NOREPLICAS
- C. `WAIT` 命令可以保证数据绝对不丢失，等价于强一致
- D. 两者都是服务端配置，客户端无需感知

<details><summary>答案与解析</summary>

**答案：B**。本机实测：开启 `min-replicas-to-write 1` 后停掉从库，写入返回 `(error) NOREPLICAS Not enough good replicas to write.`——主库主动拒绝，宁可不可写也不让数据冒险。

A 错——`min-replicas-to-write` 默认是 **0（关闭）**，需要显式开启；注意 `min-replicas-max-lag` 默认是 **3 秒**，但只有 `to-write > 0` 时才生效。
C 错——官方文档原文：*WAIT does not make Redis a strongly consistent store*，且 *it is possible to still lose a write synchronously replicated to multiple replicas*。
D 错——`min-replicas-to-write` 是服务端配置，但 `WAIT` 是**客户端命令**，需要应用在代码里显式调用。

</details>

---

## 🚀 下一批接力提示词

> 学完本课，**复制下面这段文字发给 AI**，即可无缝进入下一批（无需重新描述上下文）：

```
继续学 Redis。我的学习档案在 redis/00-学习档案.md，
刚学完阶段 3《持久化与高可用》的课 6《主从复制与哨兵》知识点「全量与增量复制、哨兵故障转移、哨兵解决不了的丢数据」，
请按大纲继续讲解阶段 4《分布式与生产实践》的课 7《分片与集群》的知识点：哈希槽与 CRC16、集群伸缩与重定向、集群下的多 key 与 Lua 限制。
```

## 🧭 课程导航

⬅️ **上一课**：[课 5：RDB 与 AOF 持久化](lesson-05-RDB与AOF持久化.md)

➡️ **下一课**：课 7：分片与集群（待编写）

📚 **返回目录**：[课程目录](../../02-课程目录.md)
