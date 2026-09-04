# 课 11　查询表达式进阶

> 📖 情节定位：**纵深（一）** —— 很多"必须写循环/必须加锁"的场景，其实一条查询就能解决
> 🎯 本课目标：用表达式把计算推给数据库，减少往返与竞态
> 🔗 承接：阶段 2 的 queryset 与 serializer
> 🔗 收尾：本課的结论是阶段 5「N+1 治理」的直接基础

---

## 第一幕 · 场景引入

运营找过来说：商品详情页的**阅读数不准**。

你查了下日志，接口确实被调用了几百次，但数据库里的 `view_count` 只有几十。你翻出代码：

```python
def detail(request, pk):
    product = Product.objects.get(pk=pk)
    product.view_count += 1
    product.save()
    return Response(ProductSerializer(product).data)
```

"这没问题啊"，你想。

**与此同时，客服转来一个投诉**：用户说秒杀商品明明显示有货，下单后却被告知库存不足——而另一个用户却买到了最后一件，还多卖出去一单。

你又看了眼扣库存的代码：

```python
if product.stock > 0:
    product.stock -= 1
    product.save()
```

"这也没问题啊"，你又想。

**第三个问题是性能**：订单列表页要展示每个商品的"已付款销量"，你写了个循环：

```python
for product in products:
    product.paid_qty = product.orders.filter(status="paid").count()
```

本地 4 个商品秒开。上线后 2000 个商品，页面转了 8 秒。

**这三个问题的根因是同一个**：你把本该数据库做的算术，搬到了 Python 里做。

- 阅读数不准 → 自增在 Python 里做，**并发时互相覆盖**
- 库存超卖 → 判断在 Python 里做，**判断与写入之间有时间差**
- 列表很慢 → 聚合在 Python 里做，**每条数据一次查询**

这一课就是把这三件事推回数据库。

---

## 第二幕 · 认知困惑

### 困惑一：`obj.count += 1` 看着原子，实际是三步

在 Python 里 `x += 1` 确实是一条语句。但 `obj.count += 1` 落到 ORM 上是：

```text
① SELECT count FROM product WHERE id=1;   ← 读到 Python 内存
② count = count + 1                        ← 在 Python 里加
③ UPDATE product SET count=... WHERE id=1; ← 写回
```

**两个请求交错执行时，后写的会覆盖先写的。**

### 困惑二：那加个 `transaction.atomic()` 或者加锁不就行了？

很多人的第一反应。但：

- **`transaction.atomic()` 不解决这件事**。默认隔离级别下，两个事务都能读到同一个旧值，然后都基于它算——照样丢失更新。
- **加锁能解决，但代价高**，而且有个隐蔽的坑（后面会讲）：`select_for_update()` 在 SQLite 上是**静默失效**的，本地测不出来。

真正的答案是：**让自增在数据库内部发生，从根上消除那个窗口**。

### 困惑三：`Q()` 不就是 `filter()` 的另一种写法吗？

大部分时候是的，但有两个场景它不可替代：

- 需要 **OR / NOT** 语义时（`filter(a, b)` 只有 AND）
- 需要**动态拼装**条件时（筛选参数可能为空）

而且 `Q()` 在多值关系上有个反直觉的行为，单靠链式 `filter()` 想当然会写错。

### 困惑四：循环查关联数据，用 `prefetch_related` 不就够了？

`prefetch_related` 解决的是"**把关联对象取回来**"，而本課的场景是"**要一个聚合结果**"（销量总和、订单数量）。

后者用 `Subquery` + `annotate` 只需要 **1 次查询**，`prefetch_related` 要 2 次且还得在 Python 里算。

---

## 第三幕 · 层层揭示

### 知识点 1：F() 表达式与原子更新

#### 竞态是怎么产生的

看一个**不依赖线程、100% 可复现**的演示——模拟两个请求交错：

```text
① 请求 A 读到 view_count = 0
② 请求 B 读到 view_count = 0   ← 和 A 读到的一样
③ 请求 A 算出 1 并写回
④ 请求 B 算出 1 并写回         ← 把 A 的结果覆盖了

期望 view_count = 2（两次自增）
实际 view_count = 1
❌ 丢失更新 1 次
```

**根因**：`obj.view_count += 1` 是**三步**，不是一步。两个请求的 ① 都发生在对方的 ③ 之前。

多线程版本更能体现真实并发（5 个线程用 Barrier 卡住）：

```text
各线程读到的值 = [0, 0, 0, 0, 0]   ← 全都一样
实际结果 = 1（期望 5），丢失 4 次
```

> ⚠️ **注**：多线程版在 SQLite 上会报 `database is locked`（SQLite 的锁机制，PostgreSQL/MySQL 不会）。**本地复现时看到这个异常是正常的，不是你跑错了**——它恰恰说明 SQLite 把并发写挡住了，但**挡不住丢失更新本身**。
>
> 这也解释了为什么本課把**确定性演示（1a）放在前面**：多线程版混着锁异常，论证不够干净。1a 不依赖线程、不产生锁竞争，机制暴露得更纯粹。

#### F() 怎么解决

```python
from django.db.models import F

Product.objects.filter(pk=pk).update(view_count=F("view_count") + 1)
```

它生成的 SQL 是：

```sql
UPDATE "shop_product"
   SET "view_count" = ("shop_product"."view_count" + %s)
 WHERE "shop_product"."id" = %s
-- 参数: (1, 1)
```

**关键在 SET 子句**：`view_count = view_count + 1` 是数据库内部对自己当前值的自增，不存在"读出来、加一、写回去"的窗口。

实测对照（同样 5 个线程、同样用 Barrier 同步）：

```text
读-改-写（Python 侧）  -> 1/5   丢失 4 次
F() 表达式（数据库侧） -> 5/5   丢失 0 次
```

#### F() 还能用在哪些地方

**比较同一行的两个字段**（`filter` 里也能用）：

```python
Product.objects.filter(stock__lt=F("like_count"))
# WHERE stock < like_count
```

**跨字段更新**（用同一行另一个字段的值）：

```python
Product.objects.update(price=F("price") * 2)              # 价格翻倍
Product.objects.update(view_count=F("like_count"))        # 用点赞数覆盖阅读数
Product.objects.filter(view_count=0).update(
    view_count=F("like_count") * 2
)                                                          # 可以带条件
```

**还能和 `Case/When` 组合，一条 SQL 做差异化更新**：

```python
Product.objects.update(
    view_count=Case(
        When(view_count__lt=10, then=F("view_count") + 100),
        default=F("view_count") + 1,
        output_field=IntegerField(),
    )
)
```

```text
update() 影响 4 行
机械键盘    view_count = 105   （原值 5，<10  → +100）
无线鼠标    view_count = 51    （原值 50，≥10 → +1）
Django 实战 view_count = 100   （原值 0， <10  → +100）
已下架商品   view_count = 100   （原值 0， <10  → +100）
```

一条 SQL 完成"不同条件更新成不同的值"，不需要循环、不需要取出对象。

> 📌 **F() 不能跨行引用**。`F("other_row.price")` 是不行的——它永远是"**当前行**的这个字段"。要跨行请用 `Subquery`。
>
> ⚠️ 另外注意：`update()` 时 `F()` 引用的是**数据库里那一行的当前值**，不是你 Python 内存里的对象值。这是它能做到原子的原因，也是它和你手上对象不同步的原因。

#### 更新后取回新值

这是最容易踩的一脚：**`update()` 不会同步你手上那个对象**。

```text
【4a】❌ update() 之后直接用内存里的旧对象
  内存中 p1.view_count = 5   ← 没变，还是旧值
  数据库中实际值      = 10
```

**正确姿势**：

```python
Product.objects.filter(pk=pk).update(view_count=F("view_count") + 1)
product.refresh_from_db()        # ✅ 唯一稳的写法
```

**只想刷新一个字段时**，可以指定 `fields`：

```python
product.refresh_from_db(fields=["view_count"])
```

实测（两个都是 1 次查询，但 SELECT 的列不同）：

```text
refresh_from_db()             SELECT id, name, category_id, stock, price, like_count, view_count, ...
refresh_from_db(fields=[...]) SELECT id, view_count FROM shop_product WHERE id = 1
```

> 📌 **别指望它能省查询次数**——两者都是 1 次。它的价值在于**少传列**：字段多、或者有大字段（`TextField`/`JSONField`）时，只刷需要的那列能省下明显的序列化与传输开销。
>
> ⚠️ 另一个副作用：`refresh_from_db()` 会**清空已缓存的关联对象**。如果你后面还要用 `product.category`，最好一起放进 `fields`，否则会再触发一次查询。

关于 `update()` 的返回值，有个常见误会：

```text
【4c】update() 返回 = 1（受影响行数，不是新值）
```

它告诉你**影响了几行**，不是新值是多少。但**这个返回值非常有用**——见下面库存扣减。

#### 库存扣减：把判断也推给数据库

**❌ 先看后扣（会超卖）**——确定性演示：

```text
库存设为 1，两个请求同时下单：
  ① 请求 A 读到 stock = 1，判断 > 0，准备扣减
  ② 请求 B 读到 stock = 1，判断 > 0，准备扣减
  ③ 请求 A 扣减后写回 stock = 0
  ④ 请求 B 扣减后写回 stock = 0   ← 覆盖了 A 的结果
最终库存 = 0
⚠️ 库存只有 1 件却卖出了 2 单 —— 这就是超卖
```

**✅ 判断和更新放进同一条 SQL**：

```python
rows = Product.objects.filter(pk=pk, stock__gt=0).update(stock=F("stock") - 1)
if rows == 0:
    raise OutOfStock("库存不足")
```

```text
请求 A：update() 返回 1  (扣减成功)
请求 B：update() 返回 0  (库存不足，未扣)
最终库存 = 0
✅ 未超卖
```

**这条写法的三个要点**：

1. `stock__gt=0` 把"还有货吗"这个判断放进 WHERE，由数据库在更新的同一刻判定
2. `F("stock") - 1` 让扣减在数据库内部发生
3. **返回值就是业务结果**——`1` 表示扣到了，`0` 表示没货

> 📌 第 3 点很关键：很多人另外发一条 `SELECT` 去查库存，那就又多了一次往返，而且重新引入了时间差。

#### F() vs select_for_update：怎么选

| | `F()` | `select_for_update()` |
|---|---|---|
| SQL | 1 条 UPDATE | SELECT ... FOR UPDATE + UPDATE |
| 加锁 | ❌ 不加锁 | ✅ 行锁，阻塞其他事务 |
| 适合 | 纯算术（+1、扣库存） | **读到的值要参与复杂业务判断** |
| 吞吐 | 高 | 低（串行化） |

经验法则：**能用 `F()` 就用 `F()`**。只有当"新值依赖读到的旧值做非算术判断"时，才需要锁。

**一个可执行的判断标准**——问自己一句话：

```text
新值能不能表示成「旧值 + 一段算术」？

能   → 用 F()
       view_count + 1、stock - 1、price * 2 ... 都是

不能 → 才考虑加锁
       例如"根据当前库存决定下一步状态"：
       读到 stock=0 要下架、stock<10 要补货提醒、否则正常
       ——这种"读值 → 分支判断 → 决定写什么"的流程，F() 表达不了
```

> 📌 注意第二种情况的前提：**判断结果要写回数据库**。如果判断只影响返回值（比如决定给用户看什么文案），那用 `Case/When` 在查询时算就行，连锁都不需要。

#### 🔴 坑：select_for_update 在 SQLite 上静默失效

这是本課最有价值的发现之一。

```text
connection.features.has_select_for_update = False
connection.vendor = sqlite

执行"成功"，view_count = 31
SQL 里含 FOR UPDATE 吗？False
```

**源码依据**（`django/db/models/sql/compiler.py:840`）：

```python
if self.query.select_for_update and features.has_select_for_update:
    ...
    for_update_part = self.connection.ops.for_update_sql(...)
```

SQLite 的 `features.py` **没有覆写** `has_select_for_update`（基类默认 `False`），所以整个 if 块被跳过——**不报错，SQL 里也没有 FOR UPDATE 子句**。

> ⚠️ **这个坑的隐蔽之处在于**：本地用 SQLite 开发时，`select_for_update()` 看起来一切正常、测试全绿，但实际**根本没加锁**。上线换成 PostgreSQL 后行为才生效，可能暴露出之前被掩盖的并发问题。
>
> **对策**：涉及锁的代码，务必在与生产同类型的数据库上验证。别指望 SQLite 能测出锁相关的行为。

---

### 知识点 2：Q() 对象与复杂条件组合

#### 四种组合

```python
from django.db.models import Q

Product.objects.filter(Q(stock__gt=0) & Q(is_active=True))   # AND
Product.objects.filter(Q(stock__gt=0), Q(is_active=True))    # AND（逗号等价）
Product.objects.filter(Q(stock__gt=0) | Q(like_count__gte=20))  # OR
Product.objects.filter(~Q(is_active=True))                     # NOT
```

实测：

```text
Q(a) & Q(b)   -> 1 件  ['机械键盘']
Q(a), Q(b)    -> 1 件  （逗号等价于 AND，结果一致：True）
Q(a) | Q(b)   -> 3 件  ['机械键盘', 'Django 实战', '已下架商品']
~Q(条件)      -> 1 件  ['已下架商品']
```

#### 优先级坑

```python
Product.objects.filter(Q(a) | Q(b), c)          # ✅ 等价于 (a OR b) AND c
Product.objects.filter((Q(a) | Q(b)) & Q(c))    # ✅ 显式写法，更清楚
```

实测两者结果一致。**但有个语法约束**：`Q()` 参数必须写在关键字参数**之前**，否则是语法错误：

```python
filter(is_active=True, Q(stock__gt=0))    # ❌ SyntaxError
filter(Q(stock__gt=0), is_active=True)    # ✅
```

#### 动态构建：从空 Q() 起手

列表接口的筛选参数可能为空，用 `Q()` 逐步拼装最干净：

```python
def search_products(keyword=None, min_stock=None, categories=None, tags=None):
    q = Q()
    if keyword:
        q &= Q(name__icontains=keyword)
    if min_stock is not None:
        q &= Q(stock__gte=min_stock)
    if categories:
        q &= Q(category__slug__in=categories)
    if tags:
        q &= Q(tags__name__in=tags)
    return Product.objects.filter(q).distinct()
```

实测：

```text
空条件（全部）        -> 4 件
keyword='键'          -> 1 件
min_stock=10          -> 2 件
categories=['books']  -> 2 件
tags=['热销']          -> 2 件
组合：热销 + 有库存    -> 1 件
```

OR 语义用 `|=`：

```python
def search_any(keyword=None, tag_names=None):
    q = Q()
    if keyword:
        q |= Q(name__icontains=keyword)
    if tag_names:
        q |= Q(tags__name__in=tag_names)
    return Product.objects.filter(q).distinct()
```

> 📌 **注意 `Q()` 空对象的安全边界**：`Q()` 是**恒真**，所以 `Product.objects.filter(Q())` 返回全部。这正好符合"没有筛选条件就返回全部"的语义，可以直接用。
>
> 但如果你要做的是"条件都没给就返回空"，那就得显式判断，别指望 `Q()` 帮你。

#### ⚠️ 多值关系的 AND 陷阱

这是 `Q()` 最容易踩的坑，而且**两种写法的语义完全相反**：

```text
链式 filter(热销).filter(新品) -> 1 件  ['机械键盘']
Q(热销) & Q(新品)             -> 0 件  []
```

为什么会这样？关键在于 **JOIN 的次数**：

- **链式 `filter().filter()`** 对多值关系是**两次 JOIN**，语义是"存在一个叫热销的 tag，**并且**存在另一个叫新品的 tag"——查的是"同时拥有这两个标签的商品"，这正是我们通常想要的。
- **`Q(a) & Q(b)` 在同一条 `filter()` 里**只做**一次 JOIN**，要求**同一个 tag 行**同时满足两个条件——一个 tag 不可能同时叫两个名字，所以永远是 0 件。

> 📌 **实践结论**：要"同时拥有多个标签"这种语义，用**链式 `filter()`**；`Q(a) & Q(b)` 在这里是陷阱，不是等价写法。

---

### 知识点 3：子查询、条件表达式与聚合

#### Subquery + OuterRef：一条查询替代 N 条

给每个商品标注"已付款订单的总销量"：

```python
from django.db.models import OuterRef, Subquery, Sum, IntegerField
from django.db.models.functions import Coalesce

paid_qty = (
    Order.objects.filter(product=OuterRef("pk"), status="paid")
    .values("product")                      # ← 关键：分组
    .annotate(total=Sum("quantity"))
    .values("total")
)

products = Product.objects.annotate(
    paid_qty=Coalesce(Subquery(paid_qty, output_field=IntegerField()), Value(0))
)
```

实测：

```text
机械键盘     已付款销量 = 3
无线鼠标     已付款销量 = 3
Django 实战  已付款销量 = 0
已下架商品    已付款销量 = 0
```

**三个必须注意的细节**：

1. **`OuterRef("pk")`** — 引用外层查询的当前行。这是子查询与主查询的**唯一**连接点。
2. **`.values("product")` 分组** — 最容易漏的一步。漏了会怎样？实测：

```text
去掉 .values('product') 分组后：[2, 3, None, None]
❌ 所有商品拿到的是同一个总数（没有按商品分组）
```

注意这里的结果很诡异——不只是"都拿到总数"，而是每行值还不一样（2 和 3）。因为去掉分组后 SQLite 返回的是匹配到的**任意一行**，不是聚合值。**这是静默的错误结果，不会报错。**

3. **`Coalesce(..., 0)`** — 没有匹配时子查询返回 `NULL`，`Coalesce` 把它变成 `0`。不加的话前端要处理 `null`。

> 📌 **关于 `output_field`**：`Subquery(..., output_field=IntegerField())` 这个类型标注到底要不要写？**实测结论是本課能省略**：
>
> ```text
> Subquery + Sum，省略 output_field -> 执行成功，结果 [3, 3, None, None]
> Subquery + Count，省略 output_field -> 执行成功，结果 [3, 2, None, None]
> ```
>
> 因为内层用了 `Sum` / `Count` 这类聚合函数，Django 能从中推断出输出类型。
>
> **但下面这些情况推断不出来，必须手写**：
> - 子查询里是普通字段而非聚合（`Subquery(Order.objects.filter(...).values("quantity"))`）
> - 用了 `Coalesce` 等包装后类型信息丢失
> - 结果要做算术运算或跨类型比较
>
> 稳妥做法：**拿不准就显式写**。写错类型会静默产生错误结果，写对了则零成本。

4. **子查询只能返回一行一列**。如果内层查询可能返回多行，数据库会报错（SQLite 是取任意一行，MySQL 可能报 `Subquery returns more than 1 row`）。这也是为什么内层要 `.values("product")` 分组。

#### Exists：只要判断"有没有"

```python
from django.db.models import Exists, OuterRef

Product.objects.annotate(
    has_cancelled=Exists(Order.objects.filter(product=OuterRef("pk"), status="cancelled"))
)
```

```text
机械键盘     有取消订单 = False
无线鼠标     有取消订单 = True
```

> 📌 `Exists` 生成 `EXISTS(SELECT 1 ...)`，**数据库找到第一条就停止**。而 `Subquery + Count` 要扫完全部匹配行。只要判断有无，一律用 `Exists`。

#### Case / When：把 if-else 推给数据库

```python
from django.db.models import Case, When, Value, CharField

Product.objects.annotate(
    stock_level=Case(
        When(stock=0, then=Value("缺货")),
        When(stock__lt=10, then=Value("紧张")),
        When(stock__lt=50, then=Value("充足")),
        default=Value("充裕"),
        output_field=CharField(),
    )
)
```

⚠️ **顺序很重要**（短路匹配）：

```text
商品          库存   正确顺序   错误顺序
机械键盘       100   充裕      充裕
无线鼠标       0     缺货      充足    ← ❌
Django 实战    0     缺货      充足    ← ❌
已下架商品      50    充裕      充裕
```

错误顺序把 `When(stock__lt=50, ...)` 放在最前面，库存 0 也满足 `< 50`，于是"缺货"永远匹配不到。

> 📌 **写 `Case/When` 要从最严格到最宽松**。

`Case` 还能用在 `filter` / `aggregate` 里：

```text
filter(is_hot=1)  -> 1 件  ['Django 实战']
aggregate 求和    -> {'hot_total': 1}
```

#### 聚合：aggregate vs annotate

| | `aggregate()` | `annotate()` |
|---|---|---|
| 返回 | 一个**字典** | 一个 **QuerySet** |
| 语义 | 整表聚合成一行 | **逐行**聚合，结果挂到每个对象上 |
| 终止 queryset | ✅ 是 | ❌ 否，可继续 filter |

```text
【11a】aggregate：{'total_stock': 150, 'avg_price': Decimal('221.5'), 'max_like': 25, 'count': 4}
【11b】annotate：机械键盘 订单数 = 3 / 无线鼠标 2 / Django 实战 0 / 已下架商品 0
```

**分组聚合**用 `values().annotate()`：

```text
{'category__name': '图书', 'n': 2, 'total_stock': 50}
{'category__name': '电子产品', 'n': 2, 'total_stock': 100}
```

> 📌 `values()` 写在 `annotate()` **之前**才是分组；写在之后就只是"取这几个字段"。位置决定了语义。

#### ⚠️ Count 的多值关系陷阱：只对**一个**多值关系时看不出来

先看只 JOIN 一张表的情况：

```python
Product.objects.annotate(n=Count("orders"))
Product.objects.annotate(n=Count("orders", distinct=True))
```

```text
商品           Count(orders)   Count(distinct=True)
机械键盘        3               3
无线鼠标        2               2
Django 实战    0               0
已下架商品      0               0
```

**两者相同**——只 JOIN 一张表时不会重复。这也是很多人以为"不用加 distinct"的原因。

🔴 **真正会翻车的是同时对两个多值关系做 `annotate`**：

```python
Product.objects.annotate(
    n_orders=Count("orders"),
    n_tags=Count("tags"),
)
```

```text
商品           Count(orders)   Count(tags)   正确值
机械键盘        6               6             订单3/标签2  ❌
无线鼠标        2               2             订单2/标签1  ❌
Django 实战    0               1             订单0/标签1
已下架商品      0               0             订单0/标签0
```

机械键盘有 3 个订单、2 个标签，两个 Count **都变成了 6**——因为两个 JOIN 产生笛卡尔积，数的是"JOIN 后的行数 3×2=6"，而不是各自的行数。

**解法**：

```python
Product.objects.annotate(
    n_orders=Count("orders", distinct=True),   # ✅
    n_tags=Count("tags", distinct=True),       # ✅
)
# 加上 distinct=True 后全部正确：True
```

> 📌 **安全习惯**：对多值关系做 `Count` 时**总是加 `distinct=True`**。只 JOIN 一张表时加不加都一样，一旦将来又加了一个多值关系的 annotate，没加的那次就会静默变成笛卡尔积——**不报错，只是数字变大**。

#### Django 6.1 新增：UUID4 / UUID7 / JSONNull / 位聚合

官方 release notes 原文：*"The new BitAnd, BitOr, and BitXor aggregates return the bitwise AND, OR, XOR, respectively. These aggregates were previously included only in contrib.postgres."*

**实测结果**（环境：Django 6.1 / Python 3.13.14 / SQLite）：

```text
函数            导入位置                        本机能跑吗
UUID4         django.db.models.functions  ✅ 可以
UUID7         django.db.models.functions  ❌ NotSupportedError
JSONNull      django.db.models（不是 functions）✅ 可以
BitAnd/Or/Xor django.db.models            ✅ 可以
```

**① `UUID4` / `UUID7` —— 数据库侧生成 UUID**

```python
from django.db.models.functions import UUID4, UUID7

Product.objects.annotate(u=UUID4()).first().u
# -> be1fcaa2-4556-4e5d-ba75-71c8c281500c
```

⚠️ **UUID7 有版本门槛**，实测报错：

```text
NotSupportedError: UUID7 on SQLite requires Python version 3.14 or later.
```

源码依据（`functions/uuid.py:75`）：SQLite 上的 `UUID7` 靠注册 Python 的 `uuid.uuid7()` 实现，而 **`uuid.uuid7()` 是 Python 3.14 才加入标准库的**。本机 3.13.14 → 不满足。

其他后端的限制（源码 `functions/uuid.py`）：

| 后端 | 要求 |
|------|------|
| PostgreSQL | 18+ |
| SQLite | Python 3.14+ |
| MariaDB | 11.7+ |
| MySQL | ❌ 不支持 |

> 📌 **UUID7 的价值**：按 RFC 9562 §5.7 定义，前 48 位是 **Unix 毫秒时间戳**（大端），因此天然时间有序。作为主键时，B-tree 索引的新记录总是追加在末尾，局部性远好于完全随机的 UUID4（随机 UUID 会 scatter 到索引各处，导致页分裂与碎片）。
>
> **但有两个代价要清楚**：
>
> 1. **环境门槛较高**——SQLite 要 Python 3.14、PG 要 18+、MariaDB 要 11.7+，MySQL 不支持。
> 2. **泄露创建时间**——任何人拿到这个 UUID 都能解出毫秒级创建时间戳。如果 ID 会出现在用户可见的 URL 里、且创建时间属于敏感信息，应该用 UUID4。用于内部主键则通常无所谓（`created_at` 字段本来就有）。

**② `JSONNull` —— 注意导入位置**

```python
from django.db.models import JSONNull        # ✅ 正确
from django.db.models.functions import JSONNull   # ❌ ImportError
```

实测：从 `functions` 导入会失败，**它在 `django.db.models`**（定义于 `expressions.py:1244`）。

**为什么需要它**：SQL 的 `NULL` 表示"没有值"，而 JSON 的 `null` 是一个**有效值**。往 `JSONField` 里写"空"时两者语义完全不同。

Django 6.1 里 `Value(None)` 在 JSON 场景下已被废弃（源码 `fields/json.py:324` 的提示：*"mean JSON scalar 'null' is deprecated. Use JSONNull() instead"*），改用 `JSONNull()`。

**③ `BitAnd` / `BitOr` / `BitXor` —— 从 contrib.postgres 提升为通用聚合**

此前只有 PostgreSQL 能用，6.1 起 MySQL / SQLite 也能用。实测（SQLite）：

```text
view_count 取值：[6, 6, 3]
BitAnd -> 2  (6 & 6 & 3 = 2)
BitOr  -> 7  (6 | 6 | 3 = 7)
BitXor -> 3  (6 ^ 6 ^ 3 = 3)
✅ 位聚合在 SQLite 上实测通过
```

典型用途：权限位掩码的批量计算、状态标志位的聚合统计。

> 📌 **不是所有"6.1 新增函数"都能无脑用**。UUID7 受后端与 Python 版本双重限制，用之前先确认环境——这是本課实测才发现的。

#### 🎁 顺带发现：6.1 的 fetch_mode 是 N+1 的官方解法

查资料时发现 6.1 还有一个与本課主题直接相关的重磅特性：

```python
from django.db import models

# FETCH_PEERS：把多数 N+1 场景压缩到 2 条查询
books = Book.objects.fetch_mode(models.FETCH_PEERS)
for book in books:
    print(book.author.name)      # 首次访问时一次性取回所有 author

# FETCH_RAISE：把意外的 N+1 变成硬错误
books = Book.objects.fetch_mode(models.FETCH_RAISE)
```

三种模式：

| 模式 | 行为 |
|------|------|
| `FETCH_ONE` | 默认，只取当前实例的字段（现有行为） |
| `FETCH_PEERS` | 一次取回同 queryset 所有实例的该字段，相当于**按需的 prefetch_related** |
| `FETCH_RAISE` | 访问未取字段时抛 `FieldFetchBlocked`，**让 N+1 在测试期就暴露** |

> 📌 这个特性属于**阶段 5「性能与异步」**的范畴，本課不展开，但值得先记一笔——它是 N+1 问题的框架级解法，比手工维护 `prefetch_related` 列表省心得多。

---

## 第四幕 · 实操验证

### 验证环境

| 组件 | 版本 | 说明 |
|------|------|------|
| Python | 3.13.14 | Windows 托管（`dj-course` venv） |
| Django | 6.1 | 课程基线版本 |
| 数据库 | SQLite | 实验工程自带，随脚本重建 |

实验工程在仓库外的临时目录（`%TEMP%/dj-lesson11-demo/query_lab`），运行 `python run_lab.py` 一键复现全部结论。

### 实验 1：竞态复现

```text
【1a】确定性演示（不依赖线程，100% 可复现）
  ① A 读到 0  ② B 读到 0  ③ A 写回 1  ④ B 写回 1（覆盖）
  期望 2，实际 1，丢失 1 次

【1b】多线程版（5 线程 + Barrier）
  各线程读到的值 = [0, 0, 0, 0, 0]
  实际 1（期望 5），丢失 4 次
  ⚠️ SQLite 会报 database is locked（锁机制，非丢失更新本身）
```

### 实验 2：F() 原子更新

```text
同样 5 线程 + Barrier：实际 5/5，丢失 0 次
对比：读-改-写 1/5  vs  F() 5/5
```

### 实验 3：F() 的 SQL

```sql
UPDATE "shop_product" SET "view_count" = ("shop_product"."view_count" + %s)
 WHERE "shop_product"."id" = %s        -- 参数 (1, 1)
```

### 实验 4：更新后取回新值

```text
update() 后内存对象仍是旧值（5），数据库已是 10
refresh_from_db() 后拿到 20
update() 返回 1 —— 是受影响行数，不是新值
```

### 实验 5：库存扣减

```text
【5a】先看后扣：库存 1，两个请求都读到 1，都扣成功 → 超卖
【5b】filter(stock__gt=0) + F()：返回 1 / 0 → 未超卖
【5c】update() 返回值：1 1 0 0（库存 2，扣 4 次）
【5d】🔴 select_for_update 在 SQLite 上静默失效
      has_select_for_update = False
      生成的 SQL 里没有 FOR UPDATE（compiler.py:840）
```

### 实验 6-8：Q() 组合

```text
AND / 逗号 / OR / NOT 四种组合均验证
混合写法的两种形式等价：True
动态构建（AND 与 OR 两种语义）均验证
多值关系陷阱：链式 filter 得 1 件，Q()&Q() 得 0 件
```

### 实验 9：Subquery

```text
带 .values('product') 分组：[3, 3, 0, 0]  ✅
去掉分组：[2, 3, None, None]            ❌ 静默错误
Exists：判断有无，找到第一条即停
```

### 实验 10：Case/When

```text
正确顺序：缺货 / 紧张 / 充足 / 充裕 各自命中
错误顺序（宽松条件在前）：库存 0 被判为"充足"  ❌
```

### 实验 11：聚合

```text
aggregate: {'total_stock': 150, 'avg_price': Decimal('221.5'), 'max_like': 25, 'count': 4}
annotate:  逐行订单数 3 / 2 / 0 / 0
values().annotate() 分组：图书 2 件、电子产品 2 件
Count 陷阱：只 JOIN 一张表时 3/3、2/2（看不出问题）
          同时对 orders + tags 两个多值关系 annotate → 都变成 6（3 单 × 2 标签）
          加 distinct=True 后全部正确：True
```

### 实验 12：6.1 新增函数

```text
UUID4    ✅ be1fcaa2-4556-4e5d-ba75-71c8c281500c
UUID7    ❌ NotSupportedError: requires Python 3.14 or later
JSONNull ✅ 在 django.db.models（不在 functions）
BitAnd/Or/Xor ✅ 2 / 7 / 3（SQLite 实测通过）
```

### 实验 13：查询次数对比

```text
循环自增 5 次          -> 10 次查询
F() 自增 5 次          -> 1 次查询
循环查 4 个商品销量     -> 5 次查询（N+1）
Subquery 一次算完       -> 1 次查询
```

### 附：实验工程结构

```text
query_lab/
├── manage.py
├── config/
│   ├── settings.py     # SQLite，SQL 日志设为 WARNING（避免淹没输出）
│   ├── urls.py
│   └── wsgi.py
└── apps/
    └── shop/
        ├── models.py   # Category / Tag / Product / Order / InventoryLog
        └── migrations/
```

`models.py` 的关键字段：

| 模型 | 用于演示 |
|------|---------|
| `Product.stock` / `like_count` / `view_count` | 知识点 1：F() 自增与库存扣减 |
| `Product.tags`（M2M） | 知识点 2：多值关系的 AND 陷阱 |
| `Product.category`（FK） | 知识点 2：跨关系查询、动态筛选 |
| `Order.product` / `status` / `quantity` | 知识点 3：Subquery、Exists、聚合 |

---

## 第五幕 · 体系收束

### 你现在会了什么

1. **说出 `obj.count += 1` 的三步分解**，并知道丢失更新是怎么发生的
2. **用 `F()` 把自增推给数据库**，消除读-改-写窗口
3. **用 `update()` 的返回值做业务判断**（库存扣减是否成功）
4. **知道 `select_for_update` 在 SQLite 上静默失效**——本地测不出来
5. **用 `Q()` 拼 AND/OR/NOT**，并从空 `Q()` 起手动态构建
6. **避开多值关系的 AND 陷阱**（链式 filter vs `Q() & Q()`）
7. **用 `Subquery` + `OuterRef` 把 N 条查询压成 1 条**，并记得 `.values()` 分组
8. **用 `Case/When` 把 if-else 推给数据库**，且知道顺序要从严到宽
9. **区分 `aggregate` 与 `annotate`**，知道 `values()` 位置决定是分组还是取字段
10. **了解 6.1 的 UUID4/UUID7/JSONNull/位聚合**，以及它们各自的导入位置与环境门槛

### 一图总结

```text
问题：把算术搬到了 Python 里
        │
   ┌────┼────────────────┐
 不准   超卖              慢
   │     │                │
 并发覆盖  判断与写入有窗口  每条数据一次查询
   │     │                │
 F() 自增  filter(cond)   Subquery/annotate
 +F() 更新  + F() 更新     聚合一次算完
   │     │                │
 1 条 SQL  1 条 SQL        1 条 SQL（原 N 条）
   └────┴────────────────┘
        │
   共同前提：让数据库干活，别在 Python 里搬数
```

### 三个取舍速查

| 场景 | 用 | 别用 |
|------|-----|------|
| 纯算术自增 | `F()` | `select_for_update`（慢、且 SQLite 静默失效） |
| 读到的值要做复杂判断 | `select_for_update`（PostgreSQL 上） | `F()`（表达不了） |
| 判断"有没有"关联记录 | `Exists` | `Subquery + Count`（要扫全） |
| 动态筛选 | 从空 `Q()` 起手 `&=` | 链式 `filter()`（多一次查询） |
| 多值关系"同时满足多个" | 链式 `filter()` | `Q(a) & Q(b)`（永远是 0） |

### 埋下的伏笔

- **N+1 的系统治理**：本課用 `Subquery` 解决了聚合类 N+1，关联对象类 N+1 要靠 `select_related` / `prefetch_related`，6.1 还新增了 `fetch_mode` → **课 15**
- **索引为什么没生效**：`F()` 与 `Subquery` 生成的 SQL 复杂，索引能不能命中要看 `explain()` → **课 12**
- **约束下沉**：本課在应用层保证了不超卖，但真正的兜底要放到数据库 → **课 12**
- **连接池**：本課的查询次数直接影响连接占用时长 → **课 12**

### 阶段 4 进度

| 课 | 主题 | 状态 |
|----|------|------|
| 课 11 | 查询表达式进阶 | ✅ 已完成（本课） |
| 课 12 | 索引、约束与连接池 | ⬜ 未开始 |
| 课 13 | 多数据库与 DB 路由 | ⬜ 未开始 |
| 课 14 | 迁移工程 | ⬜ 未开始 |

---

## 🐞 本课误区速查

| 误区 | 真相 |
|------|------|
| "`obj.count += 1` 是原子操作" | 是**三步**：SELECT → Python 加一 → UPDATE。并发时互相覆盖 |
| "包个 `transaction.atomic()` 就安全了" | 默认隔离级别下两个事务都会读到同一个旧值，照样丢失更新 |
| "`update()` 会更新我手上的对象" | **不会**。必须 `refresh_from_db()` |
| "`update()` 返回新值" | 返回的是**受影响行数**。但它可以用来判断扣减是否成功 |
| "扣库存先 `if stock > 0` 判断一下就行" | 判断与写入之间有窗口。要把条件放进 `filter()` |
| "`select_for_update()` 在哪都能用" | **SQLite 上静默失效**——不报错，SQL 里也没有 FOR UPDATE |
| "`Q(a) & Q(b)` 和链式 filter 等价" | 多值关系上**完全相反**：前者一次 JOIN 永远 0 件，后者两次 JOIN 才对 |
| "Subquery 里 `.values()` 加不加都行" | 不加会拿到**静默错误**的结果（不是报错，是错值） |
| "Case/When 顺序随便写" | **短路匹配**，宽松条件放前面会吃掉严格条件 |
| "`Count("orders")` 数出来的就是订单数" | 单个多值关系时没问题；**同时 annotate 两个多值关系**会变笛卡尔积（3 单×2 标签 → 两个 Count 都是 6）。加 `distinct=True` |
| "`values().annotate()` 和 `annotate().values()` 一样" | 前者是**分组聚合**，后者只是取字段 |
| "6.1 新增的函数都能直接用" | `UUID7` 要求 Python 3.14（SQLite）/ PG 18 / MariaDB 11.7，MySQL 不支持 |
| "`JSONNull` 在 `models.functions` 里" | 在 **`django.db.models`**（`expressions.py:1244`），从 functions 导入会失败 |
| "F() 可以引用别的行的字段" | 只能引用**当前行**的字段。跨行请用 `Subquery` |

---

## 📚 官方文档

| 主题 | 链接 | 说明 |
|------|------|------|
| Django · Query Expressions | https://docs.djangoproject.com/en/6.1/ref/models/expressions/ | F() / Subquery / Exists / Case-When 权威说明 |
| Django · QuerySet API | https://docs.djangoproject.com/en/6.1/ref/models/querysets/ | `update()` / `select_for_update()` / 聚合方法 |
| Django · Aggregation | https://docs.djangoproject.com/en/6.1/topics/db/aggregation/ | aggregate vs annotate、分组聚合 |
| Django · Database Functions | https://docs.djangoproject.com/en/6.1/ref/models/database-functions/ | UUID4 / UUID7 等函数 |
| Django 6.1 Release Notes | https://docs.djangoproject.com/en/6.1/releases/6.1 | 本课 6.1 新增内容的官方出处 |
| Django · Conditional Expressions | https://docs.djangoproject.com/en/6.1/ref/models/conditional-expressions/ | Case/When 完整说明 |
| RFC 9562 §5.7 | https://datatracker.ietf.org/doc/html/rfc9562 | UUIDv7 位布局：48 位毫秒时间戳 + 74 位随机 |

### 「文档明示」与「实测确认」的区分

| 结论 | 来源 |
|------|------|
| `BitAnd/Or/Xor` 此前只在 contrib.postgres，6.1 提升为通用 | ✅ 文档明示（release notes 原文） |
| 6.1 新增 `JSONNull` / `UUID4` / `UUID7` | ✅ 文档明示 |
| 6.1 支持 Python 3.12 / 3.13 / 3.14 | ✅ 文档明示 |
| `fetch_mode` 三种模式与 N+1 压缩效果 | ✅ 文档明示 |
| `select_for_update` 需事务、各后端支持度不同 | ✅ 文档明示 |
| **丢失更新：两个请求读到同一旧值、后写覆盖先写** | 🔬 **实测确认**（确定性演示） |
| **多线程 5 个线程读到 [0,0,0,0,0]，结果 1/5** | 🔬 实测确认 |
| **F() 同样并发下 5/5 无丢失** | 🔬 实测确认 |
| **F() 生成的 SQL 是 `SET view_count = view_count + 1`** | 🔬 实测确认 |
| **`update()` 后内存对象仍是旧值** | 🔬 实测确认 |
| **`update()` 返回受影响行数而非新值** | 🔬 实测确认 |
| **库存扣减：返回 1 表示成功、0 表示不足** | 🔬 实测确认 |
| **`select_for_update` 在 SQLite 上静默失效（SQL 无 FOR UPDATE）** | 🔬 **实测确认** + 源码核实（`compiler.py:840`） |
| **SQLite `features.py` 未覆写 `has_select_for_update`** | ✅ 源码核实（基类默认 `False`） |
| **多值关系：链式 filter 得 1 件，Q()&Q() 得 0 件** | 🔬 实测确认 |
| **Subquery 去掉 `.values()` 得到静默错误结果 [2,3,None,None]** | 🔬 实测确认 |
| **Case/When 顺序错误时库存 0 被判为"充足"** | 🔬 实测确认 |
| **`JSONNull` 在 `django.db.models` 而非 functions** | 🔬 实测确认 + 源码核实（`expressions.py:1244`） |
| **`UUID7` 在 Python 3.13 下抛 `NotSupportedError`** | 🔬 实测确认 + 源码核实（`functions/uuid.py:75`） |
| **位聚合在 SQLite 上 BitAnd=2 / BitOr=7 / BitXor=3** | 🔬 实测确认 |
| **查询次数：循环 10 次 vs F() 1 次；N+1 5 次 vs Subquery 1 次** | 🔬 实测确认 |
| **UUID7 前 48 位是毫秒时间戳（时间有序）** | ✅ 文档明示（RFC 9562 §5.7） |
| **本机 Python 3.13.14 没有 `uuid.uuid7()` —— 这正是 UUID7 报错的根因** | 🔬 实测确认 |

---

## 🚀 下一批接力提示词

**继续下一课**：

```text
继续学 Django 进阶（前后端分离）。我的学习档案在 django/00-学习档案.md，
刚学完阶段 4《数据层纵深》的课 11《查询表达式进阶》
（知识点：F() 表达式与原子更新、Q() 对象与复杂条件组合、子查询/条件表达式/聚合及 6.1 新函数），
阶段 4 还剩课 12-14。请按大纲继续讲解课 12《索引、约束与连接池》。
```

**如果想先给自己的项目做一次表达式体检**：

```text
我在做一个 Django + DRF 项目，想优化数据层。请帮我检查：
1. 所有 `obj.field += 1` 或 `obj.field -= 1` 的地方，是否应该改成 F() 表达式
2. 所有"先查询判断、再修改保存"的写操作，能否把判断合并进 filter()
3. 循环里对每条数据做聚合查询的地方（N+1），能否改成 Subquery + annotate
4. 有没有用 Python 的 if-else 做分类、其实可以改成 Case/When 的
5. 多值关系的 Count 是否都加了 distinct=True
（贴出你的 views.py 或 serializers.py）
```

---

## 🧭 课程导航

**上一课**：[阶段 3 · 课 10《分离架构下的安全实践》](../../3-认证权限与鉴权/lessons/lesson-10-分离架构下的安全实践.md)
**下一课**：[阶段 4 · 课 12《索引、约束与连接池》](./lesson-12-索引约束与连接池.md)
**阶段概览**：[阶段 4：数据层纵深](../overview.md)
**返回**：[课程目录](../../../02-课程目录.md)

---

> **本课一句话**：`obj.count += 1` 看着是一条语句，实际是 SELECT → Python 加一 → UPDATE 三步，并发时后写的直接覆盖先写的，5 个线程自增最后只剩 1。把自增写成 `F("view_count") + 1`，SQL 就变成 `SET view_count = view_count + 1`，**数据库内部完成，窗口消失**——同样并发 5/5 无丢失。而更难查的是那些不报错的错误：Subquery 漏了 `.values()` 分组会给你一组**错值**，`select_for_update()` 在 SQLite 上**静默失效**，`Q(a) & Q(b)` 在多值关系上**永远返回 0 条**。它们都不会抛异常，只会让你在上线后才发现。