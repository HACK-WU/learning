# Task 1：需求与建模

> **目标**：拿到一份业务需求，产出一套四层数仓的表设计，且每张表的模型/分区/分桶选择都有可验证的理由。

**锚定课程**：课 1（OLAP vs OLTP、列存）、课 3（三种表模型）、课 4（分区分桶）、课 12（选型）

---

## 1. 需求：故事主线的收束

回到课 1 的原始困境：

> 一家电商公司，MySQL 里 3 亿行订单数据。运营要跑「按省份按月的销售额 Top10」，加索引、上从库、分库分表全试过，报表还是要跑 3 分钟。

现在数据团队决定上 Doris。需求清单：

| # | 需求 | 特点 |
|---|------|------|
| R1 | 省份 × 月 销售额 Top10 | 固定维度聚合，**每日刷新一次** |
| R2 | 实时大盘：今日累计 GMV、订单数 | **秒级延迟**，全量扫描 |
| R3 | 用户订单明细查询（按 user_id 查最近 100 单） | **点查**，带排序 |
| R4 | 商品类目 × 支付方式 交叉分析 | 多维即席，维度组合不定 |
| R5 | 历史订单回溯（查 2025 年某月的原始订单） | 冷数据，**量大但访问少** |

**约束**：
- 数据量：当前 2150 万行（本项目用它做全量），生产将增长到 3 亿行
- 延迟要求：R1 亚秒级、R2 秒级、R3 亚秒级、R4 秒级、R5 可接受 10 秒内
- 数据质量：**源表存在完全重复的脏数据**（实测 2150 万行去重后只有 2000 万行）

---

## 2. 关键决策 1：先证明「列存 + 分区裁剪」为什么能救 R1

不要直接说"Doris 快"。先用源表实测量化收益（课 1 + 课 4 的复现）。

```bash
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop -e "
-- 全表扫 1 列（列存收益：只读 amount）
SELECT SUM(amount) FROM orders;
"
```

实测对比（跑 3 轮，看趋势不看绝对值）：

| 查询 | 耗时 | 说明 |
|------|------|------|
| `SELECT SUM(amount) FROM orders`（1 列） | 0.13 - 0.16 s | 只读 amount 列 |
| `SELECT * FROM orders LIMIT 1`（13 列） | 0.51 - 0.60 s | 读全部列 |

**结论（课 1 的复现）**：列存让"只查统计值"的成本与表宽度脱钩。课 12 实测的列数翻 13 倍、耗时翻 4 倍，在这里再次得到印证。

---

## 3. 关键决策 2：数据探查 —— 别拍脑袋建模

建模前必须先看清数据。这一步做错，后面全白做。

```bash
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop -e "
-- 数据范围（决定分区边界）
SELECT MIN(order_date) AS mn, MAX(order_date) AS mx FROM orders;

-- 指纹：全量行数与金额总和（后续每一层都对账用）
SELECT COUNT(*) AS cnt, SUM(amount) AS sum_amt FROM orders;

-- 维度基数（决定分桶键）
SELECT COUNT(DISTINCT province) AS prov_cnt,
       COUNT(DISTINCT city) AS city_cnt,
       COUNT(DISTINCT user_id) AS user_cnt,
       COUNT(DISTINCT category) AS cat_cnt
FROM orders;
"
```

🟢 **实测结果**：

| 指标 | 值 |
|------|-----|
| 日期范围 | `2025-01-01` ~ `2026-12-31` |
| 总行数 | 21,500,000 |
| 金额总和 | 53,961,153,900.75 |
| province 基数 | **8** |
| city 基数 | 50 |
| user_id 基数 | 1,835,605 |
| category 基数 | 10 |

### 3.1 ⚠️ 脏数据：2150 万 vs 2000 万

```bash
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop -e "
SELECT COUNT(*) AS total,
       COUNT(DISTINCT order_date, province, city, user_id, product_id,
                      category, quantity, amount, pay_type, status, created_at) AS dedup
FROM orders;
"
```

🟢 **实测**：`total = 21,500,000`，`dedup = 20,000,000`。**有 150 万行是完整重复的脏数据。**

重复倍数分布：

| 出现次数 | 行组数 | 贡献行数 |
|---------|--------|---------|
| 1 次 | 18,543,781 | 18,543,781 |
| 2 次 | 1,417,031 | 2,834,062 |
| 3 次 | 34,595 | 103,785 |
| 4 次 | 4,593 | 18,372 |
| **合计** | **20,000,000** | **21,500,000** |

> **这一条直接决定了 DWD 层必须用 Unique 模型去重**，而不是简单搬运。这是本项目最真实的建模约束 —— 不是教科书假设，是源数据里真的有。

### 3.2 分桶键的选择：为什么不能选 province

源表 `orders` 用的就是 `DISTRIBUTED BY HASH(province) BUCKETS 8`，而 province 基数只有 **8**。

课 4 的结论在这里得到印证：**分桶键基数太低 → 数据倾斜**。本机实测 `orders` 表倾斜比 3.00（课 3 档案记录）。

| 候选分桶键 | 基数 | 评价 |
|-----------|------|------|
| `province` | 8 | ❌ 太低，且是查询高频过滤维度，倾斜风险大 |
| `user_id` | 1,835,605 | ✅ 高基数、分布均匀，R3（点查用户订单）直接命中分桶裁剪 |
| `order_id`（需造） | 高 | ✅ 理论最优，但源表没有主键 |

**决策**：DWD 层用 `user_id` 分桶（兼顾 R3 点查 + 分布均匀），桶数按"单桶 1-10 GB"经验取 **8**（本项目数据量小，8 桶足够并行）。

---

## 4. 四层建模：每张表的选择与理由

### 4.1 ODS 层：贴源，不清洗

```sql
CREATE TABLE dw.ods_orders (
    order_date   DATE           NOT NULL,
    province     VARCHAR(16)    NOT NULL,
    city         VARCHAR(32)    NOT NULL,
    user_id      BIGINT         NOT NULL,
    product_id   INT            NOT NULL,
    category     VARCHAR(32)    NOT NULL,
    quantity     INT            NOT NULL,
    amount       DECIMAL(10,2)  NOT NULL,
    pay_type     VARCHAR(16)    NOT NULL,
    status       TINYINT        NOT NULL,
    created_at   DATETIME       NOT NULL,
    updated_at   DATETIME       NOT NULL
)
DUPLICATE KEY(order_date, province, city)
PARTITION BY RANGE(order_date) ()
DISTRIBUTED BY HASH(user_id) BUCKETS 8
PROPERTIES (
    "replication_num" = "1",
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "MONTH",
    "dynamic_partition.start" = "-24",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p",
    "dynamic_partition.create_history_partition" = "true"
);
```

**选型理由**：

| 决策 | 选择 | 理由 |
|------|------|------|
| 表模型 | **Duplicate** | ODS 的职责是"原样落地"，**包括脏数据**。用 Unique 会在这里就把 150 万重复行吃掉，导致后续无法追查数据质量问题 |
| 分区 | **按月 + 动态分区** | 时间是最核心的过滤维度（R1/R2/R5 都按时间），按月分区让 R5 的历史回溯只扫 1 个分区；动态分区避免手工维护 |
| 分桶 | **`user_id` × 8** | 高基数（183 万）分布均匀，且 R3 点查用户订单时可用分桶裁剪 |
| Key 列 | `(order_date, province, city)` | 前缀索引。ODS 常见查询按日期范围扫，日期放首位；province 次之（R1 按省份聚合）|

> **为什么 ODS 保留脏数据**：这是数仓的通用原则 —— **贴源层是"证据"**，清洗逻辑放在 DWD。如果 ODS 就去重了，将来发现"去重规则错了"，就没有原始数据可以重跑。

### 4.2 DWD 层：去重 + 清洗

```sql
CREATE TABLE dw.dwd_orders (
    order_date   DATE           NOT NULL,
    user_id      BIGINT         NOT NULL,
    order_id     BIGINT         NOT NULL,
    province     VARCHAR(16)    NOT NULL,
    city         VARCHAR(32)    NOT NULL,
    product_id   INT            NOT NULL,
    category     VARCHAR(32)    NOT NULL,
    quantity     INT            NOT NULL,
    amount       DECIMAL(10,2)  NOT NULL,
    pay_type     VARCHAR(16)    NOT NULL,
    status       TINYINT        NOT NULL,
    created_at   DATETIME       NOT NULL
)
UNIQUE KEY(order_date, user_id, order_id)
PARTITION BY RANGE(order_date) ()
DISTRIBUTED BY HASH(user_id) BUCKETS 8
PROPERTIES (
    "replication_num" = "1",
    "enable_unique_key_merge_on_write" = "true",
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "MONTH",
    "dynamic_partition.start" = "-24",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p",
    "dynamic_partition.create_history_partition" = "true"
);
```

**选型理由**：

| 决策 | 选择 | 理由 |
|------|------|------|
| 表模型 | **Unique (MoW)** | 源数据有 150 万完全重复行，必须去重。MoW（Merge-on-Write）在写入时合并，查询无需额外聚合代价（课 3 已实测 MoW vs MoR 差异）|
| Key 列 | `(order_date, user_id, order_id)` | 唯一键。分区列 `order_date` 必须在 Key 首位；`user_id` 次之用于分桶裁剪；`order_id` 保证唯一 |
| **`order_id` 从哪来** | 导入时用函数生成 | 源表无主键。Task 2 用 `row_number()` 窗口函数生成代理键（课 8 高级 SQL 的应用）|
| 分区 | 同 ODS，按月 | 与 ODS 对齐，便于按分区对账 |

> ⚠️ **Unique 模型的隐藏约束**：Key 列必须在**所有非 Key 列之前**声明。上面 `order_date, user_id, order_id` 在最前面，`province` 等在后，顺序不能乱（课 3 的坑）。

### 4.3 DWS 层：预聚合

```sql
CREATE TABLE dw.dws_prov_month (
    stat_month   DATE           NOT NULL,
    province     VARCHAR(16)    NOT NULL,
    order_cnt    BIGINT         SUM   DEFAULT "0",
    user_cnt     BIGINT         BITMAP_UNION,
    total_amount DECIMAL(18,2)  SUM   DEFAULT "0",
    max_amount   DECIMAL(10,2)  MAX   DEFAULT "0"
)
AGGREGATE KEY(stat_month, province)
PARTITION BY RANGE(stat_month) ()
DISTRIBUTED BY HASH(province) BUCKETS 4
PROPERTIES (
    "replication_num" = "1",
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "MONTH",
    "dynamic_partition.start" = "-24",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p",
    "dynamic_partition.create_history_partition" = "true"
);
```

**选型理由**：

| 决策 | 选择 | 理由 |
|------|------|------|
| 表模型 | **Aggregate** | R1（省份×月 Top10）是固定维度聚合，用 Aggregate 模型让 Doris 在**导入时**就完成聚合，查询直接读预计算结果（课 3）|
| Key 列 | `(stat_month, province)` | 就是聚合维度 |
| 分桶 | `province` × 4 | 这里基数只有 8 但**数据量极小**（8 省 × 24 月 = 192 行），倾斜无所谓；且按 province 分桶让"某省份跨月趋势"查询可裁剪 |
| `user_cnt` 用 BITMAP_UNION | 去重计数 | 订单表的 UV 不能简单 SUM，必须用 bitmap（课 8 高级 SQL）|

> ⚠️ **Aggregate 模型的聚合时机**：`SUM` 列在导入时按 Key 聚合，**查询时再聚合一次**。所以 `order_cnt` 的 SUM 语义是"行数累加"，正确。但 `max_amount` 用 MAX，多次导入会取最大值，也正确。**不要对"平均值"用 Aggregate** —— AVG 不可累加，必须存 SUM 和 CNT 两个列，查询时相除（课 3 的经典陷阱）。

### 4.4 ADS 层：面向报表

```sql
CREATE TABLE dw.ads_prov_month_top (
    stat_month   DATE           NOT NULL,
    province     VARCHAR(16)    NOT NULL,
    rank_no      INT            NOT NULL,
    total_amount DECIMAL(18,2)  NOT NULL,
    order_cnt    BIGINT         NOT NULL,
    uv           BIGINT         NOT NULL
)
DUPLICATE KEY(stat_month, province, rank_no)
PARTITION BY RANGE(stat_month) ()
DISTRIBUTED BY HASH(province) BUCKETS 4
PROPERTIES (
    "replication_num" = "1",
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "MONTH",
    "dynamic_partition.start" = "-24",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p",
    "dynamic_partition.create_history_partition" = "true"
);
```

**选型理由**：ADS 是**最终结果表**，数据由 DWS 层计算后写入，不再需要聚合语义，用 Duplicate 最灵活（可全量覆盖重写某分区）。

> ⚠️ **本项目实测踩坑：Key 列必须是 schema 的有序前缀**
>
> 第一版我把列声明成 `(stat_month, province, total_amount, order_cnt, uv, rank_no)`，
> 却写 `DUPLICATE KEY(stat_month, rank_no)` —— 想让 `rank_no` 做前缀索引第二列。
> 结果直接报错：
>
> ```
> ERROR 1105 (HY000): errCode = 2, detailMessage =
> Key columns should be a ordered prefix of the schema.
> KeyColumns[1] (starts from zero) is rank_no, but corresponding column is province
> in the previous columns declaration.
> ```
>
> **Key 列只能取「从第一列开始的连续一段」**，不能跳着选。想要 `rank_no` 进前缀索引，
> 就必须把它的**声明位置**挪到 Key 列区间内（如上表把它放在第 3 位）。
> 这是课 3 的「Key 列必须在非 Key 列之前」约束的一个更精确的推论。

---

## 5. 维表：省份 → 大区

R4（类目 × 支付方式交叉）和 R1 的省份维度需要一张维表做 Join（课 8）。

```sql
CREATE TABLE dw.dim_province (
    province     VARCHAR(16)    NOT NULL,
    region       VARCHAR(16)    NOT NULL,
    region_code  INT            NOT NULL
)
DUPLICATE KEY(province)
DISTRIBUTED BY HASH(province) BUCKETS 4
PROPERTIES (
    "replication_num" = "1"
);
```

**为什么 BUCKETS 4 而不是 8**：要与 DWS 层的 `dws_prov_month`（province 分 4 桶）做
**Colocate Join**，两张表的分桶键、桶数、副本数必须**完全一致**（课 8 的硬约束）。

### 5.1 💥 实测事故：凭空编造维度值，Join 静默丢掉一半数据

第一版我"想当然"地写了维表数据：

```sql
INSERT INTO dim_province VALUES
('广东','华南',1),('广西','华南',1),('海南','华南',1),
('江苏','华东',2),('浙江','华东',2),('上海','华东',2),
('山东','华东',2),('北京','华北',3);
```

**看起来很合理 —— 8 个省、3 个大区。问题是：它不是从数据里来的。**

🟢 **实测：DWD 里的真实省份是这 8 个**

```
四川  山东  广东  江苏  河南  浙江  湖北  福建
```

**只有 4 个对得上**（广东、江苏、浙江、山东）。
我编的 `广西`/`海南`/`上海`/`北京` **数据里根本没有**；
而真实存在的 `四川`/`河南`/`湖北`/`福建` **维表里没有**。

后果在 Task 3 才暴露 —— MV 用 `INNER JOIN` 关联维表，
**不匹配的 4 个省被静默丢弃**：

```
dwd_sum:  25,097,795,339.16
mv_sum:   12,538,817,257.72     ← 只有一半
diff:     12,558,978,081.44     ← 125 亿凭空消失
```

MV 从应有的 96 行（12 月 × 8 省）变成 **48 行**（12 月 × 4 省）。

### 5.2 ✅ 正确做法：维度值必须从数据里来

```sql
-- 不要手写 VALUES，从明细表里 DISTINCT 出来
INSERT INTO dim_province
SELECT province,
  CASE WHEN province IN ('广东','广西','海南','福建') THEN '华南'
       WHEN province IN ('江苏','浙江','山东','河南','湖北','四川') THEN '华东华中'
       ELSE '其他' END AS region,
  CASE WHEN province IN ('广东','广西','海南','福建') THEN 1
       WHEN province IN ('江苏','浙江','山东') THEN 2
       WHEN province IN ('河南','湖北','四川') THEN 3
       ELSE 9 END AS region_code
FROM (SELECT DISTINCT province FROM dwd_orders) t;
```

🟢 **修复后实测**：

```
missing（DWD 有但维表没有的省）: 0
mv_rows: 96        （12 月 × 8 省）
dwd_sum - mv_sum:  0.00        ← 完全对上
```

**⚠️ 这条规则适用于所有维表**：**维度值必须来自数据，不能来自想象。**

**怎么自查**（三步，建议固化成脚本）：

```sql
-- 1. 维表覆盖了吗？
SELECT COUNT(*) FROM fact f LEFT JOIN dim d ON f.k = d.k WHERE d.k IS NULL;  -- 应为 0

-- 2. 维表有垃圾值吗？（有事实数据用不到的维度）
SELECT COUNT(*) FROM dim d LEFT JOIN fact f ON d.k = f.k WHERE f.k IS NULL;

-- 3. 聚合前后的总量对得上吗？
SELECT SUM(x) FROM fact;                                    -- 基准
SELECT SUM(x) FROM fact f JOIN dim d ON f.k = d.k;          -- 应相等
```

> **为什么这是"静默失败"**：`INNER JOIN` 不匹配的行**不报错、不警告**，
> 直接消失。你查 MV 有 48 行，看起来"有数据"，`SUM` 也返回了一个合理的数字。
> **只有跟源表对账才能发现。** 这正是课 12 反复强调的那句话：
> **验证要看数据对不对，不只是看有没有报错。**

---

## 6. 建模决策总表

| 层 | 表 | 模型 | 分区 | 分桶 | 核心理由 |
|----|-----|------|------|------|---------|
| ODS | `ods_orders` | Duplicate | 月 + 动态 | user_id × 8 | 贴源保脏数据，高基分桶 |
| DWD | `dwd_orders` | **Unique MoW** | 月 + 动态 | user_id × 8 | 去重 150 万脏数据 |
| DWS | `dws_prov_month` | **Aggregate** | 月 + 动态 | province × 4 | 固定维度预聚合 |
| ADS | `ads_prov_month_top` | Duplicate | 月 + 动态 | province × 4 | 最终结果，需覆盖重写 |
| DIM | `dim_province` | Duplicate | 无 | province × 4 | 与 DWS Colocate；**值必须从数据 DISTINCT 来** |

---

## 7. 为什么这些选择在生产会不同（课 12 视角）

本项目数据量只有 2000 万行，很多决策在生产 3 亿行时要重新算：

| 决策 | 本项目（2000 万）| 生产（3 亿）|
|------|-----------------|------------|
| 分桶数 | 8 | 按"单桶 1-10 GB"反推，3 亿行约需 30-60 桶 |
| 副本数 | 1（本机仅 2 BE 且同主机）| **3**（课 9：3 副本是生产默认）|
| 分区粒度 | 月 | 若日增超千万，改按天（课 4 实测 365 分区 = 2920 tablet 的代价）|
| DWD 分桶键 | user_id | 若 R3 点查是主要负载，考虑**上 Redis**（课 12：5.7-6.6 ms/次 vs Redis 0.1 ms）|
| 存算 | 存算一体 | 若查询潮汐明显（白天高峰、夜间空闲），考虑**存算分离**（课 12：卖点是弹性不是性能）|

---

## 8. 执行：建库建表

```bash
bash assets/phase3-task1-setup.sh
```

脚本会：建 `dw` 库 → 建 5 张表 → 校验分区已按动态分区规则自动创建 → 校验表结构。

🟢 **预期输出**：

- 5 张表全部创建成功
- `ods_orders` / `dwd_orders` / `dws_prov_month` / `ads_prov_month_top` 各自自动生成 **28 个月分区**
  （🟢 实测覆盖范围 `p202409` ~ `p202612`：当前月 2026-09 往前 24 个月 = 2024-09，往后 3 个月 = 2026-12）
- 集群 tablet 健康无缺副本（🟢 实测 `dw` 库 676/676 全部健康）

---

## 9. 自查题（做 Task 2 之前先答出来）

<details>
<summary>1. 为什么 ODS 用 Duplicate 而不是 Unique？</summary>

**因为 ODS 的职责是"贴源保真"，包括脏数据。**

源表有 150 万行完全重复的脏数据。如果 ODS 就用 Unique 模型，这些重复行在入库瞬间就被吃掉了 —— 将来业务方质疑"你们去重规则对不对"时，你拿不出原始证据。

数仓的分层原则：**越靠底层越贴近源，清洗逻辑越靠后越可追溯**。ODS 保留全部，DWD 做去重，两者行数差（2150 万 vs 2000 万）本身就是一份**数据质量报告**。

反过来说，如果 ODS 直接去重，那么"150 万脏数据"这个事实也会被一起抹掉，数据质量问题会变成**静默失败** —— 这正是课 12 反复强调的"比报错更危险"的情况。
</details>

<details>
<summary>2. 分桶键为什么选 user_id 而不是 province？</summary>

**两个原因：基数 和 查询模式。**

**基数**：`province` 只有 8 个不同值。按它分 8 桶，理想情况每省一桶，但各省订单量不均（广东 vs 西藏），实测 `orders` 表倾斜比达 **3.00**（课 3 档案）。倾斜意味着并行度退化 —— 8 个桶里最快的跑完要等其他桶，总耗时由**最慢的那个桶**决定。

`user_id` 基数 183 万，散列后分布极均匀。

**查询模式**：R3 需求是"按 user_id 查最近 100 单"。分桶键 = 查询过滤键时，Doris 可以**只扫 1 个桶**而不是全部 8 个桶（课 4 的分桶裁剪）。用 province 分桶，查某个用户要扫全部分桶。

**什么时候该用低基数列分桶**：当该列是**极高频率的聚合维度**且数据量小、可接受倾斜时，用它可以让 Group By 变成本地聚合（避免 shuffle）。本项目 DWS 层就是这种情况 —— 8 省 × 24 月只有 192 行，倾斜无所谓，所以用了 province。
</details>

<details>
<summary>3. DWS 用 Aggregate 模型，为什么不能存"平均客单价"？</summary>

**因为 AVG 不满足结合律，多次聚合的结果会错。**

Aggregate 模型在**两个时机**做聚合：① 导入时按 Key 合并；② 查询时 Group By 再合并。要正确，聚合函数必须满足 `f(f(a,b), f(c)) = f(a, f(b,c))`。

- `SUM`：✅ 满足。`SUM(SUM(a,b), c) = SUM(a, SUM(b,c))`
- `MAX` / `MIN`：✅ 满足
- `BITMAP_UNION`：✅ 满足（位图或运算）
- `AVG`：❌ **不满足**。`AVG(AVG(10,20), 30) = AVG(15, 30) = 22.5`，但真实平均是 `(10+20+30)/3 = 20`

**正确做法**：存两个列 —— `total_amount SUM` 和 `order_cnt SUM`，查询时 `SUM(total_amount) / SUM(order_cnt)`。

这也是为什么上面的 `dws_prov_month` 表里我写了 `total_amount` 和 `order_cnt` 两个 SUM 列，而没有"平均客单价"列 —— 它需要的时候现算。

> 课 3 的同一个陷阱还有个变体：**用 `REPLACE` 存"最新状态"时，如果导入批次乱序，最终保留的是最后导入的那条，不一定是时间最新的**。
</details>

<details>
<summary>4. 动态分区的 start=-24、end=3 是什么意思？</summary>

**窗口是"过去 24 个月 ~ 未来 3 个月"，共 28 个分区。**

- `start = -24`：保留**当前月往前 24 个月**的分区，更早的分区会被 Doris **自动删除**
- `end = 3`：预先创建**当前月往后 3 个月**的分区，避免"数据来了但分区不存在"导致导入失败
- `create_history_partition = true`：建表时立即把窗口内的历史分区全部建出来（否则只建未来的）

⚠️ **生产上的致命提醒**：`start = -24` 意味着 **24 个月前的数据会被自动 DROP**。

本项目的源数据范围是 2025-01 ~ 2026-12，🟢 实测动态分区窗口是 `p202409` ~ `p202612`（当前月 2026-09 往前 24 个月 = 2024-09，往后 3 个月 = 2026-12），历史数据全在窗口内，安全。

但如果你的业务需要保留 5 年历史（比如财务审计），**必须把 start 调到 -60，或者把冷数据归档到 S3**（对应 R5 需求，课 12 讲过 S3 TVF 读冷数据）。动态分区删除数据是**静默**的，不会问你要不要备份。
</details>

---

## 🚀 下一步

Task 2：[数据接入：批量 + 实时双链路](./task-2-数据接入.md)
