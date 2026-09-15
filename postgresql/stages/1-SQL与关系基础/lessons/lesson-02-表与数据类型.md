# 课 2 · 表与数据类型

> 📍 故事中的位置：主角（一条订单）终于出生了——但它得有名字（数据类型）、有身份证号（主键）、有约束（不能空、价格不能负）

## 本课目标

学完本课后，你能：

1. 区分数值 / 字符串 / 时间 / 布尔 / JSON 等常用类型的**适用边界**
2. 用 `CREATE TABLE` 写出带主键、NOT NULL、UNIQUE、CHECK、DEFAULT 的合规表
3. 完成基础的 CRUD（INSERT / SELECT / UPDATE / DELETE）

## 知识点清单

| 知识点 | 关键点 |
|---|---|
| **2.1 常用数据类型** | · 数值（`integer` / `bigint` / `numeric` / `double precision` 的取舍） · 字符串（`varchar(n)` vs `text` vs `char(n)`，PG 推荐一律 text） · 时间（`timestamp` / `timestamptz` / `date` / `time`，带时区的差别） · 布尔 / 枚举 / 数组 / JSON / JSONB · NULL 的"非值"语义 |
| **2.2 建表语法与约束** | · `CREATE TABLE` 完整结构 · 5 大约束：PRIMARY KEY / NOT NULL / UNIQUE / CHECK / DEFAULT · 表与列的 COMMENT · `SERIAL` 与 `GENERATED AS IDENTITY` 两种自增主键的取舍 |
| **2.3 CRUD 基础** | · `INSERT` 单行 / 多行 / 从 SELECT 插入 · `SELECT` 基础（`SELECT 列 FROM 表 WHERE 条件`） · `UPDATE` 与 `DELETE`（注意 WHERE 条件，可加 `RETURNING`） · `TRUNCATE` 与 DELETE 的本质区别 |

## 故事主线中的情节定位

订单出生这一节——它选择住在哪儿（数据类型）、叫什么（约束）、什么时候搬走（DELETE）。读者通过主角出生学会"为一个实体设计表的入门姿势"。

## 正文

## 📌 知识点导航

本课首批（首批 = 课 2 全部 3 个知识点，是阶段 1 第二课，闭环前最后一个有骨架待填的课）覆盖：

| 节 | 知识点 | 核心问题 |
|---|---|---|
| 第三幕（一） | 2.1 常用数据类型 | 不同类型在"订单"这一实体上各自负责什么 |
| 第三幕（二） | 2.2 建表语法与约束 | 怎么把数据类型拼成一张合规的 `orders` 表 |
| 第三幕（三） | 2.3 CRUD 基础 | 表建好了，怎么插入 / 查 / 改 / 删一条订单 |

---

## 第一幕 · 起源与场景引入

### 一个真实的工作场景

上一课你把 PG 17 跑起来了，在 `order_service` 库里建了 `finance` / `sales` 两个 schema。现在 PM 说：

> "把订单表建起来吧，字段先这么定："
>
> | 字段 | 类型 | 备注 |
> |---|---|---|
> | id | int | 主键，自增 |
> | order_no | varchar(32) | 业务订单号，唯一 |
> | user_id | int | 用户 id |
> | amount | decimal(10,2) | 金额（不能负） |
> | status | tinyint | 状态（1=待付 / 2=已付 / 3=取消） |
> | created_at | datetime | 下单时间 |
> | paid_at | datetime | 支付时间（可空） |

你盯着这张表，立刻撞上了三个问题：

1. **`tinyint` PG 没有** —— MySQL 的类型在 PG 不能照搬
2. **`datetime` 也是 MySQL 的写法** —— PG 用 `timestamp` / `timestamptz`
3. **`decimal` 与 `numeric` 等价**，但 PM 写 `decimal` 你更熟，是直接用还是换？

更深的：金额用 `numeric` 听说是对的，但很多人用 `float`——**为什么"金额必须 numeric 而不是 float"是常识？**

订单还没出生，住址类型还没选对，后面所有的金额计算都是错的——**今天这课就是把"建一张规范表"这件事讲透**。

### 一个关于金额的本质故事

> 业界一个"想当然就出事"的案例：1999 年火星气候探测者号（Mars Climate Orbiter）坠毁——**地面团队用英制单位（磅力），飞行器软件用 SI 单位（牛顿）**。数值看起来都"对"，单位语义错了就坠毁。金额场景是一样的：你存一个 0.1 在 float 里，再加 0.2，可能拿到 0.30000000000000004。**这就是为什么要用 numeric 而不是 float**。

这件事的教训同样适用于 PG：错一个类型，后续所有查询 / 报表 / 财务对账**全部错**。

---

## 第二幕 · 认知冲突

光有"建表"这个动作，**实际落地有 4 类隐藏陷阱**：

**陷阱一：MySQL 习惯直接照抄**

```sql
-- MySQL 写法（PG 不支持）
CREATE TABLE orders (
    id INT AUTO_INCREMENT PRIMARY KEY,
    status TINYINT DEFAULT 1,
    created_at DATETIME DEFAULT NOW()
);
```

**陷阱二：money 想用 float**

```sql
amount FLOAT DEFAULT 0  -- ❌ 浮点误差，月结账对不齐
amount NUMERIC(10, 2)   -- ✅ 任意精度，无误差
```

**陷阱三：业务订单号想用 int**

```sql
order_no BIGINT  -- ❌ 用户订单号多半是字符串（前缀+日期+序号），强转 int 丢信息
order_no TEXT    -- ✅ 推荐 text 收业务号
```

**陷阱四：时间想统一用 timestamp**

```sql
created_at TIMESTAMP       -- ❌ 不带时区，跨时区会乱
created_at TIMESTAMPTZ     -- ✅ 推荐带时区
```

这 4 类陷阱，今天这课都会给你答案。**先把"类型与约束"这件事彻底搞清，再谈后面的查询优化**。

---

## 第三幕 · 层层揭示

### 第三幕（一）· 知识点 2.1：常用数据类型

#### 一句话定义

> PG 的类型分 **数值 / 字符串 / 时间 / 布尔 / 枚举 / 数组 / JSON / 特殊** 八大类；订单字段按"语义匹配"挑类型，**没有普适类型**。

#### 直觉建立

把数据类型想象成"装数据的容器"——选错容器，事后再改成本很高（**ALTER TABLE 大表很慢，要重写整个表**）。所以**建表时类型就选对**。

PG 类型体系（按"主角订单"的视角）：

| 大类 | 主角订单用到的 | 关键取舍 |
|---|---|---|
| **数值** | `INTEGER` / `BIGINT` / `NUMERIC` | 金额必须 `NUMERIC` 任意精度；不用 `FLOAT` |
| **字符串** | `TEXT` | PG 推荐 `TEXT`（不限长、性能等同比 `varchar(N)`） |
| **时间** | `TIMESTAMPTZ` | 推荐带时区；`TIMESTAMP` 不带时区在跨时区容易出错 |
| **布尔** | `BOOLEAN` | `TRUE` / `FALSE` / `NULL` 三态 |
| **枚举** | `status` 用 `TEXT` + `CHECK`，或 `CREATE TYPE ... AS ENUM` | 小集合用枚举；变化快用 `TEXT` + `CHECK` |
| **数组** | `tags TEXT[]` | 一个字段存多个值；阶段 2 课 5 会详讲 |
| **JSON / JSONB** | `extra JSONB` | 半结构化字段；阶段 2 课 6 详讲 |
| **特殊** | `UUID`（PG 13+ 内置生成函数） | 分布式主键；现在可选 PG 17 新增的 `pg_uuidv7` |

#### 类比边界（哪里不灵）

- ❌ **MySQL 习惯照抄**：`TINYINT` / `DATETIME` / `AUTO_INCREMENT` 都不是 PG 的写法
- ❌ **用 `CHAR(N)` 模拟"短定长"**：PG 的 `CHAR(N)` 用空格 padding，**对 LIKE / 比较都有反直觉副作用**——多数情况下是错误选择
- ❌ **金额用 `FLOAT` / `DOUBLE PRECISION`**：浮点的二进制表示无法精确表达 0.1 这类十进制小数

#### 核心原理 · 八大类型族（PG 17 全景）

**1. 数值（3 种 + 1 种特殊）**

```mermaid
graph LR
    N[Numeric] --> I1[SMALLINT<br/>2 bytes]
    N --> I2[INTEGER<br/>4 bytes · ±2.1e9]
    N --> I3[BIGINT<br/>8 bytes · ±9.2e18]
    N --> N1[NUMERIC p,s<br/>任意精度 · 推荐金额]
    N --> D[DOUBLE PRECISION<br/>双精度浮点 · 不用]
```

| 类型 | 字节 | 取值 | 适用场景 |
|---|---|---|---|
| `INTEGER` | 4 | -2.1e9 ~ 2.1e9 | 主键 / 一般计数 |
| `BIGINT` | 8 | -9.2e18 ~ 9.2e18 | 数量级大的主键（如雪花 ID） |
| `NUMERIC(p, s)` | 变长 | 任意精度（p 总位数，s 小数位） | **金额、单价**——任意精度无误差 |
| `DOUBLE PRECISION` | 8 | IEEE 754 双精度 | 科学计算，**生产金额禁用** |
| `SERIAL` / `BIGSERIAL` | 4 / 8 | 同 INT/BIGINT | legacy 主键自增（PG 10+ 起推荐 IDENTITY） |

> **金额必须 `NUMERIC`**：`NUMERIC(10, 2)` 表示最多 10 位数字，其中 2 位小数（即最大 99999999.99）。**没有浮点误差**，财务报表对账零误差。

**2. 字符串（PG 推荐 `TEXT`）**

| 类型 | 存储 | 性能 | 推荐 |
|---|---|---|---|
| `TEXT` | 变长 | 最快 | **PG 推荐默认** |
| `VARCHAR(N)` | 变长 | 与 TEXT 几乎一致（仅多一长度检查） | 业务强制长度上限时用 |
| `CHAR(N)` | 定长，padding 空格 | 实际**最慢**（额外存储 padding + 比较反直觉） | **几乎永远是错误选择** |

> **核对** PG 官方文档："There is no performance difference among these three types, apart from increased storage space when using the blank-padded type, and a few extra CPU cycles to check the length when storing into a length-limited column."
>
> （核查于 2026-09-06，PG 14~17 均同）

**3. 时间（带时区 vs 不带时区）**

| 类型 | 含义 | 推荐 |
|---|---|---|
| `DATE` | 只存日期 | 生日 / 入职日 |
| `TIME [WITHOUT TIME ZONE]` | 只存时分秒 | 不推荐（少用） |
| `TIMESTAMP` (abbreviation `TIMESTAMP WITHOUT TIME ZONE`) | 不带时区时间戳 | **生产禁用** |
| `TIMESTAMPTZ` (abbreviation `TIMESTAMP WITH TIME ZONE`) | 带时区时间戳（内部存 UTC） | **生产推荐** |

```sql
-- PG 17 中：
CREATE TABLE t (
    a TIMESTAMP,        -- ❌ 不带时区
    b TIMESTAMPTZ       -- ✅ 带时区（内部存 UTC，显示转换到当前时区）
);
INSERT INTO t VALUES (NOW(), NOW());
SET TIME ZONE 'Asia/Shanghai';  -- 会话级时区切换，TIMESTAMPTZ 显示会变
SET TIME ZONE 'UTC';           -- 切到 UTC，显示又变（数据不变）
-- TIMESTAMP 不会随 SET 时区变 → 跨时区协作混乱
```

**4. 布尔 / 5. 枚举 / 6. 数组 / 7. JSON / 8. 特殊**：本次仅给入口，阶段 2 详讲。

```sql
-- 布尔
is_paid BOOLEAN DEFAULT FALSE

-- 枚举
CREATE TYPE order_status AS ENUM ('pending', 'paid', 'cancelled');
status order_status DEFAULT 'pending'

-- 数组
tags TEXT[] DEFAULT '{}'

-- JSON / JSONB（推荐 JSONB：二进制 + 索引友好）
extra JSONB DEFAULT '{}'::JSONB

-- UUID（PG 13+ 内置生成；PG 17 新增 pg_uuidv7 用于分布式有序 UUID）
id UUID PRIMARY KEY DEFAULT gen_random_uuid()
```

#### 示例演示 · 主角订单各字段挑类型

```sql
-- 这是一张"挑类型后"的初版设计（先看类型选择，2.2 加约束）
CREATE TABLE public.orders (
    id           BIGINT,           -- 主键，2.2 加 GENERATED ALWAYS AS IDENTITY
    order_no     TEXT,             -- 业务订单号（前缀+日期+序号）
    user_id      INTEGER,          -- 用户 id
    amount       NUMERIC(10, 2),   -- 金额 — 任意精度，无浮点误差
    status       TEXT,             -- 状态 — 2.2 用 CHECK 约束 3 个值
    is_paid      BOOLEAN DEFAULT FALSE,
    created_at   TIMESTAMPTZ DEFAULT now(),  -- 下单时间（带时区）
    paid_at      TIMESTAMPTZ,                  -- 支付时间（可空）
    note         TEXT,             -- 备注（可空）
    tags         TEXT[] DEFAULT '{}',         -- 标签数组
    extra        JSONB DEFAULT '{}'::JSONB    -- 半结构化扩展字段
);
```

#### 常见误区

| 误区 | 真相 |
|---|---|
| ❌ "金额用 `FLOAT` 就行，性能好" | 浮点存 0.1 不精确，对账必然错。**所有金额 / 财务字段必须 `NUMERIC`** |
| ❌ "用 `VARCHAR(255)` 跟 MySQL 一样" | 在 PG 中"255"是任意业务上限；PG 推荐默认 `TEXT`，要上限用 `VARCHAR(N)` + `CHECK` |
| ❌ "`DATETIME` 与 `TIMESTAMP` 一样" | PG 没 `DATETIME`，MySQL 才有；PG 用 `TIMESTAMP`（不带时区） / `TIMESTAMPTZ`（带） |
| ❌ "`TIMESTAMP` 与 `TIMESTAMPTZ` 等价" | 等价**完全错**：跨时区协作时 TIMESTAMP 会导致"同一行在两个时区看着不一样"；TIMESTAMPTZ 内部存 UTC、显示切换 |
| ❌ "`CHAR(N)` 更快" | PG 文档明确：CHAR(N) **不比 VARCHAR(N) 快**，反而因 padding 浪费空间 |
| ❌ "`TINYINT` 也行，省字节" | PG 无 `TINYINT`。要小整数用 `SMALLINT` |
| ❌ "`NULL` 等于空字符串" | `NULL` 是"无值"语义，三值逻辑里 `NULL = 'abc'` 是 `NULL`（不是 FALSE） |

#### 一句话记住

> 金额 → NUMERIC；字符串 → TEXT；时间 → TIMESTAMPTZ；状态 → TEXT + CHECK 或 ENUM；扩展字段 → JSONB。

📚 **官方文档**：

- 数值类型：[Numeric Types](https://www.postgresql.org/docs/current/datatype-numeric.html)
- 字符类型：[Character Types](https://www.postgresql.org/docs/current/datatype-character.html)（"no performance difference" 一句即来源）
- 时间类型：[Date/Time Types](https://www.postgresql.org/docs/current/datatype-datetime.html)
- JSON 类型：[JSON Types](https://www.postgresql.org/docs/current/datatype-json.html)

---

### 第三幕（二）· 知识点 2.2：建表语法与约束

#### 一句话定义

> `CREATE TABLE` 由 **列定义 + 表级约束**组成；PG 用 5 大约束（`PRIMARY KEY` / `NOT NULL` / `UNIQUE` / `CHECK` / `DEFAULT`）+ 两种自增方式（`SERIAL` legacy / `GENERATED ALWAYS AS IDENTITY` 推荐）来给数据上"规矩"。

#### 直觉建立

`CREATE TABLE` 就像写一份"合同"：

```
表 = 一份对数据的合同

合同条款（约束）:
  PRIMARY KEY   : 主键 — 每一行的唯一身份证号
  NOT NULL      : 非空 — 这一格不能不填
  UNIQUE        : 唯一 — 这一格不能跟别的行撞
  CHECK         : 检查 — 这一格的值必须满足某条件
  DEFAULT       : 默认 — 不填就用这个值

自增（IDENTITY / SERIAL）:
  主键最常见是自动递增 — 系统帮忙生成身份号
```

PG 的 `CREATE TABLE` 结构：

```sql
CREATE TABLE [IF NOT EXISTS] schema.table (
    -- 列定义：name type [constraints]
    column1 type1 CONSTRAINT pk_inline PRIMARY KEY,
    column2 type2 NOT NULL DEFAULT ...,
    ...

    -- 表级约束（多个列联合 / 命名约束 / FK）
    CONSTRAINT pk_orders PRIMARY KEY (id),
    CONSTRAINT uq_order_no UNIQUE (order_no),
    CONSTRAINT chk_amount_positive CHECK (amount >= 0),
    ...
);
```

#### 类比边界（哪里不灵）

- ❌ **5 大约束不够用，要外键**：本课不展开外键，**外键是表与表之间的关系，课 4 关系建模详讲**
- ❌ **`CHECK` 可以替代 `NOT NULL`**：不能——`NOT NULL` 解决"是否填"，`CHECK` 解决"填了什么"，两个独立维度

#### 核心原理 · 5 大约束 + 2 种自增

**1. PRIMARY KEY（主键 = NOT NULL + UNIQUE 的合体）**

```sql
-- 行内（只对一列）
id BIGINT PRIMARY KEY

-- 表级（更适合命名约束 / 复合主键）
CONSTRAINT pk_orders PRIMARY KEY (id)
```

要点：
- 每张表**只能有 1 个**主键（但可联合多列）
- 主键会自动创建唯一索引（用 B-Tree，阶段 3 详讲）
- PRIMARY KEY 列**默认隐含 NOT NULL**，不必再显式写

**2. NOT NULL（非空）**

```sql
order_no TEXT NOT NULL
```

要点：NULL 是 SQL 的三值逻辑之一（TRUE / FALSE / **NULL**）。`NULL = 'abc'` 是 `NULL`（不是 FALSE，意味着"不知道"）。

**3. UNIQUE（唯一）**

```sql
order_no TEXT UNIQUE             -- 行内
CONSTRAINT uq_order_no UNIQUE (order_no)  -- 表级
```

要点：UNIQUE 列允许 NULL（且允许多行 NULL——NULL 不算等值）。

**4. CHECK（检查）**

```sql
amount NUMERIC(10, 2) CHECK (amount >= 0)
status TEXT CHECK (status IN ('pending', 'paid', 'cancelled'))
CONSTRAINT chk_created_before_paid CHECK (paid_at IS NULL OR paid_at >= created_at)
```

要点：`CHECK` 在 INSERT / UPDATE 时执行；不满足就报错。可以引用本行其他列（跨列约束）。

**5. DEFAULT（默认）**

```sql
created_at TIMESTAMPTZ DEFAULT now()
is_paid BOOLEAN DEFAULT FALSE
extra JSONB DEFAULT '{}'::JSONB
```

要点：DEFAULT 只在 INSERT **完全不指定该列** 时生效。显式写 `INSERT INTO t (col1) VALUES (NULL)` 仍然写入 NULL。

**自增主键：`SERIAL` vs `GENERATED ALWAYS AS IDENTITY`**

| 维度 | `SERIAL`（legacy） | `GENERATED ALWAYS AS IDENTITY`（推荐） |
|---|---|---|
| SQL 标准 | PG 私有扩展 | SQL:2003 标准 |
| 何时引入 | 一直有 | PG 10+ |
| 自动创建序列 | 是 | 是（系统命名） |
| 允许手动插入 | 允许（无错） | **ALWAYS**：禁止；**BY DEFAULT**：允许 |
| 推荐 | legacy / 兼容旧项目 | **新表统一推荐**（PG 17 官方推荐） |
| 兼容性 | 任意 PG | PG 10+ |

> **核查于 2026-09-06**：PG 17 官方文档与社区共识均为"新表用 `GENERATED ALWAYS AS IDENTITY`"。`SERIAL` 仍合法（未删除），但**新表不再推荐**。

```sql
-- 推荐写法（PG 17 新表）
id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY

-- legacy 兼容（MySQL 来的代码、dbt 生成的 SQL 等可能仍是这种）
id SERIAL PRIMARY KEY

-- 等价展开：SERIAL = CREATE SEQUENCE + DEFAULT nextval + NOT NULL
```

#### 示例演示 · 完整的 `orders` 表

```sql
-- 把 2.1 的初版升级到"带约束的完整版"
DROP TABLE IF EXISTS public.orders;

CREATE TABLE public.orders (
    -- 主键 + 自增（IDENTITY 推荐写法）
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    -- 业务字段 + 约束
    order_no     TEXT        NOT NULL UNIQUE,
    user_id      INTEGER     NOT NULL,
    amount       NUMERIC(10, 2) NOT NULL CHECK (amount >= 0),
    status       TEXT        NOT NULL DEFAULT 'pending'
                              CHECK (status IN ('pending', 'paid', 'cancelled')),
    is_paid      BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    paid_at      TIMESTAMPTZ,
    note         TEXT,
    tags         TEXT[]      NOT NULL DEFAULT '{}',
    extra        JSONB       NOT NULL DEFAULT '{}'::JSONB,

    -- 表级约束：跨列逻辑
    CONSTRAINT chk_paid_after_created CHECK (
        paid_at IS NULL OR paid_at >= created_at
    ),

    -- 表注释 / 列注释
    CONSTRAINT pk_comment CHECK (TRUE)  -- 占位以便后续 COMMENT，PG 中表/列注释用 ALTER TABLE 单独加
);

COMMENT ON TABLE  public.orders IS '订单主表：每一行代表一笔订单';
COMMENT ON COLUMN public.orders.amount IS '订单金额（含 2 位小数，单位元）';
COMMENT ON COLUMN public.orders.order_no IS '业务订单号（前缀+日期+序号，唯一）';

-- 看表结构
\d public.orders
```

#### 常见误区

| 误区 | 真相 |
|---|---|
| ❌ "主键列必须用 `SERIAL`" | `SERIAL` 是 PG 私有扩展，**PG 10+ 起推荐 `GENERATED ALWAYS AS IDENTITY`** |
| ❌ "可以给一张表多个主键" | 错。每张表只能 1 个 `PRIMARY KEY`（但可由多列联合） |
| ❌ "`UNIQUE` 比 `PRIMARY KEY` 弱" | 不弱。`PRIMARY KEY = NOT NULL + UNIQUE`；一个表可以有多个 `UNIQUE`，只有一个 `PRIMARY KEY` |
| ❌ "`NOT NULL` 写在 `CHECK (col IS NOT NULL)` 里等价" | 不等价——`CHECK` 不创建 NOT NULL 的索引与约束元数据 |
| ❌ "`DEFAULT` 在 UPDATE 时也生效" | 错。`DEFAULT` 只在 INSERT 没指定时生效 |
| ❌ "约束报错就把整条记录写入了一半" | PG 默认每条语句是单事务，**要么全成功要么全失败**（这就是"事务"的体现，阶段 4 详讲） |
| ❌ "`COMMENT` 写在建表里就行" | 错。`COMMENT ON TABLE / COLUMN` 是单独的 DDL，不写在 CREATE TABLE 内 |

#### 一句话记住

> 5 大约束 `PRIMARY KEY` / `NOT NULL` / `UNIQUE` / `CHECK` / `DEFAULT` 是表合同的"主条款"；新表主键用 `IDENTITY` 别再用 `SERIAL`。

📚 **官方文档**：

- CREATE TABLE：[CREATE TABLE](https://www.postgresql.org/docs/current/sql-createtable.html)
- Identity Columns：[Identity Columns](https://www.postgresql.org/docs/current/ddl-identity-columns.html)
- 约束（5 大主约束）：[DDL Constraints](https://www.postgresql.org/docs/current/ddl-constraints.html)

---

### 第三幕（三）· 知识点 2.3：CRUD 基础

#### 一句话定义

> CRUD = **C**reate / **R**ead / **U**pdate / **D**elete，对应 `INSERT` / `SELECT` / `UPDATE` / `DELETE` 四个 DML（数据操作语言）语句。

#### 直觉建立

数据库表是个"装数据的水池"，CRUD 四个动作就是：

- **C**reate（`INSERT`）—— 灌新水
- **R**ead（`SELECT`）—— 取水看
- **U**pdate（`UPDATE`）—— 换桶里的旧水
- **D**elete（`DELETE`）—— 把脏水放掉

```mermaid
graph LR
    A[INSERT] -->|写| B(orders 表)
    B -->|读| C[SELECT]
    B -->|改| D[UPDATE]
    B -->|删| E[DELETE]
    B -->|清空| F[TRUNCATE]
```

#### 类比边界（哪里不灵）

- ❌ **`TRUNCATE` 与 `DELETE` 无关**：`TRUNCATE` 是 DDL（数据定义语言）级别，速度**远快于** `DELETE`（不触发触发器、不写 WAL 行级 redo，阶段 5 详讲）。生产慎用 `TRUNCATE`。
- ❌ **`UPDATE` 不带 WHERE 是正常操作**：在 PG 中 `UPDATE t SET col = 'x'` **不带 WHERE** 表示"全表更新"——极危险，必须确认条件

#### 核心原理 · 4 + 1 个 CRUD 语句

**1. INSERT（写入）**

```sql
-- 单行
INSERT INTO public.orders (order_no, user_id, amount)
VALUES ('ORD-20260906-001', 1001, 99.50)
RETURNING id, created_at;   -- RETURNING 返回刚写入的关键字段

-- 多行
INSERT INTO public.orders (order_no, user_id, amount)
VALUES
    ('ORD-20260906-002', 1002, 199.00),
    ('ORD-20260906-003', 1003, 49.90),
    ('ORD-20260906-004', 1004, 0.01)
RETURNING id, order_no;

-- 从 SELECT 插入（拷贝数据）
INSERT INTO public.orders_arch (id, order_no, user_id, amount, status, created_at)
SELECT id, order_no, user_id, amount, status, created_at
FROM public.orders
WHERE created_at < '2026-01-01';
```

`RETURNING` 是 PG 的杀手锏：**插入后立即返回生成的主键**，避免再次 `SELECT currval(...)`。

**2. SELECT（读取，本课只到基础）**

```sql
-- 最简
SELECT * FROM public.orders;                       -- 所有列
SELECT id, order_no, amount FROM public.orders;    -- 显式列出列

-- 加条件
SELECT * FROM public.orders WHERE user_id = 1001;
SELECT * FROM public.orders WHERE amount > 100 ORDER BY created_at DESC;

-- 聚合
SELECT status, COUNT(*) AS n, SUM(amount) AS total
FROM public.orders
GROUP BY status;

-- 限制行数（常用）
SELECT * FROM public.orders ORDER BY id DESC LIMIT 10;
```

> ⚠️ 完整的 `SELECT` 语法（WHERE / ORDER BY / LIMIT / GROUP BY / HAVING / JOIN / 子查询 / CTE ...）在**课 3 查询基础**详讲。本课只给你基础骨架，确保你能从 `orders` 表读出来数据。

**3. UPDATE（更新）**

```sql
-- 带 WHERE（必须！否则全表更新）
UPDATE public.orders
SET status = 'paid', paid_at = now(), is_paid = TRUE
WHERE id = 1
RETURNING id, status, paid_at;

-- 多列更新
UPDATE public.orders
SET amount = amount * 0.9   -- 9 折：amount 自己也参与计算
WHERE id IN (1, 2, 3)
RETURNING id, amount;
```

要点：
- **永远带 WHERE**，否则全表更新
- `RETURNING` 同 INSERT，返回受影响的所有行
- 阶段 4 详讲：UPDATE 在并发场景下的事务与锁问题

**4. DELETE（删除）**

```sql
-- 单行
DELETE FROM public.orders WHERE id = 1 RETURNING order_no;

-- 多行
DELETE FROM public.orders WHERE created_at < '2026-01-01' RETURNING id;
```

要点：
- 同样**永远带 WHERE**
- DELETE 不是真删——MVCC 留下死元组，阶段 4 课 12 详讲（`autovacuum` 清理）
- 不带 WHERE 的 DELETE 等价于 `TRUNCATE`，但**比 TRUNCATE 慢得多**

**5. TRUNCATE（截断 = 一次性清空整张表）**

```sql
TRUNCATE TABLE public.orders RESTART IDENTITY;   -- 同时把 IDENTITY 序列重置
```

- TRUNCATE 是 DDL，**远比 DELETE 快**（大表快 100 倍起）
- **不能加 WHERE**：要全表清空才用
- 阶段 5 讲运维（备份恢复）时再深入
- **生产禁止裸 TRUNCATE**（风险等同于 DROP TABLE）

#### 示例演示 · 一条订单的一生

```sql
-- 0. 确认连接到 order_service（如未连接）
\c order_service

-- 1. C — 创建（INSERT 单行）
INSERT INTO public.orders (order_no, user_id, amount)
VALUES ('ORD-20260906-001', 1001, 99.50)
RETURNING id, order_no, amount, status, created_at;

-- 2. C — 多行
INSERT INTO public.orders (order_no, user_id, amount)
VALUES
    ('ORD-20260906-002', 1002, 199.00),
    ('ORD-20260906-003', 1003, 49.90)
RETURNING id, order_no;

-- 3. R — 读
SELECT id, order_no, amount, status, is_paid
FROM public.orders
ORDER BY id DESC
LIMIT 10;

-- 4. R — 按用户筛选并聚合
SELECT user_id, COUNT(*) AS 订单数, SUM(amount) AS 总金额
FROM public.orders
GROUP BY user_id;

-- 5. U — 改（带 WHERE！标记订单 1 为已付）
UPDATE public.orders
SET status = 'paid', paid_at = now(), is_paid = TRUE
WHERE id = 1
RETURNING id, status, paid_at;

-- 6. U — 跨列计算（订单 2 改 9 折）
UPDATE public.orders
SET amount = amount * 0.9
WHERE id = 2
RETURNING id, amount;

-- 7. D — 单行删（订单 3 取消 + 删除订单 3 的数据）
DELETE FROM public.orders WHERE id = 3 RETURNING order_no;

-- 8. 看现在表里还剩什么
SELECT id, order_no, amount, status FROM public.orders ORDER BY id;
```

#### 常见误区

| 误区 | 真相 |
|---|---|
| ❌ "UPDATE / DELETE 不带 WHERE" | 这是 PG 新手最常见的"全表改 / 全表删"事故。生产禁止 |
| ❌ "`DELETE` 与 `TRUNCATE` 都删数据" | `TRUNCATE` 比 `DELETE` 快 100 倍（大表），但**不能加 WHERE**，且是 DDL、不触发触发器 |
| ❌ "`UPDATE` 不会触发 CHECK" | 会触发——CHECK 在每行 UPDATE 时都会跑 |
| ❌ "`SELECT *` 比 `SELECT 列` 快" | `SELECT *` 只在数据少时省事；生产应当**显式列出列**（少 IO、可读、演化更稳） |
| ❌ "`INSERT ... RETURNING id` 比 `currval()` 慢" | RETURNING 是单次往返，**比 `currval()` 更安全、并发下无 race** |
| ❌ "`UPDATE t SET col = ...` 改了一行就算成功" | 默认 UPDATE 在事务里是 all-or-nothing；要事务级联多个 UPDATE 用 `BEGIN ... COMMIT`（阶段 4 详讲） |

#### 一句话记住

> 写入 `INSERT RETURNING`；读 `SELECT` 列（**别用 `*`**）；改 `UPDATE` + `WHERE`；删 `DELETE` + `WHERE`；清表才用 `TRUNCATE`。

📚 **官方文档**：

- INSERT：[INSERT](https://www.postgresql.org/docs/current/sql-insert.html)
- SELECT：[SELECT](https://www.postgresql.org/docs/current/sql-select.html)
- UPDATE：[UPDATE](https://www.postgresql.org/docs/current/sql-update.html)
- DELETE：[DELETE](https://www.postgresql.org/docs/current/sql-delete.html)
- TRUNCATE：[TRUNCATE](https://www.postgresql.org/docs/current/sql-truncate.html)

---

## 第四幕 · 实操验证

### 综合演练（端到端）

> **前置**：课 1 起的 `pg17` 容器仍在跑，`order_service` 库已建。请先连上：

```bash
pgcli postgres://postgres:postgres@localhost:5432/order_service
```

**Part A · 类型 + 建表**

```sql
-- 1. 进 order_service（如果不在）
SELECT current_database();     -- 应 = order_service
SET search_path TO public;     -- 显式把 search_path 第一位设为 public
SHOW search_path;              -- public, "$user" 是等价的字符串解析结果可能略不同

-- 2. 删旧 orders（如有）保证幂等
DROP TABLE IF EXISTS public.orders;

-- 3. 建表（IDENTITY 主键 + 5 大约束 + JSONB 字段）
CREATE TABLE public.orders (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_no     TEXT        NOT NULL UNIQUE,
    user_id      INTEGER     NOT NULL,
    amount       NUMERIC(10, 2) NOT NULL CHECK (amount >= 0),
    status       TEXT        NOT NULL DEFAULT 'pending'
                              CHECK (status IN ('pending', 'paid', 'cancelled')),
    is_paid      BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    paid_at      TIMESTAMPTZ,
    note         TEXT,
    tags         TEXT[]      NOT NULL DEFAULT '{}',
    extra        JSONB       NOT NULL DEFAULT '{}'::JSONB,
    CONSTRAINT chk_paid_after_created CHECK (
        paid_at IS NULL OR paid_at >= created_at
    )
);

COMMENT ON TABLE  public.orders IS '订单主表：每一行代表一笔订单';
COMMENT ON COLUMN public.orders.amount IS '订单金额（含 2 位小数，单位元）';

-- 4. 看表结构
\d public.orders
```

**Part B · CRUD 完整流水线**

```sql
-- 5. CREATE：插入
INSERT INTO public.orders (order_no, user_id, amount)
VALUES ('ORD-20260906-001', 1001, 99.50)
RETURNING id, order_no, amount, status, created_at;
-- 预期：id = 1（IDENTITY 起始值），其余字段正确

-- 6. CREATE：多行
INSERT INTO public.orders (order_no, user_id, amount)
VALUES
    ('ORD-20260906-002', 1002, 199.00),
    ('ORD-20260906-003', 1003, 49.90)
RETURNING id, order_no;

-- 7. READ：基础读
SELECT * FROM public.orders ORDER BY id LIMIT 5;

-- 8. READ：按用户聚合
SELECT user_id, COUNT(*) AS n_orders, SUM(amount) AS total
FROM public.orders
GROUP BY user_id;

-- 9. UPDATE：标为已付
UPDATE public.orders
SET status = 'paid', paid_at = now(), is_paid = TRUE
WHERE id = 1
RETURNING id, status, paid_at, is_paid;

-- 10. UPDATE：跨列计算
UPDATE public.orders
SET amount = amount * 0.9
WHERE id = 2
RETURNING id, amount;

-- 11. DELETE：删订单 3
DELETE FROM public.orders WHERE id = 3 RETURNING order_no;

-- 12. 最终清单
SELECT id, order_no, user_id, amount, status, is_paid FROM public.orders ORDER BY id;
```

**Part C · 反例对照 · 这些是错的，看你能解释为什么**

```sql
-- 反例 1：金额用 FLOAT（演示浮点误差）
SELECT 0.1 + 0.2;  -- PG 里 NUMERIC 算 = 0.3；FLOAT 算 = 0.30...004
SELECT 0.1::FLOAT + 0.2::FLOAT;  -- 0.30000000000000004 ——这就是金额错的原因

-- 反例 2：VARCHAR(255) 模拟 MySQL 习惯
DROP TABLE IF EXISTS public.orders_varchar;
CREATE TABLE public.orders_varchar (
    id  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    note VARCHAR(255)  -- PG 中 255 没有任何特殊意义
);
-- 同样也可以用 text：
DROP TABLE IF EXISTS public.orders_text;
CREATE TABLE public.orders_text (
    id  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    note TEXT  -- PG 推荐默认，性能一致
);

-- 反例 3：不带 WHERE 的 UPDATE / DELETE
-- UPDATE public.orders SET status = 'paid';           -- ❌ 全表 paid
-- DELETE FROM public.orders;                          -- ❌ 全表清空（慢且无 UNDO）
-- TRUNCATE public.orders;                             -- ❌ 等同 DROP+重建（生产禁）
-- （不要执行以上三条；这就是新手最容易出的事故）

-- 反例 4：SERIAL vs IDENTITY —— 两种合法写法
DROP TABLE IF EXISTS public.orders_legacy;
CREATE TABLE public.orders_legacy (
    id  SERIAL PRIMARY KEY,           -- legacy，仍可用
    amount NUMERIC(10, 2)
);
-- 新表应当用上面的 GENERATED ALWAYS AS IDENTITY
```

### 反例对照 · 5 个"看起来对但不对"的写法

| 你要写 | ❌ 错误写法 | ✅ 正确写法 | 错在哪 |
|---|---|---|---|
| 金额类型 | `amount FLOAT` | `amount NUMERIC(10,2)` | 浮点误差，财务错 |
| 状态类型 | `status TINYINT` | `status TEXT` + `CHECK` | PG 无 TINYINT；状态用文本更易读 |
| 自增主键 | `id INT AUTO_INCREMENT` | `id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | PG 无 AUTO_INCREMENT；用 IDENTITY |
| 不带 WHERE 更新 | `UPDATE orders SET status = 'paid';` | `UPDATE orders SET status = 'paid' WHERE id = 1;` | 全表更新 |
| 时间类型 | `created_at DATETIME` | `created_at TIMESTAMPTZ` | PG 无 DATETIME；带时区才稳 |

**预期结果**：
- Part B 跑完应看到 2 行（订单 1、订单 2），订单 3 已被 DELETE
- Part C 反例 1 的 FLOAT 算式应输出 `0.30000000000000004`（印证财务场景为什么必须 NUMERIC）

---

## 第五幕 · 体系收束

你今天得到的能力地图：

```
                     课 2 · 表与数据类型（全课 3 个知识点）
                                   │
        ┌──────────────┬───────────┴────────┬──────────────┐
        ▼              ▼                    ▼              ▼
   数据类型         建表约束              CRUD             一张合规
   8 大族             5 大约束            4 + 1 操作        的 orders 表
   （金额 NUMERIC）  （PRIMARY KEY）      （INSERT          （建得对 + 用得对）
        │              │                   RETURNING）        │
        │              │                   UPDATE/DELETE      │
        │              │                   + WHERE）           │
        │              │                       │              │
        └──────────────┴───────────┬──────────┴──────────────┘
                                   │
                         现在你会做什么？
                                   │
        ┌──────────────────────────┴──────────────────────────┐
        ▼                                                     ▼
  能为任意业务实体设计                                   能对一张表完成完整的
  数据类型与约束组合                                       CRUD 流水线
        │                                                     │
        └─────────────────┬──────────────────┬───────────────┘
                          ▼                  ▼
                  上一课（课 1 已会）   下一课《查询基础》
                  装库 / 连库 / 四层结构   （用 SELECT 把订单查出来）
```

**本课在整体故事中的位置**：主角一行订单**终于出生了**——我们给它**配齐类型（NUMERIC 金额 / TIMESTAMPTZ 时间 / TEXT 订单号）+ 上了规矩（PK / NOT NULL / UNIQUE / CHECK / DEFAULT）+ 演练了 CRUD 流水线**。**下一步要把订单查出来**。

**接下来**：

- **下一课《查询基础》**：用今天建的 `orders` 表做 WHERE / ORDER BY / LIMIT / JOIN / 聚合（课 3，3 个知识点）
- **阶段 1 收官预告**：学完课 3 后，你应能独立 **"用 Docker 起 PG / 建库 / 建表 / 写 CRUD / 写日常 SQL 查询"** 的端到端能力

---

## 🐞 误区清单

| # | 误区 | 触发 | 修复 |
|---|---|---|---|
| 1 | 金额用 `FLOAT` | 0.1 + 0.2 = 0.30...004；对账必然错 | 所有金额必须 `NUMERIC(10, 2)` |
| 2 | 状态用 `TINYINT` | PG 无此类型；用 `SMALLINT` 也失去可读性 | 用 `TEXT` + `CHECK` 或 `CREATE TYPE ... AS ENUM` |
| 3 | 时间用 `TIMESTAMP`（不带时区） | 跨时区协作数据错乱 | 生产用 `TIMESTAMPTZ`，跨时区无障碍 |
| 4 | 主键用 `SERIAL` | 老 PG 习惯；PG 17 不再推荐 | 新表用 `GENERATED ALWAYS AS IDENTITY` |
| 5 | `VARCHAR(255)` 模拟 MySQL | PG 中 255 无意义，反而加长度检查 | 默认 `TEXT`；要长度用 `VARCHAR(N)` + `CHECK` |
| 6 | `UPDATE` 不带 WHERE | 全表更新，生产事故 | `UPDATE ... WHERE id = 1` 永远带条件 |
| 7 | `DELETE` 不带 WHERE | 全表清空（比 TRUNCATE 慢，且无触发器） | `DELETE ... WHERE ...` 永远带条件 |
| 8 | `SELECT *` 写在大表日报 | 多读无用列；返不出可演进 | 显式 `SELECT id, order_no, amount ...` |
| 9 | 在 `TRUNCATE` 上加 `WHERE` | TRUNCATE 不接受 WHERE | `TRUNCATE` 是清全表；要条件删用 `DELETE WHERE` |
| 10 | `RETURNING` 与 `currval()` 混用 | 并发下 currval 不安全 | 用 `INSERT ... RETURNING id` 单次往返 |

---

## 一图总结

![课 2 一图总结](./assets/lesson-02-overview.svg)

---

## 📋 命令速查卡（课 2）

| 命令 | 作用 | 注意事项 |
|---|---|---|
| `DROP TABLE IF EXISTS public.orders;` | 删除表（如有）保证幂等 | IF NOT EXISTS / IF EXISTS 是好习惯 |
| `CREATE TABLE public.orders (...);` | 建表 | 推荐把所有约束写在表内或表级 |
| `id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | PG 17 推荐主键写法 | SERIAL 仍合法，新表不再推荐 |
| `column TEXT NOT NULL` | 默认字符串类型 + 非空 | text 性能等同 varchar(N) |
| `amount NUMERIC(10, 2) CHECK (amount >= 0)` | 任意精度 + 检查约束 | 金额必用 NUMERIC |
| `created_at TIMESTAMPTZ NOT NULL DEFAULT now()` | 带时区时间戳 | TIMESTAMP 不带时区，生产禁 |
| `tags TEXT[] NOT NULL DEFAULT '{}'` | 数组字段（任意元素类型都行） | 阶段 2 课 6 数组函数 |
| `extra JSONB NOT NULL DEFAULT '{}'::JSONB` | JSON 二进制编码 | 比 json 类型查询快（可建 GIN 索引） |
| `COMMENT ON TABLE / COLUMN ... IS '...'` | 表/列注释 | DDL 单独写，不可放在 CREATE TABLE |
| `\d public.orders` | 看表结构 | 含列、约束、索引、注释 |
| `INSERT INTO t (col1, col2) VALUES (...) RETURNING id, ...;` | 插入并返回生成值 | RETURNING 是 PG 杀手锏 |
| `INSERT INTO t (cols) VALUES (...), (...) RETURNING ...;` | 多行插入 | 一次往返，比单行循环快 |
| `INSERT INTO t_arch SELECT ... FROM t WHERE ...;` | 从 SELECT 插入 | 表拷贝常用 |
| `SELECT id, order_no FROM t WHERE user_id = 1001 ORDER BY id DESC LIMIT 10;` | 基础读 | 显式列 + WHERE + ORDER + LIMIT |
| `SELECT user_id, COUNT(*), SUM(amount) FROM t GROUP BY user_id;` | 聚合 | GROUP BY 列出非聚合列 |
| `UPDATE t SET col = ... WHERE id = 1 RETURNING *;` | 单行更新 | **永远带 WHERE** |
| `UPDATE t SET amount = amount * 0.9 WHERE id IN (1,2,3);` | 多行更新 + 跨列计算 | 自身列也参与计算 |
| `DELETE FROM t WHERE id = 1 RETURNING *;` | 单行删除 | **永远带 WHERE** |
| `TRUNCATE TABLE t RESTART IDENTITY;` | 一次性清空整表 | DDL，比 DELETE 快百倍，**生产禁** |
| `SELECT 0.1::FLOAT + 0.2::FLOAT;` | 演示浮点误差 | 输出 0.30000000000000004 → 为什么金额必用 NUMERIC |
| `DROP TABLE IF EXISTS public.orders;` | 反例说明（每课带"反例对照"段） | — |

> 命令速查卡规则：本课程的每条命令都会在用到它的课里再出现一次（不重复发明）。

---

## 🌐 关键事实备注（核查于 2026-09-06）

| 事实 | 当前值 | 来源 |
|---|---|---|
| PG 17 最新 minor | **17.11**（2026-08-10） | endoflife.date / hub.docker.com |
| text / varchar(N) / char(N) 性能 | **三者存储性能一致**；text / varchar(N) 几乎无差；char(N) padding 反而更慢 | postgresql.org/docs/current/datatype-character |
| NUMERIC 行为 | 任意精度（无浮点误差）；decimal 与 numeric 等价 | postgresql.org/docs/current/datatype-numeric |
| TIMESTAMPTZ 默认 | 内部存 UTC，显示切换会话时区 | postgresql.org/docs/current/datatype-datetime |
| IDENTITY 推荐 | PG 10+ 标准；**PG 17 新表推荐 IDENTITY**；SERIAL 仍合法 | postgresql.org/docs/current/ddl-identity-columns |
| PG 17 新增 | `pg_uuidv7` 扩展（用于分布式有序 UUID；PG 17+ 独有） | PG 17 release notes |

---

## 🧭 课程导航

> **本课在阶段 1 的位置**：阶段 1 三课中的第二课（中间课），课 1 是开场、课 3 收官。
>
> **阶段 1 三课**（学完课 3 阶段 1 闭环）：
>
> - 课 1 认识 PostgreSQL（[上一课 →](lesson-01-认识PostgreSQL.md)）
> - 课 2 表与数据类型 ← **你在这里**
> - 课 3 查询基础（[下一课 →](lesson-03-查询基础.md)）
>
> **阶段 1 闭环预告**：学完课 3 后，你应能独立 **"用 Docker 起 PG / 建库 / 建表 / 写 CRUD / 写日常 SQL 查询"** 的端到端能力。
>
> **整课任务完成标记**：2.1 + 2.2 + 2.3 三知识点均已交付 ✅（P0=0，2 项事实核查 PASS，见备注）。

- 上一课：[课 1 认识 PostgreSQL（认识 PG / 装库 / 四层结构）](lesson-01-认识PostgreSQL.md)（同阶段）
- 下一课：[课 3 查询基础（WHERE / JOIN / 聚合）](lesson-03-查询基础.md)（同阶段）
- 返回目录：[`02-课程目录.md`](../../02-课程目录.md)
- 上一阶 / 下一阶：阶段 1 是首阶段，上无前置阶段；阶段 2（数据建模与 SQL 进阶）作为下一阶
