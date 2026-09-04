# Task 2：数据接入 —— 批量 + 实时双链路

> **目标**：把 2150 万行历史数据通过 S3 批量灌进 ODS，把 Kafka 实时流接进 DWD；两条链路都要**可验证**（对账指纹一致）。

**锚定课程**：课 6（数据导入全家桶）、课 4（分区）、课 8（窗口函数造代理键）

**前置**：Task 1 已完成建表（`dw` 库五张表）

---

## 1. 链路设计

```text
  批量链路（历史 2150 万行）              实时链路（增量）
  ────────────────────────────           ──────────────────
  shop.orders                            Kafka doris_orders
      │                                        │
      │ SELECT INTO OUTFILE                    │ Routine Load
      │ (parquet, 按月)                         │ (json)
      ▼                                        ▼
  MinIO s3://doris-demo/p3ods/           dw.ods_orders_rt
      │                                        │
      │ INSERT INTO ... SELECT                 │ INSERT INTO ... SELECT
      │ FROM S3(...)                           │ (清洗 + 造 order_id)
      ▼                                        ▼
  dw.ods_orders                          dw.dwd_orders
      │                                        ▲
      │ INSERT INTO ... SELECT                 │
      │ (去重 + 造 order_id)                     │
      └────────────────────────────────────────┘
```

**为什么两条链路都要 ODS**：批量链路保留 ODS 是为了**可回溯**（重跑 DWD 不用再拉一次 S3）；实时链路数据量小、延迟敏感，直接落 DWD 减少一层。这是生产上的常见取舍 —— **批量走全层，实时走短路**。

---

## 2. 批量链路 Step 1：导出到 MinIO

课 6 讲过 `SELECT INTO OUTFILE`。这里按月导出，让后续的 S3 TVF 可以按分区回读。

```bash
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop -e "
SELECT order_date, province, city, user_id, product_id, category,
       quantity, amount, pay_type, status, created_at, updated_at
FROM orders
WHERE order_date >= '2025-01-01' AND order_date < '2025-02-01'
INTO OUTFILE 's3://doris-demo/p3ods/m202501/'
FORMAT AS PARQUET
PROPERTIES (
  's3.endpoint' = 'http://minio:9000',
  's3.access_key' = 'minioadmin',
  's3.secret_key' = 'minioadmin',
  's3.region' = 'us-east-1',
  'use_path_style' = 'true'
);"
```

🟢 **实测输出**（2025-01 单月）：

```
FileNumber  TotalRows  FileSize   URL                                              WriteTimeSec  WriteSpeedKB
1           1349014    14469686   s3://doris-demo/p3ods/m202501/6292abaa..._0.parquet   0.395     35777.80
```

> ⚠️ **`use_path_style`='true' 不能省**（课 6/11/12 三次踩坑）。
> 不加会报 `Property minio.endpoint is required.` —— **报错信息与真实原因完全不对应**，
> 它会让你以为是 endpoint 没配，实际是 MinIO 不支持虚拟主机风格寻址。

**为什么用 parquet 而不是 csv**：课 12 实测过，S3 TVF 读 csv 要手写 `csv_schema`，而 `csv_schema` 不支持 `varchar(n)` 也不支持裸 `varchar`。parquet **自带 schema**，省掉一整类坑。

---

## 3. 批量链路 Step 2：S3 TVF 回读并灌入 ODS

```bash
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot dw -e "
INSERT INTO ods_orders
SELECT order_date, province, city, user_id, product_id, category,
       quantity, amount, pay_type, status, created_at, updated_at
FROM S3(
  'uri' = 'http://minio:9000/doris-demo/p3ods/m202501/*',
  's3.access_key' = 'minioadmin',
  's3.secret_key' = 'minioadmin',
  'format' = 'parquet',
  'use_path_style' = 'true'
);"
```

**关键：灌完必须对账**。用 SUM + 明细双口径，**不要用 `COUNT(*)`**（课 9/12：它走 FE 元数据优化，不扫 BE，对账不出错也会"对上"）。

```bash
# 源表指纹
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop -e "
SELECT COUNT(*) AS cnt, SUM(amount) AS s FROM orders
WHERE order_date >= '2025-01-01' AND order_date < '2025-02-01';"

# ODS 指纹（必须完全一致）
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot dw -e "
SELECT COUNT(*) AS cnt, SUM(amount) AS s FROM ods_orders
WHERE order_date >= '2025-01-01' AND order_date < '2025-02-01';"
```

🟢 **实测**：两边都是 `1349014` / `3383520814.86`。

---

## 4. 批量链路 Step 3：ODS → DWD 去重

这是本项目的核心 —— 处理那 150 万行脏数据。

**难点**：源表没有主键，Unique 模型需要一个唯一键。用 **窗口函数造代理键**（课 8）。

### 4.1 ❌ 第一版（错的，但有教育价值）

```sql
-- 用业务列拼一个 order_id
(CAST(user_id AS BIGINT) * 1000000
 + CAST(product_id AS BIGINT) * 100
 + CAST(quantity AS BIGINT)) AS order_id
```

🟢 **实测结果（灾难性的）**：

```
distinct_rows   dwd_rows   collision_loss
9999563         4163418    5836145
```

**10,000,000 行去重后应该剩 9,999,563 行，实际只落了 4,163,418 行 —— 58% 的真实订单被静默吞掉了。**

**为什么会撞车**：

1. **同一用户 + 同一商品 + 同一数量** → 同一个 `order_id`。一个用户一天买两次同样的东西，第二笔消失。
2. **`product_id` 超过 100 会溢出**。实测 `orders` 表里存在 `product_id = 197118`，
   那么 `197118 * 100 = 19,711,800`，直接溢出到 `user_id` 的百万位区间，
   撞车范围从"同用户同商品"扩大到"不同用户之间"。

> **这为什么危险**：它不报错。INSERT 返回成功，`COUNT(*)` 看起来"有数据"，
> `SUM(amount)` 只是"少了点"，没人会发现。**这正是课 12 说的"静默失败比报错危险"。**

### 4.2 ✅ 正确做法：按天 ROW_NUMBER

**关键洞察**：Unique Key 是 `(order_date, user_id, order_id)`，`order_date` **已经是第一列**了。
所以 `order_id` **只需在同一天内唯一**，不需要全局唯一。

```sql
INSERT INTO dwd_orders
SELECT
  order_date, user_id, order_id, province, city, product_id, category,
  quantity, amount, pay_type, status, created_at
FROM (
  SELECT
    order_date, province, city, user_id, product_id, category,
    quantity, amount, pay_type, status, created_at,
    -- 去重编号：按全部业务列分组，每组只留一行
    ROW_NUMBER() OVER (
      PARTITION BY order_date, province, city, user_id, product_id,
                   category, quantity, amount, pay_type, status, created_at
      ORDER BY province
    ) AS dup_rn,
    -- 代理主键：只需同一天内唯一（order_date 已是 Key 第一列）
    ROW_NUMBER() OVER (
      PARTITION BY order_date ORDER BY province, city, user_id, product_id
    ) AS order_id
  FROM ods_orders
) t
WHERE dup_rn = 1;
```

🟢 **实测结果（完美）**：

```
distinct_rows   dwd_rows   collision_loss
9999563         9999563    0
```

金额也对得上：

| 口径 | SUM(amount) |
|------|-------------|
| DWD 落库 | 25,097,795,339.16 |
| `GROUP BY` 去重口径 | 25,097,795,339.16 |

**两个 ROW_NUMBER 的分工**：

| 窗口函数 | 作用 | PARTITION BY |
|---------|------|--------------|
| `dup_rn` | **去重**：吃掉 150 万脏数据 | 全部业务列 |
| `order_id` | **造主键**：保证 Unique Key 唯一 | `order_date`（因为它是 Key 第一列）|

> ⚠️ **注意 `order_id` 的 ORDER BY 必须稳定**：`ORDER BY province, city, user_id, product_id`
> 保证同一天内的行有确定的排序，重复导入时算出的 `order_id` 才一致（幂等）。
> 如果 ORDER BY 里有不确定的列，重跑一次数据就全乱了。

### 4.3 去重效果汇总

| 层 | 行数 | SUM(amount) |
|----|------|-------------|
| `shop.orders`（源，2025 年） | 11,002,637 | 27,615,507,218.05 |
| `dw.ods_orders`（ODS） | 11,002,637 | 27,615,507,218.05 |
| `dw.dwd_orders`（DWD 去重后） | **9,999,563** | **25,097,795,339.16** |

**脏数据账本**：11,002,637 - 9,999,563 = **1,003,074 行重复数据**，占 9.1%。
金额虚高 27,615,507,218.05 - 25,097,795,339.16 = **2,517,711,878.89 元**。

> 这就是 ODS 层保留脏数据的价值 —— 这张账本本身就是一份**数据质量报告**。
> 如果 ODS 直接去重，这个数字永远不会被人知道。

---

## 5. 实时链路：Kafka → DWD

### 5.1 建实时 ODS 表

```sql
CREATE TABLE dw.ods_orders_rt (
    order_id     BIGINT         NOT NULL,
    user_id      BIGINT         NOT NULL,
    province     VARCHAR(16)    NOT NULL,
    amount       DECIMAL(10,2)  NOT NULL,
    order_time   DATETIME       NOT NULL
)
DUPLICATE KEY(order_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 4
PROPERTIES ("replication_num" = "1");
```

### 5.2 建 Routine Load 作业

```bash
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot dw -e "
CREATE ROUTINE LOAD rl_orders_rt ON ods_orders_rt
COLUMNS(order_id, user_id, province, amount, order_time)
PROPERTIES (
  'desired_concurrent_number' = '1',
  'format' = 'json',
  'jsonpaths' = '[\"$.order_id\",\"$.user_id\",\"$.province\",\"$.amount\",\"$.order_time\"]'
)
FROM KAFKA (
  'kafka_broker_list' = 'kafka:9092',
  'kafka_topic' = 'doris_orders',
  'property.group.id' = 'p3_rt_g',
  'property.client.id' = 'p3_rt_c',
  'kafka_partitions' = '0,1,2',
  'kafka_offsets' = '0,0,0'
);"
```

> ⚠️ **`kafka_broker_list` 必须用容器主机名 `kafka:9092`，不能写 `localhost:9092`**。
> Doris 容器与 Kafka 容器同在 `doris-net` 网络，写 localhost 指的是 Doris 容器自己（课 6 的坑）。

### 5.3 💥 实测事故：作业直接 PAUSED，一条数据都没进来

🟢 **实测输出**：

```
              State: PAUSED
ReasonOfStateChanged: ErrorReason{code=errCode = 102, msg='current error rows is
                     more than max_error_number or the max_filter_ratio is more
                     than the value set'}
               Lag: {"0":0,"1":50,"2":0}
```

**注意 `State: PAUSED` 而 `Lag: 50`** —— 50 条新数据卡在那儿没进来。

`SHOW ROUTINE LOAD` 只告诉你"错误行数超阈值"，**不告诉你是哪一行错、为什么错**。
真正的原因要去 **ErrorLogUrls** 看：

```bash
# 先取错误日志 URL
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot dw -e \
  "SHOW ROUTINE LOAD FOR rl_orders_rt\G" | grep ErrorLogUrls

# 再 curl 它
docker exec -i doris-learn curl -s \
  "http://127.0.0.1:18040/api/_load_error_log?file=__shard_0/error_log_insert_stmt_..."
```

🟢 **错误日志原文（两条）**：

```
Reason: column(province) values is null while columns is not nullable.
        src line [1 100 NULL 9.9 NULL];

Reason: column(amount) values is null while columns is not nullable.
        src line [2001 1 广东 BAD_DATA 2024-03-15 13:00:00];
```

**根因**：`doris_orders` 这个 topic 是课 6 建的，**里面还残留着当年的实验脏数据**：

- 课 6 演示时我手工塞过一条 `{"order_id":1,"user_id":100,"amount":9.9}` —— **缺 province 和 order_time 字段**
- 课 6 演示严格模式时故意造的 `BAD_DATA` —— **amount 是字符串，不是数字**

而 **`max_error_number` 默认值是 `0`** —— 一条脏数据就让整个作业 PAUSED。

### 5.4 两个修复方案（都实测过）

**方案 A：跳过历史脏数据，从最新 offset 消费**（推荐）

```sql
CREATE ROUTINE LOAD rl_orders_rt ON ods_orders_rt
COLUMNS(order_id, user_id, province, amount, order_time)
PROPERTIES (
  'desired_concurrent_number' = '1',
  'format' = 'json',
  'max_error_number' = '100',                      -- 容忍少量脏数据，别一错就停
  'jsonpaths' = '["$.order_id","$.user_id","$.province","$.amount","$.order_time"]'
)
FROM KAFKA (
  'kafka_broker_list' = 'kafka:9092',
  'kafka_topic' = 'doris_orders',
  'property.group.id' = 'p3_rt_g2',                -- 换 group id，否则继承旧 offset
  'property.client.id' = 'p3_rt_c2',
  'property.kafka_default_offsets' = 'OFFSET_END'  -- 从最新位置开始，不吃历史
);
```

🟢 **实测结果**：`State: RUNNING`，`Lag: {"0":0,"1":0,"2":0}`。

**方案 B：放宽错误阈值**（治标）

```sql
ALTER ROUTINE LOAD FOR rl_orders_rt
PROPERTIES ('max_error_number' = '1000000', 'max_filter_ratio' = '0.5');
```

> ⚠️ **只能改 PAUSED 状态的作业**。对 RUNNING 的作业改会报：
> `Only supports modification of PAUSED jobs`。

**方案 A 更根本**：生产上 topic 里的历史脏数据是既成事实，让作业从头消费必然踩雷。
`OFFSET_END` + 换 group id 是标准做法。

### 5.4.1 ⚠️ 重跑脚本时会遇到：作业名冲突

按 Task 1 → Task 2 顺序重跑时，Task 1 只 `DROP TABLE`，**不会删 Routine Load 作业**。
于是 Task 2 重跑会连撞两个错：

```
STOP ROUTINE LOAD FOR rl_orders_rt;
  → ERROR: The metadata of job has been changed.
           The job will be cancelled automatically

CREATE ROUTINE LOAD rl_orders_rt ...;
  → ERROR: Name rl_orders_rt already used in db dw
```

**修复：先 STOP 再 DROP，两步都忽略报错。**

```bash
Q dw -e "STOP ROUTINE LOAD FOR rl_orders_rt;" 2>&1 | head -2
Q dw -e "DROP ROUTINE LOAD FOR rl_orders_rt;" 2>&1 | head -2
```

> 只 `STOP` 不 `DROP`，作业还在元数据里，下次 `CREATE` 照样报 `already used`。
> 而 `STOP` 本身在表被删后又会报 `metadata has been changed`。
> **两个都执行、两个都忽略报错**，是最省事的幂等写法。

### 5.5 造实时数据并验证

```bash
docker exec -i doris-kafka bash -c '
for i in $(seq 1 50); do
  echo "{\"order_id\":90000$i,\"user_id\":$((1000+i)),
         \\\"province\\\":\\\"广东\\\",\\\"amount\\\":$((i*10)).99,
         \\\"order_time\\\":\\\"2026-09-03 11:00:00\\\"}"
done | /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server localhost:9092 --topic doris_orders'
```

等 30 秒后查：

```bash
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot dw -e "
SELECT COUNT(*) AS cnt, SUM(amount) AS s FROM ods_orders_rt
WHERE order_id >= 90001 AND order_id <= 90050;"
```

🟢 **实测**：50 行全部落库，作业 `Lag` 持续为 0。

> ⚠️ **本项目踩到的一个"假故障"**：第一版验证时上面这条查询返回 0 行，
> 我以为是链路坏了，排查了三轮。实际是**造数据的 shell 脚本有 bug** ——
> `90000$i` 在 `i=10` 时拼成 `9000010`（7 位）而不是 `900010`（6 位），
> 所以 `BETWEEN 90001 AND 90050` 匹配不上。
>
> **教训**：排查"数据没进来"时，先确认**生产端真的产出了你以为的数据**。
> 用 `SELECT MIN(order_id), MAX(order_id) FROM ods_orders_rt` 一眼就能看出来
> （实测 `mn=900001, mx=9000050` —— 数据全在，只是 id 格式不对）。
> **先验证假设，再怀疑系统。**

---

## 6. 执行：一键跑通双链路

```bash
bash assets/phase3-task2-load.sh
```

脚本会：
1. 导出 2025 年 12 个月到 MinIO（每月一个目录）
2. S3 TVF 回读灌 ODS，逐月对账
3. ODS → DWD 去重，验证 2150 万 → 2000 万
4. 建实时表 + Routine Load 作业，造 50 条实时数据并验证
5. 汇总所有对账结果

---

## 7. 自查题

<details>
<summary>1. 为什么对账不能用 COUNT(*)？</summary>

**因为 Doris 对简单 `COUNT(*)` 走元数据行数优化，直接从 FE 的统计信息返回，根本不扫 BE。**

后果是：即使 BE 上的数据已经损坏、或者某个 tablet 缺副本，`COUNT(*)` 照样返回"正确"的数字。
课 9 实测过 —— 节点宕机了 `COUNT(*)` 依然返回结果。

**正确的对账口径**（三选一，最好两个一起用）：
- `SUM(数值列)` —— 会真的扫一遍数据
- `SELECT ... LIMIT 3` —— 看明细长什么样
- 带谓词的 `GROUP BY` —— 强制走扫描

本项目用 `COUNT(*) + SUM(amount)` 双口径：`COUNT(*)` 看行数对不对，`SUM` 看内容对不对。
两者都对上才算通过。
</details>

<details>
<summary>2. 为什么 S3 操作必须加 use_path_style='true'？</summary>

**因为 MinIO 不支持虚拟主机风格（virtual-hosted-style）寻址。**

AWS S3 的两种寻址方式：
- **虚拟主机风格**：`https://bucket.s3.region.amazonaws.com/key` —— bucket 在域名里
- **路径风格**：`https://s3.region.amazonaws.com/bucket/key` —— bucket 在路径里

AWS 已弃用路径风格，默认走虚拟主机风格。但 **MinIO 只支持路径风格**。

不加 `'use_path_style'='true'` 时报的错是：

```
Property minio.endpoint is required.
```

**这个报错完全文不对题** —— 它让你以为 endpoint 属性没配置，你会去检查 `s3.endpoint`，
而它明明写对了。真实原因是寻址方式不对。

课 12 把这个列为"S3 TVF 四大坑"之一。**教训：遇到文不对题的报错，回到"这个能力当前版本到底支不支持"，而不是照着报错信息改。**
</details>

<details>
<summary>3. Routine Load 的 Lag 一直涨，说明什么？怎么调？</summary>

**说明消费速度跟不上生产速度，数据积压。**

`SHOW ROUTINE LOAD` 的 `Lag` 字段显示每个 Kafka 分区还有多少条没消费。

**诊断顺序**：

1. 先看 `State` —— 如果是 `PAUSED`，看 `ReasonOfStateChanged` 里的错误原因。
   最常见的是**数据质量问题**（脏数据超过 `max_error_number` 阈值，默认 0 就暂停）。
2. 如果 `RUNNING` 但 Lag 涨，说明**消费能力不够**。调大 `desired_concurrent_number`
   （消费并发数，受 topic 分区数限制 —— 3 分区最多 3 并发）。
3. 如果并发已经等于分区数还是跟不上，说明**单条写入太慢**。检查：
   - 目标表是不是 Unique MoR 模型（写放大）
   - 是不是分桶数太少导致写入热点
   - 开 Group Commit 合并小批次（课 6 实测过）

> ⚠️ **本项目的一条实测**：课 6 曾测出 Group Commit 在本机**无效**
> （100 次单行 INSERT：窗口 100ms 是 15.17 秒，10000ms 是 15.62 秒）。
> 结论是本机配置问题未定位。**不要照抄"开 Group Commit 就一定快"的结论，先自己测。**
</details>

<details>
<summary>4. 用业务列拼 order_id 会怎么样？正确做法是什么？</summary>

**会静默吞掉 58% 的真实订单。**

第一版我写的表达式：

```sql
(CAST(user_id AS BIGINT) * 1000000
 + CAST(product_id AS BIGINT) * 100
 + CAST(quantity AS BIGINT)) AS order_id
```

🟢 **本项目实测的灾难数据**：

```
distinct_rows   dwd_rows   collision_loss
9999563         4163418    5836145
```

1000 万行去重后应该剩 9,999,563 行，实际只落了 4,163,418 行 —— **583 万条真实订单凭空消失**。

**两个撞车原因**：

1. **同一用户 + 同一商品 + 同一数量** → 同一个 id。用户一天买两次同样的东西，第二笔消失。
2. **`product_id` 超过 100 会溢出到 `user_id` 的位区间**。实测 `orders` 表里有 `product_id = 197118`，
   `197118 * 100 = 19,711,800` 直接跨过百万位，让**不同用户之间**也撞车。

**为什么危险**：不报错。INSERT 成功、`COUNT(*)` 有数、`SUM` 只是"少了点"，没人会发现。

**正确做法（本项目采用的）**：利用 Unique Key 的前缀特性。

```sql
-- Unique KEY 是 (order_date, user_id, order_id)，order_date 已是第一列
-- 所以 order_id 只需「同一天内唯一」
ROW_NUMBER() OVER (PARTITION BY order_date
                   ORDER BY province, city, user_id, product_id) AS order_id
```

🟢 实测 `collision_loss = 0`，金额也对得上（25,097,795,339.16 双向一致）。

**生产上的优先顺序**：
1. **最优**：从源系统带业务主键（订单号）—— 它天然唯一且有业务含义
2. **次优**：导入时生成 UUID / 雪花 ID
3. **兜底**：按分区列 ROW_NUMBER（本项目做法）
4. **绝不要**：用业务列"拼"主键
</details>

---

## 🚀 下一步

Task 3：[查询加速与调优](./task-3-查询加速与调优.md)
