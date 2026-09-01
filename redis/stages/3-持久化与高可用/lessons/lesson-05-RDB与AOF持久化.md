# 课 5：RDB 与 AOF 持久化

> 阶段 3《持久化与高可用》第 1 课
> 前置：课 4《Set、ZSet 与特殊类型》(Set 交并差、ZSet 双结构、Bitmap/HLL/Geo)
> 环境：WSL Ubuntu 24.04 + Redis 8.10.1（本机实测，核查于 2026-09）

---

## 本课要解决的三个问题

前两阶段你学到的一切，都建立在一个脆弱的前提上：**数据全在内存里**。

课 1 讲过 Redis 是"内存数据结构服务器"，快就快在这里。但内存有个致命属性——**断电即失**。课 4 结束时你能用 ZSet 存 500 万成员的排行榜、用 Set 算出共同好友，可一旦进程挂掉，这些全部归零。

本课要回答三个问题：

1. **Redis 怎么把内存数据写到磁盘上？** —— 两种方案：RDB 快照、AOF 日志
2. **为什么备份时内存会突然涨一倍？** —— fork 与写时复制，生产上最常见的内存告警来源
3. **我该用哪种？** —— 选型不是"哪个更好"，而是"你能接受丢多少数据"

---

## 第一幕：场景引入 —— 三个真实困境

### 困境一：凌晨三点，Redis 挂了

运维重启 Redis，应用起来后发现——**用户昨天的签到数据全没了，排行榜清零，购物车空了**。

你查日志发现最后一次快照是 6 小时前。这 6 小时的写入，全部丢失。

为什么会这样？因为 RDB 是**定时快照**，不是实时记录。快照之间的数据，只存在于内存里。

### 困境二：备份时内存告警，然后 Redis 被 OOM 杀掉

你给 Redis 配了 8 GB 内存，实际用了 6 GB，看起来很安全。但每次执行 `BGSAVE`，监控就告警，严重时 Redis 直接被系统杀掉。

为什么 6 GB 数据会把 8 GB 机器撑爆？因为备份期间，你**每修改一个 key，内核就要把那个 key 所在的内存页复制一份**——旧页留给子进程写快照，新页给主线程用。快照持续几秒，这几秒内的写入累积起来，可能额外吃掉几个 GB。

（具体涨多少？本课第三幕会用实测告诉你：不写入时 **1.00x**，持续写入时 **2.15x**。）

### 困境三：AOF 文件涨到 50 GB，重启要半小时

你开启了 AOF 保证数据安全。运行半年后，AOF 文件膨胀到 50 GB。某次宕机重启，Redis 花了 40 分钟重放命令才恢复服务。

为什么 AOF 会这么大？因为它记录**每一条写命令**——一个 key 被修改 1 万次，AOF 里就有 1 万条记录，尽管只有最后一条有意义。

---

## 第二幕：认知冲突 —— 三个"想当然"的崩塌

### 冲突一：BGSAVE 不阻塞？fork 那一刻是阻塞的

你可能听说"BGSAVE 在后台执行，不阻塞主进程"。这句话**大部分对，但有个关键例外**：

```
客户端 → Redis 主线程 ──fork()──> 子进程（写 RDB 文件）
                    ↑
              这一瞬间，主线程完全卡住
```

`fork()` 系统调用本身是**同步阻塞**的。它需要复制父进程的页表（page table），数据集越大，页表越大，卡得越久。

本机实测（Redis 8.10.1，WSL）：

| 数据集大小 | fork 耗时 |
|-----------|----------|
| 61 MB | 1.10 ms |
| 241 MB | 2.46 ms |
| 481 MB | 3.20 ms |

看起来很小？注意这是**单线程模型**——fork 期间，所有客户端命令都在排队。生产环境数据集几十 GB 时，fork 耗时可达**几百毫秒甚至 1 秒**（Redis 官方文档：*this may result in Redis failing to serve clients for a few milliseconds or even up to a second for very large datasets*）。

> 💡 对比一下：`SAVE` 命令是**全程阻塞**（主线程自己写文件），生产环境禁用。`BGSAVE` 只在 fork 那一瞬间阻塞，这是它能用于生产的原因。

### 冲突二：快照期间内存不是"必然翻倍"

你可能听过"BGSAVE 时内存会涨到两倍"。**这句话是错的**——准确说法是"最坏情况接近两倍"。

写时复制（Copy-On-Write）的机制是：fork 后父子**共享**所有内存页；**只有被修改的页才会被复制**。所以内存涨幅取决于**快照期间修改了多少数据**。

本机实测（基线 210 MB 物理内存，用内核 `VmRSS` 测量）：

| 场景 | 基线 | 峰值 | 放大 |
|------|------|------|------|
| BGSAVE 期间**不写入** | 209.8 MB | 209.8 MB | **1.00x** |
| BGSAVE 期间**持续写入** | 209.7 MB | 450.3 MB | **2.15x** |
| BGSAVE 期间**高强度写入** | 210.0 MB | 708.0 MB | **3.37x** |

**不写入时完全不涨**（1.00x）。只有写入才触发页复制。

> 📌 **实测方法说明**（这个坑值得单独讲）：
> 我最初用 Redis 自报的 `used_memory` 监控，得到"只涨 1.03x"的错误结论。原因是 `used_memory` 是**逻辑分配量**，不反映 COW 导致的物理页复制。
> 必须看内核级指标 `/proc/<pid>/status` 的 **`VmRSS`**（常驻物理内存）。注意字段名是 `VmRSS` 不是 `Rss`。
> 另一个坑：`--pipe` 批量写入太快（毫秒级），子进程在修改开始前就已完成快照，测出来"25%/50%/100% 修改都只涨 1.05x"。必须用后台循环让写入**贯穿整个 BGSAVE 生命周期**。
> 完整脚本见 `playground/prep-lesson-05-cow3.sh`。

**为什么会出现 3.37x？** 因为我的测试是 15 轮持续写入，每轮都把同一个 200 MB 数据集全部改一遍。每一轮都会触发新一轮的 COW 复制，而子进程还没写完，旧页不能释放——所以超过了理论上的 2 倍。**这说明"最坏 2 倍"也不是上限**，取决于快照持续期间的总写入量。

### 冲突三：AOF 记的是"命令"，不是"数据"

很多人以为 AOF 和 RDB 一样存的是数据。不是——**AOF 存的是你执行过的命令**，用 RESP 协议原样记录：

```bash
SET writetest "value-1"
```

AOF 文件里是：

```
*3\r\n$3\r\nSET\r\n$9\r\nwritetest\r\n$7\r\nvalue-1\r\n
```

这意味着：对同一个 key 修改 1 万次，AOF 就记 1 万条。前 9999 条都是废话。

**AOF 重写**解决这个问题：不是去分析旧 AOF，而是**直接读取当前数据库状态**，用最少的命令重建。本课实测：对同一个 key 写入 1 万次后，AOF 目录 9.41 MB、dbsize 只有 4；重写后**压缩到 0.00 MB**（因为数据本身极小），且 `hotkey` 的值仍是最后一次的 `value-10000`。

---

## 第三幕：层层揭示 —— 三个知识点

## 知识点 1：RDB fork 与写时复制

### 1.1 RDB 是什么

RDB（Redis Database）是**某一时刻的全量二进制快照**，存成一个 `dump.rdb` 文件。

两个触发命令：

| 命令 | 执行者 | 是否阻塞主线程 |
|------|--------|---------------|
| `SAVE` | 主线程 | **全程阻塞**（生产禁用） |
| `BGSAVE` | fork 出的子进程 | 仅 fork 瞬间阻塞 |

两者的区别不在"快慢"，而在**阻塞范围**：

- `SAVE`：**主线程自己写文件**，从开始到结束，期间**所有客户端命令全部阻塞**
- `BGSAVE`：只在 `fork()` 那一瞬间阻塞（约几毫秒），之后主线程继续服务

> ⚠️ 不要在数据集上用 `SAVE` 实测它的"慢"——本机空数据集测出 7.50 ms 是因为没有数据可写，这个数字**完全不能反映生产环境**。真实生产数据集（几十 GB）下，`SAVE` 会阻塞**数秒到数十秒**。
>
> 这也是为什么 **`SAVE` 在生产环境被禁用**：它把整个写文件的 I/O 时间加到了主线程上。

判断是否完成（对 `BGSAVE` 而言）：

```bash
redis-cli info persistence | grep rdb_bgsave_in_progress
# 0 = 已完成，1 = 进行中

redis-cli lastsave   # 最后成功保存的 Unix 时间戳
```

### 1.2 自动触发：save 配置

默认配置（Redis 8.10.1 实测）：

```
save 3600 1 300 100 60 10000
```

三组规则，**任意一组满足即触发**：

| 规则 | 含义 |
|------|------|
| `3600 1` | 3600 秒内至少 1 次变更 |
| `300 100` | 300 秒内至少 100 次变更 |
| `60 10000` | 60 秒内至少 10000 次变更 |

实测验证：

```bash
config set save "10 1"     # 改成 10 秒内 1 次变更就保存
set trigger:test 1
# rdb_changes_since_last_save: 41
# 等 12 秒后
# rdb_changes_since_last_save: 0   <-- 已自动保存
```

`rdb_changes_since_last_save` 这个计数器很有用——它告诉你"距离上次快照，已经有多少变更没落盘"，也就是**当前的风险敞口**。

### 1.3 fork 与写时复制的完整过程

```
时刻 T0：BGSAVE 发起
  │
  ├─ 主线程调用 fork()
  │    ├─ 复制页表（不复制数据）
  │    └─ ⚠️ 这一瞬间主线程阻塞
  │
  ├─ fork 完成，父子共享所有物理页，内核把它们标记为「只读」
  │
  ├─ 子进程：遍历内存，把 T0 时刻的数据写进临时 RDB 文件
  │            （只读，不触发复制）
  │
  ├─ 主线程：继续服务客户端
  │    └─ 每次写操作 → 触碰某个共享页 → 触发缺页中断
  │                 → 内核复制该页（4KB）→ 主线程在新页上修改
  │                 → 子进程仍持有旧页
  │
  └─ 子进程写完 → 原子替换旧 RDB 文件 → 退出 → 旧页被回收
```

**关键点**：子进程看到的是 **fork 瞬间的快照**，主线程后续的修改不会污染它。这是 RDB 能生成"某一时刻一致性快照"的原因。

### 1.4 COW 的三个必须知道的事实

**事实 1：复制粒度是"页"，不是"key"**

Linux 默认页大小 4 KB。你改 1 个字节，也要复制整个 4 KB 页。

**事实 2：同一页多次修改，只复制一次**

第一次修改触发 COW，该页变成父进程私有；后续修改不再触发复制。所以**集中修改少量 key** 的代价，远小于**分散修改大量 key**。

**事实 3：THP（透明大页）会把代价放大 512 倍**

THP 把页大小从 4 KB 变成 2 MB。同样是改 1 个字节：

| 页大小 | 单次 COW 复制量 |
|--------|---------------|
| 4 KB（普通页） | 4 KB |
| 2 MB（THP） | **2 MB（512 倍）** |

本课实测本机 THP 状态是 `always [madvise] never`——方括号里是 `madvise`，不是 `never`。**Redis 官方强烈建议设为 `never`**，启动时 Redis 会检查并告警。

```bash
echo never > /sys/kernel/mm/transparent_hugepage/enabled
```

### 1.5 overcommit_memory：fork 失败的元凶

生产上常见这个报错：

```
# Can't save in background: fork: Cannot allocate memory
```

原因：Linux 无法预知 COW 会复制多少页，保守起见，`overcommit_memory=0` 时要求**有足够空闲内存来容纳父进程的完整副本**才能 fork。

Redis 官方文档的解释（Redis FAQ）：*If you have a Redis dataset of 3 GB and just 2 GB of free memory it will fail.*

解决方案：

```bash
sysctl vm.overcommit_memory=1
echo 'vm.overcommit_memory = 1' >> /etc/sysctl.conf
```

本课实测本机 `overcommit_memory=0`——在生产环境这会导致大实例备份失败。

### 1.6 RDB 会丢多少数据

**RDB 的丢失窗口 = 两次快照之间的所有写入。**

用 `save 3600 1` 举例：最坏情况丢失接近 1 小时的数据。用 `save 60 10000`：如果 60 秒内写入不到 10000 次，就一直不触发，丢失窗口无限延长。

这是 RDB 的根本局限——**它不是为"不丢数据"设计的，是为"备份"设计的**。

### 1.7 完整脚本

> 📌 完整脚本：`playground/prep-lesson-05-rdb.sh`（基础行为）、`prep-lesson-05-fork.sh`（fork 耗时梯度）、`prep-lesson-05-cow3.sh`（COW 内存放大）。

```bash
bash playground/prep-lesson-05-rdb.sh
bash playground/prep-lesson-05-fork.sh
bash playground/prep-lesson-05-cow3.sh
```

---

## 知识点 2：AOF 写后日志与刷盘策略

### 2.1 写后日志：先执行，再记录

AOF（Append Only File）记录每一条**写命令**。关键在于记录的时机——

```
客户端发来 SET k v
  │
  ├─ 1. 主线程执行 SET，修改内存中的数据
  │
  ├─ 2. 命令执行「成功后」，才追加到 aof_buf 缓冲区
  │
  └─ 3. 根据 appendfsync 策略，把 aof_buf 刷到磁盘
```

为什么是"写后"而不是"写前"？两个原因：

1. **写后日志不需要校验命令合法性**——能执行成功的命令才有记录价值
2. **不会阻塞当前命令**——命令先返回给客户端，落盘是后面的事

**代价**：如果命令执行完、还没来得及写 AOF 就宕机，这条命令就丢了。

本课实测验证了"写后"语义：

```bash
SET badkey "before"        # 成功，写入 AOF
RPUSH badkey "x"           # 报错 WRONGTYPE，执行失败
# AOF 中 RPUSH 出现次数：0  <-- 失败的命令不记录
```

### 2.2 Redis 7+ 的 multi-part AOF 结构

这可能是最容易被过时资料误导的地方。**Redis 7.0 之前，AOF 是单个 `appendonly.aof` 文件；7.0 之后改成目录结构**。

本机实测（`appendonlydir/` 目录）：

```
appendonly.aof.1.base.rdb      # base：RDB 格式的全量数据
appendonly.aof.1.incr.aof      # incr：AOF 格式的增量命令
appendonly.aof.manifest        # manifest：索引，记录文件列表与顺序
```

manifest 内容：

```
file appendonly.aof.1.base.rdb seq 1 type b
file appendonly.aof.1.incr.aof seq 1 type i startoffset 0
```

为什么要拆成多个文件？因为旧版 AOF 重写需要把**整个重写缓冲**追加到新 AOF，内存开销大。multi-part 设计让 base（RDB 格式，重写时生成）和 incr（增量命令）分离，重写时只需切换 incr 文件。

### 2.3 三种刷盘策略：实测数据

`appendfsync` 是 AOF 最重要的配置，直接决定"宕机丢多少数据"。

| 策略 | 机制 | 丢失窗口 | 主线程阻塞 |
|------|------|---------|-----------|
| `always` | 每条命令后同步 fsync | 最多 1 条命令 | **是**（等 fsync 完成） |
| `everysec` | 后台线程每秒 fsync | 约 1 秒 | 否（后台线程） |
| `no` | 不主动 fsync，交给 OS | OS 决定（Linux 通常 30 秒） | 否 |

**吞吐实测**（本机，10 万次 SET × 3 轮取中位数）：

| 策略 | 吞吐 (ops/s) | 相对倍数 |
|------|-------------|---------|
| `no` | 182,149 | 1.000x |
| `everysec` | 186,916 | **1.026x** |
| `always` | 4,269 | **0.023x（慢 43 倍）** |

**延迟实测**（P50）：

| 策略 | P50 延迟 |
|------|---------|
| `no` | 0.031 ms |
| `everysec` | 0.031 ms |
| `always` | **2.223 ms（约 72 倍）** |

> 📌 **关键洞察**：`everysec` 和 `no` 的吞吐几乎相同（1.026x），因为 fsync 在**后台线程**执行，不在主线程的关键路径上。真正昂贵的是 `always`——它把磁盘 I/O 延迟直接加到了每条命令的响应时间里。
>
> 这也解释了为什么 **`everysec` 是默认且推荐的**：用几乎为零的性能代价，把丢失窗口从"OS 决定的 30 秒"压缩到"约 1 秒"。

### 2.4 断电实测：真实丢多少

用 `kill -9` 模拟宕机（不给 Redis 任何 fsync 机会），在持续写入过程中途杀掉进程：

| 策略 | 已确认写入 | 重启后恢复 | 丢失 |
|------|-----------|-----------|------|
| `no` | 1567 | 1566 | 1 条 |
| `everysec` | 1577 | 1576 | 1 条 |
| `always` | 851 | 851 | **0 条** |

**`always` 的零丢失在本机得到了验证**。

> ⚠️ **实验环境说明**：WSL 的文件系统写回策略比真实 Linux 激进，`no` 策略只丢了 1 条。**不要把这个数字当成生产环境的保证**——真实 Linux 上 `always` 丢 0 条，`everysec` 丢约 1 秒，`no` 可能丢 30 秒以上。这个实验的价值在于验证 **`always` 确实能零丢失**，而不是给出精确的丢失量。
> 完整脚本见 `playground/prep-lesson-05-loss.sh`。

### 2.5 AOF 重写

AOF 记录每条命令，文件会无限膨胀。**AOF 重写**创建一个体积最小的新 AOF：

- 不是分析旧 AOF，而是**读取当前数据库状态**
- 一个 key 用一条命令表示最终值（如 `SET key final_value`）
- 由 fork 出的子进程执行（同样有 fork + COW 代价）

实测：

```bash
# 对同一个 key 写入 10000 次
重写前：9.41 MB（dbsize 只有 4）
重写后：0.00 MB
# hotkey 的值仍是最后写入的 value-10000
```

触发方式：

```bash
BGREWRITEAOF    # 手动
```

自动触发条件（**两个都要满足**）：

```
auto-aof-rewrite-percentage 100   # 比上次重写后增长 100%
auto-aof-rewrite-min-size 64mb    # 且至少 64 MB
```

### 2.6 混合持久化（Redis 7+ 默认）

`aof-use-rdb-preamble yes` 开启后，AOF 重写的 base 文件用 **RDB 二进制格式** 存储，后面才追加 AOF 格式的增量命令。

```
┌─────────────────────┬──────────────────────┐
│  RDB 格式全量数据    │  AOF 格式增量命令      │
│  （加载快、体积小）  │  （低丢失窗口）        │
└─────────────────────┴──────────────────────┘
         ↑                        ↑
   重启时直接加载           重启时重放少量命令
```

好处：**既有 RDB 的加载速度，又有 AOF 的低丢失窗口**。

本课实测（30 万个 key）：

| 方式 | 磁盘占用 | 启动到可服务 |
|------|---------|-------------|
| RDB | 6.94 MB | 133 ms |
| 纯 AOF（关闭混合） | **13.71 MB** | **226 ms** |
| 混合（默认） | **6.94 MB** | **131 ms** |

混合持久化在体积和加载速度上都**追平了纯 RDB**，同时保留了 AOF 的 1 秒丢失窗口。这就是它成为 Redis 7+ 默认的原因。

> 📌 Redis 8.10.1 实测默认配置：`aof-use-rdb-preamble yes`、`appendonly no`、`appendfsync everysec`。

### 2.7 重启加载：AOF 优先

**当 RDB 和 AOF 同时存在时，Redis 加载 AOF**——因为 AOF 的数据通常更完整。

本课实测验证：

```bash
SET shared:key "in-both"
BGSAVE                          # RDB 含 shared:key
SET aof:only "I-am-AOF-only"    # 只有 AOF 有这条
# 重启后
# dbsize: 2
# shared:key = in-both
# aof:only  = I-am-AOF-only   ✅
```

> ⚠️ **实测踩坑**：我第一次测出"RDB 优先"的错误结论，原因是**重启时忘了加 `--appendonly yes`**，AOF 根本没被加载。这是一个真实的运维陷阱——**如果配置文件里没开 appendonly，重启后 AOF 文件会被完全忽略**，你会莫名其妙丢掉最新数据。
> 完整脚本见 `playground/prep-lesson-05-restart.sh`。

### 2.8 完整脚本

> 📌 完整脚本：`playground/prep-lesson-05-aof.sh`（multi-part 结构、写后日志验证）、`prep-lesson-05-fsync.sh`（三种策略吞吐，三轮取中位数）、`prep-lesson-05-latency.sh`（延迟分布）、`prep-lesson-05-restart.sh`（加载优先级）、`prep-lesson-05-loss.sh`（断电丢数据）。

---

## 知识点 3：持久化选型决策

### 3.1 四种方案的量化对比

本课实测（30 万 key 数据集）：

| 方案 | 磁盘占用 | 启动速度 | 丢失窗口 | 适用场景 |
|------|---------|---------|---------|---------|
| **关闭持久化** | 0 | **10 ms** | **全部丢失** | 纯缓存，数据可重建 |
| **RDB** | 6.94 MB | 133 ms | 快照间隔（分钟级） | 备份、可容忍丢失 |
| **纯 AOF** | 13.71 MB | 226 ms | 1 秒（everysec） | 需要低丢失，但不用混合 |
| **混合（推荐）** | **6.94 MB** | **131 ms** | **1 秒（everysec）** | 绝大多数生产场景 |

**混合持久化是最优解**：它同时拿到了 RDB 的体积/速度优势和 AOF 的低丢失窗口。

### 3.2 决策树

```
先问：这份数据丢了会怎样？
│
├─ 丢了无所谓（纯缓存，能从 DB 重建）
│   └─ ✅ 关闭持久化
│       save ""
│       appendonly no
│       → 省掉 fork 开销、COW 内存风险、磁盘 I/O
│
├─ 丢了很麻烦，但可以接受几分钟
│   └─ ✅ RDB
│       save 900 1        （15 分钟一次，按需调整）
│       appendonly no
│       → 适合做「备份」，加载快、文件小
│
└─ 丢了会造成业务损失
    └─ ✅ 混合持久化（RDB + AOF）
        appendonly yes
        aof-use-rdb-preamble yes
        appendfsync everysec     （默认，平衡）
        │
        └─ 能接受 43 倍性能下降换零丢失？
            └─ appendfsync always
               （仅限金融/交易等极少数场景）
```

### 3.3 三条选型铁律

**铁律 1：纯缓存就该关掉持久化**

这是本课最重要的决策，比任何参数调优都重要。

如果 Redis 里的数据**能从数据库重建**（典型缓存场景），持久化就是纯粹的负担：

- 白白承担 fork 阻塞、COW 内存翻倍、磁盘 I/O 的代价
- 换来一个你根本不需要的"恢复能力"

```bash
# 关闭 RDB
config set save ""
# 关闭 AOF
config set appendonly no
```

**铁律 2：内存要按"峰值"规划，不是按"稳态"**

如果你的 Redis 用了 6 GB，机器有 8 GB，**这是不够的**。COW 峰值可能让物理内存冲到 12 GB。

Redis 官方的建议（核查于 2026-09）：*keep maxmemory well under half of physical RAM if you persist with RDB/AOF-rewrite under write load*。

实操建议：
- `maxmemory` 设为物理内存的 **50%~60%**
- 或者**把持久化放到从库**——从库没有业务写入，COW 几乎为零

**铁律 3：生产环境必配的两个内核参数**

```bash
# 1. 允许 fork 在内存紧张时成功
sysctl vm.overcommit_memory=1

# 2. 关闭透明大页（否则 COW 代价放大 512 倍）
echo never > /sys/kernel/mm/transparent_hugepage/enabled
```

本课实测本机：`overcommit_memory=0`（需要改）、THP=`madvise`（需要改成 never）。

### 3.4 混合持久化的推荐配置

```conf
# /etc/redis/redis.conf

# ---- AOF（主持久化）----
appendonly yes
appendfilename "appendonly.aof"
appendfsync everysec
aof-use-rdb-preamble yes          # Redis 7+ 默认，混合持久化

# AOF 重写触发（两个条件都满足才触发）
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb

# 重写期间不暂停 fsync（默认 no，保持数据安全）
no-appendfsync-on-rewrite no

# ---- RDB（备份用）----
save 3600 1 300 100 60 10000      # 默认策略，作为兜底备份
dbfilename dump.rdb
rdbcompression yes
rdbchecksum yes

# BGSAVE 失败时停止接受写入（保护机制，避免你以为数据存了其实没存）
stop-writes-on-bgsave-error yes
```

### 3.5 完整脚本

> 📌 完整脚本：`playground/prep-lesson-05-load.sh`（RDB/纯AOF/混合的磁盘与加载速度横评）。

```bash
bash playground/prep-lesson-05-load.sh
```

---

## 第四幕：实操验证 —— 跟着做一遍

### 实验 1：亲眼看到 COW 让内存涨 2 倍

```bash
bash playground/prep-lesson-05-cow3.sh
```

你会看到：不写入时 1.00x，持续写入时 2.15x，高强度写入时 3.37x。

如果想手动验证，核心步骤是：

```bash
# 1. 造数据（200 个 key，每个 value 约 1MB）
python3 -c "
for i in range(1, 201):
    val = 'x' * (1024*1024)
    print('*3\r\n\$3\r\nSET\r\n\$%d\r\nk:%d\r\n\$%d\r\n%s\r\n' % (len('k:%d'%i), i, len(val), val))
" | redis-cli --pipe

# 2. 后台高频监控物理内存（关键：用 VmRSS 不是 used_memory）
PID=$(redis-cli info server | grep -oP '(?<=^process_id:)\d+')
( for i in $(seq 1 250); do
    awk '/^VmRSS:/{print $2}' /proc/$PID/status
    sleep 0.03
  done ) > /tmp/mem.txt &

# 3. BGSAVE + 持续写入（让写入贯穿整个快照周期）
redis-cli bgsave
for r in $(seq 1 8); do
  python3 -c "
for i in range(1, 201):
    val = 'y$r' * (512*1024)
    print('*3\r\n\$3\r\nSET\r\n\$%d\r\nk:%d\r\n\$%d\r\n%s\r\n' % (len('k:%d'%i), i, len(val), val))
" | redis-cli --pipe
done

# 4. 看峰值
sort -n /tmp/mem.txt | tail -1
```

> 💡 直接跑 `bash playground/prep-lesson-05-cow3.sh` 更省事，上面的代码是为了让你看清每一步在做什么。

### 实验 2：感受 always 慢 43 倍

```bash
bash playground/prep-lesson-05-fsync.sh
```

注意观察：`everysec` 的吞吐和 `no` 几乎一样（1.026x），但 `always` 掉到 0.023x。延迟 P50 从 0.031 ms 涨到 2.223 ms。

### 实验 3：验证 AOF 只记录成功的命令

```bash
# 在 Redis 的工作目录（dir 配置指向的目录）下操作
cd /tmp/redis-l05-demo

redis-cli config set appendonly yes
redis-cli set badkey "before"
redis-cli rpush badkey "x"           # 报错 WRONGTYPE，执行失败

# 查看 AOF 中是否有 RPUSH
grep -c RPUSH appendonlydir/*.incr.aof   # -> 0（失败的命令不记录）
```

如果你的 `dir` 配置不同，用这条命令查看实际路径：

```bash
redis-cli config get dir
```

### 实验 4：混合持久化的加载优势

```bash
bash playground/prep-lesson-05-load.sh
```

对比 RDB(133ms) / 纯AOF(226ms) / 混合(131ms) 的启动速度。

---

## 第五幕：体系收束 —— 本课与前后课的联系

### 持久化在 Redis 全局中的位置

```
阶段 1：为什么需要 Redis（慢）
    ↓
阶段 2：数据结构与命令（怎么用）
    ↓
阶段 3：持久化与高可用 ← 你在这里
    ├─ 课 5：RDB 与 AOF   （单机数据不丢）
    └─ 课 6：主从复制与哨兵（机器挂了服务不停）
    ↓
阶段 4：分布式与生产实践（不够用）
```

**本课解决的是"单机断电不丢数据"，下一课解决的是"机器挂了服务不停"。**

注意两者的区别：
- 持久化 → 进程重启后，数据还在
- 高可用 → 机器挂了，另一台能顶上

**持久化不能替代高可用**：如果磁盘坏了，或者整个机房断电，再好的持久化也没用。

### 与阶段 2 的联系

课 3、课 4 讲过的编码优化（listpack / intset / skiplist）在 RDB 里会被序列化成不同的存储格式。本课实测 30 万 key 的 RDB 只有 6.94 MB，正是因为这些紧凑编码 + LZF 压缩的功劳。

### 与课 6 的联系（预告）

下一课会讲主从复制。这里先埋一个伏笔：

**主从全量复制时，主库也要执行 `BGSAVE`** —— 意味着本课讲的 fork 阻塞、COW 内存放大，在复制场景同样会发生。如果你在课 5 没搞懂 COW，课 6 遇到"主库内存突然翻倍"时会无从下手。

另一个伏笔：**异步复制会丢数据**。主库写成功就返回，还没传给从库就挂了，这部分数据永久丢失。**哨兵解决的是"服务可用性"，不解决"数据不丢失"**——这正是本课讲的持久化要解决的问题。

### 本课必须记住的五个数字

| 数字 | 含义 |
|------|------|
| **1.00x / 2.15x / 3.37x** | BGSAVE 期间不写入 / 持续写入 / 高强度写入的物理内存放大（实测） |
| **43 倍** | `appendfsync always` 相对 `no` 的性能损失（实测 0.023x） |
| **512 倍** | THP 把单次 COW 复制量从 4 KB 放大到 2 MB 的倍数 |
| **1 秒** | `appendfsync everysec` 的丢失窗口 |
| **131 ms vs 226 ms** | 混合持久化 vs 纯 AOF 的启动耗时（30 万 key，实测） |

---

## 常见误区

### 误区 1："BGSAVE 完全不阻塞主线程"

**错**。`fork()` 那一瞬间主线程是**完全阻塞**的，需要复制页表。实测 481 MB 数据集 fork 耗时 3.20 ms；生产环境几十 GB 时可达几百毫秒甚至 1 秒。

正确的说法是"**BGSAVE 只在 fork 瞬间阻塞，之后主线程继续服务**"。

### 误区 2："BGSAVE 时内存会涨到两倍"

**不准确**。COW 只复制被修改的页。实测：**不写入时 1.00x（完全不涨）**，持续写入 2.15x，高强度写入 3.37x。

准确说法是"**快照期间修改越多，内存涨得越多，最坏情况接近两倍甚至更多**"。

### 误区 3："开启了 AOF 就不会丢数据"

**错**。默认 `appendfsync everysec` 的丢失窗口是约 1 秒。只有 `always` 才能做到零丢失，代价是 43 倍性能损失。

而且——**如果配置文件里没开 `appendonly`，重启时 AOF 会被完全忽略**（本课实测踩过这个坑）。

### 误区 4："AOF 存的是数据"

**错**。AOF 存的是**命令**（RESP 协议格式）。所以同一个 key 修改 1 万次，AOF 就有 1 万条记录，需要重写才能压缩。

### 误区 5："AOF 文件越大，恢复越慢，所以 AOF 不好"

**不完整**。Redis 7+ 默认开启混合持久化（`aof-use-rdb-preamble yes`），base 部分是 RDB 二进制格式。实测混合持久化 6.94 MB / 131 ms，**比纯 AOF 的 13.71 MB / 226 ms 更好**，甚至略优于纯 RDB。

### 误区 6："生产环境一定要开持久化"

**错**。如果数据能从数据库重建（纯缓存场景），**应该关掉持久化**——省掉 fork 阻塞、COW 内存风险和磁盘 I/O。这是本课最重要的选型决策。

---

## 本课小结

| 知识点 | 核心结论 |
|--------|---------|
| RDB fork 与写时复制 | `BGSAVE` fork 子进程写快照，仅 fork 瞬间阻塞（481MB→3.20ms）；COW 只复制被修改的页，实测不写入 1.00x / 持续写入 2.15x / 高强度 3.37x；丢失窗口 = 快照间隔，分钟级 |
| AOF 写后日志与刷盘策略 | 先执行成功再记录（失败命令不入 AOF）；`always`/`everysec`/`no` 实测吞吐 4269/186916/182149 ops/s，`always` 慢 43 倍但零丢失；`everysec` 与 `no` 性能持平（1.026x）却把窗口从 30 秒压到 1 秒 |
| 持久化选型决策 | 纯缓存关闭持久化（启动 10ms）；混合持久化（RDB+AOF）兼顾体积 6.94MB、速度 131ms、窗口 1 秒，是生产首选；内存按峰值规划（maxmemory ≤ 物理内存 50-60%），必配 `overcommit_memory=1` 与关闭 THP |

---

## 📝 本课小测

**Q1**：关于 `BGSAVE` 的阻塞行为，下列说法正确的是？
- A. `BGSAVE` 全程在后台执行，主线程完全不受影响
- B. `BGSAVE` 只在 `fork()` 那一瞬间阻塞主线程，之后主线程继续服务
- C. `BGSAVE` 和 `SAVE` 的阻塞行为完全一样，只是名字不同
- D. `BGSAVE` 命令返回时，代表 RDB 文件已经写完

<details><summary>答案与解析</summary>

**答案：B**。

A 错——`fork()` 需要复制页表，这一瞬间主线程完全阻塞（实测 481 MB 数据集 3.20 ms，生产大实例可达数百毫秒甚至 1 秒）；C 错——`SAVE` 是主线程全程写文件、完全阻塞，生产禁用；D 错——`BGSAVE` 返回只代表"已发起"（实测返回 3.62 ms），不代表完成，要用 `INFO persistence` 的 `rdb_bgsave_in_progress` 判断。

</details>

**Q2**：关于 RDB 快照期间的内存变化，下列说法正确的是？
- A. 无论是否写入，内存都会涨到接近两倍
- B. COW 只复制被修改的内存页，快照期间不写入则内存几乎不涨
- C. 内存涨幅与写入量无关，只与数据集大小有关
- D. 开启 THP（透明大页）可以显著减少 COW 的内存复制量

<details><summary>答案与解析</summary>

**答案：B**。本课实测（基线 210 MB）：不写入 **1.00x**、持续写入 **2.15x**、高强度写入 **3.37x**。

A 错——不写入时完全不涨；C 错——涨幅取决于快照期间修改了多少页；D 错——**恰好相反**，THP 把页从 4 KB 变成 2 MB，改 1 个字节也要复制 2 MB，代价放大 **512 倍**，生产应设为 `never`。

</details>

**Q3**：关于 AOF 的三种刷盘策略，下列说法**错误**的是？
- A. `always` 每条命令同步 fsync，实测吞吐只有 `no` 的约 2.3%，换取近乎零的丢失窗口
- B. `everysec` 由后台线程每秒 fsync 一次，实测吞吐与 `no` 几乎相同（1.026x）
- C. `no` 完全不调用 fsync，性能最好且数据同样安全
- D. `everysec` 是默认策略，丢失窗口约 1 秒

<details><summary>答案与解析</summary>

**答案：C**。`no` 策略下 Redis 不主动 fsync，交给操作系统决定（Linux 通常每 30 秒刷盘），**丢失窗口最大**，仅适用于数据可丢失的缓存场景。

A 对——实测 `always` 吞吐 4269 ops/s，是 `no`(182149) 的 0.023x；`always` 的设计语义是"命令返回前已 fsync 落盘"，因此宕机最多丢 0 条（kill -9 实测也验证了这点）。但要注意：WSL 环境下 `no` 策略同样只丢 1 条，这是环境特性，不代表生产环境 `no` 也安全。
B 对——实测 `everysec` 186916 vs `no` 182149，比值 1.026x，因为 fsync 在后台线程；
D 对——`everysec` 是 Redis 默认值也是官方推荐值。

</details>

**Q4**：某 Redis 实例用于纯缓存，数据全部可从 MySQL 重建。最合适的持久化配置是？
- A. `appendonly yes` + `appendfsync always`，确保零丢失
- B. `appendonly yes` + `appendfsync everysec`，用混合持久化
- C. 关闭持久化：`save ""` + `appendonly no`
- D. 保留默认配置不动（RDB 默认开启）

<details><summary>答案与解析</summary>

**答案：C**。纯缓存场景（数据可从 DB 重建）应该**关闭持久化**，省掉 fork 阻塞、COW 内存翻倍风险、AOF 磁盘 I/O 三重代价。实测无持久化启动仅 **10 ms**。

A 错——零丢失对可重建的缓存毫无意义，却要付出 43 倍性能损失；B 错——同理，混合持久化是为"丢了会造成业务损失"的场景设计的；D 错——默认 RDB 仍在定期 fork，白白承担 COW 内存风险。

**这是本课最重要的选型决策**：判断"这份数据丢了会怎样"，比调优任何参数都重要。

</details>

**Q5**：关于 Redis 7+ 的混合持久化（`aof-use-rdb-preamble yes`），下列说法正确的是？
- A. 混合持久化的磁盘占用比纯 AOF 更大，因为同时存了 RDB 和 AOF
- B. 混合持久化的 AOF 文件中，base 部分是 RDB 二进制格式，incr 部分是 AOF 命令格式
- C. 开启混合持久化后，RDB 和 AOF 会各存一份完整数据，磁盘占用翻倍
- D. Redis 重启时优先加载 RDB，因为 RDB 文件更小

<details><summary>答案与解析</summary>

**答案：B**。混合持久化的 AOF 由三部分组成（Redis 7+ multi-part）：`base`（RDB 格式全量）、`incr`（AOF 格式增量）、`manifest`（索引）。重启时先加载 RDB 格式的 base，再重放少量 incr 命令。

A 错——实测混合 6.94 MB，纯 AOF 13.71 MB，**混合反而更小**，因为 base 用二进制 RDB 格式比命令文本紧凑；C 错——不是存两份，base 和 incr 是**互补**关系（全量+增量）；D 错——**AOF 优先**（本课实测验证），因为 AOF 数据通常更完整。

</details>

---

## 🚀 下一批接力提示词

> 学完本课，**复制下面这段文字发给 AI**，即可无缝进入下一批（无需重新描述上下文）：

```
继续学 Redis。我的学习档案在 redis/00-学习档案.md，
刚学完阶段 3《持久化与高可用》的课 5《RDB 与 AOF 持久化》知识点「RDB fork 与写时复制、AOF 写后日志与刷盘策略、持久化选型决策」，
请按大纲继续讲解阶段 3 的课 6《主从复制与哨兵》的知识点：全量与增量复制、哨兵故障转移、哨兵解决不了的丢数据。
```

## 🧭 课程导航

⬅️ **上一课**：[课 4：Set、ZSet 与特殊类型](../../2-数据结构与命令/lessons/lesson-04-Set、ZSet与特殊类型.md)

➡️ **下一课**：课 6：主从复制与哨兵（待编写）

📚 **返回目录**：[课程目录](../../02-课程目录.md)
