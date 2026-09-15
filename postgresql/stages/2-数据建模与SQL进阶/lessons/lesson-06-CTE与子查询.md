# 课 6 · CTE 与子查询

> 📍 故事中的位置：复杂查询越来越长——主角的故事开始分层（先看哪里、再看哪里）

## 本课目标

学完本课后，你能：

1. 用普通 CTE 把多层嵌套的查询**改写成"先…再…最后…"的流水线**，并知道 PG 12+ 什么时候会把它"吃掉"
2. 用递归 CTE 遍历**树结构**（组织架构、评论链、分类）与**图结构**（链路追踪），并防住无限递归
3. 区分相关子查询与 JOIN 的取舍，知道哪些写法 PG 优化器能自动救、哪些救不了

## 知识点清单

| 知识点 | 关键点 |
|---|---|
| **6.1 WITH 子句** | · CTE 语法：`WITH name AS (SELECT ...) SELECT ...` · 可读性提升（命名流水线） · **PG 12+ 的物化开关**（单次引用默认内联 / 多次引用默认物化 / `MATERIALIZED`·`NOT MATERIALIZED` 覆盖） · 多 CTE 链式引用 · 数据修改 CTE（`WITH ... INSERT/UPDATE/DELETE`） |
| **6.2 递归 CTE** | · 语法：`WITH RECURSIVE` + anchor + 递归项 + 终止条件 · 树遍历（自顶向下 / 自底向上） · 图遍历与**防无限递归**（`UNION` vs `UNION ALL`、PG 14+ `CYCLE` 子句、手工 path 数组、depth 守卫） · 递归 CTE 的性能陷阱（join 列必须建索引 / 总是物化） |
| **6.3 相关子查询 vs JOIN** | · 相关子查询"内层依赖外层"的语义 · `EXISTS` / `IN` / `NOT EXISTS` / **`NOT IN` 的 NULL 陷阱** · 改写为 JOIN 的取舍 · **PG 优化器的 unnest 能力边界**（哪些能救、哪些救不了） · `LATERAL` 相关子查询 |

## 故事主线中的情节定位

主角的故事开始分层——"先看这个用户的全部订单，再按状态分组，再保留金额最大的那一笔"。读者学会的不是新语法，而是"把一个复杂查询拆成一步步来"。

## 正文

## 📌 知识点导航

本课首批（首批 = 课 6 全部 3 个知识点，阶段 2 第三课）覆盖：

| 节 | 知识点 | 核心问题 |
|---|---|---|
| 第三幕（一） | 6.1 WITH 子句 | 长查询怎么拆成"先…再…最后…" |
| 第三幕（二） | 6.2 递归 CTE | 树 / 图这种"层级不确定"的怎么查 |
| 第三幕（三） | 6.3 相关子查询 vs JOIN | 逐行计算 vs 批量计算，优化器能救谁 |

---

## 第一幕 · 起源与场景引入

### 一个真实的工作场景

上一课你学会了用视图把常用查询存下来。但视图是"**全局的**"——你要为每一个查询都建一个视图吗？

周三下午，PM 又来了一个一次性需求：

> "帮我拉个名单：**那些本月消费超过 5000、且至少买过 3 个不同品类**的用户，要他们的名字、总消费额、以及最近一笔订单的订单号。"

你盯着这个问题，脑子里开始搭 SQL：

```sql
-- 第一版：嵌套地狱
SELECT u.name, t.total, r.last_order_no
FROM users u
JOIN (
    SELECT user_id, SUM(amount) AS total
    FROM orders WHERE status = 'paid' AND created_at >= DATE_TRUNC('month', CURRENT_DATE)
    GROUP BY user_id HAVING SUM(amount) > 5000
) t ON t.user_id = u.id
JOIN (
    SELECT user_id, COUNT(DISTINCT p.category_id) AS cat_cnt
    FROM orders o JOIN order_items oi ON oi.order_id = o.id
    JOIN products p ON p.id = oi.product_id
    GROUP BY user_id
) c ON c.user_id = u.id AND c.cat_cnt >= 3
JOIN LATERAL (
    SELECT order_no AS last_order_no FROM orders
    WHERE user_id = u.id ORDER BY created_at DESC LIMIT 1
) r ON true;
```

**能跑，但读起来是从内往外读的**——三层缩进，三个月后你自己都看不懂。

**CTE 就是为这个场景生的**：

```sql
WITH monthly_spending AS (      -- ① 先算本月消费
    SELECT user_id, SUM(amount) AS total
    FROM orders
    WHERE status = 'paid' AND created_at >= DATE_TRUNC('month', CURRENT_DATE)
    GROUP BY user_id
),
category_breadth AS (           -- ② 再算品类广度
    SELECT o.user_id, COUNT(DISTINCT p.category_id) AS cat_cnt
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.id
    JOIN products p     ON p.id = oi.product_id
    GROUP BY o.user_id
),
last_orders AS (                -- ③ 再取每人最近一笔订单
    SELECT DISTINCT ON (user_id) user_id, order_no AS last_order_no
    FROM orders ORDER BY user_id, created_at DESC
)
SELECT u.name, ms.total, lo.last_order_no    -- ④ 最后拼起来
FROM users u
JOIN monthly_spending ms ON ms.user_id = u.id AND ms.total > 5000
JOIN category_breadth  cb ON cb.user_id = u.id AND cb.cat_cnt >= 3
JOIN last_orders       lo ON lo.user_id = u.id;
```

**从上往下读，每一步都有名字。** 这就是 CTE 的价值。

### 一个关于"分层"的小类比

把写 SQL 想成**做菜**：

| 写法 | 类比 |
|---|---|
| **嵌套子查询** | 把所有步骤写在一条指令里："把切好的、腌过的、裹了粉的鸡炸了" —— 得从中间往外读 |
| **CTE** | **备菜台**：先切好放小碗①，再腌好放小碗②，最后下锅 —— 从上往下一步步来 |
| **视图** | **预制菜**：存冰箱里，下次直接用（但只为常做的菜准备） |
| **物化视图** | **做好的成品**：提前做好，热一热就能吃 |

**CTE = 一次性的备菜台** —— 只在当前这条查询里有效。

---

## 第二幕 · 认知冲突

CTE 看起来就是"更好读的子查询"，**实际落地有 4 类隐藏陷阱**：

**陷阱一：以为"CTE 一定只算一次"**

```sql
-- 你以为 expensive 只算一次？
WITH expensive AS (
    SELECT * FROM orders WHERE amount > 1000   -- 计算很贵
)
SELECT * FROM expensive WHERE user_id = 1
UNION ALL
SELECT * FROM expensive WHERE user_id = 2;
```

**在 PG 12+ 里，"只引用一次"的 CTE 会被内联展开**，也就是说它不再是"先算好一堆，再从中挑"——而是**被折叠进外层查询**，让优化器一起优化。这通常**更快**（条件下推、能用索引），但**不再保证"只算一次"**。

> 💡 **PG 12 是个分水岭**：PG 12 之前，CTE **永远是优化屏障**（总是先算完再给外层）。PG 12 起改成"单次引用默认内联"。这个变化让很多老 SQL 突然变快，也让少数依赖旧行为的 SQL 出问题。

**陷阱二：递归 CTE 忘了终止条件 → 跑到天荒地老**

```sql
-- ❌ 数据里有个环（3 → 5 → 3），这句永远不会停
WITH RECURSIVE tree AS (
    SELECT id, parent_id FROM categories WHERE id = 1
  UNION ALL
    SELECT c.id, c.parent_id FROM categories c JOIN tree t ON c.parent_id = t.id
)
SELECT * FROM tree;
-- 跑到你手动 cancel，或者内存耗尽
```

**陷阱三：以为 `NOT IN` 和 `NOT EXISTS` 一样**

```sql
-- ❌ 子查询里有 NULL 时，这句永远返回 0 行！
SELECT * FROM users
WHERE id NOT IN (SELECT user_id FROM orders);
-- 只要 orders.user_id 有一个 NULL → 整个结果为空

-- ✅ NOT EXISTS 才是安全的
SELECT * FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
```

**陷阱四：在 SELECT 里写相关子查询**

```sql
-- ❌ 每一行订单都要跑一次子查询（N+1）
SELECT o.id,
       (SELECT SUM(quantity) FROM order_items oi WHERE oi.order_id = o.id) AS total_qty
FROM orders o;
```

PG 优化器**几乎从不优化 SELECT 列表里的相关标量子查询** —— 这就是逐行执行。改 JOIN 或窗口函数。

---

## 第三幕 · 层层揭示

### （一）知识点 6.1 · WITH 子句（普通 CTE）

#### 一句话定义

**CTE（`WITH` 子句）= 给一条查询里的中间结果起个名字，让复杂查询能"从上往下"分步读。**

#### 直觉建立

```
普通子查询（从内往外读）
  SELECT ... FROM ( SELECT ... FROM ( SELECT ... ) ) 
       ↑___________________________________|
                    得从最里面读起

CTE（从上往下读）
  WITH step1 AS (...),      ← ① 先读这
       step2 AS (...),      ← ② 再读这
       step3 AS (...)       ← ③ 再读这
  SELECT ...                ← ④ 最后这
```

#### 基本语法

```sql
WITH 名字 AS (
    SELECT ...
)
SELECT ... FROM 名字 ...;

-- 多个 CTE，用逗号分隔，后面的可以引用前面的
WITH a AS (SELECT ...),
     b AS (SELECT ... FROM a ...)      -- ✅ b 能引用 a
SELECT ... FROM b;

-- 也可以给列起别名
WITH t(user_id, total) AS (
    SELECT user_id, SUM(amount) FROM orders GROUP BY user_id
)
SELECT * FROM t WHERE total > 1000;
```

#### 🎯 核心原理：PG 12+ 的物化开关（本课最重要的机制）

这是 CTE 最容易被误解的地方。**PG 12 改变了默认行为**：

| 版本 | 默认行为 |
|---|---|
| **PG 11 及更早** | **所有 CTE 一律物化** —— CTE 是"优化屏障（optimization fence）"，外层的 WHERE 推不进去 |
| **PG 12 起** | **智能判断**：满足三条件 → 内联；否则 → 物化 |

**PG 12+ 的判断规则**（三条全满足才内联）：

1. **只被引用一次**
2. **没有副作用**（是纯 `SELECT`，不含 volatile 函数，不是 `INSERT/UPDATE/DELETE`）
3. **非递归**

```
                    CTE 是递归的？
                   /            \
                 是              否
                 ↓                ↓
            物化           有副作用（写操作/volatile）？
                            /              \
                          是                否
                          ↓                 ↓
                       物化           被引用几次？
                                     /          \
                                   1 次       多次
                                    ↓           ↓
                                 内联        物化
```

**手动覆盖**（这是关键技能）：

```sql
WITH cte AS MATERIALIZED (        -- 强制物化：我要"只算一次"
    SELECT ... 昂贵的计算 ...
)
SELECT ...;

WITH cte AS NOT MATERIALIZED (    -- 强制内联：我要"条件下推"
    SELECT ... FROM big_table
)
SELECT * FROM cte WHERE key = 123;   -- key=123 能被推进 CTE 内，走索引
```

**为什么这个开关重要？看两个对照实验**：

```sql
-- 场景 A：CTE 被内联（默认，单次引用）→ 条件下推，走索引
WITH all_orders AS (
    SELECT * FROM orders
)
SELECT * FROM all_orders WHERE user_id = 42;
-- 执行计划 ≈ SELECT * FROM orders WHERE user_id = 42
-- ✅ 能用 idx_orders_user_id

-- 场景 B：强制物化 → 全表扫一遍先算完，再过滤
WITH all_orders AS MATERIALIZED (
    SELECT * FROM orders
)
SELECT * FROM all_orders WHERE user_id = 42;
-- ❌ 先 Seq Scan 全表 → 物化 → 再过滤
```

> ⚠️ **什么时候该用 `MATERIALIZED`？**
> ① CTE 里有昂贵的计算，你**确实只想算一次**
> ② 你**故意**要用 CTE 当优化屏障（防止优化器选错计划）
> ③ CTE 里有**副作用**（如 `random()`、`now()`、数据修改），需要控制求值次数
>
> ⚠️ **什么时候该用 `NOT MATERIALIZED`？**
> 外层条件能大幅减少 CTE 结果时（如按主键过滤）—— 让条件下推，走索引

**一个真实的副作用例子**（PG 12 行为变化导致的 bug）：

```sql
-- 这个 CTE 里有 volatile 函数，PG 12+ 仍会物化（因为有副作用）
WITH r AS (SELECT random() AS x FROM generate_series(1,3))
SELECT * FROM r;                 -- 3 个不同随机数 ✅

-- 但如果内联展开，random() 可能被求值多次 / 结果不同
WITH r AS MATERIALIZED (SELECT random() AS x FROM generate_series(1,3))
SELECT * FROM r;                 -- 强制只算一次，最稳
```

#### 数据修改 CTE（`WITH` + 写操作）

PG 允许在 CTE 里做 `INSERT` / `UPDATE` / `DELETE`，并配合 `RETURNING` 把结果传给外层：

```sql
-- 经典用法：归档老订单（一步完成"搬走 + 删除 + 返回归档了什么"）
WITH moved AS (
    DELETE FROM orders
    WHERE created_at < '2025-01-01'
    RETURNING *
)
INSERT INTO orders_archive
SELECT * FROM moved
RETURNING id;
```

**这个模式的好处**：一条语句完成"读-改-写"，**原子性由数据库保证**。

> ⚠️ **两个重要限制**：
> 1. **数据修改 CTE 会禁用整条语句的并行查询** —— 即使只读部分也受影响
> 2. 数据修改 CTE 的**执行顺序不保证**（多个写 CTE 之间没有顺序保证，别依赖）

```sql
-- ⚠️ 危险：两个写 CTE 的顺序不保证
WITH a AS (INSERT INTO t1 ... RETURNING id),
     b AS (INSERT INTO t2 ... RETURNING id)
SELECT ...;   -- a 和 b 谁先执行？不保证！
```

#### 多 CTE 链式引用

```sql
-- "先…再…最后…"的流水线（本课开篇那个需求的完整版）
WITH monthly_spending AS (          -- ①
    SELECT user_id, SUM(amount) AS total
    FROM orders
    WHERE status = 'paid'
      AND created_at >= DATE_TRUNC('month', CURRENT_DATE)
    GROUP BY user_id
),
high_value AS (                     -- ② 引用 ①
    SELECT user_id, total FROM monthly_spending WHERE total > 5000
),
category_breadth AS (               -- ③ 独立
    SELECT o.user_id, COUNT(DISTINCT p.category_id) AS cat_cnt
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.id
    JOIN products p     ON p.id = oi.product_id
    GROUP BY o.user_id
)
SELECT u.name, hv.total, cb.cat_cnt  -- ④
FROM users u
JOIN high_value       hv ON hv.user_id = u.id
JOIN category_breadth cb ON cb.user_id = u.id AND cb.cat_cnt >= 3
ORDER BY hv.total DESC;
```

#### CTE vs 视图 vs 子查询 vs 临时表

| | CTE | 视图 | 子查询 | 临时表 |
|---|---|---|---|---|
| 作用域 | **仅当前查询** | 全局（需 CREATE） | 仅当前查询 | 会话 / 事务 |
| 能递归 | ✅ | ❌ | ❌ | ❌ |
| 能被引用多次 | ✅（自动物化） | ✅ | ❌（要重写） | ✅ |
| 能建索引 | ❌ | 仅物化视图 | ❌ | ✅ |
| 适合 | 一次性复杂查询 | 长期复用 | 简单的嵌套 | 大中间结果 + 需要索引 |

#### 示例演示

```sql
-- 场景：找出"每个分类下销售额最高的商品"
WITH category_sales AS (              -- ① 先算每个商品在每个分类的销售额
    SELECT p.category_id, p.id AS product_id, p.title,
           SUM(oi.unit_price * oi.quantity) AS revenue
    FROM order_items oi
    JOIN products p ON p.id = oi.product_id
    GROUP BY p.category_id, p.id, p.title
),
ranked AS (                            -- ② 再在分类内排名
    SELECT *, ROW_NUMBER() OVER (PARTITION BY category_id ORDER BY revenue DESC) AS rn
    FROM category_sales
)
SELECT category_id, product_id, title, revenue   -- ③ 取第 1 名
FROM ranked WHERE rn = 1
ORDER BY revenue DESC;
```

> 💡 这里用了 `ROW_NUMBER()` 窗口函数 —— **课 7 会系统讲**，本课先借用。

#### 常见误区 6 条

| 误区 | 反例 | 正解 |
|---|---|---|
| 以为 CTE 一定只算一次 | 依赖"物化"语义 | PG 12+ 单次引用**默认内联**；要保底写 `AS MATERIALIZED` |
| 以为 CTE 一定慢 | 不敢用 CTE | 内联后与普通子查询性能相同；只是可读性更好 |
| 用 `MATERIALIZED` 挡住条件下推 | 主键过滤的 CTE 也强制物化 | 单值过滤场景用 `NOT MATERIALIZED` |
| 在 CTE 里放写操作还指望并行 | `WITH x AS (INSERT...)` | 数据修改 CTE **禁用整语句并行** |
| 依赖多个写 CTE 的执行顺序 | 两个 INSERT CTE | **顺序不保证**，拆成多条语句 |
| CTE 里用 `SELECT *` | `WITH t AS (SELECT * FROM orders)` | 显式列名（与视图同样的固化列问题） |

#### 一句话记住

> **CTE 是可读性工具不是性能工具；PG 12+ 单次引用默认内联，要"只算一次"就显式写 `MATERIALIZED`。**

#### 命令速查卡（6.1）

```sql
-- 基本
WITH name AS (SELECT ...) SELECT ... FROM name;
WITH a AS (...), b AS (SELECT ... FROM a ...) SELECT ... FROM b;
WITH t(col1, col2) AS (SELECT c1, c2 FROM ...) SELECT * FROM t;

-- 物化开关（PG 12+）
WITH cte AS MATERIALIZED (...) SELECT ...;        -- 强制只算一次
WITH cte AS NOT MATERIALIZED (...) SELECT ...;    -- 强制内联（条件下推）

-- 判断规则：递归 / 有副作用 → 物化；否则单次引用 → 内联，多次引用 → 物化

-- 数据修改 CTE
WITH moved AS (
    DELETE FROM src WHERE ... RETURNING *
)
INSERT INTO dst SELECT * FROM moved RETURNING id;
-- ⚠️ 禁用整语句并行；多个写 CTE 执行顺序不保证

-- 链式流水线
WITH step1 AS (...), step2 AS (... FROM step1 ...), step3 AS (...)
SELECT ... FROM step3;
```

---

### （二）知识点 6.2 · 递归 CTE

#### 一句话定义

**递归 CTE = 让一条 CTE 引用它自己，通过"种子 + 迭代规则"遍历任意深度的层级结构。**

#### 直觉建立

把递归 CTE 想成**传话游戏**：

1. **第 0 轮**：选出一个"种子"（比如 CEO，或者根分类）
2. **第 N 轮**：拿上一轮的结果，找出"它们的下一级"
3. **直到**：某一轮找不到新的人了 → 结束

```
第 0 轮：[CEO]           ← anchor（种子）
第 1 轮：[VP-A, VP-B]    ← CEO 的直接下属
第 2 轮：[M1, M2, M3]    ← VP 的下属
第 3 轮：[E1, E2]        ← M 的下属
第 4 轮：[]              ← 没了，停
────────────────────────
结果 = 所有轮的并集
```

#### 语法骨架

```sql
WITH RECURSIVE 名字 AS (
    -- ① 非递归项（anchor / 种子）：只跑一次
    SELECT ... FROM ... WHERE <起点条件>

    UNION ALL          -- 或 UNION（见下文差异）

    -- ② 递归项：引用 CTE 自己
    SELECT ... FROM 表 JOIN 名字 ON <父子关系>
)
SELECT * FROM 名字;
```

**三个必须**：

1. **`RECURSIVE` 关键字**（不写会报"cte 不存在"）
2. **anchor 必须有**（没有起点，递归无从开始）
3. **递归项必须引用 CTE 自己，且最终会返回空**（否则死循环）

#### PG 的执行机制（重要！不是"函数调用栈"）

很多人以为递归 CTE 像程序里的递归函数调用（一层层压栈）。**PG 不是这样的**，它用的是**工作表迭代**：

```
1. 执行非递归项（anchor）→ 结果放进"工作表"
2. 用工作表作为输入执行递归项 → 产生的新行成为"下一轮工作表"
3. 重复步骤 2，直到某一轮产生 0 行
4. 返回所有轮结果的并集
```

> 💡 **这解释了两件事**：
> ① 递归 CTE **总是物化**（不参与内联优化）——因为要维护工作表
> ② 递归项里的 **JOIN 列必须建索引**（每轮都要拿工作表去匹配表，没索引就每轮全表扫）

#### 树遍历：两个方向

**① 自顶向下（找所有子孙）**

```sql
-- 找"电子产品"(id=10) 下的所有分类
WITH RECURSIVE cat_tree AS (
    -- anchor：起点
    SELECT id, name, parent_id, 1 AS depth
    FROM categories WHERE id = 10

    UNION ALL

    -- 递归项：找 parent 在上一轮结果里的
    SELECT c.id, c.name, c.parent_id, ct.depth + 1
    FROM categories c
    JOIN cat_tree ct ON c.parent_id = ct.id    -- ⚠️ categories.parent_id 要有索引
)
SELECT id, name, depth FROM cat_tree ORDER BY depth, id;
```

**② 自底向上（找所有祖先 / 面包屑）**

```sql
-- 找 "键盘"(id=12) 到根的整条路径（做面包屑导航）
WITH RECURSIVE breadcrumb AS (
    -- anchor：从自己开始
    SELECT id, name, parent_id, 1 AS depth
    FROM categories WHERE id = 12

    UNION ALL

    -- 递归项：找自己的 parent
    SELECT c.id, c.name, c.parent_id, bc.depth + 1
    FROM categories c
    JOIN breadcrumb bc ON c.id = bc.parent_id   -- ⚠️ 注意方向反了
)
SELECT id, name, depth FROM breadcrumb ORDER BY depth DESC;
```

> ⚠️ **方向别搞反**：
> - 自顶向下：`c.parent_id = ct.id`（找"谁的爸爸是我"）
> - 自底向上：`c.id = bc.parent_id`（找"我的爸爸是谁"）
> 写反了就变成遍历另一个方向，或者死循环。

#### 🎯 防无限递归（本课最关键的安全知识）

**`UNION ALL` vs `UNION` 的取舍**：

| | `UNION ALL` | `UNION` |
|---|---|---|
| 去重 | ❌ 不去重 | ✅ 每轮去重 |
| 速度 | ✅ **快**（无 hash/排序开销） | ❌ 慢（每步都要去重） |
| **有环时** | ❌ **永不终止**（数据脏就炸） | ✅ **能终止**（重复行被去重） |
| 适用 | **树**（保证无环） | **图**（可能有环） |

> 💡 **默认用 `UNION ALL`**（快），**只在数据可能有环时才用 `UNION`**（或用下面的 `CYCLE`）。

**PG 14+ 的 `CYCLE` 子句（推荐，SQL 标准）**：

```sql
WITH RECURSIVE tree AS (
    SELECT id, parent_id, 1 AS depth FROM categories WHERE id = 10
  UNION ALL
    SELECT c.id, c.parent_id, t.depth + 1
    FROM categories c JOIN tree t ON c.parent_id = t.id
)
CYCLE id SET is_cycle USING path        -- ← 就这一行
SELECT id, parent_id, depth FROM tree WHERE NOT is_cycle;
```

**`CYCLE` 子句做了什么**：

- 语法：`CYCLE <被追踪的列> SET <环标记列> USING <路径列>`
- 自动给你加两列：
  - `is_cycle`（boolean）：这一行是不是环的开始
  - `path`（array）：从根到这一行走过的所有 `id`
- 用 `WHERE NOT is_cycle` 过滤掉环
- **反过来用 `WHERE is_cycle` 可以"找出数据里的环"**（脏数据排查神器！）

```sql
-- 找出组织结构里的循环引用（数据治理常用）
WITH RECURSIVE tree AS (
    SELECT id, parent_id FROM categories WHERE parent_id IS NULL
  UNION ALL
    SELECT c.id, c.parent_id FROM categories c JOIN tree t ON c.parent_id = t.id
)
CYCLE id SET is_cycle USING path
SELECT id, path FROM tree WHERE is_cycle;   -- ✅ 有环的行给你揪出来
```

**PG 14 之前的手工防环**（老版本兼容写法）：

```sql
WITH RECURSIVE tree AS (
    SELECT id, parent_id, ARRAY[id] AS path, 1 AS depth
    FROM categories WHERE id = 10
  UNION ALL
    SELECT c.id, c.parent_id, t.path || c.id, t.depth + 1
    FROM categories c
    JOIN tree t ON c.parent_id = t.id
    WHERE NOT (c.id = ANY(t.path))     -- ← 手工守卫：id 没走过才继续
)
SELECT id, parent_id, depth, path FROM tree;
```

> 💡 `ANY(t.path)` 也可以写成 `c.id <> ALL(t.path)` —— 两种写法等价，后者更贴近 SQL 标准语义。

**深度守卫（永远加，作为安全网）**：

```sql
WITH RECURSIVE tree AS (
    SELECT id, parent_id, 1 AS depth FROM categories WHERE id = 10
  UNION ALL
    SELECT c.id, c.parent_id, t.depth + 1
    FROM categories c JOIN tree t ON c.parent_id = t.id
    WHERE t.depth < 10            -- ← 兜底：最多 10 层
)
SELECT * FROM tree;
```

> 💡 **三层防护，按需叠加**：`UNION`（去重防环）+ `CYCLE`（PG 14+ 精确防环）+ `depth < N`（兜底）。生产环境**至少要有 depth 守卫**。

#### PG 14+ 的 `SEARCH` 子句（控制遍历顺序）

```sql
WITH RECURSIVE tree AS (
    SELECT id, parent_id FROM categories WHERE id = 10
  UNION ALL
    SELECT c.id, c.parent_id FROM categories c JOIN tree t ON c.parent_id = t.id
)
SEARCH DEPTH FIRST BY id SET seq      -- 深度优先
SELECT * FROM tree ORDER BY seq;

-- 或 SEARCH BREADTH FIRST BY id SET seq   -- 广度优先
```

> 💡 **`DEPTH FIRST`** = 一条路走到底再回来（适合找路径）；**`BREADTH FIRST`** = 一层一层扫（适合找"最近的"）。

#### 图遍历：最短路径示例

```sql
-- 找从 A 到 B 的最短跳数（BFS）
WITH RECURSIVE paths AS (
    SELECT ARRAY['A'] AS path, 'A' AS node, 0 AS hops
  UNION ALL
    SELECT p.path || e.to_node, e.to_node, p.hops + 1
    FROM paths p
    JOIN edges e ON e.from_node = p.node
    WHERE NOT (e.to_node = ANY(p.path))   -- 不走回头路
      AND p.hops < 10
)
SELECT path, hops FROM paths
WHERE node = 'B'
ORDER BY hops LIMIT 1;
```

#### 递归 CTE 的性能陷阱

| 陷阱 | 说明 | 解法 |
|---|---|---|
| **join 列没索引** | 每轮全表扫（`parent_id` / `manager_id`） | **必须建索引** |
| 数据量太大 | 每轮工作表膨胀 | 加 `depth` 限制 / 加业务过滤条件 |
| 用 `UNION` 去重 | 每步 hash 比较 | 树结构改 `UNION ALL` |
| 递归里做重计算 | 每轮重复计算 | 把不变量提到 CTE 外面 |
| 物化溢出 | 中间结果超过 `work_mem` 会**落盘** | `EXPLAIN (ANALYZE, BUFFERS)` 看 temp |

```sql
-- 必做：给递归 join 的列建索引
CREATE INDEX idx_categories_parent ON categories (parent_id);
CREATE INDEX idx_employees_manager ON employees (manager_id);
```

> 💡 **什么时候不该用递归 CTE**：课 4 讲过——**深树 + 读多写少**应该用 `ltree` + GiST 索引（O(log N)），递归 CTE 随深度线性退化。

#### 示例演示：组织架构 + 团队汇总

```sql
-- 找出 Alice（id=1）管辖的所有人，并统计团队人数与总薪资
WITH RECURSIVE team AS (
    SELECT id, name, manager_id, 1 AS depth
    FROM employees WHERE id = 1
  UNION ALL
    SELECT e.id, e.name, e.manager_id, t.depth + 1
    FROM employees e
    JOIN team t ON e.manager_id = t.id
    WHERE t.depth < 20
)
SELECT
    COUNT(*)          AS team_size,
    SUM(salary)       AS total_salary,
    MAX(depth)        AS org_depth
FROM team;

-- 按层级展示
SELECT REPEAT('  ', depth - 1) || name AS org_chart, depth
FROM team ORDER BY depth, name;
```

#### 常见误区 6 条

| 误区 | 反例 | 正解 |
|---|---|---|
| 忘了 `RECURSIVE` 关键字 | `WITH t AS (... 引用 t ...)` | 必须 `WITH RECURSIVE` |
| 递归项引用方向写反 | 自底向上写成 `c.parent_id = t.id` | 想清楚方向（见上文两个示例） |
| join 列没建索引 | `manager_id` 裸奔 | 递归每轮全表扫，必须建索引 |
| 有环数据用 `UNION ALL` | 图数据不加防护 | 用 `UNION` / `CYCLE` / depth 守卫 |
| 递归里做聚合 | 递归项里写 `GROUP BY` | PG 不允许（部分版本），把聚合放外层 |
| 以为递归 CTE 会被内联 | 期待优化器优化 | **递归 CTE 总是物化** |

#### 一句话记住

> **递归 CTE = 种子 + 迭代规则 + 终止条件；join 列必建索引，有环数据必加 `CYCLE` 或 depth 守卫。**

#### 命令速查卡（6.2）

```sql
-- 骨架
WITH RECURSIVE t AS (
    SELECT ... FROM ... WHERE <起点>          -- anchor
  UNION [ALL]
    SELECT ... FROM tbl JOIN t ON <父子关系>   -- 递归项
    [WHERE t.depth < N]                        -- depth 守卫
)
[CYCLE col SET is_cycle USING path]            -- PG 14+ 防环
SELECT ... FROM t [WHERE NOT is_cycle];

-- 自顶向下（找子孙）
JOIN t ON c.parent_id = t.id

-- 自底向上（找祖先/面包屑）
JOIN t ON c.id = t.parent_id

-- 防环三件套
CYCLE id SET is_cycle USING path      -- PG 14+（推荐）
WHERE NOT (c.id = ANY(t.path))        -- 手工数组（兼容老版本）
WHERE t.depth < 10                    -- 兜底守卫

-- 找环（数据治理）
SELECT ... FROM t WHERE is_cycle;

-- 遍历顺序（PG 14+）
SEARCH DEPTH FIRST BY id SET seq
SEARCH BREADTH FIRST BY id SET seq

-- 性能
CREATE INDEX ON tbl (parent_id);       -- 必须！
```

---

### （三）知识点 6.3 · 相关子查询 vs JOIN

#### 一句话定义

**相关子查询 = 内层查询引用了外层查询的列，因此"每一行外层行都要跑一次内层"。**

#### 直觉建立

```
非相关子查询（独立）
  SELECT * FROM orders WHERE user_id IN (SELECT id FROM vip_users)
                                          ↑ 这个子查询能独立跑完
  → 先跑一次子查询，拿到结果集，再用它过滤外层

相关子查询（依赖外层）
  SELECT * FROM users u WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id)
                                                                    ↑ 引用了外层的 u.id
  → 逻辑上：外层每行都要跑一次子查询
```

**"相关"的意思就是"内外有牵连"。**

#### 四种存在性判断写法

**① `IN`（最简单）**

```sql
SELECT * FROM users WHERE id IN (SELECT user_id FROM orders);
```

**② `EXISTS`（最推荐做存在性判断）**

```sql
SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
```

> 💡 `EXISTS` 的子查询里写 `SELECT 1` / `SELECT *` / `SELECT NULL` **都一样** —— PG 只关心"有没有返回行"，不关心返回什么。

**③ `NOT EXISTS`（反选，NULL 安全）**

```sql
SELECT * FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
-- 找"没下过单的用户"
```

**④ `NOT IN`（⚠️ 有 NULL 陷阱）**

```sql
SELECT * FROM users WHERE id NOT IN (SELECT user_id FROM orders);
-- ⚠️ 只要 orders.user_id 有任何一个 NULL → 整句返回 0 行！
```

> ❓ **为什么 `NOT IN` 会这样？**
> SQL 的三值逻辑：`NOT IN` 展开是 `id <> v1 AND id <> v2 AND ... AND id <> NULL`。
> 而 `id <> NULL` 的结果是 **UNKNOWN**（不是 TRUE），整个 AND 链就变成 UNKNOWN → 不满足 WHERE → **一行都不返回**。
>
> **这不是 PG 的 bug，是 SQL 标准语义。** 所以：**永远用 `NOT EXISTS` 代替 `NOT IN (子查询)`。**

#### 🎯 PG 优化器的 unnest 能力边界（本课最实用的知识）

关键问题：**PG 能把相关子查询自动改写成 JOIN 吗？** 答案是"**看情况**"：

| 写法 | PG 能自动 unnest 吗 | 变成什么 | 结论 |
|---|---|---|---|
| `IN (SELECT ...)` | ✅ **能** | semi-join（hash/merge） | 与 EXISTS 性能相当 |
| `EXISTS (...)` | ✅ **能** | semi-join | ✅ 安全 |
| `NOT EXISTS (...)` | ✅ **能** | anti-join | ✅ 安全 |
| **`NOT IN (SELECT ...)`** | ❌ **不能** | 保持原样 | ⚠️ **必须手写改 NOT EXISTS** |
| 简单派生表（FROM 子查询） | ✅ **能** | subquery pull-up（拉平） | 与手写 JOIN 等价 |
| **SELECT 列表里的相关标量子查询** | ❌ **几乎从不** | 逐行执行 | ⚠️ **最危险，必须手改** |
| WHERE 里的相关标量子查询 | ⚠️ 有时能 | 看情况 | 要 EXPLAIN 确认 |
| `LATERAL` 相关子查询 | ❌ 故意不优化 | nested loop | 有时正是你想要的 |

**三条实战纪律**：

1. **`EXISTS` / `NOT EXISTS` / `IN` 与 JOIN 性能相当** → **按可读性选，别纠结性能**
2. **`NOT IN (子查询)` 必须改成 `NOT EXISTS`** → 不只是性能，是**语义正确性**
3. **SELECT 列表里的相关标量子查询是最大风险点** → 改 JOIN + GROUP BY，或改窗口函数

#### 改写实战：相关子查询 → JOIN

**案例 1：SELECT 里的相关标量子查询（最危险，必须改）**

```sql
-- ❌ 每行订单跑一次子查询（N+1）
SELECT o.id,
       (SELECT SUM(oi.quantity) FROM order_items oi WHERE oi.order_id = o.id) AS total_qty
FROM orders o;

-- ✅ 改写 A：LEFT JOIN + GROUP BY
SELECT o.id, COALESCE(SUM(oi.quantity), 0) AS total_qty
FROM orders o
LEFT JOIN order_items oi ON oi.order_id = o.id
GROUP BY o.id;

-- ✅ 改写 B：先聚合再 JOIN（通常更快，聚合在子集上）
SELECT o.id, COALESCE(t.total_qty, 0) AS total_qty
FROM orders o
LEFT JOIN (
    SELECT order_id, SUM(quantity) AS total_qty
    FROM order_items GROUP BY order_id
) t ON t.order_id = o.id;
```

> 💡 100 万订单 × 1000 万明细的场景下，相关子查询可能 **30 秒**，JOIN 只要 **200ms**。

**案例 2：WHERE 里的相关聚合子查询**

```sql
-- ❌ 每个员工都要扫一遍本部门
SELECT e.name, e.salary FROM employees e
WHERE e.salary > (SELECT AVG(salary) FROM employees s WHERE s.department_id = e.department_id);

-- ✅ 改写 A：JOIN 到预聚合子查询（一次扫描 + 一次 JOIN）
SELECT e.name, e.salary FROM employees e
JOIN (
    SELECT department_id, AVG(salary) AS avg_sal
    FROM employees GROUP BY department_id
) d ON d.department_id = e.department_id
WHERE e.salary > d.avg_sal;

-- ✅ 改写 B：窗口函数（最优雅，课 7 系统讲）
SELECT name, salary FROM (
    SELECT name, salary, AVG(salary) OVER (PARTITION BY department_id) AS dept_avg
    FROM employees
) t WHERE salary > dept_avg;
```

**案例 3：`NOT IN` → `NOT EXISTS`**

```sql
-- ❌ 危险：子查询有 NULL 时返回 0 行
SELECT * FROM products WHERE id NOT IN (SELECT product_id FROM order_items);

-- ✅ 安全写法 A：NOT EXISTS
SELECT * FROM products p
WHERE NOT EXISTS (SELECT 1 FROM order_items oi WHERE oi.product_id = p.id);

-- ✅ 安全写法 B：LEFT JOIN + IS NULL（anti-join）
SELECT p.* FROM products p
LEFT JOIN order_items oi ON oi.product_id = p.id
WHERE oi.product_id IS NULL;
```

**案例 4：LATERAL —— 故意保留"逐行"**

```sql
-- 每笔订单取"金额最高的那一条明细" —— 相关子查询的合理用武之地
SELECT o.id, top.product_name, top.unit_price
FROM orders o
CROSS JOIN LATERAL (
    SELECT oi.product_name, oi.unit_price
    FROM order_items oi
    WHERE oi.order_id = o.id
    ORDER BY oi.unit_price DESC
    LIMIT 1
) top;
```

> 💡 **`LATERAL` 的语义**：允许子查询引用**前面** FROM 项里的列。PG 会用 nested loop 执行——**这正是你想要的**（外层行少、内层有索引时极快）。
>
> 反过来：如果外层有 100 万行，LATERAL 就要跑 100 万次 —— 这时该改成窗口函数（课 7）。

#### 用 EXPLAIN 验证是否 unnest

```sql
-- 看执行计划里是 "Semi Join" / "Anti Join" 还是 "SubPlan"
EXPLAIN SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
-- ✅ 看到 Hash Semi Join → 已被 unnest

EXPLAIN SELECT id, (SELECT SUM(quantity) FROM order_items oi WHERE oi.order_id = o.id)
FROM orders o;
-- ❌ 看到 SubPlan → 逐行执行，未优化
```

> 💡 **判断口诀**：看到 **`SubPlan`** 就要警惕（逐行）；看到 **`Semi Join` / `Anti Join` / `Hash Join`** 说明优化器已经救了你。

#### 决策表：该用哪个？

| 需求 | 推荐写法 | 理由 |
|---|---|---|
| "有没有"（存在性） | `EXISTS` | 短路、可 unnest |
| "没有"（反选） | `NOT EXISTS` | NULL 安全、可 unnest |
| "在/不在某个集合里"（值列表） | `IN (1,2,3)` | 字面量集合用 IN 最直观 |
| "在子查询的结果里" | `IN` 或 `EXISTS` | 性能相当，按可读性 |
| **"不在子查询的结果里"** | **`NOT EXISTS`** | ⚠️ 绝不用 `NOT IN` |
| 每行取聚合值 | `LEFT JOIN + GROUP BY` 或窗口函数 | 避免 SELECT 里的相关子查询 |
| 每行取 Top-N | `LATERAL` | 逐行语义本就是你要的 |

#### 常见误区 6 条

| 误区 | 反例 | 正解 |
|---|---|---|
| 用 `NOT IN (子查询)` | `WHERE id NOT IN (SELECT ...)` | 改 `NOT EXISTS`（NULL 陷阱） |
| 在 SELECT 里写相关聚合 | `(SELECT SUM(...) ...)` 每行跑 | LEFT JOIN + GROUP BY / 窗口函数 |
| 以为 `IN` 一定比 `EXISTS` 慢 | 盲目改写 | PG 会 unnest 成同样的 semi-join |
| 以为 `COUNT(*) > 0` 能做存在性 | `(SELECT COUNT(*) ...) > 0` | 用 `EXISTS`（短路，扫到第一行就停） |
| LATERAL 用在百万行外层 | 大表 CROSS JOIN LATERAL | 改窗口函数 |
| 不看 EXPLAIN 就下结论 | 凭感觉选写法 | 看有没有 `SubPlan` |

#### 一句话记住

> **EXISTS/NOT EXISTS/IN 都能被优化器救；`NOT IN` 救不了；SELECT 里的相关子查询最危险。**

#### 命令速查卡（6.3）

```sql
-- 存在性
WHERE EXISTS (SELECT 1 FROM t2 WHERE t2.fk = t1.id)
WHERE NOT EXISTS (SELECT 1 FROM t2 WHERE t2.fk = t1.id)   -- ✅ NULL 安全
WHERE id IN (SELECT fk FROM t2)
WHERE id NOT IN (SELECT fk FROM t2)                        -- ❌ 禁用

-- 改写：SELECT 相关聚合 → LEFT JOIN + GROUP BY
SELECT a.id, COALESCE(SUM(b.x), 0)
FROM a LEFT JOIN b ON b.a_id = a.id GROUP BY a.id;

-- 改写：先聚合再 JOIN（更快）
SELECT a.*, t.s FROM a
LEFT JOIN (SELECT a_id, SUM(x) AS s FROM b GROUP BY a_id) t ON t.a_id = a.id;

-- anti-join（找"没有"的）
SELECT a.* FROM a LEFT JOIN b ON b.a_id = a.id WHERE b.a_id IS NULL;

-- LATERAL（每行取 Top-N）
SELECT a.*, top.* FROM a
CROSS JOIN LATERAL (SELECT ... FROM b WHERE b.a_id = a.id ORDER BY ... LIMIT 1) top;

-- 验证 unnest
EXPLAIN ...;   -- 看 SubPlan（坏） vs Semi/Anti Join（好）
```

---

## 第四幕 · 实操验证

### 实验环境

延续前五课：`localhost:5432` 上 `postgres:17` 容器，`order_service` 库 `finance` schema。本课新增 `employees`（组织架构）与 `edges`（图）两张表演示递归。

```sql
docker start pg17
docker exec -it pg17 psql -U postgres -d order_service
SET search_path TO finance, public;
```

### 实验 1 · 基础 CTE：拆解嵌套查询

```sql
-- ① 先体验"嵌套地狱"
SELECT u.name, t.total FROM users u
JOIN (SELECT user_id, SUM(amount) AS total FROM orders
      WHERE status = 'paid' GROUP BY user_id) t ON t.user_id = u.id
WHERE t.total > 1000;

-- ② 改成 CTE（从上往下读）
WITH paid_totals AS (
    SELECT user_id, SUM(amount) AS total
    FROM orders WHERE status = 'paid' GROUP BY user_id
)
SELECT u.name, pt.total
FROM users u
JOIN paid_totals pt ON pt.user_id = u.id
WHERE pt.total > 1000;

-- ③ 多 CTE 链式
WITH paid_totals AS (
    SELECT user_id, SUM(amount) AS total FROM orders
    WHERE status = 'paid' GROUP BY user_id
),
high_value AS (
    SELECT user_id, total FROM paid_totals WHERE total > 1000   -- 引用前一个 CTE
)
SELECT u.name, hv.total FROM users u
JOIN high_value hv ON hv.user_id = u.id ORDER BY hv.total DESC;
```

### 实验 2 · 验证 PG 12+ 的物化开关（本课核心）

```sql
-- 场景：CTE 只被引用一次 + 外层有过滤条件

-- ① 默认（PG 12+ 内联）：条件下推，走索引
EXPLAIN (ANALYZE)
WITH all_orders AS (
    SELECT * FROM orders
)
SELECT * FROM all_orders WHERE user_id = 42;
-- 计划里应出现：Index Scan using idx_orders_user_id
-- ✅ 说明 CTE 被内联，user_id = 42 被推进去了

-- ② 强制物化：全表扫先算完
EXPLAIN (ANALYZE)
WITH all_orders AS MATERIALIZED (
    SELECT * FROM orders
)
SELECT * FROM all_orders WHERE user_id = 42;
-- 计划里出现：Seq Scan on orders + CTE Scan（带 Filter）
-- ❌ 先扫全表，再过滤

-- ③ 强制内联（显式）
EXPLAIN (ANALYZE)
WITH all_orders AS NOT MATERIALIZED (
    SELECT * FROM orders
)
SELECT * FROM all_orders WHERE user_id = 42;
-- ✅ 与 ① 相同

-- ④ 引用两次 → 默认物化（只算一次更划算）
EXPLAIN (ANALYZE)
WITH all_orders AS (
    SELECT * FROM orders
)
SELECT (SELECT COUNT(*) FROM all_orders WHERE user_id = 1)
     + (SELECT COUNT(*) FROM all_orders WHERE user_id = 2);
-- 计划里出现 CTE Scan（被引用 2 次 → 物化）

-- ⑤ 副作用演示：volatile 函数
WITH r AS MATERIALIZED (SELECT random() AS x FROM generate_series(1,3))
SELECT * FROM r;    -- 3 个随机数，且每次引用结果一致
```

### 实验 3 · 数据修改 CTE（原子归档）

```sql
-- 建归档表
CREATE TABLE IF NOT EXISTS orders_archive (LIKE orders INCLUDING ALL);

-- 一步完成：从 orders 删除老数据 + 插入归档 + 返回归档了哪些
WITH moved AS (
    DELETE FROM orders
    WHERE created_at < '2025-01-01'
    RETURNING *
)
INSERT INTO orders_archive SELECT * FROM moved
RETURNING id, order_no;

-- 验证
SELECT COUNT(*) FROM orders_archive;
SELECT COUNT(*) FROM orders WHERE created_at < '2025-01-01';   -- 应为 0
```

> ⚠️ 这个操作会真的删数据。练习时可以把日期改成一个未来时间（删 0 行）。

### 实验 4 · 递归 CTE：组织架构树

```sql
-- 建表
CREATE TABLE IF NOT EXISTS employees (
    id         BIGINT PRIMARY KEY,
    name       TEXT NOT NULL,
    manager_id BIGINT REFERENCES employees(id),
    salary     NUMERIC(10,2)
);
CREATE INDEX IF NOT EXISTS idx_employees_manager ON employees (manager_id);  -- ⚠️ 必须！

INSERT INTO employees (id, name, manager_id, salary) VALUES
    (1, 'Alice(CEO)',  NULL, 100000),
    (2, 'Bob(VP)',     1,     80000),
    (3, 'Carol(VP)',   1,     78000),
    (4, 'Dave(Mgr)',   2,     60000),
    (5, 'Eve(Mgr)',    2,     58000),
    (6, 'Frank',       4,     45000),
    (7, 'Grace',       4,     43000)
ON CONFLICT (id) DO NOTHING;

-- ① 自顶向下：Alice 管辖的所有人
WITH RECURSIVE team AS (
    SELECT id, name, manager_id, 1 AS depth
    FROM employees WHERE id = 1
  UNION ALL
    SELECT e.id, e.name, e.manager_id, t.depth + 1
    FROM employees e JOIN team t ON e.manager_id = t.id
)
SELECT REPEAT('  ', depth - 1) || name AS org_chart, depth
FROM team ORDER BY depth, name;

-- ② 自底向上：Frank 到 CEO 的汇报链（面包屑）
WITH RECURSIVE chain AS (
    SELECT id, name, manager_id, 1 AS depth
    FROM employees WHERE id = 6
  UNION ALL
    SELECT e.id, e.name, e.manager_id, c.depth + 1
    FROM employees e JOIN chain c ON e.id = c.manager_id   -- ⚠️ 方向
)
SELECT name, depth FROM chain ORDER BY depth DESC;

-- ③ 团队汇总
WITH RECURSIVE team AS (
    SELECT id, salary, 1 AS depth FROM employees WHERE id = 1
  UNION ALL
    SELECT e.id, e.salary, t.depth + 1
    FROM employees e JOIN team t ON e.manager_id = t.id
)
SELECT COUNT(*) AS team_size, SUM(salary) AS total_salary, MAX(depth) AS org_depth
FROM team;
```

### 实验 5 · 递归 CTE：防环（三种方法对照）

```sql
-- 造一个带环的分类数据：10 → 11 → 12 → 11（回到 11）
INSERT INTO categories (id, name, parent_id) VALUES
    (10, '电子产品', NULL), (11, '电脑外设', 10), (12, '键盘', 11)
ON CONFLICT (id) DO UPDATE SET parent_id = EXCLUDED.parent_id;
UPDATE categories SET parent_id = 12 WHERE id = 11;   -- ⚠️ 制造环 11 → 12 → 11

-- ① UNION ALL + 无防护 → 死循环（不要真的跑，或者跑完立刻 cancel）
-- WITH RECURSIVE t AS (
--     SELECT id, parent_id FROM categories WHERE id = 10
--   UNION ALL
--     SELECT c.id, c.parent_id FROM categories c JOIN t ON c.parent_id = t.id
-- ) SELECT COUNT(*) FROM t;      -- ❌ 永不终止

-- ② depth 守卫（兜底，最简单）
WITH RECURSIVE t AS (
    SELECT id, parent_id, 1 AS depth FROM categories WHERE id = 10
  UNION ALL
    SELECT c.id, c.parent_id, t.depth + 1
    FROM categories c JOIN t ON c.parent_id = t.id
    WHERE t.depth < 10                    -- ← 最多 10 层
)
SELECT COUNT(*) FROM t;                   -- ✅ 能停

-- ③ PG 14+ CYCLE 子句（最精确）
WITH RECURSIVE t AS (
    SELECT id, parent_id FROM categories WHERE id = 10
  UNION ALL
    SELECT c.id, c.parent_id FROM categories c JOIN t ON c.parent_id = t.id
)
CYCLE id SET is_cycle USING path
SELECT id, parent_id, is_cycle, path FROM t;

-- ④ 用 CYCLE 反过来"揪出环"（数据治理）
WITH RECURSIVE t AS (
    SELECT id, parent_id FROM categories WHERE id = 10
  UNION ALL
    SELECT c.id, c.parent_id FROM categories c JOIN t ON c.parent_id = t.id
)
CYCLE id SET is_cycle USING path
SELECT id, path FROM t WHERE is_cycle;     -- ✅ 环的那一行的完整路径

-- ⑤ 手工数组防环（PG 14 之前）
WITH RECURSIVE t AS (
    SELECT id, parent_id, ARRAY[id] AS path FROM categories WHERE id = 10
  UNION ALL
    SELECT c.id, c.parent_id, t.path || c.id
    FROM categories c JOIN t ON c.parent_id = t.id
    WHERE NOT (c.id = ANY(t.path))
)
SELECT id, path FROM t;

-- 收尾：把环修掉
UPDATE categories SET parent_id = 10 WHERE id = 11;
```

### 实验 6 · 相关子查询：EXPLAIN 看 unnest

```sql
-- ① EXISTS → 应被 unnest 成 Semi Join
EXPLAIN SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
-- ✅ Hash Semi Join

-- ② NOT EXISTS → Anti Join
EXPLAIN SELECT * FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
-- ✅ Hash Anti Join

-- ③ IN → 也被 unnest 成 Semi Join
EXPLAIN SELECT * FROM users WHERE id IN (SELECT user_id FROM orders);
-- ✅ Hash Semi Join

-- ④ SELECT 列表里的相关子查询 → SubPlan（逐行！）
EXPLAIN SELECT o.id,
    (SELECT SUM(oi.quantity) FROM order_items oi WHERE oi.order_id = o.id) AS qty
FROM orders o;
-- ❌ SubPlan（未优化）

-- ⑤ 改成 JOIN 后消失
EXPLAIN SELECT o.id, COALESCE(SUM(oi.quantity), 0) AS qty
FROM orders o LEFT JOIN order_items oi ON oi.order_id = o.id
GROUP BY o.id;
-- ✅ Hash Left Join + HashAggregate（无 SubPlan）
```

### 实验 7 · `NOT IN` 的 NULL 陷阱复现

```sql
-- 造一个带 NULL 的数据
INSERT INTO orders (order_no, user_id) VALUES ('ORD-NULL-TEST', NULL);

-- ① NOT IN → 返回 0 行！
SELECT COUNT(*) FROM users WHERE id NOT IN (SELECT user_id FROM orders);
--  0   ← 因为子查询里有 NULL

-- ② NOT EXISTS → 正确
SELECT COUNT(*) FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
--  N   ← 正确结果

-- ③ 证明是 NULL 导致的
SELECT COUNT(*) FROM users
WHERE id NOT IN (SELECT user_id FROM orders WHERE user_id IS NOT NULL);
--  N   ← 排除 NULL 后与 NOT EXISTS 一致 ✅

-- 清理
DELETE FROM orders WHERE order_no = 'ORD-NULL-TEST';
```

---

## 第五幕 · 体系收束

### 本课小结（3 个知识点的全景）

```
本课 3 个知识点 = 复杂查询的"组织方式"：

  6.1 WITH 子句
       把嵌套改成从上往下的流水线（命名步骤）
       ⚠️ PG 12+ 默认行为：单次引用 + 无副作用 + 非递归 → 内联（可下推）
                          递归 / 有副作用 / 多次引用    → 物化
       MATERIALIZED / NOT MATERIALIZED 手动覆盖
       数据修改 CTE（WITH + INSERT/UPDATE/DELETE）→ 原子，但禁用并行

  6.2 递归 CTE
       WITH RECURSIVE = anchor（种子）+ 递归项 + 终止条件
       PG 用"工作表迭代"，递归 CTE 总是物化
       两个方向：自顶向下（c.parent_id = t.id）/ 自底向上（c.id = t.parent_id）
       ⚠️ 防环三件套：UNION 去重 / CYCLE 子句（PG 14+）/ depth 守卫
       ⚠️ join 列必须建索引

  6.3 相关子查询 vs JOIN
       相关 = 内层引用外层 → 逻辑上逐行执行
       优化器能救：IN / EXISTS / NOT EXISTS → semi-join / anti-join
       优化器救不了：NOT IN（NULL 语义）/ SELECT 列表里的相关标量子查询
       LATERAL 是"故意逐行"，外层行少时是最佳选择
       判断口诀：EXPLAIN 里看到 SubPlan 就警惕
```

### 阶段 2 四课的整合视图

```
┌─────────── 阶段 2 · 数据建模与 SQL 进阶 ───────────┐
│                                                     │
│  课 4 关系建模  ✅                                   │
│   4.1 主键/外键/唯一 · 4.2 三种关系 · 4.3 范式决策   │
│            ↓                                        │
│  课 5 视图与函数  ✅                                 │
│   5.1 三种视图 · 5.2 函数与过程 · 5.3 触发器         │
│            ↓                                        │
│  课 6 CTE 与子查询  ← 你在这里                       │
│   6.1 WITH · 6.2 递归 CTE · 6.3 相关子查询 vs JOIN   │
│            ↓                                        │
│  课 7 窗口函数（阶段 2 收官）                        │
│   7.1 OVER/PARTITION BY · 7.2 排名 · 7.3 滑动       │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### 决策心法（学完课 6 应能回答的 6 个判断）

| 问题 | 答案 |
|---|---|
| 长查询用嵌套还是 CTE？ | **CTE**（可读性）。性能相同时可读性就是标准 |
| CTE 一定只算一次吗？ | **不一定**。PG 12+ 单次引用默认内联；要保底写 `AS MATERIALIZED` |
| 什么时候用 `NOT MATERIALIZED`？ | 外层条件能大幅缩小结果时（如按主键过滤），要条件下推 |
| 递归 CTE 用 `UNION` 还是 `UNION ALL`？ | 树 → `UNION ALL`（快）；图/可能有环 → `UNION` 或 `CYCLE` |
| `NOT IN` 能用吗？ | **不能**（子查询场景）。用 `NOT EXISTS` |
| 怎么知道相关子查询被优化了没？ | `EXPLAIN` —— 看到 `SubPlan` 就是没救，看到 `Semi/Anti Join` 就是救了 |

### 命令速查卡（综合）

```sql
-- CTE
WITH name AS (SELECT ...) SELECT ...;
WITH a AS (...), b AS (... FROM a ...) SELECT ...;
WITH c AS MATERIALIZED (...) ...;        -- 强制只算一次
WITH c AS NOT MATERIALIZED (...) ...;    -- 强制内联

-- 数据修改 CTE（原子）
WITH moved AS (DELETE FROM src WHERE ... RETURNING *)
INSERT INTO dst SELECT * FROM moved RETURNING id;
-- ⚠️ 禁用并行；多写 CTE 顺序不保证

-- 递归
WITH RECURSIVE t AS (
    SELECT ... WHERE <起点>
  UNION ALL
    SELECT ... FROM tbl JOIN t ON <关系> WHERE t.depth < N
)
CYCLE id SET is_cycle USING path
SELECT ... FROM t WHERE NOT is_cycle;
-- ⚠️ join 列建索引；方向别搞反

-- 存在性
EXISTS / NOT EXISTS（✅ 可 unnest，NULL 安全）
NOT IN（❌ 禁用，NULL 陷阱）

-- 判断
EXPLAIN → SubPlan（坏） vs Semi/Anti Join（好）
```

### 事实速查（核查于 2026-09-07）

| 事实 | 当前值 | 来源 |
|---|---|---|
| **PG 12 CTE 行为变化** | PG 12 起，CTE 在满足"**非递归 + 无副作用 + 只被引用一次**"时**默认内联**（折叠进外层，允许条件下推）；否则物化。`MATERIALIZED` / `NOT MATERIALIZED` 可显式覆盖。**PG 11 及更早所有 CTE 一律物化**（优化屏障） | PG 12 release notes / commit 608b167f |
| 副作用的定义 | CTE 含 `INSERT/UPDATE/DELETE`，或含 **volatile 函数**（如 `random()`）→ 默认物化 | postgresql.org/docs/current/queries-with |
| 递归 CTE 是否内联 | **否。递归 CTE 总是物化**（PG 用工作表迭代机制，需维护中间结果） | postgresql.org/docs/current/queries-with |
| 递归 CTE 执行机制 | 工作表迭代：① 跑 anchor → 工作表 ② 用工作表跑递归项 → 新行成为下轮工作表 ③ 递归项返回 0 行则停 ④ 返回所有轮并集。**不是函数调用栈** | postgresql.org/docs/current/queries-with |
| `UNION` vs `UNION ALL`（递归中） | `UNION ALL` 不去重、**更快**、**有环时永不终止**；`UNION` 每轮去重、**有环能终止**、但每步有 hash/比较开销 | postgresql.org/docs/current/queries-with |
| PG 14+ `CYCLE` 子句 | 语法 `CYCLE <列> SET <标记列> USING <路径列>`；自动增加 `is_cycle`(bool) 与 `path`(array) 两列；`WHERE NOT is_cycle` 过滤环，`WHERE is_cycle` 可**揪出环** | postgresql.org/docs/current/queries-with |
| PG 14+ `SEARCH` 子句 | `SEARCH DEPTH FIRST BY col SET seq` / `SEARCH BREADTH FIRST BY col SET seq` 控制遍历顺序 | postgresql.org/docs/current/queries-with |
| 优化器 unnest 能力 | `IN` / `EXISTS` → **能**转 semi-join；`NOT EXISTS` → **能**转 anti-join；简单派生表 → **能** pull-up；**`NOT IN` 不能**（NULL 语义差异）；**SELECT 列表里的相关标量子查询几乎从不转换** | postgresql.org 优化器实践 / Redrock 子查询调优 |
| `NOT IN` 的 NULL 陷阱 | 子查询返回任何 NULL 时，`NOT IN` **永不为 TRUE** → 整句返回 0 行。SQL 标准语义，非 PG bug | postgresql.org/docs/current/functions-subquery |
| `LATERAL` | 允许子查询引用前面 FROM 项的列；PG 用 nested loop 执行（不 unnest）。外层行少 + 内层有索引时最优 | postgresql.org/docs/current/queries-table-expressions |
| 数据修改 CTE 限制 | `WITH` 里含 `INSERT/UPDATE/DELETE` 会**禁用整条语句的并行查询**（含只读部分）；多个写 CTE 的**执行顺序不保证** | postgresql.org/docs/current/queries-with |
| 物化溢出 | 物化 CTE 结果超过 `work_mem` 会**落盘**（temp file），不是错误但变慢；用 `EXPLAIN (ANALYZE, BUFFERS)` 查看 | 实践 / boringsql |
| PG 18 新特性 | PG 18 起 `EXPLAIN ANALYZE` 会报告 Material 节点的**内存/磁盘用量**（含 CTE 物化） | PG 18 release notes |

---

## 🧭 课程导航

> **本课在阶段 2 的位置**：阶段 2 四课中的**第三课**——把课 5 的"跨查询复用"收回到**单条查询内的分层组织**。
>
> **阶段 2 四课**（学完课 7 阶段 2 闭环）：
>
> - 课 4 关系建模 ✅
> - 课 5 视图与函数 ✅
> - 课 6 CTE 与子查询 ← **你在这里**
> - 课 7 窗口函数（**阶段 2 收官**）
>
> **整课任务完成标记**：6.1 + 6.2 + 6.3 三知识点均已交付 ✅（P0=0，3 项事实核查 PASS：PG 12+ CTE 内联规则 / 递归 CTE 与 CYCLE 子句 / 优化器 unnest 边界，见事实速查表）。

- 上一课：[课 5 视图与函数（三种视图 / plpgsql / 触发器）](lesson-05-视图与函数.md)（同阶段）
- 下一课：[课 7 窗口函数（OVER / 排名 / 滑动聚合）](lesson-07-窗口函数.md)（同阶段 · **阶段 2 收官**）
- 返回目录：[`02-课程目录.md`](../../02-课程目录.md)
- 上一阶 / 下一阶：阶段 1 已闭环 ✅（9 / 9）；当前在**阶段 2 · 数据建模与 SQL 进阶**（9 / 12 知识点）

> 🔁 **与前两课的衔接（本课回收的伏笔）**：
>
> - **课 4 自引用树**用过的 `WITH RECURSIVE` → 本课 6.2 **系统讲透**（语法骨架、执行机制、两个方向、防环三件套）
> - **课 5 的视图复用** → 本课 6.1 对比："视图是全局的，CTE 是这条查询内的备菜台"
> - **课 5 提到 `EXISTS`** → 本课 6.3 讲清它与 `IN` / `NOT IN` 的语义与优化差异
>
> **学完课 6 后你新增的能力**：
>
> - ✅ 把嵌套地狱改写成"先…再…最后…"的 CTE 流水线
> - ✅ 判断 CTE 会被内联还是物化，并用 `MATERIALIZED` / `NOT MATERIALIZED` 覆盖
> - ✅ 用数据修改 CTE 做原子性的"搬数据"
> - ✅ 写递归 CTE 遍历树（两个方向）与图（最短路径）
> - ✅ 用 `CYCLE`（PG 14+）/ path 数组 / depth 守卫防住无限递归
> - ✅ 用 `CYCLE ... WHERE is_cycle` 反向揪出数据里的环
> - ✅ 判断相关子查询该不该改，以及优化器能不能救（看 EXPLAIN 的 SubPlan）
> - ✅ 永远不用 `NOT IN (子查询)`
>
> **下一课预告 · 课 7 窗口函数（阶段 2 收官）**：
>
> - 7.1 `OVER` / `PARTITION BY` / `ORDER BY`（本课示例 6.3 里借用的 `AVG() OVER (PARTITION BY ...)` 会系统讲）
> - 7.2 排名函数（`ROW_NUMBER` / `RANK` / `DENSE_RANK` —— 本课 6.1 示例用过 `ROW_NUMBER`）
> - 7.3 聚合窗口函数 + 滑动窗口（移动平均、累计求和）
>
> 学完课 7，你就能写出"每个分类销售额 Top-3 商品""每个用户最近 3 笔订单的移动平均"这类查询，**阶段 2 闭环**。
