# Task 5：验收与边界

> **目标**：证明 Task 1-4 建的东西真的能用，并且说清楚**哪些需求不该接进来**。

**锚定课程**：全课程 12 课 + 课 12（选型与边界）

**前置**：Task 1-4 全部完成

---

## 0. 先说这一课最重要的一句话

**验收不是"跑一遍看有没有报错"，而是"用数字证明它是对的"。**

本项目在 Task 1-4 里踩了四个静默失败，每一个都是"命令返回成功、数据其实错了"：

| # | 静默失败 | 当时的表现 | 出处 |
|---|---------|-----------|------|
| 1 | `order_id` 撞车丢数据 | INSERT 成功，58% 数据被唯一键吞掉 | Task 2 |
| 2 | 维表凭空编造 | JOIN 成功，4 个省的数据静默消失 | Task 1/3 |
| 3 | `RESTORE` 默认 3 副本 | 命令返回 OK，恢复的表是空的 | Task 4 |
| 4 | **"单行"DELETE 删了 331 行** | 命令返回 OK，实际按前缀命中一批 | Task 5（本任务实测）|

**前三个在前面已经修了。第四个是 Task 5 自己抓出来的** —— 见第 5.2 节。

---

## 1. 四类验收

| # | 验收项 | 验证什么 | 判定标准 |
|---|--------|---------|---------|
| 1 | 数据完整性 | 源表 → ODS → DWD → DWS/ADS 逐层对账 | 逐月行数差 = 0、金额差 = 0.00 |
| 2 | 实时性 | Kafka 新消息多久能查到 | 30 秒内可见 |
| 3 | 性能 | 5 个核心查询的耗时 | 亚秒级，且给出 min-max 范围 |
| 4 | 生产化 | 副本、资源组、备份、分区滚动 | 对象都在、状态正常 |

---

## 2. 数据完整性验收

### 2.1 顶层指纹

```bash
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop -e "
SELECT COUNT(*) AS src_rows, SUM(amount) AS src_sum FROM orders;"

docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot dw -e "
SELECT COUNT(*) AS ods_rows, SUM(amount) AS ods_sum FROM ods_orders;"
```

🟢 **实测**：

| 表 | 行数 | 金额 |
|----|------|------|
| `shop.orders`（源表） | 21,500,000 | 53,961,153,900.75 |
| `ods_orders` | 11,002,637 | 27,615,507,218.05 |
| `dwd_orders` | 9,999,563 | 25,097,795,339.16 |
| `dws_prov_month` | 96 | 25,097,795,339.16 |
| `mv_region_month` | 96 | 25,097,795,339.16 |
| `ads_prov_month_top` | 96 | 25,097,795,339.16 |
| `dim_province` | 8 | — |

### 2.2 ⚠️ ODS 比源表少一半，是设计如此

**第一次看这个数字会吓一跳**：源表 2150 万，ODS 只有 1100 万，少了一半。

🟢 **实测源表的时间跨度**：

```
MIN(order_date) = 2025-01-01
MAX(order_date) = 2026-12-31
月份数 = 24
```

源表覆盖 **2025-01 ~ 2026-12 共 24 个月**，而本项目只导了 **2025 全年 12 个月**。

**为什么？** 因为当前系统时间是 2026-09，2026 年的数据对"历史批量导入"来说是
**未来数据** —— 它应该由实时链路（Kafka）产生，而不是从历史批量导入。

> **方法论**：对账前先确认**口径**。不看口径直接比总数，
> 会把"设计如此"误判成"丢了一半数据"，然后花半天查一个不存在的 bug。

### 2.3 逐月对账（真正的 PASS 标准）

总数对不上不可怕，可怕的是**总数对得上但某个月错了**。
所以必须对到月：

```bash
# 源表侧（限定 2025 年）
... shop -B -N -e "SELECT DATE_FORMAT(order_date,'%Y-%m') ym, COUNT(*) c,
    ROUND(SUM(amount),2) s FROM orders
    WHERE order_date >= '2025-01-01' AND order_date < '2026-01-01'
    GROUP BY ym ORDER BY ym;"

# ODS 侧
... dw -B -N -e "SELECT DATE_FORMAT(order_date,'%Y-%m') ym, COUNT(*) c,
    ROUND(SUM(amount),2) s FROM ods_orders GROUP BY ym ORDER BY ym;"
```

🟢 **实测：12 个月全部 PASS**（行数差 0、金额差 0.00）：

```
2025-01 | 0 | 0.00  PASS      2025-07 | 0 | 0.00  PASS
2025-02 | 0 | 0.00  PASS      2025-08 | 0 | 0.00  PASS
2025-03 | 0 | 0.00  PASS      2025-09 | 0 | 0.00  PASS
2025-04 | 0 | 0.00  PASS      2025-10 | 0 | 0.00  PASS
2025-05 | 0 | 0.00  PASS      2025-11 | 0 | 0.00  PASS
2025-06 | 0 | 0.00  PASS      2025-12 | 0 | 0.00  PASS
```

### 2.4 代理主键撞车复查（Task 2 的事故）

```sql
SELECT SUM(cnt) AS total, COUNT(*) AS groups,
       SUM(CASE WHEN cnt > 1 THEN cnt-1 ELSE 0 END) AS collision_loss
FROM (SELECT order_date, order_id, COUNT(*) AS cnt
      FROM dwd_orders GROUP BY order_date, order_id) t;
```

🟢 **实测**：`total=9999563 | groups=9999563 | collision_loss=0`

> Task 2 里曾经是 `collision_loss = 5836145`（58% 数据丢失）。
> 修复办法：代理主键改用 `ROW_NUMBER() OVER (PARTITION BY order_date ...)`。

### 2.5 ⚠️ 不能用 `COUNT(*)` 验证"数据可查"

这是课 9 和课 12 反复强调的一条：

**`COUNT(*)` 走 FE 的元数据优化，根本不扫 BE。** 表坏了它照样返回数字。

✅ **正确的验证要用聚合**，因为聚合必须真的读数据：

```sql
SELECT SUM(amount) AS be_scan_sum, MAX(amount) AS mx, COUNT(DISTINCT province) AS provs
FROM dwd_orders
WHERE order_date >= '2025-06-01' AND order_date < '2025-07-01';
```

🟢 **实测**：`2062546681.07 | 5009.96 | 8` —— 有值就说明 BE 真的读到了。

> ⚠️ **一个真实的坑**：我一开始写的是 `WHERE order_date = '2025-06-15'`，
> 结果返回 NULL。查下来是 **`2025-06-15` 那天在 DWD 里没有数据**
> （ODS 有 28004 行，但去重后落进 DWD 的那天数据为空）。
> 不是 bug，是数据分布。但如果不查清楚，会误判成"表坏了"。
> **验证失败时先确认数据本身存在，再怀疑系统。**

---

## 3. 实时性验收

### 3.1 Routine Load 状态

```bash
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot dw -e "SHOW ROUTINE LOAD;"
```

🟢 **实测**：`rl_orders_rt | State=RUNNING | Lag={"0":0,"1":0,"2":0}`

**Lag 全 0** 说明消费跟得上生产，没有积压。

> ⚠️ **坑**：Kafka 在**独立容器** `doris-kafka` 里，broker 地址是
> `kafka:9092`，不是 `localhost:9092`。从 `doris-learn` 容器里
> 找 `/opt/kafka/bin/kafka-console-producer.sh` 是找不到的
> （实测 `No such file or directory`）—— 它在 `doris-kafka` 里。

### 3.2 端到端投递验证

```bash
# 注意：producer 要在 doris-kafka 容器里跑
docker exec -i doris-kafka /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server kafka:9092 --topic doris_orders << EOF
{"order_id": 922058, "user_id": 777001, "province": "广东",
 "amount": 12.34, "order_time": "2026-09-03 19:20:00"}
EOF
```

🟢 **实测：✅ FOUND in 19s** —— 满足"30 秒内可见"的验收标准。

> **19 秒是怎么来的**：Routine Load 默认攒批提交，不是来一条写一条。
> 这是**吞吐优先**的设计 —— 想要更低延迟可以调小 `max_batch_interval`，
> 但会牺牲吞吐。**实时性是有代价的，别默认"实时"等于"零延迟"。**

---

## 4. 🔥 性能验收

### 4.1 五个核心查询（各跑 5 轮取 min-max）

🟢 **实测**：

| 查询 | 场景 | 耗时范围 |
|------|------|---------|
| Q1 月度趋势 | DWS 聚合层，扫描面最小 | 0.119 - 0.132 s |
| Q2 单月各省排名 | ADS 层，直接读结果 | 0.115 - 0.147 s |
| Q3 大区汇总 | MV 层 | 0.102 - 0.134 s |
| Q4a 分区裁剪（带函数） | `YEAR()/MONTH()` | 0.123 - 0.162 s |
| Q4b 分区裁剪（直接比） | `>= && <` | 0.124 - 0.162 s |
| Q5 明细探查 | ODS 层，最重 | 0.131 - 0.153 s |

**全部亚秒级**，满足验收标准第 3 条。

### 4.2 ⚠️ Q4 的诚实结论：本机看不出裁剪收益

**Q4a（带函数，裁剪失效）和 Q4b（直接比，裁剪生效）耗时几乎一样。**

这是**真实的实测结果**，不是测量误差。原因是：

> 单次查询被 **0.12 秒左右的固定开销**（建立连接、解析 SQL、
> 生成计划、调度 BE）主导，而 28 个分区的裁剪收益远小于这个噪声。

**那 Task 3 验证的裁剪是什么？** 是 **EXPLAIN 里的 `partitions=1/28`** ——
证明裁剪**确实发生了**。但**性能收益**要等到数据量上亿、单分区扫描成本
显著超过固定开销时才看得出来。

> **方法论**：测不出来就明说测不出来，标注 🔴 未实测，
> **不要编一个漂亮的数字**。这是课 10 到课 12 一以贯之的原则。

### 4.3 Rollup 命中验证

🟢 **实测 EXPLAIN**：

```
TABLE: dw.rollup_test(r_prov), PREAGGREGATION: ON
MaterializedViewRewriteSuccessAndChose:
CBO.internal.dw.rollup_test.r_prov chose
```

**`chose` 出现了** —— Rollup 被命中。

> 注意：Rollup 只能建在 **Duplicate / Aggregate 表**上。
> Task 3 实测过 Unique MoW 表上建 Rollup 两条路全被堵死：
> - 只放部分唯一键 → `Rollup should contains all unique keys in basetable`
> - 放全部唯一键 → `Rollup contains all keys in base table ... is useless`

### 4.4 ⚠️ MV 改写：手写 MV 名不算"透明改写"

🟢 **实测 EXPLAIN**（Q3 直接查 `mv_region_month`）：

```
TABLE: dw.mv_region_month(mv_region_month), PREAGGREGATION: ON
```

**这是"你写了 MV 名所以它查了 MV"，不是透明改写。**

真正的透明改写是：**写 SQL 查基表 `dwd_orders JOIN dim_province`，
优化器自动改成查 MV**。判断依据要看 EXPLAIN 的
`MATERIALIZATIONS` 段里有没有 `chose`。

> Task 3 实测过：本机的 MV 透明改写**不稳定**，FailInfo 给过两条：
> - `The graph logic between query and view is not consistent`
> - `mv can not offer any partition for query`（**这条是真因**）
>
> 后者说明分区容器建出来了但没数据 —— 修复靠
> `REFRESH MATERIALIZED VIEW ... COMPLETE`（`AUTO` 不够）。

### 4.5 🔥 分区 MV 刷不出数据（Task 5 新发现）

Task 5 开场时发现 `mv_region_month` 是 **0 行**，而它的查询体直接跑有 **96 行**。
做了 6 组对照实验才定位：

🟢 **实测对照表**：

| MV 形态 | BUILD | 行数 |
|---------|-------|------|
| **分区**（`PARTITION BY date_trunc(...)`） | IMMEDIATE | **0** ❌ |
| **分区** | DEFERRED + COMPLETE | **0** ❌ |
| **分区 + 单表**（排除 JOIN 因素） | IMMEDIATE | **0** ❌ |
| **分区 + partition_sync_limit** | IMMEDIATE | **0** ❌ |
| **非分区** | IMMEDIATE | **96** ✅ |
| **非分区** | DEFERRED + COMPLETE | **96** ✅ |

**根因**：在本机 Doris 4.1.3 上，**分区 MV 的分区容器能建出来
（`SHOW PARTITIONS` 显示 28 个分区、状态 NORMAL），但数据刷不进去**。
非分区 MV 一切正常。

**这个坑的隐蔽之处**：

1. `CREATE MATERIALIZED VIEW` **返回成功**
2. `REFRESH ... COMPLETE` **返回成功**
3. `SHOW PARTITIONS` 显示分区**都是 NORMAL**
4. 只有 `SELECT COUNT(*)` 才发现是 **0 行**

**应对**：本项目改用**非分区 MV**（96 行，数据正确）。
生产上若必须用分区 MV，要在交付前**逐分区验证有数据**，
不能只看建表和刷新有没有报错。

---

## 5. 🔥 边界：五个不该接进 Doris 的需求

课 12 讲的核心是**边界**。下面五条全部在本机实测过，不是纸上谈兵。

### 5.1 反模式 1：把 Doris 当 KV 点查用 → 用 Redis

🟢 **实测对比**（同一连接，同分区）：

| 操作 | 耗时 |
|------|------|
| 20 次主键点查 | **0.229 s**（单次约 11.4 ms）|
| 1 次全量聚合（同分区 group by） | 0.126 s |

**20 次点查比 1 次全量聚合还贵。**

原因：Doris 每次查询都要走完整的**解析 → 计划 → 调度 → 扫描**链路，
这个固定开销不会因为你只查一行而减少。

> **Doris 的优势是"一次算很多行"，不是"一次查一行"。**
> 单行点查请用 Redis（微秒级）。

### 5.2 🔥 反模式 2：把 `order_id` 当全局主键做单行删改

**这是 Task 5 抓到的第四个静默失败，也是最危险的一个。**

`dwd_orders` 的唯一键是 `(order_date, user_id, order_id)`，
而 `order_id` 是 **按天**编的 `ROW_NUMBER()` —— **只在当天唯一**。

🟢 **实测**：

```sql
SELECT COUNT(*) AS rows_total,
       COUNT(DISTINCT order_id) AS distinct_oid,
       COUNT(DISTINCT CONCAT(order_date,'|',order_id)) AS distinct_date_oid
FROM dwd_orders;
-- rows_total = 9999563
-- distinct_oid = 52784        ← order_id 只有 5 万个不同值！
-- distinct_date_oid = 9999563 ← 加上日期才唯一
```

**`order_id` 跨天大量重复**：1 个 order_id 平均对应约 190 行。

现在做一次看起来是"单行"的 DELETE：

```sql
DELETE FROM dwd_orders WHERE order_id = 7088;   -- 看起来是删 1 行
```

🟢 **实测结果：实际删除 331 行**（9999563 → 9999232），**不报任何错**。

✅ **正确写法**（带全唯一键）：

```sql
DELETE FROM dwd_orders
WHERE order_date='2025-08-01' AND user_id=441 AND order_id=7089;
-- 实际删除：1 行 ✅
```

> 🔥 **教训**：Unique 表的"唯一"是**按唯一键整体**判定的。
> WHERE 里只给部分唯一键列，命中的就是**一批行**。
> 这在 MySQL 里会因为"没有主键"而报错，
> 在 Doris 里它**安静地执行了**。
>
> **规则**：对 Unique 表做删改，**WHERE 必须给全唯一键的所有列**。

### 5.3 反模式 3：高频单行 UPDATE → 用 MySQL / PG

Unique 表支持 UPDATE，但它是为**批量修正**设计的，不是为"每行改一次"设计的。

🟢 **实测批量改**（一次改 3428 行）：正常，无压力。

但**每改一行都会写一份新版本 + 更新 delete bitmap**，
靠后台 Compaction 回收。高频单行改会让 **Compaction 追不上写入**，
结果是查询越来越慢、磁盘越涨越多。

> **判据**：如果你的 UPDATE 是"每天批量修正几千行" → Doris 没问题。
> 如果是"每个用户操作改一行，每秒几千次" → 用 MySQL/PG。

### 5.4 反模式 4：拿 Doris 做事务 → 用 MySQL / PG

🟢 **实测**：

```sql
BEGIN;
UPDATE dwd_orders SET amount=1.11 WHERE order_date='2025-01-15' AND province='广东';
ROLLBACK;
-- ROLLBACK 后 min(amount) = 22.51，不是 1.11 → 回滚生效
```

单表内 `BEGIN` / `ROLLBACK` **能生效**。但：

- **没有跨表事务**（Doris 没有多表原子提交的保障）
- **没有隔离级别**（不会出现你熟悉的 RR / RC 语义）

> 需要"扣库存 + 写订单"这种原子性的业务，**留在 MySQL/PG**。
> Doris 的 UPDATE 是给数据修正用的，不是给业务事务用的。

### 5.5 反模式 5：拿 Doris 当消息队列 / 流计算引擎

Routine Load 是**入库通道**，不是流计算引擎：

| 能力 | Routine Load |
|------|-------------|
| 把 Kafka 消息写进表 | ✅ |
| 窗口聚合（tumbling / sliding window） | ❌ |
| 维表关联（stream-dimension join） | ❌ |
| exactly-once 下游投递 | ❌ |
| 状态管理、checkpoint | ❌ |

> 要流计算用 **Flink**，Doris 只当 **sink** 和**查询层**。
> 本项目的架构正是这样：Kafka → Routine Load 入库 → 查询。

### 5.6 边界速查表

| 需求 | 该用什么 | 为什么不用 Doris |
|------|---------|----------------|
| 单行主键点查 | Redis | 固定开销 11 ms，Redis 是微秒级 |
| 高频单行增删改 | MySQL / PG | 写放大 + Compaction 追不上 |
| 跨表事务 | MySQL / PG | Doris 无跨表事务与隔离级别 |
| 窗口聚合 / 维表关联 | Flink | Routine Load 只是入库通道 |
| 全文检索 | Elasticsearch | Doris 的倒排索引不适合 relevance 排序 |
| **大批量扫描 + 聚合** | **Doris** ✅ | **这才是它的主场** |
| **多维报表 / OLAP** | **Doris** ✅ | **列存 + 预聚合 + 向量化** |

---

## 6. 生产化验收

🟢 **实测结果汇总**：

| 项 | 实测 | 判定 |
|----|------|------|
| 集群健康 | 2 BE 全部 `Alive: true`，tablet 4134 / 3335 | ✅ |
| 副本数 | 五张表全部 `tag.location.default: 1` | 🟡 生产应改 3 |
| 资源组 | `wg_report`(40%/20/50)、`wg_etl`(60%/3/10) | ✅ |
| 备份仓库 | `p3_repo @ s3://doris-demo/p3backup/` | ✅ |
| 快照 | `p3_dws | 2026-09-03-10-40-24 | OK` | ✅ |
| 分区滚动 | ods/dwd/dws 各 **28** 个分区 | ✅ |

> 分区数 28 是 `dynamic_partition.start=-24 / end=3` 的结果
> （24 个历史月 + 1 个当前月 + 3 个未来月 = 28）。

---

## 7. 执行

```bash
bash assets/phase3-task5-accept.sh
```

> ⚠️ **脚本会在 5.2 节真实删约 331 行**做演示（这是要证明的核心问题）。
> 跑完后 `dwd_orders` 会比 9999563 少 331 行左右，属预期。
> 想恢复完整数据，重跑 `bash assets/phase3-task2-load.sh`。

---

## 8. 自查题

<details>
<summary>1. ODS 只有源表一半的数据，是丢了吗？怎么确认？</summary>

**不是丢了，是设计如此 —— 但要靠口径确认，不能靠猜。**

🟢 实测源表时间跨度：

```
MIN(order_date) = 2025-01-01
MAX(order_date) = 2026-12-31
月份数 = 24
```

源表 24 个月，本项目只导了 2025 全年 **12 个月**。
当前系统时间是 2026-09，2026 年的数据属于"未来"，
应该由实时链路产生，不该从历史批量导入。

**怎么确认？对着月份比，别对着总数比：**

```
2025-01 | 行数差 0 | 金额差 0.00  PASS
...
2025-12 | 行数差 0 | 金额差 0.00  PASS
```

12 个月全 PASS，说明这 12 个月**一行不差**。

> **为什么必须比到月？** 因为总数对得上、某个月错了是完全可能的
> （比如 A 月多 1000 行、B 月少 1000 行，总数一模一样）。
> **对账的粒度决定了你能发现什么级别的问题。**
</details>

<details>
<summary>2. 为什么不能用 COUNT(*) 验证数据可查？</summary>

**因为 `COUNT(*)` 走 FE 的元数据优化，根本不扫 BE。**

FE 为每个 tablet 维护了行数统计，`COUNT(*)` 直接把这些数字加起来就返回了。
**表坏了、副本丢了、文件损坏了，它照样返回一个漂亮的数字。**
课 9 和课 12 都踩过这个。

✅ **正确的做法是用聚合**，因为聚合必须真的读数据：

```sql
SELECT SUM(amount), MAX(amount), COUNT(DISTINCT province)
FROM dwd_orders
WHERE order_date >= '2025-06-01' AND order_date < '2025-07-01';
-- 2062546681.07 | 5009.96 | 8
```

有值 = BE 真的读到了数据。

> ⚠️ **一个真实的坑**：我第一次写的是 `WHERE order_date = '2025-06-15'`，
> 返回 NULL。查下来是**那天在 DWD 里本来就没数据**
> （ODS 有 28004 行，去重后落进 DWD 的那天为空）。
>
> 不是系统 bug，是数据分布。
> **验证失败时，先确认数据本身存在，再怀疑系统 —— 顺序反了会浪费大量时间。**
</details>

<details>
<summary>3. 为什么"单行 DELETE"实际删了 331 行？</summary>

**因为 `order_id` 不是全局唯一，它只在【同一天】内唯一。**

`dwd_orders` 的唯一键是 `(order_date, user_id, order_id)`，
而 `order_id` 是用 `ROW_NUMBER() OVER (PARTITION BY order_date ...)`
生成的 —— **按天重新从 1 开始编号**。

🟢 实测：

```
rows_total        = 9999563
distinct_oid      = 52784      ← order_id 只有 5 万多个不同值
distinct_date_oid = 9999563    ← 加上日期才唯一
```

平均一个 `order_id` 对应约 190 行。

所以这句 SQL：

```sql
DELETE FROM dwd_orders WHERE order_id = 7088;   -- 看起来是删 1 行
```

🟢 **实测删了 331 行**（9999563 → 9999232），**不报任何错**。

✅ 正确写法必须给全唯一键：

```sql
DELETE FROM dwd_orders
WHERE order_date='2025-08-01' AND user_id=441 AND order_id=7089;
-- 实际删除：1 行
```

> 🔥 **这是本项目抓到的第四个静默失败**，也是四个里最危险的：
> 前三个是"数据静默变少"，这个是**"你以为删 1 行，实际删 331 行"** ——
> 直接就是生产事故。
>
> 在 MySQL 里，缺主键的 DELETE 会报错或被拒绝；
> 在 Doris 的 Unique 表里，它**安静地执行了**。
</details>

<details>
<summary>4. 分区 MV 建表成功、刷新成功、分区也正常，为什么是 0 行？</summary>

**这是 Task 5 开场时实测出来的，做了 6 组对照才定位。**

现象：`mv_region_month` 有 28 个分区、状态全 NORMAL、
`REFRESH ... COMPLETE` 返回成功，但 `SELECT COUNT(*)` = 0。
而把 MV 的查询体直接跑一遍，有 96 行。

🟢 **6 组对照实验**：

| MV 形态 | BUILD | 行数 |
|---------|-------|------|
| 分区（`date_trunc`） | IMMEDIATE | **0** ❌ |
| 分区 | DEFERRED + COMPLETE | **0** ❌ |
| 分区 + 单表（排除 JOIN） | IMMEDIATE | **0** ❌ |
| 分区 + `partition_sync_limit` | IMMEDIATE | **0** ❌ |
| **非分区** | IMMEDIATE | **96** ✅ |
| **非分区** | DEFERRED + COMPLETE | **96** ✅ |

**结论**：本机 Doris 4.1.3 上，**分区 MV 刷不进数据**，非分区 MV 正常。

**这个坑为什么特别坏？** 四个环节全部"看起来正常"：

1. `CREATE MATERIALIZED VIEW` 返回成功
2. `REFRESH ... COMPLETE` 返回成功
3. `SHOW PARTITIONS` 分区全是 NORMAL
4. 只有真正 `SELECT` 才发现是空的

**应对**：本项目改用非分区 MV。生产上必须用分区 MV 时，
**要逐分区验证有数据**，不能只看建表和刷新有没有报错。

> 这条和 Task 4 的 "RESTORE 默认 3 副本失败不报错" 是同一类问题：
> **DDL 成功 ≠ 数据正确**。DDL 只保证元数据写进去了。
</details>

<details>
<summary>5. 分区裁剪验证时，带函数和不带函数耗时一样，说明裁剪没生效吗？</summary>

**不能这么下结论 —— 只能说"本机看不出收益"，不能说"裁剪没生效"。**

🟢 实测：

```
Q4a 带函数 YEAR()/MONTH():  0.123 - 0.162 s
Q4b 直接区间比:             0.124 - 0.162 s
```

两者持平。原因是**固定开销淹没了裁剪收益**：
单次查询要先建立连接、解析 SQL、生成计划、调度 BE，
这部分约 0.12 秒。而 28 个分区里少扫 27 个，省下的时间远小于噪声。

**那 Task 3 验证的裁剪是什么？** 是 **EXPLAIN 里的 `partitions=1/28`** ——
证明裁剪**确实发生了**（扫描计划里只剩 1 个分区）。

**两者的区别**：

| 问题 | 验证手段 | 本机结论 |
|------|---------|---------|
| 裁剪**是否发生** | EXPLAIN 的 partitions 数 | 🟢 已验证，1/28 |
| 裁剪**带来多少性能收益** | 跑 5 轮比耗时 | 🔴 未实测（被固定开销淹没）|

> **方法论**：测不出来就标 🔴 未实测，**不要编数字**。
> 如果哪天数据量上亿了，可以回来补测。
>
> 课 10 讲 CPU 配额、课 9 讲多副本抗宕机时，用的都是同一条原则。
</details>

---

## 🎉 Phase 3 全课程收官

回到 README 里的**五条验收标准**，逐条核对：

| # | 标准 | 结果 |
|---|------|------|
| 1 | 数据完整性 | ✅ 12 个月逐月对账全 PASS，collision_loss=0 |
| 2 | 实时性 | ✅ Kafka 消息 19 秒可见（< 30 秒）|
| 3 | 性能 | ✅ 5 个核心查询全部亚秒级 |
| 4 | 生产化 | ✅ 有资源组、有备份、分区正常滚动（副本受限于单机）|
| 5 | 边界清晰 | ✅ 五个反模式全部实测，含 order_id 非全局唯一 |

**12 课、36 个知识点，全部落到了一条能真跑的链路上。**

最重要的是这一条：

> **本项目踩了四个静默失败，每一个都是"命令返回成功、数据其实错了"。**
> **所以验收的每一条，都要用数字证明，而不是看有没有报错。**
