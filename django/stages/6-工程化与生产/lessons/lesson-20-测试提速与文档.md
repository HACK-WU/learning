# 课 20　测试提速与文档

> 📖 情节定位：**收尾（二）** —— 敢重构，且别人看得懂，且跑得够快
> 🎯 本课目标：核心接口有测试覆盖，测试套件跑得动，文档自动生成

## 知识点清单

### 知识点 1：API 测试策略与 DRF 测试工具
- 关键点：测试金字塔 / APIClient / 认证绕过 / 工厂造数据（factory_boy）/ mock 外部服务

### 知识点 2：测试提速
- 关键点：`--keepdb` 复用测试库 / `MIGRATION_MODULES` 禁用迁移直接建表 / `--parallel` / 各自的代价与坑

### 知识点 3：接口文档：OpenAPI 自动生成
- 关键点：drf-spectacular 接入 / 注解方式 / 与版本控制的配合 / 维护策略

---

## 本课衔接

课 19 把文件与 Admin 的行为验证了一遍，留了三个问题给本课：

1. **"能跑"不等于"跑得快"** —— 验证写完了，但跑一遍要多久？测试变慢的根因往往不是测试本身，而是数据库与 IO
2. **文档的归属** —— 课 19 的"打印真实生效值"思路要延续到文档：**字段说明必须来自真实响应，而不是手写**
3. **Admin 的文档化** —— 内部后台的操作约定（谁能删、批量操作不触发 signal）也得写进文档

本课三个知识点正好对应：怎么写测试（知识点 1）、怎么让测试跑得动（知识点 2）、怎么让别人看得懂（知识点 3）。

---

## 验证环境

本课结论全部来自独立实验工程的实测，不是凭印象写的。

| 项目 | 值 |
|---|---|
| Django | 6.1 |
| DRF | 3.18.0 |
| Python | 3.13.14 |
| factory_boy | 3.3.3 |
| Faker | 40.38.0 |
| drf-spectacular | 0.30.0 |
| PyYAML | 6.0.3 |
| jsonschema | 4.26.0 |
| 数据库 | SQLite（文件库，非内存库） |
| 实验工程 | `%TEMP%/dj-lesson20-demo/testlab` |
| 实验规模 | 42 个实验 / 103 条断言 / 11 个独立进程探针 |

⚠️ **数据库选型说明**：本课刻意用 SQLite **文件库**而非内存库。因为 `--keepdb` 的语义就是"复用库文件"，用内存库根本体现不出差别——这一点在实验 21 会看到它的代价。

⚠️ **Windows 环境提醒**：跑实验前必须设 `$env:PYTHONIOENCODING="utf-8"`，否则中文输出会 `UnicodeEncodeError`。

---

# 第一幕　场景引入：一个跑不动的测试套件

## 1.1 从一个真实的困境开始

假设你接手了一个订单系统，测试大概长这样：

```python
class OrderAPITest(APITestCase):
    def setUp(self):
        # 每个用例都要造一套完整数据
        self.user = User.objects.create_user(username="tester", password="pw123456")
        self.category = Category.objects.create(name="图书")
        self.product = Product.objects.create(
            name="Django 入门", category=self.category, price=9900, stock=100
        )

    def test_create_order(self):
        self.client.force_authenticate(user=self.user)
        resp = self.client.post("/api/orders/", {...})
        self.assertEqual(resp.status_code, 201)

    def test_list_orders(self):
        ...
```

这套测试能跑通，`coverage` 也好看。但三个月后它长到了 800 个用例，跑一遍要 **11 分钟**。

于是团队开始这样的对话：

> A：测试太慢了，加个 `--parallel` 吧。
> B：我加了，没变快多少。
> A：那再加 `--keepdb`。
> B：也加了，还是慢。
> A：那就禁掉迁移，`MIGRATION_MODULES` 设成 None。
> C：等等……我们到底在优化什么？

这个对话的问题在于：**三个人都在猜**。本课要做的，就是把这三个手段各自省了什么、代价是什么，一个一个量出来。

## 1.2 本课的第一个主张

先给结论，后面全部用实验坐实：

> **测试提速不是"开关三连"，而是"先量后改"。**
> 优化之前必须知道时间花在哪，否则三个手段可能一个都没打中痛点——甚至更慢。

实验 41 会给一个"体检脚本"，把测试耗时拆成**建库 / 造数 / 执行**三段。本课实测结果是：

```text
PHASE_SETUP_MS = 150.4  (78%)   ← 建库
PHASE_SEED_MS  =  34.4  (18%)   ← 造数
PHASE_RUN_MS   =   7.6  ( 4%)   ← 执行
TOTAL_MS       = 192.4
```

**执行只占 4%。** 如果一上来就优化"用例怎么写"，最多只能省 4%——这就是为什么很多人的提速努力是无效的。

### 1.2.1 现在就量一下你自己的工程

不要等到读完第三幕。把下面这段存成 `test_health.py` 放到项目根目录，直接跑：

```python
"""测试体检：把耗时拆成 建库 / 造数 / 执行 三段。

用法：python test_health.py [测试标签]
"""
import os
import sys
import time

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")

import django  # noqa: E402

django.setup()

from django.test.runner import DiscoverRunner  # noqa: E402
from django.test.utils import setup_test_environment, teardown_test_environment  # noqa: E402


def main(label):
    setup_test_environment()
    runner = DiscoverRunner(verbosity=0, interactive=False)

    t0 = time.perf_counter()
    old_config = runner.setup_databases()          # ① 建库（create + migrate）
    setup_ms = (time.perf_counter() - t0) * 1000

    t1 = time.perf_counter()
    suite = runner.build_suite([label]) if label else runner.build_suite([])
    build_ms = (time.perf_counter() - t1) * 1000   # ② 造数（setUpTestData / factory 都在这）

    t2 = time.perf_counter()
    result = runner.run_suite(suite)               # ③ 执行
    run_ms = (time.perf_counter() - t2) * 1000

    runner.teardown_databases(old_config)
    teardown_test_environment()

    total = setup_ms + build_ms + run_ms
    print(f"\n{'阶段':<8}{'耗时':>12}{'占比':>10}")
    print(f"{'建库':<8}{setup_ms:>10.1f} ms{total and setup_ms/total*100:>9.0f}%")
    print(f"{'造数':<8}{build_ms:>10.1f} ms{total and build_ms/total*100:>9.0f}%")
    print(f"{'执行':<8}{run_ms:>10.1f} ms{total and run_ms/total*100:>9.0f}%")
    print(f"{'合计':<8}{total:>10.1f} ms")
    print(f"用例数 = {result.testsRun}，失败 = {len(result.failures) + len(result.errors)}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "")
```

⚠️ 注意：这里的"造数"测的是**收集测试 + 执行类级 `setUpTestData`** 的时间，`setUp` 里的造数算在"执行"里。要区分两者，得配合实验 15 的对照思路单独测。

跑出来之后，看哪一坨最大，直接跳到对应小节：

| 最大的是 | 跳到 | 主要手段 |
|---|---|---|
| 建库 | 3.2.3 | 禁所有 app 的迁移（2.77x） |
| 造数 | 3.1.4 | `build_batch + bulk_create`（4.3x）、复用关联对象 |
| 执行 | 3.1.6 | mock 外部 IO（144x）、`setUpTestData`（10x） |

---

# 第二幕　认知冲突：三个"常识"都是错的

这一幕是本课最值钱的部分。我们对三个流行说法做了实测，**全部被推翻**。先把冲突摆出来，第三幕逐个拆解。

## 2.1 冲突一：`--keepdb` 省掉建库，应该明显更快

**流行说法**：keepdb 复用测试库，不用每次重建，肯定快。

**实测**（实验 21，SQLite 文件库）：

```text
冷启动（重建库）: 126.9 ms
keepdb（复用库）: 145.8 ms
提速 = 0.87x   ← 不但没快，还略慢
```

不是抖动。我们做了三组交叉验证：

**验证 A：放大迁移数量。** 如果 keepdb 真省掉迁移，迁移越多收益应该越大。

```text
  0 个追加迁移: 冷 135ms vs 热 147ms
100 个追加迁移: 冷 168ms vs 热 170ms   ← 差距没有拉开
```

**验证 B：决定性实验。** 先用 keepdb 建好库，再往磁盘加一个带 `RunPython` 的数据迁移，然后**再次用 keepdb 打开同一个库**，看这个新迁移会不会被执行：

```text
APPLIED_TOTAL   = 21          ← 从 20 涨到 21
NEW_MIG_APPLIED = True        ← 新迁移被应用了
ROWS            = 1           ← 连 RunPython 灌的数据都在
```

**结论**：keepdb **照样跑 migrate**，连数据迁移都跑。它省掉的只是"删库 + 建文件"，而这在 SQLite 上本来就不值钱。

源码依据在 `django/db/backends/base/creation.py`：

```python
# 我们本可以在 keepdb 为 True 时跳过这次调用，
# 但我们选择把 keepdb 参数传进去
call_command(
    "migrate",
    run_syncdb=True,
    ...
)
# 原文注释：We could skip this call if keepdb is True,
#           but we instead give it the keepdb param
```

## 2.2 冲突二：`--parallel=4` 就能快 4 倍

**流行说法**：4 个进程并行，快 4 倍。

**实测**（实验 24，24 个用例 / 4 个 TestCase 类）：

```text
每用例 0.05s:  parallel=1 → 1222 ms，parallel=4 → 1230 ms   （0.99x，几乎没变）
每用例 0.5s :  parallel=1 → 12022 ms，parallel=4 → 3987 ms  （3.02x）
```

**同样的代码、同样的并行度，短任务毫无收益，长任务快 3 倍。**

原因是有两个门槛（实验 24 逐个拆开）：

**门槛一：并行度按 TestCase 类切分，不是按方法。**

```text
集中在 1 个类: SUBSUITE_COUNT = 1 → EFFECTIVE_PROCESSES = 1   ← 并行度退化为 1
拆成 4 个类  : SUBSUITE_COUNT = 4 → EFFECTIVE_PROCESSES = 4
```

如果你把 200 个用例全塞在一个 `class OrderTest(APITestCase)` 里，那 `--parallel=8` 和 `--parallel=1` 没有任何区别。

**怎么查自己的工程有没有踩中？** 用 `--collect-only` 拿全部用例，按类统计分布：

```bash
python manage.py test --collect-only -v 2 2>&1 | grep -oE '^[a-zA-Z_]+\([a-zA-Z0-9_.]+\)' | sed 's/.*(//;s/)//' | sort | uniq -c | sort -rn | head -20
```

输出形如：

```text
187 apps.shop.tests.OrderTest      ← 一个"巨无霸类"，并行度直接退化为 1
 42 apps.shop.tests.ProductTest
 23 apps.user.tests.UserTest
```

如果第一行远超其他行，你的 `--parallel` 基本白开了。

Windows PowerShell 等价写法：

```powershell
python manage.py test --collect-only -v 2 2>&1 |
  Select-String -Pattern '^[a-zA-Z_]+\(([a-zA-Z0-9_.]+)\)' |
  ForEach-Object { $_.Matches[0].Groups[1].Value } |
  Group-Object | Sort-Object Count -Descending | Select-Object -First 20 Count, Name
```

⚠️ 注意这只是**估算**——真正的 subsuite 数量由 `partition_suite_by_case` 决定，还受用例顺序影响（它用 `itertools.groupby(all_tests, type)`，**相邻**的同类才合并，所以同一个类被别的类隔开时可能拆成多个 subsuite）。要精确值可以用 Django 的 API 直接问：

```python
from django.test.runner import DiscoverRunner
from itertools import groupby

runner = DiscoverRunner(verbosity=0, interactive=False)
suite = runner.build_suite([])
subsuites = list(groupby(suite, type))
print(f"SUBSUITE_COUNT = {len(subsuites)}")
```

**门槛二：有一笔约 800ms 的固定开销，与任务量无关。**

```text
0 工作量：parallel=1 用 11 ms，parallel=4 用 860 ms
→ 固定开销 ≈ 849 ms（4 个 worker 的 spawn + 各自建库）
```

这两个门槛合起来可以建模：

```text
并行耗时 ≈ 固定开销 + 串行工作量 / 并行度
```

我们用这个模型预测长任务：`849 + 12022/4 = 3854 ms`，实测 `3987 ms`，**误差 3.4%**。模型成立。

由此可以算出**盈亏平衡点**（解 `T = 开销 + T/4`）：

```text
T = 4/3 × 849 ≈ 1132 ms
```

**串行耗时低于约 1.1 秒时，开 4 进程并行是净亏的。**

## 2.3 冲突三：keepdb + 禁迁移 = 表结构与模型不同步（危险组合）

**流行说法**：keepdb 跳过建库，禁迁移又跳过迁移，那模型改了表不会跟着变，测试会神秘失败。

**实测**（实验 42）：keepdb 时 Django 依然调用 `migrate`，于是：

```text
第一轮 建库  : MIGRATE_CALLED = 1 次，run_syncdb=[True]
第二轮 加字段: MIGRATE_CALLED = 1 次，run_syncdb=[True] | LATER_ADDED_TYPE = varchar(20)
第三轮 删字段: MIGRATE_CALLED = 1 次，run_syncdb=[True] | STOCK_STILL_IN_DB = False
```

**加字段能补上（varchar(20) 建出来了），删字段也能同步（字段确实从库里消失了）。**

这个组合比传说中安全得多。它真正的危险在别处——实验 19 会给出：**数据迁移（RunPython）会被完全跳过**。

## 2.4 冲突四（附加）：`setUpTestData` 的对象是共享的

**流行说法**：`setUpTestData` 里创建的对象在测试间共享，改了会"串味"，所以要小心可变对象。

**实测**（实验 25，Django 6.1）：**不共享。**

Django 6.1 有 `TestData` 描述符 + deepcopy 保护：

```python
# django/test/testcases.py
class TestData:
    def __get__(self, instance, owner):
        return deepcopy(self.data)   # 每次拿到的都是副本
```

实测三条断言全绿：

```text
✅ Django 6.1 存在 TestData 描述符机制      django.test.testcases.TestData
✅ 模型对象不共享（每个测试拿到的是 deepcopy） 改了 self.product.name 不影响下一个测试
✅ 连普通可变容器（dict）也一起被拷贝        cls.bag['count'] 的修改也没串到下一个测试
```

⚠️ 这一点版本相关。老版本 Django（3.2 之前）确实共享。但**在 Django 6.1 上，你不需要为此焦虑**。

---

# 第三幕　层层揭示：三个手段的真实账本

## 3.1 知识点 1：API 测试策略与 DRF 测试工具

### 3.1.1 Django Client 与 APIClient 到底差在哪

先做一个最朴素的对照（实验 1、2）。预设是"Django Client 拿到 HttpResponse，APIClient 拿到 DRF Response"。

**实测：预设错了。**

```text
Django Client : type=Response status=403 len=43
APIClient     : type=Response status=403 len=43
Django Client 有 .data = True（预设：没有）
APIClient 有 force_authenticate = True
Django Client 有 force_authenticate = False
```

两者拿到的**都是** `rest_framework.response.Response`，都有 `.data`，内容类型都是 `application/json`。

原因很简单：DRF 的 `Response` 是 `HttpResponse` 的子类，渲染由 Django 的 handler 统一完成。**用哪个 Client 不影响渲染结果。**

真正的差异只有一条：

> **`force_authenticate` 是 `APIClient` 专属。** 原生 Django Client 要绕认证，只能用 `force_login`（走 session 那一套）。

### 3.1.2 `force_authenticate` 的真实机制（实验 4）

预设是"直接把 user 塞进 request"。读源码后发现**不是**。

`rest_framework/test.py` 只做了一件事：

```python
def force_authenticate(self, request, user=None, token=None):
    request._force_auth_user = user
    request._force_auth_token = token
```

真正的生效点在 `rest_framework/request.py`：构造 `Request` 时检测到 `_force_auth_user`，就把 `authenticators` **整体替换**：

```python
if force_user is not None or force_token is not None:
    self.authenticators = (ForcedAuthentication(force_user, force_token),)
```

实测对照（实验 4）：

```text
A 组 未 force：认证类调用 1 次，user = AnonymousUser
B 组 force 后：authenticators = ['ForcedAuthentication']
               认证类调用 0 次，user = tester
```

**这意味着什么**：你自定义的认证类在 force 之后**一次都不会被调用**。所以如果你的认证类里有副作用（写审计日志、刷新 token 缓存），force 之后这些副作用全部消失——测试环境和生产环境的行为差异就是这么来的。

### 3.1.3 绕过认证 ≠ 绕过权限（实验 5）

这是个高频误区。`force_authenticate` 只解决了"你是谁"，没解决"你能不能干这事"。

实测（实验 5）：

```text
noperm 用户权限数 = 0
IsAuthenticated 接口: HTTP 200
DjangoModelPermissions.perms_map['GET'] = []
DjangoModelPermissions.perms_map['POST'] = ['%(app_label)s.add_%(model_name)s']
零权限用户 GET  /probe/ : HTTP 200
零权限用户 POST /probe/ : HTTP 403
```

这里还挖出一个反直觉细节：**`DjangoModelPermissions` 的 `perms_map['GET']` 是空列表**（源码 `permissions.py:191-201`）。也就是说，用 `DjangoModelPermissions` 时，任何已认证用户都能 GET，不需要任何模型权限。

> 所以「我给接口加了 DjangoModelPermissions，读接口就安全了」这句话是错的。读权限得靠别的机制。

### 3.1.4 factory_boy：造数据的代价（实验 7-9）

`build()` 不落库、`create()` 落库，这是基础（实验 7）：

```text
build()  前 2 → 后 2  (pk=None)
create() 后 3  (pk=3)
```

真正的坑在 **SubFactory 的默认行为**（实验 8）：

```text
默认（SubFactory 每次新建 category + user）: 5 个订单 = 50 条 SQL
复用 user + category                      : 5 个订单 = 10 条 SQL
```

**5 倍的差距。** 每个订单都顺手新建了分类和用户，5 个订单建了 5 个新分类。

⚠️ 这里有个调试陷阱：`CategoryFactory` 如果配了 `django_get_or_create = ("name",)`，同名分类会被复用（"查而不建"），SQL 数会**骗你**。实测时必须给每个分类不同名字，才能量出 SubFactory 的真实代价。

规模化对照（实验 9）：

```text
create_batch(1000)            = 183.4 ms
build_batch + bulk_create(1000) =  42.7 ms
比值 = 4.30x
```

> 造 1000 条数据，`create_batch` 比 `build_batch + bulk_create` 慢 4.3 倍。造数据也是 IO，也会成为瓶颈——这直接连着实验 41 里"造数占 18%"那个数字。

**这个规则对本课自己也适用。** 本课的实验工程里有一个数据迁移 `0002_seed_categories.py`，第一版是这么写的：

```python
# ❌ 第一版：循环体内有数据库操作
def seed_categories(apps, schema_editor):
    Category = apps.get_model("shop", "Category")
    for name in SEED:
        Category.objects.create(name=name)      # 3 次 INSERT
```

种子数据只有 3 条，跑起来毫无问题。但按必查项 #28 的规则——**示例给学员的练手数据量必须小到能跑，但示例本身的写法必须大到 10 万行也不炸**——这个写法不合格。改成：

```python
# ✅ 改成：一次入库，且重跑不炸唯一约束
def seed_categories(apps, schema_editor):
    Category = apps.get_model("shop", "Category")
    Category.objects.bulk_create(
        [Category(name=name) for name in SEED],
        ignore_conflicts=True,
    )
```

**为什么 3 条数据也要改**：种子数据会随业务增长，而且 keepdb 场景下这个迁移可能被反复执行（2.1 节证明了 keepdb 照样跑迁移）。`ignore_conflicts=True` 就是为这个场景准备的——没有它，重跑会撞唯一约束。

这就是必查项 #28 的执行方式：**翻到讲义里每一个 for 循环，问一句"循环体里有没有数据库/IO 操作"**。本课 25 处 for 循环里，只有这一处命中。

### 3.1.5 mock 打点位置：这是个经典坑（实验 10、11）

`mock.patch` 打错位置是最高频的错误之一。我们造了三种调用写法来对照：

```python
# 写法 A：在 services 里绑定名字
from .payments import charge          # services.py
def pay_order(...): charge(...)

# 写法 B：在 views 里绑定名字
from .payments import charge as payments_charge    # views.py

# 写法 C：晚绑定，每次走模块属性
from . import payments                 # views.py
payments.charge(...)
```

实验 10（直接调函数）：

```text
patch payments.charge 后，services 里那个 charge 仍是: apps.shop.payments.charge
patch services.charge 后 pay_order: ok=False, msg='B 被 mock'
```

实验 11（走真实 HTTP，四组对照）：

```text
A 组 patch services.charge            → HTTP 402   ✅ 生效
B 组 patch views.payments_charge      → HTTP 400   ✅ 生效
B 组 patch payments.charge（定义处）   → HTTP 200   ❌ 无效
C 组 patch payments.charge（定义处）   → HTTP 400   ✅ 生效
```

**规则一句话**：

> **patch 你使用它的那个名字，不是定义它的那个名字。**
> 例外：晚绑定写法（C 组）下，patch 定义处也生效——因为每次调用都重新查模块属性。

### 3.1.6 测试金字塔：用数字说话（实验 12-14）

**mock 掉外部 IO 值不值？**（实验 12）

```text
真实 IO（网关 sleep 1ms × 50 次）= 66.8 ms
mock 后                          =  0.5 ms
比值 = 144.1x
```

144 倍。外部 IO 是测试变慢的头号元凶。

**同一逻辑测 service 层还是测 API 层？**（实验 13）

```text
service 层: 3 条 SQL, 0.4 ms
API 层    : 5 条 SQL, 6.5 ms
```

API 层测试更慢（走完整请求栈：路由、中间件、认证、权限、序列化）。**这不是说不要写 API 测试**，而是说：业务逻辑应该在 service 层测（快且多），API 层只测契约（状态码、字段结构、权限）。

**三个 TestCase 基类的取舍**（实验 14）：

```text
TestCase               20 个空用例 =    2.7 ms
TransactionTestCase    20 个空用例 =  153.7 ms
SimpleTestCase         20 个空用例 =    0.4 ms
```

`TransactionTestCase` 比 `TestCase` 慢 **57 倍**——因为它每个用例都要 `flush` 数据库（truncate 所有表 + 重建）。

| 基类 | 隔离方式 | 20 空用例 | 什么时候用 |
|---|---|---|---|
| `SimpleTestCase` | 禁止数据库访问 | 0.4 ms | 纯逻辑、不碰 DB |
| `TestCase` | 事务回滚 | 2.7 ms | **默认选这个** |
| `TransactionTestCase` | flush 全库 | 153.7 ms | 必须测事务行为时 |

⚠️ `SimpleTestCase` 的 `databases` 默认是空集，查数据库会直接抛 `AssertionError`（实测确认）。这是特性不是 bug——它帮你抓住"这个测试其实不该碰数据库"。

**`setUpTestData` vs `setUp`**（实验 15）：

```text
setUpTestData    11 个用例 × 造 30 条 =   18.3 ms
setUp            11 个用例 × 造 30 条 =  188.4 ms
```

10 倍差距。**类级不变的数据永远放 `setUpTestData`**——而且实验 25 已经证明，Django 6.1 下不用担心对象共享问题。

## 3.2 知识点 2：测试提速的真实账本

### 3.2.1 先量后改：体检脚本（实验 41）

```text
PHASE_SETUP_MS = 150.4  (78%)   ← 建库（create + migrate）
PHASE_SEED_MS  =  34.4  (18%)   ← 造数（factory_boy）
PHASE_RUN_MS   =   7.6  ( 4%)   ← 执行（跑用例）
TOTAL_MS       = 192.4
```

本课这个测试工程的结论很明确：**78% 在建库**。所以提速的第一刀应该砍在数据库上，而不是砍在"用例怎么写"。

⚠️ 但**这不是通用结论**。你的工程可能是"造数占大头"（比如大量用了 `create_batch` 而非 `bulk_create`），也可能是"执行占大头"（比如大量真实 HTTP 调用没 mock）。**先体检，再动手。**

### 3.2.2 手段一：`--keepdb`（实验 21-23）

**回到 2.1 的发现**——keepdb 省掉的只有"删库 + 建文件"，**迁移照样跑**。所以它的收益完全取决于"建一个库"这件事本身有多贵。

**实测收益（SQLite）**：接近零，甚至略慢（126.9 → 145.8 ms）。

⚠️ 这个结论**强依赖于数据库类型**。SQLite 建文件几乎不花钱，所以省不掉什么。换成 PostgreSQL / MySQL（建库要网络连接、要建 schema），keepdb 的收益会明显得多。**不要把这个数字直接搬到你自己的工程上**——它就是"先量后改"的最好注脚。

**两个必须知道的坑**：

**坑一：模型改了但库是旧的**（实验 22）。keepdb 下改了模型，Django 不会重建表，你会得到一个"表和模型对不上"的库：

```text
AFTER_FIELDS = [..., 'tmp_probe_field']     ← 模型里有
SELECT_NEW_COLUMN_ERROR_MSG = no such column: shop_product.tmp_probe_field
STALE_DETECTED
```

好消息是它会**报错**而不是静默用旧表——你会看到 `OperationalError: no such column`，不会得到一个"测试莫名失败"的黑盒。

**坑二：隔离性会有问题吗？**（实验 23）**不会。**

```text
TEST_B_SEES_MARKER = False
ISOLATION_OK = True
```

`TestCase` 的隔离靠**事务回滚**，跟"库是不是复用的"完全无关。keepdb 复用的是"已建好的库"，不是"上一个测试留下的数据"。

### 3.2.3 手段二：`MIGRATION_MODULES` 禁用迁移（实验 16-19）

**它省了什么**：跑全部迁移，改成按当前模型直接建表。

**关键发现：禁谁，决定了有没有用。**（实验 18）

```text
默认（跑全部迁移）  应用迁移  20 个，建表 13 张，耗时 158.0 ms
只禁 shop          应用迁移  18 个，建表 13 张，耗时 142.4 ms   ← 几乎没用
禁所有 app         应用迁移   0 个，建表 12 张，耗时  57.0 ms   ← 2.77x
```

**只禁业务 app 是无效的**，因为 `django.contrib` 那 18 个迁移照跑（auth 12 个 + admin 3 个 + contenttypes 2 个 + sessions 1 个）。

配置必须这样写：

```python
MIGRATION_MODULES = {
    "shop": None,
    "admin": None,
    "auth": None,
    "contenttypes": None,
    "sessions": None,
}
```

**怎么枚举"所有 app"？** 手写容易漏，直接由 `INSTALLED_APPS` 生成：

```python
# settings_test.py
MIGRATION_MODULES = {
    app.split(".")[-1]: None for app in INSTALLED_APPS
}
```

⚠️ 两个注意点：

1. 键要用 **app_label**（`INSTALLED_APPS` 里常见写法是 `django.contrib.auth`，而 app_label 是 `auth`），所以上面做了 `split(".")[-1]`
2. 这样会**连你自己的业务 app 一起禁掉**。如果某个 app 有 `RunPython` 数据迁移（见下面的代价），要把它从字典里剔除：

```python
MIGRATION_MODULES = {
    app.split(".")[-1]: None
    for app in INSTALLED_APPS
    if app.split(".")[-1] not in ("shop",)   # shop 有数据迁移，不能禁
}
```

**怎么知道哪些 app 有数据迁移？** 搜 `RunPython`：

```bash
grep -rl "RunPython" --include="*.py" .
```

**迁移越多，收益越大**（实验 18 放大验证，把 shop 迁移链式放大到 61 个）：

```text
跑迁移 : 应用 80 个，耗时 152.5 ms
禁所有 : 应用  0 个，耗时  52.1 ms
放大后提速 = 2.93x（小工程时只有 2.77x）
```

**代价：数据迁移会完全不执行。**（实验 19）

```text
跑迁移      : 建库后 Category 数 = 3  ['图书', '数码', '家居']
禁所有迁移  : 建库后 Category 数 = 0  []
```

**表在，数据没了。** 这是最危险的代价，因为它不会报错——你的测试会以一种"看起来像业务逻辑错了"的方式失败。

> 判断标准：如果你的工程有 `RunPython` 数据迁移（灌初始数据、回填历史数据），就**不要**全局禁用迁移。要么只禁没有数据迁移的 app，要么在测试里显式补种数据。

### 3.2.4 手段三：`--parallel`（实验 20、24）

这一节的完整数据已经在 2.2 给出（两个门槛 + 盈亏平衡点 ≈ 1132ms）。这里只补代价与使用建议。

**每个 worker 一份独立数据库**（实验 20）：

```text
DiscoverRunner.parallel 的语义：
setup_databases 源码中是否处理 parallel: True
```

`--parallel=4` 意味着 4 个进程 × 各自建一份测试库。内存、连接数、磁盘都 ×4。在 CI 容器里这是实打实的资源压力。

**收益模型**（实验 24，本机 20 核 / Windows spawn）：

```text
并行耗时 ≈ 固定开销(约 850ms) + 串行工作量 / 并行度
```

四组实测：

| 任务量 | parallel=1 | parallel=4 | 加速比 |
|---|---|---|---|
| 每用例 0.05s（24 用例） | 1222 ms | 1230 ms | 0.99x |
| 每用例 0.5s（24 用例） | 12022 ms | 3987 ms | 3.02x |

**使用建议**：

1. **测试要拆到多个 TestCase 类**。全塞一个类里，并行度直接退化为 1
2. **串行跑一遍超过 2-3 秒再考虑开并行**。低于盈亏平衡点（本机约 1.1 秒）是净亏
3. **注意资源**。4 进程 = 4 份数据库

⚠️ Windows 的 spawn 模式进程启动开销显著高于 Linux 的 fork。本课的 850ms 固定开销是 **Windows 数字**，Linux 上会低不少，但"有固定开销"这个结论是通用的。

### 3.2.5 组合拳（实验 40）

三个手段作用在不同阶段，可以叠加。实测四组 `SETUP` 耗时：

```text
baseline（什么都不做）: 156.0 ms
nomig（只禁迁移）    :  60.2 ms   ← 打中建库，效果最好
keepdb（只复用库）   : 143.5 ms   ← SQLite 上几乎没用
combo（全开）        :  74.8 ms
```

⚠️ 注意 `combo (74.8ms)` 比 `nomig (60.2ms)` **还慢**。这不是矛盾——它印证了 2.1 的结论：keepdb 不但不省，还要额外付"检查库是否存在、比对状态"的成本。**在 SQLite 上，keepdb 是负收益。**

正确的组合是：**禁迁移（打中建库）+ 造数优化（打中 18%）+ mock 外部 IO（打中执行）**。keepdb 只在昂贵的数据库上才值得开。

## 3.3 知识点 3：接口文档自动生成

### 3.3.1 接入 drf-spectacular

两步：

```python
# settings.py
REST_FRAMEWORK = {
    "DEFAULT_SCHEMA_CLASS": "drf_spectacular.openapi.AutoSchema",
}

SPECTACULAR_SETTINGS = {
    "TITLE": "订单 API",
    "VERSION": "1.0.0",
    "SERVE_INCLUDE_SCHEMA": False,
}
```

```python
# urls.py
from drf_spectacular.views import (
    SpectacularAPIView,
    SpectacularSwaggerView,
)

urlpatterns = [
    ...
    path("api/schema/", SpectacularAPIView.as_view(), name="schema"),
    path("api/schema/swagger-ui/",
         SpectacularSwaggerView.as_view(url_name="schema"), name="swagger-ui"),
]
```

实测（实验 39）：

```text
GET /api/schema/            → HTTP 200, Content-Type=application/vnd.oai.openapi
GET /api/schema/swagger-ui/ → HTTP 200
schema 前 60 字符 = openapi: 3.0.3 / info: / title: 订单 API / version: 1.0.0
```

### 3.3.2 文档的字段从哪来：呼应课 19

课 19 的接力提示词里说：**文档的字段说明要来自真实响应，而不是手写**。

自动生成天生满足这一点——但**必须验证**。实验 31 做了对照：

```text
文档里的 Product 字段 = ['category', 'category_name', 'created_at', 'id', 'name', 'price', 'status', 'stock']
真实响应的字段        = ['category', 'category_name', 'created_at', 'id', 'name', 'price', 'status', 'stock']
只在文档里            = []
只在响应里            = []
```

**零差异。** 但请保留这个对照测试——它是文档可信度的守门员。

### 3.3.3 文档漂移与组件缓存（实验 32）

**预设**：改了 serializer，schema 立即跟着变。
**实测**：会变，但**组件名也跟着变**——这是个真坑。

```text
改动前: PRODUCT_FIELDS = ['category', 'category_name', ..., 'stock']
改动前: CACHE_HIDES_CHANGE = True
改动后: PRODUCT_FIELDS = []
改动后: RENAMED_COMPONENTS = ['Drifted', 'DriftedStatusEnum', 'PaginatedDriftedList']
改动后: SCHEMA_REFLECTS_CHANGE = True
```

两点：

1. **自动生成不漂移**。改了 serializer 文档立刻反映，不会像手写文档那样滞后
2. **组件名随 serializer 类名变**。把 `ProductSerializer` 改名成 `DriftedSerializer`，文档里的组件就从 `Product` 变成 `Drifted`——**对前端是破坏性变更**，生成代码的字段名全变

⚠️ **组件缓存**：`CACHE_HIDES_CHANGE = True` 说明同一进程内改 serializer 拿不到新定义（drf-spectacular 按组件名缓存）。所以 A/B 对照**必须分进程**跑。

### 3.3.4 注解能补什么（实验 28、29、35-38）

**内部字段泄漏**（实验 28）——这是最该警惕的。`Order` 模型有一个 `internal_note` 内部字段。预设是 `fields = '__all__'` 会让它出现在 `Order` 组件里。

**实测：预设错了，但更值得警惕。**

```text
LEAKED_COMPONENTS = ['AllFields']    ← 泄漏在新组件里，不是原 Order 组件
```

`__all__` 生成的是一个**新的** `AllFields` 组件，内部字段泄漏在那里。这意味着：

> 泄漏不会"污染"你已经发布的 `Order` 组件，但它**确实出现在文档里**了，而且藏在一个名字不直观的新组件中，更容易被漏审。

**枚举、只读、分页、认证的文档形态**（实验 35-38）：

```text
ProductStatusEnum = {"enum": ["draft", "on_sale", "off_shelf"], ...}
Order 的 readOnly 字段   = ['id', 'paid_at', 'product_name', 'status', 'total_price']
OrderCreate 的 writeOnly = ['card_token']      ← 支付令牌不会出现在响应文档里
分页包装组件 = ['PaginatedCategoryList', 'PaginatedOrderList', 'PaginatedProductList']
securitySchemes = ['cookieAuth']
```

`write_only` 字段（如 `card_token`）自动标 `writeOnly`，不会出现在响应文档里——这是自动生成的另一个好处：**敏感字段的可见性由 serializer 定义决定，不需要在文档里手写一遍**。

### 3.3.5 与版本控制的配合（实验 30）

**这是本课最反直觉的一节。**

需求：API 有 v1 / v2 两个版本，要出两份文档。

**直觉做法**：生成 schema 时传一个带 `version` 的 request 进去。

**实测：无效。**

```text
v1: VERSION = v1, ROOT_URLCONF = versioned_urls, DEFAULT_VERSION = v1
    PATHS_WITH_REQUEST_COUNT = 8, 样例 /api/v1/categories/
v2: VERSION = v2, ROOT_URLCONF = versioned_urls, DEFAULT_VERSION = v1   ← 没变
    PATHS_WITH_REQUEST_COUNT = 8, 样例 /api/v1/categories/               ← 还是 v1
    HAS_VERSION_IN_PATH = False                                          ← 失败
```

即使 request 的 version 是 v2，生成的路径仍然是 v1 的。**因为路径是靠 `reverse()` 生成的，而 `reverse()` 用的是 `DEFAULT_VERSION`——它是导入时的快照，运行时改无效。**

**正确做法：每个版本一个独立的 settings 模块。**

```python
# config/settings_versioned.py
ROOT_URLCONF = "versioned_urls"
REST_FRAMEWORK = {
    "DEFAULT_VERSIONING_CLASS": "rest_framework.versioning.URLPathVersioning",
    "DEFAULT_VERSION": "v1",
    "ALLOWED_VERSIONS": ["v1", "v2"],
}

# config/settings_versioned_v2.py —— 只有 DEFAULT_VERSION 不同
DEFAULT_VERSION = "v2"
```

实测：

```text
v1: THIS_VERSION_PATHS = 8，样例 /api/v1/categories/
v2: THIS_VERSION_PATHS = 8，样例 /api/v2/categories/
v1 文档版本号: ['SCHEMA_VERSION = 1.0.0 (v1)']
v2 文档版本号: ['SCHEMA_VERSION = 1.0.0 (v2)']
```

> 这个"导入时快照"的机制，与课 6 讲的"版本类是类属性"是同一个根源。凡是"导入时确定"的东西，运行时改都没用。

**出多版本文档的 CI 写法**：

```bash
python manage.py spectacular --file schema-v1.yaml --settings=config.settings_versioned
python manage.py spectacular --file schema-v2.yaml --settings=config.settings_versioned_v2
```

### 3.3.6 维护策略：把文档变成 CI 检查（实验 33）

文档自动生成不等于不用管。**要防止"代码改了但文档文件忘了提交"。**

实测（实验 33）：

```text
SCHEMA_FILE_WRITTEN = True
SCHEMA_FILE_BYTES   = 10197
EXPORT_MS           = 241.1
DETERMINISTIC = True（两次导出内容一致 = 可以安全地 git diff）
OPENAPI_VERSION = 3.0.3
PATH_COUNT      = 10
WARNING_COUNT   = 0
```

关键是 `DETERMINISTIC = True`：**两次导出内容一致**，所以可以安全地 `git diff`。

CI 里加一步：

```yaml
- name: 检查 API 文档是否最新
  run: |
    python manage.py spectacular --file schema.yaml --validate --fail-on-warn
    git diff --exit-code schema.yaml
```

Windows 本地跑同样检查（PowerShell）：

```powershell
python manage.py spectacular --file schema.yaml --validate --fail-on-warn
if ($LASTEXITCODE -ne 0) { throw "schema 校验失败" }
git diff --exit-code schema.yaml
if ($LASTEXITCODE -ne 0) { throw "schema.yaml 与代码不一致，请重新导出并提交" }
```

⚠️ 注意 `--fail-on-warn`：本工程 `WARNING_COUNT = 0`。如果你的工程有 warning（比如视图缺 serializer），这一步会失败——**这是好事**，它在逼你把文档补完整。

### 3.3.7 规模化表现（实验 34）

必查项 #28 要求：示例代码必须按"生产规模"检验一遍。

```text
DATA_ROWS        = 20000
SEED_MS          = 10831.6     ← 灌 2 万条数据
GEN_MS_WITH_DATA =    28.1     ← 有数据时生成文档
GEN_MS_EMPTY_DB  =     4.5     ← 空库时生成文档
SAME_SCHEMA      = True
```

**结论**：`SAME_SCHEMA = True` —— 2 万条数据和空库生成的文档**完全一样**。

> schema 生成是 **O(接口数)**，不是 O(数据量)。所以不用担心"数据多了文档生成会变慢"。

（注意 `GEN_MS_WITH_DATA` 比 `GEN_MS_EMPTY_DB` 慢，是因为同进程内有查询缓存等副作用，不是数据量本身导致的；判据是 `SAME_SCHEMA = True`。）

---

# 第四幕　实操验证

## 4.1 实验工程结构

```text
%TEMP%/dj-lesson20-demo/testlab/
├── config/
│   ├── settings.py               主配置（含 drf-spectacular）
│   ├── settings_nomig.py         MIGRATION_MODULES = {"shop": None}
│   ├── settings_versioned.py     v1 文档用
│   ├── settings_versioned_v2.py  v2 文档用
│   └── urls.py                   顺序即语义（见坑 1）
├── apps/
│   ├── labkit.py                 Check 断言器 + Timer
│   ├── shop/
│   │   ├── models.py             Category / Product / Order（含 internal_note）
│   │   ├── serializers.py        ProductSerializer / OrderSerializer / OrderCreateSerializer
│   │   ├── views.py              三种外部调用写法对照（A/B/C）
│   │   ├── services.py           pay_order() —— 写法 A
│   │   ├── payments.py           Gateway.charge() —— mock 的靶子
│   │   ├── factories.py          factory_boy 工厂
│   │   ├── tests_parallel.py     并行测试（4 类 × 6 用例）
│   │   └── migrations/
│   │       └── 0002_seed_categories.py   数据迁移（验证禁用迁移的代价）
├── run_lab1.py          实验 1-10   API 测试策略与 DRF 工具
├── run_lab2.py          实验 11-20  mock / 金字塔 / 提速手段
├── run_lab3.py          实验 21-30  keepdb / parallel / 文档生成
├── run_lab4.py          实验 31-42  文档维护 / 规模化 / 综合体检
├── probe_*.py           15+ 个独立进程探针
└── count_assertions.py  全量回归 + 统计
```

跑法：

```powershell
$env:PYTHONIOENCODING="utf-8"; $env:PYTHONUTF8="1"
cd "$env:TEMP\dj-lesson20-demo\testlab"
& "C:\Users\v_wypgwu\.workbuddy\binaries\python\envs\dj-course\Scripts\python.exe" count_assertions.py
```

### 4.2.1 两个可复用小工具

本课所有实验都靠这两个工具，自己搭实验工程时可以直接抄。

`apps/labkit.py`：

```python
"""实验用小工具：断言器 + 计时器。"""
import time


class Check:
    """收集式断言：跑完全部实验再汇总，一个失败不阻断后面。"""

    def __init__(self):
        self.passed = 0
        self.failures = []

    def that(self, name, cond, note=""):
        if cond:
            self.passed += 1
            print(f"    ✅ {name}  {note}")
        else:
            self.failures.append((name, note))
            print(f"    ❌ {name}  {note}")
        return bool(cond)

    def eq(self, name, actual, expected, note=""):
        return self.that(
            name, actual == expected,
            note or f"实测={actual}（期望 {expected}）",
        )

    def summary(self, label):
        print(f"\n  【{label}】通过 {self.passed}，失败 {len(self.failures)}")
        for name, note in self.failures:
            print(f"    - {name}  {note}")
        print(f"\n断言总数 = {self.passed + len(self.failures)}")
        return len(self.failures)


class Timer:
    """上下文管理器计时。用法：with Timer() as t: ...  然后读 t.elapsed_ms"""

    def __enter__(self):
        self._start = time.perf_counter()
        return self

    def __exit__(self, *exc):
        self.elapsed_ms = (time.perf_counter() - self._start) * 1000
        return False
```

⚠️ `Check` 用**收集式**而非 `assert`：一个断言失败不会中断后面的实验，跑完一次性看到全部问题。这个设计在"预设被推翻"时特别有用——你能同时看到哪几条预设错了，而不是崩在第一条上就停。

预期输出：

```text
  ✅ run_lab1.py            断言  29，退出码 0
  ✅ run_lab2.py            断言  23，退出码 0
  ✅ run_lab3.py            断言  31，退出码 0
  ✅ run_lab4.py            断言  20，退出码 0

  ✅ probe_setup_db.py migrate          退出码 0
  ✅ probe_setup_db.py nomig            退出码 0
  ✅ probe_datamig.py migrate           退出码 0
  ✅ probe_datamig.py nomig             退出码 0
  ✅ probe_schema_ci.py                 退出码 0
  ✅ probe_keepdb_nomig.py first        退出码 0
  ✅ probe_keepdb_scale.py 100 cold     退出码 0
  ✅ probe_keepdb_scale.py 100 warm     退出码 0
  ✅ probe_keepdb_remigrate.py cleanup  退出码 0
  ✅ probe_parallel_gain.py 0 1         退出码 0
  ✅ probe_parallel_gain.py 0 4         退出码 0

  实验编号数（去重） = 42
  断言总数           = 103

✅ 全量回归通过
```

## 4.3 实验清单

| 实验 | 主题 | 关键结论 | 建议 |
|---|---|---|---|
| 1-2 | Django Client vs APIClient | 都是 DRF Response；差异只有 `force_authenticate` | 看结论 |
| 3 | 三种认证绕行方式 | force_login / force_authenticate / 完整登录 | 看结论 |
| 4 | `force_authenticate` 机制 | 🚨 替换整个 authenticators 元组 | **必跑** |
| 5 | 绕过认证 ≠ 绕过权限 | 🚨 `perms_map['GET'] = []` | **必跑** |
| 6-7 | 测试隔离 / build vs create | TestCase 靠事务回滚 | 看结论 |
| 8-9 | factory_boy 的 SQL 代价 | 复用关联对象 50→10 条；bulk 快 4.3x | **必跑** |
| 10-11 | mock 打点位置 | patch 使用处，不是定义处 | **必跑** |
| 12-14 | 金字塔：IO / 层次 / 基类 | mock 快 144x；TransactionTestCase 慢 57x | 选跑 14 |
| 15 | setUpTestData | 10x 差距 | 看结论 |
| 16-17 | 建库耗时与迁移数 | 20 个迁移 | 看结论 |
| 18-19 | 禁用迁移的收益与代价 | 🚨 只禁业务 app 无效；数据迁移被跳过 | **必跑** |
| 20 | `--parallel` 的代价 | 每 worker 一份库 | 看结论 |
| 21-23 | keepdb 的收益与陷阱 | 🚨 照样跑 migrate；隔离仍成立 | **必跑 21** |
| 24 | `--parallel` 的真实收益 | 🚨 两个门槛 + 盈亏平衡点 | **必跑** |
| 25 | setUpTestData 对象共享 | 🚨 Django 6.1 不共享 | **必跑** |
| 26-27 | schema 生成与字段来源 | serializer 决定字段 | 看结论 |
| 28 | 内部字段泄漏 | 🚨 泄漏在新组件 `AllFields` | **必跑** |
| 29 | extend_schema 注解 | 从 `drf_spectacular.utils` 导入 | 看结论 |
| 30 | 版本化文档 | 🚨 必须独立 settings 模块 | **必跑** |
| 31-32 | 文档漂移与组件缓存 | 🚨 组件名随类名变 | 选跑 32 |
| 33 | CI 检查 | 导出确定性，可 git diff | **必跑** |
| 34 | 规模化 | O(接口数) 非 O(数据量) | 看结论 |
| 35-38 | 枚举 / 只读 / 分页 / 认证 | 文档形态对照 | 看结论 |
| 39 | schema 端点可达性 | 200 + swagger-ui | 看结论 |
| 40-42 | 组合拳 / 体检 / 危险组合 | 🚨 keepdb 在 SQLite 上是负收益 | **必跑 41** |

**"必跑"的 12 组**覆盖了全部 🚨 反直觉结论。其余看输出即可——它们的价值在于佐证，不需要亲手复现。

⚠️ 跑单个实验：`python run_lab1.py` 会跑完 1-10；要单独重跑某个实验，直接在脚本里注释掉其他 `banner()` 块即可（`Check` 是收集式的，不影响汇总）。

---

# 第五幕　体系收束

## 5.1 三张决策表

### 表一：该用哪个测试基类？

| 场景 | 选择 | 代价 |
|---|---|---|
| 不碰数据库的纯逻辑 | `SimpleTestCase` | 0.4 ms / 20 用例 |
| **默认（绝大多数）** | `TestCase` | 2.7 ms / 20 用例 |
| 必须测事务行为（commit/rollback） | `TransactionTestCase` | 153.7 ms / 20 用例 |

### 表二：测试慢了怎么办？按顺序排查

| 步骤 | 动作 | 怎么判断命中 | 命中后跳到 |
|---|---|---|---|
| 1 | **先跑体检脚本，分段计时** | 永远先做这一步 | 1.2.1 |
| 2 | 建库慢 → 禁所有 app 的迁移 | 建库占比 > 50%，且工程无 `RunPython` 数据迁移 | 3.2.3 |
| 3 | 造数慢 → `build_batch + bulk_create`、复用关联对象 | 造数占比 > 30%，代码里有 `create_batch` / `SubFactory` | 3.1.4 |
| 4 | 执行慢 → mock 外部 IO | 执行占比最高，用例里有真实 HTTP / `sleep` / 第三方 SDK | 3.1.6 |
| 5 | 串行 > 2-3 秒 → 考虑 `--parallel`（且要拆多类） | 串行总耗时 > 盈亏平衡点（本机约 1.1s，先用实验 24 的方法量自己的开销） | 3.2.4 |
| 6 | 数据库昂贵（PG/MySQL）→ 加 `--keepdb` | 建库耗时大且数据库非 SQLite | 3.2.2 |

**判据的判据**：如果三段占比都很平均，说明没有单一瓶颈，按 2→3→4 顺序逐个做，每做一次重跑体检确认效果。

### 表三：三个提速手段的真实账本

| 手段 | 省什么 | 不省什么 | 代价 | SQLite 实测 |
|---|---|---|---|---|
| `--keepdb` | 删库 + 建文件 | **迁移照跑** | 模型改了会报 `no such column` | 0.87x（**负收益**） |
| 禁迁移 | 跑全部迁移 | 表照样建 | **数据迁移（RunPython）不执行** | 2.77x（迁移多时 2.93x） |
| `--parallel` | 执行时间 | 建库（每 worker 各建一份） | 约 850ms 固定开销 + 资源 ×N | 短任务 0.99x / 长任务 3.02x |

## 5.2 高频误区表

| # | 误区 | 真相 | 实验 |
|---|---|---|---|
| 1 | Django Client 拿 HttpResponse，APIClient 拿 DRF Response | 两者都是 DRF Response，都有 `.data`。差异只有 `force_authenticate` | 2 |
| 2 | `force_authenticate` 是把 user 塞进 request | 是把 `authenticators` **整体替换**成 `(ForcedAuthentication,)`，自定义认证类一次都不跑 | 4 |
| 3 | 绕过认证后能访问所有接口 | 认证 ≠ 权限。零权限用户 POST 照样 403 | 5 |
| 4 | `DjangoModelPermissions` 保护读接口 | `perms_map['GET'] = []`，任何已认证用户都能 GET | 5 |
| 5 | patch 定义在哪个模块就打哪个 | 要 patch **使用处**的名字（晚绑定写法除外） | 10、11 |
| 6 | `setUpTestData` 的对象在测试间共享，改了会串味 | Django 6.1 有 `TestData` 描述符 + deepcopy，**不共享** | 25 |
| 7 | 禁用迁移设 `{"shop": None}` 就够了 | contrib 那 18 个照跑，必须禁**所有** app 才有效 | 18 |
| 8 | 禁用迁移只是不跑迁移，表和数据都在 | 表在，但 **`RunPython` 数据迁移完全不执行**，数据为 0 | 19 |
| 9 | `--keepdb` 能省掉建库时间 | 它照样跑 migrate，SQLite 上甚至是负收益 | 21 |
| 10 | keepdb + 禁迁移 = 表结构会不同步（危险） | keepdb 依然调 migrate，加字段删字段都能同步。真危险的是数据迁移被跳过 | 42、19 |
| 11 | `--parallel=4` 就快 4 倍 | 按 TestCase 类切分 + 约 850ms 固定开销，短任务是净亏 | 24 |
| 12 | `fields = '__all__'` 会把内部字段泄漏进原组件 | 泄漏在**新建的** `AllFields` 组件里——更隐蔽 | 28 |
| 13 | 生成文档时传 `request.version` 就能出对应版本 | `DEFAULT_VERSION` 是导入时快照，必须换独立 settings 模块 | 30 |
| 14 | 数据量大了文档生成会变慢 | 生成是 O(接口数)，2 万条数据 vs 空库结果完全相同 | 34 |

## 5.3 本课踩到的坑（工程实录）

这些是搭实验工程时真实踩的，不是编的。

**坑 1：路由遮蔽（课 5 知识的真实重现）** ⏱️ 纯环境问题，最费时间

写 `/api/orders/create/` 时一直返回 405。`resolve()` 一看：

```text
命中 OrderViewSet，kwargs={'pk': 'create'}
```

`DefaultRouter` 生成的 `orders/(?P<pk>[^/.]+)/$` 把 `create` 当成了主键。**修法：手写路径必须放在 `include(router.urls)` 之前。**

```python
urlpatterns = [
    path("admin/", admin.site.urls),
    # 手写路径在前，router 在后 —— 顺序即语义
    path("api/orders/create/", OrderCreateView.as_view(), name="order-create"),
    path("api/", include(router.urls)),
]
```

（⚠️ 修的时候别把 `include(router.urls)` 删了——我删过一次，`/api/orders/1/` 变成 Resolver404。）

**坑 2：`ROOT_URLCONF` 不能传列表**

```python
# 报错：TypeError: unhashable type: 'list'
with override_settings(ROOT_URLCONF=[...]):
```

课 18 踩过的同款坑。它必须是**模块路径字符串**，所以改用独立 url 模块 `probe_urls.py`。

**坑 3：`extend_schema` 的导入位置**

```python
# 错：ImportError: cannot import name 'extend_schema' from 'rest_framework.decorators'
from rest_framework.decorators import extend_schema

# 对
from drf_spectacular.utils import extend_schema
```

**坑 4：放大迁移不能用"复制 0001"**

直接复制 `0001_initial` 会报 `Conflicting migrations detected; multiple leaf nodes`。必须生成**链式**空迁移：

```python
class Migration(migrations.Migration):
    dependencies = [('shop', '0001_initial')]   # 每个依赖上一个
    operations = []
```

**坑 5：`build_mock_request` 需要 `user` 和 `auth`**

drf-spectacular 的 `build_mock_request` 会读 `original_request.user` 和 `.auth`。用 `APIRequestFactory` 造的 `WSGIRequest` 两个属性都没有，不补就 `AttributeError`。补上：

```python
request.user = AnonymousUser()
request.auth = None
```

**坑 6：PowerShell 管道改 Python 文件会破坏中文编码** ⏱️ 纯环境问题，症状极隐蔽

```powershell
# 千万别这样改含中文的 .py
(Get-Content x.py) -replace 'a','b' | Set-Content x.py
```

中文注释会变成乱码，导致文件语法错误（症状很隐蔽：测试只跑了 0.010s 就"全过"——因为模块根本没成功导入，一个用例都没跑）。**含中文的 Python 文件必须用编辑器/写入工具重写。**

**坑 7：实验数据被前序实验污染**

用计数做断言（`assert Category.objects.count() == 5`）会被前面实验的残留数据污染。改为**追踪特定 marker 对象**（用专属命名空间 + 唯一名字）。

**坑 8：`bulk_create` 拒绝未保存的关联对象**

```python
# ValueError: bulk_create() prohibited to prevent data loss
#             due to unsaved related object 'user'
```

先 `create` 关联对象，再 `build_batch`。

## 5.4 三个知识点的一句话总结

**知识点 1（测试策略）**：测试金字塔的本质是**按代价分层**——service 层测逻辑（快、多），API 层测契约（慢、少）；外部 IO 一律 mock（144x）；造数据用 `build_batch + bulk_create`（4.3x）并复用关联对象（5x SQL）。

**知识点 2（提速）**：**先量后改**。三个手段作用在不同阶段，只有打中瓶颈那个才有效。`--keepdb` 在 SQLite 上是负收益，禁迁移在数据迁移存在时是危险的，`--parallel` 有两个门槛（按类切分 + 固定开销）。

**知识点 3（文档）**：文档由代码导出所以不漂移，但要**用真实响应做对照**（实验 31）、**用 CI 比对防漏提交**（实验 33）、**按版本出独立文档**（实验 30）。维护成本从"手写"转移到"注解与校验"。

## 5.5 自检题

**Q1.** 团队说"测试从 12 分钟优化到了 11 分半，`--parallel=4` 没用"。按本课结论，最可能的原因是什么？要怎么查？

**Q2.** 你把 300 个用例都写在 `class OrderTest(APITestCase)` 里，然后开 `--parallel=8`。会发生什么？

**Q3.** 服务层代码是 `from .payments import charge`，你在测试里 `mock.patch("apps.shop.payments.charge")`。生效吗？为什么？

**Q4.** 工程用了 `MIGRATION_MODULES = {"shop": None}` 想提速，测下来几乎没变。为什么？应该怎么改？改完要担心什么？

**Q5.** 你的 API 有 v1/v2 两个版本。你在生成文档时传了一个 `version="v2"` 的 request，发现生成的路径还是 `/api/v1/...`。为什么？正确做法是什么？

**Q6.** 模型加了个 `internal_note` 字段，serializer 某处用了 `fields = '__all__'`。这个字段会出现在文档的哪个组件里？为什么这个位置更危险？

**Q7.** 你的测试套件串行跑 900ms，同事建议开 `--parallel=4`。按本课的盈亏平衡模型，你该怎么回答？

**Q8.** 为什么本课刻意用 SQLite 文件库而不是内存库？如果把结论直接搬到 PostgreSQL 上，哪个结论最可能不成立？

<details>
<summary>答案要点</summary>

**A1.** 大概率没打中瓶颈。先跑体检脚本分段计时（实验 41）。本课实测执行只占 4%、建库占 78%——如果他的 12 分钟里大部分是数据库 IO，那优化"用例怎么写"最多省 4%。另外要检查测试是不是全塞在少数几个 TestCase 类里（门槛一），以及串行总时长是不是低于盈亏平衡点（门槛二）。

**A2.** 完全没效果。并行按 **TestCase 类**切分（`partition_suite_by_case` 按 `type` 分组），300 个用例在一个类里 = 1 个 subsuite = `EFFECTIVE_PROCESSES = 1`。必须拆成多个 TestCase 类。

**A3.** 不生效。`from .payments import charge` 在 services 模块里**绑定了名字**，services 命名空间里的 `charge` 指向原函数对象。patch `payments.charge` 只是改了 payments 模块的属性。要 patch `apps.shop.services.charge`。**规则：patch 使用处，不是定义处。**

**A4.** 因为 `django.contrib` 那 18 个迁移（auth 12 + admin 3 + contenttypes 2 + sessions 1）照跑，只禁 shop 只省掉 2 个。要改成禁**所有** app：`{k: None for k in ["shop","admin","auth","contenttypes","sessions"]}`。改完要担心：**所有 `RunPython` 数据迁移都不再执行**——表在，但初始数据为 0，且不会报错。

**A5.** 路径靠 `reverse()` 生成，而 `reverse()` 用 `DEFAULT_VERSION`——它是**导入时的快照**，运行时改无效。正确做法是每个版本一个独立 settings 模块（`settings_versioned.py` / `settings_versioned_v2.py`），用 `--settings=` 分别导出。这与课 6"版本类是类属性"同源。

**A6.** 不会出现在原 `Order` 组件里，而是出现在**新建的 `AllFields` 组件**中（drf-spectacular 按组件名缓存，`__all__` 生成的是新组件）。这个位置更危险：它不会"污染"你已发布的组件，所以回归测试抓不到；但它**确实暴露在文档里**，且藏在一个名字不直观的新组件中，人工审查容易漏。

**A7.** 按本课的盈亏平衡模型（`T = 4/3 × 开销`），本课实验环境（Windows / 20 核 / spawn）4 进程固定开销约 850ms，平衡点约 1130ms。900ms < 1130ms，**开并行是净亏的**：并行后约 `850 + 900/4 = 1075ms`，比 900ms 还慢。应该先做别的优化（比如禁迁移打中建库），等串行超过 2-3 秒再考虑并行。

⚠️ 但**这套数字只对本课环境成立**。你自己的机器要先量出开销——跑两次空任务（`parallel=1` 与 `parallel=4` 各一次），差额就是你的固定开销，再乘 4/3 得到你自己的平衡点。这恰好又是"先量后改"的一次演示。

**A8.** 因为 `--keepdb` 的语义就是"复用库文件"，内存库每次都是新的，根本体现不出差别。搬 PostgreSQL 时，**"`--keepdb` 是负收益"这个结论最可能不成立**——PG 建库要网络连接 + 建 schema，成本高得多，keepdb 的收益会明显转正。这正是"先量后改"的注脚：**结论依赖环境，必须自己量**。"禁迁移有效（2.77x）"和"parallel 有固定开销"这两个结论则相对通用。

</details>

## 5.6 术语表

| 术语 | 含义 |
|---|---|
| `force_authenticate` | `APIClient` 专属方法，把 request 的 `authenticators` 整体替换为 `ForcedAuthentication` |
| `ForcedAuthentication` | DRF 内部认证类，无条件返回指定 user |
| `perms_map` | `DjangoModelPermissions` 的方法→权限映射，`GET` 对应空列表 |
| SubFactory | factory_boy 的关联工厂，默认每次新建关联对象 |
| `django_get_or_create` | factory_boy 选项，同名对象"查而不建"（会让 SQL 计数失真） |
| `build()` / `create()` | factory_boy 的"不落库" / "落库"两种构造方式 |
| TestCase / TransactionTestCase / SimpleTestCase | 三种测试基类，隔离方式分别是事务回滚 / flush 全库 / 禁止 DB |
| `setUpTestData` | 类级造数，Django 6.1 用 `TestData` 描述符 + deepcopy 保护 |
| `--keepdb` | 复用测试库（但 migrate 照跑） |
| `MIGRATION_MODULES` | 设为 `{app: None}` 禁用该 app 迁移，改为按模型直接建表 |
| `--parallel` | 多进程跑测试，按 TestCase 类切分，有固定开销 |
| `partition_suite_by_case` | Django 的测试切分函数，按 `type` 分组（不是按方法） |
| drf-spectacular | OpenAPI 3 文档生成库 |
| `AutoSchema` | drf-spectacular 的 schema 生成类 |
| `extend_schema` | 注解装饰器，从 `drf_spectacular.utils` 导入 |
| schema 组件缓存 | drf-spectacular 按组件名缓存，同进程内改 serializer 拿不到新定义 |
| 盈亏平衡点 | 并行收益 = 并行开销时的串行耗时，本课实测约 1.1 秒 |
| spawn / fork | 两种进程启动方式。Windows 用 spawn（重新导入模块，开销大），Linux 默认 fork（复制进程，开销小）——这是本课 850ms 固定开销的主要来源 |
| subsuite | `--parallel` 的切分单元，由 `partition_suite_by_case` 按 TestCase 类生成；`processes = min(parallel, len(subsuites))` |
| `--collect-only` | 只收集用例不执行，用来统计用例分布（自查"巨无霸 TestCase 类"） |

## 5.7 事实来源标注

本课所有数字来自实测，来源如下。

| 结论 | 来源 | 实验 |
|---|---|---|
| 两种 Client 都是 DRF Response | 实测输出 | 2 |
| `force_authenticate` 替换 authenticators | `rest_framework/request.py:176-180` + 实测 | 4 |
| `perms_map['GET'] = []` | `rest_framework/permissions.py:191-201` + 实测 | 5 |
| SubFactory 50→10 条 SQL | 实测 | 8 |
| `create_batch` vs `bulk_create` 4.3x | 实测 | 9 |
| patch 使用处生效 | 实测四组对照 | 11 |
| mock 外部 IO 144x | 实测 | 12 |
| 三种基类 2.7 / 153.7 / 0.4 ms | 实测 | 14 |
| `setUpTestData` 10x | 实测 | 15 |
| 禁所有 app 才有效（2.77x） | 实测 a/b/c 三层 | 18 |
| 数据迁移被跳过 | 实测 Category 数 3 → 0 | 19 |
| keepdb 照样跑 migrate | `creation.py:70-99` + 决定性实验（21 个迁移 + ROWS=1） | 21、42 |
| keepdb 隔离仍成立 | 实测 marker 不可见 | 23 |
| 并行按类切分 | `runner.py:1271 partition_suite_by_case` + 实测 | 24 |
| 并行固定开销约 850ms | 实测空任务 11ms vs 860ms | 24 |
| 盈亏平衡点约 1.1 秒 | 由开销模型算出 | 24 |
| `setUpTestData` 不共享 | `django/test/testcases.py` TestData 描述符 + 实测 | 25 |
| 内部字段泄漏在 `AllFields` | 实测 `LEAKED_COMPONENTS` | 28 |
| 版本化文档需独立 settings | 实测（运行时改无效 + 独立模块有效） | 30 |
| 导出确定性可 git diff | 实测两次导出一致 | 33 |
| 生成是 O(接口数) | 实测 2 万条 vs 空库 `SAME_SCHEMA=True` | 34 |
| 组合拳四组 SETUP 耗时 | 实测 | 40 |
| 体检三段占比 | 实测 78% / 18% / 4% | 41 |

---

## 🚀 下一批接力提示词

> 下一课：课 21《自定义管理命令与 System checks》（仍在本阶段，阶段 6 共 5 课，本课是 3/5）。
>
> 带上这三个问题：
> 1. **本课的三个"脚本"都该升级成管理命令** —— 本课的体检脚本（实验 41 的三段计时）、schema 导出（实验 33）、多版本文档导出（实验 30），现在都是临时脚本。课 21 讲 `BaseCommand` 时，请把它们改造成 `manage.py testhealth`、`manage.py exportdocs --version v1` 这样的正式命令，并补上 `--verbosity` 进度输出
> 2. **本课的"约定"都该变成 System checks** —— 本课发现的坑大多是可自动检查的约定：手写路径必须在 `include(router.urls)` 之前（坑 1）、含 `RunPython` 的 app 不能被 `MIGRATION_MODULES` 禁用（实验 19）、文档必须与真实响应字段一致（实验 31）、schema 文件必须与代码同步（实验 33）。课 21 讲自定义 check 时，这些是现成的素材——用 `Error` 级还是 `Warning` 级，取决于会不会直接导致测试失败
> 3. **`call_command` 正是测试这些命令的手段** —— 本课知识点 1 讲的是"怎么测 API"，课 21 要面对"怎么测命令"。注意本课实验 10/11 的教训在这里同样适用：`call_command` 里 patch 目标的位置依然是"使用处而非定义处"
>
> 提示：本课实验工程在 `%TEMP%/dj-lesson20-demo/testlab`，`apps/labkit.py` 里的 `Check` 断言器和 `Timer` 可直接复用；三个独立 settings 模块（`settings_nomig.py` / `settings_versioned.py` / `settings_versioned_v2.py`）是"用 settings 隔离做 A/B 对照"的现成范例，写命令测试时可以照搬这个思路。
>
> ⚠️ 环境提醒：Windows 下跑实验前必须设 `$env:PYTHONIOENCODING="utf-8"`，否则中文输出会 `UnicodeEncodeError`；含中文的 Python 文件**不要用 PowerShell 管道修改**，会破坏编码（本课坑 6）。

---

## 🧭 课程导航

- ⬅️ 上一课：[课 19《文件、存储与 Admin》](./lesson-19-文件存储与Admin.md)
- ➡️ 下一课：[课 21《自定义管理命令与 System checks》](./lesson-21-自定义管理命令与System checks.md)
- 📖 阶段概览：[阶段 6：工程化与生产](../overview.md)
- 📚 课程目录：[02-课程目录.md](../../../02-课程目录.md)
- 🏠 学习路径：[01-学习路径总览.md](../../../01-学习路径总览.md)

> 📌 **阶段 6 进度**：课 18、19、20 已完成（3/5）。下一课为课 21《部署与上线检查清单》。
