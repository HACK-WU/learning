# 课 9：生产实践与选型

> 阶段 4《分布式与生产实践》第 3 课（**阶段收官课**）
> 前置：课 7《分片与集群》、课 8《缓存设计》
> 环境：WSL Ubuntu 24.04 + Redis 8.10.1（本机实测，核查于 2026-09）

---

## 本课要解决的三个问题

前八课讲的是"Redis 怎么用、怎么不出事"。本课讲最后三件事——**出事之后怎么查、上线之前怎么配、以及最根本的：到底该不该用 Redis**。

1. **服务变慢了，从哪查起？** —— 性能诊断
2. **上线前必须做哪些配置？** —— 安全与运维基线
3. **这个业务真的需要 Redis 吗？** —— 生态与选型

先说本课的核心立场：**这三项都是"判断力"而非"知识点"**。工具命令查文档就能会，难的是面对一个报警时，知道该看哪个指标、以及看懂之后该做什么取舍。本课的每一个结论，本机都做了实测——包括几个和"网上流传的说法"相反的结果。

---

## 第一幕：场景引入 —— 三个凌晨三点的电话

### 困境一：接口变慢了，但不知道是谁的锅

监控报警：订单接口 P99 从 20ms 涨到 800ms。

你去看应用，应用说"我在等 Redis"；你去看 Redis，`INFO` 显示 CPU 不高、内存正常、连接数正常。所有"看起来该看的指标"都正常，但服务就是慢。

这时候你需要的是**能定位到具体命令、具体 key 的手段**，而不是继续盯着整体指标发呆。

### 困境二：数据没了，而日志里什么都没有

第二天早上，缓存里的数据全没了。查应用日志——没有异常；查 Redis 日志——只有一行 `DB saved on disk`。

后来才发现：Redis 端口是对外开放的，没有密码，被人扫到后执行了一条 `FLUSHALL`。

**这不是假设。** 本课实验过程中，我在探测脚本里写了一条 `SHUTDOWN`，结果把本机 6379 实例直接关掉了——一个命令，进程当场消失。这就是"危险命令 + 无鉴权"的真实破坏力。

### 困境三：团队吵了三天，要不要上 Redis

需求是"一个支持多条件筛选的后台查询页"。有人主张放 Redis（快），有人主张直接查库（简单）。

这类争论之所以吵不出结果，是因为双方在比"Redis 快"和"数据库简单"，而**真正该问的是：这个访问模式是不是 Redis 的适用场景**。

---

## 第二幕：认知冲突 —— 五个"想当然"的崩塌

### 冲突一：慢查询日志里的耗时，不是用户感受到的耗时

这是本课第一个要打破的直觉。看实测：

```
命令                    SLOWLOG 记录      客户端实测
KEYS *                     1116 us        29.17 ms
HGETALL big:hash          36633 us      1501.10 ms
LRANGE big:list 0 -1      22015 us      1423.78 ms
ZRANGE big:zset 0 -1       7010 us       567.59 ms
```

`HGETALL` 在慢查询日志里只有 **37ms**，但客户端等了 **1501ms**，差了 **40 倍**。

**为什么？** 因为 `SLOWLOG` 只记录**命令在 Redis 内部执行**的时间，不包含：

- 结果序列化与网络传输（50 万字段的响应有好几 MB）
- 客户端接收与解析
- 连接排队等待

所以，**当"Redis 不慢但接口慢"时，慢查询日志可能是干净的**——瓶颈在返回数据量，不在命令执行。这时候要看的是返回值大小，而不是慢日志。

反过来说，`SLOWLOG` 的真正价值是发现**执行本身很慢**的命令（如 `KEYS *` 全量扫描），它反映的是"这条命令在服务端占了多少 CPU 时间"。

### 冲突二：大 key 的危害不是"占内存"，是"删除时的长停顿"

很多人知道大 key 不好，理由是"占内存"。但实测显示，**更致命的是删除/过期瞬间的阻塞**：

```
                                  删除耗时        期间其他客户端最大延迟
A) 1 个 Hash（100 万字段）          113.60 ms      113.66 ms
B) 1000 个小 Hash（各 1000 字段）    95.40 ms        0.61 ms
```

两个方案的**数据总量几乎相同**（A 是 54.62 MB，B 约 51.66 MB），总删除耗时也接近（113ms vs 95ms）。

**但服务停顿差了 185.7 倍。**

原因很直白：Redis 单线程执行命令，`DEL` 一个 100 万字段的 Hash 是一次性完成的原子操作，这 113ms 内**所有其他客户端都在排队**。而删 1000 个小 key，每个只要 0.09ms，中间可以穿插处理其他请求。

这就是为什么"拆大 key"是硬要求——**不是为了省内存，是为了避免把一次长阻塞切成一段不可中断的停顿**。

**解法：`UNLINK` 替代 `DEL`**

```
DEL    huge2:hash  :  返回耗时 113.60 ms，期间其他客户端最大延迟 113.66 ms
UNLINK huge2:hash  :  返回耗时  0.11 ms，期间其他客户端最大延迟  0.45 ms
```

`UNLINK` 只把 key 从 keyspace 摘除（O(1)），真正的内存释放交给后台线程（`lazyfree`）慢慢做。阻塞从 113.66ms 降到 0.45ms。

本机 `LATENCY DOCTOR` 也给出了同样的建议（原文）：

> Deleting, expiring or evicting (because of maxmemory policy) large objects is a blocking operation. If you have very large objects that are often deleted, expired, or evicted, try to fragment those objects into multiple smaller objects.

### 冲突三：`+@read` 会连 `KEYS` 一起给出去 —— ACL 配置最常见的坑

配置只读账号，最自然的写法是：

```
ACL SETUSER app_ro on >pwd ~cache:* -@all +@read
```

看起来很安全：先 `-@all` 收掉所有权限，再 `+@read` 只给读。实测：

```
以 app_ro 身份连接：
  GET cache:a        -> 1                    ✅ 符合预期
  GET asset:secret   -> DENIED（前缀不匹配）   ✅ 符合预期
  SET cache:a 9      -> DENIED                ✅ 符合预期
  FLUSHALL           -> DENIED                ✅ 符合预期
  KEYS *             -> 返回全部 5 个 key      ❌ 预期之外！
```

**`KEYS` 属于 `@keyspace` 类别，而 `@read` 类目里并没有把它排除掉。** 给业务账号 `+@read`，等于同时给了它全量扫描的能力和全部键名的信息。

正确写法是显式排除：

```
ACL SETUSER app_safe on >pwd ~cache:* -@all +@read -keys -hgetall
```

实测：

```
  GET cache:a        -> OK
  KEYS *             -> DENIED
  HGETALL big:hash   -> DENIED
```

**要点**：ACL 的"读权限"和"安全"不是一回事。配置完必须**用真实连接逐个验证**，不能靠推理。

### 冲突四：`io-threads` 调大不一定变快 —— 而且你的压测可能是假的

这是本课最反直觉、也最容易踩坑的一条。

**第一次实测（用 Python 客户端），结论是"越多线程越慢"：**

```
io-threads         单连接        8 连接       32 连接
1                   18813        19193        28331
4                   11050        17111        21976
8                   10489        16016        20864
```

如果到此为止，就会得出"io-threads 是负优化"的结论。**但这个结论是错的。**

**换用官方 `redis-benchmark`（C 实现）重测，结论完全反转：**

```
value = 3 B，200 并发 GET
io-threads=1  :  188465 ops/s
io-threads=4  :  665779 ops/s    ← 3.5 倍
io-threads=8  :  664893 ops/s

value = 1024 B，200 并发 GET
io-threads=1  :  184706 ops/s
io-threads=4  :  499002 ops/s    ← 2.7 倍

pipeline(-P 16)，200 并发 GET
io-threads=1  : 1506024 ops/s
io-threads=4  : 1992032 ops/s
```

**为什么两次结果相反？** 因为第一次的瓶颈在**客户端**，不在服务端。Python 单连接只能跑到 18813 ops/s，根本没把服务端压满——服务端有没有开 io-threads 都无所谓，多线程反而引入了协调开销。

这和官方 redis.conf 里的警告完全对应：

> NOTE 2: If you want to test the Redis speedup using redis-benchmark, make sure you also run the benchmark itself in threaded mode, using the `--threads` option to match the number of Redis threads, otherwise you'll not be able to notice the improvements.

**三点必须记住：**

1. **`io-threads` 是 immutable 配置**，`CONFIG SET` 会报 `can't set immutable config`，必须改配置文件重启。
2. **命令执行永远单线程**。io-threads 只并行网络读写与协议解析，不改变 Redis 的单线程语义。
3. **有代价**：实测 CPU 用量 `used_cpu_sys` 从 44.5 → 78.1 → 119.9。它是拿 CPU 换吞吐，CPU 已经吃紧时不要开。

官方建议（redis.conf 原文）：4 核用 2~3，8 核用 6，**超过 8 个线程不太可能有额外收益**。

### 冲突五：`FT.CREATE` 返回 OK，不代表索引能用了

用 RediSearch 建索引时：

```
FT.CREATE orderidx ON HASH PREFIX 1 "ord:" SCHEMA amount NUMERIC SORTABLE
-> OK

立刻查询：FT.SEARCH @amount:[(9000 (10000]
-> 命中 10 条        ❌ 真实值是 9990 条
```

**索引是后台异步构建的。** `FT.CREATE` 返回 OK 只表示"索引定义建好了"。实测等待过程：

```
t=0.0s  命中 =    10
t=0.5s  命中 =  2610
t=1.0s  命中 =  5232
t=1.5s  命中 =  7718
t=2.0s  命中 = 10000   ← 构建完成（此处用的是闭区间，见下方说明）
```

**生产上必须轮询 `FT.INFO` 的 `percent_indexed`，等到 1 再切流量**，否则会静默返回错误结果——这比报错更危险，因为你不会发现。

> **关于上面 9990 与 10000 两个数字**：它们来自两个不同的查询区间。
> RediSearch 的 NUMERIC 范围默认是**闭区间**，`@amount:[9000 10000]` 会把 `amount=9000` 的 10 条也算进去，结果 10000；
> 要表达 SQL 的 `amount > 9000`，必须写成**开区间** `@amount:[(9000 (10000]`，结果是 9990。
> 数学真值也是 9990（`uid % 10000 > 9000`，uid 取 0~99999）。这个细节本身就值得记住。

---

## 第三幕：层层揭示 —— 三个知识点的原理

## 知识点 1：性能诊断

### 1.1 诊断的四层模型

排查 Redis 性能问题，按这个顺序往下走。越往上成本越低，越往下越精确：

```
第 1 层：整体指标    INFO stats / memory / clients      → 确认"是不是 Redis 的问题"
第 2 层：命令维度    INFO commandstats                  → 确认"是哪类命令"
第 3 层：单条命令    SLOWLOG / LATENCY                  → 确认"是哪条命令"
第 4 层：具体 key    MEMORY USAGE / OBJECT / SCAN       → 确认"是哪个 key"
```

**不要跳层。** 直接从第 4 层开始（比如一上来就 `SCAN` 全量找大 key）会在大实例上造成额外压力。

### 1.2 第 1 层：整体指标（先看这四个数）

```bash
redis-cli info stats | grep -E "instantaneous_ops_per_sec|keyspace_hits|keyspace_misses|expired_keys|evicted_keys|rejected_connections|latest_fork_usec"
redis-cli info memory | grep -E "used_memory_human|mem_fragmentation_ratio"
redis-cli info clients | grep -E "connected_clients|blocked_clients"
redis-cli info commandstats
```

**最该盯的四个指标：**

| 指标 | 含义 | 异常信号 |
|---|---|---|
| `instantaneous_ops_per_sec` | 实时 QPS | 突增/突降都说明上游有变化 |
| `keyspace_hits / (hits+misses)` | 缓存命中率 | 明显下降或持续偏低要查缓存设计（课 8） |
| `evicted_keys` | 被淘汰的 key 数 | 持续增长 = 内存不够（课 8） |
| `latest_fork_usec` | 上次 fork 耗时 | 过大说明 RDB/AOF 会造成卡顿（课 5） |

本课实测的健康实例：

```
instantaneous_ops_per_sec = 230726
缓存命中率 = 600040 / (600040 + 3) = 100.00%
mem_fragmentation_ratio = 1.59
rejected_connections = 0
```

**关于 `mem_fragmentation_ratio`**：这个值是 `used_memory_rss / used_memory`。实测值为 18.74 时实例刚启动、数据极少（分母小），属于正常现象；**数据量大之后**持续高于 1.5 才说明碎片严重，可考虑开启 `activedefrag`。

### 1.3 第 2 层：commandstats（找出"谁在占 CPU"）

```bash
redis-cli info commandstats
```

输出按命令聚合。本课实测（按总耗时排序）：

```
命令          调用次数      总耗时usec     平均usec
hset          1500000       644705         0.43
zadd           600000       322949         0.54
flushall            3       131826     43942.00   ← 单次极贵
hgetall             3       116376     38792.00   ← 单次极贵
lrange              3        65669     21889.67
rpush             300        56880       189.60
get             600000        40996         0.07   ← 单次很便宜
```

**怎么看这张表**：

- **`calls` 高 + `usec_per_call` 低**（如 `get`）：正常，量大但每条都便宜
- **`calls` 低 + `usec_per_call` 高**（如 `hgetall`、`flushall`）：**问题所在**，单次代价极高
- **优化优先级看 `usec` 总量**，不是看 `calls`——优化 3 次 `hgetall`（116ms）比优化 60 万次 `get`（41ms）收益大得多

### 1.4 第 3 层：SLOWLOG（找出具体的慢命令）

```bash
# 配置（默认 10000us = 10ms，生产建议 1000~5000us）
CONFIG SET slowlog-log-slower-than 1000    # 1ms
CONFIG SET slowlog-max-len 128             # 默认 128，建议调大到 1000+

SLOWLOG GET 10        # 看最近 10 条
SLOWLOG LEN           # 当前条数
SLOWLOG RESET         # 清空
```

本课实测输出结构：

```
1) id=9   耗时=   7010 us   命令=ZRANGE big:zset 0 -1 WITHSCORES
2) id=8   耗时=  22015 us   命令=LRANGE big:list 0 -1
3) id=7   耗时=  36633 us   命令=HGETALL big:hash
4) id=6   耗时=   1116 us   命令=KEYS *
```

**三个注意点：**

1. **SLOWLOG 不含网络传输时间**（见冲突一）。找"接口慢"的根因时别只看它。
2. **`slowlog-max-len` 默认只有 128**，高 QPS 下几秒就覆盖完了，生产要调大。
3. **它是内存里的 FIFO 队列**，重启即丢失，需要的话要定期采集到外部系统。

### 1.5 第 3 层补：LATENCY（SLOWLOG 抓不到的延迟）

`SLOWLOG` 只记录**命令执行**。`LATENCY MONITOR` 记录的是 Redis 内部各种**事件**的延迟，包括 fork、AOF 刷盘、大 key 释放等"不是命令但会卡住服务"的动作。

```bash
CONFIG SET latency-monitor-threshold 10    # 默认 0 = 关闭！
LATENCY LATEST
LATENCY DOCTOR          # 会给出人类可读的建议
```

本课实测（`latency-monitor-threshold` 设为 5ms 后）：

```
LATENCY LATEST:
  事件: command              峰值延迟=21 ms
  事件: command-unblocking   峰值延迟=67 ms

LATENCY DOCTOR:
  Dave, I have observed latency spikes in this Redis instance...
  1. command: 6 latency spikes (average 29ms, mean deviation 8ms). Worst all time event 40ms.
  2. command-unblocking: 2 latency spikes (average 65ms...). Worst all time event 67ms.
  I have a few advices for you:
  - Check your Slow Log to understand what are the commands you are running which are too slow...
  - Deleting, expiring or evicting (because of maxmemory policy) large objects is a blocking operation...
```

**`latency-monitor-threshold` 默认是 0（关闭）**，这是很多人"从没见过 LATENCY 有输出"的原因。生产建议设为 10~50ms。

### 1.6 第 4 层：定位大 key

**方法 A：`redis-cli --bigkeys`（最快，但只看元素个数）**

```bash
redis-cli --bigkeys          # 按"元素个数"找大 key
redis-cli --memkeys          # 按"内存占用"找大 key
redis-cli --hotkeys          # 找热 key（需要 LFU 策略）
```

⚠️ **`--bigkeys` 找的是"元素多"的 key，不是"占内存大"的 key**。一个 100 万字段但每个字段 1 字节的 Hash，和一个 10 个字段但每字段 1MB 的 Hash，前者会被报出来，后者不会。

**方法 B：`SCAN` + `MEMORY USAGE`（精确，生产推荐）**

本课实测（扫描 20004 个 key 耗时 1.17s）：

```
Top 5 大 key:
  big:hash       27.26 MB
  big:zset       15.51 MB
  big:string     10.00 MB
  big:list        6.61 MB
  user:19999       141 B
```

`SCAN` 是增量迭代，不会像 `KEYS` 那样阻塞服务，这是它能在生产上跑的原因。

**方法 C：`MEMORY USAGE` 单 key 精确测量**

```bash
MEMORY USAGE big:hash      # 27.26 MB
MEMORY USAGE user:1        # 137 B
```

**大 key 的一般标准**（经验值，按业务调整）：

| 类型 | 大 key 阈值 |
|---|---|
| String | > 10 KB（有说法是 1MB，但大 value 会影响网络与碎片，从严） |
| Hash / List / Set / ZSet | 元素数 > 5000（也有按 10000 划线的） |

本课实测的四个大 key 都远超此标准，都是真实会出问题的规模。

### 1.7 第 4 层补：定位热 key

**方法 A：`OBJECT FREQ`（需要 LFU 策略）**

这是最容易踩的坑——**它有前提**。在非 LFU 策略下调用，Redis 直接报错：

```
当前策略 = noeviction
OBJECT FREQ hot:1
-> ERR: An LFU maxmemory policy is not selected, access frequency not tracked.
   Please note that when switching between policies at runtime LRU and LFU
   data will take some time to adjust.
```

切到 `allkeys-lfu` 后重新访问 2 万次：

```
hot:1 freq = 70        ← 热 key
hot:2 freq = 74
hot:3 freq = 70
hot:4 freq = 65
hot:5 freq = 71
user:1 freq = 0        ← 冷 key
user:2 freq = 0
```

**原理**：Redis 对象头里有 24 bit 的 LRU 字段。在 LRU 策略下它存"最近访问时间戳"，**在 LFU 策略下才被解释为频率计数器**（Morris 近似计数器，8 bit 用于计数）。

**方法 B：`OBJECT IDLETIME`（LRU 视角，秒级）**

```
hot:1  idletime = 13630417 s     ← 异常值，见下方说明
user:1 idletime = 8 s
```

⚠️ 实测中 `hot:1` 显示了 1363 万秒（约 157 天）的空闲时间，这显然与"刚访问过 2 万次"矛盾。原因是这个 key 在本机测试环境里经由 RDB 加载/策略切换等路径，其 LRU 时钟未被正确刷新。**在干净的实例上，热 key 的 idletime 应该接近 0。**

这提醒一件事：**`OBJECT IDLETIME` 的绝对值在复杂操作（RDB 加载、策略切换、DEBUG 命令）后可能失真**，只适合做相对比较，不适合当精确指标。

**方法 C：客户端/代理层统计（生产最实用）**

`OBJECT FREQ` 只能一个个 key 查，无法"列出所有热 key"。真正的生产方案是：

- 在客户端 SDK 里埋点统计 key 访问频次
- 用代理（如 Redis Cluster Proxy、云厂商的代理层）做访问统计
- `redis-cli --hotkeys`（底层用 `OBJECT FREQ`，同样要求 LFU 策略）

### 1.8 性能诊断速查表

| 症状 | 第一反应 | 关键命令 |
|---|---|---|
| 整体变慢，QPS 没变 | 看命令维度 | `INFO commandstats` |
| 某类命令特别慢 | 看慢日志 | `SLOWLOG GET 10` |
| 慢日志干净但接口慢 | 返回值太大 | `MEMORY USAGE` / 查返回字节数 |
| 周期性卡顿 | fork / 过期 / 大 key 删除 | `LATENCY DOCTOR`、`latest_fork_usec` |
| 内存莫名增长 | 大 key / 客户端缓冲区 | `--memkeys`、`CLIENT LIST` |
| 命中率下降 | 缓存设计问题（课 8） | `keyspace_hits/misses` |
| 连接失败 | 连接数打满 | `connected_clients`、`maxclients` |

---

## 知识点 2：安全与运维基线

### 2.1 先看默认配置有多危险

本课实测（本机 6379 默认实例）：

```
requirepass              = (空 = 未设置)
protected-mode           = yes
bind                     = 127.0.0.1
ACL 默认用户             = user default on nopass ~* &* +@all
enable-debug-command     = no
enable-module-command    = no
enable-protected-configs = no
```

**关键风险点：`user default on nopass ~* &* +@all`**

翻译成人话：**默认用户无需密码，可访问所有 key、所有频道、所有命令。**

`protected-mode yes` + `bind 127.0.0.1` 提供了一定保护（只监听本地），但**一旦有人把 bind 改成 0.0.0.0 或加了公网 IP，Redis 就等于裸奔**。

### 2.2 危险命令：default 用户能做什么

实测（在实验实例上，default 用户无限制）：

```
(a) FLUSHALL
    执行前 DBSIZE = 2
    执行后 DBSIZE = 0          ← 一条命令，全部数据消失

(b) CONFIG SET maxmemory 100mb       → 生效
(c) CONFIG SET protected-mode no     → 生效（可用来关闭保护）
(d) KEYS *                           → 返回全部键名（泄露业务语义）
```

**真实事故链**（"Redis 未授权访问"的典型利用）：

```
无密码 → 连上 → CONFIG SET dir /var/www/html
              → CONFIG SET dbfilename shell.php
              → SET x "<?php ...?>"
              → SAVE                        ← 写入 Webshell
或直接：FLUSHALL                            ← 勒索
```

**这个威胁不是理论。** 本课做环境探测时，我在脚本里放了一条 `SHUTDOWN`，结果本机 6379 实例当场被关停——幸好 systemd 自动拉起（`uptime_in_seconds` 重置、RDB 加载 0 keys、无数据损失）。**一条命令，进程消失。** 这就是危险命令的真实破坏力。

### 2.3 ACL：最小权限实战

Redis 6.0+ 的 ACL 是唯一推荐的鉴权方式（`requirepass` 只能设一个全局密码，`rename-command` 已废弃）。

**三个典型角色：**

```bash
# (a) 只读业务用户
ACL SETUSER app_ro on >ro_password_123 ~cache:* -@all +@read -keys -hgetall

# (b) 读写业务用户（禁止管理与危险命令）
ACL SETUSER app_rw on >rw_password_456 ~cache:* ~biz:* -@all +@read +@write -@admin -@dangerous

# (c) 运维用户（可管理，但禁止删数据）
ACL SETUSER ops on >ops_password_789 ~* -@all +@read +@admin +@slow +info +config|get -flushall -flushdb -shutdown
```

**参数含义：**

| 片段 | 含义 |
|---|---|
| `on` | 启用该用户（off 表示禁用但保留） |
| `>password` | 设置密码（`<password` 是移除） |
| `~pattern` | 可访问的 key 模式（`~*` = 全部，`%RW~*` 可细化读写） |
| `&pattern` | 可访问的 Pub/Sub 频道 |
| `+@read` | 加入 `@read` 命令类 |
| `-@all` | 先移除所有权限（**建议总是先写它**） |
| `-keys` | 显式排除单个命令 |

**实测验证（`app_ro`）：**

```
GET cache:a        -> 1                    ✅
GET asset:secret   -> DENIED（前缀不匹配）   ✅
SET cache:a 9      -> DENIED                ✅
FLUSHALL           -> DENIED                ✅
KEYS *             -> 返回全部 key           ❌ 除非加了 -keys
```

**实测验证（`ops`）：**

```
CONFIG GET maxmemory   -> OK
INFO server            -> OK
SLOWLOG GET 1          -> OK
GET asset:secret       -> OK（~* 允许读所有 key）
FLUSHALL               -> DENIED  ← 即使有 +@admin，显式 -flushall 优先
```

### 2.4 ACL 的边界（它防不住什么）

**看清 ACL 的能力边界，比会配 ACL 更重要：**

1. **管不了资源消耗**：有 `@write` 权限的用户照样能写个大 key 打爆内存。ACL 管"能不能执行"，不管"执行了会不会拖垮服务"——要靠 `maxmemory` + 监控兜底。
2. **`DEBUG` 不受 ACL 控制**：它由 `enable-debug-command` 控制（默认 `no`）。实测报错信息：
   ```
   DEBUG SLEEP -> ERR DEBUG command not allowed. If the enable-debug-command
                  option is set to "local", you can run it from a local connection...
   ```
3. **慢命令不在"危险"类别里**：`KEYS`、`HGETALL` 属于 `@keyspace`/`@read`，必须显式 `-keys` 排除（冲突三）。

### 2.5 运维基线清单

**上线前必做（按优先级）：**

| # | 项 | 推荐值 | 说明 |
|---|---|---|---|
| 1 | 设密码 / ACL | 必须 | 默认 `nopass` 等于裸奔 |
| 2 | `bind` 只监听内网 | 必须 | 不要 `0.0.0.0` 直连公网 |
| 3 | 禁用/改名危险命令 | `FLUSHALL` `FLUSHDB` `SHUTDOWN` `KEYS` | 用 ACL `-command` |
| 4 | 设 `maxmemory` | 物理内存的 70~80% | 默认 0（不限制）会 OOM |
| 5 | 设 `maxmemory-policy` | 缓存用 `allkeys-lru` | 默认 `noeviction` 会让写失败 |
| 6 | 设 `slowlog-log-slower-than` | 1000~5000 us | 默认 10000us 太宽松 |
| 7 | 调大 `slowlog-max-len` | 1000+ | 默认 128 高 QPS 下秒被覆盖 |
| 8 | 设 `latency-monitor-threshold` | 10~50 ms | 默认 0 = 关闭 |
| 9 | 大 key 删除用 `UNLINK` | 替代 `DEL` | 避免长阻塞（冲突二） |
| 10 | 监控告警 | 见下 | 出事要靠它 |

**监控必须覆盖的指标：**

```
instantaneous_ops_per_sec     QPS 突变的第一个信号
keyspace_hits / misses        命中率（课 8）
evicted_keys                  淘汰数，持续增长 = 内存不足
used_memory / maxmemory       内存水位
mem_fragmentation_ratio       碎片率
connected_clients             连接数
rejected_connections          被拒连接（>0 说明 maxclients 打满）
latest_fork_usec              fork 耗时（课 5）
master_link_status            主从状态（课 6，从库视角）
```

**性能相关配置：**

| 项 | 默认 | 建议 |
|---|---|---|
| `io-threads` | 1 | 4~8（见冲突四，需压测验证，重启生效） |
| `io-threads-do-reads` | no | 读多场景设 yes |
| `lazyfree-lazy-eviction` | no | yes（避免淘汰大 key 阻塞） |
| `lazyfree-lazy-expire` | no | yes（避免过期大 key 阻塞） |
| `lazyfree-lazy-user-del` | no | yes（让 `DEL` 等价于 `UNLINK`） |
| `maxclients` | 10000 | 按实际调整 |
| `tcp-keepalive` | 300 | 保持默认 |

### 2.6 pipeline：最容易被忽视的性能杠杆

实测（写入 20000 个 key，100B value）：

```
(a) 逐条发送           :  1.012 s     19,769 ops/s
(b) pipeline(批 500)   :  0.031 s    651,669 ops/s    ← 快 33 倍
(c) 单次超大 pipeline  :  0.027 s    728,570 ops/s
```

**pipeline 把 33 倍的性能差距摆在这里**——因为逐条发送的瓶颈是网络往返（RTT），不是 Redis 处理速度。

**但不要走极端**（上面 c 比 b 只快 12%）：

- 一批太大 → Redis 要分配大缓冲区，内存峰值高
- 一批太大 → 这条连接长时间被占用，其他请求排队
- **推荐 100~1000 一批**，按 value 大小调整

---

## 知识点 3：生态与选型

### 3.1 先搞清楚：你说的"Redis"是哪个 Redis

这是选型的第一道门槛，因为**许可证在两年内变了两次**。

**时间线（已联网核查）：**

| 时期 | 版本 | 许可证 | 是否 OSI 开源 |
|---|---|---|---|
| 2009 - 2024.03 | ≤ 7.2 | BSD 3-Clause | ✅ 是 |
| 2024.03 - 2025.05 | 7.4 ~ 7.8 | RSALv2 或 SSPLv1 | ❌ 否（source-available） |
| 2025.05 起 | 8.0+ | **RSALv2 / SSPLv1 / AGPLv3 三选一** | ✅ 通过 AGPLv3 是 |

> Redis 8 起，用户可在这三个许可中任选其一。AGPLv3 是 OSI 批准的开源许可（copyleft）；RSALv2 与 SSPLv1 是 source-available，**不是** OSI 认可的开源许可。
> 同时，RediSearch、RedisJSON、RedisTimeSeries、RedisBloom 已并入 Redis Open Source 核心，适用同一三许可。

**2024 年那次改许可证的直接后果**：AWS、Google、Oracle、Alibaba、Ericsson 等联合在 Linux Foundation 下从仍为 BSD 的 7.2.4 分叉出 **Valkey**。

**Valkey 现状（核查于 2026-09）：**

- 许可证：BSD 3-Clause，Linux Foundation 治理
- 版本线：7.2.x / 8.1.x / **9.1.1**（2026-07-21 发布）
- 与 Redis 7.2 协议与数据格式兼容（RDB/AOF 可直接读），迁移是"换镜像 + 换端点"
- AWS ElastiCache、Google Cloud Memorystore、Oracle OCI Cache 等主流云厂商的托管服务均已提供 Valkey 引擎

**要点**：现在"用 Redis"和"用 Valkey"都是合理选择。决定因素通常是**许可证合规要求**与**云厂商托管服务的可用性**，而不是技术能力差异。

### 3.2 Redis vs Valkey vs Memcached vs 不用缓存

| 维度 | Redis 8 | Valkey 9 | Memcached | 不用缓存（直接查库） |
|---|---|---|---|---|
| 许可证 | 三许可（含 AGPLv3） | BSD 3 | BSD 3 | - |
| 数据结构 | 丰富（String/Hash/List/Set/ZSet/Stream/Bitmap/HLL/Geo/JSON/向量） | 丰富（同 Redis 7.2 基线 + 自有扩展） | 仅 String | - |
| 持久化 | RDB + AOF | RDB + AOF | 无 | - |
| 命令执行模型 | 单线程 | 单线程 | 多线程 | - |
| 内存效率（小 value） | 中 | 较高（8.1 起新哈希表省约 20%） | 高（slab 分配） | - |
| 适用场景 | 缓存 + 数据结构服务器 + 消息队列 + 搜索 | 缓存、会话、队列 | 纯 KV 缓存，追求极简 | 数据量小、查询复杂 |

**选型判据（按这个顺序问）：**

1. **是否需要复杂数据结构或持久化？**
   - 否 + 只要纯 KV 缓存 → Memcached 也是选项（多线程，简单场景内存效率更好）
   - 是 → Redis / Valkey
2. **是否有许可证合规要求？**（法务对 AGPL 有顾虑 / 公司政策禁用）
   - 是 → Valkey（BSD）
   - 否 → 两者皆可
3. **是否用云厂商托管？**
   - 是 → 看云厂商提供哪个引擎（主流云已转向 Valkey）
4. **是否需要 Redis 8 独占能力？**（Query Engine、JSON、TimeSeries、向量集）
   - 是 → Redis 8（Valkey 的模块生态不同，需单独评估）

### 3.3 什么时候**不该**用 Redis

这是本课最重要的判断，也比"什么时候用"更容易被忽略。

**信号 1：需要按字段条件筛选**

实测：10 万条订单，找 `amount > 9000` 的：

```
Redis 原生：MGET 取回全部 10 万条，客户端过滤
            耗时 0.26 s，命中 9990 条（9.99%）
            → 命中率 10%，却传输了 100% 的数据

数据库：SELECT * FROM orders WHERE amount > 9000   （走索引，毫秒级）
```

**Redis 是 key-value 存储，没有"按 value 字段查询"的能力**（除非用 Query Engine 建索引）。这类需求放数据库。

**信号 2：数据量超过内存预算**

Redis 所有数据都在内存。100 万个 100B 的对象，实测占 150.76 MB（还不算碎片与副本）。数据量到 TB 级时，内存成本会远超收益。

**信号 3：需要强事务 / 复杂关联查询**

Redis 的事务（`MULTI`/`EXEC`）不支持回滚，Lua 脚本能保证原子性但调试困难。多表关联、复杂聚合这类需求，关系数据库是更好的选择。

**信号 4：数据不能丢，且没有做好持久化**

如果数据不可重建、又没配好 AOF + 主从，Redis 进程重启数据就没了。（课 5、课 6）

**信号 5：只是为了"快"而加缓存，但没有热点**

缓存有效的**前提是有热点**。如果访问完全均匀、每条数据只读一次，缓存只会增加一次网络跳转和一份内存开销，纯属负优化。

### 3.4 内存效率：同一份数据，存法不同差 20%

实测（100 万个用户对象，每个 value 约 100 字节）：

```
(A) 100 万个独立 String key
    数据集内存 = 150.76 MB    碎片率 1.14

(B) 1000 个 Hash 桶，每桶 1000 字段
    数据集内存 = 120.27 MB    碎片率 1.12

→ Hash 分桶省了 30.45 MB（20.2%）
```

**为什么省**：每个独立 key 都要带 robj 头、dictEntry、SDS 等固定开销；Hash 用紧凑编码时，1000 个字段共享一个 key 的开销。

**但 listpack 编码有前提，实测阈值：**

```
hash-max-listpack-entries = 512     ← 超过就退化为 hashtable
hash-max-listpack-value   = 64      ← 单个 field 的 value 超过 64 字节也退化
zset-max-listpack-entries = 128     ← 注意：和 hash 不一样！
list-max-listpack-size    = -2
```

实测确认：

```
probe:small (1 字段)     编码 = listpack
bucket:0    (1000 字段)  编码 = hashtable   ← 超过 512，已退化
```

**所以**：这个分桶方案要真正省内存，**每桶字段数必须控制在 512 以内**（本课用了 1000，已经退化了，仍然省了 20%，说明 key 级别的固定开销才是大头）。

**代价**（必须一起权衡）：

- 无法对单个 field 设 TTL
- 无法单独淘汰某个用户
- 读写单个用户要带上桶 key，代码更复杂

### 3.5 精确 vs 概率：21 倍内存差距

实测（10 万个 id）：

```
(A) Set（精确，无误差）          3.97 MB
(B) 布隆过滤器（声明误判 0.1%）   193.25 KB
→ 概率结构省了 21.0 倍内存
   实测误判率：52 / 100000 = 0.0520%
```

**这个对比在课 8 讲穿透时已经用过**（布隆过滤器防穿透）。这里复用是为了说明一个更普适的选型原则：

> **当业务能接受"概率正确"时，概率结构往往能省一到两个数量级的资源。**

除了布隆过滤器，Redis 8 还提供：Cuckoo 过滤器（支持删除）、Count-Min Sketch（频次估计）、Top-K（高频元素）、t-digest（分位数）。

### 3.6 Redis 8 的 Query Engine：该不该在 Redis 里造索引

Redis 8 内置了 RediSearch，可以在 Redis 里建二级索引。实测（10 万条订单，Hash 存储）：

```
无索引：全量取回客户端过滤
        命中 9990 条，耗时 0.357 s

建索引后：FT.SEARCH @amount:[(9000 (10000]
        命中 9990 条，耗时 0.0020 s
        → 快 177 倍

代价：索引额外占 20.76 MB（约原数据的 195.7%）
```

**判据不是"能不能建"，而是"值不值"：**

**留在 Redis 建索引：**
- 该查询是高频主路径（每次请求都要做）
- 数据本身就是 Redis 里的主数据，不是数据库的热副本
- 能接受索引的内存与维护成本

**回数据库：**
- 只是偶发的运营查询 / 后台导出
- 数据库里已有合适索引
- 团队不具备维护 Redis 索引的经验

**两个生产陷阱：**

1. **索引是异步构建的**（见冲突五）。`FT.CREATE` 返回 OK 后立刻查，实测只命中 10 条（真值 9990）。必须用 `FT.INFO` 的 `percent_indexed` 确认就绪。
2. **NUMERIC 区间默认是闭区间**。SQL 的 `amount > 9000` 要写成 `@amount:[(9000 (10000]`，写成 `[9000 10000]` 会多出 10 条（`amount=9000`）。

**一句话**：Redis 8 把 RediSearch 内置进来，是让"Redis 顺手能做搜索"，不是让"所有搜索都该放 Redis"。

### 3.7 选型决策树

```
                    需要缓存/高速存取吗？
                    ├── 否 → 不用 Redis
                    └── 是
                        │
                        需要复杂数据结构/持久化/发布订阅吗？
                        ├── 否（纯 KV 缓存）
                        │   └── Memcached 或 Redis 均可
                        │       （极简场景 Memcached 内存效率更好）
                        └── 是
                            │
                            有 AGPL 合规顾虑吗？
                            ├── 有 → Valkey（BSD 3）
                            └── 无
                                │
                                需要 Redis 8 独占能力吗？
                                （Query Engine / JSON / TimeSeries / 向量集）
                                ├── 是 → Redis 8
                                └── 否 → Redis 或 Valkey 皆可
                                        （看云厂商托管与团队经验）

⚠️ 任何时候，出现以下信号就该重新评估：
   - 需要按 value 字段做条件筛选（改用数据库或 Query Engine）
   - 数据量超过内存预算
   - 需要强事务或多表关联
   - 没有热点（缓存无收益）
```

---

## 第四幕：实操验证

> 环境：WSL Ubuntu 24.04 + Redis 8.10.1（redis-stack，含 bf / search / ReJSON 模块）
> **实验全部使用独立端口 7101~7106，不触碰默认 6379 实例。**

### 实验 0：准备实验实例

```bash
# 完整可复制版本（先建目录，MOD 是本机 redis-stack 模块路径）
MOD=/usr/lib/redis/modules
DIR=/tmp/redis-l09
mkdir -p $DIR

# ① 诊断与安全实验实例
redis-server --port 7101 --bind 127.0.0.1 --dir $DIR \
  --save '' --appendonly no \
  --loadmodule $MOD/redisbloom.so --loadmodule $MOD/rejson.so &

# ② 选型实验实例（不带 search，用于实验 5）
redis-server --port 7105 --bind 127.0.0.1 --dir $DIR \
  --save '' --appendonly no \
  --loadmodule $MOD/redisbloom.so &

# ③ io-threads 对比实例（该配置 immutable，只能在启动时指定）
for spec in "7102:1" "7103:4" "7104:8"; do
  PORT=${spec%%:*}; T=${spec##*:}
  redis-server --port $PORT --bind 127.0.0.1 --dir $DIR \
    --save '' --appendonly no --io-threads $T &
done

# ④ 选型实验实例（带 search 模块，用于实验 6）
redis-server --port 7106 --bind 127.0.0.1 --dir $DIR \
  --save '' --appendonly no \
  --loadmodule $MOD/redisbloom.so --loadmodule $MOD/rejson.so \
  --loadmodule $MOD/redisearch.so &

sleep 1.5
# 验证：应看到 6 个 PONG
for p in 7101 7102 7103 7104 7105 7106; do
  echo -n "$p -> "; redis-cli -p $p ping
done
```

> **如果模块路径不同**：用 `find / -name "redisbloom*.so" 2>/dev/null` 定位，或执行 `redis-cli -p 6379 module list` 查看已加载模块的 path（本机 6379 上跑着 redis-stack，含全部模块）。
> **不需要全部模块也能跑大部分实验**：只有实验 2 的布隆过滤器（`BF.*`）与实验 6 的 `FT.*` 需要模块，其余纯 Redis 内核命令即可。

> 本机 Python 3.12 无第三方 Redis 客户端，实验脚本用纯标准库 socket 实现 RESP2 协议（沿用课 8 惯例），脚本在 `redis/playground/prep-lesson-09-*.py`。

### 实验 1：诊断四件套

```bash
cd /mnt/d/projects/learning/redis/playground
python3 prep-lesson-09-diag.py
```

**你会看到：**

1. **慢查询日志**——触发 `KEYS *`、`HGETALL`、`LRANGE`、`ZRANGE` 后，`SLOWLOG GET` 记录的耗时与客户端实测耗时相差数十倍（冲突一）
2. **大 key**——`MEMORY USAGE` 精确测量，`SCAN` + `MEMORY USAGE` 全量扫描找出 Top 5
3. **热 key**——`OBJECT FREQ` 在非 LFU 策略下报错（冲突三的前提），切到 `allkeys-lfu` 后热 key freq 达 65~74，冷 key 为 0
4. **commandstats**——`hgetall` 调用 3 次却占总耗时 116ms，`get` 调用 60 万次仅 41ms

**关键输出片段：**

```
  ⚠️ 关键对比：SLOWLOG 记录的耗时 vs 客户端感受到的耗时
    命令                                  SLOWLOG(us)      客户端实测(ms)
    KEYS                                       1116          29.17
    HGETALL                                   36633        1501.10
```

### 实验 2：安全基线

```bash
python3 prep-lesson-09-security.py
```

**你会看到：**

1. 默认用户 `+@all` 下，`FLUSHALL` / `CONFIG SET` / `KEYS *` 全部可用
2. 三个 ACL 角色创建后，用**真实连接**逐个验证权限
3. **`KEYS *` 在 `+@read` 下仍然可用**——直到显式加 `-keys` 才被拒绝（冲突三）
4. `DEBUG` 命令不受 ACL 控制，由 `enable-debug-command` 独立控制

### 实验 3：性能与运维基线

```bash
python3 prep-lesson-09-perf.py
```

**你会看到：**

1. **pipeline 快 33 倍**（19769 → 651669 ops/s）
2. **大 key 删除阻塞 113.66ms，小 key 仅 0.61ms（185.7 倍）**（冲突二）
3. **`UNLINK` 把阻塞从 113.66ms 降到 0.45ms**

> ⚠️ `perf.py` 在第 4 节（io-threads）会因 `io-threads` 是 immutable 配置而报错中断。
> 后面的 `maxmemory` 与客户端缓冲区两节**必须单独跑 `perf2.py`**（见下）。

### 实验 3b：maxmemory 保护与客户端缓冲区

```bash
python3 prep-lesson-09-perf2.py
```

**你会看到（maxmemory 设与不设的差别）：**

```
场景 A：maxmemory=20mb + allkeys-lru
  写入 300000 个 key（理论 57.22 MB）
  实际 used_memory = 20.00 MB      ← 被限制住
  DBSIZE           = 68911
  evicted_keys     = 231088
  写入成功 299999 次，失败 1 次

场景 B：同样 20mb，但策略是默认的 noeviction
  写入成功  67172 次，失败 132828 次
  首次报错: OOM command not allowed when used memory > 'maxmemory'.
```

**以及客户端输出缓冲区的风险（订阅者不消费）：**

```
CLIENT LIST: omem=17920496  cmd=subscribe
used_memory_human = 18.95M
继续发布后：订阅者已被断开（触发 pubsub 32MB 硬限制保护）
```

这解释了"Redis 内存涨了但 key 没变多"这类问题——内存被**客户端输出缓冲区**吃掉了。

### 实验 4：io-threads（注意压测方法）

```bash
# ❌ 用 Python 客户端测，会得出"越多线程越慢"的错误结论
python3 prep-lesson-09-iothreads-bench.py

# ✅ 用官方 redis-benchmark（C 实现），且 --threads 匹配服务端
bash prep-lesson-09-iothreads-bench5.sh
```

**正确的实测结果：**

```
value = 3 B，200 并发 GET
io-threads=1  :  188465 ops/s
io-threads=4  :  665779 ops/s    ← 3.5 倍
io-threads=8  :  664893 ops/s

代价（CPU 累计用量 used_cpu_sys）：
io-threads=1  :  44.5
io-threads=4  :  78.1
io-threads=8  : 119.9
```

**同时验证 io 线程确实在工作：**

```
io-threads=1 : io_threaded_reads_processed:0
io-threads=4 : io_threaded_reads_processed:11257605
io-threads=8 : io_threaded_reads_processed:11257606
```

### 实验 5：选型的实测依据

```bash
python3 prep-lesson-09-select.py
```

**你会看到：**

1. String 存 vs Hash 分桶存，内存差 20.2%（150.76 MB vs 120.27 MB）
2. listpack 阈值实测：`hash-max-listpack-entries = 512`，`zset-max-listpack-entries = 128`（**两者不同**）
3. Set vs 布隆过滤器：3.97 MB vs 193.25 KB，省 21 倍，实测误判 0.052%
4. 按条件筛选：命中率 9.99% 却传输 100% 数据——不该用 Redis 的信号

### 实验 6：Query Engine 的能力边界

```bash
python3 prep-lesson-09-search-bench.py    # 正确的等待索引就绪版本
python3 prep-lesson-09-search-verify.py   # 演示异步索引构建的坑
```

**你会看到：**

```
无索引全量扫描：0.357 s，命中 9990
建索引后查询  ：0.0020 s，命中 9990    ← 快 177 倍
索引内存代价  ：额外 20.76 MB（约数据的 195.7%）

索引异步构建的坑：
  t=0.0s  命中 =    10    ← FT.CREATE 刚返回
  t=0.5s  命中 =  2610
  t=1.0s  命中 =  5232
  t=2.0s  命中 = 10000    ← 构建完成
```

### 清理

```bash
for p in 7101 7102 7103 7104 7105 7106; do
  redis-cli -p $p shutdown nosave 2>/dev/null
done
rm -rf /tmp/redis-l09
```

---

## 第五幕：体系收束

### 本课三个知识点的内核

**性能诊断**——四层模型：整体指标 → 命令维度 → 单条命令 → 具体 key。不要跳层。记住两个反直觉点：**SLOWLOG 不含网络时间**（所以慢日志干净不代表没问题），**大 key 的危害是删除时的长停顿**（不是占内存）。

**安全与运维基线**——默认配置等于裸奔（`user default on nopass +@all`）。ACL 是唯一推荐的鉴权方式，但要注意 **`+@read` 会连 `KEYS` 一起给出**，必须显式 `-keys`。配置完必须用真实连接验证，不能靠推理。

**生态与选型**——先搞清楚"你说的 Redis 是哪个 Redis"（许可证两年变两次，Valkey 已分叉）。选型的关键不是"Redis 有多快"，而是**识别出不该用 Redis 的信号**：按字段筛选、数据量超内存、无热点、需要强事务。

### 三个必须记住的"测量陷阱"

本课花了大量篇幅修正测量方法，因为这三类错误会直接导致错误结论：

1. **用错误客户端压测**：Python 单连接跑不到 2 万 ops/s，压不满服务端，会得出"io-threads 是负优化"的错误结论。官方 redis.conf 明确要求 benchmark 本身也要多线程。
2. **只看聚合不看时间轴**：课 8 雪崩实验第一版只统计"有查询的秒"，把尖峰平均掉了。本课 io-threads 第一版同理。
3. **把"命令返回成功"当成"操作已完成"**：`FT.CREATE` 返回 OK 时索引还在后台建，立刻查会得到静默的错误结果。

### 与前面八课的呼应

| 课 | 概念 | 在课 9 的落点 |
|---|---|---|
| 课 2 | `KEYS` 的危险 | 安全基线里显式 `-keys`；`SCAN` 用于大 key 扫描 |
| 课 4 | ZSet / Bitmap / HLL | 概率结构（布隆）省 21 倍内存的同类思路 |
| 课 5 | RDB fork / AOF | `latest_fork_usec` 是诊断项；持久化选型是选型前提 |
| 课 6 | 主从复制 | `master_link_status` 是必监控项 |
| 课 7 | 集群 | `--bigkeys` 在集群上要逐节点执行；热 key 问题在集群下更突出 |
| 课 8 | 淘汰策略 / 一致性 | `evicted_keys` 是诊断项；`OBJECT FREQ` 需要 LFU 策略 |

### 阶段 4 收官：从"会用"到"会判断"

阶段 4 的三课，讲的是同一件事的三个层面：

- **课 7（分片与集群）**：数据量超单机时，怎么横向扩展——**代价是多 key 操作受限、运维复杂度上升**
- **课 8（缓存设计）**：加缓存后会出现哪些故障——**代价是一致性只能做到"最终"，且没有完美方案**
- **课 9（生产实践与选型）**：出事后怎么查、上线前怎么配、最根本的要不要用——**代价是引入一整套运维与判断的负担**

贯穿三课的立场一致：**Redis 的每个能力都有代价，工程能力体现在说清代价并做出取舍**，而不是背下"最佳实践"清单。

### 一句话总结

> Redis 不难用，难的是判断什么时候不该用，以及出问题时知道该看哪里。

---

## 常见误区

1. **"慢查询日志没记录，说明 Redis 没问题"**
   错。SLOWLOG 只记命令执行时间，不含网络传输。返回值大的命令客户端等 1501ms，慢日志可能只记 37ms。

2. **"大 key 不好，因为它占内存"**
   不全面。数据总量相同时，大 key 的致命问题是删除/过期瞬间的**不可中断阻塞**（实测 113.66ms vs 0.61ms）。解法是 `UNLINK` + 拆分。

3. **"删数据不会有风险"**
   错。`DEL` 一个大 key 会造成百毫秒级全服务停顿。生产应默认用 `UNLINK`，或配置 `lazyfree-lazy-user-del yes` 让 `DEL` 等价于 `UNLINK`。

4. **"配了 ACL 只读账号就安全了"**
   不够。`+@read` 包含 `KEYS`（实测可返回全部键名）。必须显式 `-keys -hgetall`。

5. **"io-threads 越大越好"**
   错。官方建议不超过 8，超过无收益；它拿 CPU 换吞吐（实测 CPU 从 44.5 涨到 119.9）；且必须改配置重启生效（`CONFIG SET` 会报 immutable）。

6. **"用 Python 脚本压测的结果可以直接下结论"**
   危险。客户端可能先于服务端成为瓶颈（本课 Python 单连接仅 18813 ops/s，而服务端能跑 66 万）。压测前先确认瓶颈在哪一侧。

7. **"`FT.CREATE` 返回 OK 就能查了"**
   错。索引是后台异步构建的，立刻查会得到**静默的错误结果**（实测 10 条 vs 真值 9990 条）。必须轮询 `FT.INFO` 的 `percent_indexed`。

8. **"Redis 快，所以查询都放 Redis"**
   错。Redis 没有"按 value 字段查询"的能力。实测按条件筛选时命中率 9.99% 却要传输 100% 数据——这类需求属于数据库。

9. **"Hash 分桶一定省内存"**
   有条件。listpack 紧凑编码在超过 `hash-max-listpack-entries`（实测 512）后退化为 hashtable。且分桶后无法对单 field 设 TTL。

10. **"默认配置能用就行"**
    危险。默认 `requirepass` 为空、`maxmemory` 为 0（不限制，会 OOM）、`maxmemory-policy` 为 `noeviction`（写会失败）、`latency-monitor-threshold` 为 0（延迟监控关闭）。这四项上线前必改。

---

## 小测（5 题）

### Q1

某接口 P99 从 20ms 涨到 800ms，怀疑是 Redis 慢。你查看了慢查询日志，**里面干干净净，一条记录都没有**。关于这个现象，下列说法正确的是？

A. 说明 Redis 确实没问题，瓶颈在应用或数据库
B. 说明慢查询阈值配得太高，需要调低 `slowlog-log-slower-than` 后重新观察
C. 不能据此排除 Redis 问题——慢查询日志只记录命令在 Redis 内部的执行时间，不含网络传输与客户端解析
D. 说明 slowlog 缓冲区被覆盖了，需要调大 `slowlog-max-len`

<details>
<summary>答案</summary>

**C**

慢查询日志记录的是**命令在 Redis 内部执行**的时间，不包含结果序列化、网络传输、客户端解析和连接排队。

本课实测：

```
命令                    SLOWLOG 记录      客户端实测
KEYS *                     1116 us        29.17 ms
HGETALL big:hash          36633 us      1501.10 ms
LRANGE big:list 0 -1      22015 us      1423.78 ms
```

`HGETALL` 慢日志只有 37ms，客户端却等了 1501ms——**差 40 倍**。如果这个命令恰好低于慢日志阈值，慢日志就是空的，但用户感知的延迟是实打实的。

所以"Redis 不慢但接口慢"时，要看的是**返回数据量**（`MEMORY USAGE`、返回值大小），而不是慢日志。

- A 错误：慢日志干净不等于 Redis 没问题，只能说明"没有执行时间过长的命令"。
- B 错误：调低阈值确实能看到更多记录（也是个好习惯），但本题问的是"为什么慢日志干净却仍然可能是 Redis 的问题"，根本原因是统计口径不同，不是阈值高低。
- D 错误：`slowlog-max-len`（默认 128）确实可能在高 QPS 下被覆盖，但这解释的是"记录丢了"，不是"记录为空"。而且 `SLOWLOG LEN` 可以直接确认当前有多少条。

**排查顺序**：先看 `INFO commandstats` 找出哪类命令总耗时最高，再看返回值大小，最后才下结论。
</details>

### Q2

某服务里有一个 100 万字段的 Hash（约 55MB），业务下线时需要清理它。关于删除方式，下列说法正确的是？

A. 直接 `DEL`，因为删除是 O(1) 操作，Redis 会异步回收内存
B. 用 `UNLINK`，因为它只把 key 从 keyspace 摘除，内存释放交给后台线程
C. 先拆成 1000 个小 key 再逐个 `DEL`，这样总耗时更短
D. 用 `EXPIRE` 设短 TTL 让它自动过期，效果与 `UNLINK` 相同

<details>
<summary>答案</summary>

**B**

`UNLINK` 只把 key 从 keyspace 摘除（O(1)），真正的内存释放交给后台线程（lazyfree）异步完成。

本课实测（同一个 100 万字段的 Hash）：

```
DEL    huge2:hash  :  返回耗时 113.60 ms，期间其他客户端最大延迟 113.66 ms
UNLINK huge2:hash  :  返回耗时  0.11 ms，期间其他客户端最大延迟  0.45 ms
```

阻塞从 113.66ms 降到 0.45ms。

- A 错误：**这是最常见的误解**。`DEL` 对集合类型不是 O(1)，它是 O(N)——要逐个释放元素。而且 Redis 单线程执行，`DEL` 期间所有其他客户端都在排队。只有 `UNLINK` 才是"先摘除、后异步释放"。
- C 错误：拆分确实是治理大 key 的正确做法，但**理由不是"总耗时更短"**。本课实测：删一个 100 万字段的大 Hash 耗时 113.60ms，删 1000 个各 1000 字段的小 Hash 总耗时 95.40ms——总量相同，总耗时也接近。拆分的真正价值是**把一次 113ms 的不可中断停顿，变成 1000 次 0.09ms 的可打断操作**（期间其他客户端最大延迟从 113.66ms 降到 0.61ms）。
- D 错误：过期 key 的释放在 `lazyfree-lazy-expire`（默认 no）关闭时同样是**同步阻塞**的。要让它异步，得显式设置 `lazyfree-lazy-expire yes`。

**生产建议**：默认用 `UNLINK` 替代 `DEL`，或配置 `lazyfree-lazy-user-del yes` 让 `DEL` 自动等价于 `UNLINK`。
</details>

### Q3

团队配置了一个"只读"业务账号：

```
ACL SETUSER app_ro on >pwd ~cache:* -@all +@read
```

配置完成后用该账号连接测试，下列哪个命令**仍然可以执行**？

A. `SET cache:a 9`
B. `FLUSHALL`
C. `KEYS *`
D. 以上都不能执行

<details>
<summary>答案</summary>

**C**

`KEYS` 属于 `@keyspace` 命令类，**没有被 `@read` 排除**。这是 ACL 配置最常见的坑。

本课实测（以 `app_ro` 身份连接）：

```
GET cache:a        -> 1                 ✅
GET asset:secret   -> DENIED（前缀不匹配） ✅
SET cache:a 9      -> DENIED            ✅
FLUSHALL           -> DENIED            ✅
KEYS *             -> 返回全部 5 个 key   ❌ 预期之外
```

修复方法是显式排除：

```
ACL SETUSER app_safe on >pwd ~cache:* -@all +@read -keys -hgetall
```

实测：

```
GET cache:a        -> OK
KEYS *             -> DENIED
HGETALL big:hash   -> DENIED
```

- A 错误：`SET` 属于 `@write`，`+@read` 没有授予它，会被拒绝（实测 DENIED）。
- B 错误：`FLUSHALL` 属于 `@dangerous`/`@admin`，会被拒绝（实测 DENIED）。
- D 错误：`KEYS` 确实能执行。

**要点**：ACL 的"读权限"和"安全"不是一回事。配完 ACL 必须**用真实连接逐个验证**，不能靠推理——本课四个选项里，只有实测才能发现 C 这个坑。
</details>

### Q4

关于 `io-threads`，下列说法**正确**的是？

A. `io-threads` 让 Redis 的命令执行变成多线程，从而充分利用多核
B. 调大 `io-threads` 一定能提升吞吐，建议设成 CPU 核数
C. `io-threads` 只并行网络读写与协议解析，命令执行仍是单线程，且调大会增加 CPU 消耗
D. `io-threads` 可以通过 `CONFIG SET` 在线调整，方便随时验证效果

<details>
<summary>答案</summary>

**C**

`io-threads` 只并行**网络读写与协议解析**，命令执行仍然是单线程——这是 Redis 保持原子性与简单性的基石。

本课实测（官方 `redis-benchmark`，200 并发 GET，value=3B）：

```
io-threads=1  :  188465 ops/s
io-threads=4  :  665779 ops/s    ← 3.5 倍
io-threads=8  :  664893 ops/s
```

代价是 CPU：

```
used_cpu_sys:  io-threads=1 → 44.5
               io-threads=4 → 78.1
               io-threads=8 → 119.9
```

- A 错误：**命令执行永远单线程**。`io-threads` 只把 socket 读写和协议解析并行化。
- B 错误：官方 redis.conf 明确写"超过 8 个线程不太可能有额外收益"，且建议"只在确实存在性能问题时使用"。本课实测 io-threads=8 相比 =4 没有进一步提升（664893 vs 665779）。它是拿 CPU 换吞吐，CPU 已吃紧时不该开。
- D 错误：`io-threads` 是 **immutable 配置**，`CONFIG SET` 会报 `ERR CONFIG SET failed (possibly related to argument 'io-threads') - can't set immutable config`，必须改配置文件重启。

**⚠️ 附加考点**：本课第一次用 Python 客户端压测时，得出了"io-threads 越大越慢"的结论（18813 → 10489）。这是**客户端瓶颈造成的假象**——Python 单连接只能跑 18813 ops/s，根本压不满服务端（服务端能跑 66 万）。官方 redis.conf 对此有明确警告：

> If you want to test the Redis speedup using redis-benchmark, make sure you also run the benchmark itself in threaded mode, using the `--threads` option to match the number of Redis threads, otherwise you'll not be able to notice the improvements.

**压测前先确认瓶颈在哪一侧**，这是本课反复强调的方法论。
</details>

### Q5

团队要做一个"订单后台查询页"，支持按金额、城市、时间范围等条件组合筛选，数据量约 500 万条，QPS 很低（运营人员偶尔用）。关于技术选型，下列判断最合理的是？

A. 放 Redis，因为 Redis 快，查询体验好
B. 放 Redis 并用 RediSearch 建索引，实测比全量扫描快 177 倍，是最佳方案
C. 放数据库，因为这是低 QPS 的多条件筛选，Redis 原生不支持按字段查询，而建索引的内存与复杂度代价不划算
D. 放 Redis，用 Hash 分桶存储省 20% 内存，再全量取回客户端过滤

<details>
<summary>答案</summary>

**C**

这道题考的是"识别不该用 Redis 的信号"，不是考 Redis 快不快。

**两个决定性事实：**

1. **Redis 原生没有"按 value 字段查询"的能力**。本课实测：10 万条订单找 `amount > 9000`，必须全量取回客户端过滤，命中率 9.99% 却传输了 100% 的数据。数据库里一条 `SELECT ... WHERE amount > 9000` 走索引就是毫秒级。

2. **建索引的代价很高**。本课实测（10 万条数据）：
   ```
   无索引全量扫描：0.357 s
   建索引后查询  ：0.0020 s   ← 快 177 倍
   索引内存代价  ：额外 20.76 MB（约原数据的 195.7%）
   ```
   索引占了原数据近 2 倍内存。500 万条数据的索引开销会非常可观——**为了一个运营人员偶尔用的页面，不值得**。

- A 错误：只比了"快"，没问"是不是适用场景"。Redis 的快体现在**按 key 精确访问**，不是按条件筛选。而且 500 万条全放内存，成本也高。
- B 错误：这是本题最大的干扰项。177 倍是实测事实，但**技术可行不等于值得做**。判据是"查询是不是高频主路径"——运营后台低 QPS 场景，应该用数据库。此外 RediSearch 还有异步构建的坑（索引未就绪时静默返回错误结果，实测 10 条 vs 真值 9990 条），运维复杂度不低。
- D 错误：Hash 分桶省 20% 内存是实测事实，但它解决的是存储成本，**完全没解决查询问题**。全量取回客户端过滤在 500 万条规模下不可行。

**记住这个判据**：问"这个查询是不是高频主路径"。是 → 考虑 Query Engine；否 → 回数据库。Redis 8 把 RediSearch 内置进来，是让"Redis 顺手能做搜索"，不是让"所有搜索都该放 Redis"。
</details>

---

## 🚀 下一批接力提示词

**阶段 4 已完成，Redis 课程 9 课全部讲完。** 下一步是综合实战项目（评审清单中的 Phase 3）。复制以下内容发给 AI 即可继续：

```
继续学 Redis。我的学习档案在 redis/00-学习档案.md，
阶段 1-4 的 9 课已全部学完（课 1 Redis 是什么 / 课 2 跑起来第一个 Redis /
课 3 List 与 Hash / 课 4 Set、ZSet 与特殊类型 / 课 5 RDB 与 AOF 持久化 /
课 6 主从复制与哨兵 / 课 7 分片与集群 / 课 8 缓存设计 / 课 9 生产实践与选型）。
请按大纲开始结课实战项目，并在完成后生成实战经验、排障速查手册与场景解法库。
```

---

## 🧭 课程导航

- **上一课**：[课 8：缓存设计](lesson-08-缓存设计.md)
- **下一课**：结课实战项目（待编写）
- **返回**：[阶段 4 总览](../overview.md) ｜ [课程目录](../../02-课程目录.md)
