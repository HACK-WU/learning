# 课 5 · 视图与函数

> 📍 故事中的位置：常用查询不再每次都写一遍——主角的故事被沉淀成视图、函数、触发器

## 本课目标

学完本课后，你能：

1. 用视图 / 物化视图 / 可更新视图**封装复杂查询**，知道三者各自的适用边界
2. 用 `plpgsql` 写函数与存储过程，**判断何时该用函数、何时该用过程、何时该用视图**
3. 理解触发器的语义（行级 / 语句级、BEFORE / AFTER / INSTEAD OF）与三个典型陷阱

## 知识点清单

| 知识点 | 关键点 |
|---|---|
| **5.1 普通视图 / 可更新视图 / 物化视图** | · 普通视图 = 保存的查询（虚拟表，**不能建索引**） · 可更新视图：简单视图自动可更新（5 个条件）+ `INSTEAD OF` 触发器 + `WITH CHECK OPTION` · **物化视图** = 保存的结果（物理表，**必须建索引**）+ `REFRESH` 的两种刷新与 `CONCURRENTLY` 的 4 个硬条件 · 视图与权限的搭配 |
| **5.2 函数与存储过程（plpgsql 入门）** | · `CREATE FUNCTION ... LANGUAGE plpgsql` 骨架 · 参数 / 返回值 / 变量声明 / `DECLARE` · `PERFORM` / `RETURN QUERY` / `RAISE` · **FUNCTION vs PROCEDURE**（PG 11+）：返回值 / 调用方式 / **事务控制** |
| **5.3 触发器基础** | · 行级（`FOR EACH ROW`）vs 语句级（`FOR EACH STATEMENT`） · `BEFORE` / `AFTER` / `INSTEAD OF` · `NEW` / `OLD` / `TG_OP` 等特殊变量在各场景的可用性 · **典型陷阱**：递归触发 / 性能开销 / 调试困难 |

## 故事主线中的情节定位

主角的故事被固化——"这条订单被创建的同时自动写入订单日志"，这种业务规则开始从应用层下沉到数据库层。读者第一次感受到"业务不只是 PHP / Python 写的代码"。

## 正文

## 📌 知识点导航

本课首批（首批 = 课 5 全部 3 个知识点，阶段 2 第二课）覆盖：

| 节 | 知识点 | 核心问题 |
|---|---|---|
| 第三幕（一） | 5.1 三种视图 | 常用查询怎么"存下来复用" |
| 第三幕（二） | 5.2 函数与存储过程 | 带逻辑的复用该写在哪一层 |
| 第三幕（三） | 5.3 触发器基础 | 数据变更时自动做事，怎么不掉坑 |

---

## 第一幕 · 起源与场景引入

### 一个真实的工作场景

上一课你建好了 `users / orders / order_items / products` 四张表。现在第三周，你发现自己在**反复写同一段 SQL**：

```sql
-- 每天早上运营都要的"用户消费榜"，你已经手打了 20 遍
SELECT
    u.id,
    u.name,
    COUNT(o.id)          AS order_cnt,
    COALESCE(SUM(o.amount), 0) AS total_amount
FROM users u
LEFT JOIN orders o ON o.user_id = u.id AND o.status = 'paid'
GROUP BY u.id, u.name
ORDER BY total_amount DESC;
```

问题来了：

1. **每次都要复制粘贴** —— 运营同学也要用，你发了个 SQL 文本给他，下周他改了条件，你们俩的结果对不上
2. **跑得越来越慢** —— 用户表涨到 50 万，这查询每次 3 秒
3. **改一次要通知所有人** —— 你把 `status = 'paid'` 改成 `status IN ('paid','shipped')`，得在群里吼一圈

你脑子里闪过三个想法：

- **存成视图**？`CREATE VIEW user_spending AS SELECT ...` —— 大家查视图就行
- **存成物化视图**？数据先算好放那儿，秒开
- **写成函数**？传个参数还能查"某个时间段"的

**这三个都是对的，但用错场景会出事。**

更进一步的：PM 又说了一句

> "订单一创建，就自动往 `order_logs` 表写一条记录，谁也别忘。"

你心里一紧：这个"自动"，是写在 Python 代码里，还是**写在数据库里**？

> 如果写在 Python 里，另一个同事用 Go 写的服务、一个跑批脚本、一个 DBA 手动 `INSERT`，**都会绕过它**。
> 如果写在数据库触发器里，**所有写入路径都跑不掉**。

**这就是课 5 的主题 —— 把逻辑沉淀到数据库层的三种武器：视图、函数、触发器。**

### 一个关于"抽象层次"的小类比

把数据库想成一家餐厅：

| 武器 | 类比 | 本质 |
|---|---|---|
| **视图** | 菜单上的"套餐"—— 后厨现做 | 保存的**查询**，每次查都重新执行 |
| **物化视图** | 提前做好的**自助餐台** —— 拿起来就吃，但补菜有延迟 | 保存的**结果**，存在磁盘上 |
| **函数** | 点单时说的"**具体要求**"（"面煮软点"）—— 带参数 | 带逻辑的**可复用代码块** |
| **触发器** | **自动触发的规则**（"客人一落座就上茶"） | 数据变更时**自动执行**的代码 |

---

## 第二幕 · 认知冲突

这三个武器看起来都很美，**实际落地有 4 类隐藏陷阱**：

**陷阱一：以为"视图能加速查询"**

```sql
-- ❌ 错：视图不会让查询变快，它只是把 SQL 存起来
CREATE VIEW user_spending AS SELECT ...复杂的 JOIN + GROUP BY...;
SELECT * FROM user_spending;   -- 每次都重新执行底层查询，一样慢
```

**视图是"保存的查询"，不是"保存的结果"**。查询视图时，PG 把视图定义**展开（展开成原始 SQL）**再执行——性能跟手写一模一样。

想加速？**用物化视图**。

**陷阱二：物化视图建完就不管索引**

```sql
CREATE MATERIALIZED VIEW daily_gmv AS SELECT ...;
-- 你以为建完就快了？
SELECT * FROM daily_gmv WHERE day = '2026-09-01';   -- Seq Scan！
```

**物化视图就是一张物理表**。**没有索引的物化视图 = 没有索引的表**，每次查询全表扫。这是物化视图**最常见的错误**。

**陷阱三：`REFRESH ... CONCURRENTLY` 报莫名其妙的错**

```sql
REFRESH MATERIALIZED VIEW CONCURRENTLY daily_gmv;
-- ERROR:  cannot refresh materialized view "public.daily_gmv" concurrently
-- HINT:   Create a unique index with no WHERE clause on one or more columns of the materialized view.
```

CONCURRENTLY 有 **4 个硬条件**（详见第三幕），缺一个就报错。

**陷阱四：触发器里访问了不存在的 `NEW`**

```sql
CREATE FUNCTION log_delete() RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO order_logs(order_id) VALUES (NEW.id);  -- ❌ DELETE 时 NEW 是 NULL
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;
```

`NEW` 只在 **INSERT / UPDATE 的行级触发器**里有值；`OLD` 只在 **UPDATE / DELETE 的行级触发器**里有值。**搞反就是 NULL 或报错**。

---

## 第三幕 · 层层揭示

### （一）知识点 5.1 · 普通视图 / 可更新视图 / 物化视图

#### 一句话定义

**普通视图 = 保存的查询（虚拟表）；物化视图 = 保存的结果（物理表）。**

#### 直觉建立

```
普通视图（VIEW）
  ┌─────────────────┐
  │  只存 SQL 定义   │  ← 不占存储
  │  查询时展开执行   │  ← 每次重新算，永远最新
  └─────────────────┘
        ↓ 查一次算一次

物化视图（MATERIALIZED VIEW）
  ┌─────────────────┐
  │  存 SQL 定义     │
  │  + 存结果数据    │  ← 占磁盘，像一张真表
  └─────────────────┘
        ↓ 查一次直接读          ↓ REFRESH 才更新
```

| 维度 | 普通视图 | 物化视图 |
|---|---|---|
| 存储 | ❌ 不存数据 | ✅ 存数据（物理表） |
| 数据新鲜度 | ✅ 永远最新 | ❌ 快照，需 `REFRESH` |
| 查询速度 | 跟手写 SQL 一样 | ✅ **快**（预计算 + 可建索引） |
| **能建索引吗** | ❌ **不能** | ✅ **能，而且必须建** |
| 能 INSERT/UPDATE 吗 | 简单视图可以（可更新视图） | ❌ **不可更新** |
| 适用场景 | 简化查询 / 权限隔离 | 报表 / 大聚合 / 缓存 |

#### 普通视图：创建与使用

```sql
-- 封装"用户消费榜"
CREATE VIEW user_spending AS
SELECT
    u.id,
    u.name,
    COUNT(o.id)                 AS order_cnt,
    COALESCE(SUM(o.amount), 0)  AS total_amount
FROM users u
LEFT JOIN orders o ON o.user_id = u.id AND o.status = 'paid'
GROUP BY u.id, u.name;

-- 用起来跟表一样
SELECT * FROM user_spending ORDER BY total_amount DESC LIMIT 10;

-- 查看定义
SELECT definition FROM pg_views WHERE viewname = 'user_spending';
```

**视图的三个典型用途**：

1. **简化查询** —— 把 5 表 JOIN 封装成一个名字
2. **权限隔离** —— 只给用户视图的权限，不给底层表（如"隐藏 salary 列的员工视图"）
3. **兼容层** —— 底层表结构改了，改视图定义让老应用无感

> ⚠️ **注意 `SELECT *` 的坑**：`CREATE VIEW v AS SELECT * FROM t` 会在创建时**固化列列表**——之后 `t` 加新列，视图**不会**自动包含。需要 `CREATE OR REPLACE VIEW` 重建。

#### 可更新视图：5 个自动可更新条件

PG 官方规定，视图**同时满足以下 5 条**才"自动可更新"（能直接 INSERT/UPDATE/DELETE）：

1. `FROM` 列表**只有一项**，且必须是**表或另一个可更新视图**
2. 顶层**不含** `WITH` / `DISTINCT` / `GROUP BY` / `HAVING` / `LIMIT` / `OFFSET`
3. 顶层**不含**集合操作 `UNION` / `INTERSECT` / `EXCEPT`
4. 选择列表**不含**聚合函数、窗口函数、集合返回函数
5. 要 INSERT 的话，视图必须**包含所有无默认值的 NOT NULL 列**

```sql
-- ✅ 自动可更新：单表 + 无聚合 + 无 DISTINCT
CREATE VIEW active_users AS
SELECT id, name, email FROM users WHERE is_active = true;

UPDATE active_users SET name = '张三' WHERE id = 1;   -- ✅ 直接改 users 表

-- ❌ 不可自动更新：有 GROUP BY + 聚合
CREATE VIEW user_spending AS
SELECT u.id, u.name, SUM(o.amount) AS total
FROM users u LEFT JOIN orders o ON o.user_id = u.id
GROUP BY u.id, u.name;

UPDATE user_spending SET total = 999 WHERE id = 1;
-- ERROR: cannot update view "user_spending"
-- DETAIL: Views that do not select from a single table or view are not automatically updatable.
-- HINT:  To enable updating the view, provide an INSTEAD OF UPDATE trigger ...
```

**复杂视图要想可更新 → `INSTEAD OF` 触发器**

```sql
CREATE OR REPLACE FUNCTION update_user_spending() RETURNS TRIGGER AS $$
BEGIN
    -- 自己决定"改视图"意味着什么
    RAISE EXCEPTION 'user_spending 是聚合视图，不支持直接修改';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_user_spending_update
INSTEAD OF UPDATE ON user_spending
FOR EACH ROW EXECUTE FUNCTION update_user_spending();
```

> 💡 **`INSTEAD OF` 的硬规则**：
> - **只能建在视图上**（表上不行）
> - **必须是 `FOR EACH ROW`**（行级）
> - 表上的 `BEFORE` / `AFTER` 触发器可以是行级或语句级；**视图上的 `BEFORE`/`AFTER` 必须是语句级**

**`WITH CHECK OPTION`：防止插入"视图看不见"的行**

```sql
CREATE VIEW active_users AS
SELECT id, name, email, is_active FROM users WHERE is_active = true;

-- 没有 CHECK OPTION 时，这行能插进去，但视图里看不到（幽灵行）
INSERT INTO active_users (id, name, email, is_active) VALUES (99, '幽灵', 'g@x.com', false);

-- 加上 CHECK OPTION 后直接拒绝
CREATE VIEW active_users AS
SELECT id, name, email, is_active FROM users WHERE is_active = true
WITH CASCADED CHECK OPTION;

INSERT INTO active_users (...) VALUES (..., false);
-- ERROR: new row violates check option for view "active_users"
```

- `LOCAL CHECK OPTION`：只检查本视图的条件
- `CASCADED CHECK OPTION`：检查本视图**及所有底层视图**的条件（**推荐，更安全**）

#### 物化视图：创建、索引、刷新

**第一步：创建**

```sql
CREATE MATERIALIZED VIEW daily_gmv AS
SELECT
    DATE_TRUNC('day', created_at) AS day,
    COUNT(*)                      AS order_cnt,
    SUM(amount)                   AS gmv
FROM orders
WHERE status = 'paid'
GROUP BY 1
WITH DATA;          -- 默认，立即填充
```

`WITH NO DATA` 只建结构不填数据：

```sql
CREATE MATERIALIZED VIEW daily_gmv AS SELECT ... WITH NO DATA;
SELECT * FROM daily_gmv;
-- ERROR:  materialized view "daily_gmv" has not been populated
-- HINT:   Use the REFRESH MATERIALIZED VIEW command.
```

> 💡 **什么时候用 `WITH NO DATA`？** ① 迁移脚本里先建结构 ② 想**先建索引再填充**（空表建索引极快）③ 初始查询太贵，想放到维护窗口跑

**第二步：建索引（最容易忘、但必须做）**

```sql
-- ⚠️ 没有索引的物化视图 = 没有索引的表，全表扫
CREATE UNIQUE INDEX idx_daily_gmv_day ON daily_gmv (day);   -- CONCURRENTLY 需要它
CREATE INDEX idx_daily_gmv_gmv ON daily_gmv (gmv DESC);     -- 业务查询用
```

**第三步：刷新**

```sql
-- 普通刷新：拿 AccessExclusiveLock，清空重算，期间阻塞所有读
REFRESH MATERIALIZED VIEW daily_gmv;

-- 并发刷新：不阻塞读，但要求严格（见下）
REFRESH MATERIALIZED VIEW CONCURRENTLY daily_gmv;
```

**`CONCURRENTLY` 的 4 个硬条件（缺一即报错）**：

| # | 条件 | 说明 |
|---|---|---|
| 1 | 必须有 **UNIQUE 索引** | 普通索引不算 |
| 2 | 索引**不能带 WHERE** | 不能是部分索引（部分索引覆盖不全，无法标识所有行） |
| 3 | 索引列**不能含 NULL** | NULL ≠ NULL，无法判定"是不是同一行" |
| 4 | **视图必须已填充** | 空视图没有"旧数据"做差量对比，**首次必须用普通 REFRESH** |

```sql
-- 标准生产 SOP（照抄即可）
CREATE MATERIALIZED VIEW daily_gmv AS SELECT ... WITH NO DATA;   -- ① 先建空壳
CREATE UNIQUE INDEX idx_daily_gmv_day ON daily_gmv (day);        -- ② 空表建索引（快）
REFRESH MATERIALIZED VIEW daily_gmv;                             -- ③ 首次：必须普通刷新
REFRESH MATERIALIZED VIEW CONCURRENTLY daily_gmv;                -- ④ 之后：都可并发
```

> 💡 **为什么 CONCURRENTLY 需要唯一索引？** 它的机制是"**新旧数据做 FULL OUTER JOIN 差量对比**"——必须能唯一识别"新旧两张表里的同一行"，否则分不清哪行是新增、哪行被删、哪行被改。

**无唯一键时的兜底方案**（按优先级）：

```sql
-- 方案 A（最优）：保留业务主键
CREATE MATERIALIZED VIEW mv_orders AS SELECT order_id, ... FROM orders WITH NO DATA;
CREATE UNIQUE INDEX ON mv_orders (order_id);

-- 方案 B（聚合视图最优）：复合唯一索引
CREATE MATERIALIZED VIEW mv_daily_stats AS
    SELECT customer_id, created_at::date AS d, COUNT(*), SUM(amount)
    FROM orders GROUP BY 1, 2 WITH NO DATA;
CREATE UNIQUE INDEX ON mv_daily_stats (customer_id, d);

-- 方案 C（兜底）：ROW_NUMBER() 造行号
CREATE MATERIALIZED VIEW mv_x AS
    SELECT ROW_NUMBER() OVER (ORDER BY order_id) AS row_id, ... FROM orders WITH NO DATA;
CREATE UNIQUE INDEX ON mv_x (row_id);
-- ⚠️ row_id 每次 REFRESH 会重新编号，不能当稳定业务标识，不能被外键引用
```

**定时刷新**（PG 官方扩展 `pg_cron`）：

```sql
CREATE EXTENSION IF NOT EXISTS pg_cron;
SELECT cron.schedule('refresh-daily-gmv', '0 3 * * *',
                     'REFRESH MATERIALIZED VIEW CONCURRENTLY daily_gmv');
-- 每天凌晨 3 点
```

**PG 17 新特性 · `MAINTAIN` 权限**

```sql
-- PG 17 之前：只有 owner 能 REFRESH
-- PG 17 起：可以授予 MAINTAIN 权限，让非 owner 角色也能刷新
GRANT MAINTAIN ON daily_gmv TO refresh_role;
```

#### 视图与权限的搭配

```sql
-- 场景：给运营同学看用户消费数据，但不能看 email
CREATE VIEW ops_user_spending AS
SELECT u.id, u.name, COUNT(o.id) AS order_cnt, SUM(o.amount) AS total
FROM users u LEFT JOIN orders o ON o.user_id = u.id
GROUP BY u.id, u.name;

GRANT SELECT ON ops_user_spending TO ops_role;
-- ✅ ops_role 只能查视图，看不到 users.email，也碰不到 users 表
```

> 💡 **视图的权限规则**：
> - 使用者需要**视图上**的对应权限（SELECT / INSERT / ...）
> - **视图的 owner** 必须有底层表的权限（**使用者不需要**底层表权限）
> - 这就是视图做权限隔离的原理：**"使用者查视图 → 视图 owner 的身份去读底层表"**

#### 示例演示

```sql
-- 完整三件套：视图 + 物化视图 + 可更新视图
-- ① 普通视图：封装 JOIN（永远最新）
CREATE VIEW order_details AS
SELECT o.id, o.order_no, u.name AS user_name, o.amount, o.status, o.created_at
FROM orders o JOIN users u ON o.user_id = u.id;

-- ② 物化视图：日报（预计算 + 索引 + 定时刷新）
CREATE MATERIALIZED VIEW daily_gmv AS
SELECT DATE_TRUNC('day', created_at) AS day,
       COUNT(*) AS order_cnt, SUM(amount) AS gmv
FROM orders WHERE status = 'paid' GROUP BY 1
WITH NO DATA;
CREATE UNIQUE INDEX ON daily_gmv (day);
REFRESH MATERIALIZED VIEW daily_gmv;

-- ③ 可更新视图 + CHECK OPTION（权限隔离 + 防幽灵行）
CREATE VIEW my_orders AS
SELECT id, order_no, amount, status FROM orders WHERE user_id = 42
WITH CASCADED CHECK OPTION;
```

#### 常见误区 6 条

| 误区 | 反例 | 正解 |
|---|---|---|
| 以为视图能加速 | 建视图期待变快 | 视图 = 保存的查询，性能不变；要快用物化视图 |
| 物化视图不建索引 | 建完就查 | **必须建索引**，否则全表扫 |
| 空视图直接 CONCURRENTLY | 首次就并发刷新 | 首次必须普通 `REFRESH` |
| 用部分唯一索引配 CONCURRENTLY | `CREATE UNIQUE INDEX ... WHERE status='paid'` | 索引**不能带 WHERE** |
| `SELECT *` 建视图以为会跟着变 | 底层加列视图自动包含 | 视图**固化列列表**，需 `CREATE OR REPLACE` |
| 物化视图想 UPDATE | `UPDATE mv SET ...` | 物化视图**不可更新**，只能 `REFRESH` |

#### 一句话记住

> **视图存查询（不加速、不可建索引）；物化视图存结果（要建索引、要刷新）。**

#### 命令速查卡（5.1）

```sql
-- 普通视图
CREATE VIEW v AS SELECT ...;
CREATE OR REPLACE VIEW v AS SELECT ...;                 -- 改定义
CREATE VIEW v AS SELECT ... WITH CASCADED CHECK OPTION; -- 防幽灵行
DROP VIEW v;

-- 可更新视图（自动）需满足 5 条件：
--   FROM 单项 / 无 DISTINCT,GROUP BY,HAVING,LIMIT,OFFSET,WITH / 无 UNION 等 / 无聚合窗口 / 含所有无默认 NOT NULL 列

-- INSTEAD OF（只能建在视图，必须 FOR EACH ROW）
CREATE TRIGGER t INSTEAD OF UPDATE ON v
  FOR EACH ROW EXECUTE FUNCTION fn();

-- 物化视图
CREATE MATERIALIZED VIEW mv AS SELECT ... WITH [NO] DATA;
CREATE UNIQUE INDEX ON mv (col);              -- CONCURRENTLY 必需
CREATE INDEX ON mv (col2);                    -- 业务查询索引
REFRESH MATERIALIZED VIEW mv;                 -- 阻塞读
REFRESH MATERIALIZED VIEW CONCURRENTLY mv;    -- 不阻塞读（4 条件）
DROP MATERIALIZED VIEW mv;

-- PG 17 新权限
GRANT MAINTAIN ON mv TO role;                 -- 非 owner 也能刷新

-- 定时刷新（pg_cron）
SELECT cron.schedule('job', '0 3 * * *', 'REFRESH MATERIALIZED VIEW CONCURRENTLY mv');

-- 查看定义
SELECT definition FROM pg_views WHERE viewname = 'v';
SELECT definition FROM pg_matviews WHERE matviewname = 'mv';
```

---

### （二）知识点 5.2 · 函数与存储过程（plpgsql 入门）

#### 一句话定义

**函数 = 能在 SQL 里调用、有返回值的代码块；存储过程 = 只能用 `CALL` 调、**能控制事务**的代码块。**

#### 直觉建立

| | 函数 `FUNCTION` | 存储过程 `PROCEDURE` |
|---|---|---|
| 类比 | 计算器上的"√"键 —— 按了出结果 | 洗衣机上的"启动"键 —— 按了干活 |
| 返回值 | ✅ **必须有** `RETURNS` | ❌ 没有（可用 `OUT` 参数） |
| 怎么调 | `SELECT fn()` / `WHERE` 里 / `JOIN` 里 | **只能 `CALL proc()`** |
| 事务控制 | ❌ **禁止** `COMMIT` / `ROLLBACK` | ✅ **可以** `COMMIT` / `ROLLBACK` |
| 能在触发器里用 | ✅ 可以 | ❌ 不可以 |
| 引入版本 | 一直有 | **PG 11+** |

> 💡 **一句话选型**：**要结果 → 函数；要事务控制 → 存储过程。**

#### plpgsql 函数骨架

```sql
CREATE OR REPLACE FUNCTION function_name(param1 TYPE, param2 TYPE DEFAULT 值)
RETURNS 返回类型
LANGUAGE plpgsql
AS $$
DECLARE
    -- 变量声明区
    v_count INTEGER;
    v_name  TEXT;
BEGIN
    -- 逻辑区
    SELECT COUNT(*) INTO v_count FROM orders;

    IF v_count = 0 THEN
        RAISE EXCEPTION '没有订单';
    END IF;

    RETURN v_count;
END;
$$;
```

**五个关键语法点**：

**1. `LANGUAGE` 的三种常用选择**

| 语言 | 特点 | 何时用 |
|---|---|---|
| `LANGUAGE sql` | 纯 SQL，能被**内联优化**（性能最好） | 简单查询封装 |
| `LANGUAGE plpgsql` | 完整过程语言（IF / LOOP / 异常处理） | 有逻辑分支 |
| `LANGUAGE plpython3u` 等 | 外部语言 | 特殊需求（需装扩展） |

```sql
-- SQL 函数：可被内联，性能最好
CREATE FUNCTION add(a INT, b INT) RETURNS INT
LANGUAGE sql IMMUTABLE AS $$ SELECT a + b $$;
```

**2. 参数模式：`IN` / `OUT` / `INOUT`**

```sql
-- IN（默认）：传入
CREATE FUNCTION f(x INT) ...

-- OUT：传出
CREATE FUNCTION get_stats(OUT cnt INT, OUT total NUMERIC) ...
SELECT * FROM get_stats();     -- 返回一行两列

-- INOUT：传入并传出
CREATE FUNCTION bump(INOUT x INT) ...
```

**3. 返回类型**

```sql
RETURNS INTEGER                    -- 标量
RETURNS TEXT
RETURNS VOID                       -- 无返回值
RETURNS TABLE(id INT, name TEXT)   -- 返回表（最常用）
RETURNS SETOF users                -- 返回某表结构的行集
RETURNS RECORD                     -- 动态结构
```

**4. `PERFORM` / `RETURN QUERY` / `RAISE`**

```sql
-- PERFORM：执行一个查询但丢弃结果（plpgsql 里不能直接写裸 SELECT）
PERFORM some_function();
PERFORM 1 FROM orders WHERE id = 1;

-- RETURN QUERY：把查询结果追加到函数返回值
RETURN QUERY SELECT id, name FROM users WHERE is_active;

-- RAISE：输出信息 / 报错
RAISE NOTICE '处理了 % 行', v_count;         -- 提示
RAISE WARNING '数据可疑';                     -- 警告
RAISE EXCEPTION '金额不能为负: %', v_amount;  -- 报错并回滚
```

> ⚠️ **plpgsql 常见坑**：在 plpgsql 里写 `SELECT ...;` 会报 `query has no destination for result data`。要么 `SELECT ... INTO 变量`，要么用 `PERFORM`。

**5. `$$` 美元引用**

函数体用 `$$ ... $$` 包裹，内部的单引号**不需要转义**：

```sql
-- ✅ 用 $$：内部单引号直接写
AS $$ BEGIN RAISE NOTICE 'hello'; END $$;

-- ❌ 用单引号：内部每个单引号都要写两遍，地狱
AS 'BEGIN RAISE NOTICE ''hello''; END';
```

#### 实战：三个常用函数

```sql
-- ① 标量函数：算订单总额
CREATE OR REPLACE FUNCTION order_total(p_order_id BIGINT)
RETURNS NUMERIC
LANGUAGE plpgsql
AS $$
DECLARE
    v_total NUMERIC;
BEGIN
    SELECT COALESCE(SUM(unit_price * quantity), 0)
      INTO v_total
    FROM order_items
    WHERE order_id = p_order_id;

    RETURN v_total;
END;
$$;

SELECT order_total(1);

-- ② 表函数：返回某个用户的订单列表
CREATE OR REPLACE FUNCTION user_orders(p_user_id BIGINT)
RETURNS TABLE(order_id BIGINT, order_no TEXT, amount NUMERIC, created_at TIMESTAMPTZ)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT o.id, o.order_no, o.amount, o.created_at
    FROM orders o
    WHERE o.user_id = p_user_id
    ORDER BY o.created_at DESC;
END;
$$;

SELECT * FROM user_orders(42);

-- ③ 带异常处理的函数
CREATE OR REPLACE FUNCTION safe_insert_order(p_order_no TEXT, p_user_id BIGINT)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO orders (order_no, user_id) VALUES (p_order_no, p_user_id);
    RETURN true;
EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE '订单号 % 已存在，跳过', p_order_no;
    RETURN false;
END;
$$;
```

> 💡 **plpgsql 的"部分回滚"**：PG 里 `SAVEPOINT` / `ROLLBACK TO SAVEPOINT` **在 plpgsql 中一律禁止**。要做"出错只回滚这一段"，用**嵌套 `BEGIN ... EXCEPTION ... END` 块**——它会自动建一个隐式 savepoint：

```sql
BEGIN
    -- 主逻辑
    BEGIN
        -- 这段出错只回滚这里
        INSERT INTO risky_table VALUES (...);
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '跳过这条: %', SQLERRM;
    END;
    -- 主逻辑继续
END;
```

#### 存储过程（PROCEDURE）：什么时候用

```sql
CREATE OR REPLACE PROCEDURE archive_old_orders(p_before DATE)
LANGUAGE plpgsql
AS $$
DECLARE
    v_moved INTEGER;
BEGIN
    -- 把老订单搬到归档表
    INSERT INTO orders_archive
    SELECT * FROM orders WHERE created_at < p_before;

    GET DIAGNOSTICS v_moved = ROW_COUNT;

    DELETE FROM orders WHERE created_at < p_before;

    -- ✅ 存储过程里可以 COMMIT（函数里不行）
    COMMIT;
    RAISE NOTICE '归档了 % 条订单', v_moved;
END;
$$;

-- 调用：只能用 CALL
CALL archive_old_orders('2025-01-01');
```

> ⚠️ **带事务控制的 PROCEDURE 的限制**：
> - 不能在**显式事务块**里调用（`BEGIN; CALL ...; COMMIT;` 会报错）
> - 必须在**自动提交模式**下 `CALL`
> - 函数里**不能** `COMMIT`，写了会报 `ERROR: invalid transaction termination in function`
> - 不能在函数或 `DO` 块里 `CALL` 有事务控制的过程

**典型用途**：批量数据处理 / ETL / 分批归档 / 迁移脚本 —— **需要"每批提交一次，避免长事务"的场景**。

```sql
-- 分批提交（避免一个大事务锁全表）
CREATE PROCEDURE batch_update() LANGUAGE plpgsql AS $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT id FROM huge_table WHERE processed = false LIMIT 1000 LOOP
        UPDATE huge_table SET processed = true WHERE id = rec.id;
    END LOOP;
    COMMIT;    -- 每批提交一次
END;
$$;
```

#### 示例演示：把三个概念串起来

```sql
-- 场景：订单创建后要①写日志 ②更新用户消费额 ③返回结果

-- ① 函数：算订单总额（纯计算，可在 SQL 里用）
SELECT order_total(1);

-- ② 表函数：查用户订单（可在 FROM 里 JOIN）
SELECT u.name, o.order_no, o.amount
FROM users u, LATERAL user_orders(u.id) o
WHERE u.id = 42;

-- ③ 存储过程：夜间批量归档（需要事务控制）
CALL archive_old_orders('2025-01-01');
```

#### 常见误区 6 条

| 误区 | 反例 | 正解 |
|---|---|---|
| 函数里写 COMMIT | `CREATE FUNCTION ... BEGIN COMMIT; END` | ❌ 报 `invalid transaction termination`；要事务控制用 PROCEDURE |
| plpgsql 里裸 SELECT | `SELECT COUNT(*) FROM t;` | 用 `SELECT ... INTO 变量` 或 `PERFORM` |
| 用 `SELECT` 调存储过程 | `SELECT proc()` | 存储过程**只能 `CALL`** |
| 函数体用单引号 | `AS 'BEGIN ... ''x'' ... END'` | 用 `$$` 美元引用 |
| 以为 plpgsql 能用 SAVEPOINT | `SAVEPOINT sp;` | plpgsql **禁止**；用嵌套 `BEGIN...EXCEPTION...END` |
| 所有函数都用 plpgsql | 简单查询也写 plpgsql | 简单封装用 `LANGUAGE sql`（可内联优化，更快） |

#### 一句话记住

> **要结果用函数（SELECT 调用），要事务用过程（CALL 调用）；plpgsql 里裸 SELECT 不行，用 PERFORM 或 INTO。**

#### 命令速查卡（5.2）

```sql
-- 函数骨架
CREATE OR REPLACE FUNCTION fn(p1 TYPE, p2 TYPE DEFAULT 值)
RETURNS 类型
LANGUAGE plpgsql
AS $$
DECLARE
    v_var TYPE;
BEGIN
    SELECT col INTO v_var FROM t WHERE ...;
    PERFORM other_fn();
    RETURN QUERY SELECT ...;
    RAISE NOTICE 'msg %', v_var;
    RETURN v_var;
END;
$$;

-- 调用
SELECT fn(1);
SELECT * FROM fn_returning_table(1);

-- 存储过程
CREATE PROCEDURE proc(p TYPE) LANGUAGE plpgsql AS $$ BEGIN ... COMMIT; END $$;
CALL proc(1);

-- 异常处理（模拟 savepoint）
BEGIN
    ...
EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'dup: %', SQLERRM;
END;

-- 常用
GET DIAGNOSTICS v_n = ROW_COUNT;   -- 取影响行数
DROP FUNCTION fn(TYPE);            -- 删函数要带参数类型
DROP PROCEDURE proc(TYPE);
```

---

### （三）知识点 5.3 · 触发器基础

#### 一句话定义

**触发器 = 数据变更（INSERT / UPDATE / DELETE / TRUNCATE）时自动执行的函数。**

#### 直觉建立

把触发器想成**门禁系统**：

- **触发时机**（BEFORE / AFTER / INSTEAD OF）= 是进门**前**检查，还是进门**后**记录，还是**代替**开门做别的事
- **触发粒度**（ROW / STATEMENT）= 是**每个人**过闸机都检查，还是**一批人**进来只检查一次
- **触发事件**（INSERT / UPDATE / DELETE / TRUNCATE）= 什么动作触发

```sql
CREATE TRIGGER 触发器名
{BEFORE | AFTER | INSTEAD OF} {INSERT | UPDATE | DELETE | TRUNCATE}
ON 表名
[FOR EACH ROW | FOR EACH STATEMENT]
[WHEN (条件)]
EXECUTE FUNCTION 函数名();
```

#### 两个维度：时机 × 粒度

**时机（WHEN）**

| 时机 | 含义 | 典型用途 |
|---|---|---|
| **BEFORE** | 变更**发生前** | 校验 / 修正数据（如自动填 `updated_at`）；**返回 NULL 可取消该行操作** |
| **AFTER** | 变更**发生后** | 写审计日志 / 同步冗余字段（此时数据已确定） |
| **INSTEAD OF** | **代替**原操作 | **只能用在视图上**，把对视图的变更翻译到底层表 |

**粒度（LEVEL）**

```sql
FOR EACH ROW         -- 行级：每影响一行触发一次（1000 行 = 1000 次）
FOR EACH STATEMENT   -- 语句级：一条 SQL 只触发一次（不管影响多少行）
```

| 场景 | 行级 | 语句级 |
|---|---|---|
| 影响 1000 行时触发几次 | 1000 次 | **1 次** |
| 能访问 `NEW` / `OLD` | ✅ 能 | ❌ **都是 NULL** |
| 性能开销 | 大（逐行） | 小 |
| 典型用途 | 逐行校验 / 逐行同步 | 发通知 / 记录"有人改了这张表" |

> ⚠️ **硬规则**：**`TRUNCATE` 触发器只能是 `FOR EACH STATEMENT`**（TRUNCATE 没有"行"的概念，PG 不支持行级 TRUNCATE 触发器）。

**PG 的触发器支持矩阵**：

| 时机 | 事件 | 行级 | 语句级 |
|---|---|---|---|
| BEFORE | INSERT/UPDATE/DELETE | 表 | 表 + 视图 |
| BEFORE | TRUNCATE | ❌ | 表 |
| AFTER | INSERT/UPDATE/DELETE | 表 | 表 + 视图 |
| AFTER | TRUNCATE | ❌ | 表 |
| INSTEAD OF | INSERT/UPDATE/DELETE | **仅视图** | ❌ |
| INSTEAD OF | TRUNCATE | ❌ | ❌ |

#### 特殊变量：`NEW` / `OLD` / `TG_OP`

这是触发器函数里最重要的三个变量，也是**最容易搞混的地方**：

| 变量 | 含义 | 什么时候有值 |
|---|---|---|
| **`NEW`** | 变更后的新行（`RECORD`） | **行级**的 INSERT / UPDATE。→ **语句级 和 DELETE 时是 NULL** |
| **`OLD`** | 变更前的旧行（`RECORD`） | **行级**的 UPDATE / DELETE。→ **语句级 和 INSERT 时是 NULL** |
| **`TG_OP`** | 触发事件名 | 恒有：`'INSERT'` / `'UPDATE'` / `'DELETE'` / `'TRUNCATE'` |

**完整变量清单**：

| 变量 | 类型 | 说明 |
|---|---|---|
| `NEW` | `record` | 新行（INSERT/UPDATE 行级） |
| `OLD` | `record` | 旧行（UPDATE/DELETE 行级） |
| `TG_NAME` | `name` | 触发器名 |
| `TG_WHEN` | `text` | `'BEFORE'` / `'AFTER'` / `'INSTEAD OF'` |
| `TG_LEVEL` | `text` | `'ROW'` / `'STATEMENT'` |
| `TG_OP` | `text` | `'INSERT'` / `'UPDATE'` / `'DELETE'` / `'TRUNCATE'` |
| `TG_TABLE_NAME` | `name` | 触发表名（**用这个**，不要用废弃的 `TG_RELNAME`） |
| `TG_TABLE_SCHEMA` | `name` | 触发表的 schema |
| `TG_NARGS` / `TG_ARGV[]` | `int` / `text[]` | `CREATE TRIGGER` 传入的参数 |

**返回值规则（非常重要）**：

```sql
-- BEFORE 行级触发器：
RETURN NEW;    -- INSERT/UPDATE：正常继续（通常改完 NEW 再返回）
RETURN OLD;    -- DELETE：正常继续（DELETE 时 NEW 是 NULL，只能返回 OLD）
RETURN NULL;   -- ⚠️ 取消这一行的操作（后续的触发器也不跑了）

-- AFTER 行级 / 任意语句级触发器：
RETURN NULL;   -- 返回值被忽略，随便返回什么都行（但 AFTER 里 RAISE EXCEPTION 能中止整个操作）

-- INSTEAD OF 触发器：
RETURN NULL;   -- 表示"没做任何更新"，跳过该行
RETURN NEW;    -- INSERT/UPDATE 成功（支持 RETURNING）
RETURN OLD;    -- DELETE 成功
```

#### 实战：三个常用触发器

**① 自动维护 `updated_at`（BEFORE UPDATE）**

```sql
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := now();      -- 直接改 NEW 的字段
    RETURN NEW;                   -- 必须返回 NEW
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated
BEFORE UPDATE ON users
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
```

**② 审计日志（AFTER，用 TG_OP 区分操作）**

```sql
CREATE TABLE order_logs (
    id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id  BIGINT,
    action    TEXT NOT NULL,
    changed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION log_order_change() RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO order_logs(order_id, action) VALUES (NEW.id, 'created');
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO order_logs(order_id, action) VALUES (NEW.id, 'updated');
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO order_logs(order_id, action) VALUES (OLD.id, 'deleted');  -- ⚠️ 用 OLD
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_order_audit
AFTER INSERT OR UPDATE OR DELETE ON orders
FOR EACH ROW EXECUTE FUNCTION log_order_change();
```

**③ 同步冗余字段（AFTER，课 4 的 order_count 完整版）**

```sql
CREATE OR REPLACE FUNCTION sync_user_order_count() RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE users SET order_count = order_count + 1 WHERE id = NEW.user_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE users SET order_count = order_count - 1 WHERE id = OLD.user_id;
    ELSIF TG_OP = 'UPDATE' AND NEW.user_id <> OLD.user_id THEN
        -- 订单换了主人：旧主人 -1，新主人 +1
        UPDATE users SET order_count = order_count - 1 WHERE id = OLD.user_id;
        UPDATE users SET order_count = order_count + 1 WHERE id = NEW.user_id;
    END IF;
    RETURN NULL;    -- AFTER 触发器返回值被忽略
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_order_count
AFTER INSERT OR UPDATE OR DELETE ON orders
FOR EACH ROW EXECUTE FUNCTION sync_user_order_count();
```

> 💡 课 4 实验 4 只处理了 INSERT / DELETE，**这里补上了 UPDATE 换主人的情况** —— 这正是"触发器要覆盖所有变更路径"的典型例子。

**④ 防止误删（BEFORE DELETE 返回 NULL 取消）**

```sql
CREATE OR REPLACE FUNCTION prevent_paid_order_delete() RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status = 'paid' THEN
        RAISE EXCEPTION '已支付订单（%s）不能删除', OLD.order_no;
    END IF;
    RETURN OLD;     -- DELETE 的 BEFORE 返回 OLD
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_no_delete_paid
BEFORE DELETE ON orders
FOR EACH ROW EXECUTE FUNCTION prevent_paid_order_delete();
```

#### 触发器的三个典型陷阱

**陷阱 1 · 递归触发（无限循环）**

```sql
-- ❌ 危险：AFTER UPDATE 里又 UPDATE 同一张表 → 又触发 → 无限递归
CREATE TRIGGER trg_a AFTER UPDATE ON orders
FOR EACH ROW EXECUTE FUNCTION fn_that_updates_orders();
-- ERROR: stack depth limit exceeded（或无限循环直到资源耗尽）
```

**解法**：

```sql
-- 方案 A：加 WHEN 条件，只在字段真的变了才触发
CREATE TRIGGER trg_a AFTER UPDATE OF status ON orders   -- 只监听 status 列
FOR EACH ROW WHEN (OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION fn();

-- 方案 B：函数内加守卫
IF NEW.updated_at = OLD.updated_at THEN RETURN NEW; END IF;

-- 方案 C：临时关掉（会话级）
ALTER TABLE orders DISABLE TRIGGER trg_a;
-- ... 批量操作 ...
ALTER TABLE orders ENABLE TRIGGER trg_a;

-- 方案 D：用 pg_trigger_depth() 限制递归深度
IF pg_trigger_depth() > 1 THEN RETURN NEW; END IF;
```

**陷阱 2 · 性能开销（行级触发器 × 批量操作）**

```sql
-- ❌ 一次 UPDATE 10 万行 → 触发器执行 10 万次，每次一条 UPDATE
UPDATE orders SET status = 'paid' WHERE created_at < '2026-01-01';
-- 慢 10 倍不止
```

**解法**：

```sql
-- 方案 A：批量场景改用语句级触发器（只跑 1 次）
CREATE TRIGGER trg_x AFTER UPDATE ON orders
FOR EACH STATEMENT EXECUTE FUNCTION fn_batch();

-- 方案 B：批量操作前临时禁用触发器
ALTER TABLE orders DISABLE TRIGGER trg_order_count;
UPDATE orders SET status = 'paid' WHERE ...;
-- 手动补一次对账
UPDATE users u SET order_count = (SELECT COUNT(*) FROM orders o WHERE o.user_id = u.id);
ALTER TABLE orders ENABLE TRIGGER trg_order_count;
```

**陷阱 3 · 调试困难（触发器是"隐形"的）**

触发器的问题在于：**你跑一条 `INSERT`，背后悄悄跑了一堆逻辑，报错时你不知道是谁干的**。

**排查手段**：

```sql
-- ① 看这张表上挂了哪些触发器
SELECT tgname, tgtype, tgenabled, proname
FROM pg_trigger t
JOIN pg_proc p ON p.oid = t.tgfoid
WHERE tgrelid = 'orders'::regclass AND NOT tgisinternal;

-- ② 触发器函数里加 RAISE NOTICE（客户端能看到）
RAISE NOTICE 'TG_OP=%, order_id=%', TG_OP, NEW.id;

-- ③ 用 pg_trigger_depth() 看当前递归深度
RAISE NOTICE 'depth=%', pg_trigger_depth();

-- ④ 临时禁用某个触发器定位问题
ALTER TABLE orders DISABLE TRIGGER trg_order_count;
```

> 💡 **纪律**：触发器**只做"必须一致、不能被绕过"的事**（审计、冗余同步、强校验）。**业务逻辑尽量放应用层** —— 触发器里的逻辑最难测试、最难调试、最难迁移。

#### 示例演示：完整的审计方案

```sql
-- ① 建日志表
CREATE TABLE audit_log (
    id       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tbl      TEXT NOT NULL,
    op       TEXT NOT NULL,
    row_id   BIGINT,
    payload  JSONB,
    at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ② 通用审计函数（用 to_jsonb 把整行存进 JSONB）
CREATE OR REPLACE FUNCTION audit_trigger() RETURNS TRIGGER AS $$
DECLARE
    v_payload JSONB;
    v_row_id  BIGINT;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_payload := to_jsonb(OLD);
        v_row_id  := (to_jsonb(OLD)->>'id')::BIGINT;
    ELSE
        v_payload := to_jsonb(NEW);
        v_row_id  := (to_jsonb(NEW)->>'id')::BIGINT;
    END IF;

    INSERT INTO audit_log(tbl, op, row_id, payload)
    VALUES (TG_TABLE_NAME, TG_OP, v_row_id, v_payload);

    RETURN NULL;   -- AFTER 触发器，返回值忽略
END;
$$ LANGUAGE plpgsql;

-- ③ 挂到 orders 上（一张函数复用到多张表）
CREATE TRIGGER trg_audit_orders
AFTER INSERT OR UPDATE OR DELETE ON orders
FOR EACH ROW EXECUTE FUNCTION audit_trigger();

CREATE TRIGGER trg_audit_users
AFTER INSERT OR UPDATE OR DELETE ON users
FOR EACH ROW EXECUTE FUNCTION audit_trigger();

-- ④ 查看审计
SELECT op, row_id, payload->>'order_no' AS order_no, at
FROM audit_log WHERE tbl = 'orders' ORDER BY at DESC LIMIT 10;
```

#### 常见误区 6 条

| 误区 | 反例 | 正解 |
|---|---|---|
| DELETE 触发器里用 NEW | `VALUES (NEW.id)` | DELETE 只有 `OLD`，`NEW` 是 NULL |
| 语句级触发器里用 NEW/OLD | `FOR EACH STATEMENT ... NEW.id` | 语句级**两者都是 NULL** |
| TRUNCATE 想写行级触发器 | `FOR EACH ROW ... TRUNCATE` | TRUNCATE **只能语句级** |
| BEFORE 触发器忘了 RETURN | 函数没有 RETURN | BEFORE 行级必须返回（NULL 会取消操作） |
| AFTER 里 UPDATE 同表导致递归 | AFTER UPDATE 里 UPDATE 自己 | 加 `WHEN` / `UPDATE OF col` / `pg_trigger_depth()` 守卫 |
| 批量操作不禁用行级触发器 | 10 万行 UPDATE 逐行触发 | 批量前 `DISABLE TRIGGER`，之后手动对账 |

#### 一句话记住

> **BEFORE 能改数据能取消，AFTER 做日志做同步，INSTEAD OF 只在视图；NEW 是新的、OLD 是旧的，DELETE 只有 OLD。**

#### 命令速查卡（5.3）

```sql
-- 创建触发器
CREATE TRIGGER t_name
{BEFORE|AFTER|INSTEAD OF} {INSERT|UPDATE|DELETE|TRUNCATE}
ON tbl
[FOR EACH ROW | FOR EACH STATEMENT]
[WHEN (条件)]
EXECUTE FUNCTION fn();

-- 只监听某列变化
AFTER UPDATE OF col1, col2 ON tbl
FOR EACH ROW WHEN (OLD.col1 IS DISTINCT FROM NEW.col1)

-- 触发器函数骨架
CREATE OR REPLACE FUNCTION fn() RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN ... RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN ... RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN ... RETURN OLD;
    END IF;
    RETURN NULL;
END; $$ LANGUAGE plpgsql;

-- 管理触发器
ALTER TABLE tbl DISABLE TRIGGER t_name;
ALTER TABLE tbl ENABLE TRIGGER t_name;
ALTER TABLE tbl DISABLE TRIGGER ALL;
DROP TRIGGER t_name ON tbl;

-- 查看触发器
SELECT tgname, tgenabled FROM pg_trigger
WHERE tgrelid = 'tbl'::regclass AND NOT tgisinternal;

-- 防递归
WHERE pg_trigger_depth() <= 1
CREATE TRIGGER ... AFTER UPDATE OF col ...   -- 只监听指定列

-- 通用审计（to_jsonb 存整行）
v_payload := to_jsonb(NEW);   -- 或 OLD
```

---

## 第四幕 · 实操验证

### 实验环境

延续前四课：`localhost:5432` 上 `postgres:17` 容器，`order_service` 库 `finance` schema（users / orders / order_items / products 四表已建）。

```sql
docker start pg17
docker exec -it pg17 psql -U postgres -d order_service
SET search_path TO finance, public;
```

### 实验 1 · 普通视图：封装 + 验证"不加速"

```sql
-- 建视图封装订单明细
CREATE OR REPLACE VIEW order_details AS
SELECT o.id, o.order_no, u.name AS user_name, o.amount, o.status, o.created_at
FROM orders o JOIN users u ON o.user_id = u.id;

-- 查视图
SELECT * FROM order_details ORDER BY created_at DESC LIMIT 5;

-- 用 EXPLAIN 看：视图被展开成底层 JOIN（证明"不加速"）
EXPLAIN SELECT * FROM order_details WHERE user_name = 'Alice';
-- 计划里出现 Hash Join (orders × users) —— 视图被展开，跟手写 SQL 一样
```

### 实验 2 · 可更新视图 + CHECK OPTION

```sql
-- 自动可更新视图（单表 + 无聚合）
CREATE OR REPLACE VIEW active_users AS
SELECT id, name, email, is_active FROM users WHERE is_active = true;

-- 直接 UPDATE 视图 → 实际改 users 表
UPDATE active_users SET name = '爱丽丝' WHERE id = 1;
SELECT name FROM users WHERE id = 1;    -- 爱丽丝 ✅

-- 幽灵行问题：不加 CHECK OPTION 能插入视图看不见的行
INSERT INTO users (email, name, is_active) VALUES ('g@x.com', '幽灵用户', false);
INSERT INTO active_users (id, name, email, is_active)
SELECT id, name, email, is_active FROM users WHERE email = 'g@x.com';
SELECT COUNT(*) FROM active_users WHERE name = '幽灵用户';   -- 0（插进去了但看不见）

-- 加 CHECK OPTION 后拒绝
CREATE OR REPLACE VIEW active_users AS
SELECT id, name, email, is_active FROM users WHERE is_active = true
WITH CASCADED CHECK OPTION;

INSERT INTO active_users (id, name, email, is_active)
SELECT id, name, email, is_active FROM users WHERE email = 'g@x.com';
-- ERROR: new row violates check option for view "active_users" ✅
```

### 实验 3 · 物化视图：完整 SOP + CONCURRENTLY 报错复现

```sql
-- ① 建空壳
CREATE MATERIALIZED VIEW daily_gmv AS
SELECT DATE_TRUNC('day', created_at) AS day,
       COUNT(*) AS order_cnt,
       SUM(amount) AS gmv
FROM orders
GROUP BY 1
WITH NO DATA;

-- ② 查空视图 → 报错
SELECT * FROM daily_gmv;
-- ERROR: materialized view "daily_gmv" has not been populated
-- HINT:  Use the REFRESH MATERIALIZED VIEW command.

-- ③ 什么都不建，直接并发刷新 → 复现报错
REFRESH MATERIALIZED VIEW CONCURRENTLY daily_gmv;
-- ERROR: cannot refresh materialized view "finance.daily_gmv" concurrently
-- HINT:  Create a unique index with no WHERE clause on one or more columns of the materialized view.

-- ④ 建唯一索引（CONCURRENTLY 的四条件：UNIQUE / 无 WHERE / 无 NULL / 已填充）
CREATE UNIQUE INDEX idx_daily_gmv_day ON daily_gmv (day);

-- ⑤ 空视图仍然不能用 CONCURRENTLY → 复现第二个坑
REFRESH MATERIALIZED VIEW CONCURRENTLY daily_gmv;
-- ERROR: cannot refresh materialized view "finance.daily_gmv" concurrently
-- DETAIL: The materialized view has not been populated.

-- ⑥ 首次必须普通刷新
REFRESH MATERIALIZED VIEW daily_gmv;
SELECT COUNT(*) FROM daily_gmv;   -- 有数据了 ✅

-- ⑦ 之后可以并发
REFRESH MATERIALIZED VIEW CONCURRENTLY daily_gmv;   -- ✅

-- ⑧ 建业务索引（不建就 Seq Scan）
EXPLAIN SELECT * FROM daily_gmv WHERE gmv > 1000;
CREATE INDEX idx_daily_gmv_gmv ON daily_gmv (gmv DESC);
EXPLAIN SELECT * FROM daily_gmv WHERE gmv > 1000;   -- 走索引 ✅

-- ⑨ PG 17 新权限：让非 owner 也能刷新
GRANT MAINTAIN ON daily_gmv TO postgres;
```

### 实验 4 · 函数：三种返回类型

```sql
-- ① 标量函数
CREATE OR REPLACE FUNCTION order_total(p_order_id BIGINT)
RETURNS NUMERIC LANGUAGE plpgsql AS $$
DECLARE v_total NUMERIC;
BEGIN
    SELECT COALESCE(SUM(unit_price * quantity), 0) INTO v_total
    FROM order_items WHERE order_id = p_order_id;
    RETURN v_total;
END; $$;

SELECT order_total(1);

-- ② 表函数
CREATE OR REPLACE FUNCTION user_orders(p_user_id BIGINT)
RETURNS TABLE(order_id BIGINT, order_no TEXT, amount NUMERIC)
LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT o.id, o.order_no, o.amount FROM orders o
    WHERE o.user_id = p_user_id ORDER BY o.created_at DESC;
END; $$;

SELECT * FROM user_orders(1);

-- ③ 异常处理 + 部分回滚
CREATE OR REPLACE FUNCTION safe_insert_user(p_email TEXT, p_name TEXT)
RETURNS BOOLEAN LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO users (email, name) VALUES (p_email, p_name);
    RETURN true;
EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE '邮箱 % 已存在，跳过', p_email;
    RETURN false;     -- ✅ 只有这个 INSERT 被回滚，外层不受影响
END; $$;

SELECT safe_insert_user('a@x.com', '重复');   -- NOTICE + false（不报错）
```

### 实验 5 · 存储过程：事务控制（对比函数）

```sql
-- ① 函数里 COMMIT → 报错
CREATE OR REPLACE FUNCTION fn_try_commit() RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO users (email, name) VALUES ('t1@x.com', 'T1');
    COMMIT;
END; $$;

SELECT fn_try_commit();
-- ERROR: invalid transaction termination
-- DETAIL: A COMMIT was executed inside a PL/pgSQL function...

-- ② 存储过程里 COMMIT → 成功
CREATE TABLE IF NOT EXISTS proc_test (id INT, note TEXT);

CREATE OR REPLACE PROCEDURE proc_try_commit() LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO proc_test VALUES (1, 'first');
    COMMIT;
    INSERT INTO proc_test VALUES (2, 'second');
    COMMIT;
END; $$;

CALL proc_try_commit();              -- ✅ 成功
SELECT * FROM proc_test;             -- 两行都在

-- ③ 证明"不能 SELECT 调过程"
SELECT proc_try_commit();
-- ERROR: procedure proc_try_commit() ... 必须用 CALL
```

### 实验 6 · 触发器：NEW/OLD + 递归陷阱

```sql
-- ① 审计日志表
CREATE TABLE IF NOT EXISTS order_logs (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id BIGINT, action TEXT, at TIMESTAMPTZ DEFAULT now()
);

-- ② 审计触发器（演示 NEW / OLD / TG_OP）
CREATE OR REPLACE FUNCTION log_order_change() RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO order_logs(order_id, action) VALUES (NEW.id, 'created');
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO order_logs(order_id, action) VALUES (NEW.id, 'updated');
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO order_logs(order_id, action) VALUES (OLD.id, 'deleted');
        RETURN OLD;
    END IF;
    RETURN NULL;
END; $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_order_audit
AFTER INSERT OR UPDATE OR DELETE ON orders
FOR EACH ROW EXECUTE FUNCTION log_order_change();

-- ③ 验证三种操作
INSERT INTO orders (order_no, user_id) VALUES ('ORD900', 1);
UPDATE orders SET status = 'paid' WHERE order_no = 'ORD900';
DELETE FROM orders WHERE order_no = 'ORD900';
SELECT order_id, action FROM order_logs ORDER BY id;
--  created / updated / deleted  ✅

-- ④ 演示"DELETE 里用 NEW 会报错"
CREATE OR REPLACE FUNCTION bad_delete_fn() RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO order_logs(order_id, action) VALUES (NEW.id, 'x');  -- ❌
    RETURN OLD;
END; $$ LANGUAGE plpgsql;
-- 实际运行时：record "new" is not assigned yet / NEW 为 NULL

-- ⑤ 递归陷阱演示
CREATE OR REPLACE FUNCTION recursive_fn() RETURNS TRIGGER AS $$
BEGIN
    UPDATE orders SET amount = amount WHERE id = NEW.id;   -- 又 UPDATE orders
    RETURN NEW;
END; $$ LANGUAGE plpgsql;
-- 若挂上 AFTER UPDATE 会无限递归 → stack depth limit exceeded

-- ✅ 正解：加 WHEN 条件 + 深度守卫
CREATE OR REPLACE FUNCTION safe_fn() RETURNS TRIGGER AS $$
BEGIN
    IF pg_trigger_depth() > 1 THEN RETURN NEW; END IF;    -- 深度守卫
    RETURN NEW;
END; $$ LANGUAGE plpgsql;

-- ⑥ 查看触发器
SELECT tgname, tgenabled FROM pg_trigger
WHERE tgrelid = 'finance.orders'::regclass AND NOT tgisinternal;

-- ⑦ 批量操作前禁用（性能）
ALTER TABLE orders DISABLE TRIGGER trg_order_audit;
UPDATE orders SET status = 'paid' WHERE created_at < now();
ALTER TABLE orders ENABLE TRIGGER trg_order_audit;
```

---

## 第五幕 · 体系收束

### 本课小结（3 个知识点的全景）

```
本课 3 个知识点 = 把逻辑沉淀到数据库层的三种武器：

  5.1 三种视图
       普通视图   = 保存的查询（虚拟表，不能建索引，不加速）
       可更新视图 = 满足 5 条件的简单视图 / 否则用 INSTEAD OF 触发器
       物化视图   = 保存的结果（物理表，必须建索引，要 REFRESH）
                    CONCURRENTLY 的 4 个硬条件
                    PG 17 新增 MAINTAIN 权限

  5.2 函数与存储过程
       函数       = 有返回值，SELECT 调用，❌ 不能 COMMIT
       存储过程   = 无返回值，CALL 调用，✅ 能 COMMIT（PG 11+）
       plpgsql 骨架：DECLARE / BEGIN / PERFORM / RETURN QUERY / RAISE
       ⚠️ 裸 SELECT 不行；SAVEPOINT 禁止，用嵌套 BEGIN...EXCEPTION

  5.3 触发器基础
       时机：BEFORE（可改可取消）/ AFTER（日志同步）/ INSTEAD OF（仅视图）
       粒度：行级（逐行，能访问 NEW/OLD）/ 语句级（一次，NEW/OLD 为 NULL）
       变量：NEW（INSERT/UPDATE 行级）/ OLD（UPDATE/DELETE 行级）/ TG_OP
       陷阱：递归触发 / 批量性能 / 调试困难
```

### 阶段 2 四课的整合视图

```
┌─────────── 阶段 2 · 数据建模与 SQL 进阶 ───────────┐
│                                                     │
│  课 4 关系建模  ✅                                   │
│   4.1 主键/外键/唯一 · 4.2 三种关系 · 4.3 范式决策   │
│            ↓  设计好了，怎么复用？                   │
│  课 5 视图与函数  ← 你在这里                         │
│   5.1 三种视图 · 5.2 函数与过程 · 5.3 触发器         │
│            ↓  逻辑复杂了，怎么组织？                 │
│  课 6 CTE 与子查询                                   │
│   6.1 WITH 子句 · 6.2 递归 CTE · 6.3 相关子查询     │
│            ↓  要做分组内排名？                       │
│  课 7 窗口函数                                       │
│   7.1 OVER/PARTITION BY · 7.2 排名 · 7.3 滑动       │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### 决策心法（学完课 5 应能回答的 6 个判断）

| 问题 | 答案 |
|---|---|
| 想让查询变快，用视图还是物化视图？ | **物化视图**。普通视图不加速（只是保存查询） |
| 视图和物化视图都能建索引吗？ | **只有物化视图能**。而且物化视图**必须**建索引 |
| 物化视图首次刷新能用 CONCURRENTLY 吗？ | **不能**。空视图没旧数据做差量，首次必须普通 REFRESH |
| CONCURRENTLY 需要什么样的索引？ | **UNIQUE** + **不带 WHERE** + **列不含 NULL** |
| 要返回结果用函数还是过程？ | **函数**（SELECT 调用、有 RETURNS） |
| 要批量归档、每批提交一次呢？ | **存储过程**（CALL 调用、能 COMMIT） |
| DELETE 触发器里能访问 NEW 吗？ | **不能**。DELETE 只有 `OLD`，`NEW` 是 NULL |
| 批量更新 10 万行，触发器怎么办？ | 批量前 `DISABLE TRIGGER`，之后手动对账；或改语句级触发器 |

### 命令速查卡（综合）

```sql
-- 三视图
CREATE VIEW v AS SELECT ...;                       -- 存查询
CREATE VIEW v AS SELECT ... WITH CASCADED CHECK OPTION;  -- 防幽灵行
CREATE MATERIALIZED VIEW mv AS SELECT ... WITH [NO] DATA;  -- 存结果
CREATE UNIQUE INDEX ON mv (col);                   -- CONCURRENTLY 必需
REFRESH MATERIALIZED VIEW mv;                       -- 首次 / 阻塞
REFRESH MATERIALIZED VIEW CONCURRENTLY mv;          -- 后续 / 不阻塞

-- 函数 vs 过程
CREATE FUNCTION fn() RETURNS 类型 LANGUAGE plpgsql AS $$ ... $$;
SELECT fn();
CREATE PROCEDURE proc() LANGUAGE plpgsql AS $$ ... COMMIT; ... $$;
CALL proc();

-- 触发器
CREATE TRIGGER t {BEFORE|AFTER|INSTEAD OF} {INSERT|UPDATE|DELETE|TRUNCATE}
ON tbl FOR EACH ROW EXECUTE FUNCTION fn();

-- 防坑速记
--  · 视图不加速 → 要快用物化视图
--  · 物化视图必须建索引
--  · CONCURRENTLY 四条件：UNIQUE / 无 WHERE / 无 NULL / 已填充
--  · 函数不能 COMMIT，过程才能
--  · plpgsql 裸 SELECT 不行 → PERFORM 或 INTO
--  · DELETE 只有 OLD；语句级 NEW/OLD 皆 NULL；TRUNCATE 只能语句级
--  · 批量前 DISABLE TRIGGER，之后对账
```

### 事实速查（核查于 2026-09-06）

| 事实 | 当前值 | 来源 |
|---|---|---|
| **普通视图能建索引吗** | **不能**。视图是虚拟表（保存的查询），不占存储；**只有物化视图能建索引**。查询普通视图时 PG 把定义展开执行，性能与手写 SQL 相同 | postgresql.org/docs/17/sql-createview |
| 自动可更新视图的 5 条件 | ① FROM 只有一项（表或可更新视图）② 顶层无 WITH/DISTINCT/GROUP BY/HAVING/LIMIT/OFFSET ③ 顶层无 UNION/INTERSECT/EXCEPT ④ 选择列表无聚合/窗口/集合返回函数 ⑤ INSERT 需包含所有无默认值的 NOT NULL 列 | postgresql.org/docs/17/sql-createview |
| `INSTEAD OF` 触发器限制 | **只能建在视图上**，且**必须 `FOR EACH ROW`**；表上不支持。视图上的 BEFORE/AFTER 必须 `FOR EACH STATEMENT` | postgresql.org/docs/17/sql-createtrigger |
| `REFRESH ... CONCURRENTLY` 条件 | 需 **UNIQUE 索引**（普通索引不行）、**不能带 WHERE**（不能是部分索引）、**索引列不能含 NULL**、**视图必须已填充**（首次必须普通 REFRESH）。缺任一条报 `cannot refresh materialized view ... concurrently` | postgresql.org/docs/17/sql-refreshmaterializedview |
| 物化视图可否 UPDATE | **不可更新**，只能 `REFRESH` | postgresql.org/docs/17/sql-creatematerializedview |
| PG 17 `MAINTAIN` 权限 | PG 17 **新增** `GRANT MAINTAIN ON mv TO role` —— 允许非 owner 角色刷新物化视图（此前需 owner 权限） | PG 17 release notes |
| `NEW` / `OLD` 可用性 | `NEW`：行级 INSERT/UPDATE 有值，**语句级和 DELETE 时为 NULL**；`OLD`：行级 UPDATE/DELETE 有值，**语句级和 INSERT 时为 NULL** | postgresql.org/docs/17/plpgsql-trigger |
| `TG_OP` 取值 | `'INSERT'` / `'UPDATE'` / `'DELETE'` / `'TRUNCATE'` | postgresql.org/docs/17/plpgsql-trigger |
| TRUNCATE 触发器粒度 | **只能 `FOR EACH STATEMENT`**，不支持行级 | postgresql.org/docs/17/sql-createtrigger |
| `TG_RELNAME` | **已废弃**，用 `TG_TABLE_NAME`（+ `TG_TABLE_SCHEMA`） | postgresql.org/docs/17/plpgsql-trigger |
| FUNCTION vs PROCEDURE | 函数：有 `RETURNS`、`SELECT` 调用、**禁止 COMMIT/ROLLBACK**（报 `invalid transaction termination`）、可用于触发器；过程：**无 RETURNS**、只能 `CALL`、**支持 COMMIT/ROLLBACK**、**PG 11+ 引入**、不能用于触发器 | postgresql.org/docs/17/xproc |
| plpgsql 中的 SAVEPOINT | `SAVEPOINT` / `RELEASE SAVEPOINT` / `ROLLBACK TO SAVEPOINT` 在 plpgsql 中**一律禁止**；部分回滚用嵌套 `BEGIN ... EXCEPTION ... END`（隐式 savepoint） | postgresql.org/docs/17/plpgsql-control-structures |
| BEFORE 触发器返回值 | 行级 BEFORE：返回 `NEW`（INSERT/UPDATE）/ `OLD`（DELETE）/ **NULL = 取消该行操作**。AFTER 与语句级返回值被忽略 | postgresql.org/docs/17/plpgsql-trigger |

---

## 🧭 课程导航

> **本课在阶段 2 的位置**：阶段 2 四课中的**第二课**——把课 4 设计好的关系，用视图 / 函数 / 触发器沉淀下来复用。
>
> **阶段 2 四课**（学完课 7 阶段 2 闭环）：
>
> - 课 4 关系建模（[上一课 →](lesson-04-关系建模.md)）
> - 课 5 视图与函数 ← **你在这里**
> - 课 6 CTE 与子查询
> - 课 7 窗口函数
>
> **整课任务完成标记**：5.1 + 5.2 + 5.3 三知识点均已交付 ✅（P0=0，4 项事实核查 PASS：视图不可建索引 / 物化视图 CONCURRENTLY 4 条件 / NEW-OLD 可用性 / FUNCTION vs PROCEDURE，见事实速查表）。

- 上一课：[课 4 关系建模（主键/外键/三种关系/范式决策）](lesson-04-关系建模.md)（同阶段）
- 下一课：[课 6 CTE 与子查询（WITH 子句 / 递归 CTE / 相关子查询）](lesson-06-CTE与子查询.md)（同阶段）
- 返回目录：[`02-课程目录.md`](../../02-课程目录.md)
- 上一阶 / 下一阶：阶段 1 已闭环 ✅（9 / 9）；当前在**阶段 2 · 数据建模与 SQL 进阶**（6 / 12 知识点）

> 🔁 **与课 4 的衔接（本课补全了上一课埋的伏笔）**：
>
> - 课 4 实验 4 的 `sync_user_order_count` 触发器 → 本课 5.3 **补全了 UPDATE 换主人的分支**与三个典型陷阱
> - 课 4 实验里用到的 `REFRESH MATERIALIZED VIEW` → 本课 5.1 **系统讲透**（WITH NO DATA / CONCURRENTLY 四条件 / 必须建索引）
>
> **学完课 5 后你新增的能力**：
>
> - ✅ 用普通视图封装复杂 JOIN（并知道它不加速）
> - ✅ 用可更新视图 + `WITH CHECK OPTION` 做权限隔离与防幽灵行
> - ✅ 用物化视图做报表加速，掌握完整 SOP（建空壳 → 建索引 → 首次刷新 → 并发刷新）
> - ✅ 用 plpgsql 写函数（标量 / 表函数 / 异常处理）
> - ✅ 判断何时用函数、何时用存储过程（事务控制是分水岭）
> - ✅ 写 BEFORE / AFTER / INSTEAD OF 触发器，正确处理 `NEW` / `OLD` / `TG_OP`
> - ✅ 避开触发器的三个典型陷阱（递归 / 批量性能 / 调试困难）
>
> **下一课预告 · 课 6 CTE 与子查询**：
>
> - 6.1 `WITH` 子句（把本课视图的"临时复用"搬到**单条查询内**）
> - 6.2 递归 CTE（**课 4 自引用树用过**，本课系统讲语法与终止条件）
> - 6.3 相关子查询 vs JOIN（性能取舍，配合 `EXPLAIN` 实证）
