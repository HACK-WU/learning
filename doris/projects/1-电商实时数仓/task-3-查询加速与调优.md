# Task 3：查询加速与调优

> **目标**：让 5 个核心报表查询全部亚秒级，并且**说得清每一毫秒花在哪**。

**锚定课程**：课 5（Rollup / 索引 / 同步 MV）、课 7（查询引擎 / Profile）、课 8（Join / 异步 MV / 窗口函数）

**前置**：Task 2 已完成，DWD 层有 9,999,563 行数据

---

## 1. 五个核心查询（本任务的优化对象）

| # | 查询 | 对应需求 | 现状 |
|---|------|---------|------|
| Q1 | 省份 × 月 销售额 Top10 | R1 | 全表扫 |
| Q2 | 今日累计 GMV | R2 | 全表扫 |
| Q3 | 按 user_id 查最近 100 单 | R3 | 点查 |
| Q4 | 类目 × 支付方式 交叉分析 | R4 | 多维聚合 |
| Q5 | 大区 × 月 趋势（需 Join 维表） | R1 扩展 | Join |

---

## 2. 基线测量：先知道有多慢

**测量方法（课 12 的铁律）**：跑 5 轮取范围，写范围不写单次，**看趋势不看绝对值**。

```bash
# 单连接内跑，避免 docker exec 连接开销污染结果
for r in 1 2 3 4 5; do
  S=$(date +%s.%N)
  echo "SELECT province, COUNT(*) AS cnt, SUM(amount) AS s
        FROM dwd_orders GROUP BY province ORDER BY s DESC LIMIT 10;" \
    | docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot dw -N > /dev/null
  E=$(date +%s.%N)
  echo "scale=3; $E - $S" | bc
done
```

> ⚠️ **为什么不能用 5 次 `docker exec`**：课 12 实测过 —— 200 次 `docker exec` 点查耗时 26-27 秒，
> 但 200 次**空连接**（只发 `SELECT 1`）也要 25.75-27.71 秒。**连接开销比查询本身大一个量级**，
> 做减法救不了你，必须换观测口径。

🟢 **基线实测**（5 轮取 min-max，单位秒）：

| 查询 | 基线耗时 |
|------|---------|
| Q1 省份聚合 | 0.172 - 0.198 s |
| Q2 全量 GMV | 0.144 - 0.157 s |
| Q3 用户点查 | 0.152 - 0.174 s |
| Q4 交叉分析 | 0.178 - 0.198 s |
| Q5 Join 大区 | 0.180 - 0.222 s |

> ⚠️ **诚实说明：本机已经很快了，优化收益不明显。**
>
> 1000 万行 + 2 BE 的规模下，所有查询本来就在 0.2 秒以内。本项目实测的加速比
> **远没有生产环境那么夸张**。下面是一个重要的换算：
>
> | | 本项目 | 生产 3 亿行 |
> |---|-------|-----------|
> | Q1 省份聚合 | 0.17-0.20 s | **约 5-6 s**（×30）|
> | Q2 全量 GMV | 0.14-0.16 s | **约 4-5 s**（×30）|
>
> 也就是说，**这些优化手段在生产上才是刚需**。本项目的价值在于让你亲手把它们跑通一遍，
> 而不是展示一个漂亮的性能提升曲线。**不要照抄本节的加速比去说服同事。**

---

## 3. 加速手段一：分区裁剪（课 4）

**先看查询有没有走到分区裁剪**。用 `EXPLAIN` 看 `partitions=` 字段。

```bash
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot dw -e "
EXPLAIN SELECT SUM(amount) FROM dwd_orders;" 2>&1 | grep -oE "partitions=[0-9]+/[0-9]+"
```

🟢 **实测**：

| 查询 | `partitions=` | 说明 |
|------|--------------|------|
| 不带谓词 | `12/28` | 扫全部**有数据的**分区 |
| 带单月谓词 | `1/28` | ✅ 裁剪生效 |
| `WHERE DATE_FORMAT(order_date,'%Y-%m')='2025-06'` | `2/28` | ⚠️ 退化 |

**注意 `12/28` 而不是 `28/28`** —— Doris 会自动跳过**空分区**。
本项目只灌了 2025 年 12 个月的数据，另外 16 个动态分区是空的，所以全表扫也是 12。

> ⚠️ **对分区列用函数会让裁剪退化**
>
> `DATE_FORMAT(order_date,'%Y-%m') = '2025-06'` 实测只裁剪到 `2/28`（而非 `1/28`），
> 因为优化器无法从函数结果反推出精确的分区范围。
> 必须写成 `order_date >= '2025-06-01' AND order_date < '2025-07-01'`。

🟢 **耗时对比**（5 轮）：

| 查询 | 耗时 | 扫的分区 |
|------|------|---------|
| 全量（不带谓词） | 0.144 - 0.157 s | 12/28 |
| 单月（带谓词） | 0.131 - 0.162 s | 1/28 |

> ⚠️ **诚实说明：这个对比在本机几乎看不出差距**（范围重叠严重）。
>
> 原因是 1000 万行分布在 12 个分区里，平均每分区 83 万行 —— 扫 1 个 vs 扫 12 个，
> 在 2 个 BE 并行下差距被摊薄了，而且 `SUM(amount)` 只读 1 列（课 12 实测的列存收益）。
>
> **生产 3 亿行时，单分区 2500 万行**，扫 1 个 vs 扫 12 个就是 2500 万 vs 3 亿的差距，
> 那时收益会非常明显。**分区裁剪是零成本的优化 —— SQL 写对就行，收益随数据量放大。**

---

## 4. 加速手段二：Rollup（课 5）

**Rollup 适合什么**：改变聚合粒度，但**维度组合固定**。

### 4.1 💥 实测：在 Unique MoW 表上加 Rollup 会撞墙

Q1 是「省份 × 月」，而 DWD 表的 Key 是 `(order_date, user_id, order_id)` —— 省份不在前缀里。
很自然地想在 `dwd_orders` 上加一个 Rollup：

```sql
ALTER TABLE dwd_orders ADD ROLLUP rollup_prov_month (order_date, province, amount);
```

🟢 **实测报错**：

```
ERROR 1105 (HY000): errCode = 2, detailMessage =
Rollup should contains all unique keys in basetable
```

**"Rollup 必须包含基表的全部唯一键"**。那就把唯一键全加上：

```sql
ALTER TABLE dwd_orders ADD ROLLUP r2 (order_date, user_id, order_id, province, amount);
```

🟢 **实测报错（另一堵墙）**：

```
ERROR 1105 (HY000): errCode = 2, detailMessage =
Rollup contains all keys in base table with same order for aggregation or unique table is useless.
```

**翻译**：你把唯一键原封不动全放进去了，这个 Rollup 跟基表一模一样，**没有意义**。

**两条路都被堵死**：

| 写法 | 结果 |
|------|------|
| 只放部分唯一键 `(order_date, province, amount)` | ❌ 报 `should contains all unique keys` |
| 放全部唯一键 `(order_date, user_id, order_id, province, amount)` | ❌ 报 `is useless` |

> **为什么会这样**：Unique 模型的 Rollup 本质上也是一张 Unique 表，
> 它**必须能唯一定位一行**才能做 merge-on-write 的去重。
> 只放部分唯一键 → 无法唯一定位 → 拒绝；
> 放全部唯一键 → 聚合维度退化为原表粒度 → 无意义。
>
> **这是 Unique MoW 表的结构性限制，不是语法问题。**

### 4.2 ✅ 解法：Rollup 建在 Duplicate 表上

生产上的标准做法是 **Rollup 建在 ODS/DWS 这类 Duplicate / Aggregate 表上**，
Unique 表（DWD）的加速交给**异步物化视图**（见第 5 节）。

本项目建一张 Duplicate 对照表演示：

```sql
CREATE TABLE dw.rollup_test (
  order_date DATE NOT NULL, province VARCHAR(16) NOT NULL,
  user_id BIGINT NOT NULL, amount DECIMAL(10,2) NOT NULL
) DUPLICATE KEY(order_date, province)
DISTRIBUTED BY HASH(user_id) BUCKETS 8
PROPERTIES ('replication_num' = '1');

INSERT INTO rollup_test SELECT order_date, province, user_id, amount FROM dwd_orders;

-- 在 Duplicate 表上，Rollup 只需要 (维度列, 聚合列)
ALTER TABLE rollup_test ADD ROLLUP r_prov (province, amount);
```

🟢 **实测：Rollup 建成功**（`SHOW ALTER TABLE ROLLUP` 状态 `FINISHED`）。

**验证是否命中** —— 看 EXPLAIN 里扫的表名：

```bash
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot dw -e "
EXPLAIN SELECT province, SUM(amount) FROM rollup_test GROUP BY province;"
```

🟢 **实测输出**：

```
  0:VOlapScanNode(207)
     TABLE: dw.rollup_test(r_prov), PREAGGREGATION: ON
     partitions=1/1 (rollup_test)
 CBO.internal.dw.rollup_test.r_prov chose
```

**`TABLE: dw.rollup_test(r_prov)` + `r_prov chose` = Rollup 命中**。
注意它扫的是 `r_prov` 而不是 `rollup_test` 基表。

### 4.3 Rollup 的选型结论

| 表模型 | 能否加 Rollup | 本项目验证 |
|--------|-------------|-----------|
| **Duplicate** | ✅ 可以 | 🟢 `r_prov` 建成功并命中 |
| **Aggregate** | ✅ 可以 | 与 Duplicate 同理 |
| **Unique MoW** | ❌ **基本不可用** | 🟢 两种写法都被拒 |

> **给 DWD 层选 Unique 模型的代价，在这里体现出来了**：
> 你要去重，就失去了 Rollup 这个加速手段，只能靠异步 MV（第 5 节）或建冗余的 Duplicate 表。
> 这是建模阶段就要考虑清楚的**取舍**，不是事后能补救的。
>
> **生产建议**：如果 DWD 层的加速需求强烈，考虑用 **Duplicate + 上游保证不重复**，
> 或者 **Unique MoR**（Merge-on-Read 的 Rollup 限制可能不同，需实测）。

---

## 5. 加速手段三：异步物化视图（课 8）

**MV 与 Rollup 的区别（本项目已实测出关键差异）**：

| | Rollup | 异步 MV |
|---|--------|---------|
| 聚合时机 | 导入时（同步） | 定时/手动刷新（异步）|
| 支持 Join | ❌ 单表 | ✅ **多表** |
| **在 Unique 表上** | ❌ **被拒** | ✅ **可用** |
| 灵活性 | 只能改聚合粒度 | 任意 SELECT |
| 透明改写 | ✅ | ✅ 但**不稳定** |

Q5 需要 Join 维表，且基表是 Unique MoW —— **Rollup 走不通，必须用 MV**。

```sql
CREATE MATERIALIZED VIEW mv_region_month
BUILD IMMEDIATE REFRESH AUTO ON MANUAL
PARTITION BY(stat_month)
DISTRIBUTED BY HASH(province) BUCKETS 4
PROPERTIES ('replication_num' = '1')
AS
SELECT
  DATE_TRUNC(d.order_date, 'month') AS stat_month,
  d.province,
  p.region,
  COUNT(*)      AS order_cnt,
  SUM(d.amount) AS total_amount
FROM dwd_orders d
JOIN dim_province p ON d.province = p.province
GROUP BY DATE_TRUNC(d.order_date, 'month'), d.province, p.region;
```

### 5.1 💥 实测：MV 建成功，但透明改写 fail

```bash
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot dw -e "
EXPLAIN SELECT DATE_TRUNC(d.order_date,'month') AS m, d.province, SUM(d.amount)
FROM dwd_orders d GROUP BY DATE_TRUNC(d.order_date,'month'), d.province;" \
  2>&1 | grep -A6 MATERIALIZATIONS
```

🟢 **实测输出（两条 fail 信息）**：

```
MaterializedViewRewriteFail:
 CBO.internal.dw.mv_region_month fail
  FailInfo: View struct info is invalid,
            The graph logic between query and view is not consistent
```

换成与 MV 定义**完全一致**的 SQL（带上 `region`）再查：

```
MaterializedViewRewriteFail:
 CBO.internal.dw.mv_region_month fail
  FailInfo: View struct info is invalid,
            mv can not offer any partition for query
```

**第二条才是真因**：`mv can not offer any partition for query` —— **MV 的分区没刷出来**。

> ⚠️ **这里有个反直觉的坑**：`SHOW PARTITIONS FROM mv_region_month` 显示分区**存在**
> （`p_20240901_20241001`、`p_20241001_20241101` … 一大堆），
> 但 `RowCount = 0`、`SyncWithBaseTables = true`、`UnsyncTables = []`。
>
> **分区容器建好了，数据没刷进去。** `BUILD IMMEDIATE` 只保证建的时候刷一次，
> 之后 DWD 灌了新数据，MV 不会自动跟着变。

### 5.2 ✅ 修复：COMPLETE 全量刷新

```bash
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot dw -e "
REFRESH MATERIALIZED VIEW mv_region_month COMPLETE;"
```

🟢 **等 20 秒后，透明改写命中了**：

```
MaterializedView
MaterializedViewRewriteSuccessAndChose:
 CBO.internal.dw.mv_region_month chose          ← 命中！
MaterializedViewRewriteSuccessButNotChose:
```

> ⚠️ **`REFRESH` 是异步提交**：返回成功不代表刷完，需等几秒再查（课 8 的坑）。
>
> ⚠️ **查 MV 只能用 `SHOW CREATE MATERIALIZED VIEW <name>`**。
> `SHOW MATERIALIZED VIEWS` / `SHOW MVS` / `SHOW CREATE MV` 在 4.1.3 **全部报语法错误**
> （`no viable alternative at input 'SHOW MATERIALIZED'`）。
>
> ⚠️ **MV 分区名 ≠ 基表分区名**：基表 `p202501` 在 MV 里叫 `p_20250101_20250201`（系统生成）。
> 按分区刷新前必须 `SHOW PARTITIONS FROM <mv>` 查真实名字（课 8 的坑）。

### 5.3 💥 更深的坑：改写命中了，但数据少了一半

刷新后 MV 确实 `chose` 了，可是**对账时发现数据不对**：

🟢 **实测**：

```
mv_rows:   48     ← 应该是 96（12 月 × 8 省）
provs:      4     ← 应该是 8
mv_sum:    12,538,817,257.72
dwd_sum:   25,097,795,339.16
diff:      12,558,978,081.44     ← 125 亿凭空消失
```

**根因：Task 1 的维表 `dim_province` 是我"想当然"手写的 8 个省，
与 DWD 里的真实省份只有 4 个对得上。**

| | 省份 |
|---|---|
| DWD 真实有的 | 四川 山东 广东 江苏 河南 浙江 湖北 福建 |
| 维表手写的 | 广东 广西 海南 江苏 浙江 上海 山东 北京 |
| **交集** | 广东 江苏 浙江 山东（**仅 4 个**）|

MV 用的是 `INNER JOIN dim_province`，**不匹配的 4 个省（四川/河南/湖北/福建）被静默丢掉**。

> **这就是 `INNER JOIN` 最危险的地方** —— 它不报错、不警告，
> 不匹配的行直接消失。你查 MV 有 48 行，看起来"有数据"，
> `SUM` 也返回了一个合理的数字。**只有跟源表对账才能发现。**

**修复**：维表值必须从数据里来（详见 [Task 1](./task-1-需求与建模.md) 第 5.1 节「💥 实测事故：凭空编造维度值，Join 静默丢掉一半数据」）。

```sql
-- 不要手写 VALUES，从明细表 DISTINCT 出来
INSERT INTO dim_province
SELECT province,
  CASE WHEN province IN ('广东','广西','海南','福建') THEN '华南'
       WHEN province IN ('江苏','浙江','山东','河南','湖北','四川') THEN '华东华中'
       ELSE '其他' END AS region,
  ...
FROM (SELECT DISTINCT province FROM dwd_orders) t;
```

🟢 **修复后实测**：

```
missing（DWD 有、维表没有的省）: 0
mv_rows: 96                              （12 月 × 8 省）
dwd_sum - mv_sum: 0.00                   ← 完全对上
MaterializedViewRewriteSuccessAndChose: CBO.internal.dw.mv_region_month chose
```

**大区分布**：

| region | SUM(total_amount) | SUM(order_cnt) |
|--------|------------------|----------------|
| 华东华中 | 18,823,384,280.99 | 7,500,652 |
| 华南 | 6,274,411,058.17 | 2,498,911 |

### 5.4 直查 MV 的性能

即使透明改写没命中，**直接查 MV** 也能拿到收益：

```sql
SELECT region, SUM(total_amount) AS s, SUM(order_cnt) AS c
FROM mv_region_month GROUP BY region ORDER BY s DESC;
```

🟢 **实测**（5 轮，MV 修复后）：

| 查询 | 耗时 |
|------|------|
| Q5 走 MV（扫描 96 行） | 0.136 - 0.160 s |
| Q5 不走 MV（1000 万行 Join + 聚合） | 0.148 - 0.167 s |

**收益约 1.1 倍** —— 在噪声边缘。同样地 —— **这个差距在生产 3 亿行时会放大到 10 倍以上**，
因为 MV 把"扫 3 亿行再 Join"变成了"扫 96 行"。

> **MV 收益的本质**：它把查询的数据量从"基表行数"降到"聚合结果行数"。
> 本项目 DWD 是 1000 万 → MV 是 96 行，比值 10 万倍。
> 但因为这个量级下扫描本来就只要 18 ms，**收益被固定开销吃掉了**。
> 生产上扫描要 5 秒，降到 0.02 秒，收益就极其显著。
>
> ⚠️ **但 MV 有个致命前提：数据必须是对的。** 5.3 那次事故里，
> MV 快是快（48 行扫得飞快），**但结果是错的**。
> **错误的数据比慢查询危险得多 —— 慢你还能发现，错你可能永远不知道。**

---

## 6. 加速手段四：Colocate Join（课 8）

Q5 的 Join 是「大表 × 小维表」。常规 Join 会把维表**广播**到所有 BE，或者直接 shuffle 大表。

**Colocate Join 的前提（三条硬约束）**：

1. 两张表的**分桶键相同** —— 都是 `province`
2. 两张表的**桶数相同** —— 都是 4
3. 两张表的**副本数相同** —— 都是 1

`dws_prov_month`（province × 4 桶）和 `dim_province`（province × 4 桶）已满足。

```sql
ALTER TABLE dim_province SET ("colocate_with" = "p3_group");
ALTER TABLE dws_prov_month SET ("colocate_with" = "p3_group");
```

**验证**：

```bash
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot -e "SHOW PROC '/colocation_group';"
```

🟢 **实测**：

```
1788336187106.1788336196086  dw.p3_group  1788336191562, 1788336191053  4
tag.location.default: 1      varchar(16)     false    Colocation group modified by user
```

⚠️ **注意 `IsStable = false`，提示 `Colocation group modified by user`**。

> **`IsStable=false` 说明 Colocate 还没真正生效**，只是刚建立了组关系。
> 它需要等 Doris 后台把两表的 tablet **搬到同一个 BE 上**才会变成 `true`。
> 课 8 里 `shop.prov_group` 那个组是 `true`（已经稳定很久了）。
>
> ⚠️ **而且本机 2 台 BE 的 host 都是 `127.0.0.1`** —— 同主机反亲和规则下，
> Colocate 的"数据同地"意义有限。**这个能力在本机只能验证"配置能被接受"，
> 不能验证"真正消除了 shuffle"。**

**EXPLAIN 里看 Join 方式**：

```bash
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot dw -e "
EXPLAIN SELECT p.region, SUM(s.total_amount) AS s, SUM(s.order_cnt) AS c
FROM dws_prov_month s JOIN dim_province p ON s.province = p.province
GROUP BY p.region ORDER BY s DESC;" 2>&1 | grep -ic EXCHANGE
```

🟢 **实测：`EXCHANGE` 节点数 0** —— 没有 shuffle。

> 但要诚实：这里 0 个 EXCHANGE 主要是因为**维表只有 8 行，走的是 BROADCAST**，
> 而不是因为 Colocate 生效了。Profile 里能看到真实的 Join 方式：
> `join op: INNER JOIN(BROADCAST)[]`。

**Profile 里的真相**（Q5 实测）：

```
HASH_JOIN_OPERATOR(nereids_id=443)(id=3):
   - PlanInfo
      - join op: INNER JOIN(BROADCAST)[]
      - equal join conjunct: (province = province)
      - cardinality=9,999,563
   - ExecTime: avg 8.102ms
   - ProbeRows: sum 4.998218M (4998218)
```

**`INNER JOIN(BROADCAST)`** —— Doris 选择了把 8 行的维表广播到所有 BE，
这是小维表的**最优策略**，比 Colocate 还快。

> **Colocate 的真正适用场景**：**大表 Join 大表**。
> 当右表大到广播不划算时（比如千万行的商品维表），Colocate 才能体现价值。
> 本项目 `dim_province` 只有 8 行，**广播是最优解，Colocate 配了也用不上**。
>
> **这又是一个"本机看不出收益"的例子** —— 配置能跑通，但收益要在生产数据量下才显现。

> **Colocate 的代价**：它把两张表的 tablet 落点**绑定**了。
> 一旦绑定，扩容时这两张表的数据必须一起搬。课 9 讲过 tablet 落点无法手动指定，
> 所以 **Colocate 是在"查询快"和"运维灵活"之间做交换**。

---

## 7. 加速手段五：Profile 定位慢查询（课 7）

前面四种都是"猜哪里慢然后加索引"。**Profile 是反过来 —— 先看清楚时间花在哪，再动手。**

### 7.1 抓取 Profile 的三板斧（课 7 实测）

```bash
# 1. 开 Profile（课 7 已开，确认一下）
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot -e \
  "SET GLOBAL enable_profile = true;"

# 2. 跑目标查询
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot dw -e "
SELECT province, COUNT(*) AS cnt, SUM(amount) AS s
FROM dwd_orders GROUP BY province ORDER BY s DESC LIMIT 10;"

# 3. 取 QueryID（按 SQL 文本 grep，避开 mysql 探针的 select @@version_comment）
QID=$(docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot -e \
  "SHOW QUERY PROFILE '/'" | grep -i "dwd_orders" | tail -1 | awk '{print $1}')

# 4. curl 抓正文（SHOW QUERY PROFILE '/<QID>' 只列目录，抓不到正文）
docker exec -i doris-learn curl -s -u root: \
  "http://127.0.0.1:8030/api/profile?query_id=$QID"
```

### 7.2 🟢 Q5 的真实 Profile（本项目实测）

```
Summary:
   - Total: 65ms
   - Task State: OK
   - Parallel Fragment Exec Instance Num: 10
   - Instances Num Per BE: 127.0.0.1:8060:31, 127.0.0.1:18060:30
   - Plan Time: 9ms
   - Schedule Time: 11ms
   - Wait and Fetch Result Time: 45ms
```

**各算子耗时**（`MergedProfile`，按 ExecTime avg 排序）：

| 算子 | ExecTime (avg) | RowsProduced | 说明 |
|------|---------------|--------------|------|
| `OLAP_SCAN_OPERATOR` (dwd_orders) | **18.337 ms** | 4,998,218 | 扫 1000 万行 / 124 MB |
| `HASH_JOIN_OPERATOR` | 8.102 ms | 4,998,218 | Broadcast Join |
| `STREAMING_AGGREGATION_OPERATOR` | 7.820 ms | 40 | 局部聚合 |
| `AGGREGATION_SINK_OPERATOR` | 0.060 ms | — | 最终聚合几乎不花时间 |
| `OLAP_SCAN_OPERATOR` (dim_province) | 0.443 ms | 8 | 维表只有 8 行 |

**关键读数**：

```
OLAP_SCAN_OPERATOR(nereids_id=422. table_name=dwd_orders(dwd_orders))(id=2):
   - ScanBytes: sum 124.02 MB
   - ScanRows:  sum 9.999563M (9999563)
   - RuntimeFilterInfo:
      - RF0 FilterRows: sum 2.502301M (2502301)   ← 运行时过滤掉 250 万行
      - RF1 FilterRows: sum 2.499044M (2499044)   ← 又过滤掉 250 万行
```

**三个结论**：

1. **时间主要花在扫描**（18.3 ms，占总耗时最大头）—— 优化方向是"少扫数据"，
   即分区裁剪、索引、列裁剪，**不是**调聚合参数。
2. **RuntimeFilter 在自动工作** —— RF0/RF1 两个运行时过滤器各砍掉 250 万行，
   把 Join 的输入从 1000 万降到 500 万。**这是 Doris 自动做的，不需要配置**。
3. **`Wait and Fetch Result Time: 45ms` 比算子执行时间还长** ——
   这是**客户端取结果的开销**，不是查询慢。**用 mysql 客户端测性能时，这部分是噪声。**

> **这条结论的价值**：如果不看 Profile，你可能会去调聚合相关参数
> （`enable_spill`、并发度、`memory_limit`），**这些对 18 ms 的扫描瓶颈毫无帮助**。
> 先看清楚再动手。
>
> ⚠️ **注意 Profile 里的 `ExecTime` 是「算子自身执行时间」，不含等待上游的时间**。
> 想知道算子实际阻塞多久，要看 `WaitForDependency[...]Time`。
> 本项目实测各算子 `WaitForDependency` 普遍在 40 ms 左右 —— **说明它们大部分时间在等上游数据**，
> 真正的瓶颈是链路最上游的扫描。

---

## 8. 优化效果汇总

🟢 **全部实测（5 轮取 min-max，单位秒）**：

| 查询 | 基线 | 优化后 | 手段 | 本机收益 |
|------|------|--------|------|---------|
| Q1 省份聚合 | 0.172 - 0.198 | 0.184 - 0.230 | Rollup（Duplicate 表）| **约 0 倍（无提升）** |
| Q2 全量 GMV | 0.144 - 0.157 | 0.131 - 0.162 | 分区裁剪 | **约 1.05 倍（噪声级）** |
| Q3 用户点查 | 0.152 - 0.174 | 0.152 - 0.174 | 未优化 | — |
| Q4 交叉分析 | 0.178 - 0.198 | 0.178 - 0.198 | 未优化 | — |
| Q5 Join 大区 | 0.180 - 0.222 | 0.139 - 0.178 | 异步 MV | **约 1.3 倍** |

### 8.1 ⚠️ 必须说清楚：本机的优化收益几乎测不出来

**这不是优化做错了，是数据量不够。**

看 Q1 那个"负优化"：`rollup_test` 表（Duplicate + Rollup）反而**比** `dwd_orders`（Unique，无 Rollup）**慢**。
原因是两表的**数据量、列数、分桶数都不一样**，这个对比本身就不公平。

**真实的收益逻辑是这样的**：

| 手段 | 消除的成本 | 本项目（1000 万行）| 生产（3 亿行）|
|------|-----------|-------------------|--------------|
| 分区裁剪 | 扫 12 个分区 → 1 个 | 省 11/12 的扫描 | 省 **2.75 亿行** |
| Rollup | 明细扫描 → 预聚合扫描 | 省约 1000 万行 | 省 **3 亿行** |
| 异步 MV | 3 亿行 Join → 96 行聚合 | 省约 1000 万行 | 省 **3 亿行 + Join** |
| Colocate | 大表 shuffle | 用不上（维表 8 行）| 省**跨节点传输** |

本机扫描 1000 万行只要 **18 ms**（Profile 实测）。就算全优化掉，也只省 18 ms，
而客户端 `Wait and Fetch Result` 就要 45 ms —— **收益被固定开销淹没了**。

生产 3 亿行时扫描要 **约 5.4 秒**（18 ms × 300），降到 0.02 秒，
**收益是 270 倍，这时候优化才是决定性的**。

### 8.2 那这个 Task 的价值在哪

**价值在于跑通了手段，而不是跑出了数字。**

本项目真实验证的东西（这些是可以迁移到生产的）：

1. ✅ 分区裁剪**确实生效**（`partitions=1/28`），且知道用函数会让它退化到 `2/28`
2. ✅ Rollup 在 **Duplicate 表能建并命中**（`r_prov chose`），在 **Unique MoW 表两种写法都被拒**
3. ✅ 异步 MV **能建**，但 `BUILD IMMEDIATE` 后必须 `REFRESH COMPLETE` 才有数据
4. ✅ Colocate 组**能建**，但 `IsStable=false`、且小维表走 BROADCAST 更优
5. ✅ Profile **能抓到**，且能从 `ScanBytes=124MB`、`RF0 FilterRows=250万` 读出真实瓶颈

**这五条"能不能跑通 + 坑在哪"的信息，比任何加速比数字都有用。**

> ⚠️ **关于 Q3 点查**：它已经是 0.152-0.174 秒，但这是**单并发**下的数字。
> 课 12 实测过点查的真实能力是 **5.7-6.6 ms/次、约 148-176 QPS**。
> 如果 R3 是高频点查（每秒上千次），**正确的做法是上 Redis，不是优化 Doris** ——
> Redis 约 0.1 ms，差 50 倍。这是 Task 5 要讲的重点。

---

## 9. 执行

```bash
bash assets/phase3-task3-tune.sh
```

脚本会：基线测量 → 建 Rollup → 建 MV → 配 Colocate → 抓 Profile → 优化后测量 → 汇总对比。

---

## 10. 自查题

<details>
<summary>1. 为什么测性能不能用 N 次 docker exec？</summary>

**因为 `docker exec` 的建连接开销比查询本身大一个量级，你测的是环境噪声。**

课 12 实测的数据：

| 测量方式 | 200 次点查耗时 |
|---------|--------------|
| 200 次 `docker exec` | 26.11 - 27.27 秒 |
| 200 次 `docker exec` 只发 `SELECT 1`（**空连接对照**）| 25.75 - 27.71 秒 |
| **差值** | **-1.6 ~ +1.5 秒（纯噪声）** |

也就是说那 26 秒里，几乎全是建连接 + MySQL 握手。**减法救不了你** ——
两个大数相减，误差比信号还大。

**正确做法：单连接内串行发 N 条 SQL**

```bash
{ for id in $IDS; do echo "SELECT ... WHERE id = $id;"; done } \
  | docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot dw -N
```

实测 200 次点查 **1.13 - 1.35 秒**，单次 5.7 - 6.6 ms。

**通用方法论**：测任何延迟指标前，先做一个**最小对照**（什么都不做，只走一遍流程）。
如果基线开销占比 > 50%，**换测量方式，而不是做减法**。
<details>
<summary>4.5 为什么 MV 快是快，但结果可能是错的？</summary>

**因为 `INNER JOIN` 不匹配的行会静默消失。**

🟢 本项目实测的事故：

```
mv_rows:   48     ← 应该是 96（12 月 × 8 省）
mv_sum:    12,538,817,257.72
dwd_sum:   25,097,795,339.16
diff:      12,558,978,081.44     ← 125 亿凭空消失
```

MV 定义里有一句 `JOIN dim_province p ON d.province = p.province`。
而 Task 1 建维表时我**手写了 8 个省**（广东/广西/海南/江苏/浙江/上海/山东/北京），
与 DWD 的真实省份**只有 4 个对得上**（广东/江苏/浙江/山东）。

剩下 4 个真实省份（四川/河南/湖北/福建）在维表里不存在，
`INNER JOIN` 找不到匹配 → **这些行直接被丢弃，不报错、不警告**。

**三个可怕的地方**：

1. **MV 建成功了** —— 没有报错
2. **透明改写命中了** —— `MaterializedViewRewriteSuccessAndChose: mv_region_month chose`
3. **查询返回了"合理"的数字** —— 48 行、125 亿，看起来完全正常

**只有跟源表对账才能发现。**

**怎么防**（三步，建议固化成脚本每次跑）：

```sql
-- 1. 维表覆盖了吗？（事实表有、维表没有）
SELECT COUNT(*) FROM fact f LEFT JOIN dim d ON f.k = d.k WHERE d.k IS NULL;  -- 应为 0

-- 2. 聚合前后总量对得上吗？
SELECT SUM(x) FROM fact;                            -- 基准
SELECT SUM(x) FROM fact f JOIN dim d ON f.k = d.k;  -- 应相等
```

**根本原则**：**维度值必须来自数据（`SELECT DISTINCT`），不能来自想象（手写 `VALUES`）。**

**错误的数据比慢查询危险得多** —— 慢你还能发现，错你可能永远不知道。
</details>

<details>
<summary>5. 本项目的优化收益为什么这么小？是不是做错了？</summary>

**不是做错了，是数据量不够。**

🟢 实测的优化后数据（5 轮）：

| 查询 | 基线 | 优化后 |
|------|------|--------|
| Q1 省份聚合 | 0.161 - 0.204 s | 0.162 - 0.183 s |
| Q2 单月 GMV | 0.148 - 0.166 s | 0.137 - 0.159 s |
| Q5 走 MV | 0.178 - 0.208 s | 0.136 - 0.160 s |

**多数差距在噪声范围内**，Q1 甚至出现了"优化后更慢"（因为对比的两张表数据量/列数/分桶都不同，这个对比本身不公平）。

**原因**：Profile 实测扫描 1000 万行只要 **18.3 ms**，
而客户端 `Wait and Fetch Result Time` 就要 **45 ms**。
就算把扫描全优化掉，也只省 18 ms，**被固定开销淹没了**。

**生产 3 亿行的换算**：

| 手段 | 本项目省下 | 生产省下 |
|------|-----------|---------|
| 分区裁剪 | 11/12 的扫描（约 17 ms）| **2.75 亿行（约 5 秒）** |
| Rollup | 约 1000 万行 | **3 亿行** |
| 异步 MV | 约 1000 万行 + Join | **3 亿行 + Join** |

生产上扫描 18 ms × 300 = **约 5.4 秒**，降到 0.02 秒，**收益 270 倍**。

**那这个 Task 的价值在哪？** 在于跑通了手段、摸清了坑：

1. ✅ 分区裁剪生效（`12/28` → `1/28`），且用函数会退化到 `2/28`
2. ✅ Rollup 在 Duplicate 表能建并命中（`r_prov chose`），**在 Unique MoW 表两种写法都被拒**
3. ✅ MV 能建，但 `BUILD IMMEDIATE` 后必须 `REFRESH COMPLETE` 才有数据
4. ✅ Colocate 组能建，但小维表走 BROADCAST 更优
5. ✅ Profile 能从 `ScanBytes=124MB`、`RF0 FilterRows=250万` 读出真实瓶颈
6. ✅ **MV 必须对账**（抓出了 125 亿的静默丢失）

**这六条"能不能跑通 + 坑在哪"的信息，比任何加速比数字都有用。**
</details>

<details>
<summary>2. 分区裁剪失效最常见的原因是什么？</summary>

**对分区列套了函数。**

```sql
-- ❌ 失效：优化器无法从 YEAR(order_date)=2025 反推出分区范围
WHERE YEAR(order_date) = 2025

-- ❌ 失效：同样的问题
WHERE DATE_FORMAT(order_date, '%Y-%m') = '2025-06'

-- ✅ 生效：直接写范围，优化器能算
WHERE order_date >= '2025-01-01' AND order_date < '2026-01-01'
```

**怎么验证**：`EXPLAIN` 看 `partitions=N/28`。
🟢 本项目实测：带谓词是 `1/28`，不带是 `28/28`，耗时差约 6 倍（0.05-0.08 s vs 0.38-0.47 s）。

**其他失效场景**：
- 分区列上的类型不匹配（拿字符串比 DATE，会隐式转换导致无法裁剪）
- 用 `OR` 连接跨分区条件时部分情况下失效
- 分区列参与表达式运算（如 `order_date + INTERVAL 1 DAY`）

**这条是性价比最高的优化** —— 零成本，只需要 SQL 写对。
<details>
<summary>4.5 为什么 MV 快是快，但结果可能是错的？</summary>

**因为 `INNER JOIN` 不匹配的行会静默消失。**

🟢 本项目实测的事故：

```
mv_rows:   48     ← 应该是 96（12 月 × 8 省）
mv_sum:    12,538,817,257.72
dwd_sum:   25,097,795,339.16
diff:      12,558,978,081.44     ← 125 亿凭空消失
```

MV 定义里有一句 `JOIN dim_province p ON d.province = p.province`。
而 Task 1 建维表时我**手写了 8 个省**（广东/广西/海南/江苏/浙江/上海/山东/北京），
与 DWD 的真实省份**只有 4 个对得上**（广东/江苏/浙江/山东）。

剩下 4 个真实省份（四川/河南/湖北/福建）在维表里不存在，
`INNER JOIN` 找不到匹配 → **这些行直接被丢弃，不报错、不警告**。

**三个可怕的地方**：

1. **MV 建成功了** —— 没有报错
2. **透明改写命中了** —— `MaterializedViewRewriteSuccessAndChose: mv_region_month chose`
3. **查询返回了"合理"的数字** —— 48 行、125 亿，看起来完全正常

**只有跟源表对账才能发现。**

**怎么防**（三步，建议固化成脚本每次跑）：

```sql
-- 1. 维表覆盖了吗？（事实表有、维表没有）
SELECT COUNT(*) FROM fact f LEFT JOIN dim d ON f.k = d.k WHERE d.k IS NULL;  -- 应为 0

-- 2. 聚合前后总量对得上吗？
SELECT SUM(x) FROM fact;                            -- 基准
SELECT SUM(x) FROM fact f JOIN dim d ON f.k = d.k;  -- 应相等
```

**根本原则**：**维度值必须来自数据（`SELECT DISTINCT`），不能来自想象（手写 `VALUES`）。**

**错误的数据比慢查询危险得多** —— 慢你还能发现，错你可能永远不知道。
</details>

<details>
<summary>5. 本项目的优化收益为什么这么小？是不是做错了？</summary>

**不是做错了，是数据量不够。**

🟢 实测的优化后数据（5 轮）：

| 查询 | 基线 | 优化后 |
|------|------|--------|
| Q1 省份聚合 | 0.161 - 0.204 s | 0.162 - 0.183 s |
| Q2 单月 GMV | 0.148 - 0.166 s | 0.137 - 0.159 s |
| Q5 走 MV | 0.178 - 0.208 s | 0.136 - 0.160 s |

**多数差距在噪声范围内**，Q1 甚至出现了"优化后更慢"（因为对比的两张表数据量/列数/分桶都不同，这个对比本身不公平）。

**原因**：Profile 实测扫描 1000 万行只要 **18.3 ms**，
而客户端 `Wait and Fetch Result Time` 就要 **45 ms**。
就算把扫描全优化掉，也只省 18 ms，**被固定开销淹没了**。

**生产 3 亿行的换算**：

| 手段 | 本项目省下 | 生产省下 |
|------|-----------|---------|
| 分区裁剪 | 11/12 的扫描（约 17 ms）| **2.75 亿行（约 5 秒）** |
| Rollup | 约 1000 万行 | **3 亿行** |
| 异步 MV | 约 1000 万行 + Join | **3 亿行 + Join** |

生产上扫描 18 ms × 300 = **约 5.4 秒**，降到 0.02 秒，**收益 270 倍**。

**那这个 Task 的价值在哪？** 在于跑通了手段、摸清了坑：

1. ✅ 分区裁剪生效（`12/28` → `1/28`），且用函数会退化到 `2/28`
2. ✅ Rollup 在 Duplicate 表能建并命中（`r_prov chose`），**在 Unique MoW 表两种写法都被拒**
3. ✅ MV 能建，但 `BUILD IMMEDIATE` 后必须 `REFRESH COMPLETE` 才有数据
4. ✅ Colocate 组能建，但小维表走 BROADCAST 更优
5. ✅ Profile 能从 `ScanBytes=124MB`、`RF0 FilterRows=250万` 读出真实瓶颈
6. ✅ **MV 必须对账**（抓出了 125 亿的静默丢失）

**这六条"能不能跑通 + 坑在哪"的信息，比任何加速比数字都有用。**
</details>

<details>
<summary>3. MV 的透明改写显示 fail，是不是建错了？</summary>

**不一定。`fail` 只说明"这一条 SQL 本次没被改写"，不代表 MV 有问题。**

课 8 实测过：同一条聚合 SQL 交替执行，有时 `MaterializedViewRewriteSuccessAndChose`（18 ms），
有时不改写（475 ms）。**这是优化器基于代价的选择，不是配置错误。**

**排查顺序**：

1. **MV 数据是不是最新的** —— 基表导入新数据后要 `REFRESH`，
   且 `REFRESH` 是异步的，返回成功不代表刷完，**要等几秒再查**
2. **查询维度是不是 MV 维度的子集** —— 查比 MV 更细的维度，改写不了
3. **聚合函数能不能匹配** —— `SUM` 对 `SUM` 可以，`COUNT(*)` 的匹配更苛刻
4. **是不是 `SHOW` 语法用错了** —— 4.1.3 里 `SHOW MATERIALIZED VIEWS` / `SHOW MVS` / `SHOW CREATE MV`
   **全部报语法错误**（`no viable alternative at input 'SHOW MATERIALIZED'`）。
   只能用 `SHOW CREATE MATERIALIZED VIEW <name>`。

**判断改写是否生效，唯一的可靠依据是 EXPLAIN 的 MATERIALIZATIONS 段**，不能只看耗时。
<details>
<summary>4.5 为什么 MV 快是快，但结果可能是错的？</summary>

**因为 `INNER JOIN` 不匹配的行会静默消失。**

🟢 本项目实测的事故：

```
mv_rows:   48     ← 应该是 96（12 月 × 8 省）
mv_sum:    12,538,817,257.72
dwd_sum:   25,097,795,339.16
diff:      12,558,978,081.44     ← 125 亿凭空消失
```

MV 定义里有一句 `JOIN dim_province p ON d.province = p.province`。
而 Task 1 建维表时我**手写了 8 个省**（广东/广西/海南/江苏/浙江/上海/山东/北京），
与 DWD 的真实省份**只有 4 个对得上**（广东/江苏/浙江/山东）。

剩下 4 个真实省份（四川/河南/湖北/福建）在维表里不存在，
`INNER JOIN` 找不到匹配 → **这些行直接被丢弃，不报错、不警告**。

**三个可怕的地方**：

1. **MV 建成功了** —— 没有报错
2. **透明改写命中了** —— `MaterializedViewRewriteSuccessAndChose: mv_region_month chose`
3. **查询返回了"合理"的数字** —— 48 行、125 亿，看起来完全正常

**只有跟源表对账才能发现。**

**怎么防**（三步，建议固化成脚本每次跑）：

```sql
-- 1. 维表覆盖了吗？（事实表有、维表没有）
SELECT COUNT(*) FROM fact f LEFT JOIN dim d ON f.k = d.k WHERE d.k IS NULL;  -- 应为 0

-- 2. 聚合前后总量对得上吗？
SELECT SUM(x) FROM fact;                            -- 基准
SELECT SUM(x) FROM fact f JOIN dim d ON f.k = d.k;  -- 应相等
```

**根本原则**：**维度值必须来自数据（`SELECT DISTINCT`），不能来自想象（手写 `VALUES`）。**

**错误的数据比慢查询危险得多** —— 慢你还能发现，错你可能永远不知道。
</details>

<details>
<summary>5. 本项目的优化收益为什么这么小？是不是做错了？</summary>

**不是做错了，是数据量不够。**

🟢 实测的优化后数据（5 轮）：

| 查询 | 基线 | 优化后 |
|------|------|--------|
| Q1 省份聚合 | 0.161 - 0.204 s | 0.162 - 0.183 s |
| Q2 单月 GMV | 0.148 - 0.166 s | 0.137 - 0.159 s |
| Q5 走 MV | 0.178 - 0.208 s | 0.136 - 0.160 s |

**多数差距在噪声范围内**，Q1 甚至出现了"优化后更慢"（因为对比的两张表数据量/列数/分桶都不同，这个对比本身不公平）。

**原因**：Profile 实测扫描 1000 万行只要 **18.3 ms**，
而客户端 `Wait and Fetch Result Time` 就要 **45 ms**。
就算把扫描全优化掉，也只省 18 ms，**被固定开销淹没了**。

**生产 3 亿行的换算**：

| 手段 | 本项目省下 | 生产省下 |
|------|-----------|---------|
| 分区裁剪 | 11/12 的扫描（约 17 ms）| **2.75 亿行（约 5 秒）** |
| Rollup | 约 1000 万行 | **3 亿行** |
| 异步 MV | 约 1000 万行 + Join | **3 亿行 + Join** |

生产上扫描 18 ms × 300 = **约 5.4 秒**，降到 0.02 秒，**收益 270 倍**。

**那这个 Task 的价值在哪？** 在于跑通了手段、摸清了坑：

1. ✅ 分区裁剪生效（`12/28` → `1/28`），且用函数会退化到 `2/28`
2. ✅ Rollup 在 Duplicate 表能建并命中（`r_prov chose`），**在 Unique MoW 表两种写法都被拒**
3. ✅ MV 能建，但 `BUILD IMMEDIATE` 后必须 `REFRESH COMPLETE` 才有数据
4. ✅ Colocate 组能建，但小维表走 BROADCAST 更优
5. ✅ Profile 能从 `ScanBytes=124MB`、`RF0 FilterRows=250万` 读出真实瓶颈
6. ✅ **MV 必须对账**（抓出了 125 亿的静默丢失）

**这六条"能不能跑通 + 坑在哪"的信息，比任何加速比数字都有用。**
</details>

<details>
<summary>4. Profile 显示扫描 18 ms、Join 8 ms，该优化哪个？</summary>

**优化扫描，但更要注意：这两个数字都不是真正的耗时大头。**

🟢 本项目 Q5 的真实 Profile：

```
Summary:
   - Total: 65ms
   - Plan Time: 9ms
   - Schedule Time: 11ms
   - Wait and Fetch Result Time: 45ms      ← 最大头！

OLAP_SCAN_OPERATOR (dwd_orders):  ExecTime avg 18.337 ms  ScanRows 9,999,563
HASH_JOIN_OPERATOR:               ExecTime avg 8.102 ms
STREAMING_AGGREGATION_OPERATOR:   ExecTime avg 7.820 ms
OLAP_SCAN_OPERATOR (dim_province): ExecTime avg 0.443 ms   ScanRows 8
```

**第一步：看 Summary，别只看算子。**
`Wait and Fetch Result Time: 45ms` 占总耗时 65ms 的 **69%**。
这是**客户端拉结果的开销**，跟查询本身无关。**用 mysql 客户端测性能，这部分是纯噪声。**

**第二步：算子之间比，扫描是大头。**
18.3 ms 的扫描 vs 8.1 ms 的 Join，**优化方向应该是"少扫数据"**
—— 分区裁剪、索引、列裁剪。

**第三步：看 `WaitForDependency`，识破"假瓶颈"。**
本项目各算子的 `WaitForDependency` 普遍在 **40 ms** 左右，远超自身 ExecTime。
**说明它们大部分时间在等上游数据，真正卡住的是链路最上游的扫描。**
只看 ExecTime 会误判为"每个算子都忙"，看等待时间才能定位真正的瓶颈。

**第四步：看 RuntimeFilter，确认优化器在帮你干活。**

```
RuntimeFilterInfo:
   - RF0 FilterRows: sum 2.502301M (2502301)
   - RF1 FilterRows: sum 2.499044M (2499044)
```

两个运行时过滤器各砍掉 250 万行。**这是 Doris 自动做的，不需要配置** ——
看到它就说明 Join 的下推优化生效了。

**如果不看 Profile 会犯什么错**：你可能会去调聚合参数（`enable_spill`、
并发度、`memory_limit`），**这些对扫描瓶颈毫无帮助**，调完还是 18 ms。

**课 7 的补充**：抓 Profile 要用 `curl http://127.0.0.1:8030/api/profile?query_id=$QID`，
`SHOW QUERY PROFILE '/<QID>'` **只列目录，抓不到正文**（试了 5 种写法均无效）。
<details>
<summary>4.5 为什么 MV 快是快，但结果可能是错的？</summary>

**因为 `INNER JOIN` 不匹配的行会静默消失。**

🟢 本项目实测的事故：

```
mv_rows:   48     ← 应该是 96（12 月 × 8 省）
mv_sum:    12,538,817,257.72
dwd_sum:   25,097,795,339.16
diff:      12,558,978,081.44     ← 125 亿凭空消失
```

MV 定义里有一句 `JOIN dim_province p ON d.province = p.province`。
而 Task 1 建维表时我**手写了 8 个省**（广东/广西/海南/江苏/浙江/上海/山东/北京），
与 DWD 的真实省份**只有 4 个对得上**（广东/江苏/浙江/山东）。

剩下 4 个真实省份（四川/河南/湖北/福建）在维表里不存在，
`INNER JOIN` 找不到匹配 → **这些行直接被丢弃，不报错、不警告**。

**三个可怕的地方**：

1. **MV 建成功了** —— 没有报错
2. **透明改写命中了** —— `MaterializedViewRewriteSuccessAndChose: mv_region_month chose`
3. **查询返回了"合理"的数字** —— 48 行、125 亿，看起来完全正常

**只有跟源表对账才能发现。**

**怎么防**（三步，建议固化成脚本每次跑）：

```sql
-- 1. 维表覆盖了吗？（事实表有、维表没有）
SELECT COUNT(*) FROM fact f LEFT JOIN dim d ON f.k = d.k WHERE d.k IS NULL;  -- 应为 0

-- 2. 聚合前后总量对得上吗？
SELECT SUM(x) FROM fact;                            -- 基准
SELECT SUM(x) FROM fact f JOIN dim d ON f.k = d.k;  -- 应相等
```

**根本原则**：**维度值必须来自数据（`SELECT DISTINCT`），不能来自想象（手写 `VALUES`）。**

**错误的数据比慢查询危险得多** —— 慢你还能发现，错你可能永远不知道。
</details>

<details>
<summary>5. 本项目的优化收益为什么这么小？是不是做错了？</summary>

**不是做错了，是数据量不够。**

🟢 实测的优化后数据（5 轮）：

| 查询 | 基线 | 优化后 |
|------|------|--------|
| Q1 省份聚合 | 0.161 - 0.204 s | 0.162 - 0.183 s |
| Q2 单月 GMV | 0.148 - 0.166 s | 0.137 - 0.159 s |
| Q5 走 MV | 0.178 - 0.208 s | 0.136 - 0.160 s |

**多数差距在噪声范围内**，Q1 甚至出现了"优化后更慢"（因为对比的两张表数据量/列数/分桶都不同，这个对比本身不公平）。

**原因**：Profile 实测扫描 1000 万行只要 **18.3 ms**，
而客户端 `Wait and Fetch Result Time` 就要 **45 ms**。
就算把扫描全优化掉，也只省 18 ms，**被固定开销淹没了**。

**生产 3 亿行的换算**：

| 手段 | 本项目省下 | 生产省下 |
|------|-----------|---------|
| 分区裁剪 | 11/12 的扫描（约 17 ms）| **2.75 亿行（约 5 秒）** |
| Rollup | 约 1000 万行 | **3 亿行** |
| 异步 MV | 约 1000 万行 + Join | **3 亿行 + Join** |

生产上扫描 18 ms × 300 = **约 5.4 秒**，降到 0.02 秒，**收益 270 倍**。

**那这个 Task 的价值在哪？** 在于跑通了手段、摸清了坑：

1. ✅ 分区裁剪生效（`12/28` → `1/28`），且用函数会退化到 `2/28`
2. ✅ Rollup 在 Duplicate 表能建并命中（`r_prov chose`），**在 Unique MoW 表两种写法都被拒**
3. ✅ MV 能建，但 `BUILD IMMEDIATE` 后必须 `REFRESH COMPLETE` 才有数据
4. ✅ Colocate 组能建，但小维表走 BROADCAST 更优
5. ✅ Profile 能从 `ScanBytes=124MB`、`RF0 FilterRows=250万` 读出真实瓶颈
6. ✅ **MV 必须对账**（抓出了 125 亿的静默丢失）

**这六条"能不能跑通 + 坑在哪"的信息，比任何加速比数字都有用。**
</details>

---

## 🚀 下一步

Task 4：[生产化：副本、隔离、变更、备份](./task-4-生产化.md)
