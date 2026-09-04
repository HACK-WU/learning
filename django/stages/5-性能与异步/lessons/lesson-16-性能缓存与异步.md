# 课 16《性能：缓存与异步》

> 🧭 所属阶段：[阶段 5 性能与异步](../overview.md) ｜ 上一课：[课 15《ORM 进阶与 N+1 治理》](./lesson-15-ORM进阶与N+1治理.md) ｜ 下一课：课 17 信号：隐式耦合的代价
>
> 🎯 **本课回答三个问题**：缓存该加在哪一层、什么时候清？`async def` 视图到底什么时候真的有用？这个慢活该交给内置 `django.tasks` 还是 Celery？
>
> ⚙️ **实跑环境**：Django **6.1** / DRF **3.18.0** / Python **3.13.14**（Windows 托管 venv `dj-course`）。SQLite 单文件。缓存用 `LocMemCache`（实验 33 会专门说明它的局限）。
>
> 📦 实验工程：`%TEMP%/dj-lesson16-demo/cachelab`，**34 个实验全部实测通过**（断言 95 项，零失败）。

#### 怎么跑起来

```powershell
# 复用课 2 建的虚拟环境
$env:PYTHONPATH = "%TEMP%\dj-lesson16-demo\cachelab\apps"
$env:PYTHONIOENCODING = "utf-8"          # 否则中文输出乱码
cd %TEMP%\dj-lesson16-demo\cachelab

python run_lab1.py     # 实验 1-9  ：缓存分层、粒度、失效时机、穿透
python run_lab2.py     # 实验 10-18：异步视图与 ASGI 边界
python run_lab3.py     # 实验 19-27：内置 Tasks 框架的能力边界
python run_lab4.py     # 实验 28-34：缓存与 DRF 的集成点

python run_lab1.py 7   # 只跑第 7 个实验
python count_assertions.py   # 汇总四组实验的断言数

python probe_getmany.py      # 验证 1.2 节的生产写法（含 1 万条放大检验）
python probe_cache_key.py    # 验证 1.4 节缓存键构成（Vary 头的差异）
```

> 💡 **不需要 Redis**。缓存的**层级、粒度、失效时机、缓存键构成**都是 Django Python 侧的行为，用 `LocMemCache` 完整可复现。真正需要 Redis 的是"多进程共享缓存"这一点——实验 33 用两个 alias 对照演示了它的局限，并明确标注为"必须在真实共享后端上验证"。
>
> 💡 **不需要 Celery**。本课讲的是"该选哪个"，不是"Celery 怎么用"。内置框架的能力缺口全部由本机实测坐实（实验 20、21、24、25）。

#### 实验用的模型

本课的缓存实验都基于下面这套模型。如果你丢掉了实验工程，用它可以完整重建：

```python
from django.db import models


class Category(models.Model):
    name = models.CharField(max_length=50)


class Product(models.Model):
    """缓存实验的主模型。updated_at 用于演示按版本失效。"""

    name = models.CharField(max_length=100)
    price = models.IntegerField(default=0)
    stock = models.IntegerField(default=0)
    category = models.ForeignKey(Category, on_delete=models.CASCADE, null=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["id"]
```

种子数据规模：**50 个商品 / 1 个分类**。异步实验与任务实验不依赖这套模型，用的是独立的计时与计数器。

> ⚠️ 实验工程在 `%TEMP%` 下，**可能被系统清理**。如果跑不起来，用上面的模型 + `config/settings.py` 即可重建。
> 注意 settings 里必须有 `ALLOWED_HOSTS = ["testserver"]`——`cache_page` 会调 `build_absolute_uri()`，缺了会抛 `DisallowedHost`（本课踩到的第一个坑）。

---

## 开场：三个"加了缓存/上了异步"的接口，还是没解决问题

### 先对齐几个术语

本课会密集出现下面这些词，先给一句直白解释，避免后面被名词绊住：

| 术语 | 直白解释 |
|------|----------|
| `Vary` | 响应头里的一句话，告诉缓存"我的内容还跟这些请求头有关"——它决定缓存键里要不要带上那些头 |
| 事件循环 | 单线程里轮流执行所有协程的那个调度器。**一个人卡住，所有人都得等** |
| `thread_sensitive` | `sync_to_async` 的开关，打开表示"同一段 async 代码里的同步部分共用一个线程"（为了保护数据库连接） |
| `ImmediateBackend` | 内置任务框架的**默认**后端，`enqueue` 时**当场同步执行**，不是丢给后台 |
| 缓存穿透 | 查一个根本不存在的数据，缓存里永远没有，于是每次都打到数据库 |
| 缓存雪崩 | 大批缓存**同一时刻**集体过期，那一瞬间数据库被全部流量命中 |
| ASGI / WSGI | 两种服务器接口协议。WSGI 同步（一请求一线程），ASGI 异步（事件循环，支持长连接） |

**接口 A**（商品详情）：加了缓存，查询数从 1 条降到 0 条，压测 QPS 翻了三倍。上线一周后客服工单激增——**用户看到的价格永远是旧的**。代码里确实写了 `cache.delete`，但删的那个键和读的那个键不是同一个。

**接口 B**（订单聚合）：团队把视图改成了 `async def`，还顺手用了 `asyncio.gather` 并发调三个下游。上线后 P99 不降反升 15%。查下来：三个下游调用里**有一个是同步的 `requests.get`**，它把整个事件循环卡死了，剩下两个的并发收益全被吃掉。

**接口 C**（发通知）：用 Django 6.0 新内置的 `django.tasks` 把发邮件丢出去了，本地测试"秒返回"，很高兴。上线后发现：邮件**一封都没发出去**——不是队列堵了，是默认后端 `ImmediateBackend` 会在 `enqueue` 那一刻**当场同步执行**，而"秒返回"只是因为本地发邮件够快。更要命的是任务内部抛了异常，异常被塞进 `result.errors`，`enqueue()` 自己**一声不响**。

三个接口的共同点：**都做了"看起来正确"的性能优化，但优化的位置和真正的瓶颈对不上**。

| 你以为 | 实际 |
|--------|------|
| 加了缓存就快了 | 缓存**键**错了等于没加，缓存**清错时机**比不加更糟 |
| `async def` 能并发 | 有一处同步阻塞，整个事件循环陪它一起等 |
| 内置任务框架"丢出去就完事" | 默认后端是**同步当场执行**；任务炸了 `enqueue` 不抛异常 |

这一课就是把这三组错配拆开。

---

## 第一幕：缓存该加在哪一层

### 1.1 先看收益有多大

缓存最直接的效果是**把 SQL 降到零**。50 个商品的列表接口：

```python
# 实验 1
def hot_list():
    return list(Product.objects.select_related("category")[:50])

def cached_list():
    data = cache.get("product:list:v1")
    if data is None:
        data = list(Product.objects.select_related("category")[:50])
        cache.set("product:list:v1", data, 300)
    return data
```

实测（实验 1）：

| 场景 | SQL 条数 |
|------|----------|
| 不加缓存 | 1 条 |
| 加缓存首次（miss） | 1 条 |
| 加缓存再次（hit） | **0 条** |

200 次调用：**108.5ms → 74.4ms**。

> 🔍 这里值得停一下：`select_related` 已经把查询压到 1 条了，缓存还能把 1 条变成 0 条。所以课 15 的优化和本课的缓存是**叠加关系**——先用 `select_related` 把 N+1 治了，再用缓存把剩下的那 1 条也省掉。反过来做（先加缓存不治 N+1）收益很小：你只是把 11 条 SQL 缓存起来，首次访问照样 11 条。

### 1.2 四层缓存，各解决什么

Django 提供了四个层级的缓存，它们的**覆盖范围**和**失效代价**完全不同：

| 层级 | 写法 | 覆盖范围 | 失效代价 |
|------|------|----------|----------|
| per-site | `UpdateCacheMiddleware` + `FetchFromCacheMiddleware` | 全站 | 站点级，几乎不可控 |
| **per-view** | `@cache_page(300)` | 单个视图的整个响应 | 改任何一处都要等 TTL 或手工清 |
| **低层 API** | `cache.get_or_set(...)` | **你指定的任意片段** | 精确到单个键 |
| 模板片段 | `{% cache %}` | 模板里的一个块 | 前后端分离项目用不上 |

前后端分离项目里真正会用到的是**中间两层**。它们的差别是本节的核心。

#### per-view：省心，但管得太宽

```python
# 实验 2
@cache_page(300)
def product_view(request):
    products = list(Product.objects.all()[:50])
    return JsonResponse({"count": len(products)})
```

实测：第一次请求 1 条 SQL，第二次 **0 条**。视图函数本身只执行了 **1 次**（2 次请求）。

`cache_page` 的省心之处在于它连中间件一起跳过了——响应是直接从缓存里取的，视图、认证、权限、限流**全都不执行**。

> 💡 这正是它危险的地方。**不执行权限检查 = 谁都能拿到缓存里的那份响应**。

#### 低层 API：麻烦，但可控

```python
# 实验 4 · 粒度 A：整个列表一个键
data = cache.get_or_set(
    "list:all",
    lambda: list(Product.objects.all()[:50]),
    300,
)
```

实测：首次 1 条 SQL，命中后 **0 条**。

```python
# 实验 4 · 粒度 B：每个对象一个键
pks = list(Product.objects.values_list("pk", flat=True)[:50])
objs = [
    cache.get_or_set(f"product:{pk}", lambda pk=pk: Product.objects.get(pk=pk), 300)
    for pk in pks
]
```

实测：首次 **50 条** SQL，命中后 0 条。

**同样的 50 条数据，冷启动时一个 1 条、一个 50 条。** 这就是粒度的代价。

| 粒度 | 冷启动 | 命中后 | 改 1 个商品要清 |
|------|--------|--------|----------------|
| 整列表一个键 | 1 条 SQL | 0 条 | 1 个键，但**整列表重建**（49 个没变的数据也重算） |
| 每个对象一个键 | 50 条 SQL | 0 条 | 1 个键，**精准**；但列表页拼装要 50 次 `get` |

> ⚠️ **注意这张表里的循环次数**：粒度 B 的列表解析式跑了 50 次 `cache.get_or_set`，每次 miss 都要打一次库——这就是课 15 和评审必查项 #28 反复强调的 **O(N) 次往返**。真实项目里如果选了对象级粒度，列表页必须走 `cache.get_many(pks)` 一次批量取回，而不是写个 `for`。
>
> ```python
> # ✅ 生产写法：一次 get_many，缺的再批量补
> def batch_get_products(pks):
>     keys = {f"product:{pk}": pk for pk in pks}
>     found = cache.get_many(keys)                       # 1 次网络往返
>     missing = [keys[k] for k in keys if k not in found]
>     if missing:                                        # 最多 1 条 SQL
>         fresh = {}
>         # .iterator()：不把结果集整体物化，10 万行也不会吃掉内存
>         for p in Product.objects.filter(pk__in=missing).iterator():
>             fresh[f"product:{p.pk}"] = p
>         cache.set_many(fresh, 300)                     # 1 次写入
>         found.update(fresh)
>     # 缓存键顺序不保证，按请求的 pks 顺序还原
>     return [found[f"product:{pk}"] for pk in pks if f"product:{pk}" in found]
> ```
>
> 这段代码的实测结果（`probe_getmany.py`，含放大检验）：
>
> | 场景 | SQL 条数 |
> |------|----------|
> | 冷启动（缓存全空，50 个） | **1 条** |
> | 全部命中 | **0 条** |
> | 部分命中（缺 10 个） | **1 条** |
> | **放大到 10000 个 pk** | **仍是 1 条** |
>
> 关键点：**查询数不随 N 增长**。`.iterator()` 保证缺的那一批不会整体载入内存（课 14 的教训），`get_many`/`set_many` 保证往返次数不随 N 增长（课 15 + 必查项 #28）。
>
> ⚠️ 一个容易漏的细节：`cache.get_many()` 返回的字典**不保证顺序**，所以最后必须按请求的 `pks` 顺序还原，不能直接 `return list(found.values())`——否则列表页的顺序会随机漂移。

**怎么选**：

- 数据**整体更新、很少局部改**（如配置字典、首页聚合）→ 整列表一个键
- 数据**频繁局部更新、按 id 访问**（如商品详情、用户资料）→ 对象级 + `get_many`
- 拿不准 → 先用整列表，等"重建成本"真的成为瓶颈再拆

### 1.3 per-view 的致命盲区

`cache_page` 的缓存键是什么构成的？课上常说"按 URL 缓存"，这只对了一半。

```python
# 实验 3
@cache_page(300)
def me_from_header(request):
    user = request.headers.get("X-User", "anonymous")
    return JsonResponse({"user": user})
```

实测：alice 先请求，bob 后请求——

```text
alice 请求得到：{"user": "alice"}
bob   请求得到：{"user": "alice"}     ← 拿到了 alice 的响应
视图体实际收到：['alice']              ← 视图只跑了 1 次
```

**bob 看到了 alice 的数据。** 这就是把 per-view 缓存用在私有接口上的后果。

但如果你把 `X-User` 换成 `Authorization`，结果**完全相反**（实验 30）：

```text
alice 的响应：{"token": "Bearer alice"}
bob   的响应：{"token": "Bearer bob"}   ← 没串号
视图体实际解析到的 token：['Bearer alice', 'Bearer bob']
响应的 Vary 头：'Authorization'
```

**为什么一个有兜底、一个没有？** 我在备课时预设"缓存键不含请求头"，实测打脸，查源码才看清全貌（实验 34）。

### 1.4 缓存键的完整规则：URL + Vary

源码级答案在 `django/utils/cache.py` 与 `django/middleware/cache.py`：

```python
# django/utils/cache.py
def _generate_cache_header_key(key_prefix, request):
    url = md5(request.build_absolute_uri().encode("ascii"), ...)
    return "views.decorators.cache.cache_header.%s.%s" % (key_prefix, url.hexdigest())

def _generate_cache_key(request, method, headerlist, key_prefix):
    ctx = md5(...)
    for header in headerlist:                      # ← 关键：按 headerlist 逐头取值
        value = request.META.get(header)
        ctx.update(b"%d:%s," % (len(data), data))
    url = md5(request.build_absolute_uri()...)
    return "views.decorators.cache.cache_page.%s.%s.%s.%s" % (...)
```

流程是三步：

1. `_generate_cache_header_key()` 用 **URL** 生成一个"headerlist 的键"
2. `learn_cache_key()` 把**响应 `Vary` 头里的头名**存进这个 headerlist
3. `_generate_cache_key()` 再按 headerlist **逐头取值**参与 md5

所以准确的表述是：**缓存键 = URL + 响应 `Vary` 头里列出的那些请求头**，不是"永远不含请求头"。

#### 唯一的自动兜底

```python
# django/middleware/cache.py · UpdateCacheMiddleware.process_response
# Make the response vary on Authorization if the request bears that
# header, unless allowed by "public" per RFC 9111, Section 3.5.
if request.headers.get("Authorization") and "public" not in cache_control_parts:
    patch_vary_headers(response, ("Authorization",))
```

**Django 只对 `Authorization` 做自动兜底。** 任何自定义身份头——`X-User`、`X-Tenant-Id`、`X-Org-Code`——都**不会**自动进缓存键。这就是实验 3 串号、实验 30 不串号的全部原因。

> 🚨 **这条对前后端分离项目特别重要**：多租户系统里，租户标识经常放在自定义头里。用 `cache_page` 缓存这类接口，**等于把 A 租户的数据发给 B 租户**，而且不报错。
>
> 判据很简单：**响应内容是否随某个请求输入变化？是，那这个输入就必须进缓存键**——要么声明 `Vary`，要么改用低层 API 自己拼键。

#### 自己怎么验

不想背这套规则的话，可以直接把 headerlist 打出来看：

```python
from django.core.cache import cache
from django.utils.cache import _generate_cache_header_key

header_key = _generate_cache_header_key("", request)
print(cache.get(header_key))
# 带 Authorization 的请求：['HTTP_AUTHORIZATION']
# 只带自定义头的请求：[]      ← 空的，说明没有任何请求头参与键计算
```

这个列表就是 `_generate_cache_key()` 会逐头取值参与 md5 的那份清单。**它是空的，就意味着缓存键里只有 URL**——任何身份头都不影响命中。实验 34 的 A/B 对照就是靠它定位的。

#### 怎么修

```python
# 方案 1：显式声明 Vary（实验 34 场景 B 实测：视图执行 2 次，bob 拿到自己的）
@vary_on_headers("X-User")
@cache_page(300)
def view_with_vary(request):
    ...

# 方案 2：改用低层 API，把身份拼进键（推荐，见实验 29）
key = f"v1:user:{request.user.id}:orders"
data = cache.get_or_set(key, lambda: build_orders(request.user), 300)
```

方案 2 更可控：键里有什么，你一眼看得见，不用去猜框架帮你加了什么。

---

## 第二幕：什么时候清缓存

### 2.1 失效比缓存本身更难

加缓存是一行代码，**清缓存是一个分布式系统问题**。这一幕讲三个必须知道的坑。

### 2.2 事务回滚了，缓存却留着新值

这是本课**第一处"不报错的错误"**。

```python
# ❌ 危险写法：事务还没提交就把新值写进缓存（实验 7 场景 B）
with transaction.atomic():
    p = Product.objects.get(pk=pk)
    p.price = 888
    p.save()
    cache.set(f"p:{pk}", 888, 300)      # 事务未提交就写缓存
    raise RuntimeError("业务失败，回滚")
```

实测输出：

```text
回滚后：数据库 11，缓存 888
```

**数据库回滚到了旧值 11，缓存里却留着新值 888。** 之后所有读请求都拿到 888，而数据库里是 11——**不一致会一直持续到 TTL 到期**，期间没有任何报错。

同一个实验里还有个"温和版"：事务内 `cache.delete()` 然后回滚（场景 A）。这个**不会**产生脏数据，只是白清一次——数据库没变，缓存却没了，下一个请求白打一次库。代价小，但也是白损失。

#### 正确写法：`on_commit`

```python
# ✅ 实验 7 场景 C
with transaction.atomic():
    p = Product.objects.get(pk=pk)
    p.price = 777
    p.save()
    transaction.on_commit(lambda: cache.delete(f"p:{pk}"))
```

实测：

```text
事务内（未提交）缓存是否还在：'旧'      ← 还没清
提交后 on_commit 是否执行：[True]
提交后缓存：None                      ← 提交后才清
```

课后 15 讲 `on_commit` 时提到"提交后清缓存"，这里把它的必要性坐实了：**在事务提交前动缓存，要么白清、要么留下脏数据**。

> 📌 规则：**写缓存用 `on_commit` 删，不要用 `set` 更新**。"删"是幂等的、不会产生脏值；"更新"则可能在事务回滚后留下幽灵数据。

### 2.3 穿透：存 None 到底挡不挡得住

查询一个不存在的 id，每次都打库，这就是**缓存穿透**。流行说法是"把空值也缓存起来"。实测下来（实验 6、9），这个说法**只对了一半**。

```python
# 常见写法
def get_product(pk):
    data = cache.get(f"p:{pk}")
    if data is None:
        data = Product.objects.filter(pk=pk).first()
        cache.set(f"p:{pk}", data, 300)     # 查不到 → 存 None
    return data
```

实测：同一个不存在的 id 查 5 次 → **5 条 SQL，一次没挡住**。

问题不在"存没存进去"。查下来（`实验 9`）：

```text
写入 cache.set('p:empty', None) 后：
  cache.get('p:empty')      = None
  cache.has_key('p:empty')  = True     ← 确实存进去了
  cache.has_key('p:nope')   = False    ← 从未写入的键
```

**None 确实被存进缓存了。** 之所以挡不住，是因为 `cache.get(key)` 在"键不存在"和"值是 None"时**都返回 None**（`default` 参数默认就是 `None`），调用方根本区分不了，于是每次都当成 miss 去查库。

> 🔬 顺带验证：改用 `cache.get(key, sentinel)` 也**区分不了**——对"缓存了 None"它照样返回 None 而不是哨兵。真正可靠的判断是 `cache.has_key(key)`。

改成先判键再取值：

```python
# ✅ 实验 9：同一不存在的 id 查 5 次 → 1 条 SQL
def get_product_fixed(pk):
    key = f"p:{pk}"
    if cache.has_key(key):          # 先在键层面判断
        return cache.get(key)
    data = Product.objects.filter(pk=pk).first()
    cache.set(key, data, 300)
    return data
```

**但随机 id 仍然挡不住**：5 个不同的随机 id → **5 条 SQL**。空值缓存只能挡住**重复查询同一个不存在的键**，挡不住**每次都不同的随机 id**。后者需要布隆过滤器或前置的存在性校验，那超出了本课范围。

> ⚠️ 别抬杠说"用 `get_or_set` 就行"：`get_or_set` 同样用 `get` 判空，遇到缓存里的 None 一样会重算。

### 2.4 雪崩：同时过期

100 个热点键在同一秒写入、同一秒过期，过期那一刻全部请求打到数据库。

```python
# ❌ 实验 5：100 个键 TTL 完全一致
for i in range(100):
    cache.set(f"hot:{i}", value, 60)
# 实测：TTL 分布 最小 60s，最大 60s（完全一致）

# ✅ 加抖动
ttl = 60 + random.randint(0, 30)
# 实测：最小 60s，最大 90s（分散）
```

一行代码的事，但漏了它，代价是在某个固定时刻的流量尖峰。

### 2.5 缓存键设计：版本化 vs 手工失效

两种主流做法（实验 8）：

**方案 A · 版本化**：把数据的更新时间拼进键

```python
def list_key():
    latest = Product.objects.aggregate(m=Max("updated_at"))["m"]
    return f"list:v{latest.timestamp() if latest else 0}"
```

实测：**每次生成键要花 1 条聚合查询**。好处是永远不需要主动清——数据变了键就变了，旧键自然过期。

**方案 B · 手工失效**：固定键 + 每个写路径显式删

```python
cache.set("list:manual", data, 300)
p.save()
cache.delete("list:manual")     # 漏一处就是脏数据
```

| 方案 | 读路径开销 | 写路径风险 |
|------|-----------|-----------|
| 版本化 | 每次多 1 条聚合查询 | **无**（不需要主动清） |
| 手工失效 | 无 | **每个写路径都得记得清，漏一处就是脏数据** |

**怎么选**：写路径**少且集中**（只有一两个地方改数据）→ 手工失效；写路径**多且分散**（后台、定时任务、数据同步都在改）→ 版本化。

> 💡 **那多花的那条聚合查询值不值？** 这笔账要算清楚：
>
> 版本化的成本是**每次读多 1 条 SQL**，但它是 `Max()` 聚合——只要 `updated_at` **上有索引**，这就是一次索引端的极值查找，成本接近常数级。⚠️ **前提是你的 `updated_at` 建了索引**，否则它会变成全表扫描，那就不划算了。
>
> 手工失效的成本是**零查询**，但代价是**人的记忆**——每个写路径都得记得清，漏一处就是脏数据，而**脏数据不报错**，往往等用户投诉才发现。
>
> 所以：写路径 ≥ 3 处、或者改动散落在多个模块时，多花那条（走索引的）查询换"不可能漏"，是划算的。

### 2.6 缓存与 DRF：限流其实存在缓存里

这是个容易被忽略的耦合点。DRF 的限流计数**就存在 Django 缓存后端里**：

```python
# 实验 28
class FivePerMin(SimpleRateThrottle):
    rate = "5/min"
    scope = "five"

    def get_cache_key(self, request, view):
        return "throttle:fixed"

class LimitedView(APIView):
    throttle_classes = [FivePerMin]
    def get(self, request):
        return Response({"ok": True})
```

实测：连打 7 次 →

```text
7 次请求的状态码：[200, 200, 200, 200, 200, 429, 429]
缓存里的计数：[1788407240.11, 1788407240.11, ...]   ← 5 个时间戳
清缓存后再请求 3 次：[200, 200, 200]               ← 配额被重置
```

**清缓存 = 重置配额。** 缓存重启、Redis 清库、TTL 到期，都会让限流计数归零。

配合课 10 的结论（多进程下 `LocMemCache` 各数各的），完整图景是：

| 进程数 | 单进程配额 5/min 时的实际配额 |
|--------|---------------------------|
| 1 | 5/min |
| 2 | 10/min |
| 4 | 20/min |

所以：**限流要真的生效，缓存后端必须是共享的**（Redis/Memcached）。这也是阶段 3 讲限流时能跑、上线后配额翻倍的根因。

### 2.7 多进程下的缓存：LocMemCache 的天然局限

```python
# 实验 33：两个 alias 模拟两个进程
cache.set("k", "process-1-value", 300)          # default alias
caches["redis_like"].set("k", "process-2-value", 300)

# 实测
default    alias 读到：'process-1-value'
redis_like alias 读到：'process-2-value'    ← 互相看不见
```

`LocMemCache` 是**进程内**缓存。N 个 worker 就有 N 份：

- **不一致**：进程 A 清了键，进程 B 还在读旧值
- **不省内存**：同一份数据存了 N 遍

**多进程部署必须换共享后端。** 本机没有 Redis，所以这一条标注为"须在真实共享后端上验证"，但机制是确定的。

> 📌 第一幕收口 —— 缓存决策清单：
> 1. **要不要加**：先用 `select_related`/索引把 SQL 治了（课 15），再谈缓存
> 2. **加哪层**：私有数据用低层 API；公开数据才考虑 `cache_page`
> 3. **键里有什么**：URL + Vary（自定义身份头必须自己声明）
> 4. **什么时候清**：`on_commit` 里删，不要用 `set` 更新
> 5. **用什么后端**：多进程必须是 Redis/Memcached，`LocMemCache` 只用于开发

---

## 第三幕：async 视图的真实边界

前两幕讲"慢"，这一幕讲"以为快了其实没快"。

### 3.0 从缓存到异步

前两幕我们把"重复的计算"省掉了。但如果一个请求**本来就慢**——它要去调三个下游服务——缓存帮不上忙（数据实时、不能缓存）。这时候你会想到异步。

**但异步不解决"慢"，它解决"等"。** 这一幕把这句话坐实。

### 3.1 async 视图里不能直接用 ORM

先撞一次墙：

```python
# ❌ 实验 11
async def bad_async_view(request):
    n = Product.objects.count()      # 同步 ORM 调用
    return JsonResponse({"count": n})
```

实测报错：

```text
django.core.exceptions.SynchronousOnlyOperation:
You cannot call this from an async context - use a thread or sync_to_async.
```

报错信息本身就把解法告诉你了：

```python
# ✅
@sync_to_async
def count_products():
    return Product.objects.count()

async def good_async_view(request):
    n = await count_products()
    return JsonResponse({"count": n})
```

实测通过：`{"count": 5}`。

### 3.2 那 async 到底快在哪

关键实验（实验 12）：5 次 50ms 的 IO 等待。

```python
def fake_io(seconds):
    time.sleep(seconds)          # 同步等待

async def fake_io_async(seconds):
    await asyncio.sleep(seconds) # 异步等待
```

实测：

```text
同步串行 5 次 IO（每次 50ms）：252.0ms
异步并发 5 次 IO：57.6ms
加速比：4.37x
```

**5 次等待，同步要 252ms，异步只要 58ms——约等于一次等待的时间。**

### 3.3 但前提是"等"得让出来

这是本课最容易被忽略的一条。同样是 `async def`：

```python
# ❌ 实验 13
async def blocking_sleep():
    for _ in range(5):
        time.sleep(0.05)         # 阻塞整个事件循环

# ✅
async def nonblocking_sleep():
    await asyncio.gather(*[asyncio.sleep(0.05) for _ in range(5)])
```

实测：

```text
async 函数里用 time.sleep（阻塞）×5：253.1ms
async 函数里用 asyncio.sleep（让出）×5：54.2ms
加速比：4.67x
```

**写了 `async def` 不等于并发。** 事件循环里任何一处 `time.sleep`、同步 `requests`、同步文件 IO，都会**卡死整个循环**——不只是那个协程慢，是**所有协程一起等**。

> 🚨 回到开场接口 B：三个下游调用里有一个是同步的 `requests.get`，另外两个的并发收益**全部被它吃掉**，还多付了线程切换的开销，所以 P99 不降反升。
>
> 判据：**你的 async 视图里，每一处 await 之间必须是真的能让出的 IO**。用 `asyncio.gather` 包五个同步函数调用，等于把它们串行执行，还多绕了一层。

#### 自己怎么发现踩了这个坑

靠读代码一个个看不现实。两个办法：

**办法 1：看事件循环在 IO 期间还能不能动**

```python
import asyncio, time

async def probe(your_logic):
    """如果 your_logic 里有同步阻塞，tick 的 10 次唤醒会挤成一团。"""
    stamps = []

    async def tick():
        for _ in range(10):
            await asyncio.sleep(0.01)
            stamps.append(time.perf_counter())

    t0 = time.perf_counter()
    await asyncio.gather(your_logic(), tick())
    gaps = [stamps[i + 1] - stamps[i] for i in range(len(stamps) - 1)]
    print(f"tick 间隔：最小 {min(gaps) * 1000:.1f}ms，最大 {max(gaps) * 1000:.1f}ms")
    print(f"总耗时：{(time.perf_counter() - t0) * 1000:.1f}ms")
```

判据：**tick 本该是每次 10ms 均匀分布**。如果最大间隔远大于 10ms（比如某两次之间隔了 60ms），说明那段时间内事件循环被卡住了——去看看你在那个时间点跑了什么。

**办法 2：同步 ORM 的报错本身就是探针**

在 async 上下文里直接调同步 ORM 会抛 `SynchronousOnlyOperation`（实验 11）。反过来说：**如果某段同步代码在 async 视图里没抛这个错，它大概率已经被丢进线程了**（比如 `sync_to_async` 包的、或者本来就是异步客户端），不会卡循环。

所以排查顺序是：先找**没被 `sync_to_async` 包裹的同步调用**——`requests`、`time.sleep`、同步文件读写、同步 SDK。这些才是循环杀手。

### 3.4 ORM 查询在 async 里仍然是串行的

即使你正确用了 `sync_to_async`，ORM 也不会变成并发：

```python
# 实验 15
@sync_to_async
def q_and_tid():
    return Product.objects.count(), threading.current_thread().name

async def run():
    return await asyncio.gather(*[q_and_tid() for _ in range(5)])
```

实测：

```text
5 次并发 ORM 查询：结果 {10}，线程 {'ThreadPoolExecutor-0_0'}
```

**5 次查询跑在同一个线程上。** 原因是 `sync_to_async` 默认 `thread_sensitive=True`——同一个 async 上下文里的同步代码共用一个线程（实验 14 实测：5 次调用 1 个线程）。

这么设计是为了保护数据库连接：**Django 的连接绑定在线程上**，如果 5 次查询跑在 5 个线程，就要 5 条连接。

```python
# 实验 14：关掉 thread_sensitive
@sync_to_async(thread_sensitive=False)
def record_tid2(): ...
# 实测：5 次调用跑在 2 个线程上
```

⚠️ 代价是**更多数据库连接**——课 12 的连接数公式要按线程数重新算。默认开着就别关。

**所以结论是**：async 视图 + 同步 ORM = **用 async 的语法，跑同步的性能**。

### 3.5 异步 ORM 接口（a 前缀）

Django 为每个同步 ORM 方法提供了 `a` 前缀的异步版本：

```python
# 实验 16
n = await Product.objects.acount()                    # 实测 10
objs = [o async for o in Product.objects.all()[:3]]   # 实测取到 3 条
first = await Product.objects.aget(pk=objs[0].pk)     # 实测取到 '商品0'
```

三个都可用。但要注意：**它们仍然是串行执行的**——`acount()` 只是不在线程里跑，该等的时间一秒不少。

异步 ORM 的价值是**不占线程**，不是**更快**。所以它的收益取决于场景：

| 场景 | 异步 ORM 的收益 |
|------|----------------|
| 普通短请求（CRUD 接口） | **接近零**——省下的那点线程开销可以忽略 |
| 高并发长连接（WebSocket / SSE） | **明显**——不占线程 = 同样内存能撑更多连接 |
| async 视图里的零散查询 | 中等——避免了 `sync_to_async` 的线程池调度 |

别把它当成普适优化。对绝大多数前后端分离项目（短请求为主），用 `sync_to_async` 包同步 ORM 就够了，不必强改 `a` 前缀。

### 3.6 ASGI 是什么，WSGI 又是什么

```python
# 实验 17
from django.core.asgi import get_asgi_application
app = get_asgi_application()      # 实测：ASGIHandler 构造成功
```

| | WSGI | ASGI |
|---|------|------|
| 协议 | 同步，一请求一线程 | 异步，事件循环 |
| 长连接（WebSocket/SSE） | 不支持 | 支持 |
| 同步 ORM | 原生 | 需 `sync_to_async` |
| 部署 | gunicorn / uWSGI | uvicorn / daphne |

**ASGI 能同时跑同步和异步视图**——同步视图会被自动放到线程池里执行。所以迁移到 ASGI 不会破坏现有代码。

### 3.7 什么时候值得写 async

实测支撑（实验 18）：

| 场景 | 外部 IO 次数 | 建议 |
|------|-------------|------|
| 纯 ORM 查询接口 | 0 | **不值得** |
| ORM + 1 次外部 HTTP | 1 | 看比例 |
| 扇出调用 5 个外部服务 | 5 | **值得** |
| WebSocket / SSE 长连接 | 长连接 | **必须用** |

量化（单次 ORM 2ms、单次外部 HTTP 50ms）：

```text
1 次外部 IO：串行 52ms  → 并发 52ms  （省 0ms，0%）
3 次外部 IO：串行 152ms → 并发 52ms  （省 100ms，66%）
5 次外部 IO：串行 252ms → 并发 52ms  （省 200ms，79%）
```

> 📌 **判据**：async 的收益 ≈ 你能并发掉的那部分 IO 时间。**IO 占比越高、次数越多，收益越大。** 纯数据库接口加 async 只是徒增复杂度和一层线程切换。

---

## 第四幕：慢活交给谁

### 4.0 从异步到任务

第三幕解决了"等待"的问题——但它只适用于**请求内**的并发等待。如果一个操作要跑 30 秒（生成报表、批量发邮件、转码视频），再怎么并发，用户也得等 30 秒。

这类"慢活"得从请求里挪出去。Django 6.0 起内置了 `django.tasks`，本幕回答：**这个内置的够不够用**。

### 4.1 内置框架的最小可用形态

```python
# 实验 19
from django.tasks import task

@task
def add(a, b):
    return a + b

result = add.enqueue(2, 3)
```

实测：

```text
result.status        = SUCCESSFUL
result.return_value  = 5
任务函数实际被调用   = [('add', 2, 3)]
```

三个硬约束（都是实测踩出来的）：

**① 任务函数必须是模块级的**

```python
# ❌ 在函数内部定义 → django.tasks.exceptions.InvalidTask:
#    Task function must be defined at a module level.
def some_view():
    @task
    def inline_task(): ...
```

**② 参数必须是 JSON 兼容类型**

```python
# ❌ 实验 22：传模型实例
takes_product.enqueue(product)
# TypeError: Unsupported type: <class 'shop.models.Product'>

# ✅ 传主键
takes_pk.enqueue(product.pk)     # return_value = '测试商品'
```

源码依据：`django/utils/json.py` 的 `normalize_json()` 只认 `str/int/float/bool/None/list/dict/bytes`，其他一律 `raise TypeError`。

**③ 默认后端是同步的（最重要）**

```python
# 实验 20
settings.TASKS = {'default': {'BACKEND': '...immediate.ImmediateBackend'}}
# global_settings.py:692 的默认值就是这个

@task
def slow_task():
    time.sleep(0.1)
    return "done"

slow_task.enqueue()      # 实测：这次调用耗时 >100ms
```

**`enqueue()` 不是把任务丢给别人，而是在当前线程当场跑完。** 视图该等多久还等多久。

> 🚨 回到开场接口 C：本地"秒返回"只是因为发邮件够快；上线后邮件服务慢，`enqueue` 就跟着慢。要用内置框架真正异步，必须换后端（如 `django-tasks-db` + worker 进程）。

### 4.2 任务炸了不会报错

这是本课**第二处"不报错的错误"**。

```python
# 实验 23
@task
def boom():
    raise ValueError("任务内部炸了")

r = boom.enqueue()      # ← 这一行不抛异常
```

实测：

```text
status  = FAILED
errors  = 1 条
exception_class = builtins.ValueError
```

`enqueue()` 一声不响地返回了，异常被塞进 `result.errors`。**不检查 `result.status`，等于任务静默失败。**

读返回值时会抛错：

```python
r.return_value      # ValueError: Task failed
```

#### 一段可以直接抄的检查封装

注意：**`try/except` 包 `enqueue` 是拦不住的**——异常根本不在这里抛。

```python
import logging

logger = logging.getLogger(__name__)


def enqueue_checked(task, *args, **kwargs):
    """enqueue 的带检查版本：失败时立刻记日志，不让任务静默失败。"""
    result = task.enqueue(*args, **kwargs)
    if str(result.status) == "FAILED":
        err = result.errors[0] if result.errors else None
        logger.error(
            "任务 %s 失败：%s",
            task.module_path,
            err.exception_class_path if err else "未知错误",
            extra={"traceback": err.traceback if err else ""},
        )
    return result
```

用法就是把 `send_email.enqueue(uid)` 换成 `enqueue_checked(send_email, uid)`。

> ⚠️ 这个封装只解决"看得见"。要解决"自动重试"，内置框架帮不上——见 4.3 节。

### 4.3 内置框架缺什么

这部分全部由本机实测坐实。

**① 没有自动重试**（实验 24）

```python
@task
def flaky():
    ATTEMPTS["n"] += 1
    if ATTEMPTS["n"] < 3:
        raise RuntimeError("失败")
    return "ok"

flaky.enqueue()     # 实测：尝试 1 次，status=FAILED
```

要重试只能自己循环。

**② 没有定时器**（实验 25）

```python
add.using(run_after=timezone.now() + timedelta(hours=1)).enqueue(1, 2)
# InvalidTask: Backend does not support run_after.
```

**③ 没有任务编排**（chain/chord/group 一概没有）

能力对照表：

| 能力 | 内置 `django.tasks` | Celery |
|------|--------------------|--------|
| 延迟执行 / 定时任务（Beat） | ❌ | ✅ |
| 自动重试 + 退避 | ❌ | ✅ |
| 任务编排（chain / chord / group） | ❌ | ✅ |
| 结果后端 / 状态查询 | 看后端 | ✅ |
| 优先级队列 | 看后端 | ✅ |

### 4.4 测试时怎么不真跑任务

用 `DummyBackend`。注意：切后端属于配置对照，按必查项 #19 用**独立 settings 模块 + 独立进程**验证（实验 21）：

```python
# config/settings_dummy.py
TASKS = {
    "default": {"BACKEND": "django.tasks.backends.immediate.ImmediateBackend"},
    "dummyish": {"BACKEND": "django.tasks.backends.dummy.DummyBackend"},
}
```

实测输出：

```text
BACKEND: DummyBackend
STATUS: READY
IS_FINISHED: False
RETURN_VALUE_RAISES: ValueError: Task has not finished yet
```

> ⚠️ 我原以为 dummy 后端会返回 `None`，**实测是抛 `ValueError`**。原因在 `django/tasks/base.py:240`——`return_value` 对非 `SUCCESSFUL` 状态一律抛错，而 dummy 后端让任务停在 `READY`。
>
> 工程含义：用 dummy 后端跑测试时，**只能断言"任务被 enqueue 了"，不能断言结果**。

### 4.5 任务生命周期的可观测点

内置框架提供三个信号（实验 26）：

```python
from django.tasks.signals import task_enqueued, task_started, task_finished

# 实测捕获：[('enqueued', 'add'), ('finished', 'SUCCESSFUL')]
```

⚠️ 这些是 Django signal，与课 17 要讲的业务 signal 是同一套机制——**同样要小心"信号默认不跨事务"**。

### 4.6 怎么选

| 场景 | 选择 | 理由 |
|------|------|------|
| 发一封欢迎邮件 | 内置 | 丢了也就一封邮件 |
| 生成缩略图 | 内置 | 失败了可以下次访问时重生成 |
| 每晚 3 点跑报表 | **Celery** | 需要定时器（Beat） |
| 支付回调重试 3 次 | **Celery** | 需要自动重试 + 退避 |
| 先扣库存再发货再通知 | **Celery** | 需要 chain/chord 编排 |
| 跨服务、多语言消费者 | **Celery** | 内置是 Django 专用契约 |

判断顺序：

1. 需要定时吗？→ 是 = Celery（内置无 Beat）
2. 需要自动重试退避吗？→ 是 = Celery（内置无重试）
3. 需要任务编排吗？→ 是 = Celery（内置无 chain/chord）
4. 以上都不需要 → 内置 `django.tasks` 足够，且部署更简单

> 📌 Celery 自身的可靠性、编排、运维**不重复讲**，回指 `celery-django` 课程。本课只解决"该选哪个"的决策问题。

---

## 第五幕：三张决策表

### 5.1 缓存层级对照

| 层级 | 写法 | 适合 | 不适合 |
|------|------|------|--------|
| per-view | `@cache_page` | 公开、无身份差异的响应 | **任何私有数据** |
| 低层 API | `cache.get_or_set` | 一切需要精确控制的场景 | —— |
| 模板片段 | `{% cache %}` | —— | 前后端分离项目用不上 |

### 5.2 异步决策表

| 场景特征 | 结论 |
|----------|------|
| 纯 ORM、无外部 IO | 别用 async，收益为负 |
| 有 N 次可并行的外部 IO | 值得，收益 ≈ IO 时间 × (1 - 1/N) |
| 有同步阻塞调用 | 先改成异步客户端，否则**更慢** |
| 长连接（WebSocket/SSE） | 必须用 ASGI |

### 5.3 任务决策表

见 4.6。核心是三个"内置框架没有"：Beat、重试、编排。

---

## 高频误区

| 误区 | 真相 | 出处 |
|------|------|------|
| "加了缓存就快了" | 缓存**键**错了等于没加；**清错时机**比不加更糟 | 实验 3、7 |
| "缓存键就是 URL" | 是 **URL + Vary 里的头**；且只有 `Authorization` 有自动兜底 | 实验 34 |
| "存个 None 就能防穿透" | `cache.get` 对"无键"和"值为 None"都返回 None，**要用 `has_key`** | 实验 6、9 |
| "事务里改完顺手更新缓存" | 回滚后**缓存留着新值**，不一致持续到 TTL | 实验 7 |
| "`async def` 就能并发" | 一处同步阻塞，整个事件循环陪它等 | 实验 13 |
| "async 视图 + ORM 会更快" | ORM 仍串行，`thread_sensitive` 让它们共用一线程 | 实验 15 |
| "`enqueue()` 是异步的" | 默认后端**当场同步执行**，耗时计入请求 | 实验 20 |
| "任务炸了会报错" | 异常塞进 `result.errors`，`enqueue` 不抛 | 实验 23 |
| "Django 6 有内置任务，Celery 可以扔了" | 内置**无 Beat、无重试、无编排** | 实验 24、25 |
| "dummy 后端任务返回 None" | 停在 `READY`，读 `return_value` **抛 ValueError** | 实验 21 |

---

## 本课"不报错的错误"清单

| # | 现象 | 后果 | 出处 |
|---|------|------|------|
| 1 | 事务回滚但缓存留着新值 | 数据不一致持续到 TTL，无任何报错 | 实验 7 |
| 2 | 任务异常被塞进 `result.errors` | 任务静默失败，`enqueue` 不抛异常 | 实验 23 |
| 3 | 自定义身份头不进缓存键 | **A 用户看到 B 用户的数据** | 实验 3、34 |
| 4 | `cache.get` 分不清"无键"与"值为 None" | 空值缓存形同虚设，穿透照旧 | 实验 6、9 |

> 阶段 5 累计：课 15 有 4 处，本课 4 处。

---

## 自检题

<details>
<summary>【1】你的商品详情接口加了 <code>cache_page(60)</code>。用户反馈"改了价格要一分钟才生效"，你想缩短到 5 秒。除了改 TTL，还有什么更好的办法？为什么？</summary>

改 TTL 只是把"不一致的时间窗"从 60 秒压到 5 秒，**问题本身没解决**——中间那 5 秒用户照样看到旧价格，而且 TTL 越短缓存命中率越低。

更好的办法是**主动失效**：在写路径上用 `transaction.on_commit(lambda: cache.delete(key))`（实验 7 场景 C）。这样一致性与 TTL 解耦——TTL 可以设得很长（保命中率），价格一改立刻失效（保一致性）。

注意两点：①必须用 `on_commit`，否则事务回滚后缓存已清，白损失一次（场景 A）；②**不要用 `cache.set` 更新缓存**（场景 B），那会留下脏数据。
</details>

<details>
<summary>【2】你的接口用 <code>X-Tenant-Id</code> 头区分租户，想加 <code>cache_page</code>。会不会串号？为什么？</summary>

**会串号。** 实验 3 用的就是自定义头（`X-User`），实测 alice 先请求、bob 后请求，bob 拿到了 alice 的响应，视图只执行了 1 次。

根因在实验 34：缓存键 = URL + 响应 `Vary` 头里列出的那些请求头。Django 只在 `middleware/cache.py` 里对 **`Authorization`** 做了自动兜底（`patch_vary_headers(response, ('Authorization',))`），租户头、自定义身份头**不在兜底范围内**。

解法二选一：①`@vary_on_headers("X-Tenant-Id")`；②改用低层 API，把 `tenant_id` 拼进键（推荐，键里有什么一目了然）。

多租户系统里这条是**数据泄露级**风险，且不报错。
</details>

<details>
<summary>【3】你把列表视图改成了 <code>async def</code>，里面用 <code>asyncio.gather</code> 并发了 5 个 ORM 查询。为什么还是慢？</summary>

两层原因：

**第一层**：async 视图里不能直接调同步 ORM，会抛 `SynchronousOnlyOperation`（实验 11）。你得用 `sync_to_async` 包裹。

**第二层**（关键）：即使用了 `sync_to_async`，`thread_sensitive=True` 是默认值，5 次查询会跑在**同一个线程**上（实验 15 实测：5 次查询 1 个线程），等价于串行执行。

Django 这么设计是为了保护数据库连接——连接绑定在线程上，5 个线程就要 5 条连接。所以：**async 视图 + 同步 ORM = async 的语法、同步的性能**。

async 的收益只来自"能并发掉的外部 IO"。纯数据库接口加 async 是负收益。
</details>

<details>
<summary>【4】你们用内置 <code>django.tasks</code> 发通知，上线后发现通知经常没发出去，但日志里没有任何错误。可能是什么原因？</summary>

两个原因，都测过：

**① 默认后端是同步的**（实验 20）。`global_settings.py:692` 默认是 `ImmediateBackend`，`enqueue()` 当场执行。本地快所以"秒返回"，上线后通知服务慢，请求就被拖慢，超时后任务根本没跑完。

**② 异常被吞掉**（实验 23）。任务内部抛异常时，`enqueue()` **不抛**，异常被塞进 `result.errors`，`status` 变成 `FAILED`。不检查 `result.status` 就完全看不到。

排查方法：打印 `result.status` 与 `result.errors`：

```python
r = send_notification.enqueue(user_id)
if str(r.status) == "FAILED":
    logger.error("任务失败: %s", r.errors[0].exception_class_path)
```

另外记得：内置框架**没有自动重试**（实验 24），失败就是失败了。
</details>

<details>
<summary>【5】你的限流配了 100/hour，线上 4 个进程跑，实际放了多少？为什么？</summary>

**400/hour**。限流计数存在 Django 缓存后端里（实验 28 实测：计数是缓存里的一个时间戳列表）。用 `LocMemCache` 时，每个进程各存各的、各数各的，4 个进程就是 4 倍配额。

正确做法：限流必须用**共享**缓存后端（Redis/Memcached）。

顺带一个坑：清缓存会重置配额（实验 28 实测清缓存后 3 次请求全部放行）。Redis 重启、键过期，都会让限流"重新开始数"。
</details>

<details>
<summary>【6】判断题：<code>cache.set(key, None, 300)</code> 之后再 <code>cache.get(key)</code> 返回 None，说明这个键没被缓存。对吗？</summary>

**不对。** 实验 9 实测：`cache.set('p:empty', None, 300)` 之后，`cache.has_key('p:empty')` 返回 **True**——None 确实被存进去了。

`cache.get(key)` 返回 None 有两种可能：键不存在、键存在但值是 None。二者**无法从返回值区分**。改用 `cache.get(key, sentinel)` 也区分不了（对"缓存了 None"它照样返回 None）。

唯一可靠的判断是 `cache.has_key(key)`。这也是为什么"把空值缓存起来防穿透"的常见写法（用 `if cache.get(key) is None` 判 miss）**根本不起作用**——见实验 6，同一 id 查 5 次照样 5 条 SQL。
</details>

<details>
<summary>【7】你要缓存"用户的订单列表"，键该怎么设计？为什么不能用 <code>cache_page</code>？</summary>

**不能用 `cache_page`**：订单列表是私有数据，而 `cache_page` 的缓存键默认只含 URL（自定义身份头不进键，`Authorization` 有兜底但依赖中间件那一层）。一旦串号，A 用户会看到 B 用户的订单。

**用低层 API 把身份拼进键**（实验 29）：

```python
key = f"v1:user:{user.id}:orders"
data = cache.get_or_set(key, lambda: build_orders(user), 300)
```

实验 29 实测：带 `user_id` 的两个键互不干扰；不带 `user_id` 的键，user 2 直接读到了 user 1 的数据。

失效：订单状态变更时用 `transaction.on_commit(lambda: cache.delete(key))`。
</details>

<details>
<summary>【8】你的 async 视图用 <code>asyncio.gather</code> 并发调 3 个下游，其中一个是同步的 <code>requests.get</code>。P99 会改善吗？</summary>

**不会，大概率变差。** 实验 13 实测：async 函数里用 `time.sleep` 阻塞，5 次 50ms 等待仍要 253ms（对比 `asyncio.sleep` 的 54ms）。

原因：事件循环是单线程的，`requests.get` 这种同步阻塞调用会**卡死整个循环**——不只是那一个协程慢，是**所有协程一起等**，还多付了线程切换的开销。这正是开场接口 B 的场景。

修法：把同步 HTTP 客户端换成异步的（`httpx.AsyncClient` / `aiohttp`），或者把同步调用用 `sync_to_async(thread_sensitive=False)` 丢到独立线程（注意会增加线程数与连接数）。
</details>

<details>
<summary>【9】为什么 <code>@task</code> 装饰的函数必须定义在模块顶层？</summary>

`BaseTaskBackend.validate_task()` 里有硬性检查（`django/tasks/backends/base.py:47`）：

```python
if not is_module_level_function(task.func):
    raise InvalidTask("Task function must be defined at a module level.")
```

原因是任务要能被**序列化后跨进程传递**。看 `Task.__reduce__()`：它只存 `self.module_path`（`f"{func.__module__}.{func.__qualname__}"`），worker 侧靠 `import_string` 把它导回来。嵌套函数没有可导入的模块路径，自然无法重建。

我备课时就在函数内部定义任务，直接踩了这个错。
</details>

<details>
<summary>【10】单元测试里不想真跑任务，配了 <code>DummyBackend</code>，然后断言 <code>result.return_value is None</code>。会发生什么？</summary>

**断言永远跑不到——读 `return_value` 就抛 `ValueError: Task has not finished yet`。**

实验 21 实测：dummy 后端下 `status=READY`、`is_finished=False`。原因在 `django/tasks/base.py` 的 `return_value` 属性——它对非 `SUCCESSFUL` 状态一律抛错（`FAILED` 抛 "Task failed"，其他抛 "Task has not finished yet"）。

我原本预设会返回 None，实测推翻了这个预设。

正确断言方式：只断言任务被 enqueue 了（比如断言 `result.status == 'READY'`），或者用 `task_enqueued` 信号捕获（实验 26）。
</details>

<details>
<summary>【11】你的缓存用了"整列表一个键"，每次改一个商品都要重建整个列表。什么情况下该换成"对象级粒度"？换的时候要注意什么？</summary>

**该换的信号**：写操作频繁、且每次只影响列表里的一小部分（商品详情被频繁改价，但列表页有 1000 个商品）。

对照实验 4 的数据：

| 粒度 | 冷启动 | 改 1 个商品 |
|------|--------|------------|
| 整列表一个键 | 1 条 SQL | 清 1 个键，**但整列表重建** |
| 每个对象一个键 | **50 条 SQL** | 清 1 个键，精准 |

**换的时候最大的坑是循环里的数据库往返**（评审必查项 #28）。对象级粒度的列表拼装如果写成：

```python
objs = [cache.get_or_set(f"product:{pk}", lambda: Product.objects.get(pk=pk), 300)
        for pk in pks]
```

冷启动就是 **50 条 SQL**。生产写法必须用 `cache.get_many()` 一次批量取回，缺的再用 `filter(pk__in=...)` **一条 SQL** 补齐（见 1.2 节的代码）。

另外注意：对象级粒度下，**列表页拼装本身仍是 N 次 `get`**（虽然不打到数据库，但是 N 次网络往返到 Redis）。列表很长时，可以把"id 列表"和"对象字典"拆成两个键分别缓存。
</details>

<details>
<summary>【12】你想给热点键的 TTL 加抖动防雪崩，写了 <code>ttl = 60 + random.randint(0, 30)</code>。这够吗？</summary>

方向对，但实验 5 暴露了一个写法问题：**如果你在写入时用随机 TTL，却在别处（比如日志、监控）另外生成一次随机数去"记录"TTL，两边就对不上了**——我备课时就是这么写的，日志里的分布和实际写入的分布是两批随机数。

正确做法：**先生成 TTL，再用这个 TTL 去写，并复用同一个值做记录**。

```python
ttls = [60 + random.randint(0, 30) for _ in range(100)]
for i, ttl in enumerate(ttls):
    cache.set(f"jitter:{i}", value, ttl)   # 用的是采样到的那个 ttl
```

实测：抖动后 TTL 分布 60s~90s，不抖动时全部 60s（实验 5）。

补充：抖动只是防雪崩的** cheapest 一招**。热点键永不过期 + 后台异步刷新、或加互斥锁（只放一个请求去重建）是更彻底的方案。
</details>

---

## 事实核查说明

本课结论分四类标注，**未经实测的一律标明**：

| 结论 | 来源 |
|------|------|
| `TASKS` 默认后端是 `ImmediateBackend` | ✅ `global_settings.py:692` 源码明示 |
| 任务函数必须模块级 | ✅ `backends/base.py:47` 源码明示 + 实测踩到 |
| 任务参数须 JSON 兼容（`normalize_json`） | ✅ `utils/json.py` 源码明示 + 实测（实验 22） |
| `return_value` 对非 SUCCESSFUL 抛错 | ✅ `tasks/base.py` 源码明示 + 实测（实验 21、23） |
| `ImmediateBackend` 不支持 `run_after` | ✅ 实测 `InvalidTask`（实验 25） |
| 缓存键由 URL + Vary 构成 | ✅ `utils/cache.py` 源码明示（`_generate_cache_key`） |
| Django 自动为带 Authorization 的请求打 Vary | ✅ `middleware/cache.py` 源码明示 + 实测（实验 30、34） |
| async 上下文禁止同步 ORM（`SynchronousOnlyOperation`） | ✅ 官方文档明示 + 实测（实验 11） |
| `sync_to_async` 默认 `thread_sensitive=True` | ✅ 官方文档明示 + 实测（实验 14） |
| `LocMemCache` 是进程内缓存 | ✅ 官方文档明示 + 实测（实验 33） |
| **只有 `Authorization` 有 Vary 兜底，自定义身份头没有** | 🔬 **实测确认**（实验 3 vs 30）——文档未见集中说明 |
| **存 None 挡不住穿透（`get` 无键/None 不可区分）** | 🔬 **实测确认**（实验 6、9）· **本课首次** |
| **事务回滚后缓存留新值** | 🔬 **实测确认**（实验 7）· **本课首次** |
| **`DummyBackend` 读返回值抛 ValueError 而非返回 None** | 🔬 **实测确认**（实验 21）· **本课首次** |
| DRF 默认响应的 Vary 是 `Accept`，不含 Authorization | 🔬 **实测确认**（实验 34） |
| 内置框架无 Beat / 无重试 / 无编排 | 🔬 实测确认（实验 24、25）+ 官方文档定位为"任务契约层" |
| 多进程共享缓存（Redis/Memcached）的行为 | ⏳ **未经实测**（本机无 Redis），标注为"须在真实共享后端验证" |
| Celery 的具体能力（Beat/重试/编排） | ⏳ **未在本课实测**（本机无 Celery），引自 `celery-django` 课程 |

> ⚠️ 本课五条"实测确认但文档未集中说明"的结论（Vary 兜底范围、空值缓存失效、事务回滚留脏缓存、DummyBackend 抛错、DRF 默认 Vary）都属于**实现行为**而非契约保证。Django 7.0 升级时需重新跑 `run_lab1.py` / `run_lab3.py` / `run_lab4.py` 验证。

---

## 验证环境

| 项 | 值 |
|----|-----|
| Django | **6.1** |
| DRF | **3.18.0** |
| Python | **3.13.14**（Windows 托管 venv `dj-course`） |
| 数据库 | SQLite（内存库） |
| 缓存 | `LocMemCache`（default + redis_like）+ `DummyCache`（null） |
| 任务后端 | `ImmediateBackend`（默认）+ `DummyBackend`（独立 settings 验证） |
| 实验工程 | `%TEMP%/dj-lesson16-demo/cachelab` |
| 实验数 / 断言数 | **34 个实验 / 95 项断言**，零失败 |

> ⚠️ **环境受限说明（必查项 #20）**：
> ①**本机无 Redis**，缓存实验用 `LocMemCache`。缓存的层级/粒度/失效时机/键构成都是 Django Python 侧行为，完整可复现；唯独"多进程共享"这一点只能靠两个 alias 模拟对照（实验 33），**真实 Redis 行为须在生产同类型后端验证**。
> ②**本机无 Celery**，内置框架的能力缺口全部实测，"Celery 有这些能力"引自既有课程，未在本课实跑。
> ③**未使用 WSL**（课 2 起 `wsl.exe` 被本机安全策略拦截），全程 Windows 托管 Python。
>
> 所有命令均为 PowerShell 语法，已在上述环境逐条跑通。

---

🚀 **下一批接力提示词**

> 课 17《信号：隐式耦合的代价》。带上这三个问题：
> 1. **信号默认不跨事务** —— 本课实验 26 已经碰到（`task_finished` 是 Django signal）。课 17 要展开：为什么"用 `post_save` 发通知最解耦"是最危险的写法，以及 `on_commit` 怎么配合
> 2. **信号的隐式代价** —— 循环触发、`bulk_create` 不发信号、测试里静默跳过，这三处坑怎么发现和规避
> 3. **什么时候必须拆掉信号** —— 给一条从信号改显式调用的迁移路径
>
> 提示：本课实验工程在 `%TEMP%/dj-lesson16-demo/cachelab`，课 17 可复用 `labkit.py` 的 `Check` 断言器，做"信号到底执行了几次"的量化对照。

---

🧭 **课程导航**

- ⬅️ 上一课：[课 15《ORM 进阶与 N+1 治理》](./lesson-15-ORM进阶与N+1治理.md)
- ➡️ 下一课：[课 17《信号：隐式耦合的代价》](./lesson-17-信号隐式耦合的代价.md)
- 📖 所属阶段：[阶段 5 性能与异步](../overview.md)
- 🏠 课程目录：[02-课程目录.md](../../../02-课程目录.md)
- 🗺️ 学习路径：[01-学习路径总览.md](../../../01-学习路径总览.md)

---

> 📊 本课数据：34 个实验 · 95 项断言 · 5 幕 · 12 道自检题 · 4 处"不报错的错误"（阶段 5 累计 8 处）
