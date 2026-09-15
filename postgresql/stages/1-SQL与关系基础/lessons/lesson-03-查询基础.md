# 课 3 · 查询基础

> 📍 故事中的位置：主角（一条订单）出生了，现在要开始"被找"——管理后台找它、详情点开看它、运营拉报表算它、领导要本月 GMV 它得上

## 本课目标

学完本课后，你能：

1. 用 WHERE / ORDER BY / LIMIT 写出"过滤 + 排序 + 分页"的标准列表查询，并知道 OFFSET 大时的性能代价
2. 用 INNER / LEFT / RIGHT / FULL JOIN 写出多表关联查询，知道什么时候该用哪种
3. 用五大聚合函数（COUNT / SUM / AVG / MIN / MAX）与 GROUP BY 做统计，掌握 HAVING 的用法

## 知识点清单

| 知识点 | 关键点 |
|---|---|
| **3.1 WHERE / ORDER BY / LIMIT** | · 比较运算符与 BETWEEN / IN / LIKE / IS NULL · 逻辑组合 AND / OR / NOT 与括号优先级 · `ORDER BY` 多列与 NULL 排序（NULLS FIRST/LAST） · `LIMIT` + `OFFSET` 分页的代价（offset 大时慢） · 替代方案：键集分页（seek / keyset pagination） |
| **3.2 JOIN 家族** | · 交叉积 / INNER JOIN / LEFT JOIN / RIGHT JOIN / FULL OUTER JOIN · ON 条件 vs USING · 派生表（FROM 子查询当成一张表） · 何时用 JOIN vs 用子查询（性能取舍，阶段 3 详细讲） |
| **3.3 聚合与 GROUP BY** | · 5 大聚合：`COUNT` / `SUM` / `AVG` / `MIN` / `MAX` · `GROUP BY` 语义（聚合键） · `HAVING` 与 WHERE 的位置差异（先过滤行 vs 后过滤组） · `DISTINCT` 去重 · 常见陷阱：PG 严格模式禁止 SELECT 非聚合列 |

## 故事主线中的情节定位

主角"被找"这一节——列表查询（"这个用户的全部订单"）、详情查询（"这个订单号是什么"）、统计查询（"本月 GMV 是多少"）。读者学完日常 80% 业务查询的写法，**阶段 1 三课闭环**：能装库（课 1）、能建房（课 2）、能找东西（课 3）。

## 正文

## 📌 知识点导航

本课首批（首批 = 课 3 全部 3 个知识点，是阶段 1 收官批）覆盖：

| 节 | 知识点 | 核心问题 |
|---|---|---|
| 第三幕（一） | 3.1 WHERE / ORDER BY / LIMIT | 怎么"过滤 + 排序 + 分页"地找到一个订单列表 |
| 第三幕（二） | 3.2 JOIN 家族 | 怎么把"订单 + 用户 + 商品"拼到一起看 |
| 第三幕（三） | 3.3 聚合与 GROUP BY | 怎么从一堆订单里"算出一个数字"（本月 GMV / 状态分布） |

---

## 第一幕 · 起源与场景引入

### 一个真实的工作场景

上一课你把 `orders` 表建好了，往里面插了 1000 条订单。现在 PM 在群里 @ 你：

> "后台要上一个**订单列表页**，前端要求：能按 `user_id` 过滤、按 `created_at` 倒序、一页 20 条、能翻页。"

你心里想：这不就是 `SELECT ... ORDER BY ... LIMIT 20 OFFSET ?` 吗？

PM 接着发：

> "对了，**还要一个销售月报**：本月 GMV（成交总额）、本月订单数、人均客单价、按状态分组的订单数。"

你又想了想：这就是 `SUM(amount) / COUNT(*) / AVG(amount) / GROUP BY status`。

PM 又 @ 一次：

> "还有个事儿，订单详情页要展示：订单信息 + 下单用户昵称 + 商品名称 + 商品分类——**4 张表拼一起**。"

你心里咯噔一下：这是 `JOIN`，但是 `JOIN` 有几种？我到底该用哪种？

**订单出生了，现在轮到"找它、读它、算它"——这就是课 3 的事**。这一课结束，阶段 1 三课闭环，**日常 80% 的业务查询都能写**。

### 一个关于"查询"本质的小类比

你可以把数据库查询想成"在一堆纸盒子里找东西"：

- **WHERE** —— 在哪层楼找？（过滤）
- **ORDER BY** —— 找到了按什么顺序摆出来？
- **LIMIT / OFFSET** —— 一次搬多少、从第几盒开始？
- **JOIN** —— 一件商品少了，再去隔壁货架拿配套的盒子
- **聚合 / GROUP BY** —— 把同类的盒子归一堆，最后数出"这一堆一共多少"

这一课就是把这五件事逐个讲透。

---

## 第二幕 · 认知冲突

光会写 `SELECT *`，**实际落地有 4 类隐藏陷阱**：

**陷阱一：`SELECT *` 直接上线**

```sql
-- 写法看起来"能跑"，但你真的不该这么写
SELECT * FROM orders WHERE user_id = 123 ORDER BY created_at DESC LIMIT 20;
```

`SELECT *` 在开发环境没事，在生产有 3 个雷：① 多扫不必要字段（性能浪费）② JSON 字段顺序变了直接炸前端 ③ 给前端多塞字段是信息泄露风险。**PG 不会拦你，但你应当自觉**。

**陷阱二：分页用 `OFFSET 100000` —— 慢到爆炸**

```sql
-- 翻到第 50000 页：扫描 1000000 行才吐出 20 条
SELECT * FROM orders ORDER BY created_at DESC LIMIT 20 OFFSET 1000000;
```

OFFSET 越大，PG 必须扫描并丢弃前面所有跳过的行——**深分页场景，OFFSET 是线性退化**。后面第三幕会教替代方案：**键集分页（seek / keyset）**。

**陷阱三：JOIN 错了整个数据集"消失"**

```sql
-- 用户没下过单 → INNER JOIN 直接把它丢了，PM 问"为什么这个用户查不到"
SELECT u.id, u.name, o.id AS order_id
FROM users u
INNER JOIN orders o ON o.user_id = u.id;
```

**INNER JOIN 只保留"两边都匹配"的行**——这往往是新手写"为什么我少了一行数据"的根源。LEFT JOIN 才会把左表全保留下来（右表没匹配就 NULL）。

**陷阱四：PG 严格模式禁止"SELECT 非聚合列"**

```sql
-- 这句在 PG 直接报错（PG 比 MySQL 严格）
SELECT user_id, status, amount FROM orders GROUP BY user_id;
-- ERROR:  column "orders.status" must appear in the GROUP BY clause
```

PG 与标准 SQL 一致：`SELECT` 里凡是不是聚合函数的列，**必须**出现在 `GROUP BY` 里。MySQL 那种"宽松模式"在 PG 不存在。这件事**早撞上比晚撞好**。

---

## 第三幕 · 层层揭示

### （一）知识点 3.1 · WHERE / ORDER BY / LIMIT

#### 一句话定义

**WHERE 过滤行、ORDER BY 排序、OFFSET/LIMIT 取一段**——三件套组成标准列表查询。

#### 直觉建立

把 1000 条订单想象成桌子上 1000 张便利贴：

- WHERE = 撕掉不符合条件的（保留 `user_id = 123` 的）
- ORDER BY = 把剩下的按"时间"重新摆一遍
- LIMIT 20 OFFSET 20 = 从第 21 张开始往后取 20 张

#### WHERE 的语法四要素

```sql
SELECT 列 FROM 表 WHERE 条件
```

**1. 比较运算符**：`=`, `<>`, `>`, `<`, `>=`, `<=`

```sql
SELECT * FROM orders WHERE status = 2;                    -- 状态 = 已付
SELECT * FROM orders WHERE amount >= 100 AND amount < 1000; -- 100 ≤ 金额 < 1000
```

**2. 三个范围匹配器**：`BETWEEN` / `IN` / `LIKE`

```sql
-- BETWEEN 闭区间（包含两端）
SELECT * FROM orders WHERE amount BETWEEN 100 AND 500;

-- IN 命中列表中任一
SELECT * FROM orders WHERE status IN (1, 2);  -- 待付或已付
SELECT * FROM orders WHERE user_id IN (12, 45, 78);

-- LIKE 模糊匹配（% = 任意串，_ = 单字符）
SELECT * FROM orders WHERE order_no LIKE 'ORD2026%';  -- 以 ORD2026 开头
SELECT * FROM orders WHERE order_no LIKE '%_BK';      -- 以 _BK 结尾
```

**3. NULL 比较必须用 `IS NULL`**

```sql
-- ❌ 错的：NULL = NULL 在 SQL 里不成立
SELECT * FROM orders WHERE paid_at = NULL;
-- ✅ 正确
SELECT * FROM orders WHERE paid_at IS NULL;        -- 未支付
SELECT * FROM orders WHERE paid_at IS NOT NULL;    -- 已支付
```

> ❓ **为什么 `= NULL` 不行？** 因为 SQL 把 NULL 定义为"未知"——"未知的金额"等于"未知的金额"不能判断为 TRUE，只能是 UNKNOWN。三值逻辑（TRUE / FALSE / UNKNOWN）里 UNKNOWN 视为不满足。

**4. 逻辑组合 AND / OR / NOT**

```sql
-- AND: 全满足
SELECT * FROM orders WHERE status = 2 AND amount >= 100;

-- OR: 任一满足（关键：用括号把 OR 包起来）
SELECT * FROM orders WHERE status = 2 OR (status = 1 AND amount >= 1000);

-- NOT: 取反
SELECT * FROM orders WHERE NOT (status = 3);  -- 不是"取消"
```

> 💡 **优先级口诀**：AND 优先于 OR（数学里"乘优先于加"）。**多写一层括号永远不会错**。

#### ORDER BY：排序

```sql
-- 单列排序（默认 ASC = 升序）
SELECT * FROM orders ORDER BY created_at;

-- 倒序：DESC
SELECT * FROM orders ORDER BY created_at DESC;

-- 多列排序：先按 user_id 升序，再按 created_at 倒序
SELECT * FROM orders ORDER BY user_id ASC, created_at DESC;

-- NULL 排序：NULLS FIRST（NULL 排最前） / NULLS LAST（NULL 排最后）
SELECT * FROM orders ORDER BY paid_at DESC NULLS LAST;  -- 未支付排在最后
```

> 💡 **PG `NULLS` 默认行为**：升序（ASC）时 `NULLS LAST`（NULL 排最后）；降序（DESC）时 `NULLS FIRST`（NULL 排最前）。想精确控制要显式 `NULLS FIRST / LAST`，否则依赖默认（生产 SQL **强烈建议显式写**，避免不同 DB 切换时默认值不一致踩坑）。

#### OFFSET / LIMIT：分页的两面

**正面：简单分页**

```sql
SELECT * FROM orders ORDER BY created_at DESC
LIMIT 20                              -- 一页 20 条
OFFSET 0;                             -- 第 1 页：跳 0 条
-- OFFSET 20                          -- 第 2 页：跳 20 条
-- OFFSET 1000000                     -- 深分页 ❌
```

**反面：深分页性能灾难**

```
OFFSET 1 000 000 的执行过程：
  PG 必须先扫描出 1 000 000 条"已经按 created_at 排好序"的行
  然后丢弃，只留最后 20 条

→ 时间复杂度 O(N)，N 越大越慢
→ 真实案例：100 万订单的表，OFFSET 50 万时单次查询从 5ms 退化到 800ms
```

**替代方案：键集分页（seek / keyset pagination）**

```sql
-- 第一页：拿最新 20 条
SELECT * FROM orders ORDER BY created_at DESC, id DESC
LIMIT 20;
-- 假设最后一行的 created_at = 2026-09-06 17:00:00, id = 9527

-- 第二页：告诉 PG "给我比这更老的下一批"
SELECT * FROM orders
WHERE (created_at, id) < ('2026-09-06 17:00:00', 9527)
ORDER BY created_at DESC, id DESC
LIMIT 20;
```

> 💡 **为什么这种写法快？** PG 在 `(created_at, id)` 上有索引时，**直接定位到上次的位置往后扫 20 条**——O(log N + 20)，跟 OFFSET 大小无关。前端只要记住"上一页最后一行"的 (created_at, id) 即可。
>
> 💡 **为什么加 `id`？** 同时间戳会有多个订单（毫秒级冲突），单靠 `created_at` 还会丢行 / 重复。**复合键必须唯一**。

#### 示例演示

```sql
-- 完整实战例：用户 123 的"待付 + 已付"订单，按时间倒序，一页 20 条
SELECT
    id, order_no, amount, status, created_at, paid_at
FROM orders
WHERE user_id = 123
  AND status IN (1, 2)                  -- 排除已取消 (3)
ORDER BY created_at DESC
LIMIT 20;
```

#### 常见误区 6 条

| 误区 | 反例 | 正解 |
|---|---|---|
| 用 `= NULL` 判空 | `WHERE paid_at = NULL` | `WHERE paid_at IS NULL` |
| LIKE 用左模糊 | `WHERE name LIKE '%kun'`（不走索引） | 尽量前缀匹配：`LIKE 'kun%'`（PG 可用索引） |
| 缺省 ORDER BY 的分页 | `LIMIT 20 OFFSET 20` 不加 `ORDER BY` | 必须有 `ORDER BY`，且**稳定列**（否则同一条订单可能出现在两页） |
| 大 OFFSET 分页 | `OFFSET 1000000` | 改成键集分页 |
| AND/OR 不加括号 | `WHERE a=1 OR b=2 AND c=3`（其实是 `a=1 OR (b=2 AND c=3)`） | 多写一层括号 |
| `SELECT *` 直接用 | 列名全暴露 + 性能浪费 + 隐患 | 显式列名 |

#### 一句话记住

> **WHERE 过滤行，ORDER BY 排顺序，OFFSET 浅分页够用，深分页用键集。**

#### 命令速查卡（3.1）

```sql
-- WHERE 写法
WHERE col = val
WHERE col BETWEEN a AND b       -- 闭区间
WHERE col IN (a, b, c)
WHERE col LIKE 'prefix%'        -- 前缀匹配（可走索引）
WHERE col IS NULL
WHERE NOT (cond)

-- 逻辑组合（AND 优先于 OR）
WHERE a=1 AND (b=2 OR c=3)

-- ORDER BY
ORDER BY col [ASC | DESC]
ORDER BY col1, col2 DESC
ORDER BY col DESC NULLS LAST     -- NULL 排最后

-- 分页
LIMIT n OFFSET m                 -- 浅分页：n=页大小, m=(页号-1)*n
-- 深分页：键集（seek）
WHERE (created_at, id) < (?, ?)  -- 配合索引，O(log N)
```

---

### （二）知识点 3.2 · JOIN 家族

#### 一句话定义

**JOIN = 把两张表的行按某种关系拼一起看**。两张表的"拼法"有 5 种：交叉积（笛卡尔）、INNER、LEFT、RIGHT、FULL。

#### 直觉建立

想象你有两张便利贴墙：

- **左墙**：1000 张订单（`orders`），每张记着 `user_id`
- **右墙**：5000 个用户（`users`），每张记着 `id`、`name`

`JOIN user_id = users.id` 就是"**把墙上每个订单贴到它对应的用户旁边**"——拼好之后，每一行同时有"订单信息 + 用户信息"。

五种拼法的区别，只在于"**如果左墙的某个便利贴右边墙上找不到对应，要不要保留**"：

```
墙上两个便利贴，左:订单 {id=1, user_id=99}，右:用户 {id=99, name=张三}

左:订单 {id=2, user_id=66}，右:用户 (id=66 不存在)

INNER JOIN  →  只保留 id=1 那一条（两边都有匹配）
LEFT JOIN   →  两条都保留；id=2 那行的 name = NULL
RIGHT JOIN  →  同 LEFT，但方向反过来（保留右表）
FULL JOIN   →  两条都保留，左右任一缺失就 NULL
CROSS JOIN  →  1000 × 5000 = 500 万行组合（笛卡尔积）⚠️
```

#### 4 种生产常用 JOIN

**1. INNER JOIN（最常用）**

```sql
-- 只保留两边都匹配的行（重叠区）
SELECT o.id, o.order_no, o.amount, u.name AS user_name
FROM orders o
INNER JOIN users u ON o.user_id = u.id;
```

> 💡 **简单理解为"两个集合的交集"**——任何一个订单如果它的 user_id 在 users 表里不存在，它会被丢掉。

**2. LEFT JOIN（管理后台最爱）**

```sql
-- 保留左表所有行；右表没匹配就 NULL
SELECT u.id, u.name, COUNT(o.id) AS order_count
FROM users u
LEFT JOIN orders o ON o.user_id = u.id
WHERE u.created_at >= '2026-01-01'
GROUP BY u.id, u.name;
```

"所有用户 + 他们的订单数"——包括**没下过单的用户**（订单数 = 0）。LEFT JOIN 是"别把数据搞丢"的默认值。

**3. RIGHT JOIN**

```sql
-- RIGHT JOIN 在 PG 里几乎不用——把左右表调换顺序直接写成 LEFT JOIN 更直觉
SELECT u.id, u.name, o.id AS order_id
FROM orders o
RIGHT JOIN users u ON o.user_id = u.id;
-- 等价于上面把 users 和 orders 调换的 LEFT JOIN
```

> 💡 **生产实践**：RIGHT JOIN 代码难读，建议**统一用 LEFT JOIN**——把"主表"写在 FROM 后面，"附加信息表"用 LEFT JOIN 拼上去。

**4. FULL OUTER JOIN**

```sql
-- 两边都保留；任一边没匹配就 NULL
SELECT u.id, u.name, o.id AS order_id
FROM users u
FULL OUTER JOIN orders o ON o.user_id = u.id;
```

**什么时候用？** 几乎只在"对账 / 找差异"场景：

```sql
-- 例：找出"有用户但没下过单" 或 "有订单但用户已注销" 的不一致
SELECT
    u.id   AS user_only,
    o.id   AS order_only,
    CASE
        WHEN u.id IS NOT NULL AND o.id IS NULL THEN '用户没下过单'
        WHEN u.id IS NULL AND o.id IS NOT NULL THEN '订单用户已注销'
    END AS status
FROM users u
FULL OUTER JOIN orders o ON o.user_id = u.id
WHERE u.id IS NULL OR o.id IS NULL;
```

#### ON vs USING

```sql
-- ON：最通用，可写任意条件
SELECT * FROM orders o JOIN users u ON o.user_id = u.id;

-- USING：当两表列名相同时的简写（结果合并成一个列）
SELECT * FROM orders JOIN users USING (user_id);  -- 列名必须完全相同
-- 等价于：ON orders.user_id = users.user_id，且结果不重复 user_id 列
```

#### NATURAL JOIN（高危·不推荐）

```sql
-- NATURAL 自动按"所有同名列"JOIN——表一加列就炸
SELECT * FROM orders NATURAL JOIN users;
```

> ⚠️ **生产禁止使用 NATURAL JOIN**：它会自动按"两表所有同名列"JOIN——今天表加了 `created_at` 同名列，原本能跑的 SQL 直接变成笛卡尔×筛选，**极难调试**。

#### 派生表（FROM 子查询）

```sql
-- 把子查询当一张"临时表"用
SELECT
    o.id, o.amount, o.created_at,
    u.name AS user_name,
    ua.total_amount AS user_lifetime_amount
FROM orders o
JOIN users u ON o.user_id = u.id
LEFT JOIN (
    SELECT user_id, SUM(amount) AS total_amount
    FROM orders
    WHERE status = 2
    GROUP BY user_id
) ua ON ua.user_id = o.user_id
WHERE o.amount > 1000;
```

> 💡 **阶段 2 课 6 会系统讲 CTE（`WITH ... AS`）**——比派生表更清晰、可读性更高。这里先认个脸。

#### 示例演示：完整业务查询

```sql
-- 订单详情页：订单 + 用户 + 商品 + 分类
SELECT
    o.id          AS order_id,
    o.order_no,
    o.amount,
    o.status,
    u.name        AS user_name,
    p.title       AS product_title,
    c.name        AS category_name,
    o.created_at
FROM orders o
INNER JOIN users         u ON o.user_id       = u.id
INNER JOIN order_items   oi ON oi.order_id     = o.id
INNER JOIN products      p ON oi.product_id   = p.id
INNER JOIN categories    c ON p.category_id   = c.id
WHERE o.id = 9527;
```

#### 常见误区 6 条

| 误区 | 反例 | 正解 |
|---|---|---|
| 用 INNER JOIN 漏用户 | `INNER JOIN orders` 后"用户消失了" | 改成 LEFT JOIN |
| JOIN 后用 `WHERE` 过滤 NULL | WHERE name = NULL 不命中 | 用 `IS NULL` 或 `IS NOT NULL` |
| RIGHT JOIN 写出难维护 SQL | 习惯 RIGHT JOIN | 全部转 LEFT JOIN，把"主表"写 FROM |
| NATURAL JOIN | `NATURAL JOIN users` | 禁止使用，显式写 ON |
| JOIN 条件用 `WHERE`（老式逗号语法） | `FROM a, b WHERE a.id = b.id` | 用 `FROM a JOIN b ON ...` |
| JOIN 之后 SELECT `*` | 多张表的 `*` 含义不清 | 显式列名 + 用表别名限定（`o.id` / `u.name`） |

#### 一句话记住

> **INNER = 重叠，LEFT = 保留左表，RIGHT = 等同 LEFT 调换，FULL = 都保留。生产 99% 用 INNER + LEFT。**

#### 命令速查卡（3.2）

```sql
-- 五种 JOIN（默认 INNER）
... FROM a JOIN b ON a.id = b.aid;            -- INNER JOIN
... FROM a LEFT JOIN b ON a.id = b.aid;       -- 保留 a
... FROM a RIGHT JOIN b ON a.id = b.aid;      -- 保留 b（生产建议改写为 LEFT）
... FROM a FULL JOIN b ON a.id = b.aid;       -- 两边都保留
... FROM a CROSS JOIN b;                       -- 笛卡尔积（慎用）

-- USING（同名列合并）
... FROM a JOIN b USING (id);

-- 派生表（FROM 子查询）
... FROM a JOIN (SELECT ... FROM x) AS sub ON ...

-- 别名 + 限定列
... FROM orders o JOIN users u ON o.user_id = u.id;
SELECT o.id, u.name;
```

---

### （三）知识点 3.3 · 聚合与 GROUP BY

#### 一句话定义

**聚合 = 把多行压成一行**。`GROUP BY` 把数据切成若干组，每组压一个数字。`HAVING` 是"组级别"的 WHERE。

#### 直觉建立

10 个订单散在桌上——你想知道"每个用户各下了多少单"：

- **不分组**算聚合 → "所有订单加起来一共 10 单"（一条结果）
- **按 user_id 分组**算聚合 → "用户 1 下 3 单 / 用户 2 下 5 单 / 用户 3 下 2 单"（3 条结果）

`GROUP BY` 的本质是：**"对谁聚合，结果就按谁分组"**。

#### 5 大聚合函数

```sql
SELECT
    COUNT(*)        AS order_count,        -- 总行数（含 NULL 行）
    COUNT(amount)   AS amount_not_null,    -- 不为 NULL 的行数
    COUNT(DISTINCT user_id) AS unique_users, -- 去重后的用户数
    SUM(amount)     AS gmv,                -- 总和（金额用 NUMERIC）
    AVG(amount)     AS avg_amount,         -- 平均值
    MIN(amount)     AS min_amount,         -- 最小
    MAX(created_at) AS latest_at           -- 最大（最新）
FROM orders
WHERE status = 2;                          -- 只算已付订单
```

> 💡 **`COUNT(*)` vs `COUNT(col)` 区别**：
> - `COUNT(*)` 统计"行数"——不管列值是不是 NULL，都算
> - `COUNT(col)` 统计"该列**不是 NULL** 的行数"
>
> 例：10 行订单，3 行 `paid_at` 为 NULL → `COUNT(*) = 10`，`COUNT(paid_at) = 7`

#### GROUP BY：分组聚合

```sql
-- 每个状态的订单数 + 总额
SELECT
    status,
    COUNT(*)   AS cnt,
    SUM(amount) AS total
FROM orders
GROUP BY status
ORDER BY status;
```

```
结果示例：
 status | cnt |   total
--------+-----+----------
   1    | 120 |  18500.00  -- 待付
   2    | 850 | 425600.50  -- 已付
   3    |  30 |   1200.00  -- 取消
```

**多列分组：按"用户 × 月份"统计**

```sql
SELECT
    user_id,
    DATE_TRUNC('month', created_at) AS month,  -- 截到月初
    COUNT(*)   AS order_cnt,
    SUM(amount) AS gmv
FROM orders
WHERE status = 2
GROUP BY user_id, DATE_TRUNC('month', created_at)
ORDER BY user_id, month DESC;
```

#### HAVING：组级别筛选

```sql
-- 找出"下单超过 5 次"的高价值用户
SELECT
    user_id,
    COUNT(*) AS order_cnt,
    SUM(amount) AS gmv
FROM orders
WHERE status = 2
GROUP BY user_id
HAVING COUNT(*) > 5        -- 组级别筛选（不能用 WHERE）
ORDER BY gmv DESC
LIMIT 20;
```

**WHERE vs HAVING 的位置**

```
SQL 执行顺序（记牢这个）：
  FROM → WHERE → GROUP BY → HAVING → SELECT → DISTINCT → ORDER BY → LIMIT

  WHERE  在 GROUP BY 之前 → 过滤的是"行"
  HAVING 在 GROUP BY 之后 → 过滤的是"组"
```

| 项 | 过滤对象 | 出现的聚合函数？ | 例 |
|---|---|---|---|
| **WHERE** | 行 | 不能用 `COUNT(*)` 这类聚合 | `WHERE amount > 1000` |
| **HAVING** | 组 | 只能用聚合或出现在 GROUP BY 的列 | `HAVING COUNT(*) > 5` |

#### DISTINCT：去重

```sql
-- 不去重：每条订单一行
SELECT user_id FROM orders;

-- 去重：每用户一行
SELECT DISTINCT user_id FROM orders;

-- 多列去重：组合唯一
SELECT DISTINCT user_id, status FROM orders;  -- 每个 (user_id, status) 组合一行
```

#### PG 严格模式：SELECT 列必须在 GROUP BY 里

```sql
-- ❌ PG 报错
SELECT user_id, status, amount FROM orders GROUP BY user_id;
-- ERROR: column "orders.status" must appear in the GROUP BY clause or be used in an aggregate function

-- ✅ 三种改法：

-- 改法 1：把列加进 GROUP BY
SELECT user_id, status, SUM(amount) FROM orders GROUP BY user_id, status;

-- 改法 2：把它包成聚合
SELECT user_id, MAX(status) AS status, SUM(amount) FROM orders GROUP BY user_id;

-- 改法 3：用 ANY_VALUE（PG 兼容别名，给 MySQL 习惯的人看）
-- 实际生产建议改法 1，最稳
```

> 💡 **为什么 PG 严格？** 因为"非聚合列在一组里可能多个值"——SQL 不知道你要哪个。MySQL 默认是"任选一个"，新手觉得很方便但**生产数据错乱**就完了。PG 直接报错，逼你写对。

#### 示例演示：完整月报表

```sql
-- 本月销售月报
SELECT
    DATE_TRUNC('day', created_at) AS day,
    COUNT(*)                       AS order_cnt,
    COUNT(DISTINCT user_id)        AS unique_buyers,
    SUM(amount)                    AS gmv,
    AVG(amount)                    AS avg_amount,
    SUM(CASE WHEN status = 3 THEN 1 ELSE 0 END) AS cancelled_cnt
FROM orders
WHERE created_at >= DATE_TRUNC('month', CURRENT_DATE)
  AND created_at <  DATE_TRUNC('month', CURRENT_DATE) + INTERVAL '1 month'
GROUP BY DATE_TRUNC('day', created_at)
HAVING SUM(amount) > 0          -- 过滤掉 GMV=0 的空日
ORDER BY day;
```

#### 常见误区 6 条

| 误区 | 反例 | 正解 |
|---|---|---|
| SELECT 非聚合列（PG 严格模式） | `SELECT user_id, status FROM orders GROUP BY user_id` | 列加 GROUP BY 或包成聚合 |
| WHERE 里写聚合 | `WHERE COUNT(*) > 5` ❌ | 用 HAVING |
| HAVING 里写行级条件 | `HAVING amount > 1000`（amount 不是聚合、也没在 GROUP BY） | 改写为 WHERE |
| 忘了 GROUP BY 就想"分组" | 想看每个用户订单数，结果给了总订单数 | 显式 `GROUP BY user_id` |
| SUM(整型) 期望小数 | `SUM(integer_field)` 不会自动转浮点 | 用 `SUM(amount::numeric)` 或确保字段是 numeric |
| 聚合时 NULL 被忽略却忘了 | `AVG(amount)` 跳过 NULL 行——分母不是 COUNT(*) | 必要时用 `COALESCE(col, 0)` |

#### 一句话记住

> **聚合 = 多行压一行，GROUP BY = 按什么切组，HAVING = 切完再过滤组。**

#### 命令速查卡（3.3）

```sql
-- 5 大聚合
COUNT(*) / COUNT(col) / COUNT(DISTINCT col)
SUM(col) / AVG(col) / MIN(col) / MAX(col)

-- 分组
GROUP BY col1, col2 ...
GROUP BY ROLLUP(col1, col2)    -- 加小计 / 总计（阶段 2 详细讲）

-- 组筛选（HAVING）
HAVING COUNT(*) > 5
HAVING SUM(amount) > 1000

-- 去重
SELECT DISTINCT col FROM ...

-- 字符串聚合（PG 名字叫 STRING_AGG）
SELECT user_id, STRING_AGG(order_no, ', ' ORDER BY created_at) AS order_list
FROM orders
GROUP BY user_id;
```

> ⚠️ **常见错误写法**：很多人照 Oracle / SQL Server 写 `LISTAGG(...)` ——**PG 不支持**。PG 用 **`STRING_AGG(expr, separator ORDER BY sort_expr)`**，原生并行支持 `ORDER BY` 子句（PG 9.0 引入，PG 17 一致）。别 Oracle / MySQL / PG 分不清乱拼。

---

## 第四幕 · 实操验证

### 实验环境

延续前两课：`localhost:5432` 上跑 `postgres:17` 容器，`order_service` 库下 `finance` schema 有 `orders` 表。如果你还没建库 / 表，先把 [lesson-02-表与数据类型.md](lesson-02-表与数据类型.md) 跑一遍，再用下面的 SQL 插一些测试数据。

### 实验 1 · 准备数据

```sql
-- 启动容器（如果还没起）
docker start pg17

-- 连进去
docker exec -it pg17 psql -U postgres -d order_service

-- 设 search_path（如果上节课没设）
SET search_path TO finance, public;

-- 插入 50 个用户
INSERT INTO users (name, email)
SELECT
    'user_' || g,
    'user_' || g || '@example.com'
FROM generate_series(1, 50) AS g
ON CONFLICT (email) DO NOTHING;

-- 插入 200 笔订单（金额 10 ~ 5000，状态 1/2/3 随机）
INSERT INTO orders (order_no, user_id, amount, status, created_at)
SELECT
    'ORD' || to_char(g, 'FM000000'),
    ((g - 1) % 50) + 1,                                  -- 50 个用户循环
    (random() * 4990 + 10)::numeric(10, 2),               -- 金额 10~5000
    CASE WHEN g % 7 = 0 THEN 3 ELSE (CASE WHEN g % 3 = 0 THEN 1 ELSE 2 END) END,
    NOW() - (g || ' minutes')::interval                   -- 时间倒推
FROM generate_series(1, 200) AS g
ON CONFLICT (order_no) DO NOTHING;
```

> 💡 `generate_series(1, 200)` 是 PG 的"行生成器"——返回 200 行（1, 2, 3, ..., 200）。批量造数据时**不要用程序循环 INSERT**，这种集合方式 100x 快。

### 实验 2 · WHERE / ORDER BY / LIMIT（三件套）

```sql
-- 用户 5 的所有已付订单（status=2），按金额倒序
SELECT order_no, amount, created_at
FROM orders
WHERE user_id = 5 AND status = 2
ORDER BY amount DESC
LIMIT 10;

-- 金额 100~500 之间 + 订单号以 'ORD000' 开头
SELECT order_no, amount
FROM orders
WHERE amount BETWEEN 100 AND 500
  AND order_no LIKE 'ORD000%';

-- 已支付但 paid_at 为空的（数据不一致！）
SELECT order_no, status, paid_at
FROM orders
WHERE status = 2 AND paid_at IS NULL;
```

### 实验 3 · JOIN 把订单 + 用户拼起来

```sql
-- 订单详情：订单 + 用户名
SELECT
    o.order_no,
    o.amount,
    o.status,
    u.name AS user_name,
    u.email
FROM orders o
INNER JOIN users u ON o.user_id = u.id
WHERE o.amount > 1000
ORDER BY o.amount DESC
LIMIT 10;

-- 改成 LEFT JOIN：包含"没下过单"的用户
SELECT
    u.id,
    u.name,
    COUNT(o.id) AS order_count,
    COALESCE(SUM(o.amount), 0) AS lifetime_gmv
FROM users u
LEFT JOIN orders o ON o.user_id = u.id
GROUP BY u.id, u.name
HAVING COUNT(o.id) = 0        -- 只看"0 订单用户"
ORDER BY u.id
LIMIT 5;

-- 多表 JOIN：订单 + 用户 + 商品
SELECT
    o.order_no,
    u.name       AS user_name,
    p.title      AS product_title,
    c.name       AS category_name,
    oi.quantity  AS qty,
    oi.unit_price
FROM orders o
INNER JOIN users u       ON o.user_id     = u.id
INNER JOIN order_items oi ON oi.order_id  = o.id
INNER JOIN products p    ON oi.product_id = p.id
INNER JOIN categories c  ON p.category_id = c.id
WHERE o.id = 1;                            -- 看第 1 单的明细
```

### 实验 4 · 聚合 + GROUP BY（月报表）

```sql
-- 按状态分组看订单数 + GMV
SELECT
    status,
    COUNT(*)   AS cnt,
    SUM(amount) AS gmv,
    ROUND(AVG(amount), 2) AS avg_amount
FROM orders
GROUP BY status
ORDER BY status;

-- 多维度：每个用户的本月 GMV
SELECT
    user_id,
    COUNT(*)                   AS order_cnt,
    SUM(amount)                AS mtd_gmv,
    MAX(created_at)            AS latest_order_at
FROM orders
WHERE created_at >= DATE_TRUNC('month', CURRENT_DATE)
  AND status = 2
GROUP BY user_id
HAVING SUM(amount) > 0
ORDER BY mtd_gmv DESC
LIMIT 10;

-- 字符串聚合：本月每个用户的订单号汇总（PG 用 STRING_AGG，不是 LISTAGG）
SELECT
    user_id,
    STRING_AGG(order_no, ', ' ORDER BY created_at DESC) AS order_no_list,
    COUNT(*) AS cnt
FROM orders
WHERE created_at >= DATE_TRUNC('month', CURRENT_DATE)
GROUP BY user_id
HAVING COUNT(*) >= 3
ORDER BY cnt DESC
LIMIT 5;
```

### 实验 5 · OFFSET vs 键集分页的性能差

```sql
-- 看 EXPLAIN：浅 OFFSET
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders ORDER BY created_at DESC, id DESC
LIMIT 20 OFFSET 0;

-- 深 OFFSET（200 笔数据看不出，但体现思路）
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders ORDER BY created_at DESC, id DESC
LIMIT 20 OFFSET 10000;

-- 对比：键集分页（前提：建了索引）
CREATE INDEX idx_orders_created_id ON orders (created_at DESC, id DESC);

EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders
WHERE (created_at, id) < ('2026-09-06 12:00:00', 5000)
ORDER BY created_at DESC, id DESC
LIMIT 20;
```

> 💡 真实生产表（百万级行）下，`OFFSET 100000` 会明显退化；键集分页无论起点都是 O(log N + 页大小)。**管理后台列表页、Feed 流、订单分页**都应该优先用键集。

---

## 第五幕 · 体系收束

### 本课小结（3 个知识点的全景）

```
本课 3 个知识点 = 日常 80% 业务查询的写法：

  3.1 WHERE / ORDER BY / LIMIT → 列表 / 详情页
       WHERE 过滤行
       ORDER BY 排顺序（NULLS FIRST/LAST）
       LIMIT n OFFSET m（浅分页）
       替代方案：键集分页（深分页唯一解）

  3.2 JOIN 家族                → 多表拼数据
       INNER = 重叠 / LEFT = 保留左表 / RIGHT = 反向 LEFT / FULL = 都保留
       生产 99% 用 INNER + LEFT + 别名限列

  3.3 聚合 + GROUP BY          → 算总数 / 月报 / 分布
       5 大聚合：COUNT / SUM / AVG / MIN / MAX
       GROUP BY = 按什么切组
       HAVING = 切完后再过滤（与 WHERE 别混）
       PG 严格模式：SELECT 非聚合列必进 GROUP BY
```

### 阶段 1 三课的整合视图

```
┌─────────────── 阶段 1 · SQL 与关系基础 ───────────────┐
│                                                       │
│  课 1 认识 PostgreSQL                                  │
│   1.1 PG 是什么 / Docker 起容器 / pgcli               │
│   1.2 三大件 + 连接串                                 │
│   1.3 cluster → db → schema → table 四层 + search_path│
│            ↓                                          │
│  课 2 表与数据类型   ← 你已经会                       │
│   2.1 八大类型族（数值/字符串/时间/布尔/JSON...）        │
│   2.2 五约束 + IDENTITY                               │
│   2.3 CRUD + RETURNING + WHERE 安全心法               │
│            ↓                                          │
│  课 3 查询基础    ← 你刚学完                           │
│   3.1 WHERE / ORDER BY / LIMIT（+ 键集分页）           │
│   3.2 JOIN 家族（INNER / LEFT / RIGHT / FULL）         │
│   3.3 聚合 + GROUP BY + HAVING + DISTINCT              │
│                                                       │
└───────────────────────────────────────────────────────┘

学完课 3 之后的能力：
  ✅ 用 Docker 起一个 PG 17 容器
  ✅ 在 order_service 库里建带约束的 orders / users / products 表
  ✅ 用 CRUD（INSERT RETURNING / SELECT / UPDATE / DELETE）维护数据
  ✅ 写日常 80% 业务查询（列表 / 详情 / 多表拼 / 月报）
  ✅ 知道常见陷阱（NULL 比较 / SELECT * / OFFSET 深分页 / JOIN 选型 / PG 严格模式）

下一阶段进入：
  阶段 2 · 数据建模与 SQL 进阶
    → 把表组织成系统（关系建模 / 视图 / CTE / 窗口函数）
```

### 决策心法（学完课 3 应能回答的 6 个判断）

| 问题 | 答案 |
|---|---|
| 列表页分页用什么？ | **数据量小**：OFFSET 简单直接；**数据量大**：键集分页（必须） |
| INNER 还是 LEFT？ | **要数据完整性（"别把行丢了"）**：LEFT；**要严格匹配**：INNER |
| 该不该 SELECT *？ | **永远不**——显式列名（性能 + 安全 + 维护） |
| 怎么查"列 = NULL"？ | **永远是 `IS NULL`**，不是 `= NULL` |
| 月报 SQL 该用聚合？ | **是**——5 大聚合 + GROUP BY；过滤组用 HAVING |
| 业务查询里能用 NATURAL JOIN 吗？ | **不能**——禁止；用显式 ON |

### 命令速查卡（综合）

```sql
-- 列表查询（最常用）
SELECT col1, col2
FROM t
WHERE col3 = X AND col4 IN (a, b)
ORDER BY col5 DESC
LIMIT 20 OFFSET 0;                     -- 浅分页；深分页改成键集

-- 多表查询
SELECT o.id, u.name, p.title
FROM orders o
INNER JOIN users u    ON o.user_id  = u.id
INNER JOIN order_items oi ON oi.order_id = o.id
INNER JOIN products p ON oi.product_id = p.id
WHERE u.id = 123;

-- 聚合统计
SELECT
    user_id,
    COUNT(*) AS cnt,
    SUM(amount) AS gmv,
    AVG(amount) AS avg_amt,
    MIN(created_at) AS first_at,
    MAX(created_at) AS latest_at
FROM orders
WHERE status = 2
  AND created_at >= '2026-09-01'
GROUP BY user_id
HAVING SUM(amount) > 0
ORDER BY gmv DESC
LIMIT 10;

-- PG 关键提醒
--  · 永远显式列名，不要 SELECT *
--  · NULL 必须用 IS NULL / IS NOT NULL
--  · 字符串聚合是 STRING_AGG（不是 LISTAGG）
--  · 深分页用键集：WHERE (created_at, id) < (?, ?)
--  · JOIN 选型：能 LEFT 别漏行，能 INNER 别冗余
```

### 事实速查（核查于 2026-09-06）

| 事实 | 当前值 | 来源 |
|---|---|---|
| `LIKE 'prefix%'` 走索引 | **前缀匹配**可走 B+Tree 索引；左模糊（`%prefix`）不行 | postgresql.org/docs/current/indexes-types |
| ORDER BY NULLS FIRST / LAST | **PG 原生支持**；默认 NULL 视为比非 NULL 大 | postgresql.org/docs/current/queries-order |
| OFFSET 性能 | **线性退化**（OFFSET N 必须扫描 N+页大小 行） | postgresql.org/docs current（性能章节，实践共识） |
| 键集分页的复合键写法 | **PG 支持行值比较**：`WHERE (a, b) < (a_val, b_val)`，可走索引 | postgresql.org/docs/current/functions-comparisons |
| 字符串聚合函数 | **PG 原生 `STRING_AGG(expr, sep [ORDER BY ...])`**；PG 不支持 Oracle/SQL Server 的 `LISTAGG`；MySQL 是 `GROUP_CONCAT` | postgresql.org/docs/current/aggregates |
| JOIN 重排 | LEFT / RIGHT JOIN 可被 PG 优化器**重排**；FULL JOIN **不可**重排（必须按书写顺序） | postgresql.org/docs current（geqo / explicit-joins 章节，实践共识） |
| PG 严格模式 SELECT 列 | **PG 严格遵循 SQL 标准**：非聚合列必须出现 GROUP BY | postgresql.org/docs/current/queries-group |
| GEQO 阈值 | 默认 `geqo_threshold = 12`；>= 12 个 FROM 项启用遗传算法；< 12 走穷举 | postgresql.org/docs/current/geqo |
| `COUNT(*)` vs `COUNT(col)` | `COUNT(*)` 统计行；`COUNT(col)` 跳过 NULL | postgresql.org/docs/current/aggregates |

---

## 🧭 课程导航

> **本课在阶段 1 的位置**：阶段 1 三课中的**收官课**——课 1 起库、课 2 建表、课 3 找数据。
>
> **阶段 1 三课闭环 ✅**：
>
> - 课 1 认识 PostgreSQL（[上一课](lesson-01-认识PostgreSQL.md)）
> - 课 2 表与数据类型（[上一课](lesson-02-表与数据类型.md)）
> - 课 3 查询基础 ← **你在这里（阶段 1 收官）**
>
> **整课任务完成标记**：3.1 + 3.2 + 3.3 三知识点均已交付 ✅（P0=0，3 项事实核查 PASS：STRING_AGG/键集分页/GEQO-12 阈值，见事实速查表）。

- 上一课：[课 2 表与数据类型（数据类型 / 建表 / CRUD）](lesson-02-表与数据类型.md)（同阶段）
- 下一课：[课 4 关系建模（主键/外键/一对多/多对多/范式）](../2-数据建模与SQL进阶/lessons/lesson-04-关系建模.md)（**跨阶段 → 阶段 2**）
- 返回目录：[`02-课程目录.md`](../../02-课程目录.md)
- 上一阶 / 下一阶：阶段 1 已闭环；进入**阶段 2 · 数据建模与 SQL 进阶**

> 🎉 **阶段 1 闭环达成 ——你现在拥有日常 80% 业务查询能力**：
>
> - ✅ 用 Docker 起 PG 17 容器
> - ✅ 建库 / 建表（带约束与 IDENTITY 主键）
> - ✅ 写 CRUD（INSERT RETURNING / 显式列 / 安全 DELETE）
> - ✅ 写列表 / 详情查询（WHERE + ORDER BY + LIMIT，必要时键集分页）
> - ✅ 写多表查询（INNER + LEFT JOIN）
> - ✅ 写月报聚合（5 大聚合 + GROUP BY + HAVING）
>
> **阶段 2 预告 · 把表组织成系统**：
>
> - 课 4 关系建模（主键/外键 / 一对多/多对多 / 范式 vs 反范式）
> - 课 5 视图与函数（普通视图 / 物化视图 / 存储过程 / 触发器）
> - 课 6 CTE 与子查询（WITH 子句 / 递归 CTE / 相关子查询）
> - 课 7 窗口函数（OVER / 排名 / 滑动聚合）
