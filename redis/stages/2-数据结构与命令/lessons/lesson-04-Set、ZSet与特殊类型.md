# 课 4：Set、ZSet 与特殊类型

> 阶段 2《数据结构与命令》第 2 课
> 前置：课 3《List 与 Hash》(List 双向操作、List 当队列的三个硬伤、Hash vs String+JSON)
> 环境：WSL Ubuntu 24.04 + Redis 8.10.1（本机实测，核查于 2026-09）

---

## 本课要解决的三个问题

课 3 结束时你掌握了两种"容器"：List 是**有序可重**的序列，Hash 是**字段-值**的对象。但在真实业务里，还有三类需求它们都满足不了：

1. **"这两个标签群的共同用户是谁？"** —— List 求交集要写双重循环，O(N×M) 搬到客户端做，网络传输先撑爆
2. **"实时排行榜，第 3 名是谁？"** —— List 按下标取是 O(N)，Hash 根本没有顺序概念
3. **"1 亿用户的日活，内存装得下吗？"** —— Set 存 1 亿个 userId 需要约 3 GB

这三个问题，分别对应本课的 Set、ZSet、特殊类型。

---

## 第一幕：场景引入 —— 三个真实困境

### 困境一：共同好友，客户端算到超时

产品提了个需求："展示我和 TA 的共同好友"。你的第一反应是用 List 存好友，然后在应用代码里求交集：

```python
my_friends = redis.lrange("friends:1001", 0, -1)   # 假设 500 人
ta_friends = redis.lrange("friends:1002", 0, -1)   # 假设 800 人
common = set(my_friends) & set(ta_friends)          # 客户端做交集
```

这段代码能跑，但有三个问题：**1300 个成员的两次全量传输**（网络开销）、**应用服务器承担计算**（本来 Redis 的 CPU 闲着）、**并发时重复计算**（同样的好友对每天被算几万次）。

如果 Redis 能直接返回交集呢？

### 困境二：排行榜，每次取 Top10 都要全表扫描

游戏排行榜，100 万玩家，实时更新分数。用 List 存的话：

```bash
LPUSH leaderboard "玩家A:5200"   # 插入无序
LRANGE leaderboard 0 9            # 取不到"分数最高的10个"，只能取"最新插入的10个"
```

List 只有**插入顺序**，没有**分数顺序**。你需要在客户端取出 100 万条、排序、取前 10——每次刷新页面都做一次。

### 困境三：日活统计，内存先撑不住

要统计每天的独立访客（DAU）。用 Set：

```bash
SADD uv:2026-09-01 "user12345"
SCARD uv:2026-09-01
```

精确、简单。但当日活是 1 亿时，这个 Set 大约消耗 **3 GB 内存**（按本课实测的每成员约 32 字节推算）。而你要存 30 天的数据做趋势分析……

---

## 第二幕：认知冲突 —— 三个"想当然"的崩塌

### 冲突一：Set 的编码不是"一种"

你可能听过"Set 底层是 intset 或 hashtable"。但在 Redis 8 里实测一下：

```bash
SADD s:int 1 2 3
OBJECT ENCODING s:int
# intset

SADD s:str "hello" "world"
OBJECT ENCODING s:str
# listpack          <-- 咦？不是 hashtable
```

**Set 有三条编码路径，而不是两条**：

| 条件 | 编码 | 实测触发点 |
|------|------|-----------|
| 全是整数 且 数量 ≤ 512 | `intset` | 512 个整数仍是 intset |
| 全是非整数字符串 且 数量 ≤ 128 且 每个 ≤ 64 字节 | `listpack` | 128 个字符串仍是 listpack |
| 其他 | `hashtable` | 513 个整数 / 129 个字符串 |

实测证据（本机 Redis 8.10.1）：

```bash
# 整数路径（set-max-intset-entries=512）
100 个整数  -> intset
512 个整数  -> intset       <-- 阈值边界
513 个整数  -> hashtable    <-- 超一个就转

# 字符串路径（set-max-listpack-entries=128）
100 个字符串 -> listpack
128 个字符串 -> listpack     <-- 阈值边界
129 个字符串 -> hashtable    <-- 超一个就转
```

而且这个转换**不可逆**——你把 600 个整数删到只剩 99 个，编码仍然是 `hashtable`：

```bash
SADD s:irr 1..600        # -> hashtable
SREM s:irr 100..600      # 删到只剩 99 个
OBJECT ENCODING s:irr    # -> hashtable（不会转回 intset）
```

> ⚠️ **和课 3 的 Hash 是同一个道理**：Hash 超过 `hash-max-listpack-entries` 也会不可逆退化。这是 Redis 内存优化的统一套路——**小数据用紧凑编码省内存，大数据用哈希/跳表保性能，一旦升级不回头**。

还有一个容易踩的坑：**整数集合里混进一个长字符串，会立即退化**：

```bash
SADD s:mix 1 2 3 4 5 6 7 8 9 10
OBJECT ENCODING s:mix        # intset
SADD s:mix "<70字节的字符串>"
OBJECT ENCODING s:mix        # hashtable   <-- value 超 64 字节，直接转
```

### 冲突二：交并差的性能差距，是 5934 倍

同样是对两个 Set 做集合运算，SINTER 和 SUNION 的性能差了**三个数量级**。本机实测（big=100 万成员，small=100 成员）：

| 命令 | 单次耗时 | 相对倍数 |
|------|---------|---------|
| `SINTER big small` | 0.0525 ms | 1x |
| `SINTER small big` | 0.0520 ms | **1x（参数顺序无关！）** |
| `SUNION big small` | 311.5 ms | **5934x** |

为什么差这么多？因为 **SINTER 只遍历最小的那个集合**，拿它的每个成员去其他集合里做 O(1) 的哈希查找：

```
SINTER big(100万) small(100)
  → Redis 内部按基数排序，选 small 作为遍历基准
  → 遍历 100 个成员，每个去 big 里查一次（O(1)）
  → 总共 100 次查找，而非 100 万次
```

而 SUNION **必须遍历所有集合的所有成员**（并集需要每个元素至少看一眼），所以是 O(N总)。

> 📌 **参数顺序不影响 SINTER 性能**——Redis 内部会自动重排。这个实测结论（0.0525ms vs 0.0520ms）值得记住，因为很多资料会说"要把小集合放前面"，那是错的。

但 **SDIFF 是方向敏感的**，而且敏感的是**结果**不是性能：

```bash
SADD tag:A u1 u2 u3 u4
SADD tag:B u3 u4 u5 u6

SDIFF tag:A tag:B   # -> u1 u2      (A 有 B 没有)
SDIFF tag:B tag:A   # -> u5 u6      (B 有 A 没有)
```

### 冲突三：ZSet 不是"排序的 Set"，而是两套结构叠在一起

面试高频题："ZSet 底层是什么？"标准答案是"跳表+哈希表"。但这八个字背后有个关键问题：**为什么要两套？一套不行吗？**

不行。因为它们解决的是**两个方向的查询**：

| 查询方向 | 例子 | 需要的结构 | 复杂度 |
|---------|------|-----------|--------|
| 按**成员**查分数 | `ZSCORE lb 张三` | 哈希表 | O(1) |
| 按**分数**查排名/范围 | `ZREVRANK lb 张三`、`ZRANGE lb 0 9` | 跳表 | O(logN) + M |

只用跳表，`ZSCORE` 要 O(logN)；只用哈希表，根本排不了序。**两套结构共享同一份 member+score 数据**（通过指针），不是存两份，所以内存代价是可接受的。

---

## 第三幕：层层揭示 —— 三个知识点

## 知识点 1：Set 交并差与去重

### 1.1 去重：SADD 天然幂等

```bash
SADD uv:page:1 u1 u2 u3
SADD uv:page:1 u2 u3 u4    # 重复加入 u2 u3
SCARD uv:page:1            # -> 4（不是 6）
SMEMBERS uv:page:1         # -> u1 u2 u3 u4
```

`SADD` 返回的是**新增成功的数量**，不是集合总量：

```bash
SADD uv:page:1 u1 u2 u3     # -> 3（新增 3 个）
SADD uv:page:1 u2 u3 u4     # -> 1（只有 u4 是新的，u2/u3 已存在）
```

上面第二条命令返回 **1** 而不是 3，因为 u2、u3 已经在集合里了，只有 u4 是新成员。用这个返回值可以判断"这次操作是否真的改变了集合"——比如做幂等去重时，返回 0 说明之前已经处理过。

这就是 Set 的核心价值：**去重这件事 Redis 帮你做了，而且是 O(1)**。对比一下，如果用 List，你得先 `LRANGE` 全部取出、在客户端判断、再 `RPUSH`。

### 1.2 交并差三件套

```bash
SADD tag:A u1 u2 u3 u4
SADD tag:B u3 u4 u5 u6

SINTER tag:A tag:B   # 交集 -> u3 u4
SUNION tag:A tag:B   # 并集 -> u1 u2 u3 u4 u5 u6
SDIFF  tag:A tag:B   # 差集 -> u1 u2     (A - B)
SDIFF  tag:B tag:A   # 差集 -> u5 u6     (B - A，结果不同！)
```

**复杂度对照表**（官方定义 + 本课实测）：

| 命令 | 复杂度 | N 的含义 | 实测（100万+100） |
|------|--------|---------|------------------|
| `SINTER` | O(N×M) | N=最小集合基数，M=集合个数 | 0.052 ms |
| `SUNION` | O(N) | N=所有集合元素总数 | 311.5 ms |
| `SDIFF` | O(N) | N=所有集合元素总数 | 与大集合相关 |
| `SINTERCARD` | O(N×M) | 同 SINTER，但只返回计数 | 省网络传输 |

### 1.3 SINTER 与 SINTERSTORE：返回值完全不同

这是新手最常踩的坑：

```bash
SINTER tag:A tag:B           # 返回成员列表：1) "u3"  2) "u4"
SINTERSTORE dest tag:A tag:B # 返回的是"结果基数"：2
```

`SINTERSTORE` 把结果存到 `dest`，然后返回**存了多少个元素**。如果你想拿成员，得再 `SMEMBERS dest`。

**还有个更危险的覆盖行为**：

```bash
SET dest:str "i-am-a-string"        # dest:str 是 String 类型
SINTERSTORE dest:str tag:A tag:B    # 用它当交集结果的目标 key
TYPE dest:str                        # -> set   <-- String 被覆盖了！
```

`*STORE` 系列命令**无条件覆盖目标 key**，不管它原来是什么类型。如果结果为空，还会**直接删除目标 key**（而不是留一个空 Set）。

### 1.4 随机抽取：SRANDMEMBER vs SPOP

两个命令都能"随机拿元素"，但一个删一个不删：

```bash
SADD pool a b c d e
SCARD pool              # 5

SRANDMEMBER pool 2      # 返回 2 个随机成员
SCARD pool              # 5   <-- 没删

SPOP pool 2             # 返回并"移除" 2 个随机成员
SCARD pool              # 3   <-- 删了
```

应用场景：抽奖用 `SPOP`（中奖后不能再中），随机展示用 `SRANDMEMBER`（每次刷新换一批，但池子不变）。

> 💡 **SRANDMEMBER 的 count 可以是负数**——正数表示"不重复地取 N 个"，负数表示"允许重复地取 |N| 个"。这个细节在做"随机推荐可能重复"时有用。

### 1.5 完整脚本

> 📌 完整脚本已备好：`playground/prep-lesson-04-set.sh` 和 `playground/prep-lesson-04-set-enc.sh`，会跑完上述全部实验（去重、交并差、SINTERSTORE 覆盖、编码阈值与不可逆性）并打印结论。

```bash
bash playground/prep-lesson-04-set.sh
bash playground/prep-lesson-04-set-enc.sh
```

---

## 知识点 2：ZSet 跳表 + 哈希表双结构

### 2.1 成员唯一，但分数可覆盖

和 Set 一样，ZSet 的 member 是唯一的；和 Set 不同的是，每个 member 带一个 score：

```bash
ZADD z:rank 100 alice
ZADD z:rank 200 alice      # 同一个 member，不同 score
ZCARD z:rank               # -> 1（不是 2）
ZSCORE z:rank alice         # -> 200（被覆盖更新了）
```

对比课 3 的 List：

```bash
RPUSH l:rank alice
RPUSH l:rank alice
LLEN l:rank                # -> 2   <-- List 允许重复
```

**这就是 ZSet 适合排行榜的根本原因**：同一个玩家反复刷新分数，不会在榜上出现两次。

### 2.2 分数相同时，按字典序排

```bash
ZADD z:tie 100 banana 100 apple 100 cherry
ZRANGE z:tie 0 -1
# -> apple, banana, cherry    <-- 同分按成员字典序
```

这个规则在实现"同分按加入时间排序"时会成为障碍——因为字典序和你想要的时间序无关。解决方案是把时间戳编码进 score（如 `score = 分数 * 1e10 + (1e10 - 时间戳)`）。

### 2.3 双结构如何各司其职

```
        ZSET (skiplist 编码)
        ┌─────────────────────────┐
        │   dict: member -> score │ ← ZSCORE 走这里，O(1)
        │   skiplist: 按 score 有序│ ← ZRANGE/ZRANK 走这里，O(logN)
        │   两者共享 member+score 数据（指针，不重复存储）
        └─────────────────────────┘
```

**跳表长什么样**（Redis 实现）：

- 最底层（Level 1）是完整的**双向有序链表**，包含所有节点
- 上面每层是"快车道"，节点数约为下层的 1/4
- 每个新节点的层数**随机**决定：25% 概率升到下一层，最高 32 层
- 每个前进指针带一个 **span**（跨度），记录跳过了多少节点
- 查找时从最高层往右走，走不动了就下降一层

**span 是排名查询的关键**：`ZRANK`/`ZREVRANK` 之所以是 O(logN)，就是因为在下降过程中把经过的 span 累加起来，直接得到排名，不需要遍历底层链表。

### 2.4 实测：O(1) 与 O(logN) 的证据

这是本课最有说服力的数据。规模从 1 万涨到 500 万（**500 倍**）：

| 命令 | 1 万成员 | 500 万成员 | 增长倍数 | 理论预测 |
|------|---------|-----------|---------|---------|
| `ZSCORE`（哈希表 O(1)） | 1.140 us | 1.663 us | **1.46x** | 1.00x |
| `ZREVRANK`（跳表 O(logN)） | 1.143 us | 1.773 us | **1.55x** | 1.67x |

**N 涨了 500 倍，耗时只涨了约 1.5 倍**。而如果是 O(N)，应该涨 500 倍。

> 📌 **实测方法说明**（这个坑值得单独讲）：
> 我最初用 `redis-cli` 循环计时，得到"所有命令都是 1.5ms"——因为这个 1.5ms 是 **redis-cli 进程启动的固定开销**，完全掩盖了命令本身（微秒级）。
> 改用 `redis-benchmark -c 1` 后，得到"所有命令都是 40us"——这是**本地回环网络 RTT**，还是淹没。
> 想用 Lua 在服务端内部计时？也不行——**Redis 为保证脚本可复制性，Lua 里的 `TIME` 命令在整个脚本执行期间返回同一个固定值**。
> 最终方案是 `redis-benchmark -P 50`（pipeline 打包 50 条命令成一个 TCP 往返），把 RTT 摊薄到 1/50，才测出真实数据。
> 完整脚本见 `playground/prep-lesson-04-bench-pipe.sh` 与 `prep-lesson-04-bench-extreme.sh`。

对比课 3 的 List（同样 pipeline 条件，1 万→100 万）：

| 命令 | 1 万 | 100 万 | 增长 |
|------|------|--------|------|
| `LINDEX`（List O(N)） | 1.44 us | 1.80 us | 1.25x |

咦，LINDEX 是 O(N) 却只涨了 25%？**因为课 3 讲过，Redis 8 的 List 是 quicklist（链表+listpack），LINDEX 会先定位到 listpack 再内部索引**，常数优化得很好。所以**大 List 的真实代价不是单条命令慢，而是内存和整体吞吐**——课 3 的结论依然成立。

### 2.5 ZSet 的内存代价

双结构不是免费的。实测内存占用：

| 结构 | 规模 | 总内存 | 每元素 |
|------|------|--------|--------|
| ZSet | 100 万成员 | 73.43 MB | 77.0 字节 |
| ZSet | 500 万成员 | 425.9 MB | 89.3 字节 |
| List | 100 万元素 | 8.53 MB | 8.9 字节 |

在**同为 100 万**的规模下对比：ZSet 是 **73.43 MB**，List 是 **8.53 MB**，**ZSet 约为 List 的 8.6 倍**。

（补充观察：ZSet 每元素开销随规模从 77.0 字节涨到 89.3 字节，因为成员数增多后跳表节点平均层数上升、指针开销变大。）

> 💡 如果排行榜只有几百人，考虑用 `zset-max-listpack-entries`（默认 128）让它保持在 listpack 编码，能省不少内存。但超过 128 就不可逆地转 skiplist 了。

### 2.6 命令语法：Redis 6.2 后的新旧交替

```bash
# 旧语法（仍可用，但已不推荐）
ZRANGEBYSCORE z:big 1 3

# 新语法（Redis 6.2+ 推荐，功能更强）
ZRANGE z:big 1 3 BYSCORE
ZRANGE z:big 1 100 BYSCORE LIMIT 0 3
```

新版 `ZRANGE` 统一了按排名（`BYRANK`）和按分数（`BYSCORE`）两种模式，还支持 `LIMIT`。**新项目建议直接用 ZRANGE**。

### 2.7 排行榜实战

```bash
ZADD z:lb 3000 张三 5200 李四 4100 王五

# 降序 Top3（真实排行榜）
ZREVRANGE z:lb 0 2 WITHSCORES
# -> 李四 5200, 王五 4100, 张三 3000

# 张三排第几？（从 0 开始，+1 才是真实名次）
ZREVRANK z:lb 张三      # -> 2   即第 3 名

# 给张三加 500 分（原子自增，比"读-改-写"安全）
ZINCRBY z:lb 500 张三
```

> 💡 `ZINCRBY` 的原子性很重要：如果用 `ZSCORE` 读出来、加 500、`ZADD` 写回去，并发时两个请求会互相覆盖。这和课 3 讲的 `HINCRBY` 是同一个道理。

---

## 知识点 3：Bitmap / HyperLogLog / Geo

这三个类型的**共同点**：底层都是别的类型，Redis 只是提供了一组专门的命令。

| 类型 | 底层 | 证据 |
|------|------|------|
| Bitmap | **String** | `SETBIT` 后 `TYPE` 返回 `string` |
| HyperLogLog | **String** | `PFADD` 后 `TYPE` 返回 `string` |
| Geo | **ZSet** | `GEOADD` 后 `TYPE` 返回 `zset` |

### 3.1 Bitmap：本质是 String 的按位操作

```bash
SETBIT sign:2026-09 0 1
TYPE sign:2026-09        # -> string     <-- 就是 String！
STRLEN sign:2026-09      # -> 1 字节

SETBIT sign:2026-09 100 1
STRLEN sign:2026-09      # -> 13 字节     <-- ceil(101/8) = 13
BITCOUNT sign:2026-09    # -> 统计置位的数量
GETBIT sign:2026-09 101  # -> 0（未设置默认 0）
```

**空间优势是压倒性的**。统计 100 万用户（userId 1..1000000）：

| 方案 | 内存 | 精确? | 可取成员? |
|------|------|-------|----------|
| Set | 30.78 MB | 是 | 是 |
| **Bitmap** | **0.13 MB** | 是 | 否（需遍历） |
| HyperLogLog | 0.0137 MB | 否（±0.81%） | 否 |

**Bitmap 相对 Set 省 99.6%**。

**但是——Bitmap 有个致命陷阱**：空间由**最大 offset** 决定，不是元素个数。

```bash
# 只存 10 个元素，但其中一个是 1 亿
SETBIT uv:sparse 1 1 ... SETBIT uv:sparse 9 1
SETBIT uv:sparse 100000000 1
BITCOUNT uv:sparse              # -> 10（只有 10 个元素）
MEMORY USAGE uv:sparse          # -> 14.00 MB ！！！

# 同样的 10 个元素用 Set 存
SADD uv:s10 1 2 ... 9 100000000
MEMORY USAGE uv:s10             # -> 73 字节
```

**10 个元素，Bitmap 占 14 MB，Set 占 73 字节——Bitmap 大了 19 万倍。**

> ⚠️ **选型铁律**：Bitmap 只适合 **ID 连续且密集**的场景（自增 userId、连续日期）。如果 ID 是 UUID、雪花 ID、或者稀疏分布，**不要用 Bitmap**。

**BITOP 做留存分析**：

```bash
# d1 = {1,2,3}, d2 = {2,3,4}
BITOP AND d:both d1 d2     # 两日都来
BITCOUNT d:both            # -> 2（用户 2、3）

BITOP OR d:either d1 d2    # 任一日来
BITCOUNT d:either          # -> 4（用户 1、2、3、4）
```

### 3.2 HyperLogLog：用 12 KB 数 1 亿人

**核心原理**（一句话）：把每个元素哈希成一个 64 位串，看它前导零的长度；分到 16384 个寄存器里，每个寄存器只记"见过的最大前导零数"；最后对所有寄存器取**调和平均数**并做偏差修正。

```
16384 个寄存器 × 6 bit = 98304 bit = 12288 字节 = 12 KB
```

**为什么是 12 KB 封顶**：一个寄存器存的是"最长前导零数"，50 位的哈希值最多 50 个前导零，6 bit（0-63）足够存。**元素再多，寄存器也不会变大**，只会上调自己的最大值。

标准误差 **0.81%**（= 1.04/√16384，Redis 官方值，核查于 2026-09）。

**实测误差**（本机）：

| 真实值 | PFCOUNT | 误差 |
|--------|---------|------|
| 1,000 | 1,006 | -0.60% |
| 10,000 | 9,948 | 0.52% |
| 100,000 | 100,372 | -0.37% |
| 1,000,000 | 1,005,024 | **-0.50%** |

全部在 0.81% 以内。注意误差**可正可负**——HLL 是估计，不是"只多不少"或"只少不多"。

**内存实测**：100 万元素后 `MEMORY USAGE` = 14361 字节（约 14 KB，含 key 开销）。

> 💡 HLL 内部有 **sparse（稀疏）和 dense（密集）两种表示**。元素少时用 sparse（只占几百字节），元素多了自动转 dense（12 KB）。所以小基数时比 12 KB 还省。

**PFMERGE 做多天合并去重**：

```bash
PFADD hll:d1 x1..x5000        # day1: 5000 人
PFADD hll:d2 x2500..x7500     # day2: 5001 人（与 day1 有 2500 重叠）
PFMERGE hll:week hll:d1 hll:d2
PFCOUNT hll:week              # -> 7541（真实去重值 7500，误差 0.55%）
```

**HLL 的本质限制**：只能计数，**取不出成员**。没有 "PFMEMBERS" 这种命令。所以：

- 要"今天有多少独立访客" → HLL ✅
- 要"今天具体哪些人来过" → Set ✅，HLL ❌
- 要"用户 A 今天来过吗" → Set（SISMEMBER）✅，HLL ❌

### 3.3 Geo：地理位置，底层是 ZSet

```bash
GEOADD geo:cities 116.4074 39.9042 北京
GEOADD geo:cities 121.4737 31.2304 上海
TYPE geo:cities              # -> zset    <-- 就是 ZSet！

# 用 ZSet 命令看底层：分数是 geohash 编码的 52 位整数
ZRANGE geo:cities 0 -1 WITHSCORES
# -> 广州 4046533736564473 / 上海 4054803464923741 / 北京 4069885372147137
```

**因为是 ZSet，所以没有 GEODEL，删除要用 `ZREM`**：

```bash
ZREM geo:cities 广州
ZCARD geo:cities             # -> 2
```

**常用命令**：

```bash
GEOPOS geo:cities 北京                          # 取坐标（有精度损失）
GEODIST geo:cities 北京 上海 km                 # 距离 -> 1067.6112 km
GEOSEARCH geo:cities FROMMEMBER 北京 BYRADIUS 1000 km   # 附近搜索
```

**GEORADIUS 已废弃**（Redis 6.2 起，核查于 2026-09），新代码用 `GEOSEARCH`：

```bash
# 废弃（仍可用）
GEORADIUSBYMEMBER geo:cities 北京 1000 km

# 推荐（6.2+，还支持矩形范围 BYBOX）
GEOSEARCH geo:cities FROMMEMBER 北京 BYRADIUS 1000 km
GEOSEARCH geo:cities FROMLONLAT 116.4 39.9 BYBOX 100 100 km
```

**精度说明**（两个必须知道的）：

1. **坐标有损**：GEOADD 时经纬度被编码成 52 位 geohash，GEOPOS 取回来的是解码值，与原值有小误差。实测 `GEOADD 116.4074 39.9042` → `GEOPOS` 返回 `116.40740185976028 39.90420012463195`。
2. **距离是球面近似**：GEODIST 假设地球是完美球体，边缘情况误差可达 **0.5%**。

**纬度限制**：有效纬度是 -85.05112878 到 85.05112878（超出会报错）。这是 Web 墨卡托投影的限制，南北极附近无法索引。

### 3.4 完整脚本

> 📌 完整脚本：`playground/prep-lesson-04-special.sh`（三种特殊类型的全部实验）与 `playground/prep-lesson-04-compare.sh`（Set/Bitmap/HLL 横评 + Bitmap 稀疏陷阱）。

```bash
bash playground/prep-lesson-04-special.sh
bash playground/prep-lesson-04-compare.sh
```

---

## 第四幕：实操验证 —— 跟着做一遍

### 实验 1：验证 Set 的编码转换不可逆

```bash
# 整数路径
SADD s:test 1 2 3
OBJECT ENCODING s:test              # intset

# 加到 513 个（超过 set-max-intset-entries=512）
# 用脚本批量加：bash playground/prep-lesson-04-set-enc.sh
# 或者手动验证：
EVAL "for i=1,513 do redis.call('sadd', KEYS[1], i) end return redis.call('object','encoding',KEYS[1])" 1 s:test2
# -> hashtable

# 再删回 3 个
EVAL "for i=4,513 do redis.call('srem', KEYS[1], i) end return redis.call('object','encoding',KEYS[1])" 1 s:test2
# -> hashtable   <-- 不可逆！
```

### 实验 2：亲眼看到 5934 倍的性能差

```bash
bash playground/prep-lesson-04-sinter.sh
```

你会看到 `SINTER` 是 0.05 ms 级，`SUNION` 是 311 ms 级。**在单线程模型下，311 ms 意味着期间所有其他命令都在排队**。

### 实验 3：Bitmap 稀疏陷阱

```bash
# 正常的密集 Bitmap
SETBIT dense 0 1 ; SETBIT dense 1 1 ; SETBIT dense 2 1
MEMORY USAGE dense          # 很小

# 稀疏的灾难
SETBIT sparse 1 1
SETBIT sparse 100000000 1   # 只加了一个大 offset
MEMORY USAGE sparse         # -> 14.00 MB（理论 100000000/8/1024/1024 ≈ 11.9 MB，实测含 String 对象开销）
```

**对照前面密集场景**：同样 100 万个连续 offset 只占 0.13 MB，而这里 10 个元素就占了 14 MB。

---

## 第五幕：体系收束 —— 选型决策树

### 四种"去重/计数"结构怎么选？

```
需要去重 / 计数 / 判断存在性
│
├─ 需要取出具体成员？ 
│   └─ 是 → Set（唯一选择，可取成员、可 SISMEMBER）
│
└─ 只要数量，不要成员
    │
    ├─ 必须 100% 精确？
    │   ├─ 是 → ID 是否连续密集（自增ID、连续日期）？
    │   │        ├─ 是 → Bitmap（省 99.6%）
    │   │        └─ 否 → 回到 Set（稀疏 ID 用 Bitmap 会爆炸）
    │   │
    │   └─ 否（能接受 ±0.81% 误差）→ HyperLogLog（省 99.96%）
    │
    └─ 还要排序 / 取 TopN？→ ZSet
```

### 五种结构总对照表

| 结构 | 有序? | 可重? | 核心能力 | 典型场景 | 内存代价 |
|------|-------|-------|---------|---------|---------|
| **List** | 插入序 | 是 | 两端 O(1) | 队列、栈、时间线 | 低（8.9 B/元素） |
| **Hash** | 否 | 字段唯一 | 部分读写 | 对象存储 | 低（紧凑编码） |
| **Set** | 否 | 否 | O(1) 去重 + 集合运算 | 标签、共同好友 | 中（32 B/成员） |
| **ZSet** | 分数序 | 成员唯一 | 排名 + 范围查询 | 排行榜、延迟队列 | **高（89 B/成员）** |
| **Bitmap** | 位序 | - | 极致空间 | 连续 ID 签到 | **极低（1 bit/元素）** |
| **HLL** | 否 | - | 12 KB 计数 | DAU/UV 统计 | **固定 12 KB** |
| **Geo** | 空间 | 成员唯一 | 附近搜索 | LBS | 同 ZSet |

### 本课必须记住的五个数字

| 数字 | 含义 |
|------|------|
| **512** | `set-max-intset-entries`，整数 Set 的编码阈值 |
| **128** | `set-max-listpack-entries` / `zset-max-listpack-entries`，紧凑编码阈值 |
| **5934x** | 同等数据下 `SUNION` 比 `SINTER` 慢的倍数（实测） |
| **0.81%** | HyperLogLog 的标准误差（= 1.04/√16384） |
| **12 KB** | HyperLogLog 的内存上限（16384 寄存器 × 6 bit） |

### 与前后课的联系

- **← 课 3**：List 的 quicklist、Hash 的 listpack，和本课 Set 的 intset/listpack、ZSet 的 listpack/skiplist，是**同一套编码优化思路**
- **→ 阶段 3**：RDB 持久化时，这些底层编码会被序列化；`listpack` 和 `skiplist` 的存储格式不同，影响 RDB 文件大小
- **→ 阶段 4**：集群模式下，`SINTER`/`SUNION`/`ZUNIONSTORE`/`PFMERGE` 这些**多 key 命令**会受 hash slot 限制（CROSSSLOT 错误）

---

## 常见误区

### 误区 1："SINTER 要把小集合放前面才快"

**错**。Redis 内部会自动按基数排序，用最小集合作为遍历基准。本课实测：`SINTER big small` 0.0525 ms，`SINTER small big` 0.0520 ms，**几乎相同**。

但 `SDIFF` 的参数顺序**影响结果**（A-B ≠ B-A），这一点要区分清楚。

### 误区 2："Set 底层就是 intset 和 hashtable 两种"

**不完整**。Redis 7.0+ 有三种：`intset`（整数≤512）、`listpack`（字符串≤128 且每个≤64 字节）、`hashtable`。实测 128 个字符串的 Set 是 `listpack`，129 个才是 `hashtable`。

### 误区 3："ZSet 就是'排序的 Set'"

**不准确**。Set 是哈希表单结构，ZSet 是**跳表+哈希表双结构**。这个区别决定了 ZSet 的内存代价是 Set 的数倍（89 B vs 32 B/成员）。

### 误区 4："Bitmap 一定比 Set 省内存"

**只在 ID 连续密集时成立**。本课实测：10 个元素但 offset 到 1 亿，Bitmap 占 14 MB，Set 只占 73 字节。

### 误区 5："HyperLogLog 的误差是'只多不少'"

**错**。HLL 是**估计**，误差可正可负。本课实测：n=1000 时 PFCOUNT=1006（多 0.6%），n=10000 时 PFCOUNT=9948（**少** 0.52%）。

### 误区 6："LINDEX 是 O(N) 所以很慢"（回顾课 3）

课 3 已经澄清过，本课实测再次验证：100 万元素的 List，`LINDEX` 单次仅 1.80 us（1 万时是 1.44 us，只涨 25%）。原因是 quicklist 会先定位 listpack 再内部索引。**大 List 的真实代价是内存，不是单条命令延迟**。

---

## 本课小结

| 知识点 | 核心结论 |
|--------|---------|
| Set 交并差与去重 | SADD 天然 O(1) 去重；SINTER 只遍历最小集合（0.05ms），SUNION 遍历全部（311ms），差 **5934 倍**；Set 有 intset/listpack/hashtable 三编码，转换**不可逆** |
| ZSet 双结构 | 跳表管 O(logN) 排名、哈希表管 O(1) 查分，**共享同一份数据**；N 涨 500 倍，ZSCORE 只涨 1.46x、ZREVRANK 涨 1.55x；代价是 89 B/成员 |
| Bitmap / HLL / Geo | 底层分别是 String/String/ZSet；Bitmap 省 99.6% 但**稀疏 ID 会爆炸**；HLL 固定 12 KB + 0.81% 误差但**取不出成员**；Geo 用 GEOSEARCH（GEORADIUS 已废弃） |

---

## 📝 本课小测

**Q1**：关于 Set 的底层编码，下列说法正确的是？
- A. Set 只有 intset 和 hashtable 两种编码
- B. 全是整数且数量 ≤ 512 时用 intset，全是非整数字符串且 ≤ 128 时用 listpack
- C. 编码转换是可逆的，元素减少后会自动转回紧凑编码
- D. `set-max-listpack-entries` 的默认值是 512

<details><summary>答案与解析</summary>

**答案：B**。实测（Redis 8.10.1）：512 个整数仍是 intset，513 个转 hashtable；128 个字符串仍是 listpack，129 个转 hashtable。

A 错——Redis 7.0+ 有**三种**编码（intset / listpack / hashtable）；C 错——转换**不可逆**，删回 99 个仍是 hashtable；D 错——`set-max-listpack-entries` 默认是 **128**，512 是 `set-max-intset-entries` 的值。

</details>

**Q2**：在生产环境对两个 Set 做集合运算，big 有 100 万成员、small 有 100 个成员。下列说法正确的是？
- A. `SINTER big small` 比 `SINTER small big` 慢很多，应把小集合放前面
- B. `SINTER` 与 `SUNION` 性能接近，因为都是集合运算
- C. `SINTER` 只遍历最小集合，约 0.05 ms；`SUNION` 遍历全部元素，约 311 ms
- D. `SDIFF` 的两个方向性能差异很大

<details><summary>答案与解析</summary>

**答案：C**。本课实测：SINTER 0.0525 ms，SUNION 311.5 ms，相差约 **5934 倍**。

A 错——Redis 内部会按基数自动重排，参数顺序**不影响** SINTER 性能（实测 0.0525 vs 0.0520 ms）；B 错——两者复杂度不同（SINTER 是 O(最小集合×集合数)，SUNION 是 O(总元素数)）；D 错——`SDIFF` 方向敏感的是**结果**（A-B ≠ B-A），不是性能。

</details>

**Q3**：关于 ZSet 的双结构，下列说法**错误**的是？
- A. 哈希表负责按 member 查 score，复杂度 O(1)
- B. 跳表负责按 score 排序与排名，复杂度 O(logN)
- C. 两个结构各存一份 member+score 数据，所以内存占用是单结构的两倍
- D. 跳表节点的层数随机决定，25% 概率升到上一层，最高 32 层

<details><summary>答案与解析</summary>

**答案：C**。两个结构通过**指针共享同一份** member+score 数据，不是存两份。

ZSet 内存高（实测 89.3 B/成员）是因为跳表节点本身要存多层指针、span 字段、后退指针等元数据，以及哈希表条目开销，而不是因为数据存了两份。A、B、D 都是正确描述。

</details>

**Q4**：需要统计 1 亿用户的日活（DAU），下列哪些方案是合理的？（多选）
- A. Set 存 1 亿个 userId——精确且可取成员，但需要约 3 GB 内存
- B. HyperLogLog——约 12 KB 内存，但有 ±0.81% 误差，且取不出成员
- C. Bitmap——只要 userId 是连续自增的整数，约 12.5 MB 内存且精确
- D. HyperLogLog 的误差是"只多不少"，所以可以适当减去一点作为真实值

<details><summary>答案与解析</summary>

**答案：A、B、C**。

A 合理——Set 精确，代价是内存（按本课实测 32 B/成员推算，1 亿约 3 GB）；B 合理——HLL 用 12 KB 换 0.81% 误差，适合只要数字的分析场景；C 合理——Bitmap 在 ID 连续时精确且极省（1 亿 bit 的**理论位容量**是 1e8/8/1024/1024 ≈ 11.9 MB；本课实测 100 万连续 offset 时 `MEMORY USAGE` 为 0.13 MB，按比例外推 1 亿 offset 约 13 MB 左右，仍远小于 Set 的 3 GB）。

D 错——HLL 误差**可正可负**（本课实测：n=1000 时多 0.6%，n=10000 时**少** 0.52%），不能做单向修正。

</details>

**Q5**：关于 Bitmap 的使用，下列说法正确的是？
- A. Bitmap 底层是专门的位图类型，与 String 无关
- B. Bitmap 的内存由元素个数决定，与 offset 大小无关
- C. 存 10 个元素但最大 offset 是 1 亿时，Bitmap 约占 14 MB，而 Set 只需 73 字节
- D. Bitmap 适合存储 UUID 形式的用户 ID

<details><summary>答案与解析</summary>

**答案：C**。本课实测：10 个元素 + 1 亿 offset，Bitmap 占 14.00 MB；同样 10 个整数用 Set 只占 73 字节。

A 错——Bitmap 底层就是 **String**（`SETBIT` 后 `TYPE` 返回 string）；B 错——Bitmap 内存由**最大 offset** 决定；D 错——UUID 是稀疏 ID，用 Bitmap 会爆炸，应该用 Set 或 HLL。

</details>

---

## 🚀 下一批接力提示词

> 学完本课，**复制下面这段文字发给 AI**，即可无缝进入下一批（无需重新描述上下文）：

```
继续学 Redis。我的学习档案在 redis/00-学习档案.md，
刚学完阶段 2《数据结构与命令》的课 4《Set、ZSet 与特殊类型》知识点「Set 交并差与去重、ZSet 跳表 + 哈希表双结构、Bitmap / HyperLogLog / Geo」，
请按大纲继续讲解阶段 3《持久化与高可用》的课 5《RDB 与 AOF 持久化》的知识点：RDB fork 与写时复制、AOF 写后日志与刷盘策略、持久化选型决策。
```

## 🧭 课程导航

⬅️ **上一课**：[课 3：List 与 Hash](lesson-03-List与Hash.md)

➡️ **下一课**：课 5：RDB 与 AOF 持久化（待编写）

📚 **返回目录**：[课程目录](../../02-课程目录.md)
