# 课 13《多数据库与 DB 路由》

> 🧭 所属阶段：[阶段 4 数据层纵深](../overview.md) ｜ 上一课：[课 12 索引、约束与连接池](./lesson-12-索引约束与连接池.md) ｜ 下一课：课 14 迁移工程（阶段 4）
>
> 🎯 **本课回答三个问题**：查询到底去了哪个库？为什么刚写完就读不到？多库会禁掉哪些单库下的默认行为？
>
> ⚙️ **实跑环境**：Django **6.1** / Python **3.13.14**（Windows 托管 venv `dj-course`）。三个 SQLite 文件分别扮演 `default`（主库）、`replica`（从库）、`logs`（独立业务库）。
>
> 📦 实验工程：`%TEMP%/dj-lesson13-demo/routelab`，**25 个实验全部实测通过**（断言 85 项，零失败）。

#### 怎么跑起来

```bash
# 复用课 2 建的虚拟环境
# Windows: C:\Users\<你>\.workbuddy\binaries\python\envs\dj-course\Scripts\python.exe

cd %TEMP%/dj-lesson13-demo/routelab
set PYTHONPATH=<routelab绝对路径>/apps      # shop / logs 两个 app 在 apps/ 下
set PYTHONIOENCODING=utf-8                  # 否则中文输出乱码

python manage.py makemigrations shop logs
python manage.py migrate                     # 主库
python manage.py migrate --database=replica  # 从库
python manage.py migrate --database=logs     # 独立业务库

python run_lab.py     # 实验 1-9 ：钩子机制与跨库关系
python run_lab2.py    # 实验 10-16：迁移与事务
python run_lab3.py    # 实验 17-21：主从延迟的工程解法
python run_lab4.py    # 实验 22-24：社区方案验证与系统检查
python run_lab5.py    # 实验 25  ：评审 P0 验证（跨 app 外键会不会被拦）
```

> 💡 **不需要真的装 PostgreSQL**。路由、跨库校验、事务、迁移这些**都是 Python 侧的逻辑**，用三个 SQLite 文件就能完整复现。真正只有 PostgreSQL 才有的东西（WAL 复制位点）本课会明确标注为「伪代码 + 方案说明」，不假装跑过。

---

## 开场：三个"看起来对"的决定

**决定一**：数据库压力大，运维加了两台从库。你配好 `DATABASE_ROUTERS`，写主读从，上线后**用户投诉"我刚发的文章，刷新就没了"**。

**决定二**：审计日志量太大，你想把它挪到独立的库。加了个外键指向业务表，结果**赋值就报错**，模型根本用不起来。

**决定三**：下单要写业务库和审计库，你写了 `@transaction.atomic`。上线后对账发现**业务库有记录、审计库没有**，而代码"明明在一个事务里"。

三个决定的共同点：都在**用单库的直觉去套多库的世界**。单库下"写完就能读到""外键随便建""事务包住就安全"这三条常识，多库下全部失效。

这一课就是要把这三条直觉拆开，换成可验证的做法。

---

## 第一幕：DATABASE_ROUTERS —— 四个钩子决定一切

### 1.1 先看清默认行为：没有路由器时，一切归 `default`

在讲钩子之前，先确认基线。Django 的默认路由方案是开箱即用的（`docs/topics/db/multi-db` 原文："The default routing scheme ensures that objects remain 'sticky' to their original database"）：

```python
Article.objects.all()                    # → default
Article.objects.using("replica")         # → replica
obj.save(using="replica")                # → replica，且 obj._state.db 被记住
```

实测（实验 2）：

```
✅ Article.objects.all().db                   实际='default'   期望='default'
✅ Article.objects.using('replica').db        实际='replica'   期望='replica'
✅ create() 后 obj._state.db                   实际='default'   期望='default'
✅ save(using='replica') 后 _state.db          实际='replica'   期望='replica'
```

两条默认规则，务必记住：

1. **粘性（sticky）**：从哪个库读出来的对象，就存回哪个库 —— 靠 `instance._state.db` 记住。
2. **回落 `default`**：没指定、也没粘性信息时，一律走 `default`。

> ⚠️ **粘性是后面那个大坑的根源**。第二幕会看到，它配上一个"只写了一半的路由器"，就能把写操作静默送进只读库。

### 1.2 四个钩子的调用时机（实测，不是猜的）

`DATABASE_ROUTERS` 里每个路由器**最多提供四个方法**，可以只实现其中几个。它们的调用时机，我用一个"只记录不表态"的 `TraceRouter` 抓了一遍（实验 1）：

```
① 查询（qs 求值）:
     ('db_for_read', 'Article', [])
② 新建（objects.create）:
     ('db_for_write', 'Article', [])
③ 赋外键（a.author = au）:
     ('db_for_write', 'Author', [])
     ('allow_relation', 'Author', [])
④ 保存已有对象（obj.save()）:
     ('db_for_write', 'Article', ['instance'])
⑤ migrate：共调用 17 次，去重后 1 组
     ('allow_migrate', 'default')
```

四条结论：

- **`db_for_read` 在 queryset 求值时调用**，不是在 `.filter()` 时。所以 `qs = Article.objects.all()` 还没决定去哪个库。
- **赋外键会连调两个钩子**：先 `db_for_write` 确定对方对象该在哪个库，再 `allow_relation` 问"这关系允许吗"。
- **`hints` 里目前只有 `instance` 一种键**（官方文档明示："At present, the only hint that will be provided is `instance`"）。保存已有对象时才会带上，新建时是空的。
- **`allow_migrate` 只在迁移时调用**，每次 `migrate` 会对每个 `(库, app)` 组合问一遍。

### 1.3 钩子的返回值语义：这是最容易记混的地方

四个钩子的返回值规则**各不相同**，混用就会出事：

| 钩子 | 返回值 | 语义 | 全部返回 None 时 |
|------|--------|------|------------------|
| `db_for_read` / `db_for_write` | 库别名 或 `None` | `None` = 我没意见 | 回落 `instance._state.db`，再回落 `default` |
| `allow_relation` | `True` / `False` / `None` | **`None` = 我没意见** | **只允同库关系** |
| `allow_migrate` | `True` / `False` / `None` | **`None` = 我没意见** | **一律放行（`True`）** |

两个 `allow_*` 的兜底行为**完全相反**，这是本课第一个必须记住的对照：

```python
# django/db/utils.py:244-268（源码原文）
def allow_relation(self, obj1, obj2, **hints):
    for router in self.routers:
        ...
        allow = method(obj1, obj2, **hints)
        if allow is not None:
            return allow
    return obj1._state.db == obj2._state.db   # ← 兜底：只允同库

def allow_migrate(self, db, app_label, **hints):
    for router in self.routers:
        ...
        allow = method(db, app_label, **hints)
        if allow is not None:
            return allow
    return True                                # ← 兜底：一律放行
```

实测坐实（实验 7、12）：

```
✅ 无路由时 allow_migrate('default','shop')      实际=True   期望=True
✅ 无路由时 allow_migrate('replica','shop')      实际=True   期望=True   ← 任何库都放行
✅ allow_migrate('replica','shop')（None→回落）   实际=True   期望=True   ← 危险
```

> 🚨 **`allow_migrate` 返回 `None` 等于放行**。写路由器时如果只想管一个 app，管完必须显式把其他情况处理掉 —— 否则剩下的一切都会被静默放行到**每一个库**上。这是"按 app 分库"最常见的翻车方式。

### 1.4 多个路由器的顺序：第一个"表态"的胜出

`DATABASE_ROUTERS` 是**有序列表**。官方文档原文："The order in which routers are processed is significant."

规则（源码 `utils.py:224-238`）：**依次询问，第一个返回非 `None` 的直接采用**。

实测（实验 6）：

```
✅ [None 路由, 全从路由] 读     实际='replica'   ← 前者不表态，后者决定
✅ [全从路由, None 路由] 读     实际='replica'   ← 前者直接决定
✅ [None 路由, 全主路由] 读     实际='default'
✅ 无路由时读回落到             实际='default'
```

注意这里的关键词是**非 `None`**，不是"非空"。因为 `db_for_read` 的合法返回值只有库别名和 `None`，所以：

- 返回 `"default"` → 采用，立即停止询问
- 返回 `None` → 不表态，继续问下一个

> 💡 **实践建议**：把**最具体**的路由器放前面，**最宽泛**的放后面。比如先放 `AuthRouter`（只管 auth/contenttypes），再放 `PrimaryReplicaRouter`（管剩下所有）。顺序反了，宽泛的那个会把所有请求截胡。

### 1.5 主从路由的最小实现

官方文档给的示例，我们跑通了（实验 3）：

```python
class PrimaryReplicaRouter:
    def db_for_read(self, model, **hints):
        return "replica"

    def db_for_write(self, model, **hints):
        return "default"
```

实测：

```
create() 后 obj._state.db =        default
✅ queryset 的 .db（读）            实际='replica'
✅ 读确实落在 replica               实际='replica'
db_for_write(Article) =            default
db_for_read(Article) =             replica
```

> ⚠️ **官方自己给这个示例打了免责声明**，原文值得逐字读一遍：
>
> "This example is intended as a demonstration of how the router infrastructure can be used to alter database usage. It **intentionally ignores some complex issues**... This example **won't work if any of the models in myapp contain relationships to models outside of the other database**... The primary/replica configuration described is also flawed – **it doesn't provide any solution for handling replication lag**... It also **doesn't consider the interaction of transactions** with the database utilization strategy."
>
> 翻译：官方明说了这是**教学示例，不是生产方案**。它不处理复制延迟、不处理事务、跨库关系会坏。第二幕和第三幕讲的正是这三件事。

---

## 第二幕：写后读不一致 —— 主从架构的必修课

### 2.1 不一致是真的：写入成功却在列表里读不到

先看复现（实验 4）。主从路由已配好，写入一篇文章后立刻读：

```
—— 写入后立刻读（复制尚未发生）——
主库条数（using('default')）          1
从库条数（using('replica')）          0
默认读（经路由 → replica）             0
✅ 【不一致】默认读看不到刚写的          实际=0   期望=0
✅ 【不一致】详情也查不到                实际=False
—— 手动强制读主库——
✅ using('default') 能读到            实际=True
—— 模拟复制完成——
✅ 复制完成后默认读能读到               实际=1
—— 再写一次，制造新的延迟窗口——
✅ 新窗口内又读不到了                   实际=1
```

这就是用户投诉的那个 bug。成因一句话：**写和读去了两个不同的物理库，中间隔着一段复制延迟**。

关键点在于——**这段延迟不是异常，是常态**。主从复制是异步的，延迟可以是几十毫秒，也可以是几秒（大事务、从库负载高、网络抖动时更长）。你的代码不能假设它是 0。

### 2.2 一个更隐蔽的坑：只写 `db_for_read` 会把写操作送进只读库

这是本课**最危险的一条**，因为它不报错。

假设你只实现了读钩子（可能觉得"写本来就走 default，不用管"）：

```python
class ReadOnlyReplicaRouter:
    def db_for_read(self, model, **hints):
        return "replica"
    # 没有 db_for_write
```

然后这段代码：

```python
obj = Article.objects.get(pk=1)      # 经路由 → replica，obj._state.db = 'replica'
obj.title = "新标题"
obj.save()                            # 去哪儿了？
```

实测（实验 5）：

```
经路由读出来的对象 _state.db =      replica
保存后 _state.db =                 replica
✅ 【事故】写入落到了只读库           实际='replica'
主库标题（没变）                     新建一篇
从库标题（被改了）                    在从库上改过的标题
✅ 主库未被更新                      实际='新建一篇'
✅ 从库被写入                       实际='在从库上改过的标题'
```

**写入成功了，写进了从库。** 后果是双重的：

1. 主库没这条更新 —— 从库的数据会被主库的下一次复制**直接覆盖**，你的修改凭空消失。
2. 从库被写入 —— 在真实的主从里，从库通常是只读的，这一步要么报权限错误，要么（更糟）造成主从数据 divergence。

机制就在 `utils.py:233-238`：

```python
instance = hints.get("instance")
if instance is not None and instance._state.db:
    return instance._state.db      # ← 粘性兜底：对象从哪来，回哪去
return DEFAULT_DB_ALIAS
```

你没提供 `db_for_write`，路由器不表态，于是**粘性规则生效**，把写操作送回了对象出生的那个库。

> 🚨 **规则：实现 `db_for_read` 就必须实现 `db_for_write`。** 二者必须成对出现，否则每一次"读出来改一下再存"都会变成一次静默的错写。`manage.py check` 抓不到这个 —— 它语法完全合法。

### 2.3 三个解法，以及各自的失效边界

#### 方案 A：关键路径显式读主

```python
Article.objects.using("default").get(pk=pk)
```

实测（实验 17）：

```
✅ 写后立刻 using('default') 能读到      实际=1
✅ 默认读（走从库）读不到                 实际=0
```

**优点**：零成本、零魔法、行为完全可预测。
**代价**：读主就是放弃读扩展，主库压力回不去。

**适用**：刚写完立刻要读的场景 —— 创建后跳转详情、支付后立即查状态、任何"用户刚操作完就要看到结果"的路径。

#### 方案 B：写入后钉住主库（thread-local）

思路：写操作发生后，在**当前线程**内的一小段时间里，把读也钉在主库上。

```python
import threading, time

class PinRouter:
    def __init__(self, pin_seconds=1.0):
        self.pin_seconds = pin_seconds
        self._local = threading.local()      # ← 必须线程隔离

    def db_for_write(self, model, **hints):
        self._local.last_write = time.monotonic()
        return "default"

    def db_for_read(self, model, **hints):
        last = getattr(self._local, "last_write", None)
        if last is not None and (time.monotonic() - last) < self.pin_seconds:
            return "default"
        return "replica"
```

实测（实验 18）：

```
钉住窗口内 db_for_read →                  default
✅ 窗口内读主（钉住生效）                   实际='default'
等待 1.0 秒让窗口过期……
窗口过后 db_for_read →                   replica
✅ 窗口过后回落到从库                      实际='replica'
```

**关键实现细节**：必须是 `threading.local`。写在一个普通实例属性上，多线程下会互相污染 —— A 线程的写会把 B 线程的读也钉住（或反过来）。Web 服务器是多线程的，这个 bug 只在并发下才出现，本地测不出来。

**失效边界**（实验 19）：

```
模拟复制延迟 0.5 秒 > 窗口 0.2 秒
窗口已过，读回落到                        replica
✅ 窗口过后读从库                         实际='replica'
```

**延迟超过窗口，方案 B 就失效**。而窗口大小是拍脑袋定的 —— 定大了浪费读扩展能力，定小了挡不住延迟。

#### 方案 C：延迟感知（等从库追上再读）

思路：不猜时间，而是**主动询问**从库复制到哪了。

```python
def wait_for_replica(primary_lsn, timeout=1.0):
    """等从库追上主库的位点；超时则回落到读主库。"""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        lsn = query_replica("SELECT pg_last_wal_replay_lsn()")
        if lsn >= primary_lsn:
            return True          # 追上了，可以安全读从库
        time.sleep(0.01)
    return False                 # 超时，回落到读主库
```

PostgreSQL 上要用的三个函数：

```sql
SELECT pg_current_wal_lsn();        -- 主库：当前写入位点
SELECT pg_last_wal_replay_lsn();    -- 从库：已重放到的位点
SELECT pg_wal_lsn_diff(a, b);       -- 两点之间的差距（字节）
```

> ⚠️ **诚实标注**：这一段是**方案说明，不是实测**。本机没有 PostgreSQL 主从复制环境，跑不出真实位点。我在实验 20 里用"从库条数 < 主库条数"模拟了位点落后的**判定逻辑**并验证通过：
>
> ```
> ✅ 写入后从库确实落后          实际=False  期望=False
> ✅ 未追上则回落主库            实际='default'
> ✅ 追上后读从库               实际='replica'
> ```
>
> 但**真实的 LSN 查询部分请务必在自己的 PG 环境上验证** —— 这跟课 11、12 反复出现的教训是同一条：凡是锁、性能、复制的结论，必须在生产同类型的库上验证。

#### 三个方案怎么选

| 方案 | 一致性 | 读扩展 | 实现成本 | 适用 |
|------|--------|--------|---------|------|
| **A 读主** | 强一致 | ❌ 无（压力回主） | 最低 | 写后立刻读的关键路径 |
| **B 钉住窗口** | 窗口内一致 | 部分 | 中（thread-local） | 中等一致性要求，延迟可控 |
| **C 等位点** | 追上即一致 | 大部分保留 | 高（需查 LSN） | 高一致性要求 + 要保住读扩展 |

> 💡 **实用建议**：不要指望一个方案打天下。真实项目几乎都是**混合**的 —— 默认读从库（要扩展），少数关键路径显式读主（要正确）。方案 A 的性价比远高于它的"笨"，先用它把关键路径守住，再考虑要不要上 B 或 C。

### 2.4 兜底：明白 `instance._state.db` 是怎么参与决策的

理解这条链，你就能自己推导任何路由行为（实验 21 实测）：

```
db_for_read / db_for_write
   ├─ 依次询问每个路由器
   │    └─ 第一个返回非 None 的胜出
   ├─ 全都不表态？→ 看 hints["instance"]._state.db（粘性）
   └─ 也没有？   → default
```

```
✅ 无路由 → default                    实际='default'
✅ 回落到对象所在库                      实际='replica'
   ↑ 对象保存在 replica，带 instance hint 的 db_for_write 就返回 replica
```

**粘性不是 bug，是特性** —— 它保证了"从哪读的就写回哪"，在**按 app 分库**的场景里这正是你想要的。它只在**主从**场景里才是坑，因为从库不该被写。

---

## 第三幕：多库的硬约束 —— 哪些单库默认行为被禁掉了

> 🗺️ **本幕路线图**：单库下"外键随便建""事务包住就安全""migrate 一次搞定"这三条常识，多库下全部失效。本幕逐个验证：

| # | 问题 | 一句话结论 | 实验 |
|---|------|-----------|------|
| 3.1 | 跨库外键为什么建不起来？ | 赋值即 `ValueError`，根源是参照完整性无法跨库校验 | 7、8 |
| 3.2 | `db_constraint=False` 能救吗？ | 只管 DDL，管不了运行时 `allow_relation` | 22 |
| 3.3 | 那它是安全的吗？ | ❌ 也可能**静默指向错误的数据**，本课最危险的一条 | 9 |
| 3.4 | 该用什么替代？ | 普通整数字段存 ID + 手动两步查 | 9 |
| 3.5 | `atomic` 能跨库吗？ | ❌ `using` 是单数，只管一个库 | 14 |
| 3.6 | 多库怎么迁移？ | 一次只管一个库，`allow_migrate` 决定谁在哪建表 | 10–16 |
| 3.7 | `check` 能帮我抓出什么？ | 能抓重名表，抓不出延迟/漏迁移/缺 `db_for_write` | 23、24 |
| 3.8 | 多库连接数怎么算？ | 每库各有一份池，总连接数 = Σ(max_size) × 进程数 | 串联课 12 |

### 3.1 跨库外键：赋值即报错

官方文档明示（`Limitations of multiple databases` → `Cross-database relations`）：

> "Django doesn't currently provide any support for foreign key or many-to-many relationships spanning multiple databases. If you have used a router to partition models to different databases, any foreign key and many-to-many relationships defined by those models must be internal to a single database. **This is because of referential integrity.**"

原因是参照完整性：Django 需要确认"被引用的主键是有效的"，而主键在另一个库时无法校验。

实测（实验 7），把 `Ticket` 路由到 logs 库、给它赋一个 default 库的 `Article`：

```
Article 落在                        default
✅ 抛出 ValueError：Cannot assign "<Article: Article object (8)>": the current database router prevents this relation.
赋值失败后 Ticket._state.db =         logs
↑ 注意：即使赋值失败，_state.db 已经被路由器就地改写了
```

报错来自 `related_descriptors.py:325-330`。**两处细节值得注意**：

1. **报错是 `ValueError` 不是 `ValidationError`** —— 它不在 Django 的校验体系内，`full_clean()` 不会碰它，只能在赋值那一刻捕获。
2. **赋值失败但 `_state.db` 已经被改写了**。源码里先调 `db_for_write` 设置 `_state.db`，再调 `allow_relation` 校验。所以对象在异常后已经"沾上"了错误的库，别拿它继续用。

M2M 和反向 `add()` 走的是**另一条代码路径**，报错原文也不同（实验 8）：

```
✅ 抛出 ValueError：Cannot add "<Article: Article object (12)>": instance is on database "logs", value is on database "default"
```

来自 `related_descriptors.py:1506-1510`。**记住这两条报错文案**，线上看到就能立刻定位到是路由问题。

`allow_relation` 的三种返回值对照（实验 7）：

| 返回值 | 实测结果 |
|--------|---------|
| `None`（不表态） | 走默认规则：**只允同库** |
| `True` | 跨库也放行 |
| `False` | **连同库也拦**（实测：同库赋值同样报 `Cannot assign`） |

### 3.2 社区流传的"跨库 FK 三件套"，实测只解决一半

搜"django cross database foreignkey"，高频出现的方案是：

```python
models.ForeignKey(Target, on_delete=models.DO_NOTHING, db_constraint=False, null=True)
# 再配 router.allow_relation() 返回 True
```

**实测结论：这两件事是独立的两道关卡，`db_constraint=False` 只管第一道。**

`db_constraint=False` 的作用**只在 DDL 层** —— 让迁移时不生成 `FOREIGN KEY` 约束（否则在只有一个库有目标表时会报 `relation does not exist`）。它**管不了运行时的 `allow_relation` 校验**。

实测（实验 22）：

```
—— 只加 db_constraint=False，不改 allow_relation ——
✅ 仍然报错：Cannot assign "<Article: Article object (47)>": the current database router prevents this relation.
   ↑ 结论：db_constraint=False 只影响 DDL，管不了运行时的 allow_relation 校验

—— 再加上 allow_relation 返回 True ——
赋值结果                        成功，article_id=47
✅ allow_relation=True 后赋值通过   实际=47
```

**两道关卡的完整关系**：

| 关卡 | 谁管 | 失败表现 |
|------|------|---------|
| ① DDL 层：目标库有没有这张表、要不要建 FK 约束 | `db_constraint` | `migrate` 时报 `relation "xxx" does not exist` |
| ② 运行时：这关系允不允许 | `allow_relation` | 赋值时报 `Cannot assign ...` |

**三件套确实能让赋值通过，但代价是四样东西**（这是社区文章很少讲的部分）：

1. **数据库层没有外键约束** → 悬空引用不会被拦截
2. **没有级联删除** → 主表删了，从表残留（`on_delete=DO_NOTHING` 更是直接放弃）
3. **`select_related` 跨库 JOIN 不可用** → 两个库物理上连不上，JOIN 无从谈起
4. **读到的是"另一份数据"** → 下面这条最危险

第 4 条是我在实验 9 里**意外撞出来**的，值得单独说。

### 3.3 一个意外发现：跨库 FK 会在"错误的库"上校验约束

实验 9 本来想验证"用普通整数字段存 ID"这个替代方案，结果先撞上了一个 `IntegrityError`：

```
—— 方案 C：Ticket 被路由到 logs，与主库跨库 ——
Article 落在                     default
✅ 抛出 IntegrityError: FOREIGN KEY constraint failed
   ↑ 关键：Ticket 在 logs 库，但它的 FK 约束指向的是 logs 库自己的
     shop_article 表 —— 那里根本没有 article 记录，于是约束失败。
```

**这是怎么发生的**：`Ticket` 被路由到 logs 库，而 logs 库里也有一张 `shop_article` 表（我们给三个库都 migrate 过）。于是外键约束指向的是** logs 库自己的那张 `shop_article`**，而不是主库的那张。绕过描述符直接写 `article_id` 时，`allow_relation` 不参与，约束就在这个错误的库上被校验了。

**然后是最危险的一步**（实验 9 后半段）：

```
—— 那么「先建表再删记录」呢？把 logs 库的 article 也建一份——
Article.objects.using("logs").create(pk=art.pk, title="从库的同 pk 记录")
✅ 从库有同 pk 记录时可以写入       实际=39  期望=39
   ↑ 这恰恰是最危险的情况：写进去了，但引用的是另一份数据
     两份 article 内容可以完全不同，业务上完全错误，数据库却不报错
```

**写入成功了。** 主库的 `article #39` 是一篇文章，logs 库的 `article #39` 是另一篇内容完全不同的文章。你的 `ticket.article_id = 39` 在 logs 库里有合法的引用目标，约束通过，业务逻辑却完全错了。

> 🚨 **这是本课最应该记住的一条**：跨库 FK 不是"会报错所以安全"，而是**要么报错、要么静默指向错误的数据**。而后者不会有任何异常。
>
> 课 11 讲过 `select_for_update` 在 SQLite 上静默失效，课 12 讲过 `pool={}` 静默失效、MySQL 对 `condition` 静默忽略 —— **这是同一类问题的第四次出现**。凡是"不报错的错误"，都要拉出来单独讲。

### 3.4 跨库引用的正确做法

既然 FK 不能用，那用什么？实测对照（实验 9）：

| 方案 | 赋值 | `select_related` | 级联 | DB 级引用完整性 |
|------|------|-----------------|------|----------------|
| **跨库 `ForeignKey`** | ❌ `ValueError` | ❌ | ❌ | ❌（约束在错库上） |
| **普通整数字段存 ID** | ✅ | ❌ 需手动两步查 | ❌ 需自己实现 | ❌ 不存在的 ID 也能存 |

推荐写法：

```python
class Ticket(models.Model):
    code = models.CharField(max_length=32)
    # 不用 ForeignKey，存 ID 即可
    ref_article_id = models.IntegerField(null=True, blank=True, db_index=True)

    def get_article(self):
        """手动跨库查询：两步，且必须显式指定 using。"""
        if self.ref_article_id is None:
            return None
        return Article.objects.using("default").filter(pk=self.ref_article_id).first()
```

接受这四样失去的能力，并**用代码补偿**：

- **悬空引用** → 定时任务扫描清理，或读取时判空
- **级联删除** → 删主表记录时，显式写一段去清理从库的引用
- **JOIN** → 两步查 + 手动拼装（无法避免）
- **引用完整性** → 应用层校验，或干脆接受最终一致

### 3.5 跨库事务：`atomic` 只管一个库

> 📌 **这就是开场「决定三」的答案**：下单写了业务库和审计库，`@transaction.atomic` 包住了，对账却发现业务库有记录、审计库没有。下面是原因。

这是开场"决定三"的成因。官方文档在示例中明确说了它 "doesn't consider the interaction of transactions with the database utilization strategy"。

实测（实验 14），三个场景对照：

**场景 A：内层异常向外传播** —— 反而是对的

```
✅ logs 库回滚了                      实际=0
✅ default 库也回滚了（异常传播到外层）   实际=0
   ↑ 注意这是异常传播的效果，不是 atomic 跨库了
```

**场景 B：内层异常被 `except` 吞掉** —— 真正的坑

```python
with transaction.atomic(using="default"):
    Article.objects.using("default").create(...)
    try:
        with transaction.atomic(using="logs"):
            AuditLog.objects.using("logs").create(...)
            raise RuntimeError("审计写入失败")
    except RuntimeError:
        pass          # ← 吞掉了
```

```
✅ logs 库回滚了                        实际=0
✅ 【跨库不一致】default 库的写入提交了     实际=1
   ↑ 两个库从此不一致：主库有这笔业务，审计库没有它的记录
```

**场景 C：只在 default 上 `atomic`，却写了 logs 库**

```
✅ default 回滚了                      实际=0
✅ 【跨库不回滚】logs 库的写入留下了        实际=1
   ↑ atomic 不带 using 时只管 default，另一个库根本没被它管
```

**结论**：`transaction.atomic(using=...)` 中的 `using` 是**单数**。它只作用于那一个连接。两个库要一起回滚，只有两条路：

1. **让异常一路传播**（场景 A 的效果）—— 最省事，但前提是所有写操作都在 `atomic` 块内且没人吞异常。
2. **接受最终一致** —— 用 outbox 模式、补偿任务、对账任务来保证最终收敛。这是分布式系统里唯一现实的做法。

> ⚠️ **不要试图用两阶段提交（2PC）解决**。Django 没有内置支持，而 2PC 的协调成本和故障模式远比它解决的问题复杂。

### 3.6 多库迁移：`migrate` 一次只管一个库

**`migrate` 没有"一键多库"**（官方文档："The migrate management command operates on one database at a time"）：

```bash
python manage.py migrate                      # → default
python manage.py migrate --database=replica   # → replica
python manage.py migrate --database=logs      # → logs
```

实测（实验 16）：

```
migrate --database=default 后该库业务表   ['logs_auditlog', 'shop_article', 'shop_author', ...]
migrate --database=replica 后该库业务表   ['logs_auditlog', 'shop_article', 'shop_author', ...]
migrate --database=logs    后该库业务表   ['logs_auditlog', 'shop_article', 'shop_author', ...]
```

**注意上面三行是一样的** —— 因为没配 `allow_migrate`，每个库都建了**全套表**。这就是实验 10 说的"污染"：

```
✅ 【污染】replica 也建了 shop_article     实际=True
✅ 【污染】replica 也建了 logs_auditlog    实际=True
```

在**主从**架构里这没问题（真实主从靠复制同步，从库本来就该有全套表）。但在**按 app 分库**里这是错的 —— 你不想在审计库里建业务表。

#### `allow_migrate` 的三种返回值（实验 11、12）

| 返回值 | 语义 | 实测 |
|--------|------|------|
| `True` | 该 model 在这个库上建表 | `allow_migrate('default','shop')` → `True` |
| `False` | 跳过（**静默**，不报错） | `allow_migrate('logs','shop')` → `False` |
| `None` | 不表态 → **最终回落 `True`** | 见下方危险案例 |

按 app 分库的标准写法（官方文档示例的简化版，实验 15 实测）：

```python
class AppSplitRouter:
    def db_for_read(self, model, **hints):
        if model._meta.app_label == "logs":
            return "logs"
        return "default"

    def db_for_write(self, model, **hints):
        if model._meta.app_label == "logs":
            return "logs"
        return "default"

    def allow_relation(self, obj1, obj2, **hints):
        return obj1._meta.app_label == obj2._meta.app_label

    def allow_migrate(self, db, app_label, **hints):
        if app_label == "logs":
            return db == "logs"
        return db == DEFAULT_DB_ALIAS
```

实测（实验 15）：

```
Article.save() 落在            default
AuditLog.save() 落在           logs
✅ 业务表写 default              实际='default'
✅ 审计表写 logs                 实际='logs'
✅ shop 只在 default 建表         实际=True
✅ shop 不在 logs 建表           实际=False
✅ logs 只在 logs 建表           实际=True
```

### 3.6.1 🚨 这个示例的 `allow_relation` 会让你的项目炸掉

上面示例里这一行**不能直接抄到真实项目**：

```python
def allow_relation(self, obj1, obj2, **hints):
    return obj1._meta.app_label == obj2._meta.app_label   # ← 危险
```

它的含义是**跨 app 的外键一律禁止**。而真实项目里，业务模型几乎必然要外键指向 `auth.User`（课 2 的自定义用户模型、课 8 的 JWT 都依赖它）。于是——

实测（实验 25）：

```
【场景 1】Article.author → Author（同为 shop app）
✅ 同 app 放行                                实际=True

【场景 2】业务表外键指向 auth.User（真实项目高频场景）
User 的 app_label =                        auth
Article 的 app_label =                     shop
✅ 【P0 坐实】跨 app 外键被拦                   实际=False
✅ 抛出 ValueError：Cannot assign "<User: u1>": the current database router prevents this relation.
```

**`note.owner = request.user` 会直接抛 `ValueError`。** 而且是在运行时、在用户操作的那一刻 —— 不是启动时，`manage.py check` 也抓不到。

**修正版**：放行 `auth` 与 `contenttypes`（这也是官方文档把 `AuthRouter` 单独拆出来的真实原因）：

```python
class FixedAppSplitRouter(AppSplitRouter):
    """放行 auth / contenttypes，其余按 app 判定。"""

    cross_app_allowed = {"auth", "contenttypes"}

    def allow_relation(self, obj1, obj2, **hints):
        labels = {obj1._meta.app_label, obj2._meta.app_label}
        if labels & self.cross_app_allowed:      # 涉及 auth/contenttypes 的，一律放行
            return True
        return obj1._meta.app_label == obj2._meta.app_label
```

实测：

```
✅ 修正后跨 app 外键放行                      实际=True
✅ 同 app 仍然放行                           实际=True
```

**放行 `auth` 会不会破坏分库目标？** 不会。实测（实验 25 场景 4）：

```
db_for_read(User) =                        default
allow_migrate('default','auth') =          True
allow_migrate('logs','auth') =             False
✅ auth 表仍在 default（不受 allow_relation 影响）  实际='default'
✅ auth 不在 logs 建表                       实际=False
```

关键认知：**`allow_relation` 只决定"关系允不允许"，不决定"表建在哪个库"。** 后者由 `db_for_read/write` 和 `allow_migrate` 管。放行 `auth` 的关系，不会把 `auth_user` 表搬到别处去。

> 🚨 **`allow_migrate` 返回 `None` 的危险案例**（实验 12 实测）：
>
> ```python
> class SilentOnLogsRouter:
>     def allow_migrate(self, db, app_label, **hints):
>         if app_label == "logs":
>             return db == "logs"
>         return None          # ← 本意是"其他 app 我不管"
> ```
>
> ```
> ✅ None 回落到 True                       实际=True
> ✅ replica 上的 shop 也被放行（危险）        实际=True
> ✅ logs 在 default 被拦                   实际=False
> ```
>
> 结果：`shop` 的表在**每一个库**上都被建出来了。你的"我不管"被翻译成了"全都允许"。

#### `makemigrations` 的一致性检查：不配路由就不查非默认库

官方文档原文："When `makemigrations` verifies the migration history, it skips databases where no app is allowed to migrate."

源码佐证（`makemigrations.py:146-148`）：

```python
aliases_to_check = (
    connections if settings.DATABASE_ROUTERS else [DEFAULT_DB_ALIAS]
)
```

实测（实验 13）：

```
无路由时检查的库          ['default']
   → 非默认库的迁移历史不一致，根本不会被发现
配了路由后检查的库        ['default', 'logs', 'replica']
   → 一旦配了 DATABASE_ROUTERS，所有库都进入一致性检查
```

**含义**：配了路由之后，`makemigrations` 会去检查**每一个**库的迁移历史。这既是好事（能抓出不一致），也是新的失败点（某个库漏 migrate 了，`makemigrations` 会直接报 `InconsistentMigrationHistory`）。

### 3.8 多库下的连接数怎么算（串联课 12）

课 12 讲过连接池的两条硬结论：**池是按进程计算的**，容量公式是：

```
单个库的连接数 = max_size × 进程数
```

多库下要再乘一层：**每个库别名各有一份独立的连接池**。

```
总连接数 = Σ(每个库的 max_size) × 进程数
```

举例：4 个 gunicorn worker，配置 `default`、`replica`、`logs` 三个库，`max_size` 都是 10：

```
总连接数 = (10 + 10 + 10) × 4 = 120 条
```

**而 PostgreSQL 默认 `max_connections = 100`。** 这个配置直接超限。

注意几个容易算错的地方：

- **从库也要算**。读从库的请求同样要建连接，`replica` 的池不是免费的。
- **`max_size` 是每库单独配的**，没配的库回落到 min_size（课 12 实测为 4，不可依赖）。
- **预留量要按总连接数算**，不是按单库算。课 12 给的判据 `max_size ≤ (max_connections − 预留) ÷ 总进程数`，多库下要把 `max_connections − 预留` 这个**总额度**再按库数量分摊。

> 💡 **实践建议**：多库场景下，与其给每个库都配 `max_size=10`，不如先按读写比例分配额度 —— 读多写少时，`replica` 可以给大一些，`default` 和 `logs` 给小一些。总盘子守住 `max_connections` 的 70%（课 12 的判据），超了就上 PgBouncer。

### 3.9 系统检查能帮你到什么程度

好消息：跨库重名表，Django 能查出来，而且**配不配路由器，级别不同**（实验 23 实测）：

```
无 DATABASE_ROUTERS 时的检查项     [('models.E028', 'Error')]
   消息: db_table 'legacy_user' is used by multiple models: shop.LegacyUser, shop.LegacyUserShadow.
   hint: None

有 DATABASE_ROUTERS 时的检查项     [('models.W035', 'Warning')]
   消息: db_table 'legacy_user' is used by multiple models: shop.LegacyUser, shop.LegacyUserShadow.
   hint: You have configured settings.DATABASE_ROUTERS. Verify that shop.LegacyUser, shop.LegacyUserShadow are correctly routed to separate databases.
```

源码（`model_checks.py:41-48`）：

```python
if settings.DATABASE_ROUTERS:
    error_class, error_id = Warning, "models.W035"
    error_hint = "You have configured settings.DATABASE_ROUTERS. Verify that %s are correctly routed to separate databases."
else:
    error_class, error_id = Error, "models.E028"
    error_hint = None
```

**含义**：配了路由后，Django 认为"两个模型在不同库上各有一份同名表"是**合理设计**（比如主从各自一份），于是从 `Error` 降级为 `Warning`。但如果你其实是在**同一个库**上撞名，那仍然是错误 —— Django 只是不再替你判定了。

> ⚠️ **一个坑（我踩过）**：这个检查**只覆盖 `managed=True` 且非 proxy 的模型**。源码 `model_checks.py:22`：`if model._meta.managed and not model._meta.proxy`。我最初把两个演示模型都设成 `managed=False`，检查一项都没报 —— 查源码才发现被过滤掉了。

坏消息：`manage.py check` **抓不出**下面这些（实验 24 实测）：

| 问题 | check 能否发现 | 说明 |
|------|--------------|------|
| 主从延迟导致的写后读不一致 | ❌ | check 完全不知道"复制"这回事 |
| 忘了 `migrate` 某个库 | ❌ | check 不检查表是否真的存在 |
| 只写 `db_for_read` 不写 `db_for_write` | ❌ | 语法完全合法，语义是错的 |
| `allow_migrate` 返回 `None` 的静默放行 | ❌ | 与显式 `True` 结果相同 |
| 跨库外键指向了错误的数据 | ❌ | 见 3.3，数据库也不报错 |

**这五项只能靠设计约束和代码评审来防。**下面是我的检查清单。

---

## 回到开场三个决定

**决定一**（配了主从，用户说"刚发的文章没了"）：写后读不一致。解法不是"再等等"，而是**区分关键路径**：默认读从库保扩展，写后立刻读的路径显式 `using("default")`。方案 B/C 是进阶选项，别一上来就上。

**决定二**（审计库的外键建不起来）：跨库外键被禁，原因是参照完整性无法跨库校验。别去试 `db_constraint=False` 那套三件套 —— 它只解决 DDL 那一关，运行时仍要 `allow_relation` 放行，而放行之后你会失去引用完整性、级联、JOIN，还可能**静默指向错误的数据**。改用普通整数字段存 ID，自己两步查，并写清补偿逻辑。

**决定三**（`atomic` 包住了，对账还是不平）：`atomic(using=...)` 的 `using` 是单数。它只管一个连接，另一个库根本没被它管。两条路：让异常一路传播（前提是所有写都在块内且没人吞异常），或者接受最终一致 + 对账补偿。

**贯穿三幕的同一类陷阱**：这是本课程**第四次**遇到"不报错的错误"——课 11 的 `select_for_update` 静默失效、课 12 的 `pool={}` 静默失效与 MySQL 对 `condition` 静默忽略、本课的"跨库 FK 指向错误数据"与"只写 `db_for_read` 导致写入只读库"。它们的共同点：**语法合法、不抛异常、只在特定条件下才暴露**。

**另外两条需要单独记住**（不属于上面那条线索，但同样容易漏）：

- **按 app 分库时别照抄示例的 `allow_relation`** —— 它会连业务表指向 `auth.User` 的外键一起禁掉。真实项目必须放行 `auth` / `contenttypes`（3.6.1，实验 25）。
- **多库会让连接数翻倍** —— 每个库各有一份连接池，总连接数要按 `Σ(max_size) × 进程数` 算（3.8，串联课 12）。

---

## 决策清单

### 先走这条路径：渐进式上多库

不要一次性把多库全套搬上去。按下面的顺序推进，每步都能独立验证、独立回滚：

| 阶段 | 做什么 | 验证什么 | 做不到就停在这 |
|------|--------|---------|--------------|
| ① 单库优化 | 索引（课 12）、N+1（课 15）、缓存（课 16） | 慢查询是否消失、CPU 是否降下来 | **绝大多数项目停在这一步就够了** |
| ② 主从读扩展 | 加从库 + 主从路由；**关键路径显式读主** | 主库压力是否下降、有没有"刚写完读不到"的投诉 | 读写比不够高就不必做 |
| ③ 延迟治理 | 按需引入钉住窗口（方案 B）或等位点（方案 C） | 复制延迟监控 + 不一致投诉归零 | 延迟可接受就别加复杂度 |
| ④ 按 app 分库 | 引入 `allow_migrate` 做数据隔离 | 每个库只有它该有的表 | 没有独立扩容/合规需求就不做 |
| ⑤ 跨库引用 | 一律用整数字段 + 手动两步查 | 有没有残留的跨库 FK | — |

**判断该不该继续往下走的参考指标**（业界经验值，**非 Django 官方建议**，请按自己的业务压测）：

| 指标 | 经验参考 | 说明 |
|------|---------|------|
| 数据库 CPU | 长期 > 70% | 且慢查询已优化完，才说明是容量问题 |
| 读写比 | > 10:1 | 低于这个，主从收益有限 |
| 连接数 | 接近 `max_connections` 的 70% | 先算课 12 + 本课的公式 |
| 单表数据量 | 千万级以上且增长快 | 才考虑拆库/分区，而非主从 |

> ⚠️ 这些数字是**经验参考不是阈值**。本课坚持一条原则：不给出未经实测的数字。真实阈值取决于你的硬件、查询模式与业务容忍度，必须自己压测。

### 要不要上多库？（先问这个，90% 的项目答案是不需要）

- 单库有没有真的到瓶颈？先做索引、查询、缓存优化（课 12、15、16）
- 读写比是多少？读多写少才值得做主从
- 能否接受最终一致？不能接受就别做主从
- 团队有没有能力维护路由 + 迁移 + 对账？

**配路由时**

- `db_for_read` 与 `db_for_write` **必须成对实现**
- `allow_migrate` 管完自己的 app 后，其余情况**必须显式返回**，不能留 `None`
- 路由器列表**从具体到宽泛**排序
- `allow_relation` 返回 `None` = 只允许同库关系（与 `allow_migrate` 相反！）

**写代码时**

- 写后立刻读的路径 → `using("default")`
- 跨库引用 → 普通整数字段 + 手动两步查，不要用 FK
- 跨库写 → 别指望 `atomic`，要么让异常传播，要么上补偿
- deploy 脚本 → `migrate` 必须对**每个库**各跑一次

---

## 高频误区

| 误区 | 真相 | 实验 |
|------|------|------|
| "配了主从，写主读从就完事" | 复制延迟会导致刚写完读不到，需按场景手动路由回主库 | 4 |
| "只写 `db_for_read` 就够了，写本来走 default" | 写入会回落 `instance._state.db`，把写操作送进只读库 | 5 |
| "`db_constraint=False` 能让跨库 FK 用起来" | 它只管 DDL。运行时仍要 `allow_relation` 放行，且会失去引用完整性 | 22 |
| "跨库 FK 会报错所以是安全的" | 也可能**静默指向另一份数据**，业务全错而数据库不报错 | 9 |
| "`@transaction.atomic` 包住就安全了" | `using` 是单数，只管一个库；异常被吞则不回滚 | 14 |
| "`allow_migrate` 返回 `None` = 我不表态" | 等于**一律放行**，所有库都会建这套表 | 12 |
| "`allow_relation` 返回 `None` = 只允同库，所以按 app 分库时写 `app_label` 相等就行" | 会连 `auth.User` 的外键一起禁掉，运行时抛 `ValueError` | 25 |
| "`migrate` 会把所有库都迁好" | 一次只管一个库，必须逐个 `--database` 执行 | 16 |
| "多库下 `max_size=10` 还是 10 条连接" | 每库各有一份池，总连接数 = Σ(max_size) × 进程数，三库四进程就是 120 条 | 3.8 |
| "两个模型同名表是硬错误" | 配了 `DATABASE_ROUTERS` 会降级为 `Warning`（W035） | 23 |
| "`manage.py check` 能抓出路由配置问题" | 抓不出延迟、漏迁移、缺 `db_for_write`、`None` 放行这四类 | 24 |

---

## 自检题

1. 一个只实现了 `db_for_read`（返回 `"replica"`）的路由器，对 `obj = Article.objects.get(pk=1); obj.save()` 会产生什么后果？为什么？
2. `allow_relation` 返回 `None` 和 `allow_migrate` 返回 `None`，兜底行为有什么不同？分别是什么？
3. 写入主库后立刻从从库读，读不到。列出三种解法，并说明各自在什么情况下会失效。
4. 为什么 Django 禁止跨库外键？根本原因是什么（不是"因为官方这么说"）？
5. `db_constraint=False` 能解决跨库外键的什么问题？不能解决什么问题？
6. 下面这段代码，两个库最终各是什么状态？为什么？
   ```python
   with transaction.atomic(using="default"):
       A.objects.using("default").create(...)
       try:
           with transaction.atomic(using="logs"):
               B.objects.using("logs").create(...)
               raise RuntimeError("x")
       except RuntimeError:
           pass
   ```
7. 按 app 分库时，`allow_migrate` 只对目标 app 显式返回、其余返回 `None`，会发生什么？
8. 为什么配了 `DATABASE_ROUTERS` 之后，`makemigrations` 会开始报 `InconsistentMigrationHistory`？
9. 抄了本课的 `AppSplitRouter` 示例后，`note.owner = request.user` 抛了 `ValueError`。原因是什么？放行 `auth` 之后，会不会把 `auth_user` 表搬到别的库去？
10. 4 个 gunicorn worker，`default`/`replica`/`logs` 三个库都配了 `max_size=10`。PostgreSQL 默认 `max_connections=100`，这个配置有什么问题？

<details>
<summary>参考答案</summary>

1. **写入落到 replica（只读库）**。因为该路由器没有 `db_for_write`，不表态，于是 `ConnectionRouter` 走粘性兜底 `instance._state.db`，而对象正是从 replica 读出来的。主库不会被更新，且这次修改会被下一次主从复制覆盖。实验 5。

2. **`allow_relation` 返回 `None` 的兜底是"只允同库"（`obj1._state.db == obj2._state.db`）；`allow_migrate` 返回 `None` 的兜底是"一律放行 `True`"。** 二者完全相反。`utils.py:253` vs `utils.py:268`。

3. **A 显式读主**：代价是放弃读扩展；**B 钉住窗口**：延迟超过窗口就失效；**C 等复制位点**：实现复杂、需查 LSN，且超时后仍要回落读主。实验 17–20。

4. **参照完整性**。Django 需要确认被引用对象的主键是有效的，而主键存放在另一个数据库时无法校验。`allow_relation` 就是为此存在的运行时校验关卡。

5. **能解决**：迁移时不会在目标库生成 `FOREIGN KEY` 约束（避免 `relation does not exist`）。**不能解决**：运行时的 `allow_relation` 校验 —— 那是完全独立的另一道关卡，仍需返回 `True` 才放行。实验 22。

6. **default 有记录，logs 没有。** 内层 `atomic` 回滚了 logs，异常被 `except` 吞掉后不再传播，外层 `atomic` 正常提交。实验 14 场景 B。

7. **其余 app 的表会在每一个库上都建出来。** 因为 `allow_migrate` 返回 `None` 最终回落为 `True`。实验 12。

8. **因为 `makemigrations` 的检查范围从"只查 default"变成了"查所有库"**（源码 `makemigrations.py:146-148`：`connections if settings.DATABASE_ROUTERS else [DEFAULT_DB_ALIAS]`）。某个库漏跑了 `migrate`，历史不一致就被暴露出来了。实验 13。

9. **原因**：示例的 `allow_relation` 写的是 `obj1._meta.app_label == obj2._meta.app_label`，对跨 app 外键一律返回 `False`，而 `auth.User` 的 `app_label` 是 `auth`、业务模型是 `shop`，于是被拦。**放行 `auth` 不会把表搬走** —— `allow_relation` 只决定"关系允不允许"，"表建在哪个库"由 `db_for_read/write` 与 `allow_migrate` 决定。实验 25。

10. **总连接数 = (10+10+10) × 4 = 120 条，超过 `max_connections=100` 的默认上限。** 每个库别名各有一份独立连接池，从库的池也不是免费的。要么按读写比例重新分配 `max_size`（读多则 `replica` 给大、`default`/`logs` 给小），要么上 PgBouncer。见 3.8（串联课 12）。

</details>

---

## 怎么确认你真的会用（三个动手动作）

自检题检验的是"读懂了"。下面三个动作检验的是"会用了" —— **都可以在 SQLite 上立刻完成，不需要 PostgreSQL**。

**动作一：亲手制造一次"写进只读库"**

配一个只有 `db_for_read` 的路由器（本课示例 `ReadOnlyReplicaRouter`），然后：

```python
obj = Article.objects.get(pk=1)
obj.title = "改过的标题"
obj.save()
print(obj._state.db)          # 你预期是什么？实际是什么？
```

再用 sqlite 客户端分别打开两个库文件，对比这条记录的标题。**看到了"主库没变、从库变了"，你就真正理解了粘性兜底。**

**动作二：确认两个钩子都按预期返回**

```python
from django.db import router
from shop.models import Article

print(router.db_for_read(Article))     # 你预期 'replica'
print(router.db_for_write(Article))    # 你预期 'default' —— 真的吗？
```

如果第二个打印出来是 `replica`，说明你只实现了 `db_for_read`。**这行检查值得写进项目的启动自检里。**

**动作三：在代码库里搜跨库外键**

用本课的两条报错文案去搜你的代码和 issue 记录：

```
Cannot assign "..." : the current database router prevents this relation.
Cannot add "...": instance is on database "...", value is on database "..."
```

搜不到不代表安全 —— **静默指向错误数据的那种不会报错**。所以再手工过一遍：所有模型的 `ForeignKey` / `ManyToManyField`，它指向的模型**和自己在同一个库吗**？

---

## 本课核心结论

> **路由决定去向，复制决定新鲜度，事务只管一个库。**
>
> 四个钩子里，`allow_relation` 与 `allow_migrate` 的 `None` 兜底行为**完全相反**（一个只允同库、一个一律放行）。只实现 `db_for_read` 不实现 `db_for_write`，写操作会被粘性规则送进只读库 —— 不报错。跨库外键要么在赋值时报错、要么**静默指向错误的数据** —— 后者才是真危险。`transaction.atomic` 的 `using` 是单数，跨库不回滚。

**下一课**：[课 14 迁移工程](../overview.md) —— 数据迁移为什么必须用 `apps.get_model` 拿历史模型、`RunSQL` 与 `SeparateDatabaseAndState` 怎么让状态与数据库解耦、给已有表加唯一字段的三步走。

---

## 事实核查说明

本课结论分三类，已逐条标注来源：

**官方文档明示**（[Multiple databases](https://docs.djangoproject.com/en/6.1/topics/db/multi-db/)）：
- 四个钩子的方法签名与返回值语义
- "If no router has an opinion (i.e. all routers return None), only relations within the same database are allowed"
- "A router doesn't have to provide all these methods"
- "The order in which routers are processed is significant"
- "The migrate management command operates on one database at a time"
- 跨库关系不受支持及参照完整性的原因
- 官方示例的免责声明（不处理复制延迟、不处理事务、跨库关系会坏）

**Django 6.1 源码**：
- `django/db/utils.py:224-238` 钩子遍历与粘性兜底；`:253` 与 `:268` 两个相反的 `None` 兜底
- `django/db/models/fields/related_descriptors.py:325-330` 与 `:1506-1510` 两条跨库报错
- `django/core/checks/model_checks.py:22` 只检查 managed 非 proxy；`:41-48` E028/W035 分级
- `django/core/management/commands/makemigrations.py:146-148` 一致性检查范围

**本课实测发现**（文档未明说，25 个实验坐实）：
- 只写 `db_for_read` 会把写操作送进只读库（机制 = 粘性兜底）
- 跨库 FK 会在**错误的库**上校验约束，且可能静默指向另一份数据
- `db_constraint=False` 只管 DDL，管不了运行时 `allow_relation`
- 赋值失败后 `_state.db` 已被就地改写
- 异常被吞时跨库不回滚（异常传播时反而都回滚）
- `allow_migrate` 返回 `None` 的静默放行危害
- `check_all_models` 只覆盖 `managed=True` 的模型
- **🆕 按 app 分库的 `allow_relation` 示例会禁掉指向 `auth.User` 的外键**（评审 P0，实验 25）；且放行 `auth` 不影响表的归属

**⚠️ 未经实测、需自行验证的部分**：
- 方案 C（延迟感知）的 PostgreSQL LSN 查询部分 —— 本机无 PG 主从环境，仅验证了"位点落后判定"的逻辑，真实 SQL 请在自己的 PG 环境上验证。
- 真实主从复制的延迟量级 —— 因数据库、配置、负载而异，本课不给出具体数字。

---

**课 13 完** ｜ 实验工程：`%TEMP%/dj-lesson13-demo/routelab` ｜ 25 个实验 / 85 项断言 / 零失败
