# 课 4 · 关系建模

> 📍 故事中的位置：一笔订单牵连出订单明细、用户、商品——主角从"一个人"变成"一条关系链"

## 本课目标

学完本课后，你能：

1. 为一个业务域设计表结构，**区分**主键 / 外键 / 唯一键的适用场景
2. 识别一对多 / 多对多 / 自引用关系，并把多对多拆成"中间表 + 两端外键"
3. 在"完全范式化"和"反范式加冗余字段"之间**做出有理由的决策**

## 知识点清单

| 知识点 | 关键点 |
|---|---|
| **4.1 主键 / 外键 / 唯一约束** | · 主键的"业务键 vs 代理键"之争 · 自然键 vs `GENERATED AS IDENTITY` / UUID · 外键的 5 种引用动作（NO ACTION / RESTRICT / CASCADE / SET NULL / SET DEFAULT） · **外键不会自动建索引**（PG 17 仍未变） · 唯一约束与主键的差别 · 复合主键的取舍 |
| **4.2 一对多 / 多对多 / 自引用** | · 一对多（用户→订单）的标准模式 · 多对多拆中间表（订单↔商品 → `order_items`） · 自引用（评论的 `parent_comment_id`）+ 三种树模型选择 · 多态关联（PG 没有原生，需中间表模拟） |
| **4.3 范式与反范式（决策点）** | · 三大范式的本意（1NF / 2NF / 3NF） · 反范式的三大模式（缓存聚合 / 快照历史 / 物化视图） · **决策点**：查询性能 vs 写入一致性的权衡 · PG 的反范式手段（触发器维护冗余 / 物化视图 / JSONB 中间地带） |

## 故事主线中的情节定位

主角从"一条订单"变成"一条关系链"——订单有一堆明细、明细指商品、商品有分类、用户有地址。读者学会的不是语法，而是"识别两个实体的关系类型并正确建模"。

## 正文

## 📌 知识点导航

本课首批（首批 = 课 4 全部 3 个知识点，**阶段 2 开篇课**）覆盖：

| 节 | 知识点 | 核心问题 |
|---|---|---|
| 第三幕（一） | 4.1 主键 / 外键 / 唯一约束 | 用什么当"身份证"，两张表怎么"认亲" |
| 第三幕（二） | 4.2 一对多 / 多对多 / 自引用 | 三种关系长什么样，怎么翻译成表 |
| 第三幕（三） | 4.3 范式与反范式（决策点） | 该不该冗余，什么时候该冗余 |

---

## 第一幕 · 起源与场景引入

### 一个真实的工作场景

上一课你学会了找数据。现在 PM 又来了，这次不是提查询需求，**是提业务变更**：

> "订单要支持**多商品**了 —— 一笔订单可以买好几个商品，每个商品有自己的数量和成交价。"

你打开现在的 `orders` 表一看：

```sql
CREATE TABLE orders (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_no   TEXT NOT NULL UNIQUE,
    user_id    INTEGER NOT NULL,
    amount     NUMERIC(10,2) NOT NULL,
    status     TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

**问题来了**：`amount` 是整单金额，但一个订单有多个商品，**每个商品的价格和数量存哪儿？**

你脑子里可能闪过三个方案：

1. **在 orders 里加 `product_ids TEXT`** —— 把商品 id 用逗号拼起来存（`1,2,3`）
2. **加 `product_1 / product_2 / product_3` 三列** —— 反正一般也就买 3 个
3. **新建一张 `order_items` 表** —— 一行一个商品

三个方案都能"跑起来"。但：

- 方案 1：想查"买了商品 42 的所有订单"要 `LIKE '%,42,%'` ——**慢且会误匹配 142**
- 方案 2：有人买第 4 个商品时，**改表结构**
- 方案 3：多一张表、多一个 JOIN，但**可以无限扩展**

**这就是"关系建模"**——不是学新语法，是学"怎么把现实世界的东西翻译成表"。

### 一个关于"建模"本质的小类比

你可以把建模想成**整理衣柜**：

- **实体（表）** = 一类东西（上衣 / 裤子 / 袜子）
- **属性（列）** = 这件东西的特征（颜色 / 尺码）
- **主键** = 每件衣服的唯一编号（不能有两件同号）
- **外键** = "这件外套配的是 3 号围巾"——**指向另一个格子里的东西**
- **关系类型** = 一件上衣配几条裤子？（一对多 / 多对多）

**范式** 就是"一格只放一类东西，别混着塞"；
**反范式** 就是"把常一起穿的一套挂在一起，省得每次找两遍"。

---

## 第二幕 · 认知冲突

光会建表，**实际落地有 4 类隐藏陷阱**：

**陷阱一：以为"外键 = 自动有索引"**

```sql
-- 你以为 PG 会帮你建索引？不会。
CREATE TABLE orders (
    user_id INTEGER REFERENCES users(id)   -- ⚠️ 引用侧没有索引！
);
```

PG **只保证"被引用侧"有索引**（因为 FK 必须引用 PK / UNIQUE，而这两个都自动建 B-tree 索引）。
**"引用侧"（子表的外键列）PG 不会自动建索引** ——这是你自己的责任。PG 17 与历史版本一致，官方文档原文：

> "the declaration of a foreign key constraint does not automatically create an index on the referencing columns"

后果：父表删一行 → PG 必须**全表扫子表**确认有没有引用它的行。子表百万行时，删一个用户要几秒。

**陷阱二：默认 `ON DELETE` 行为不知道是什么**

```sql
-- 什么都不写 = NO ACTION
FOREIGN KEY (user_id) REFERENCES users(id)
```

`NO ACTION` 和 `RESTRICT` 看起来都是"不让删"，**但有个关键区别**：NO ACTION 允许把检查推迟到事务后面（配合 `SET CONSTRAINTS ... DEFERRED`），**RESTRICT 不允许**。这个差别在你写"先删子表再删父表"的事务时会救命。

**陷阱三：`ON DELETE CASCADE` 随手就加**

```sql
-- 看起来很方便：删用户自动删他的订单
FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
```

方便是真方便，**危险也是真危险**：运维手滑 `DELETE FROM users WHERE id = 42`，**42 号用户 3 年的订单连带明细一条不留**。生产环境 CASCADE 是**事故高发区**。

**陷阱四：以为"范式越高越好"**

```sql
-- 3NF 纯净版：订单详情必须 JOIN 商品表才能看到名字
SELECT oi.quantity, p.title, p.price
FROM order_items oi JOIN products p ON oi.product_id = p.id;
```

但商品明天改名、后天涨价了 ——**你去年那笔订单的明细跟着变了**。财务对账时对不上，因为历史订单"活"了。

**这时候反而该反范式**：在 `order_items` 里**快照**当时的 `product_name` 和 `unit_price`。

---

## 第三幕 · 层层揭示

### （一）知识点 4.1 · 主键 / 外键 / 唯一约束

#### 一句话定义

**主键 = 行的身份证（唯一 + 非空）；外键 = 指向别人家主键的指针；唯一约束 = 值不能重复（但可以是 NULL）。**

#### 直觉建立

| 约束 | 比喻 | 能不能空 | 一张表几个 | 自动建索引 |
|---|---|---|---|---|
| **PRIMARY KEY** | 身份证号 | ❌ 不能 | **最多 1 个** | ✅ B-tree（唯一） |
| **UNIQUE** | 邮箱 / 手机号 | ✅ 能（多个 NULL 不冲突） | 任意多个 | ✅ B-tree（唯一） |
| **FOREIGN KEY** | "我爸是谁" | ✅ 能（NULL 表示"没有"） | 任意多个 | ❌ **引用侧不建** |

> ⚠️ **UNIQUE 与 NULL 的坑**：PG 默认 `NULLS DISTINCT` —— 两个 NULL **不算重复**，所以 UNIQUE 列可以有很多行 NULL。想让 NULL 也算重复得显式写 `UNIQUE NULLS NOT DISTINCT`（PG 15+ 支持）。

#### 主键之争：业务键 vs 代理键

这是建模第一道分水岭。

**方案 A · 业务键（自然键，natural key）**

```sql
CREATE TABLE orders (
    order_no TEXT PRIMARY KEY,   -- 用业务订单号当主键
    ...
);
```

- ✅ 有业务含义，人能读懂，跨系统同步天然幂等
- ❌ 业务规则一变就完蛋（订单号规则从 `ORD2026xxxx` 改成 `T2026xxxx`）
- ❌ 字符串主键索引比 BIGINT 大、JOIN 慢
- ❌ 一旦发出去就改不了（改主键 = 改所有引用它的表）

**方案 B · 代理键（surrogate key）**

```sql
CREATE TABLE orders (
    id       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,  -- 无意义的自增
    order_no TEXT NOT NULL UNIQUE,                             -- 业务号降级为 UNIQUE
    ...
);
```

- ✅ 与业务解耦，业务规则随便改
- ✅ BIGINT 索引小、JOIN 快
- ❌ 无业务含义，跨系统同步要额外映射

**方案 C · UUID / UUIDv7（分布式场景）**

```sql
CREATE EXTENSION IF NOT EXISTS pg_uuidv7;  -- PG 17 新增扩展

CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    ...
);
```

- ✅ 可以在**应用层生成**主键，不需要回查数据库 → 适合分库分表 / 多写
- ✅ 天然防遍历（不会被人猜出"你有 100 万订单"）
- ❌ 16 字节 vs BIGINT 8 字节，索引更大
- ❌ 随机 UUID（v4）插入会导致 B-tree 页分裂 → **必须用有序的 UUIDv7**

> 💡 **决策规则**：
> - 单机 / 主从（99% 业务）→ **BIGINT IDENTITY**（PG 17 推荐）
> - 需要多写 / 数据合并 / 前端提前知道 id → **UUIDv7**（PG 17 有 `pg_uuidv7` 扩展）
> - 绝不要用 UUIDv4 当主键（随机插入毁索引）

#### 外键的 5 种引用动作

```sql
FOREIGN KEY (col) REFERENCES parent(id) ON DELETE <动作> ON UPDATE <动作>
```

| 动作 | 删父行时 | 关键特性 |
|---|---|---|
| **NO ACTION**（默认） | 有引用行就报错 | ✅ **允许检查推迟到事务后期**（配合 `SET CONSTRAINTS DEFERRED`） |
| **RESTRICT** | 有引用行就报错 | ❌ **不允许推迟检查**，立刻报错 |
| **CASCADE** | 引用行**一起删** | ⚠️ 危险但方便（明细类数据适用） |
| **SET NULL** | 引用列设为 NULL | 引用列必须可为 NULL；可指定列列表 |
| **SET DEFAULT** | 引用列设为默认值 | 默认值必须仍满足 FK，否则报错 |

**NO ACTION vs RESTRICT 到底差在哪？**

```sql
-- RESTRICT：立刻检查，下面这句直接失败
BEGIN;
DELETE FROM users WHERE id = 42;     -- ❌ ERROR: 仍有 orders 引用
DELETE FROM orders WHERE user_id = 42;
COMMIT;

-- NO ACTION + DEFERRABLE：检查推迟到 COMMIT，下面这句成功
BEGIN;
SET CONSTRAINTS fk_orders_user DEFERRED;
DELETE FROM users WHERE id = 42;     -- 先删父表，暂不检查
DELETE FROM orders WHERE user_id = 42;  -- 再把子表清了
COMMIT;                              -- ✅ 此刻检查：没有悬空引用，通过
```

> 💡 **实践建议**：绝大多数情况用默认的 `NO ACTION` 就够了。只有当你确实需要在事务里"临时打破引用完整性再补回来"，才用 `DEFERRABLE INITIALLY DEFERRED`。

**什么时候用 CASCADE？** PG 官方文档给的判据：

> "When the referencing table represents something that is a **component** of what is represented by the referenced table and cannot exist independently, then CASCADE could be appropriate."

翻译：**子表是父表的"组成部分"、离开父表就没意义** → CASCADE 合适。

```sql
-- ✅ 合适：order_items 是 orders 的组成部分，订单没了明细也没意义
FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE

-- ❌ 不合适：products 与 orders 是独立实体，删商品不该连带删掉历史订单
FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE   -- 危险！
-- 应该：
FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE RESTRICT
```

#### 外键索引：PG 不帮你做，你得自己做

```
被引用侧（父表 users.id）  → PK/UNIQUE → PG 自动建 B-tree 索引 ✅
引用侧（子表 orders.user_id）→ 外键列   → PG 不建索引 ❌
```

**为什么引用侧必须建索引？** 三个场景会全表扫子表：

1. 父表 `DELETE` 一行 → 扫子表找引用行
2. 父表被引用的键 `UPDATE` → 扫子表找引用行
3. 按外键列 `JOIN` / 过滤 → 没索引就 Seq Scan

```sql
-- 建表后补索引（生产必备）
CREATE INDEX idx_orders_user_id ON orders (user_id);
CREATE INDEX idx_order_items_order_id ON order_items (order_id);
```

> 💡 **一条纪律**：**每写一个外键，就顺手在引用侧建一个索引。** 除非你能证明这张子表永远不会有父表删除 / 关联查询。

#### 复合主键的取舍

```sql
-- 多对多中间表：复合主键很自然
CREATE TABLE order_items (
    order_id   BIGINT NOT NULL REFERENCES orders(id),
    product_id BIGINT NOT NULL REFERENCES products(id),
    quantity   INTEGER NOT NULL,
    PRIMARY KEY (order_id, product_id)     -- 复合主键
);
```

- ✅ 天然保证"一个订单里同一商品只有一行"
- ❌ 别的表引用它时要带两列（外键写起来啰嗦）
- 💡 **常见替代**：复合主键 + 单独 `id BIGINT GENERATED ALWAYS AS IDENTITY UNIQUE`，用代理键简化引用

#### 示例演示

```sql
-- order_service 库的完整关系骨架（阶段 2 目标形态）
CREATE TABLE users (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email      TEXT NOT NULL UNIQUE,
    name       TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE products (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    title      TEXT NOT NULL,
    price      NUMERIC(10,2) NOT NULL CHECK (price >= 0),
    category_id BIGINT REFERENCES categories(id) ON DELETE SET NULL
);

CREATE TABLE orders (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_no   TEXT NOT NULL UNIQUE,
    user_id    BIGINT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    status     TEXT NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_orders_user_id ON orders (user_id);        -- ⚠️ 引用侧补索引
CREATE INDEX idx_orders_created_at ON orders (created_at DESC);

CREATE TABLE order_items (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id    BIGINT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id  BIGINT NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    product_name TEXT NOT NULL,          -- 快照（反范式，见 4.3）
    unit_price  NUMERIC(10,2) NOT NULL,  -- 快照
    quantity    INTEGER NOT NULL CHECK (quantity > 0),
    UNIQUE (order_id, product_id)
);
CREATE INDEX idx_order_items_order_id   ON order_items (order_id);
CREATE INDEX idx_order_items_product_id ON order_items (product_id);
```

#### 常见误区 6 条

| 误区 | 反例 | 正解 |
|---|---|---|
| 以为外键自动建索引 | 建完 FK 就不管了 | 引用侧**手动** `CREATE INDEX` |
| 随手 `ON DELETE CASCADE` | 用户表加 CASCADE | 明细类用 CASCADE；独立实体用 RESTRICT |
| UNIQUE 以为能防重复 NULL | `email TEXT UNIQUE` 存了 5 个 NULL | PG 默认 `NULLS DISTINCT`；要防得写 `UNIQUE NULLS NOT DISTINCT`（PG 15+） |
| 用 UUIDv4 当主键 | `DEFAULT gen_random_uuid()` | 改用 **UUIDv7**（PG 17 有 `pg_uuidv7` 扩展） |
| 拿业务字段当主键 | `order_no TEXT PRIMARY KEY` | 代理键 + 业务号降为 `UNIQUE` |
| 以为 NO ACTION = RESTRICT | 混用 | NO ACTION **可 defer**，RESTRICT **不可** |

#### 一句话记住

> **主键身份证、外键认亲戚、唯一防重复；外键建了记得补索引，删父表的动作想清楚再选。**

#### 命令速查卡（4.1）

```sql
-- 主键（PG 17 推荐 IDENTITY）
id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY
PRIMARY KEY (col1, col2)                       -- 复合主键

-- 唯一约束
email TEXT NOT NULL UNIQUE
UNIQUE NULLS NOT DISTINCT (col)                -- PG 15+：NULL 也算重复
CONSTRAINT uk_name UNIQUE (col1, col2)         -- 命名 + 复合

-- 外键（5 种动作）
REFERENCES parent(id)                                    -- 默认 NO ACTION
REFERENCES parent(id) ON DELETE RESTRICT                 -- 不可 defer
REFERENCES parent(id) ON DELETE CASCADE                  -- 连带删（明细类）
REFERENCES parent(id) ON DELETE SET NULL                 -- 置空（列需可空）
REFERENCES parent(id) ON DELETE SET DEFAULT              -- 置默认值
REFERENCES parent(id) ON UPDATE CASCADE                  -- 键更新时同步

-- 可延迟约束
CONSTRAINT fk_x FOREIGN KEY (c) REFERENCES p(id) DEFERRABLE INITIALLY DEFERRED
SET CONSTRAINTS fk_x DEFERRED;                 -- 事务内推迟检查

-- 引用侧补索引（PG 不自动建！）
CREATE INDEX idx_child_parent ON child (parent_id);

-- UUIDv7（PG 17）
CREATE EXTENSION IF NOT EXISTS pg_uuidv7;
id UUID PRIMARY KEY DEFAULT uuid_generate_v7()
```

---

### （二）知识点 4.2 · 一对多 / 多对多 / 自引用

#### 一句话定义

**一对多 = 在"多"的那侧存"一"的主键；多对多 = 拆一张中间表，两端各存一个外键；自引用 = 外键指向自己这张表。**

#### 直觉建立

想象三张便利贴墙：

```
一对多（用户 → 订单）：
  用户的便利贴上写着"我有这些订单"，但现实做法是——
  → 订单便利贴上写"我的 user_id 是 5"

多对多（订单 ↔ 商品）：
  一笔订单有多个商品，一个商品出现在多笔订单
  → 单独拿一张"配对表"：一行 = (订单 7, 商品 42, 数量 2)

自引用（评论 → 父评论）：
  评论的便利贴上写"我回复的是第 88 号评论"
  → 外键指向自己这张表
```

#### 一对多：标准模式

```sql
-- "多"的那侧存外键
CREATE TABLE orders (
    id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id),   -- ← 在这里
    ...
);
```

**判据**：问自己"一个 X 有几个 Y？"
- 一个用户有**多**笔订单 → 外键放**订单**表
- 一个订单有**一**个用户 → 不放订单表里再存"用户列表"

> ❌ **反模式**：在用户表里存 `order_ids TEXT`（逗号拼接）
> - 查"订单 42 属于谁"要全表扫 + 字符串匹配
> - 无法用外键保证订单真实存在
> - 无法限制"一个订单只能属于一个用户"

#### 多对多：拆中间表

```sql
-- 订单 ↔ 商品 是多对多 → 拆出 order_items
CREATE TABLE order_items (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id   BIGINT NOT NULL REFERENCES orders(id)   ON DELETE CASCADE,
    product_id BIGINT NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    quantity   INTEGER NOT NULL CHECK (quantity > 0),

    -- 同一订单同一商品只出现一次
    UNIQUE (order_id, product_id)
);
```

**中间表的三个设计决策**：

| 决策 | 选项 | 建议 |
|---|---|---|
| 要不要独立 `id`？ | 复合主键 `(order_id, product_id)` vs 独立 `id` | **有独立业务含义**（如"这条明细要被退款单引用）→ 要 `id`；纯关联 → 复合主键即可 |
| 中间表能不能带属性？ | 纯两列 vs 带 `quantity` / `unit_price` | **能带，而且通常都带** —— 中间表往往是业务实体（订单明细）而不只是关联 |
| 唯一性怎么保证？ | `UNIQUE (order_id, product_id)` | 加上，防止同一商品重复插入 |

#### 自引用：树形结构

```sql
-- 评论回复评论
CREATE TABLE comments (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    post_id         BIGINT NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    parent_id       BIGINT REFERENCES comments(id) ON DELETE CASCADE,  -- ← 指向自己
    author_id       BIGINT NOT NULL REFERENCES users(id),
    body            TEXT NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_comments_parent_id ON comments (parent_id);
```

**这是"邻接表（adjacency list）"模型** —— 每行只记 `parent_id`。写起来最简单。

##### 三种树模型的取舍（重要决策）

| 模型 | 存什么 | 查整棵子树 | 写入 / 移动 | 适用 |
|---|---|---|---|---|
| **邻接表 + 递归 CTE** | `parent_id` | 递归遍历，**随深度线性退化** | ✅ O(1) 插入，移动只改一行 | 深度 ≤ 10、写多读少（评论、组织架构） |
| **ltree（物化路径）** | `path ltree`（如 `1.5.42`） | ✅ GiST 索引，`@>` 一次命中，**O(log N)** | ❌ 移动子树要重写整棵 | 读多写少、深树（分类目录、权限树） |
| **闭包表** | 单独表存所有 `(祖先, 后代, 深度)` 对 | ✅ O(1) 单表查询 | ❌ 写放大 O(深度) | 极深 + 频繁子树查询 |

**递归 CTE 写法**（课 6 会系统讲，这里先看形态）：

```sql
WITH RECURSIVE tree AS (
    -- 起点：根评论
    SELECT id, parent_id, body, 1 AS depth
    FROM comments WHERE id = 1
  UNION ALL
    -- 递归：找子节点
    SELECT c.id, c.parent_id, c.body, t.depth + 1
    FROM comments c JOIN tree t ON c.parent_id = t.id
)
SELECT * FROM tree;
```

**ltree 写法**：

```sql
CREATE EXTENSION IF NOT EXISTS ltree;

CREATE TABLE categories (
    id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name TEXT NOT NULL,
    path ltree NOT NULL
);
CREATE INDEX idx_categories_path ON categories USING GIST (path);

-- 查"电子产品"下所有子孙分类（含自己）
SELECT name FROM categories
WHERE path <@ 'electronics';
-- 或：'electronics' @> path

-- 常用操作符
--  @>  是祖先    'electronics' @> 'electronics.laptops'  → true
--  <@  是后代    'electronics.laptops' <@ 'electronics'   → true
--  ~   lquery 正则匹配
```

> 💡 **决策规则**：
> - 深度 ≤ 10、需要频繁插入 / 移动 → **邻接表 + 递归 CTE**（默认选这个）
> - 深度大、查询远多于写入 → **ltree**（PG 专属优势，CYBERTEC 实测 <1ms）
> - 两者都要 → **混合**：`parent_id` 管写，`path` 管读，用触发器维护

#### 多态关联（PG 没有原生支持）

需求：一张 `attachments` 表，既能挂在订单上，又能挂在商品上、评论上。

```sql
-- ❌ 常见错误：PG 不支持这种"指向任一表"的外键
CREATE TABLE attachments (
    id            BIGINT PRIMARY KEY,
    owner_type    TEXT,        -- 'order' / 'product' / 'comment'
    owner_id      BIGINT,      -- 指向哪一行的 id
    url           TEXT
    -- 无法加外键：一列外键只能指向一张表
);
```

**PG 的三种解法**：

**解法 1 · 多张中间表（最规范）**

```sql
CREATE TABLE order_attachments (
    order_id BIGINT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    attachment_id BIGINT NOT NULL REFERENCES attachments(id) ON DELETE CASCADE,
    PRIMARY KEY (order_id, attachment_id)
);
CREATE TABLE product_attachments ( ... );   -- 同理
```
- ✅ 有真外键，引用完整性有保证
- ❌ 每加一种 owner 就多一张表

**解法 2 · 每张 owner 表各存一列外键（可空，加 CHECK 保证恰好一个非空）**

```sql
CREATE TABLE attachments (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id   BIGINT REFERENCES orders(id)   ON DELETE CASCADE,
    product_id BIGINT REFERENCES products(id) ON DELETE CASCADE,
    url TEXT NOT NULL,
    CHECK (num_nonnulls(order_id, product_id) = 1)   -- 恰好一个非空
);
```
- ✅ 一张表搞定，有真外键
- ❌ 加一种 owner 要加一列 + 改 CHECK

**解法 3 · 用 JSONB 存（最灵活，无外键保证）**

```sql
owner JSONB NOT NULL   -- {"type": "order", "id": 9527}
```
- ✅ 随便加类型，不改表
- ❌ **没有外键保证**，应用层自己负责

> 💡 **决策**：能用解法 1/2 就用（有外键 = 有保证）；owner 类型会无限增长时才考虑解法 3。

#### 示例演示：完整三表关系

```sql
-- 查"用户 42 买过哪些商品"（一对多 + 多对多 三层）
SELECT DISTINCT p.id, p.title
FROM orders o
JOIN order_items oi ON oi.order_id = o.id
JOIN products p     ON p.id = oi.product_id
WHERE o.user_id = 42
ORDER BY p.id;

-- 查"每个商品被多少笔订单买过"（多对多的反向统计）
SELECT
    p.title,
    COUNT(DISTINCT oi.order_id) AS order_count,
    SUM(oi.quantity)            AS total_qty
FROM products p
LEFT JOIN order_items oi ON oi.product_id = p.id
GROUP BY p.id, p.title
ORDER BY order_count DESC;
```

#### 常见误区 6 条

| 误区 | 反例 | 正解 |
|---|---|---|
| 用逗号拼接代替一对多 | `order_ids TEXT` | 外键放"多"的那侧 |
| 多对多不拆中间表 | 在 orders 里加 `product_ids` | 拆 `order_items` |
| 中间表忘了唯一约束 | 同一商品重复插入 | `UNIQUE (order_id, product_id)` |
| 自引用忘加索引 | `parent_id` 无索引 | 递归查询会全表扫 |
| 深树硬用递归 CTE | 20 层分类每次递归 | 换 ltree / 闭包表 |
| 多态关联强行加外键 | `owner_type + owner_id` 想加 FK | 用多中间表或多列外键 + CHECK |

#### 一句话记住

> **一对多：外键放"多"侧；多对多：拆中间表带两端外键；自引用：外键指自己，深树换 ltree。**

#### 命令速查卡（4.2）

```sql
-- 一对多
CREATE TABLE child (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    parent_id BIGINT NOT NULL REFERENCES parent(id) ON DELETE RESTRICT
);
CREATE INDEX idx_child_parent ON child (parent_id);   -- 补索引

-- 多对多中间表
CREATE TABLE link (
    a_id BIGINT NOT NULL REFERENCES a(id) ON DELETE CASCADE,
    b_id BIGINT NOT NULL REFERENCES b(id) ON DELETE RESTRICT,
    attr INTEGER,
    PRIMARY KEY (a_id, b_id)
);

-- 自引用（邻接表）
parent_id BIGINT REFERENCES same_table(id) ON DELETE CASCADE

-- 递归 CTE 遍历
WITH RECURSIVE t AS (
    SELECT id, parent_id, 1 AS depth FROM node WHERE id = <root>
  UNION ALL
    SELECT n.id, n.parent_id, t.depth + 1
    FROM node n JOIN t ON n.parent_id = t.id
) SELECT * FROM t;

-- ltree
CREATE EXTENSION ltree;
CREATE INDEX idx_path ON t USING GIST (path);
SELECT * FROM t WHERE path <@ 'root.a';      -- 后代
SELECT * FROM t WHERE 'root.a' @> path;      -- 祖先（等价写法）

-- 多态（多列外键 + CHECK）
CHECK (num_nonnulls(order_id, product_id) = 1)
```

---

### （三）知识点 4.3 · 范式与反范式（决策点）

#### 一句话定义

**范式 = 消除冗余（一格只放一类东西）；反范式 = 故意加冗余换读性能（把常一起用的挂一起）。**

#### 直觉建立

把数据库想成 Excel 表格：

- **1NF（第一范式）**：**一个格子只能放一个值** —— 不能有"数组格"
- **2NF（第二范式）**：**非主键列必须依赖"整个"主键** —— 复合主键时不能只依赖其中一列
- **3NF（第三范式）**：**非主键列不能依赖另一个非主键列** —— 不能有"传递依赖"

#### 三大范式逐个看

**1NF · 列不可再分**

```sql
-- ❌ 违反 1NF：一格存多个值
CREATE TABLE orders (
    id BIGINT PRIMARY KEY,
    product_ids TEXT      -- '1,2,3'
);

-- ✅ 符合 1NF：拆成多行
CREATE TABLE order_items (
    order_id   BIGINT,
    product_id BIGINT,
    PRIMARY KEY (order_id, product_id)
);
```

> 💡 **PG 有个灰色地带**：数组类型（`INTEGER[]`）、JSONB 严格说违反 1NF。**这不是罪**——PG 提供它们就是为了在某些场景用。但你要清楚自己在破坏 1NF，以及代价（无法加外键、无法高效 JOIN）。

**2NF · 依赖整个主键**

```sql
-- ❌ 违反 2NF：product_name 只依赖 product_id，不依赖 order_id
CREATE TABLE order_items (
    order_id     BIGINT,
    product_id   BIGINT,
    product_name TEXT,        -- ← 只跟 product_id 走
    quantity     INTEGER,
    PRIMARY KEY (order_id, product_id)
);

-- ✅ 符合 2NF：product_name 归 products 表
CREATE TABLE products (
    id   BIGINT PRIMARY KEY,
    name TEXT NOT NULL
);
```

**3NF · 不能有传递依赖**

```sql
-- ❌ 违反 3NF：category_name 依赖 category_id，而 category_id 依赖 id
CREATE TABLE products (
    id            BIGINT PRIMARY KEY,
    category_id   BIGINT,
    category_name TEXT      -- 传递依赖：id → category_id → category_name
);

-- ✅ 符合 3NF：拆出 categories 表
CREATE TABLE categories (
    id   BIGINT PRIMARY KEY,
    name TEXT NOT NULL UNIQUE
);
CREATE TABLE products (
    id          BIGINT PRIMARY KEY,
    category_id BIGINT REFERENCES categories(id)
);
```

> 💡 **3NF 是默认目标**。BCNF / 4NF / 5NF 真实业务中极少需要。**先做到 3NF，出现问题再反范式。**

#### 反范式的三大模式

**模式 1 · 缓存聚合值（用触发器维护）**

```sql
-- 需求：用户列表页要显示"每人下了多少单"，每次 COUNT 太慢
-- 反范式：在 users 表冗余一个 order_count

ALTER TABLE users ADD COLUMN order_count INTEGER NOT NULL DEFAULT 0;

CREATE OR REPLACE FUNCTION sync_user_order_count() RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE users SET order_count = order_count + 1 WHERE id = NEW.user_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE users SET order_count = order_count - 1 WHERE id = OLD.user_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_order_count
AFTER INSERT OR DELETE ON orders
FOR EACH ROW EXECUTE FUNCTION sync_user_order_count();
```

- ✅ 读变成 `SELECT order_count FROM users` —— 无需 JOIN、无需 COUNT
- ❌ 写入变慢（每次 INSERT 多一次 UPDATE）
- ❌ 触发器出 bug 就永久不一致（**必须定期校验**：`SELECT user_id, COUNT(*) FROM orders GROUP BY user_id` 对账）

**模式 2 · 快照历史数据（最重要、最少争议）**

```sql
CREATE TABLE order_items (
    id           BIGINT PRIMARY KEY,
    order_id     BIGINT NOT NULL REFERENCES orders(id),
    product_id   BIGINT NOT NULL REFERENCES products(id),
    product_name TEXT NOT NULL,        -- ← 下单那一刻的名字
    unit_price   NUMERIC(10,2) NOT NULL,  -- ← 下单那一刻的价格
    quantity     INTEGER NOT NULL
);
```

**这不是冗余，这是历史事实。**

商品明天改名、后天涨价 —— 你去年那笔订单的明细**必须保持原样**。财务对账、退货、纠纷仲裁都要看"当时成交的是什么"。

> 💡 **判据**：这个字段查询时应该显示**当前值**还是**当时值**？
> - 当时值 → 快照（合理反范式）
> - 当前值 → 别冗余（JOIN 父表）

**模式 3 · 物化视图（课 5 详细讲）**

```sql
CREATE MATERIALIZED VIEW daily_gmv AS
SELECT DATE_TRUNC('day', created_at) AS day,
       SUM(amount) AS gmv,
       COUNT(*)    AS order_cnt
FROM orders WHERE status = 'paid'
GROUP BY 1;

REFRESH MATERIALIZED VIEW CONCURRENTLY daily_gmv;   -- 定时刷新
```

- ✅ 复杂聚合预计算，读极快
- ❌ 数据有延迟（刷新间隔内是旧的）

#### JSONB：规范化与反范式之间的中间地带

PG 的 JSONB 让你**在同一个表里既享受关系型的保证，又保留文档型的灵活**。

**该用 JSONB 的时候**：

```sql
-- ✅ 结构真的不固定：不同商品的属性千差万别
CREATE TABLE products (
    id         BIGINT PRIMARY KEY,
    title      TEXT NOT NULL,
    attributes JSONB NOT NULL DEFAULT '{}'   -- 手机: {"屏幕":"6.7寸","内存":"256G"}
                                             -- 图书: {"作者":"...","ISBN":"..."}
);
CREATE INDEX idx_products_attrs ON products USING GIN (attributes);
```

**不该用 JSONB 的时候**（5 个危险信号）：

| 信号 | 说明 |
|---|---|
| 同一个 JSON 路径被反复查询 | `WHERE data->>'status' = 'x'` 每次全扫 → 该提成真列 |
| 要 JOIN JSON 里的值 | `ON o.data->>'user_id' = u.id::text` → 慢且无法用高效 JOIN 策略 |
| 规划器估算严重偏差 | JSONB 内统计信息缺失 → 估算错 4 倍以上 → 选错执行计划 |
| 建了一堆表达式索引 | 建 4 个表达式索引 = "伪装成 JSON 的规范化表"，不如直接提成列 |
| 该字段需要约束 / 外键 | **JSONB 里没法加 NOT NULL、CHECK、外键** |

> 💡 **存储实测参考**：1000 万行场景下，规范化（4 表 + FK）约 **1.2 GB + 400 MB 索引**；JSONB 单表嵌入约 **8 GB + 1.2 GB GIN** —— **JSONB 存储约 6.7 倍**。（来源：业界公开基准，量级参考）

```sql
-- JSONB 提速：给高频路径建表达式索引
CREATE INDEX idx_orders_user_name ON orders ((data->>'user_name'));
```

#### 🎯 决策点：该不该反范式？

这是本课唯一的**非唯一答案题**。用下面这张表做判断：

| 场景 | 反范式？ | 理由 |
|---|---|---|
| 源数据**频繁变动**（如库存数、余额） | ❌ **不** | 副本同步成本高，迟早不一致 |
| 表**写入极频繁** | ❌ **不** | 每次写都要维护冗余，写放大 |
| 表很小（< 1 万行） | ❌ **不** | JOIN 本来就快，没必要 |
| **历史快照**（下单时的价格/名） | ✅ **要** | 这是事实，不是冗余 |
| 聚合值被**极高频读**（首页计数） | ✅ **要** | 配触发器 + 定期对账 |
| 报表查询复杂且**允许延迟** | ✅ **要** | 物化视图 |
| 结构**真的不固定**的扩展属性 | ✅ **要** | JSONB |

**决策纪律（背下来）**：

> **默认规范化到 3NF。只有在你实测到了"规范化导致的性能问题"之后，才针对那个具体问题反范式。**
>
> 不要"预防性反范式"——你猜的瓶颈 90% 不在那儿。

#### 常见误区 6 条

| 误区 | 反例 | 正解 |
|---|---|---|
| 以为范式越高越好 | 硬拆到 BCNF | 3NF 足够，BCNF+ 极少需要 |
| 预防性反范式 | "JOIN 可能慢"先加冗余 | 先规范化，**实测**后再反 |
| 把"历史快照"当冗余删掉 | order_items 只存 product_id | 价格和名字**必须**快照 |
| 反范式不同步 | 加了 order_count 没写触发器 | 冗余字段必须有维护机制 + 对账 |
| 什么都塞 JSONB | 订单核心字段存 JSONB | 核心业务数据用真列（约束 / 外键 / 类型安全） |
| 建一堆 JSONB 表达式索引 | 4 个路径各建一个索引 | 说明该提成真列了 |

#### 一句话记住

> **默认 3NF；历史值快照、高频聚合、灵活扩展属性三类可以反范式；JSONB 是中间地带但别当垃圾桶。**

#### 命令速查卡（4.3）

```sql
-- 缓存聚合（触发器）
ALTER TABLE users ADD COLUMN order_count INTEGER NOT NULL DEFAULT 0;
CREATE TRIGGER trg AFTER INSERT OR DELETE ON orders
  FOR EACH ROW EXECUTE FUNCTION sync_fn();

-- 快照（建表时就定）
product_name TEXT NOT NULL,  unit_price NUMERIC(10,2) NOT NULL

-- 物化视图
CREATE MATERIALIZED VIEW mv AS SELECT ...;
REFRESH MATERIALIZED VIEW CONCURRENTLY mv;

-- JSONB
attributes JSONB NOT NULL DEFAULT '{}'
CREATE INDEX idx_attrs ON t USING GIN (attributes);
CREATE INDEX idx_path  ON t ((data->>'key'));      -- 表达式索引
SELECT * FROM t WHERE attributes @> '{"color":"red"}';   -- 包含
SELECT * FROM t WHERE attributes ? 'color';              -- 键存在

-- 校验冗余是否一致（定期对账！）
SELECT u.id, u.order_count, COUNT(o.id) AS real_count
FROM users u LEFT JOIN orders o ON o.user_id = u.id
GROUP BY u.id, u.order_count
HAVING u.order_count <> COUNT(o.id);
```

---

## 第四幕 · 实操验证

### 实验环境

延续前三课：`localhost:5432` 上 `postgres:17` 容器，`order_service` 库 `finance` schema。本课要把**阶段 1 的单表 orders** 升级成**阶段 2 的四表关系**。

```sql
-- 若容器未启动
docker start pg17
docker exec -it pg17 psql -U postgres -d order_service
SET search_path TO finance, public;
```

### 实验 1 · 建四表关系骨架

```sql
-- 1. 分类（自引用：树形）
CREATE TABLE IF NOT EXISTS categories (
    id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name      TEXT NOT NULL,
    parent_id BIGINT REFERENCES categories(id) ON DELETE CASCADE
);
CREATE INDEX idx_categories_parent ON categories (parent_id);

-- 2. 用户
CREATE TABLE IF NOT EXISTS users (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email      TEXT NOT NULL UNIQUE,
    name       TEXT NOT NULL,
    order_count INTEGER NOT NULL DEFAULT 0,   -- 反范式：缓存聚合（见实验 4）
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3. 商品
CREATE TABLE IF NOT EXISTS products (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    title       TEXT NOT NULL,
    price       NUMERIC(10,2) NOT NULL CHECK (price >= 0),
    category_id BIGINT REFERENCES categories(id) ON DELETE SET NULL,
    attributes  JSONB NOT NULL DEFAULT '{}'    -- 反范式：灵活扩展（见实验 5）
);
CREATE INDEX idx_products_category ON products (category_id);

-- 4. 订单（users 一对多）
CREATE TABLE IF NOT EXISTS orders (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_no   TEXT NOT NULL UNIQUE,
    user_id    BIGINT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    status     TEXT NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_orders_user_id ON orders (user_id);        -- ⚠️ 引用侧索引

-- 5. 订单明细（多对多中间表 + 快照）
CREATE TABLE IF NOT EXISTS order_items (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id     BIGINT NOT NULL REFERENCES orders(id)   ON DELETE CASCADE,
    product_id   BIGINT NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    product_name TEXT NOT NULL,           -- 快照
    unit_price   NUMERIC(10,2) NOT NULL,  -- 快照
    quantity     INTEGER NOT NULL CHECK (quantity > 0),
    UNIQUE (order_id, product_id)
);
CREATE INDEX idx_order_items_order   ON order_items (order_id);
CREATE INDEX idx_order_items_product ON order_items (product_id);
```

### 实验 2 · 验证外键的 5 种动作

```sql
-- 造数据
INSERT INTO users (email, name) VALUES
    ('a@x.com','Alice'), ('b@x.com','Bob');
INSERT INTO products (title, price) VALUES
    ('键盘', 299.00), ('鼠标', 99.00), ('显示器', 1299.00);
INSERT INTO orders (order_no, user_id) VALUES ('ORD001', 1);
INSERT INTO order_items (order_id, product_id, product_name, unit_price, quantity)
VALUES (1, 1, '键盘', 299.00, 2), (1, 2, '鼠标', 99.00, 1);

-- ① RESTRICT：用户被订单引用 → 删不掉
DELETE FROM users WHERE id = 1;
-- ERROR: update or delete on table "users" violates foreign key constraint
--        "orders_user_id_fkey" on table "orders"
-- DETAIL: Key (id)=(1) is still referenced from table "orders".

-- ② CASCADE：删订单 → 明细连带删
SELECT COUNT(*) FROM order_items WHERE order_id = 1;      -- 2
DELETE FROM orders WHERE id = 1;
SELECT COUNT(*) FROM order_items WHERE order_id = 1;      -- 0 ✅ 被级联删除

-- ③ SET NULL：删分类 → 商品的 category_id 置 NULL
INSERT INTO categories (name) VALUES ('外设');
UPDATE products SET category_id = 1 WHERE id = 1;
DELETE FROM categories WHERE id = 1;
SELECT category_id FROM products WHERE id = 1;            -- NULL ✅

-- ④ 引用完整性：插不存在的用户 → 拒绝
INSERT INTO orders (order_no, user_id) VALUES ('ORD999', 9999);
-- ERROR: insert or update on table "orders" violates foreign key constraint
```

### 实验 3 · 验证"外键不自动建索引"

```sql
-- 看现在有哪些索引（注意：orders_user_id_fkey 相关只有 PK 的索引）
SELECT tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'finance' AND tablename IN ('orders','order_items')
ORDER BY tablename, indexname;

-- 你会看到 orders_pkey（PK 自动建）、orders_order_no_key（UNIQUE 自动建）
-- 以及我们手动建的 idx_orders_user_id
-- 但：如果没有手动建，user_id 外键列上不会有任何索引

-- 实验：删掉索引看父表删除变成 Seq Scan
DROP INDEX idx_order_items_order_id;
EXPLAIN (ANALYZE) DELETE FROM orders WHERE id = 2;
-- 计划里出现：Seq Scan on order_items（全表扫子表确认引用）

CREATE INDEX idx_order_items_order_id ON order_items (order_id);
EXPLAIN (ANALYZE) DELETE FROM orders WHERE id = 3;
-- 计划里出现：Index Scan using idx_order_items_order_id  ✅
```

### 实验 4 · 反范式：触发器维护 order_count

```sql
-- 建同步函数 + 触发器
CREATE OR REPLACE FUNCTION finance.sync_user_order_count() RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE finance.users SET order_count = order_count + 1 WHERE id = NEW.user_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE finance.users SET order_count = order_count - 1 WHERE id = OLD.user_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_order_count
AFTER INSERT OR DELETE ON finance.orders
FOR EACH ROW EXECUTE FUNCTION finance.sync_user_order_count();

-- 验证
SELECT id, name, order_count FROM users ORDER BY id;   -- Alice: 0
INSERT INTO orders (order_no, user_id) VALUES ('ORD100', 1), ('ORD101', 1);
SELECT id, name, order_count FROM users WHERE id = 1;  -- Alice: 2 ✅

-- 对账（冗余字段必须定期校验！）
SELECT u.id, u.order_count, COUNT(o.id) AS real_count
FROM users u LEFT JOIN orders o ON o.user_id = u.id
GROUP BY u.id, u.order_count
HAVING u.order_count <> COUNT(o.id);   -- 应返回 0 行
```

### 实验 5 · JSONB：灵活扩展属性

```sql
-- 不同商品有不同属性（结构不固定 → JSONB 合理）
UPDATE products SET attributes = '{"接口":"Type-C","轴体":"红轴"}' WHERE title = '键盘';
UPDATE products SET attributes = '{"DPI":"16000","无线":true}'     WHERE title = '鼠标';

-- GIN 索引加速包含查询
CREATE INDEX idx_products_attrs ON finance.products USING GIN (attributes);

SELECT title FROM products WHERE attributes @> '{"轴体":"红轴"}';
--  键盘

SELECT title FROM products WHERE attributes ? 'DPI';
--  鼠标

-- ⚠️ 危险信号演示：->> 提取后比较无法用 GIN
EXPLAIN SELECT title FROM products WHERE attributes->>'轴体' = '红轴';
-- Seq Scan（GIN 帮不上 ->> 文本比较）

-- 解法：给高频路径建表达式索引
CREATE INDEX idx_products_axis ON finance.products ((attributes->>'轴体'));
EXPLAIN SELECT title FROM products WHERE attributes->>'轴体' = '红轴';
-- Index Scan ✅
```

### 实验 6 · 自引用树：递归 CTE vs ltree

```sql
-- 造一棵分类树
INSERT INTO categories (id, name, parent_id) VALUES
    (10, '电子产品', NULL),
    (11, '电脑外设', 10),
    (12, '键盘', 11),
    (13, '鼠标', 11);

-- ① 邻接表 + 递归 CTE：查"电子产品"下所有子孙
WITH RECURSIVE tree AS (
    SELECT id, name, parent_id, 1 AS depth
    FROM categories WHERE id = 10
  UNION ALL
    SELECT c.id, c.name, c.parent_id, t.depth + 1
    FROM categories c JOIN tree t ON c.parent_id = t.id
)
SELECT id, name, depth FROM tree ORDER BY depth, id;

-- ② ltree：同一查询用物化路径
CREATE EXTENSION IF NOT EXISTS ltree;

ALTER TABLE categories ADD COLUMN path ltree;
UPDATE categories SET path = 'electronics'                    WHERE id = 10;
UPDATE categories SET path = 'electronics.peripherals'        WHERE id = 11;
UPDATE categories SET path = 'electronics.peripherals.kbd'    WHERE id = 12;
UPDATE categories SET path = 'electronics.peripherals.mouse'  WHERE id = 13;
CREATE INDEX idx_categories_path ON finance.categories USING GIST (path);

SELECT id, name FROM categories WHERE path <@ 'electronics.peripherals';
--  11 电脑外设 / 12 键盘 / 13 鼠标  ✅ 一次索引命中，无递归
```

---

## 第五幕 · 体系收束

### 本课小结（3 个知识点的全景）

```
本课 3 个知识点 = 从"一张表"到"一群关系"：

  4.1 主键 / 外键 / 唯一约束
       代理键（BIGINT IDENTITY / UUIDv7）vs 业务键（降为 UNIQUE）
       外键 5 种动作：NO ACTION(可 defer) / RESTRICT / CASCADE / SET NULL / SET DEFAULT
       ⚠️ 外键不自动建索引 —— 引用侧必须手动 CREATE INDEX

  4.2 一对多 / 多对多 / 自引用
       一对多：外键放"多"的那侧
       多对多：拆中间表（中间表常是业务实体，可带属性）
       自引用：邻接表 + 递归 CTE（默认）/ ltree（深树读多）/ 闭包表（极深）
       多态：PG 无原生，用多中间表 或 多列外键 + CHECK

  4.3 范式与反范式（决策点）
       默认 3NF（1NF 一格一值 / 2NF 依赖整个主键 / 3NF 无传递依赖）
       三类合理反范式：历史快照 / 高频聚合（触发器）/ 灵活扩展（JSONB）
       纪律：先规范化，实测到瓶颈再针对性反范式
```

### 阶段 2 四课的整合视图

```
┌─────────── 阶段 2 · 数据建模与 SQL 进阶 ───────────┐
│                                                     │
│  课 4 关系建模    ← 你刚学完（阶段 2 开篇）          │
│   4.1 主键 / 外键 / 唯一约束                        │
│   4.2 一对多 / 多对多 / 自引用                      │
│   4.3 范式与反范式（决策点）                        │
│            ↓  设计好了，怎么复用？                   │
│  课 5 视图与函数                                     │
│   5.1 普通视图 / 可更新视图 / 物化视图               │
│   5.2 函数与存储过程（plpgsql 入门）                 │
│   5.3 触发器基础                                    │
│            ↓  逻辑复杂了，怎么组织？                 │
│  课 6 CTE 与子查询                                   │
│   6.1 WITH 子句 · 6.2 递归 CTE · 6.3 相关子查询     │
│            ↓  要做分组内排名？                       │
│  课 7 窗口函数                                       │
│   7.1 OVER / PARTITION BY · 7.2 排名 · 7.3 滑动     │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### 决策心法（学完课 4 应能回答的 6 个判断）

| 问题 | 答案 |
|---|---|
| 主键用什么？ | 单机 → **BIGINT IDENTITY**；多写 / 前端生成 → **UUIDv7**；业务号降为 UNIQUE |
| 外键建完还要做什么？ | **在引用侧手动建索引**（PG 不自动建） |
| ON DELETE 选哪个？ | 明细类（离开父表无意义）→ CASCADE；独立实体 → RESTRICT；可选关系 → SET NULL |
| NO ACTION 和 RESTRICT 差在哪？ | NO ACTION **可 defer**（事务内临时打破再补）；RESTRICT **不可** |
| 该不该反范式？ | **默认不**。三类例外：历史快照 / 高频聚合 / 结构不固定 |
| 深树怎么存？ | 深度 ≤ 10 写多 → 邻接表 + 递归 CTE；读多树深 → **ltree + GiST** |

### 命令速查卡（综合）

```sql
-- 建表骨架（阶段 2 形态）
CREATE TABLE t (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ...
    other_id BIGINT NOT NULL REFERENCES other(id) ON DELETE RESTRICT
);
CREATE INDEX idx_t_other ON t (other_id);      -- ⚠️ 引用侧索引

-- 关系三件套
一对多   → 外键放"多"侧
多对多   → 中间表 + UNIQUE(两端)
自引用   → parent_id REFERENCES 自己

-- 反范式三件套
快照     → 建表时加 product_name / unit_price 列
聚合     → ALTER TABLE ADD COLUMN + 触发器 + 定期对账
灵活扩展 → attributes JSONB + GIN 索引

-- 校验一致性（冗余字段必做）
SELECT ... HAVING cached_count <> COUNT(*);
```

### 事实速查（核查于 2026-09-06）

| 事实 | 当前值 | 来源 |
|---|---|---|
| 外键是否自动建索引 | **否**。被引用侧（PK / UNIQUE）PG 自动建 B-tree；**引用侧不建**。PG 17 与历史版本一致，官方文档原文："the declaration of a foreign key constraint does not automatically create an index on the referencing columns" | postgresql.org/docs/17/ddl-constraints |
| FK 必须引用什么 | 必须引用 **PRIMARY KEY / UNIQUE 约束 / 非部分唯一索引** 的列 | postgresql.org/docs/17/ddl-constraints |
| `ON DELETE` 5 种动作 | `NO ACTION`（默认，**允许 defer**）/ `RESTRICT`（**不允许 defer**）/ `CASCADE` / `SET NULL` / `SET DEFAULT` | postgresql.org/docs/17/ddl-constraints |
| `SET NULL` / `SET DEFAULT` 列列表 | `ON DELETE` 时**可**指定列列表（`SET NULL (col)`）；`ON UPDATE` 时**不可** | postgresql.org/docs/17/ddl-constraints |
| CASCADE 适用判据 | 官方文档：子表是父表的**组成部分**、不能独立存在时 CASCADE 合适；独立实体用 RESTRICT / NO ACTION | postgresql.org/docs/17/ddl-constraints |
| UNIQUE 与 NULL | PG 默认 `NULLS DISTINCT`（多个 NULL 不冲突）；`UNIQUE NULLS NOT DISTINCT` 可让 NULL 也算重复（**PG 15+**） | postgresql.org/docs/current/ddl-constraints |
| PG 17 UUIDv7 | PG 17 新增 `pg_uuidv7` 扩展，提供有序 UUID（避免 v4 随机插入毁 B-tree） | PG 17 release notes |
| ltree 索引与性能 | `CREATE EXTENSION ltree` + `USING GIST (path)`；祖先 / 后代查询 `@>` / `<@` 走索引，CYBERTEC 实测 < 1ms；ltree 最多支持 **65535 个 label** | postgresql.org/docs/current/ltree |
| 递归 CTE 退化 | 深度大、子树宽时**线性退化**；深度 > 20 且频繁子树查询应考虑 ltree 或**闭包表** | 业界基准 / CYBERTEC |
| 3NF 是否够用 | **3NF 是默认目标**；BCNF / 4NF / 5NF 真实业务极少需要 | 数据库设计通行实践 |
| JSONB vs 规范化存储 | 1000 万行量级：规范化约 1.2 GB + 400 MB 索引；JSONB 单表嵌入约 8 GB + 1.2 GB GIN（**约 6.7 倍**） | 业界公开基准（量级参考） |

---

## 🧭 课程导航

> **本课在阶段 2 的位置**：阶段 2 四课中的**开篇课**——从阶段 1 的"一张表"跨入"一群关系"。
>
> **阶段 2 四课**（学完课 7 阶段 2 闭环）：
>
> - 课 4 关系建模 ← **你在这里（阶段 2 开篇）**
> - 课 5 视图与函数（[下一课 →](lesson-05-视图与函数.md)）
> - 课 6 CTE 与子查询
> - 课 7 窗口函数
>
> **整课任务完成标记**：4.1 + 4.2 + 4.3 三知识点均已交付 ✅（P0=0，4 项事实核查 PASS：外键索引 / ON DELETE 5 动作 / 3NF 与反范式 / 树模型，见事实速查表）。

- 上一课：[课 3 查询基础（WHERE / JOIN / 聚合）](../1-SQL与关系基础/lessons/lesson-03-查询基础.md)（**跨阶段 ← 阶段 1 收官课**）
- 下一课：[课 5 视图与函数（普通视图 / 物化视图 / 存储过程 / 触发器）](lesson-05-视图与函数.md)（同阶段）
- 返回目录：[`02-课程目录.md`](../../02-课程目录.md)
- 上一阶 / 下一阶：**阶段 1 · SQL 与关系基础已闭环 ✅**（9 / 9 知识点）；当前在**阶段 2 · 数据建模与 SQL 进阶**（1 / 12 知识点）

> 🚀 **阶段 2 开篇 · 从"一张表"到"一群关系"**：
>
> 学完课 4 后你新增的能力：
>
> - ✅ 为业务域选对主键（BIGINT IDENTITY / UUIDv7 / 业务键降 UNIQUE）
> - ✅ 写外键并选对 `ON DELETE` 动作（5 种，知道 NO ACTION 与 RESTRICT 的 defer 差异）
> - ✅ **记得给外键引用侧补索引**（PG 最大的建模陷阱）
> - ✅ 把一对多 / 多对多 / 自引用翻译成正确的表结构
> - ✅ 在范式与反范式之间做有理由的决策（默认 3NF，三类例外）
> - ✅ 用 JSONB 处理结构不固定的扩展属性，并知道 5 个危险信号
>
> **下一课预告 · 课 5 视图与函数**：
>
> - 5.1 普通视图 / 可更新视图 / **物化视图**（本课实验用过的 `REFRESH MATERIALIZED VIEW` 会系统讲）
> - 5.2 函数与存储过程（**plpgsql 入门** ——本课实验 4 的触发器函数会补全语法讲解）
> - 5.3 触发器基础（本课的 `sync_user_order_count` 会讲透 `TG_OP` / `NEW` / `OLD`）
