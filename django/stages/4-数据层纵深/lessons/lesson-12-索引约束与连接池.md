# 课 12《索引、约束与连接池》

> 🧭 所属阶段：[阶段 4 数据层纵深](../overview.md) ｜ 上一课：[课 11 查询表达式进阶](./lesson-11-查询表达式进阶.md) ｜ 下一课：课 13 多数据库与 DB 路由（阶段 4）
>
> 🎯 **本课回答三个问题**：索引怎么加才真的有用？校验为什么必须下沉到数据库？连接池的连接数到底怎么算？
>
> ⚙️ **实跑环境**：Django **6.1** / Python **3.13.14** / psycopg **3.3.5** + psycopg-pool **3.3.1**（Windows 托管 venv `dj-course`）。索引与约束实验跑在 SQLite，连接池实验直接构造 PostgreSQL `DatabaseWrapper` 验证配置校验（不要求真的连上 PG）。
>
> 📦 实验工程：`%TEMP%/dj-lesson12-demo/idxlab`，13 个实验全部实测通过。

#### 怎么跑起来

```bash
# 复用课 2 建的虚拟环境
# Windows: C:\Users\<你>\.workbuddy\binaries\python\envs\dj-course\Scripts\python.exe

# ① 索引与约束实验（实验 1–7、10–12）：只需 SQLite，无需装 psycopg
cd %TEMP%/dj-lesson12-demo/idxlab
set PYTHONPATH=<idxlab绝对路径>/apps        # shop app 在 apps/ 下，不设会 import 失败
python manage.py makemigrations shop
python run_lab.py

# ② 连接池实验（实验 8、9、13）：需装 psycopg3，但不需要真的连上 PostgreSQL
pip install "psycopg[binary,pool]"
python run_lab.py
```

> 💡 **第二点很关键**：连接池的三条硬约束都是**配置校验**，在建立真实连接之前就会触发。所以即使本机没有 PostgreSQL，实验 8 照样能跑、照样能看到 `ImproperlyConfigured`。别因为没有 PG 环境就跳过第三幕 —— 第四坑就在那里。

---

## 开场：三个"看起来对"的决定

**决定一**：列表页慢，运维说"加个索引"。你给 `status` 加了索引，上线后发现**查询没变快，写入反而慢了**。

**决定二**：金额必须大于 0，你写在了 Serializer 里。半年后新同事写了个数据修复脚本，直接 `bulk_create`，**负数进库了**。

**决定三**：上了连接池，`max_size=10`。你算着"10 条连接，数据库上限 100，稳得很"。上线第二天数据库报 `too many clients already`。

三个决定都是"看起来对"的。它们的共同点：**都在用直觉替代验证**。

这一课就是把这三个直觉拆开，换成可验证的做法。

---

## 第一幕：索引 —— 加之前先问"它会被用上吗"

### 1.1 三种索引的物理形态

先从最实在的问题开始：你写的 `Meta.indexes` 到底生成了什么 DDL？

```python
class Article(models.Model):
    title = models.CharField(max_length=200)
    email = models.EmailField(max_length=255)
    status = models.CharField(max_length=16, default="draft")
    view_count = models.IntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes = [
            # ① 普通索引
            models.Index(fields=["status"], name="idx_art_status"),
            # ② 部分索引：只对 published 建
            models.Index(
                fields=["-created_at"],
                condition=models.Q(status="published"),
                name="idx_art_pub_created",
            ),
            # ③ 函数索引：按小写邮箱查询时使用
            models.Index(Lower("email"), name="idx_art_email_lower"),
        ]
```

`sqlmigrate` 的真实输出（实验 1）：

```sql
CREATE INDEX "idx_art_status"       ON "shop_article" ("status");
CREATE INDEX "idx_art_pub_created"  ON "shop_article" ("created_at" DESC) WHERE "status" = 'published';
CREATE INDEX "idx_art_email_lower"  ON "shop_article" ((LOWER("email")));
```

三者的差别一眼可见：

| 类型 | DDL 特征 | 索的是什么 |
|------|---------|-----------|
| 普通索引 | 无特殊子句 | 全表所有行的列值 |
| **部分索引** | 带 `WHERE` | 只有满足条件的行 |
| **函数索引** | 键是表达式 `(LOWER(email))` | 表达式的计算结果，不是原列 |

注意函数索引那对**双括号** `((LOWER("email")))` —— 外层是索引定义，内层是表达式。这是表达式索引的固定形态。

> ⚠️ **命名是强制的**：使用 `condition` 或表达式索引时，`name` **必填**，Django 不会自动生成。

### 1.2 部分索引：体积是最硬的论据

"部分索引更小"人人都说，但小多少？实测（实验 12，20000 行，published 占 10%）：

```
表本体                        1,626,112 bytes
idx_art_status（全表）          356,352 bytes
idx_art_pub_created（10%）      131,072 bytes  = 全表索引的 37%
idx_art_email_lower（函数）     659,456 bytes
```

**131 KB vs 356 KB，省了 63%。** 索引体积直接决定：磁盘占用、缓存命中率、写入时要维护的 B 树大小。

> 💡 **`dbstat` 是 SQLite 的虚拟表**，PostgreSQL 上查索引体积用：
> ```sql
> SELECT pg_size_pretty(pg_relation_size('idx_art_status'));       -- 单个索引
> SELECT pg_size_pretty(pg_total_relation_size('shop_article'));    -- 表 + 全部索引
> SELECT pg_size_pretty(pg_indexes_size('shop_article'));           -- 只算索引
> ```

适用场景非常明确：**热点只占少数**。未归档的订单、已发布的文章、未处理的任务队列 —— 这些表 90% 以上的行会被历史数据淹没，而你的查询只关心那 10%。

### 1.3 反直觉：优化器未必选你的部分索引

这是本课最值得记的一条。实验 2b 用 SQLite 的 `INDEXED BY` 强制对比：

```
不干预（优化器自选）
    SEARCH shop_article USING INDEX idx_art_status (status=?)
    USE TEMP B-TREE FOR ORDER BY        ← 额外排序

禁用全部索引
    SCAN shop_article
    USE TEMP B-TREE FOR ORDER BY

强制部分索引
    SCAN shop_article USING INDEX idx_art_pub_created
                                        ← 排序步骤消失
```

强制部分索引后，**`USE TEMP B-TREE FOR ORDER BY` 消失了** —— 这就是部分索引的真实收益：索引本身有序，数据库不必再排一遍。

但请注意前半段：**不强制时，SQLite 优化器根本没选它**，而是选了 `status` 索引 + 额外排序。

这说明两件事：

1. 部分索引的价值在 PostgreSQL 上更可靠 —— PG 的优化器对部分索引的识别更成熟，SQLite 需要 `INDEXED BY` 强制。
2. **不要凭"我建了索引"就认为它生效**。必须用 `explain()` 验证。

#### 那到底该不该建部分索引？

关键看你的**生产数据库**是哪一种（Django 官方文档明示的后端差异）：

| 后端 | `condition` 支持 | 说明 |
|------|----------------|------|
| **PostgreSQL** | ✅ 完整支持 | 优化器识别成熟，可放心依赖；要求条件中的函数标为 `IMMUTABLE` |
| **SQLite** | ✅ 支持 | 有构建限制，且优化器保守，实测需要 `INDEXED BY` 才一定生效 |
| **MySQL / MariaDB** | ❌ 忽略 | `condition` 参数被静默忽略，索引会建成全表索引 |
| **Oracle** | ❌ 不支持 | 需用函数索引 + `Case` 表达式模拟，靠 `RunSQL` 迁移 |

实践建议：**"本地 SQLite + 生产 PostgreSQL"是最常见的组合，此时以 PG 的行为为准**。也就是说，即使 SQLite 上 `explain()` 没选中部分索引，只要你的生产库是 PG，这个索引依然值得建 —— 但要**在 PG 上复验一次**。

反过来说，如果生产是 MySQL，写 `condition` 不但没用，还会让你误以为建了部分索引 —— 这是"静默失效"的又一个例子。

> 📌 这已经是本课第三次遇到"SQLite 与 PG 行为不一致"：课 11 的 `select_for_update` 在 SQLite 上静默失效、本节的优化器选择差异、下一节的 `dbstat` 只能用于 SQLite。**凡是涉及性能与并发的结论，都要在生产同款数据库上验证。**

### 1.4 函数索引：写法必须精确匹配

函数索引的陷阱是"表达式要一模一样"。实验 2c：

```python
# ✅ 命中：USING INDEX idx_art_email_lower (<expr>=?)
Article.objects.annotate(lo=Lower("email")).filter(lo="user5@example.com")

# ❌ 全表扫描：SCAN shop_article
Article.objects.filter(email__iexact="user5@example.com")

# ❌ 全表扫描：与原列比较，和函数索引无关
Article.objects.filter(email="user5@example.com")
```

> 🔴 **实测证伪**：我原以为存在 `email__lower` 这个 lookup，实测直接报错：
> ```
> FieldError: Unsupported lookup 'lower' for EmailField
> ```
> `Lower` 是**数据库函数**，不是 **lookup**。要命中函数索引，只能走 `annotate` + `filter` 的写法。

> 💡 **`annotate` 在这里是必需的，不是可选写法**。它会往查询里加一个**计算列**并给它起个名字（`lo`），然后 `filter` 对这个计算列做过滤。只有这样，生成的 SQL 才是与索引定义完全一致的 `LOWER(email) = ?`。
> 直接 `filter` 是做不到的 —— `Lower("email")` 作为关键字参数在 Python 里本身就非法（函数名不能做参数名）。`annotate` / 表达式的用法详见[课 11 查询表达式进阶](./lesson-11-查询表达式进阶.md)。

`iexact` 生成的是 `LIKE ... ESCAPE`，与 `LOWER(email) = ?` 不是同一个表达式，所以命中不了。

### 1.5 选择性：为什么"加了索引却没变快"

实验 3 在同一张表、同一个索引上，换不同取值：

```
status='published'  命中索引=True  | SEARCH shop_article USING INDEX idx_art_status
status='archived'   命中索引=True  | SEARCH shop_article USING INDEX idx_art_status
status='draft'      命中索引=True  | SEARCH shop_article USING INDEX idx_art_status
WHERE view_count=5（无索引）        | SCAN shop_article
```

诚实地说：**在这个数据集上 SQLite 全都命中了索引**，我预设的"低选择性不命中"**没有复现**。SQLite 的优化器比较朴素，倾向于有索引就用。

但把结论说全：

- **"低选择性导致放弃索引"是 PostgreSQL/MySQL 的典型行为**，它们的优化器会基于成本估算，发现要回表 60% 的行时不如直接顺序扫描。
- **SQLite 的行为不代表生产环境**。用 SQLite 做索引实验，得到的是"索引存在与否"，不是"优化器会怎么选"。
- 真正普适的结论是后半句：**索引在拖慢写入，这一点在任何数据库上都成立**。

所以"加了索引就快"这个信念，正确版本是：**加了索引，且优化器选择了它，且过滤性足够好，才会快**。

### 1.6 索引的代价：每次写入都要维护

实验 4，同样插入 2000 行：

```
Article（3 个二级索引）                 耗时    24.0 ms
Order（1 个二级索引 + 2 个约束）          耗时    19.7 ms
```

每多一个索引，每次 `INSERT` / `UPDATE` / `DELETE` 就要多维护一棵 B 树。这张表的索引数量差 3 倍，写入耗时差约 22%。

**没有万能的"索引数量上限"**。合理边界取决于表的读写比：读多写少的配置表可以多建，高频写入的流水表要克制。

### 1.7 验证手段：explain()

```python
Article.objects.filter(status="published").explain()
# '3 0 61 SEARCH shop_article USING INDEX idx_art_status (status=?)'

# PostgreSQL 支持更多格式
qs.explain(format="json")      # PG 可用
qs.explain(analyze=True)       # PG 可用，真实执行
```

> ⚠️ **SQLite 不支持 format 参数**（实验 11 实测）：
> ```
> ValueError: JSON is not a recognized format. SQLite does not support any formats.
> ```

`explain()` 是索引验证的**唯一可靠手段**。"应该会走索引"是不算数的。

> ⚠️ **`INDEXED BY` 是 SQLite 专有语法**，PostgreSQL 上要用 `SET enable_seqscan = off;` 来强制对比（仅用于验证，不要在生产开）。

### 1.8 索引设计决策清单

把上面七节收口成一个可执行流程。下次遇到"这个列表页慢"，按这个顺序判断：

1. **这个查询高频吗？** 不高频（比如一天几次的后台统计）→ 不建，索引的写入代价不划算。
2. **现在 `explain()` 走的是什么？** 如果已经走了索引还慢 → 问题不在索引，去看返回行数、序列化、N+1。
3. **过滤条件的选择性如何？** 单列选择性差（如 `status` 只有 3 个值）→ 不要单建，考虑作为复合索引的**后列**配合其他高选择性字段。
4. **是不是只查热点子集？** 是（未归档订单、已发布文章）→ **部分索引**，体积小、写入代价低。
5. **过滤涉及表达式吗？** 是（大小写无关、日期截断、JSON 取值）→ **函数索引**，且查询写法必须与索引定义精确匹配。
6. **建完之后再 `explain()` 一次。** 没走 → 回第 3 步重新设计，不要保留一个不生效的索引。

一个反面清单同样重要：**不要建这三类索引** —— 从不用于过滤/排序的列、与现有复合索引前缀重复的索引、低频写入表之外的高频写入表上的多余索引。

### 1.9 已移除：index_together

实验 10 实测 Django 6.1：

```
Options 上是否还有 index_together 属性：False
定义带 index_together 的模型 —— 报错：TypeError
    'class Meta' got invalid attribute(s): index_together
```

不是废弃警告，是**直接报错**。`index_together` 已彻底移除，统一用 `Meta.indexes`。同理 `check=` 参数也已移除（见 2.4）。

---

## 第二幕：约束下沉 —— 可被绕过的不叫约束

### 2.1 为什么 Serializer 校验不够

Serializer 校验只覆盖**经过这条代码路径的请求**。绕过它太容易了：

- 数据修复脚本 / 管理命令
- Celery 任务
- 未来的第二个服务，用另一种语言写的
- 同事在 `dbshell` 里手改
- 数据迁移 `RunPython`

数据库约束是 DDL，写在表结构里，**任何写入路径都绕不过**。

### 2.2 两种约束怎么写

```python
class Order(models.Model):
    shop_id = models.IntegerField()
    order_no = models.CharField(max_length=64)
    amount = models.DecimalField(max_digits=10, decimal_places=2)
    status = models.CharField(max_length=16, default="draft")

    class Meta:
        constraints = [
            # ① 值域约束
            models.CheckConstraint(
                condition=models.Q(amount__gt=0),
                name="chk_order_amount_positive",
            ),
            # ② 条件唯一：仅对非 cancelled 的记录强制唯一
            models.UniqueConstraint(
                fields=["shop_id", "order_no"],
                condition=~models.Q(status="cancelled"),
                name="uniq_order_shop_no_active",
            ),
        ]
```

生成的 DDL（实测）：

```sql
CONSTRAINT "chk_order_amount_positive" CHECK ("amount" > '0')

CREATE UNIQUE INDEX "uniq_order_shop_no_active"
    ON "shop_order" ("shop_id", "order_no") WHERE NOT ("status" = 'cancelled');
```

**条件唯一约束在物理上就是一个唯一的部分索引** —— 第一幕的知识在这里直接复用。

> 💡 `~models.Q(...)` 中的 `~` 是**取反**运算符，等价于 SQL 的 `NOT`。所以上面生成的是 `WHERE NOT (status = 'cancelled')`。Q 对象的 `&`（AND）、`|`（OR）、`~`（NOT）三种运算详见[课 11 查询表达式进阶](./lesson-11-查询表达式进阶.md)。

### 2.3 实测：任何路径都绕不过

实验 5、6：

```
5a ORM create(amount=-5)    —— 被拦截：CHECK constraint failed: chk_order_amount_positive
5b 裸 SQL 插入              —— 同样被拦截：CHECK constraint failed: chk_order_amount_positive
6① 创建 shop=7/NO-100/paid  —— 成功
6② 再建一条 draft 同号      —— 被拦截：UNIQUE constraint failed: shop_order.shop_id, shop_order.order_no
6③ 再建一条 cancelled 同号  —— 成功（condition 排除了它）
```

第 6③ 条是条件唯一的精髓：**已取消的订单允许重号**，因为 `condition` 把它们排除了。用 `unique_together` 做不到这件事。

### 2.4 ⚠️ 与旧文档冲突：full_clean() 现在会校验约束

这是本课**最需要注意的版本差异**。

很多教程（包括 Django 5.2 官方文档的约束页）写着：

> "constraints are not checked during `full_clean()`"

**在 Django 6.1 上这句话已经不成立**。实验 5c 与补充验证实测：

```python
o = Order(shop_id=777, order_no='ZZZ', amount='-3.00', status='draft')
o.full_clean()
# ValidationError: {'__all__': ['Constraint "chk_order_amount_positive" is violated.']}
```

三类场景全测了：

| 场景 | `full_clean()` 结果 |
|------|-------------------|
| 金额非法（无唯一冲突） | 报 `Constraint "chk_order_amount_positive" is violated.` |
| 条件唯一冲突 | 报 `Constraint "uniq_order_shop_no_active" is violated.` |
| 仅金额非法，唯一值全新 | 报 `Constraint "chk_order_amount_positive" is violated.` |

源码依据（`django/db/models/base.py` 的 `validate_constraints`）会遍历 `get_constraints()` 并逐个 `validate()`。**约束验证自 Django 4.1 起并入模型验证**，旧文档的表述是历史遗留。

> 📌 **实践含义**：`full_clean()` 现在能提前拦住约束错误，不必等到 `save()` 抛 `IntegrityError`。但**它只对调用了 `full_clean()` 的路径生效** —— DRF 的 Serializer 默认调用的是字段级校验，**不自动调用 `full_clean()`**。所以"下沉到 DB"依然是唯一可靠的那一层。

### 2.5 ⚠️ 第二个版本坑：check= 参数已被移除

旧写法（Django ≤ 5.x）：

```python
models.CheckConstraint(check=Q(price__gt=0), name="old_style")   # ❌
```

Django 6.1 实测：

```
TypeError: CheckConstraint.__init__() got an unexpected keyword argument 'check'
```

当前签名：

```python
CheckConstraint.__init__(self, *, condition, name,
                         violation_error_code=None, violation_error_message=None)
```

`check` 关键字在 **Django 6.0 被移除**（见 6.0 release notes 的 "Features removed in 6.0"）。照抄旧教程会直接启动失败。

### 2.6 异常翻译：从 IntegrityError 到 API 错误码

实验 7：

```
CheckConstraint 违反  → IntegrityError: CHECK constraint failed: chk_order_amount_positive
条件唯一违反         → IntegrityError: UNIQUE constraint failed: shop_order.shop_id, shop_order.order_no
```

Django 把所有 DB 完整性错误统一为 `IntegrityError`，**没有细分子类型**。要区分"违反了哪个约束"，只能匹配异常消息里的约束名。

这就是为什么 **2.2 里约束命名要带业务含义**（`chk_order_amount_positive` 而不是 `check1`）。

翻译到 API 层的模式：

```python
from django.db import IntegrityError
from rest_framework.exceptions import ValidationError, APIException

def create_order(data):
    try:
        with transaction.atomic():
            return Order.objects.create(**data)
    except IntegrityError as e:
        msg = str(e)
        if "chk_order_amount_positive" in msg:
            raise ValidationError({"amount": "金额必须大于 0"})      # 400
        if "uniq_order_shop_no_active" in msg:
            raise APIException("订单号重复", code="order_duplicated")  # 409
        raise
```

> ⚠️ 依赖异常消息做分支是**脆弱的**：不同数据库、不同版本的消息文本会变。生产环境更稳的做法是**先查后写**（用 `select_for_update` 或条件唯一查询），把 `IntegrityError` 当作兜底而非主路径。

"先查后写"长这样：

```python
from django.db import transaction

def create_order(shop_id, order_no, amount):
    with transaction.atomic():
        # 先在同一事务里锁住并判断，把冲突在写之前就发现
        exists = (
            Order.objects
            .select_for_update()
            .filter(shop_id=shop_id, order_no=order_no)
            .exclude(status="cancelled")
            .exists()
        )
        if exists:
            raise APIException("订单号重复", code="order_duplicated")
        return Order.objects.create(
            shop_id=shop_id, order_no=order_no, amount=amount, status="paid"
        )
```

> ⚠️ **`select_for_update` 在 SQLite 上静默失效**（课 11 实测：SQL 里根本没有 `FOR UPDATE`）。这段代码在 SQLite 上跑不出锁的效果，必须配合 DB 约束兜底 —— 这正是"两件事都要做"的典型场景：**DB 约束保证正确性，先查后写保证错误可读**。

---

## 第三幕：连接池 —— 连接数到底怎么算

### 3.1 为什么需要池

没有池时，每个请求都要经历：TCP 握手 → SSL 握手 → PG 认证 → 建会话。这段开销通常是 **几十毫秒**，可能比查询本身还慢。

Django 5.1 起内置了连接池，不需要 PgBouncer，也不需要第三方包：

```python
DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": "mydb",
        "USER": "u", "PASSWORD": "p",
        "HOST": "127.0.0.1", "PORT": "5432",
        "CONN_MAX_AGE": 0,              # 必须
        "OPTIONS": {
            "pool": {"min_size": 4, "max_size": 10, "timeout": 10},
        },
    }
}
```

### 3.2 三条硬约束（全部实跑）

**约束一：必须是 psycopg3 + psycopg[pool]**

源码 `django/db/backends/postgresql/base.py` 两道校验：

```python
# 版本门槛
if (3,) <= psycopg_version() < (3, 1, 12):
    raise ImproperlyConfigured("psycopg version 3.1.12 or newer is required")
if psycopg_version() < (2, 9, 9):
    raise ImproperlyConfigured("psycopg2 version 2.9.9 or newer is required")

# 池的驱动要求（在 get_connection_params 中）
pool_options = conn_params.pop("pool", None)
if pool_options and not is_psycopg3:
    raise ImproperlyConfigured("Database pooling requires psycopg >= 3")
```

> 📌 档案里记的是"需 psycopg3"，**不精确**。源码的实际门槛是 **3.1.12**，不是"3"。
> 本机实测：`psycopg 3.3.5`，`is_psycopg3 = True`。

缺 `psycopg_pool` 时会提示：

```
ImproperlyConfigured: Error loading psycopg_pool module.
Did you install psycopg[pool]?
```

安装方式（注意是 `psycopg` 不是 `psycopg3`）：

```bash
pip install "psycopg[binary,pool]"
```

**约束二：`CONN_MAX_AGE` 必须为 0**

实验 8d 实测报错原文：

```
ImproperlyConfigured: Pooling doesn't support persistent connections.
```

源码位置（`base.py:200`）：

```python
if self.settings_dict.get("CONN_MAX_AGE", 0) != 0:
    raise ImproperlyConfigured("Pooling doesn't support persistent connections.")
```

原因是职责冲突：池要自己管理连接生命周期（`max_lifetime` / `max_idle`），如果 Django 再按 `CONN_MAX_AGE` 关一次，两边会互相打架。

**约束三：池是按进程算的**

源码里 `_connection_pools` 是**类属性**：

```python
class DatabaseWrapper(BaseDatabaseWrapper):
    _connection_pools = {}     # 类级字典，每个进程一份
```

所以：

```
总连接数 ≈ worker 进程数 × max_size
4 workers × max_size=10 = 40 条，不是 10 条
```

这是生产容量估算最经典的错误来源。

### 3.3 🔴 第四个坑（档案没记）：`pool={}` 会静默失效

实验 8 抓到的，官方文档没有强调：

```
8a 未配置 pool                    → pool 为 None
8b pool={} 空字典                 → pool 为 None     ← 静默失效！
8c pool=True                      → 池创建成功 min_size=4 max_size=4
8d pool=True + CONN_MAX_AGE=60    → ImproperlyConfigured
8e pool={'max_size': 10}          → 池创建成功 min_size=4 max_size=10
```

源码判定是：

```python
pool_options = self.settings_dict["OPTIONS"].get("pool")
if self.alias == NO_DB_ALIAS or not pool_options:
    return None
```

**空字典 `{}` 是 falsy**，直接 `return None`。写 `"pool": {}` 想"用默认配置"，结果是**池根本没启用，还不报错**。

正确写法：`"pool": True`，或带实际键值的字典。

### 3.4 默认参数与容量公式

`psycopg_pool.ConnectionPool` 的默认值（实读签名）：

```
min_size             默认 = 4
max_size             默认 = None
timeout              默认 = 30.0
max_lifetime         默认 = 3600.0   (1 小时)
max_idle             默认 = 600.0    (10 分钟)
reconnect_timeout    默认 = 300.0
num_workers          默认 = 3
max_waiting          默认 = 0
```

> ⚠️ `max_size` 默认是 `None`（不设上限）。但实测 `pool=True` 时得到的是 `max_size=4` —— 因为 `psycopg_pool` 在 `max_size is None` 时会回落到 `min_size`。
> **不要依赖这个行为**，显式写出 `max_size`。

容量估算：

```
总连接数 ≈ (gunicorn worker 数 × max_size)
         + (Celery worker 数 × max_size)
         + 定时任务 / 管理命令的连接

max_size 建议上限 = (DB max_connections − 预留给运维的连接) ÷ 总进程数
```

举例：PG `max_connections = 100`，预留 20 给运维和 psql，web 层 4 个 worker，Celery 4 个 worker：

```
max_size ≤ (100 − 20) ÷ 8 = 10
```

> 💡 **"预留 20" 是怎么来的**：这不是算出来的，是经验值 —— 通常取 `max_connections` 的 **15%~25%**，留给运维连接、`psql` 直连、监控采集、以及迁移期间的额外占用。取太低，故障时你会连不上去排查；取太高，业务连接数不够用。

**什么时候该换外部代理**：把上面的公式反过来用 —— 当 `总进程数 × max_size` 已经超过 `max_connections` 的 **70%** 时，内置池就不够用了。因为池是进程内的，无法在进程间复用，进程越多浪费越大；此时需要 PgBouncer 这类外部代理做跨进程多路复用。

### 3.5 什么时候不该用内置池

内置池是**进程内**复用，不能跨进程多路复用。以下场景仍需要 PgBouncer：

| 场景 | 方案 |
|------|------|
| Django 5.1+ / worker 数可控 | 内置 psycopg 池 |
| Django ≤ 5.0 | 只能调 `CONN_MAX_AGE`，或上 PgBouncer |
| worker / 副本非常多 | 外部代理（PgBouncer transaction 模式） |
| Serverless / 缩容到 0 | 外部代理 + `CONN_MAX_AGE = 0` |

> ⚠️ **与 PgBouncer 混用要关服务端游标**：`DISABLE_SERVER_SIDE_CURSORS = True`，否则 `iterator()` 之类会出问题。

### 3.6 一个容易忽略的泄漏点

内置池上线后，最容易出问题的不是 web 层，而是**自己开的线程和 Celery 任务**。

Django 在请求结束时会自动把连接还回池子；但**请求-response 周期之外**打开的连接（自建线程、管理命令）不会自动归还。没开池时你可能没感觉，开了池之后这些不还的连接会把 `max_size` 耗尽，开始抛 `PoolTimeout`。

处置方式：自建线程里显式 `connections.close_all()`；管理命令里调 `close_old_connections()`。

---

## 回到开场的三个决定

**决定一：给 `status` 加索引，查询没变快、写入变慢了。**
原因有两层：`status` 只有 3 个取值，选择性太差，单列索引价值有限；而索引的写入代价是实打实的。正确做法是按 1.8 的决策清单走一遍 —— 先看 `explain()`，再判断要不要把 `status` 放进复合索引后列，或改成部分索引。如果生产是 PG，记得在 PG 上复验。

**决定二：金额校验写在 Serializer 里，负数进库了。**
Serializer 只保护经过它的那条路径，`bulk_create`、管理命令、数据迁移都绕得过去。正确做法是 `CheckConstraint` 下沉到数据库层 —— 它连裸 SQL 都拦得住。顺带一提，Django 6.1 的 `full_clean()` 也会校验约束，但 DRF 的 Serializer 默认不调 `full_clean()`，所以 DB 层仍是唯一可靠的一层。

**决定三：`max_size=10`，数据库却爆了。**
池是**按进程**算的：4 个 gunicorn worker + 4 个 Celery worker，就是 `8 × 10 = 80` 条，早就超过了预留后的可用额度。正确做法是先算总进程数，再用 3.4 的公式倒推 `max_size`。另外记得别写 `"pool": {}` —— 那会让池静默失效，你以为开了其实没开。

---

## 📊 本课知识点与阶段目标对齐

| 阶段目标 | 本课覆盖 | 验证方式 |
|---------|---------|---------|
| 让索引真正生效 | 部分索引 / 函数索引 / `explain()` 验证 / 选择性 | 实验 1、2、3、11、12 |
| 把校验下沉到数据库 | `CheckConstraint` / `UniqueConstraint(condition=)` / 异常翻译 | 实验 5、6、7 |
| 正确估算连接数 | 三条硬约束 + 第四坑 + 容量公式 | 实验 8、9、13 |
| （代价意识） | 索引拖慢写入 / `index_together` 已移除 | 实验 4、10 |

---

## ⚠️ 高频误区复盘

| 误区 | 真相 | 证据 |
|------|------|------|
| "加了索引查询就一定快" | 要看选择性，且必须用 `explain()` 验证；SQLite 上的结论不能外推到 PG | 实验 2、3 |
| "部分索引肯定会被用上" | SQLite 优化器未必选它，实测需 `INDEXED BY` 强制才生效 | 实验 2b |
| "`email__lower` 可以查小写" | 没有这个 lookup，实测 `FieldError` | 实验 2c |
| "校验写在 Serializer 里就够了" | 可被绕过；DB 约束任何路径都拦得住 | 实验 5a/5b |
| "约束不参与 `full_clean()`" | **6.1 上不成立**，实测三类场景全报错（旧文档遗留） | 实验 5c + 补充验证 |
| "`CheckConstraint(check=...)`" | 6.0 已移除，实测 `TypeError`，要用 `condition=` | 补充验证 |
| "开了池 `max_size=10` 就是 10 条" | 按进程算，4 worker 就是 40 条 | 实验 9 |
| "`pool={}` 用默认配置" | **静默失效**，空字典是 falsy，池根本没启用 | 实验 8b |
| "连接池需要 psycopg3" | 精确门槛是 **3.1.12+**，不是"3" | 源码 + 实验 13 |

---

## 🧪 实验清单

| 实验 | 内容 | 关键结论 |
|------|------|---------|
| 1 | 索引物理形态（`sqlite_master`） | 部分索引带 WHERE、函数索引是表达式 |
| 2 | `explain()` 验证三种索引 | 函数索引需写法精确匹配；部分索引需强制 |
| 3 | 选择性对命中的影响 | SQLite 全命中，结论不可外推至 PG |
| 4 | 写入放大 | 索引越多写入越慢 |
| 5 | `CheckConstraint` 拦截 | 裸 SQL 也拦得住；6.1 的 `full_clean` 也会校验 |
| 6 | 条件唯一约束 | 已取消的记录允许重号 |
| 7 | 异常翻译 | 统一为 `IntegrityError`，靠约束名区分 |
| 8 | 连接池硬约束 | `CONN_MAX_AGE` 互斥；**`pool={}` 静默失效** |
| 9 | 池按进程计算 | 4×10=40 |
| 10 | `index_together` 状态 | 6.1 已移除，直接 `TypeError` |
| 11 | `explain()` 参数 | SQLite 不支持 `format` |
| 12 | 部分索引体积 | 131 KB vs 356 KB（37%） |
| 13 | psycopg 版本门槛 | 3.3.5 / `is_psycopg3=True` / 门槛 3.1.12 |

---

## 📌 本课方法论沉淀

**#21（先跑再写）又一次救场。** 本课有三条断言是"我写下来时才发现问题"的：

1. 我准备写 `email__lower` 作为函数索引的查询写法 —— 跑出来是 `FieldError`，这个 lookup 根本不存在。
2. 我预设"低选择性索引不会被命中" —— 实测 SQLite **全部命中**，预设没复现。我把它如实写成了"SQLite 不可外推"，而不是硬凑一个结论。
3. 我准备写 `pool={}` 表示"用默认配置" —— 实测**静默失效**，池压根没创建。

**#22（区分文档明示与实测）** 在本课出现了**文档与实测冲突**的情况：Django 5.2 文档说约束不参与 `full_clean()`，但 6.1 实测会校验。我以实测为准，并标注了版本差异与源码依据。旧文档的表述对 4.1 之前的版本成立，属于历史遗留。

**#23（实验覆盖断言）** 执行情况：13 个实验覆盖了正文全部结论。唯一一处"结论未复现"（实验 3 的选择性）我保留了原始输出并说明局限，没有删掉或改写。

**实验方法上的一个退让**：课 11 的并发竞态最初被 SQLite 锁污染，本课改用确定性手段。索引实验里同样遇到了 SQLite 优化器不按预期选索引的问题 —— 解法是引入 `INDEXED BY` 强制对比，把"优化器选择"和"索引能力"两件事拆开验证。这是比"跑一次看结果"更可靠的做法。

---

## 🔗 参考

- [Django 模型索引参考](https://docs.djangoproject.com/zh-hans/5.2/ref/models/indexes/)（部分索引、函数索引、各后端限制）
- [Django 约束参考](https://docs.djangoproject.com/en/5.2/ref/models/constraints/)（注意：`full_clean` 相关表述在 6.1 已过时）
- [Django 6.0 release notes](https://docs.djangoproject.com/en/dev/releases/6.0/)（`check` 参数移除、Constraints expose `check()`）
- [psycopg_pool 文档](https://www.psycopg.org/psycopg3/docs/api/pool.html)（`ConnectionPool` 全部参数）
- [Django ticket #35685](https://code.djangoproject.com/ticket/35685)（池与持久连接不兼容的官方讨论）

---

## ✅ 本课自检

1. 部分索引的 DDL 与普通索引差在哪？什么场景下它最划算？
2. 你建了函数索引 `Lower(email)`，查询怎么写才能命中？写 `email__iexact` 行不行？为什么？
3. 为什么说"约束下沉到数据库"是唯一可靠的校验层？举出 3 条绕过 Serializer 的路径。
4. 在 Django 6.1 上，`full_clean()` 会不会校验 `CheckConstraint`？如果你看到相反的说法，可能是什么原因？
5. 启用连接池，`CONN_MAX_AGE` 应该设成多少？设错了会怎样？
6. 写 `"pool": {}` 期望启用默认配置，实际会发生什么？
7. 4 个 gunicorn worker × 4 个 Celery worker，`max_size=10`，PG 侧最多可能看到多少条连接？
8. 为什么 `explain()` 是索引验证的必要步骤，而不是可选步骤？

---

> **下一课预告**：课 13《多数据库与 DB 路由》—— `DATABASE_ROUTERS` 的四个钩子、主从架构的写后读不一致、跨库外键被禁的连锁后果。本课的连接池容量计算，在课 13 的多库场景会更复杂（每个库各有一份池）。
