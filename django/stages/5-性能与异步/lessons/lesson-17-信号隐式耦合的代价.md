# 课 17　信号：隐式耦合的代价

> 📖 情节定位：**扛住真实世界（三）** —— 最方便的解耦机制，也最容易变成看不见的调用链
> 🎯 本课目标：知道信号什么时候该用、什么时候必须改用显式调用

---

## 开场：三处"用了信号"的代码，上线后都出了事

### 先对齐几个术语

本课会密集出现下面这些词，先给一句直白解释，避免后面被名词绊住：

| 术语 | 直白解释 |
|------|----------|
| `receiver` | 信号的接收函数。一个 `@receiver` 就是在说"某件事发生时叫我" |
| 信号（Signal） | Django 内置的一套观察者机制。模型层最常用的是 `pre_save` / `post_save` / `pre_delete` / `post_delete` / `m2m_changed` |
| `sender` | 注册信号时指定的模型类。不指定就是"所有模型都收" |
| `dispatch_uid` | 注册时给 receiver 起的唯一标识，用于去重 |
| `on_commit` | `transaction.on_commit(fn)` —— 把 fn 推迟到**事务提交之后**执行；回滚了就不执行 |
| `fast_delete` | Django 删除时的优化路径：不走逐对象加载，直接一条 SQL 删掉，**不发信号** |
| 隐式调用链 | 调用点看不出会触发哪些代码的控制流 |

**接口 A**（订单通知）：用 `post_save` 发通知，写起来最干净——下单的地方只管 `Order.objects.create()`，通知自动发出。上线一个月后客服收到投诉：**用户收到了订单确认短信，但订单列表里查无此单**。查下来：下单流程最后一步调第三方支付超时，整个事务回滚了；**短信却已经发出去了**，因为 `post_save` 在事务内执行，而短信是外部调用，回滚不回来。

**接口 B**（商品统计）：有个 receiver 负责在商品保存后刷新分类的商品数。上线后数据对不上：后台显示某分类有 320 个商品，点进去只有 300 个。查下来：运营用管理后台的"批量导入"功能一次性导入了 20 个商品，走的是 `bulk_create`，**一个信号都没发**。

**接口 C**（用户注册）：团队给 `User` 挂了个 `post_save`，创建用户时自动建用户资料（Profile）。测试环境一切正常。上线后偶发报错：`Profile 已存在`。查了三天才发现：某次代码重构把 `signals.py` 的 import 挪到了另一个模块，**同一个 receiver 被注册了两次**，一次 save 触发两遍。

三个接口的共同点：**信号让代码写起来更短，但让"这一行代码背后到底会发生什么"变得不透明**。

| 你以为 | 实际 |
|--------|------|
| `post_save` 发通知最解耦 | 它在**事务内**执行，事务回滚了通知照样发（外部副作用退不回来） |
| 信号能覆盖所有写入 | `bulk_create` / `bulk_update` / `update()` **一个信号都不发** |
| 注册一次就执行一次 | 模块被重复 import 时可能注册多次，`dispatch_uid` 的去重规则还很反直觉 |

这一课就是把这三组错配拆开。

---

## 第一幕：信号是怎么跑起来的

### 1.1 五个常用的模型信号

Django 在模型层提供了五个信号，它们串起了一次保存的完整生命周期：

| 信号 | 触发时机 | 典型用途 |
|------|----------|----------|
| `pre_save` | `save()` 之前，还没写库 | 改字段值、做校验 |
| `post_save` | `save()` 之后，已写库 | 发通知、写审计、清缓存 |
| `pre_delete` | `delete()` 之前 | 检查能不能删、备份 |
| `post_delete` | `delete()` 之后 | 清理关联文件 |
| `m2m_changed` | 多对多关系变化时 | 维护冗余计数 |

实测（实验 2）：一次"创建 + 删除"的完整顺序是：

```
pre_save → post_save → pre_delete → post_delete
```

`post_save` 的参数里藏着两个关键信息（实验 1）：

```python
@receiver(post_save, sender=Product)
def spy(sender, instance, created, **kwargs):
    print(created)          # True 表示新建，False 表示更新
    print(instance.pk)      # 已经有主键了
    print(kwargs.keys())    # dict_keys(['signal', 'using', 'raw', 'update_fields'])
```

`created` 是最常用的开关——绝大多数通知类 receiver 都只想处理"新建"，写成 `if not created: return` 能省掉一半的误触发。

### 1.2 注册发生在 `AppConfig.ready()`

这是信号机制里**最容易踩、且最难查**的一环。

信号的注册依赖 `ready()` 里那一行 import：

```python
# apps/shop/apps.py
class ShopConfig(AppConfig):
    name = "apps.shop"

    def ready(self):
        from apps.shop import signals  # ⚠️ 少这一行，所有 @receiver 全部失效
```

少了这一行会怎样？实测（实验 3，独立进程对照）：

| 配置 | `post_save(sender=Order)` 上的 receiver 数 | 创建订单后通知数 | 有没有报错 |
|------|------|------|------|
| `ready()` 正常 import | 2 | 2 | — |
| `ready()` 不 import | **0** | **0** | **没有** |

**全程静默。** 程序正常启动、正常退出、日志干净，只是那些"应该自动发生的事"一件都没发生。

> 🔍 为什么这么安静？因为 `@receiver` 只是把函数登记进一个列表，没人登记就列表为空，发信号时遍历空列表什么都不做——**这不是错误状态**。

这也是本课"不报错的错误"清单第 1 条。自查手段——在 shell 里枚举当前注册的 receiver：

```python
# 最小版：看总数
from django.db.models.signals import post_save, pre_save

for name, sig in [("pre_save", pre_save), ("post_save", post_save)]:
    print(f"{name}: {len(sig.receivers)} 个")
```

```python
# 完整版（含函数名、作用范围）：见 4.4 节
```

跑出来如果是 0，而你明明写了 `@receiver`——那就是 `ready()` 那行 import 没了。

### 1.3 `sender` 决定范围

注册时可以指定 `sender`，也可以不指定（实验 4）：

| 写法 | 收到谁的事件 | 实测（1 个 Category + 1 个 Product） |
|------|--------------|--------------------------------------|
| `connect(fn, sender=Product)` | 只收 Product | 1 次 |
| `connect(fn)` | **所有模型** | 2 次 |

不指定 `sender` 的 receiver 会收到**每一个模型**的事件，包括 Django 内置的 `User`、`LogEntry` 等。这意味着你的 receiver 里必须自己判断 `sender`，否则就会对无关模型也跑一遍（实验 20）。

生产建议：**永远指定 `sender`**。不指定只在极少数"我真的要监听一切"的场景才合理（比如全局审计）。

### 1.4 重复注册：`dispatch_uid` 的反直觉之处

这是本课第二处"我原以为 X，实测是 Y"。

我备课时的预设是：`dispatch_uid` 是**防重复注册**的手段，不带它注册两次就会执行两次。实测下来，两条都不完全对（实验 5 的 A/B/C 三组对照）：

| 组 | 场景 | receiver 数 | 一次 save 执行次数 |
|----|------|-------------|---------------------|
| A | 同一函数对象，注册两次，**不带 uid** | 1 | 1 |
| B | 两个**不同函数**，共用**同一个 uid** | 1 | 先注册的 1 次，后注册的 **0 次** |
| C | 循环里定义 3 个不同局部函数 | 3 | **3 次** |

三条结论：

**其一，不带 uid 也会去重。** 源码 `dispatcher.py:148-151`：

```python
if dispatch_uid:
    lookup_key = (dispatch_uid, _make_id(sender))
else:
    lookup_key = (_make_id(receiver), _make_id(sender))   # ← 用函数对象的 id
```

不带 uid 时用**函数对象的 id** 作去重键。同一个函数对象注册两次，第二次的 key 与第一次相同，被丢弃。

**其二，`dispatch_uid` 的去重键是"uid 本身"，函数不参与比较。** 看上面那两行——带 uid 时 lookup_key 里**根本没有 receiver**。所以 B 组里两个不同的函数共用同一个 uid，第二个被**静默丢弃**，而且没有任何警告。

> ⚠️ 这是 `dispatch_uid` 最容易踩的坑。官方 docstring 只说"will not be added if another receiver was already connected with that dispatch_uid"，**没说函数不参与比较**。属实现行为，非契约保证。

**其三，真正的重复注册来自"不同的函数对象"。** C 组模拟了典型场景——在循环里、或在会被多次执行的代码块里定义 receiver。这三个函数 id 各不相同，去重装不上，于是注册三次、执行三次。

> ⚠️ **接口 C 的真相**：重构导致 `signals.py` 被以两个不同的模块名导入（比如 `apps.shop.signals` 与 `shop.signals`），Python 视为两个模块，函数对象也不同，于是每个 receiver 都注册了两遍。

**结论**：`dispatch_uid` 不是"防止重复注册"的万能药，它的真实语义是"给这个接收点起个名字，同名只留一个"。防重复注册要靠**保证模块只被导入一次**。

### 1.5 异常与返回值

**receiver 抛异常会怎样**（实验 7）：

| 情形 | 实测结果 |
|------|----------|
| 异常是否冒泡给调用方 | ✅ 冒泡，`save()` 那一行直接抛出 |
| 后面的 receiver 还执行吗 | ❌ 不执行（同一信号内串行，前一个是异常就中断） |
| autocommit 下商品落库了吗 | ✅ **已落库**（`post_save` 时 INSERT 已经提交） |
| 套了 `atomic` 才回滚 | ✅ 回滚 |
| `pre_save` 抛异常 | ❌ 未落库（还没写库） |

第三条值得停一下。我原以为"异常冒泡 → 事务回滚 → 数据没落库"，实测在 autocommit 模式下**完全相反**：单条 `save()` 自己就是一个已提交的事务，`post_save` 抛异常时数据已经写进去了。只有显式套了 `atomic` 才会回滚。

**receiver 的返回值**（实验 6）：`signal.send()` 会返回 `[(receiver, 返回值), ...]`，但 Django 内部发送模型信号时用的是 `send()`，返回值**不参与任何 ORM 逻辑**。所以 receiver 的返回值对 `save()` 没有任何影响——想改动数据，得在 receiver 里自己再写一次库。

---

## 第二幕：信号的真实代价

### 2.0 从机制到代价

第一幕讲的是"信号怎么用"，第二幕讲"用了之后要付什么账"。这五笔账分别是：事务边界、循环触发、批量操作、测试污染、性能黑盒。

### 2.1 事务边界：数据库退得回来，外部退不回来

这是本课最核心的一节。

#### 先分清两类副作用

receiver 里能做的事分两类，**它们在事务回滚时的表现完全相反**：

| 类型 | 例子 | 事务回滚后 |
|------|------|-----------|
| **数据库副作用** | `Notification.objects.create(...)` | ✅ **随事务一起回滚** |
| **外部副作用** | 发短信、发邮件、调第三方 HTTP API | ❌ **已发生，退不回来** 💥 |

这个区分是理解信号事务边界的关键。实测（实验 11）：

```python
@receiver(post_save, sender=Order)
def send_notification(sender, instance, created, **kwargs):
    Notification.objects.create(text=f"订单 {instance.pk}")  # ① 数据库，可回滚
    send_sms(instance.user.phone, "...")                      # ② 外部调用，退不回来

# 事务回滚后的实测结果：
#   订单本身       → 回滚，没创建
#   数据库通知 ①   → 也回滚了（同一事务）
#   短信 ②        → 已发出，退不回来 💥
```

> 💡 **这才是"post_save 发通知最解耦"真正的危险**：不在于数据库里多一条脏数据（那个反而会自动回滚），而在于**外部系统收到了一个根本不存在的订单的通知**。用户拿着短信来问"我的订单呢"，查无此单。

#### 这个区分修正了一个流行说法

你大概听过"用 `post_save` 发通知，事务回滚了通知却发出去了"。**这句话说对了一半**。

我备课时的预设就是这句话的字面意思——"通知会留在数据库里"。实测下来是反的：**数据库里的通知跟着一起回滚了**。

所以准确的说法应该是：

| 流行说法 | 实测真相 |
|---------|---------|
| "事务回滚了通知却发出去了" | 数据库通知**已回滚**；但**外部通知（短信/邮件）确实发出去了** |

危险真实存在，只是位置不在数据库层——**在外部系统**。这也是它更难被发现的原因：数据库里干干净净，投诉却从用户那边来。

**正解是 `transaction.on_commit`**（实验 11b）：

```python
@receiver(post_save, sender=Order)
def send_notification(sender, instance, created, **kwargs):
    if not created:
        return

    def _do():
        Notification.objects.create(text=f"订单 {instance.pk}")
        send_sms(instance.user.phone, "...")

    transaction.on_commit(_do)   # ✅ 提交后才执行，回滚就不执行
```

实测：回滚后通知 0 条、短信 0 封；提交后各 1 条。**两类副作用都被钉在提交之后。**

#### `on_commit` 在 autocommit 下不排队

第三处预设被推翻。我原以为 `on_commit` 的回调会排在当前代码之后执行，实测（实验 13）是**当场同步执行，而且早于 post_save 里它后面的代码**：

```python
def probe(sender, instance, **kwargs):
    transaction.on_commit(lambda: log.append("on_commit 回调"))
    log.append("post_save 内")

# 实测输出：['on_commit 回调', 'post_save 内']
```

源码依据（`base.py:727`）写得很清楚：

```python
if self.in_atomic_block:
    self.run_on_commit.append((set(self.savepoint_ids), func, robust))
elif not self.get_autocommit():
    raise TransactionManagementError(...)
else:
    # No transaction in progress and in autocommit mode; execute immediately.
    func()   # ← 没有事务就当场跑，不排队
```

这带来一个实用的心智模型：**`on_commit` 是"最迟在提交时执行"，不是"延后执行"**。没有事务时它退化为普通函数调用。

### 2.2 循环触发：一个 save 引发的连锁

在 receiver 里 `save()` 同一个对象，会再次触发信号（实验 14）：

```python
@receiver(post_save, sender=Product)
def recursive(sender, instance, created, **kwargs):
    instance.name = "改了"
    instance.save()   # ❌ 再次触发 post_save → 无限递归
```

实测：外部只调用了一次 `save()`，receiver 跑了 50 层（被我加的安全阀截断）。真实环境没有安全阀，结果是 `RecursionError`。

**两种打断方式**（实验 15）：

```python
# 解法一：用 queryset.update()（不发信号，天然不递归）
Product.objects.filter(pk=instance.pk).update(price=instance.price)

# 解法二：用 update_fields 缩小范围 + 守卫条件
@receiver(post_save, sender=Product)
def guarded(sender, instance, update_fields, **kwargs):
    if update_fields and "price" in update_fields:
        Product.objects.filter(pk=instance.pk).update(stock=instance.stock)
```

> 🔍 解法一更彻底。`queryset.update()` 在 SQL 层执行，完全绕开信号机制——这也是下一节的主角。

### 2.3 批量操作：哪些发信号，哪些不发

这是本课第二处"我原以为 X，实测是 Y"，而且**结论和很多人的印象相反**。

我原来的预设是"`queryset.delete()` 和 `bulk_create` 一样不发信号"。实测（实验 17）给出的完整矩阵：

| 操作 | `pre_save` | `post_save` | `pre_delete` | `post_delete` |
|------|-----------|-------------|--------------|---------------|
| `instance.save()` | 1 | 1 | 0 | 0 |
| `instance.delete()` | 0 | 0 | 1 | 1 |
| `queryset.update()` | **0** | **0** | 0 | 0 |
| `bulk_create()` | **0** | **0** | 0 | 0 |
| `bulk_update()` | **0** | **0** | 0 | 0 |
| `queryset.delete()` | 0 | 0 | **3**（每个对象一次） | **3** |

**不发信号的是 `update` 家族（`update` / `bulk_create` / `bulk_update`），不是 `delete`。**

> ⚠️ **这一点与很多人的印象相反，值得单独记住。**
> 提到"批量操作不发信号"，大多数人会连 `queryset.delete()` 一起算进去。实测下来恰恰相反——
> `delete()` 会给每个对象逐一发送 `pre_delete` / `post_delete`（源码 `deletion.py:493` 与 `deletion.py:542`），
> 真正静默的是 `update` / `bulk_create` / `bulk_update` 这三个。

> ⚠️ `bulk_create` 不发信号，直接后果就是**接口 B 那个 bug**：批量导入的商品没触发统计刷新，缓存里的分类商品数永远是旧的。
>
> 而且这里藏着第五处"不报错的错误"：**信号看起来覆盖了所有写入路径，实际上漏掉了一大半**。你以为的"全覆盖"，在批量操作面前是漏的。

#### 级联删除的反直觉行为

第四处预设被推翻，也是本课**最反直觉**的一个发现。

我原以为"级联删除时子对象收不到信号"。实测（实验 18 的 A/B 对照）发现，**这取决于子模型有没有挂 receiver**：

| 组 | Product（子模型）有没有 receiver | 数据库结果 | Product 的 `post_delete` |
|----|--------------------------------|-----------|--------------------------|
| A | 有 | 3 个子对象全删 | **3 次** |
| B | 没有 | 3 个子对象全删 | **0 次**（走了 fast_delete） |

两组的**数据库结果完全一样**，但信号次数不同。

根因在 `deletion.py:210` 的 `can_fast_delete()`：

```python
def can_fast_delete(self, objs, from_field=None):
    ...
    if self._has_signal_listeners(model):
        return False   # ← 有 receiver 就放弃快速删除
    ...
```

Django 为了性能优化，默认对无 receiver 的模型走"快速删除"——一条 SQL 直接删，不逐个加载对象、不发信号。**一旦你给子模型挂上 receiver，Django 就自动切换到"逐对象加载 + 逐个发信号"的慢路径。**

工程含义有两层：

- **好消息**：你想监听子模型删除，挂个 receiver 就行，Django 会自动配合。
- **坏消息**：给子模型加 receiver 会**改变删除的执行路径**——从 1 条 SQL 变成 N+1 条。在一个有 10 万子对象的父节点上删除，这个代价是数量级的。

> 💡 这也解释了为什么"级联删除收不到信号"这个说法会流传——大多数项目根本没给子模型挂 receiver，于是走的正是 fast_delete 路径。

### 2.4 测试里的信号：静默生效与静默失效

信号是**全局注册**的，这给测试带来两个方向的问题。

**问题一：不想让它跑，它跑了**（实验 23）。你写了个只测订单创建的测试，结果因为有个 `post_save` 写通知，数据库里凭空多出一条 `Notification`。如果你的断言碰巧检查了全表数量，就会莫名其妙地失败。

**问题二：想让它跑，它没跑**。某个测试 `disconnect` 了信号却没恢复，后续所有测试都受影响——而且症状表现为"结果偶发不对"，极难排查（实验 38）。

**正确的开关写法**（实验 26）：

```python
from contextlib import contextmanager

@contextmanager
def mute_signal(signal, receiver, sender):
    """临时断开某个 receiver，退出时恢复。"""
    signal.disconnect(receiver, sender=sender)
    try:
        yield
    finally:
        signal.connect(receiver, sender=sender)   # ✅ finally 保证异常路径也恢复
```

`try/finally` 是这里的关键——没有它，一个断言失败就会让信号永久断开，后面几十个测试集体失真。

**CI 防线**（实验 24）：信号的隐式 SQL 开销可以被 `assertNumQueries` 挡住。

```python
with self.assertNumQueries(1):        # 加 receiver 前
    Order.objects.create(...)

# 有人加了个 receiver，里面多查一次库 → 变成 2 条 → 测试失败
```

实测：无 receiver 时创建订单 1 条 SQL；挂上"多查一次"的 receiver 后变成 2 条。这条断言会在代码评审之外，自动挡住信号的隐式开销。

### 2.5 性能黑盒：钱花在 receiver 内部

先说一个反直觉的结论：**信号调度本身的开销小到测不出来**（实验 35）。

| 配置 | 实测耗时（100 次 save） |
|------|------------------------|
| 无 receiver | 9.07 ms |
| 1 个空 receiver | 9.77 ms |
| 5 个空 receiver | 8.70 ms |

注意看：5 个 receiver 那一组**比 0 个还快**。

这不是"信号有负开销"，而是说明**纯调度开销小于测量噪声**——微基准在这个量级上不可靠，三组数字的大小关系没有意义。

所以准确的表述是：

| 说法 | 是否准确 | 原因 |
|------|---------|------|
| "信号调度很慢" | ❌ | 实测测不出差异 |
| "信号调度几乎不花钱" | ⚠️ 方向对，但暗示"能测出来" | 实测是**测不出来**，不是"测出来很小" |
| "receiver 内部做的事在调用点看不见" | ✅ | 这才是真问题 |

准确的说法是：**receiver 内部做的事，在调用点是看不见的**（实验 21）。

```python
@receiver(post_save, sender=Product)
def n1_receiver(sender, instance, **kwargs):
    _ = instance.category.name   # ← 看起来只是"读个名字"
```

实测（10 个商品逐个 `save()`）：

| receiver 内部做什么 | SQL 条数 |
|---------------------|---------|
| 无 receiver | 10 条 |
| 读 `instance.category.name` | **20 条** |
| 只读 `instance.category_id` | 10 条 |

差别全在 receiver 内部。调用方看到的只是"SQL 从 10 条变成了 20 条"，不读 receiver 的代码根本不知道多在哪。

**放大检验**（实验 19，必查项 #28）：一个"查一次 + 写一次"的 receiver，让每条数据的 SQL 从 1 条变成 2 条。

| 数据量 | 无信号 | 有信号 |
|--------|--------|--------|
| 20 条 | 20 条 SQL | 40 条 SQL |
| **10 万条** | 10 万条 | **20 万条** |

多出来的 10 万次数据库往返，全部由一个"看起来很轻"的 receiver 造成。

---

## 第三幕：什么时候必须拆掉信号

### 3.0 从代价到决策

第二幕列了五笔账，第三幕回答"那还用不用"。答案是：**保留两类场景，其余改用显式调用**。

### 3.1 信号仍合适的两类场景

**场景一：横切关注点，且与业务无关**（实验 31）。

审计日志是最佳例子：

```python
# 一次注册，覆盖多个模型
for model in (Product, Order, Category):
    post_save.connect(audit, sender=model)
```

实测：三个模型各创建一次，产生 3 条审计记录。

判断依据三条：
- 与具体业务无关（审计是横切关注点，不是"下单流程的一部分"）
- 需要**全覆盖**（不希望有人忘记调用）
- 副作用是写本地库（可随事务回滚，不产生外部副作用）

**场景二：扩展你不拥有的代码**（实验 32）。

```python
# 想监听 django.contrib.auth 的 User 创建，但不想改 Django 源码
post_save.connect(on_user_created, sender=User)
```

实测：未改动 `auth` 一行代码，捕获到 2 次用户创建。

这是信号**不可替代**的场景——你没法在源码里加一行显式调用。

### 3.2 必须改成显式调用的场景

| 场景 | 为什么不能用信号 | 出处 |
|------|-----------------|------|
| 发邮件 / 短信 / 调外部 API | 外部副作用退不回来，回滚了照样发 | 实验 11 |
| 维护聚合统计 / 冗余计数 | `bulk_create` 不发信号，会算漏 | 实验 16、17 |
| 需要按条件跳过（如"内部导入不发通知"） | receiver 是全局的，无法对单次调用开小差 | 实验 28 |
| 逻辑属于核心业务流程 | 调用点看不出全貌，接手的人会漏掉 | 实验 37 |
| 需要按调用点传不同参数 | 信号参数固定，传不了自定义参数 | — |

第三条的实测（实验 28）：

```python
def create_order(product, quantity, notify=True):
    order = Order.objects.create(product=product, quantity=quantity)
    if notify:
        send_notice(order)
    return order

create_order(prod, 1, notify=False)   # ✅ 内部导入不发通知
create_order(prod, 1, notify=True)    # ✅ 正常下单发通知
```

信号做不到这一点——receiver 一旦注册就是全局的，没法对某一次调用说"这次别跑"。

### 3.3 显式调用与信号的行为等价性

值得说清楚的是：**两种写法在"结果"上没有差别**（实验 27）。

```python
# 写法 A：信号
post_save.connect(notify_impl, sender=Order)
Order.objects.create(product=prod, quantity=1)     # 副作用自动发生

# 写法 B：显式
def create_order_with_notice(product, quantity):
    order = Order.objects.create(product=product, quantity=quantity)
    send_notice(order)
    return order

create_order_with_notice(prod, 1)                  # 副作用同样发生
```

实测两者都发出 1 封通知。**差别不在结果，而在可读性**（实验 37）：

| | 信号写法 | 显式写法 |
|---|---------|---------|
| 调用点 | `product.save()` | `update_product_and_notify(product)` |
| 要知道会发生什么 | 得去找 `signals.py`、找 `ready()`、找所有 `connect` | 看函数名和函数体就够了 |
| receiver 数量 | 3 个（要数一遍才知道） | 函数里几行就是几行 |

### 3.4 迁移路径：三步拆掉一个信号

假设你现在有一个 `post_save` 在发订单通知，想改成显式调用。直接删掉信号会让所有老调用点失效，所以分三步：

**第一步：把 receiver 改成"只转发"的壳**（实验 29）

```python
# service 层（新）—— 动作单独抽出来
def notify_order_created(order):
    transaction.on_commit(lambda: send_sms(...))

def order_service_create(product, quantity):
    order = Order.objects.create(product=product, quantity=quantity)
    notify_order_created(order)
    return order

# 信号（旧）—— 只剩一层转发壳
@receiver(post_save, sender=Order)
def legacy_shim(sender, instance, created, **kwargs):
    if not created:
        return
    notify_order_created(instance)   # ✅ 只调"动作"，不再创建订单
```

⚠️ **这里有个必踩的坑**（实验 29b，而且我在备课过程中真的踩了）：

```python
def legacy_shim(sender, instance, created, **kwargs):
    order_service_create(instance.product, instance.quantity)   # ❌
```

shim 里调 service 的 create → create 又 `Order.objects.create()` → 又触发 shim → 无限递归。实测递归了 50 层后被我的安全阀截断，真实环境直接 `RecursionError`。

**第二步：找出所有老调用点**（实验 30）

```python
import traceback

def tracker(sender, instance, created, **kwargs):
    for frame in reversed(traceback.extract_stack()[:-1]):
        if "django" not in frame.filename:
            logger.info(f"signal triggered from {frame.filename}:{frame.lineno}")
            break
```

实测抓到 2 个调用点。生产环境跑一周，就能拿到完整的触发点清单，再逐个改成显式调用。

**第三步：逐个替换，注意双触发**（实验 29）

这一步有个隐蔽的陷阱——**shim 还在的时候，service 显式调用会导致通知发两遍**。

先看看不加防护会发生什么（实测，实验 29）：

| 路径 | 实测通知数 |
|------|-----------|
| 老路径（裸 `create()`，走 shim） | 1 |
| 新路径（`order_service_create()`） | **2** 💥 |

原因：service 显式发了一次，`Order.objects.create()` 又经 shim 再发一次。两条路径**叠加**而不是互斥。

后果很实际：用户收到两封一模一样的邮件。而在过渡期这是**常态**——你把 service 写好了、老调用点还没改完，两条路径同时生效。

正解是用一个开关让两条路径互斥：

```python
class OrderNotifier:
    def __init__(self):
        self.by_service = False

    def create(self, product, quantity):
        self.by_service = True
        try:
            order = Order.objects.create(product=product, quantity=quantity)
        finally:
            self.by_service = False       # ✅ finally 保证异常路径也复位
        self.notify(order)
        return order

    def shim(self, sender, instance, created, **kwargs):
        if not created or self.by_service:
            return                         # ✅ service 触发时 shim 让路
        self.notify(instance)
```

实测修正后：新路径 1 封、老路径 1 封，行为一致。等所有调用点都改成显式调用，再把 shim 整个删掉。

### 3.5 生产写法：批量场景必须绕开信号

承接 2.3 节——既然 `bulk_create` 不发信号，批量场景就必须**自己补上**"信号该做的事"。

这是必查项 #28 的重点场景：讲义批判"简化示例经不起放大检验"，自己就不能在批量示例上重犯。

```python
def bulk_create_with_audit(rows, category):
    """批量创建 + 批量审计。

    - bulk_create 避免 O(N) 次 INSERT
    - 审计日志也批量写（信号不触发，我们自己来）
    - 显式列出可预期的异常类型，不用裸 except Exception
    """
    from django.db import IntegrityError

    try:
        with transaction.atomic():
            objs = [
                Product(name=name, category=category, price=price)
                for name, price in rows
            ]
            created = Product.objects.bulk_create(objs, batch_size=500)
            AuditLog.objects.bulk_create(
                [
                    AuditLog(action="bulk_create", target=f"Product#{o.pk}")
                    for o in created
                    if o.pk
                ],
                batch_size=500,
            )
            return len(created)
    except IntegrityError as e:
        logger.error(f"数据库约束冲突：{e}")   # ✅ 只捕获可预期的异常
        raise
    except ValueError as e:
        logger.error(f"参数错误：{e}")
        raise
```

三个要点：

**其一，`batch_size` 让 SQL 数与 N 解耦。** 实测放大检验（`probe_scale_check.py`）：

| 写法 | 20 条数据 | **1 万条数据** | 判定 |
|------|----------|---------------|------|
| 逐条 `create` + 信号写审计 | 40 条 SQL | 2 万条 SQL | ❌ O(N) 往返 |
| `bulk_create` + 批量审计 | 4 条 SQL | **42 条 SQL** | ✅ 扛得住 10 万条 |

**其二，异常必须显式列出类型。** 这里复现了课 15 那个 P0（批量导入 200 行全部静默跳过且无报错）：

| 写法 | 实测（10 行，字段名故意拼错） |
|------|------------------------------|
| 裸 `except Exception` | 静默跳过 10 行，**程序无报错** |
| `except (IntegrityError, ValueError)` | 直接抛 `NameError`，立刻暴露 |

**其三，receiver 内部更新计数用 `F()` 而不是读后写。**

```python
# ❌ 读后写：一次 SELECT + 一次 UPDATE，且并发下会丢更新
cat = Category.objects.get(pk=instance.category_id)
cat.product_count = cat.product_count + 1
cat.save()

# ✅ F() 表达式：一条 UPDATE，且并发安全
Category.objects.filter(pk=instance.category_id).update(
    product_count=F("product_count") + 1
)
```

实测（20 条数据）：

| 写法 | SQL 条数 | 额外风险 |
|------|---------|---------|
| 读后写 | 60 条 | 并发下会丢更新（见课 15 实验 24） |
| `F()` | **40 条** | 无 |

---

## 第四幕：动手验证

> 本幕所有实验均已在 Django 6.1 + Python 3.13.14 实测通过。**48 个实验 / 115 项断言 / 零失败。**
> 实验工程：`%TEMP%/dj-lesson17-demo/signallab`（仓库外，用完即弃）

### 4.1 环境准备

```powershell
$py = "C:\Users\v_wypgwu\.workbuddy\binaries\python\envs\dj-course\Scripts\python.exe"
$env:PYTHONIOENCODING = "utf-8"      # 必须，否则中文输出乱码
cd $env:TEMP\dj-lesson17-demo\signallab
& $py run_lab1.py                     # 第一组：机制与注册（实验 1-10）
```

### 4.2 四组实验清单

| 脚本 | 实验 | 覆盖知识点 |
|------|------|-----------|
| `run_lab1.py` | 1-10 | 触发时机、参数、顺序、`sender`、重复注册、异常、m2m |
| `run_lab2.py` | 11-22 | 事务边界、循环触发、批量操作、级联删除、性能放大 |
| `run_lab3.py` | 23-32 | 测试污染、开关写法、显式调用对照、迁移路径 |
| `run_lab4.py` | 33-40 | 排查手段、性能量级、DRF 集成、决策表 |
| `run_lab_registration.py` | 3 | **独立进程**：`ready()` 注册 vs 不注册（必查项 #19） |
| `probe_scale_check.py` | A-D | 必查项 #28 放大检验（含 1 万条实测） |

实验 3 必须单独跑（涉及 app 加载配置，按必查项 #19 用独立进程）：

```powershell
& $py run_lab_registration.py signals      # 实验组：ready() 正常注册
& $py run_lab_registration.py nosignals    # 对照组：ready() 不注册
```

### 4.3 关键实验输出摘录

**实验 3（`ready()` 不注册的后果）**

```
【实验组】ready() 正常注册
  post_save(sender=Order) 上的 receiver 数 = 2
  create Order 后通知数：0 → 2
【对照组】ready() 不注册信号
  post_save(sender=Order) 上的 receiver 数 = 0
  create Order 后通知数：0 → 0
  ⚠️ 关键：**没有任何报错**，程序正常退出
```

**实验 5（重复注册三组对照）**

```
A 组实测：1 个 receiver，执行 1 次
B 组实测：1 个 receiver，g_a 执行 1 次 / g_b 执行 0 次
C 组实测：3 个 receiver，执行 3 次 ← 真正的重复注册
```

**实验 11（事务边界）**

```
实测：订单 0→0，数据库通知 0→0，邮件 0→1
⚠️ 关键区分：
   · 数据库副作用 → 随事务回滚，看似安全
   · 外部副作用（邮件/短信/HTTP 调用）→ **发了就是发了**，回滚不回来
```

**实验 17（批量操作信号矩阵）**

```
操作                      pre_save  post_save  pre_del  post_del
queryset.update()              0          0        0         0
bulk_update()                  0          0        0         0
instance.save()                1          1        0         0
queryset.delete()              0          0        3         3
instance.delete()              1          1        1         1
```

**实验 18（级联删除的 A/B 对照）**

```
A 组（Product 有 receiver）：Category 信号 1 次，Product 信号 3 次
B 组（Product 无 receiver）：Category 信号 1 次（子对象走了 fast_delete，无信号）
💡 两组的数据库结果完全一样（都是 0），**但信号次数不同**
```

**放大检验（必查项 #28）**

```
实测：20 条 → 4 条 SQL（分 2 批，与 N 无关）
实测：10000 条 → 42 条 SQL
对比：A 组写法需要 20000 条 SQL
```

### 4.4 信号体检脚本

实验 40 给了一个可以直接放进项目的体检脚本，扫出所有已注册的 receiver 并标出高风险项：

```
体检结果（2 条）：
信号            receiver            范围      异步
post_save     rec_a               指定      False
post_save     rec_b               全局      False  ⚠️ 全局
```

把它做成管理命令放进 CI，receiver 数量增长就有预警。

---

## 第五幕：三张决策表

### 5.1 信号 vs 显式调用

| 判据 | 用信号 | 用显式调用 |
|------|--------|-----------|
| 是否横切关注点（与业务无关） | ✅ | |
| 是否需要"全覆盖、不许有人忘记" | ✅ | |
| 是否要扩展不拥有的代码 | ✅ | |
| 是否有外部副作用（邮件/短信/API） | | ✅ |
| 是否需要按条件跳过 | | ✅ |
| 是否属于核心业务流程 | | ✅ |
| 批量路径也要生效 | | ✅ |
| 需要按调用点传不同参数 | | ✅ |

### 5.2 批量操作与信号

| 操作 | 发信号吗 | 批量场景要注意 |
|------|---------|---------------|
| `instance.save()` | ✅ | O(N) 次往返，大数据量改用 `bulk_*` |
| `instance.delete()` | ✅ | 同上 |
| `queryset.update()` | ❌ | 需要信号语义时，自己补 |
| `bulk_create()` | ❌ | **最容易漏**，导入类功能必须自查 |
| `bulk_update()` | ❌ | 同上 |
| `queryset.delete()` | ✅ 逐对象 | 子模型无 receiver 时走 fast_delete，不发 |

### 5.3 信号的代价与对策

| 代价 | 表现 | 对策 |
|------|------|------|
| 事务边界 | 外部副作用退不回来 | `transaction.on_commit` |
| 循环触发 | `RecursionError` | `queryset.update()` / `update_fields` 守卫 |
| 批量漏触发 | 统计数据算漏 | 批量路径自己补，或用 `F()` |
| 测试污染 | 结果偶发不对 | `mute_signal` 上下文管理器 + `finally` |
| 性能黑盒 | SQL 莫名变多 | `assertNumQueries` + 体检脚本 |
| 注册失效 | 静默不执行 | shell 里枚举 `sig.receivers` |

---

## 高频误区

| 误区 | 真相 | 出处 |
|------|------|------|
| "用 `post_save` 发通知最解耦" | 它在**事务内**执行。数据库副作用能回滚，**外部副作用（短信/邮件）退不回来** | 实验 11 |
| "信号能覆盖所有写入" | `update` / `bulk_create` / `bulk_update` **一个都不发** | 实验 16、17 |
| "`queryset.delete()` 不发信号" | **反了**。它逐对象发；不发的是 `update` 家族 | 实验 17 |
| "级联删除子对象收不到信号" | 取决于**子模型有没有 receiver**——有就走慢路径发信号，没有就走 fast_delete | 实验 18 |
| "加 `dispatch_uid` 就能防重复注册" | 它的去重键是 **uid 本身**，不是"函数+uid"；不同函数共用 uid 会被静默丢弃 | 实验 5 |
| "不带 uid 注册两次会执行两次" | **不会**。不带 uid 也用 `id(receiver)` 去重 | 实验 5 |
| "receiver 抛异常，数据会回滚" | autocommit 下**已落库**；只有套了 `atomic` 才回滚 | 实验 7 |
| "`on_commit` 是延后执行" | 没有事务时**当场同步执行**，甚至早于 post_save 后续代码 | 实验 13 |
| "信号慢" | 调度开销测不出来；慢的是 receiver **内部**做的事 | 实验 35 |
| "`ready()` 忘了 import 会报错" | **不报错**，所有 receiver 静默失效 | 实验 3 |

---

## 本课"不报错的错误"清单

| # | 错误 | 为什么没报错 | 怎么发现 |
|---|------|-------------|---------|
| 1 | `ready()` 没 import `signals` | 空 receiver 列表不是错误状态 | 枚举 `sig.receivers`（实验 3、33） |
| 2 | 不同函数共用 `dispatch_uid` | 后者被静默丢弃，无警告 | 数 receiver 数（实验 5 B 组） |
| 3 | receiver 在循环里定义 → 重复注册 | 函数 id 不同，去重装不上 | 数 receiver 数（实验 5 C 组） |
| 4 | 外部副作用在事务内发出 | 回滚管不到外部系统 | 断言"回滚后外部调用次数"（实验 11） |
| 5 | `bulk_create` 漏触发业务逻辑 | 批量路径本就不发信号 | 批量后校验统计值（实验 16） |
| 6 | 给子模型加 receiver 改变删除路径 | 行为正确，只是变慢 | SQL 计数对比（实验 18） |
| 7 | shim 期双触发 | 通知发两遍，看似"功能正常" | 分别断言两条路径的次数（实验 29） |

> 📌 阶段 5 累计 15 处（课 15 共 4 处、课 16 共 4 处、本课 7 处）。

---

## 自检题

<details>
<summary><b>【1】</b>为什么"用 post_save 发短信"是危险写法？危险到底在哪一层？</summary>

危险**不在数据库层**，而在外部系统。

实测（实验 11）显示：receiver 里写的 `Notification` 记录会**随事务一起回滚**（它在同一个 `atomic` 块内），所以数据库不会留下脏数据。

真正的危险是短信/邮件/HTTP 调用这类**外部副作用**——它们不参与数据库事务，发出去就退不回来。事务回滚后，用户收到"订单创建成功"的短信，但订单根本不存在。

正解是 `transaction.on_commit`，它把两类副作用都钉在提交之后（实验 11b 实测：回滚后通知 0 条、短信 0 封）。

</details>

<details>
<summary><b>【2】</b>下列操作哪些发信号？`bulk_create`、`queryset.update()`、`queryset.delete()`、`instance.save()`</summary>

| 操作 | 发信号吗 |
|------|---------|
| `bulk_create()` | ❌ 不发 |
| `queryset.update()` | ❌ 不发 |
| `queryset.delete()` | ✅ **发**，逐对象各一次 |
| `instance.save()` | ✅ 发 |

最反直觉的是第三条——很多人以为 `delete()` 和 `bulk_create` 一样不发信号，实测恰恰相反（实验 17）。不发信号的是 `update` 家族。

</details>

<details>
<summary><b>【3】</b>给子模型加一个 `post_delete` receiver，会怎样影响父模型的删除？</summary>

会**改变 Django 的删除执行路径**。

`can_fast_delete()`（`deletion.py:210`）里有一行 `if self._has_signal_listeners(model): return False`。子模型没有 receiver 时走 fast_delete（一条 SQL 直接删，不发信号）；一旦挂上 receiver，Django 就切换到"逐对象加载 + 逐个发信号"的慢路径。

实测（实验 18）：两组数据库结果完全一样（子对象都被删光），但 A 组发 3 次信号、B 组发 0 次。

工程含义：在有大量子对象的父模型上，给子模型加 receiver 会让删除**从 1 条 SQL 变成 N+1 条**。

- 好消息：你想监听子模型删除，挂个 receiver 就行，Django 会自动配合（放弃快速删除）
- 坏消息：这个"自动配合"是静默的——你加 receiver 时不会收到任何性能警告

实测（实验 18）：A 组（Product 有 receiver）发 3 次信号，B 组（无 receiver）发 0 次，两组的数据库结果都是"3 个子对象全删"。

</details>

<details>
<summary><b>【4】</b>`dispatch_uid` 到底防的是什么？</summary>

它的去重键是 **uid 本身**，不是"函数 + uid"（源码 `dispatcher.py:148-151`）。

三条实测（实验 5）：

- **A 组**：不带 uid 也去重——用 `id(receiver)` 作键，同一函数对象注册两次只留一个
- **B 组**：两个**不同函数**共用同一个 uid → 后者被**静默丢弃**，无任何警告
- **C 组**：循环里定义 3 个不同局部函数 → 注册 3 个、执行 3 次 ← 真正的重复注册

所以 `dispatch_uid` 的语义是"给这个接收点起个名字，同名只留一个"，**不是**"防止重复注册"。防重复注册要靠保证模块只被导入一次。

</details>

<details>
<summary><b>【5】</b>迁移一个信号到显式调用时，最容易踩的两个坑是什么？</summary>

**坑一：shim 反向调用 service 导致无限递归**（实验 29b）。

```python
def legacy_shim(sender, instance, created, **kwargs):
    order_service_create(...)   # ❌ 这里面又 Order.objects.create() → 又触发 shim
```

备课过程中这个错误**真的发生过**，实测递归 50 层后被安全阀截断，真实环境直接 `RecursionError`。正解是 shim 只调用"动作"（`notify_order_created`），不再创建订单。

**坑二：shim 期双触发**（实验 29）。

shim 还在的时候，service 显式发一次、`Order.objects.create()` 又经 shim 发一次，通知发两遍（实测新路径 2 封 vs 老路径 1 封）。正解是用一个开关（如 `self.by_service`）让两条路径互斥。

</details>

<details>
<summary><b>【6】</b>怎么在 CI 里挡住信号的隐式开销？</summary>

用 `assertNumQueries`（实验 24）。

实测：无 receiver 时创建订单 1 条 SQL；挂上一个"多查一次库"的 receiver 后变成 2 条。断言 `assertNumQueries(1)` 会在这个 receiver 合入时**立刻失败**，把讨论提前到代码评审阶段。

配合实验 40 的体检脚本（枚举所有 receiver、标出全局 receiver），可以在 receiver 数量失控前预警。

</details>

<details>
<summary><b>【7】</b>信号调度本身的性能开销大吗？"信号慢"这个说法准确吗？</summary>

**调度开销小到测不出来**。

实测（实验 35，每组 100 次 save）：无 receiver 9.07ms、1 个空 receiver 9.77ms、5 个空 receiver 8.70ms——5 个甚至可能比 0 个更快，说明纯调度开销被噪声淹没。

准确的说法是：**receiver 内部做的事，在调用点看不见**（实验 21）。

实测 10 个商品逐个 `save()`：无 receiver 10 条 SQL；receiver 里读 `instance.category.name` 变成 20 条。调用方只看到"SQL 变多了"，不读 receiver 代码不知道多在哪。

放大检验（实验 19）：一个"查一次 + 写一次"的 receiver，让 10 万条数据从 10 万条 SQL 变成 20 万条。

</details>

<details>
<summary><b>【8】</b>`on_commit` 在没有事务时会怎样？</summary>

**当场同步执行，不排队**。

源码 `base.py:727` 写得很清楚：`No transaction in progress and in autocommit mode; execute immediately`。

实测（实验 13）：

```python
def probe(sender, instance, **kwargs):
    transaction.on_commit(lambda: log.append("on_commit 回调"))
    log.append("post_save 内")

# 输出：['on_commit 回调', 'post_save 内']  ← 回调反而更早
```

心智模型：`on_commit` 是"**最迟**在提交时执行"，不是"延后执行"。没有事务时它退化为普通函数调用。

</details>

<details>
<summary><b>【9】</b>哪些场景信号是**不可替代**的？</summary>

两类（实验 31、32）：

**一、横切关注点且需要全覆盖**——审计日志是最佳例子。判断依据三条：与具体业务无关、不希望有人忘记调用、副作用是写本地库（可随事务回滚）。

**二、扩展你不拥有的代码**——比如监听 `django.contrib.auth` 的 `User` 创建。你没法在 Django 源码里加一行显式调用，信号是唯一选择。实测未改动 `auth` 一行代码就捕获到 2 次用户创建。

其余场景（外部副作用、聚合统计、核心业务流程、需要条件跳过的逻辑）都应该改用显式调用。

</details>

<details>
<summary><b>【10】</b>批量导入 1 万条数据，怎么保证"信号该做的事"也被做到？</summary>

`bulk_create` 不发信号，所以要**自己补上**，且必须批量（必查项 #28 放大检验）：

```python
with transaction.atomic():
    created = Product.objects.bulk_create(objs, batch_size=500)
    AuditLog.objects.bulk_create(
        [AuditLog(action="bulk_create", target=f"Product#{o.pk}")
         for o in created if o.pk],
        batch_size=500,
    )
```

实测对比：

| 写法 | 20 条 | 1 万条 |
|------|-------|--------|
| 逐条 create + 信号写审计 | 40 条 SQL | 2 万条 SQL |
| `bulk_create` + 批量审计 | 4 条 SQL | **42 条 SQL** |

另外，receiver 内部更新计数要用 `F()` 而不是"读后写"——实测 20 条数据下 60 条 SQL vs 40 条 SQL，且读后写在并发下会丢更新（课 15 实验 24）。

</details>

<details>
<summary><b>【11】</b>测试里怎么安全地临时关掉一个信号？</summary>

用带 `try/finally` 的上下文管理器（实验 26）：

```python
@contextmanager
def mute_signal(signal, receiver, sender):
    signal.disconnect(receiver, sender=sender)
    try:
        yield
    finally:
        signal.connect(receiver, sender=sender)   # ✅ 保证异常路径也恢复
```

`finally` 是关键。没有它，一个断言失败就会让信号永久断开，后续几十个测试集体失真，而且症状表现为"结果偶发不对"，极难排查（实验 38）。

</details>

<details>
<summary><b>【12】</b>怎么确认生产环境里到底挂了哪些 receiver？</summary>

在 shell 里枚举（实验 33、40）：

```python
from django.db.models.signals import pre_save, post_save

for name, sig in [("pre_save", pre_save), ("post_save", post_save)]:
    print(f"{name}: {len(sig.receivers)} 个")
```

实验 40 给出了完整版体检脚本，能列出每个 receiver 的函数名、作用范围（指定 sender / 全局）、是否异步，并给全局 receiver 打上 ⚠️ 标记：

```
信号            receiver            范围      异步
post_save     rec_a               指定      False
post_save     rec_b               全局      False  ⚠️ 全局
```

把它做成管理命令放进 CI，receiver 数量增长就有预警。

</details>

---

## 事实核查说明

本课结论分四类标注，**未经实测的一律标明**：

| 结论 | 来源 |
|------|------|
| 五个模型信号的触发顺序 | ✅ 官方文档明示 + 实测确认（实验 2） |
| `post_save` 的 `created` / `update_fields` 参数 | ✅ 官方文档明示 + 实测确认（实验 1） |
| `dispatch_uid` 用于唯一标识 receiver | ✅ 官方文档明示（docstring） |
| `on_commit` 无事务时立即执行 | ✅ `base.py:727` 源码明示 + 实测（实验 13） |
| `can_fast_delete` 检查信号监听器 | ✅ `deletion.py:210/235` 源码明示 + 实测（实验 18） |
| `queryset.delete()` 逐对象发信号 | ✅ `deletion.py:493/542` 源码明示 + 实测（实验 17） |
| **`dispatch_uid` 的去重键不含函数，只认 uid** | 🔬 **实测确认**（实验 5 B 组）——文档措辞未明示此边界 |
| **不带 uid 也用 `id(receiver)` 去重** | 🔬 **实测确认**（实验 5 A 组）· **本课首次** |
| **autocommit 下 `post_save` 抛异常数据已落库** | 🔬 **实测确认**（实验 7）· **本课首次** |
| **数据库副作用随事务回滚，外部副作用不会** | 🔬 **实测确认**（实验 11）· **本课首次** |
| **`queryset.delete()` 会发信号（与常见印象相反）** | 🔬 **实测确认**（实验 17）· **本课首次** |
| **子模型有无 receiver 会改变级联删除路径** | 🔬 **实测确认**（实验 18）· **本课首次** |
| **shim 期双触发** | 🔬 **实测确认**（实验 29）· **本课首次** |
| **`on_commit` 回调早于 post_save 后续代码** | 🔬 **实测确认**（实验 13）· **本课首次** |
| 信号调度开销可忽略 | 🔬 实测确认（实验 35，微基准噪声大于信号开销） |
| Django 7.0 后上述行为是否变化 | ⏳ **未验证**，需重跑全部实验 |

> ⚠️ 本课七条"实测确认但文档未明示"的结论都属于**实现行为**而非契约保证。其中 `dispatch_uid` 语义、`can_fast_delete` 的信号检查、`on_commit` 的立即执行三条虽然有源码依据，但 Django 未在文档中承诺其稳定性——**升级大版本需重新跑 `run_lab1.py` / `run_lab2.py` 验证**。

---

## 验证环境

| 项 | 值 |
|----|-----|
| Django | **6.1** |
| DRF | **3.18.0** |
| Python | **3.13.14**（Windows 托管 venv `dj-course`） |
| 数据库 | SQLite（内存库） |
| 实验工程 | `%TEMP%/dj-lesson17-demo/signallab` |
| 实验数 / 断言数 | **48 个实验 / 115 项断言**，零失败 |

> ⚠️ **环境受限说明（必查项 #20）**：
> ①**未使用 WSL**（课 2 起 `wsl.exe` 被本机安全策略拦截），全程 Windows 托管 Python，所有命令为 PowerShell 语法。
> ②**SQLite 内存库**——本课的事务边界实验（实验 11、12、13）在 SQLite 上验证。事务语义由 Django 统一管理，结论与 PostgreSQL 一致；但**行级锁与并发行为**在 SQLite 上不可靠（课 15 实验 25 已验证 `select_for_update` 在 SQLite 静默失效），本课未涉及并发场景。
> ③**外部副作用用列表模拟**（`SENT_MAIL`），未真实发送短信/邮件——`on_commit` 的时序结论不受影响，但真实网络调用的**超时与重试**行为未在本课实测。
> ④**DRF 集成**（实验 36）用最小 ViewSet + `APIClient` 验证，未覆盖复杂序列化器场景。
>
> 所有命令均已在上述环境逐条跑通。

---

🚀 **下一批接力提示词**

> 课 18《中间件与请求链路》。带上这三个问题：
> 1. **请求链路上的隐式行为** —— 本课的信号是"模型层的隐式调用链"，课 18 的中间件是"请求层的隐式拦截"。两者都"看不见"，但排查手段不同，值得对照
> 2. **`on_commit` 与响应阶段** —— 本课的 `on_commit` 在事务提交时执行；中间件的 `__call__` 与 `process_response` 在响应阶段执行。什么时候该用哪个？
> 3. **全局注册的治理** —— 信号的 receiver 可以枚举（`sig.receivers`），中间件的顺序可以打印（`settings.MIDDLEWARE`）。把这两者做成统一的"系统隐式行为体检"，是阶段 6 工程化的好素材
>
> 提示：本课实验工程在 `%TEMP%/dj-lesson17-demo/signallab`，`labkit.py` 的 `Check` 断言器与 `mute_signal` 上下文管理器可直接复用于中间件顺序的量化对照。

---

🧭 **课程导航**

- ⬅️ 上一课：[课 16《性能：缓存与异步》](./lesson-16-性能缓存与异步.md)
- ➡️ 下一课：[课 18《中间件与请求链路》](../../6-工程化与生产/lessons/lesson-18-中间件与请求链路.md)
- 📖 所属阶段：[阶段 5 性能与异步](../overview.md)
- 🏠 课程目录：[02-课程目录.md](../../../02-课程目录.md)
- 🗺️ 学习路径：[01-学习路径总览.md](../../../01-学习路径总览.md)

---

## 本课小结：三句话

1. **信号在事务内执行**——数据库副作用能回滚，外部副作用（短信/邮件/API）退不回来，所以 `post_save` 发通知必须配 `transaction.on_commit`。
2. **信号覆盖不了批量操作**——`update` / `bulk_create` / `bulk_update` 一个都不发（但 `queryset.delete()` 反而会逐对象发）。
3. **保留两类场景，其余改显式**——横切关注点（审计）与扩展第三方代码留信号；外部副作用、聚合统计、核心业务流程一律改成 service 层显式调用。

> 🎉 **阶段 5 到此结课**。三课累计：课 15 的 N+1 与并发、课 16 的缓存与异步、本课的信号治理——回答的都是同一个问题：**"让它快"和"让它对"之间，哪些捷径不能走**。
>
> 下一阶段（阶段 6 工程化与生产）从 [课 18《中间件与请求链路》](../../6-工程化与生产/lessons/lesson-18-中间件与请求链路.md) 开始。
