# 课 14《迁移工程：不依赖 model 的迁移》

> 🧭 所属阶段：[阶段 4 数据层纵深](../overview.md) ｜ 上一课：[课 13 多数据库与 DB 路由](./lesson-13-多数据库与DB路由.md) ｜ 下一课：阶段 5 性能与异步（课 15 ORM 进阶与 N+1 治理）
>
> 🎯 **本课回答三个问题**：为什么迁移里不能 import 模型？`RunSQL` 建的东西 Django 为什么"看不见"？给线上有数据的表加唯一字段，怎么做才不出事？
>
> ⚙️ **实跑环境**：Django **6.1** / Python **3.13.14**（Windows 托管 venv `dj-course`）。两个 SQLite 文件分别扮演 `default`（主库）与 `logs`（独立库）。
>
> 📦 实验工程：`%TEMP%/dj-lesson14-demo/miglab`，**33 个实验全部实测通过**（断言 120 项，零失败）。

#### 怎么跑起来

```bash
# 复用课 2 建的虚拟环境
# Windows: C:\Users\<你>\.workbuddy\binaries\python\envs\dj-course\Scripts\python.exe

cd %TEMP%/dj-lesson14-demo/miglab
set PYTHONPATH=<miglab绝对路径>/apps      # shop / logs 两个 app 在 apps/ 下
set PYTHONIOENCODING=utf-8                # 否则中文输出乱码

python run_lab1.py     # 实验 1-8  ：数据迁移与历史模型
python run_lab2.py     # 实验 9-16 ：RunSQL 与状态解耦
python run_lab3.py     # 实验 17-25：零停机变更与迁移治理
python run_lab4.py     # 实验 26-30：多库迁移与自定义 Operation
python run_lab5.py     # 实验 31-33：大表回填（评审 P0 验证）
```

> 💡 **不需要装 PostgreSQL**。历史模型、状态与数据库解耦、`atomic`、squash 这些**都是 Django Python 侧的逻辑**，SQLite 上完整可复现。真正只有 PostgreSQL 才有的部分（`CREATE INDEX CONCURRENTLY`）本课会明确标注为「方案说明 + 引用来源」，不假装跑过。

---

## 开场：三个"上线后才爆炸"的迁移

**迁移 A**（数据迁移）：半年前写的，把 `slug` 填成 `legacy-{id}`。今天新同事克隆仓库跑 `migrate`，**在第 7 个迁移处崩了**，报 `AttributeError: 'Article' object has no attribute 'legacy_tag'` —— 而 `legacy_tag` 上个月就被删了。

**迁移 B**（SQL 迁移）：用 `RunSQL` 建了个视图。之后每次跑 `makemigrations`，Django 都**想再建一次那个字段**；或者更糟，它什么都不提，直到某天有人改模型，自动检测器基于错误的状态生成了错误的迁移。

**迁移 C**（加字段）：给有 500 万行的表加一个 `unique=True` 的字段。`makemigrations` 顺利通过，上线执行时 **`UNIQUE constraint failed`，整库回滚，服务中断 8 分钟**。

三个迁移的共同点：**都是把"现在的模型"和"迁移时的模型"搞混了，或者把"数据库的状态"和"Django 的状态"搞混了**。

这一课就是把这两组概念拆开：

| 你以为 | 实际 |
|--------|------|
| 迁移里的模型 = `models.py` 里的模型 | 迁移里的模型是**那一刻的快照** |
| `RunSQL` 建了表，Django 就知道了 | Django 只知道**状态**，不知道你的裸 SQL |
| 加字段是一个原子操作 | 加唯一字段是**三个部署步骤** |

---

## 第一幕：数据迁移与历史模型

### 1.1 先看"错误写法"是怎么工作的

几乎所有人都写过这样的迁移 —— 直接 import 当前模型：

```python
# ❌ 反例：0002_bad_import.py
from django.db import migrations
from shop.models import Article          # ← 问题在这里


def fill_slug(apps, schema_editor):
    for obj in Article.objects.all():
        obj.slug = "x-%s" % obj.legacy_tag
        obj.save()


class Migration(migrations.Migration):
    dependencies = [("shop", "0001_initial")]
    operations = [migrations.RunPython(fill_slug, migrations.RunPython.noop)]
```

**它在写下的当天是完全正常的**（实验 1）：

```
✅ migrate 退出码                                  实际=0
✅ shop.0002_fill 被标记已应用                       实际=True
✅ 数据确实被改写（说明它工作时很正常）                    实际='x-t1'
```

然后过了几个月，有人删掉了 `Article.legacy_tag` 这个字段。新人跑 `migrate`（实验 2）：

```
AttributeError: 'Article' object has no attribute 'legacy_tag'
  File ".../apps/shop/migrations/0002_fill.py", line 8, in fill
    obj.slug = "x-" + str(obj.legacy_tag)
```

**整条迁移链断在第 2 步。**

> ⚠️ **这才是最危险的地方**：这段代码在 CI 里跑得好好的（因为测试库的迁移历史是"已经应用过 0002"的，不会重跑），只有在**全新环境从零重放**时才会炸。所以它能一路活到生产。

### 1.2 为什么 `apps.get_model` 能躲开

改一行就够了：

```python
# ✅ 正例
def fill_slug(apps, schema_editor):
    Article = apps.get_model("shop", "Article")   # ← 拿「那一刻」的模型
    for obj in Article.objects.all():
        obj.slug = "x-%s" % obj.legacy_tag
        obj.save()
```

同样的删除字段场景，**顺利通过**（实验 3）：

```
✅ migrate 退出码                                  实际=0
✅ 0004 删字段成功                                  命中='shop.0004_drop_legacy_tag'
```

关键在于 `apps` 是什么。它是 `StateApps` —— 一个**根据迁移历史现场重建出来的应用注册表**，不是 `django.apps.apps` 那个全局注册表。

`RunPython` 的源码里写得很清楚（`migrations/operations/special.py:203`）：

```python
def database_forwards(self, app_label, schema_editor, from_state, to_state):
    from_state.clear_delayed_apps_cache()
    if router.allow_migrate(schema_editor.connection.alias, app_label, **self.hints):
        self.code(from_state.apps, schema_editor)   # ← 传的是 from_state.apps
```

注意最后一行的注释，Django 自己解释了为什么不直接覆盖全局缓存：

```python
# We now execute the Python code in a context that contains a
# 'models' object, representing the versioned models as an app
# registry. We could try to override the global cache, but then
# people will still use direct imports, so we go with a
# documentation approach instead.
```

翻译：**我们知道有人会直接 import，但我们拦不住，只能在文档里说**。所以这个坑永远存在，只能靠你自己不踩。

### 1.3 历史模型是"那一刻的快照"（实验 4）

这句话要精确理解。我在删除 `legacy_tag` 的迁移**之前**和**之后**各放了一个探针：

```
✅ 删字段「之前」的历史模型含 legacy_tag     实际=True
✅ 删字段「之后」的历史模型已无 legacy_tag    实际=False
```

**每个迁移看到的是它自己执行时那一刻的模型状态**。0002 看到的是有 `legacy_tag` 的 `Article`，0005 看到的是没有的。所以 `apps.get_model` 不是"永远拿到旧模型"，而是"**永远拿到正确的那个**"。

画成时间线更清楚：

```
迁移序列    0001_initial → 0002_fill → 0003 → 0004_drop_legacy_tag → 0005
                │              │                      │                 │
历史模型       Article        Article               Article            Article
（那一刻）     ├ id           ├ id                  ├ id               ├ id
              ├ title        ├ title               ├ title            ├ title
              ├ legacy_tag ✅ ├ legacy_tag ✅       ├ legacy_tag ❌    ├ legacy_tag ❌
              └ slug         └ slug                └ slug             └ slug
                   │              │
                   └── 0002 与 0004 用的是同一个模型名，但字段集合不同
```

字段参数也一样取自迁移文件，而不是 `models.py`（实验 8）：

```
✅ 历史字段 max_length 取自迁移文件           实际=20
✅ 历史字段 default 取自迁移文件              实际='old'
```

### 1.4 历史模型是"裸模型"：没有 manager、没有自定义方法

这是很多人踩的第二个坑（实验 5）：

```
✅ 历史模型的 manager 只有默认 Manager        实际=['Manager']
✅ 历史模型没有自定义方法                      实际=False
```

**你在 `models.py` 里定义的自定义 manager、自定义方法、自定义 `save()`，在历史模型上一律不存在。** 因为迁移文件里只存了字段定义，没存你的 Python 代码。

```python
# ❌ 会炸：历史模型没有这些方法
Article = apps.get_model("shop", "Article")
Article.objects.published()          # 自定义 manager 方法 → AttributeError
obj = Article.objects.get(pk=1)
obj.recalculate_score()              # 自定义方法 → AttributeError
obj.save()                           # 自定义 save() 不会执行！
```

> 💡 **这条尤其阴险**：`obj.save()` **不报错**，只是你重写的 `save()` 逻辑（自动更新时间、写审计日志、发信号）**全部静默跳过**。这已经是本阶段抓到的第 7 处"不报错的错误"。

**正确做法**：数据迁移里需要的业务逻辑，在迁移文件内部重新实现一遍，不要依赖模型方法。

### 1.5 `RunPython` 不产生任何状态

源码里 `RunPython.state_forwards` 就是一个 `pass`（`special.py:184`）：

```python
def state_forwards(self, app_label, state):
    # RunPython objects have no state effect. To add some, combine this
    # with SeparateDatabaseAndState.
    pass
```

这带来三个直接后果（实验 6）：

```
✅ RunPython.reversible（无 reverse_code）    实际=False
✅ RunPython.reduces_to_sql                 实际=False
✅ 给了 reverse_code 后可逆                    实际=True
```

1. **不写 `reverse_code` 就不可逆**，回滚时抛 `IrreversibleError`。
2. `reduces_to_sql = False` —— `sqlmigrate` 时会打印 `-- THIS OPERATION CANNOT BE WRITTEN AS SQL`，**无法生成 SQL 预览**。
3. 它改的数据**不进状态** —— 下一节的 `RunSQL` 同理。

### 1.6 迁移默认在事务里（实验 7）

`Migration.atomic` 的默认值是 `True`（`migrations/migration.py:53`）。所以一个迁移里的所有操作**要么全成，要么全败**：

```
✅ 抛出了 RuntimeError                       命中='BOOM_IN_MIGRATION'
✅ 0002 未被标记为已应用                        实际=['0001_initial']
✅ boom 建的临时记录已回滚                       实际=0
✅ 0001 播种的 5 行仍在（未波及已提交迁移）          实际=5
```

注意最后两条的对照：**回滚只针对当前这个失败的迁移，不会波及之前已经提交的迁移**。这是"每个迁移一个事务"的直接结果，也是第三幕 `atomic=False` 讨论的起点。

---

## 第二幕：SQL 迁移与状态解耦

### 2.1 `RunSQL` 只跑 SQL，完全不改状态

视图、触发器、扩展、部分索引 —— 这些数据库对象 **Django 的模型层没有对应概念**，只能靠 `RunSQL`。

```python
migrations.RunSQL(
    "CREATE VIEW shop_hot_article AS SELECT id, title FROM shop_article",
    "DROP VIEW shop_hot_article",
)
```

实测（实验 9）：

```
✅ migrate 退出码                              实际=0
✅ 视图在数据库里存在                             实际=True
✅ 状态里的 shop 模型只有两个                      实际=[('shop','article'), ('shop','author')]
```

**视图建出来了，但 Django 的状态里没有它。**

### 2.2 "看不见"的后果：自动检测器会重复提议

这是最典型的症状（实验 10）：

```
✅ 表已建出来                                  实际=True
✅ Django 未提出任何与 shop_extra 相关的改动        实际=False
✅ 状态里的 shop 模型仍只有两个（视图/裸表不进状态）   实际=[('shop','article'), ('shop','author')]
```

用 `RunSQL` 建了一张 `shop_extra` 表之后，`makemigrations` **对它只字不提**。

原因在原理层面：`makemigrations` 比对的是

> **「所有历史迁移累积出来的状态」** vs **「`models.py` 的当前状态」**

它**从不去看数据库里到底有什么**。你用裸 SQL 建的东西，只要没写进状态，Django 就永远不知道。

社区文章里对这个机制的解释很到位（[Real Python: Create an Index Without Downtime](https://realpython.com/create-django-index-without-downtime/)）：

> Django did not know you created the index because you didn't use a familiar migration operation. When Django aggregated all the migrations and compared them with the state of the models, it found that an index was missing.

### 2.3 解法一：`RunSQL(state_operations=...)`

如果你用 SQL 做的改动**确实对应某个模型变化**，就把状态操作一起传进去（实验 11）：

```python
migrations.RunSQL(
    "ALTER TABLE shop_article ADD COLUMN extra_note varchar(30) DEFAULT ''",
    "ALTER TABLE shop_article DROP COLUMN extra_note",
    state_operations=[                       # ← 让状态跟着走
        migrations.AddField(
            model_name="article",
            name="extra_note",
            field=models.CharField(default="", max_length=30),
        )
    ],
)
```

```
✅ 数据库里多了 extra_note 列                   实际=True
✅ 状态里也能看到 extra_note                    实际=True
```

这是 `RunSQL` 自带的便捷参数，等价于把它包一层 `SeparateDatabaseAndState`。

### 2.4 解法二：`SeparateDatabaseAndState` —— 完全解耦

当你需要**库里做的事**和**状态里记的事**完全不是一回事时，用它（实验 12）：

```python
migrations.SeparateDatabaseAndState(
    database_operations=[migrations.RunSQL(SQL, REV)],   # 库里：建视图
    state_operations=[],                                  # 状态：什么都不做
)
```

```
✅ 视图已建                                    实际=True
✅ 回滚退出码                                   实际=0
✅ 回滚后视图已删除                               实际=False
```

**反向解耦**也成立 —— 只改状态、不动数据库（实验 13）。这在某些"数据库已经手动改过了，只补一个状态"的场景有用：

```python
migrations.SeparateDatabaseAndState(
    database_operations=[],                    # 库里什么都不做
    state_operations=[migrations.AddField(...)],  # 只改状态
)
```

```
✅ 数据库里没有 ghost_field 列                   实际=False
```

> ⚠️ **官方文档对它的警告很重**（[迁移操作参考](https://docs.djangoproject.com/en/6.1/ref/migration-operations/)）：*"If the actual state of the database and Django's view of the state get out of sync, this can break the migration framework, **even leading to data loss**."* 以及 *"Do not use this operation unless you're very sure you know what you're doing."*
>
> 校验方法文档也给了：`sqlmigrate` 查数据库操作，`makemigrations --dry-run` 查状态操作。

### 2.5 不可逆的代价（实验 14）

不给 `reverse_sql`，迁移就是单向的：

```
✅ 正向迁移成功                                 实际=True
✅ 回滚退出码非 0                               实际=True
✅ 报 IrreversibleError                      命中='IrreversibleError'
```

如果某个方向确实"什么都不用做"，用 `RunSQL.noop` 显式表达（实验 15）：

```python
migrations.RunSQL(sql="...", reverse_sql=migrations.RunSQL.noop)
```

`RunSQL.noop` 就是空字符串 `""`（实测 `RunSQL.noop == ""`），`_run_sql` 遇到它会跳过执行。

### 2.6 `elidable=True`：让临时迁移从历史里消失

`elidable` 是 `RunPython` 和 `RunSQL` 共有的参数。它决定这个操作在 **squash 时是否可以被丢弃**，用于那些"只是一次性修补"的迁移：

```python
migrations.RunPython(nice_to_have, migrations.RunPython.noop, elidable=True)
```

文档的原话是：*"The optional `elidable` argument determines whether or not the operation will be removed (elided) when squashing migrations."*

**它的效果要到 3.6 节 squash 时才看得见**（实测见 3.7 节），这里先记住两点：

- 标了 `elidable=True` → squash 时**会被移除**
- 不标 → squash 时**原样保留**

> 📌 所以它归在第二幕（它是操作的属性），但**作用发挥在第三幕**。别把它当成 squash 的参数 —— 它写在操作上，不是写在 `Migration` 类上。

### 2.7 自定义 Operation：Django 没有的操作自己写

当同一段 SQL 逻辑要在多个迁移里复用，或者你想要一个语义清晰的操作名时，写自定义 Operation（实验 29、30）。

最小骨架就是三个方法：

```python
from django.db import migrations
from django.db.migrations.operations.base import Operation   # ← 必须显式 import


class CreateView(Operation):
    reversible = True
    reduces_to_sql = True

    def __init__(self, name, sql, reverse_sql):
        self.name = name
        self.sql = sql
        self.reverse_sql = reverse_sql

    def state_forwards(self, app_label, state):
        pass                      # 视图不进状态

    def database_forwards(self, app_label, schema_editor, from_state, to_state):
        schema_editor.execute(self.sql)

    def database_backwards(self, app_label, schema_editor, from_state, to_state):
        schema_editor.execute(self.reverse_sql)

    def describe(self):
        return "Create view %s" % self.name
```

实测跑通且可回滚：

```
✅ 自定义 Operation 正向执行成功                  实际=0
✅ 视图已建出                                   实际=True
✅ 回滚成功                                    实际=0
✅ 回滚后视图已删除                               实际=False
```

> 📌 **关于 import 的两种写法**：上面用的是 `from django.db.migrations.operations.base import Operation`，基类直接写 `Operation`。实验 30 里写的是 `class CreateView(migrations.operations.base.Operation)`，那是**通过 `migrations` 包逐级访问**，等价于前者 —— 前提是有 `from django.db import migrations`（迁移文件默认就有这一行）。
>
> 两种都对，但**模板里必须显式 import `Operation`**，否则会 `NameError`。迁移文件是普通 Python 模块，没有自动注入。

三个方法的分工：

| 方法 | 职责 | 不实现的后果 |
|------|------|-------------|
| `state_forwards` | 改 Django 的状态 | 自动检测器看不见你的改动 |
| `database_forwards` | 改数据库 | 迁移什么都不做 |
| `database_backwards` | 回滚 | 需把 `reversible` 设为 `False` |

> 📌 文档还提示了一个细节：如果要在 `database_forwards` 里用 `from_state` 取模型，必须先调 `from_state.clear_delayed_apps_cache()`，否则关联模型可能拿不到（`RunPython` 源码里正是这么做的）。

### 2.8 串联课 13：多库下 SQL 去哪个库

这是本课与课 13 的交汇点，也是我**预期被实测推翻**的一处。

先确认基线（实验 26）：

```
✅ 主库 migrate 成功                            实际=0
✅ 主库建出了 shop_article                       实际=True
✅ logs 库此时还没有 shop_article                 实际=False
✅ 再对 logs 库 migrate 成功                     实际=0
✅ shop 的表仍未建到 logs 库（allow_migrate 拦住了）  实际=False
✅ logs 应用的表确实建在 logs 库                   实际=True
✅ logs 应用的表没有建到主库                        实际=False
```

`migrate` **一次只作用于一个库**（官方文档明示），多库必须逐个跑。而"这套表建在哪个库"由 `allow_migrate` 说了算 —— 这正好复用了课 13 的结论。

然后是 `hints`。文档的说法是：

> The optional `hints` argument will be passed as `**hints` to the `allow_migrate()` method of database routers to assist them in making a routing decision.

**关键在于"assist"（辅助），不是"dictate"（决定）。** 我实测了这个区别（实验 16）：

```
✅ shop 应用的 RunSQL 未落到 logs 库（allow_migrate 拦截）    实际=False
✅ hints 并未阻止它在 default 库执行（hints 只是传给路由器的参数）  实际=True
✅ 对照：logs 应用的 RunSQL 成功落到 logs 库                 实际=True
✅ 换成读 hints 的路由器后，logs_only 成功落到 logs 库         实际=True
✅ 且不再落到 default 库                                  实际=False
```

结论：**`hints` 对 Django 自身毫无意义，它只是原样转发给路由器的参数。**

我的第一个路由器忽略了 `hints`，所以 `hints={"database": "logs"}` 完全不起作用；换成会读 `hints` 的路由器后，同一条迁移的行为**立刻改变**。源码层面就是这样（`db/utils.py:257`）：

```python
def allow_migrate(self, db, app_label, **hints):
    for router in self.routers:
        ...
        allow = method(db, app_label, **hints)   # ← 原样转发，Django 不解释
        if allow is not None:
            return allow
    return True
```

> ⚠️ **实践含义**：`RunSQL(hints={"database": "logs"})` **不是**"只在 logs 库执行"的意思。它能不能生效，**完全取决于你的路由器读不读这个 key**。如果你的 `allow_migrate` 签名是 `def allow_migrate(self, db, app_label, model_name=None, **hints)` 却从不看 `hints`，那这个参数写了等于没写 —— 这和课 12 的 `"pool": {}`、课 13 的"只写 `db_for_read`"是同一类**静默失效**。

---

## 第三幕：零停机变更与迁移治理

### 3.1 事故复现：一步到位加唯一字段

先看错误做法（实验 17）。给一张已有 5 行数据的表加 `unique=True` 的字段：

```python
migrations.AddField(
    model_name="article",
    name="code",
    field=models.CharField(default="", max_length=20, unique=True),
)
```

```
✅ migrate 退出码非 0                           实际=True
✅ 报 UNIQUE constraint failed                命中='UNIQUE constraint failed'
✅ 0002 未被标记为已应用                          实际=['0001_initial']
```

**原因**：`AddField` 带默认值时，数据库会给**所有已有行**填上同一个默认值 `""`，然后立刻建唯一索引 —— 5 行全是 `""`，直接冲突。

这也解释了为什么测试环境从来看不到：测试库是空的，没有行就没有冲突。

> 📌 **串联课 12 的两个易混概念**：
> 1. 课 12 讲过**约束下沉到数据库**（裸 SQL 也绕不过）。这里正是它的延续 —— 唯一约束在数据库层，所以重复值无处可逃。
> 2. `AddField` 还有一个 `preserve_default` 参数（默认 `True`）。它管的是"默认值**是否保留在字段定义里**"，跟这里说的"默认值**被写进已有行**"是两件事 —— 后者由 `schema_editor.add_field` 处理（`backends/base/schema.py:760`），无论 `preserve_default` 是什么都会发生。**别指望调 `preserve_default` 能解决唯一冲突。**

### 3.2 正解：三步走

把一个迁移拆成**三个独立的部署步骤**（实验 18、19）：

**第一步：加可空字段，不加约束**

```python
migrations.AddField(
    model_name="article",
    name="code",
    field=models.CharField(blank=True, max_length=20, null=True),
)
```

**第二步：数据迁移回填唯一值**

```python
def backfill(apps, schema_editor):
    Article = apps.get_model("shop", "Article")
    for obj in Article.objects.all().order_by("id"):
        obj.code = "C%04d" % obj.pk
        obj.save(update_fields=["code"])


class Migration(migrations.Migration):
    dependencies = [("shop", "0002_step1_add_nullable")]
    operations = [migrations.RunPython(backfill, reverse_backfill)]
```

> ⚠️ **上面这个写法只适合小表。** 它有两个问题，在大表上会出事（详见 3.2.1）：
> 1. `objects.all()` 会**一次性把全表载入内存**（实验 31 实测：`_result_cache` 里存了全部 50 行）；
> 2. 逐条 `save()` 会产生 **1 + N 条 SQL**（实验 33 实测：50 行 = 51 条 SQL）。
>
> 500 万行的表就是 500 万次往返加全表内存占用 —— 要么慢到超时，要么直接 OOM。**生产写法见 3.2.1。**

**第三步：收紧为唯一非空**

```python
migrations.AlterField(
    model_name="article",
    name="code",
    field=models.CharField(max_length=20, unique=True),
)
```

实测：

```
✅ 三步走全部成功                               实际=0
✅ 回填出唯一值                                 实际=['C0001', 'C0002', 'C0003']
✅ 裸 SQL 插入重复 code 被数据库拦下               实际=True
```

最后一条最关键 —— 我用**裸 SQL** 绕开 ORM 去插重复值，依然被拦。说明约束真的落在数据库层，这是课 12"约束下沉"的又一次验证。

> 💡 **为什么要拆成三个迁移而不是一个？** 因为第二步（回填）在 500 万行的表上可能要跑很久，而且**应该可以失败重试**。如果三步挤在一个事务里，回填跑到一半失败会全部回滚；拆开之后，第二步失败时第一步已经提交，你可以修好再重跑。

### 3.2.1 大表回填：怎么写才不会 OOM

3.2 节第二步的写法（`objects.all()` + 逐条 `save()`）是教科书里的常见示例，但**它在大表上会出事**。实测（实验 31、33）：

```
✅ queryset 缓存里存了全部 50 行（即全表载入内存）      实际=50
✅ 逐条 save 的 SQL 条数 = 1 次 SELECT + 50 次 UPDATE  实际=51
✅ 批量写法条数 = 1 次游走 + 5 次批量 UPDATE            实际=6
✅ 批量 UPDATE 语句中带 CASE WHEN（一次更新多行）        实际=True
```

两条实测结论：

1. **`objects.all()` 会一次性把全表塞进 `_result_cache`** —— 500 万行就是 500 万个 Python 对象常驻内存。
2. **逐条 `save()` 产生 1 + N 条 SQL** —— 500 万次数据库往返。

正确的写法用 `iterator()` 分批取、`bulk_update()` 分批写：

```python
BATCH = 1000


def backfill(apps, schema_editor):
    Article = apps.get_model("shop", "Article")
    batch = []
    for obj in Article.objects.order_by("id").iterator(chunk_size=BATCH):
        obj.code = "C%04d" % obj.pk
        batch.append(obj)
        if len(batch) >= BATCH:
            Article.objects.bulk_update(batch, ["code"])
            batch = []          # 释放引用，让这批对象可以被 GC
    if batch:
        Article.objects.bulk_update(batch, ["code"])


def reverse_backfill(apps, schema_editor):
    apps.get_model("shop", "Article").objects.update(code=None)
```

三个要点：

| 要点 | 作用 | 代价 |
|------|------|------|
| `iterator(chunk_size=N)` | 不填充 `_result_cache`，逐块取（实验 32） | 不能对同一个 queryset 重复遍历 |
| `bulk_update(batch, [...])` | 一条 `CASE WHEN` SQL 更新 N 行 | **不触发信号、不跑自定义 `save()`** |
| `batch = []` 清空 | 让已处理对象可被回收 | — |

实测的 SQL 形态（`bulk_update` 生成的是单条多行的 `CASE WHEN`）：

```sql
UPDATE "shop_article" SET "code" = CASE
  WHEN ("shop_article"."id" = 1) THEN 'C0001'
  WHEN ("shop_article"."id" = 2) THEN 'C0002'
  ...
WHERE "shop_article"."id" IN (1, 2, ...)
```

> ⚠️ **三条必须自己验证的事**（本机只有 SQLite，不能替你下结论）：
> 1. **`bulk_update` 不触发信号、不跑自定义 `save()`** —— 如果你的回填逻辑依赖 `save()` 里的副作用，批量写法会**静默跳过**它们（这跟 1.4 节的历史模型是同一类坑）。
> 2. **`iterator()` 在不同后端上的游标行为不同** —— SQLite 与 PostgreSQL 的分块游标实现有差异，长事务在 PG 上还可能被 `idle in transaction` 超时打断。
> 3. **批大小需要实测** —— 1000 只是起点。批次越大 SQL 越少，但单条 SQL 越长、事务越大、锁持有越久。这个数字必须在**与生产同规格的库**上调。
>
> 这一条也是本课"凡是性能和锁的结论都要在同类型库上验证"原则的延伸。

### 3.3 `atomic=False`：什么时候必须用它

PostgreSQL 的 `CREATE INDEX CONCURRENTLY` **不能在事务块里执行**。Django 默认把每个迁移包在事务里，所以会直接报错（[Real Python 原文](https://realpython.com/create-django-index-without-downtime/)）：

```
psycopg2.InternalError: CREATE INDEX CONCURRENTLY cannot run inside a transaction block
```

解法是把整个迁移标记为非原子：

```python
class Migration(migrations.Migration):
    atomic = False          # ← 关掉整个迁移的事务
    dependencies = [("shop", "0001_initial")]
    operations = [
        migrations.SeparateDatabaseAndState(
            state_operations=[migrations.AddIndex(...)],
            database_operations=[migrations.RunSQL("CREATE INDEX CONCURRENTLY ...")],
        ),
    ]
```

### 3.4 `atomic=False` 的真实代价（实验 20 vs 21）

这是本课**最需要用实测建立直觉**的一组对照。同样一个"前半段成功、后半段失败"的迁移：

**`atomic = False`**（实验 20）：

```
✅ migrate 退出码非 0                            实际=True
✅ 前半段的 tmp_a 已加上（留在库里）                  实际=True
✅ 前半段的 tmp_b 已加上（留在库里）                  实际=True
✅ 失败的迁移未被标记为已应用                         实际=['0001_initial']
```

**`atomic = True`**（实验 21）：

```
✅ migrate 退出码非 0                            实际=True
✅ tmp_a 未留下                                实际=False
✅ tmp_b 未留下                                实际=False
```

**`atomic=False` 的迁移失败后，会留下"做了一半"的数据库，而且迁移记录里没有它。** 这意味着：

1. 你不能直接重跑（前两个 `AddField` 会报"字段已存在"）。
2. 你也不能直接回滚（Django 认为这个迁移没应用过，没有回滚的起点）。
3. **只能手工收拾。**

所以文档的配套建议是：非原子迁移里的操作**要尽可能少**，能拆出去的都拆到别的迁移里。

### 3.5 非原子迁移里的单操作仍可原子（实验 22）

`atomic=False` 是迁移级别的，但**单个操作仍可单独要求事务**。源码里逐个操作判断（`migrations/migration.py:120`）：

```python
atomic_operation = operation.atomic or (
    self.atomic and operation.atomic is not False
)
if not schema_editor.atomic_migration and atomic_operation:
    # Force a transaction on a non-transactional-DDL backend or an
    # atomic operation inside a non-atomic migration.
    with atomic(schema_editor.connection.alias):
        operation.database_forwards(...)
```

这个公式读作：

| `Migration.atomic` | `Operation.atomic` | 该操作是否在事务里 |
|--------------------|--------------------|-------------------|
| `True`（默认） | `None`（默认） | ✅ 是 |
| `True` | `False` | ❌ 否 |
| `False` | `None`（默认） | ❌ 否 |
| `False` | `True` | ✅ 是（`operation.atomic` 短路） |

最后一行是关键：即使整个迁移非原子，给某个 `RunPython` 加 `atomic=True` 仍能让它单独成事务。

> 📌 另外注意文档里的这条：**在 PostgreSQL 上不要把 schema 变更和 `RunPython` 放进同一个迁移**，否则可能撞上 `OperationalError: cannot ALTER TABLE "mytable" because it has pending trigger events`。

### 3.6 迁移治理：`squashmigrations`

迁移文件攒了几百个之后，`migrate` 从零跑一遍会很慢。用 squash 压缩：

```bash
python manage.py squashmigrations shop 0003 --no-input
```

> 💡 **坑**：这个命令**默认是交互式的**，会问 `Do you wish to proceed? [y/N]`。在 CI 里直接跑会因为 `EOFError` 崩掉 —— 这是我实测踩到的（不加 `--no-input` 时退出码为 1）。

squash 的产物有两个关键部分（实验 25）：

```python
class Migration(migrations.Migration):
    replaces = [('shop', '0001_initial'), ('shop', '0002_a'), ('shop', '0003_b')]
    initial = True
    operations = [ ... ]
```

`replaces` 让 Django 知道"这个迁移替代了那几个"。已经应用过旧迁移的环境不会重跑，新环境直接用压缩版 —— 机制在 `executor.py` 的 `check_replacements()` 里。

### 3.7 `elidable=True` 的实际效果（对照实测）

`elidable` 的定义见 2.6 节。这里看它在 squash 时的**实际行为**（实验 24）：

```
✅ elidable 操作已被压掉（正文不含 nice_to_have）     实际=False
✅ 非 elidable 的操作被保留                       命中='kept_field'
✅ 对照组：未标 elidable 的 RunPython 被保留         实际=True
✅ replaces 记录了被压掉的 0002_elidable           命中='0002_elidable'
```

关键是最后一条对照：**不标 `elidable` 的 `RunPython` 会被原样保留**。所以 `elidable` 不是"默认就会压掉"，而是"**允许**被压掉"。

### 3.8 squash 生成的文件**不能直接跑**（重要）

这是我实测中最意外的发现（实验 24）。

squash 会在文件顶部留一段注释：

```python
# Functions from the following migrations need manual copying.
# Move them and any dependencies into this file, then update the
# RunPython operations to refer to the local versions:
# shop.migrations.0001_initial
```

然后生成这样的代码：

```python
migrations.RunPython(
    code=shop.migrations.0001_initial.seed,      # ← 没有 import，直接语法错误
    reverse_code=django.db.migrations.operations.special.RunPython.noop,
),
```

它不是"引用"，而是**把路径当表达式直接写出来了**。从零重放的结果（实验 24）：

```
✅ 重放确实失败                                  实际=True
✅ 失败原因是生成的引用无法解析                        命中='SyntaxError'
```

报错是 `SyntaxError: invalid decimal literal` —— **连语法都过不了，不是运行时错误**。

按提示把函数搬进来之后，立刻正常（实验 24）：

```
✅ 手工搬运函数后，squash 文件可正常从零重放             实际=0
✅ 重放后数据完整                                  实际=5
```

> ⚠️ **实践含义**：`squashmigrations` 是**半自动**的。生成之后必须：手工搬运函数 → 从零 `migrate` 验证 → 再提交。**如果 squash 文件里有 `RunPython` 而你没验证过，它在全新环境上一定跑不起来。**

### 3.8.1 squash 的部署时序：什么时候才能删旧文件

这是 squash 最容易出生产事故的地方。三类环境的状态是不一样的：

| 环境 | 已有记录 | 部署 squash 后 |
|------|---------|---------------|
| 老环境（已应用过旧迁移） | `0001`~`0003` 都在 `django_migrations` 里 | 因为 `replaces` 声明，Django 把 squash 版**标记为已应用**，不重跑 |
| 新环境（从零） | 空 | 直接跑 squash 版 |
| 中间态（只应用了部分） | 只到 `0002` | 跑 squash 版中尚未应用的部分 —— **这是最容易出错的一类** |

"老环境自动标记"这个机制在源码里（`executor.py` 的 `check_replacements`）：

```python
def check_replacements(self):
    """
    Mark replacement migrations applied if their replaced set all are.
    ...
    """
    applied = self.recorder.applied_migrations()
    for key, migration in self.loader.replacements.items():
        if key not in applied and self.loader.all_replaced_applied(key, applied):
            self.recorder.record_applied(*key)
```

**删除旧文件的三条判据**（必须全部满足）：

1. **所有环境都已经跑过 `migrate`**（不是"部署了代码"，是"执行过 migrate"）—— 否则某个环境还停在旧迁移上，而文件已经没了。
2. **没有任何迁移依赖被 `replaces` 的迁移**（比如别的 app 的迁移 `dependencies` 里写了 `("shop", "0002_a")`）。有的话要先改依赖。
3. **squash 版已经在生产上稳定运行一段时间** —— 不要"上线当天就删"。

> ⚠️ **"中间态"环境才是真危险**。如果某个环境只应用到了 `0002`，而你已经删掉了 `0003`，又让 squash 版 `replaces` 了 `0001`~`0003` —— Django 会发现 `all_replaced_applied` 不成立，于是尝试执行整个 squash 版，但库里已经有 `0001`、`0002` 建好的表，直接报"表已存在"。
>
> **所以判据 1 必须逐个环境核对 `django_migrations` 表**，而不是"代码上线了应该就跑过了"。

`--squashed-name` 可以自定义生成的文件名；如果想保留原迁移文件（推荐先保留），squash 本身不会删除它们 —— **删文件是你手动做的决定**。

---

### 3.9 迁移冲突怎么处理

两个人同时改了同一个模型，各自生成了 `0005_xxx` 和 `0005_yyy`。Django 会检测到多个叶子节点并拒绝执行。

```bash
python manage.py makemigrations --merge
```

它会生成一个合并迁移，`dependencies` 里同时依赖两个分支。合并迁移本身通常不含操作，只是把两条历史接起来。

> 📌 `--merge` 只能解决**依赖图**层面的冲突。如果两边改了同一个字段的同一个属性（比如一个改成 `max_length=100`，另一个改成 `200`），合并后状态仍是矛盾的 —— 需要人工决定，然后在合并迁移里补一个 `AlterField` 定下最终值。

---

## 收束：三个知识点，其实是同一件事

回顾三幕，表面上是三个不相关的话题，实际上都在讲**同一件事：你以为只有一套状态，其实有两套**。

| 维度 | 你以为 | 实际是两套 |
|------|--------|-----------|
| **模型** | 迁移里的模型 = `models.py` 里的模型 | **历史快照**（那一刻的模型） vs **当前模型**（`models.py`） |
| **状态** | 数据库改成什么样，Django 就知道什么样 | **数据库状态**（真实表结构） vs **Django 状态**（迁移历史累积出来的） |
| **部署** | 加字段是一次变更 | **多个中间状态**（可空 → 回填 → 收紧），每个都得能独立存活 |

对应的三把钥匙：

- 第一套 → **`apps.get_model`**：拿"那一刻"的模型，而不是当前的。
- 第二套 → **`SeparateDatabaseAndState`**：库里做什么、状态记什么，分开声明。
- 第三套 → **三步走 + 逐个迁移**：让每个中间状态都能独立部署、独立回滚。

把这三行记住，本课 90% 的内容都能推出来。

---

## 本课核心结论

> **迁移里的模型是快照，不是当前模型；数据库的状态和 Django 的状态是两回事。**
>
> `from myapp.models import X` 是定时炸弹 —— 它只在"碰到了后来被改掉的字段/方法"时才炸，所以 review 极难发现。`apps.get_model` 拿到的是**那一刻**的模型，而且它是**裸模型**（没有自定义 manager 和方法，连你重写的 `save()` 都不会跑）。
>
> `RunSQL` 只改数据库不改状态，Django 对它建的东西**完全看不见**；`SeparateDatabaseAndState` 就是把这两件事拆开成对声明。
>
> 加唯一字段是**三个部署步骤**，不是一个迁移。`atomic=False` 是 PG 并发建索引的必需品，代价是失败后留下半成品 —— 只能手工收拾。squash 生成的文件**必须手工搬运函数后再验证**，否则全新环境上直接 `SyntaxError`。

**串联课 13**：`RunSQL(hints={"database": "logs"})` 不是"只在 logs 库执行"。`hints` 只是透传给路由器的参数，**路由器不读就等于没写**。

---

## 自检题

1. 迁移里 `from myapp.models import Article` 一定会出问题吗？什么条件下才会炸？
2. 历史模型和当前模型有哪三点不同？
3. 为什么历史模型上 `obj.save()` 不报错，却是危险的？
4. `RunPython` 不传 `reverse_code` 会怎样？`sqlmigrate` 会怎么显示它？
5. 用 `RunSQL` 建了个视图，之后 `makemigrations` 会有什么异常表现？根因是什么？
6. `SeparateDatabaseAndState` 的两个参数各管什么？官方文档对它有什么警告？
7. 给有 500 万行的表加 `unique=True` 字段，三步分别是什么？为什么必须拆成三个迁移？
8. `atomic=False` 的迁移中途失败，会留下什么？为什么不能直接重跑？
9. `Migration.atomic=False` 但某个 `RunPython(atomic=True)`，这个操作在事务里吗？
10. squash 生成的文件为什么在全新环境上会 `SyntaxError`？怎么处理？
11. 讲义 3.2 节的回填示例（`objects.all()` + 逐条 `save()`）在大表上有什么问题？正确的写法要解决哪两件事？
12. `RunSQL(hints={"database": "logs"})` 能保证只在 logs 库执行吗？为什么？
13. squash 上线之后，什么时候才能删掉被 `replaces` 的旧迁移文件？

<details>
<summary>参考答案</summary>

1. **不一定。** 只有当你**用到了后来被删掉/改掉的字段或方法**时才炸。只碰仍然存在的字段就一切正常（实验 1）。所以它在 CI 里跑得好好的（测试库不会从零重放），只在全新环境炸（实验 2）。这正是它危险的原因。

2. **① 字段集合是那一刻的**（删字段之前的历史模型有该字段，之后没有 —— 实验 4）；**② 字段参数取自迁移文件而非 `models.py`**（实验 8）；**③ 没有自定义 manager 和自定义方法**（实验 5）。

3. **`obj.save()` 不报错，但你重写的 `save()` 逻辑全部静默跳过** —— 自动更新时间、审计日志、信号都不会触发。历史模型是裸模型，只带字段定义。这是"不报错的错误"。

4. **不可逆**，回滚抛 `IrreversibleError`。`sqlmigrate` 会打印 `-- THIS OPERATION CANNOT BE WRITTEN AS SQL`（因为 `reduces_to_sql = False`）。

5. **`makemigrations` 对它只字不提**（实验 10）。根因：`makemigrations` 比对的是「历史迁移累积出的状态」vs「`models.py` 的当前状态」，**从不看数据库里实际有什么**。

6. `database_operations` 管库里执行什么，`state_operations` 管状态记成什么。文档警告：*"If the actual state of the database and Django's view of the state get out of sync, this can break the migration framework, even leading to data loss"*，以及 *"Do not use this operation unless you're very sure you know what you're doing"*。

7. **① 加可空字段（`null=True`，不加唯一）→ ② 数据迁移回填唯一值 → ③ `AlterField` 收紧为 `unique=True`**。必须拆开是因为第二步在大表上耗时很久且应可失败重试；挤在一个事务里，回填跑到一半失败会全量回滚。

8. **留下"做了一半"的数据库，且 `django_migrations` 里没有这条记录**（实验 20）。不能直接重跑（前面的 `AddField` 会报字段已存在），也不能直接回滚（Django 认为没应用过）。只能手工收拾。所以文档建议非原子迁移里的操作要尽可能少。

9. **在。** 源码公式 `operation.atomic or (self.atomic and operation.atomic is not False)`，`operation.atomic=True` 会短路成立（`migration.py:120`）。

10. squash 把 `code=shop.migrations.0001_initial.seed` 这种**路径当表达式**直接写进文件，却没有 import 语句，连语法都过不了。处理：按文件顶部 `# Functions ... need manual copying` 的提示把函数搬进来，改成 `code=seed`，然后**从零 `migrate` 验证**再提交（实验 24）。

11. **两个问题**：`objects.all()` 会把全表一次性载入内存（实验 31：`_result_cache` 存了全部行）；逐条 `save()` 产生 1 + N 条 SQL（实验 33：50 行 = 51 条）。正确写法要用 `iterator(chunk_size=N)` 避免缓存全表，用 `bulk_update()` 把 N 条 UPDATE 合成一条 `CASE WHEN`（实测降到 6 条）。**额外注意**：`bulk_update` 不触发信号、不跑自定义 `save()`，依赖 `save()` 副作用的逻辑会被静默跳过。

12. **不能。** `hints` 对 Django 自身毫无意义，它只是原样转发给路由器 `allow_migrate()` 的 `**hints` 参数（`db/utils.py:257`）。能不能生效**完全取决于你的路由器读不读这个 key**。我的第一个路由器忽略了 `hints`，写了等于没写；换成会读 `hints` 的路由器后，同一条迁移的行为立刻改变（实验 16）。

13. **三条判据全部满足**：① 所有环境都**执行过** `migrate`（要逐个核对 `django_migrations` 表，不是"代码上线了"）；② 没有其他迁移依赖被 `replaces` 的旧迁移；③ squash 版已在生产稳定运行一段时间。最危险的是**中间态环境**（只应用了部分旧迁移）—— 它会导致 `all_replaced_applied` 不成立，Django 试图执行整个 squash 版，然后报"表已存在"。

</details>

---

## 怎么确认你真的会用（三个动手动作）

**动作一：亲手制造一次"历史迁移崩溃"**

在你的项目里找一条最老的数据迁移，把里面 `apps.get_model("app", "Model")` 临时改成 `from app.models import Model`，然后：

```bash
rm -f db.sqlite3 && python manage.py migrate
```

如果它崩了 —— 恭喜，你找到了一个定时炸弹。改回去，然后**把这条规则写进团队的 code review 清单**。

**动作二：给一张有数据的表加唯一字段**

在本地造一张有几百行的表，先按"一步到位"试一次（应该失败），再按三步走做一次。然后**用裸 SQL 插一条重复值**，确认数据库真的拦得住：

```sql
INSERT INTO shop_article (title, slug, code) VALUES ('dup', '', 'C0001');
-- 应该报 UNIQUE constraint failed
```

**动作三：审计你的迁移目录**

```bash
# macOS / Linux
grep -rn "from .*models import" */migrations/*.py
```

```powershell
# Windows PowerShell
Get-ChildItem -Recurse -Path *\migrations -Filter *.py |
  Select-String -Pattern "from .*models import"
```

**任何一条命中的都是一个潜在的定时炸弹。** 同时检查：

```bash
grep -rn "atomic = False" */migrations/*.py   # 每一条都要能回答"失败了怎么收拾"
```

```powershell
# Windows PowerShell
Get-ChildItem -Recurse -Path *\migrations -Filter *.py |
  Select-String -Pattern "atomic = False"
```

---

## 阶段 4 收官：四条主线与一个贯穿陷阱

本课是阶段 4 的最后一课。回看课 11-14，其实只做了四件事：

| 主线 | 课 | 一句话 |
|------|----|--------|
| **把计算推给数据库** | 课 11 | `obj.count += 1` 是三步，有竞态；`F()` 让数据库内部完成，窗口消失 |
| **让索引真正生效** | 课 12 | 索引的价值不在"建了"，而在"被优化器选中且选择性够好"，必须 `explain()` 验证 |
| **把校验下沉到数据库** | 课 12 | Serializer 可被绕过，DB 约束是唯一任何写入路径都绕不过的层 |
| **安全变更线上库** | 课 13、14 | 路由决定去向、复制决定新鲜度、事务只管一个库；迁移里的模型是快照，加唯一字段要三步走 |

而贯穿四课的**同一类陷阱**是：**不报错的错误**。到本课结束，阶段 4 已累计抓到 **7 处**：

1. `Subquery` 漏了 `.values()` 分组 → 给你一组**错值**（课 11）
2. `select_for_update()` 在 SQLite 上**静默失效**（课 11）
3. `Q(a) & Q(b)` 在多值关系上**永远返回 0 条**（课 11）
4. `Count` 少加 `distinct=True` → **静默变成笛卡尔积**（课 11）
5. 连接池 `"pool": {}` **静默失效**（空字典是 falsy）（课 12）
6. **跨库外键静默指向另一份数据**（课 13）
7. **历史模型上的 `obj.save()` 静默跳过你重写的 `save()`**（本课 1.4）

它们的共同点是：**不抛异常、不报警、测试环境看不出来**，只在特定条件（真实并发、真实数据量、全新环境重放、生产同类型数据库）下才暴露。

**这是阶段 4 留给你最重要的一个习惯**：看到"没有报错"不要直接认为"没有问题"，先问一句 —— **"它在什么条件下会静默做错事？"**

**下一阶段**：阶段 5 性能与异步，课 15《ORM 进阶与 N+1 治理》。本课 2.2 节那个 `for obj in Article.objects.all()` 就是典型的 N+1 形态，阶段 5 会系统性地解决它。

---

## 事实核查说明

本课结论分三类，已逐条标注来源：

**官方文档明示**（[Migrations](https://docs.djangoproject.com/en/6.1/topics/migrations/) / [Migration Operations](https://docs.djangoproject.com/en/6.1/ref/migration-operations/)）：
- `RunPython` 的 `apps` 是"历史版本的应用注册表"；"We can't import the Person model directly as it may be a newer version than this migration expects"
- `hints` 会作为 `**hints` 传给路由器的 `allow_migrate()`，用于 **assist**（辅助）路由决策
- `elidable` 决定操作在 squash 时是否被移除
- 不传 `reverse_code` 时 `RunPython` 不可逆；`RunSQL.noop` 用于表达"该方向什么都不做"
- `SeparateDatabaseAndState` 的两个列表语义，以及"不同步可能破坏迁移框架甚至导致数据丢失"的警告
- PG 上不要在同一迁移里混用 schema 变更与 `RunPython`（可能撞 `pending trigger events`）
- 非原子迁移中，操作只有在 `atomic=True` 时才会在事务里执行
- `migrate` 一次只作用于一个数据库
- 自定义 Operation 的三方法骨架，以及需用 `clear_delayed_apps_cache()` 渲染关联模型

**Django 6.1 源码**：
- `migrations/operations/special.py:203` `RunPython.database_forwards` 传的是 `from_state.apps`；`:184` `state_forwards` 是 `pass`
- `migrations/migration.py:53` `atomic = True` 默认值；`:120` 与 `:181` 的 `atomic_operation` 公式
- `migrations/executor.py:255` 与 `:285` `schema_editor(atomic=migration.atomic)`
- `db/utils.py:257` `allow_migrate` 把 `**hints` 原样转发给路由器
- `db/backends/base/schema.py:760` `add_field` 的默认值处理
- `db/migrations/state.py:623` `StateApps` 的构造

**本课实测发现**（文档未明说，33 个实验坐实）：
- **直接 import 只在"碰到后来被改的字段"时才炸**（实验 1 vs 2）—— 这是它在 review 中难以被发现的根本原因
- 历史模型是**那一刻**的快照，删字段前后看到的内容不同（实验 4）
- 历史模型**没有自定义 manager 与方法**，重写 `save()` 会静默跳过（实验 5）
- 迁移回滚**只针对当前失败的迁移**，不波及已提交的迁移（实验 7）
- `RunSQL` 建的东西 Django 完全看不见，`makemigrations` 只字不提（实验 10）
- **`hints={"database": ...}` 对 Django 自身无意义**，只是透传给路由器的参数；路由器不读就等于没写（实验 16，含路由器对照）
- `atomic=False` 失败后留下半成品，且既不能重跑也不能回滚（实验 20 vs 21）
- **`squashmigrations` 生成的文件是 `SyntaxError`**，必须手工搬运函数（实验 24）
- `squashmigrations` 默认交互式，不加 `--no-input` 在 CI 里会 `EOFError`（实验 24 调试过程）
- **`objects.all()` 会一次性把全表载入 `_result_cache`**，逐条 `save()` 产生 1+N 条 SQL；`iterator()` + `bulk_update()` 可把 50 行的 51 条 SQL 降到 6 条（实验 31-33，评审 P0 验证）
- `bulk_update` 生成的是单条带 `CASE WHEN` 的 UPDATE，一次更新整批（实验 33）

**⚠️ 未经实测、需自行验证的部分**：
- PostgreSQL 的 `CREATE INDEX CONCURRENTLY` —— 本机无 PG 环境，本节内容引自 [Real Python](https://realpython.com/create-django-index-without-downtime/) 的方案与报错原文。`atomic=False` 的**语义与代价**已在 SQLite 上实测（实验 20、21），但 PG 上的具体报错信息请自行验证。
- 大表（百万行以上）回填的耗时与锁表现 —— 因数据量、数据库版本、配置而异，本课不给出具体数字。

**引用来源**：
- [Django 官方文档 - Migrations](https://docs.djangoproject.com/en/6.1/topics/migrations/)
- [Django 官方文档 - Migration Operations](https://docs.djangoproject.com/en/6.1/ref/migration-operations/)
- [Real Python - How to Create an Index in Django Without Downtime](https://realpython.com/create-django-index-without-downtime/)

---

**课 14 完** ｜ 实验工程：`%TEMP%/dj-lesson14-demo/miglab` ｜ 33 个实验 / 120 项断言 / 零失败
