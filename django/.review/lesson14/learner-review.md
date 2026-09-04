# 课 14 评审报告 —— learner 视角（零基础学员）

> 评审对象：`stages/4-数据层纵深/lessons/lesson-14-迁移工程.md`
> 评审视角：**零基础学员** —— 假设我只学过课 1-13，没有迁移工程经验，照着这份讲义能不能看懂、照着做会不会出错。
> 评审时间：2026-09-02

---

## 总体评价

**结论：通过（需修 1 个 P0、2 个 P1）。**

讲义的可读性很好，开场三个事故场景能让我立刻明白"这课跟我有关"。实测数据标了实验编号，我可以自己去复现验证。

但我发现**一个 P0**：讲义里的一个核心示例，我照着抄会在运行时炸掉。

---

## P0（必修）

### P0-1 三步走的第二步示例，在大表上会把内存打爆

**位置**：3.2 节 第二步 代码示例

```python
def backfill(apps, schema_editor):
    Article = apps.get_model("shop", "Article")
    for obj in Article.objects.all().order_by("id"):   # ← 这里
        obj.code = "C%04d" % obj.pk
        obj.save(update_fields=["code"])
```

**问题**：`Article.objects.all()` 会**一次性把所有行load进内存**。讲义自己在 3.2 节的引用块里说"第二步（回填）在 500 万行的表上可能要跑很久" —— 那么按这个写法，500 万行会先全部载入内存，**服务直接 OOM**。

更矛盾的是：讲义在"动作二"里让我"在本地造一张有几百行的表"来练手。**几百行用这个写法完全没问题，所以我练手时永远不会发现这个坑，然后照抄到生产上炸掉。**

这跟讲义自己批判的"测试环境看不出问题"是**同一个错误的两次犯**：
- 第一幕说"直接 import 在 CI 里跑得好好的，因为测试库不会从零重放"
- 第三幕的示例在"几百行练手"时跑得好好的，因为不会 OOM

**建议**：给出分页/分批的正确写法，并明确说明为什么：

```python
def backfill(apps, schema_editor):
    Article = apps.get_model("shop", "Article")
    # 用 iterator + 主键分批，避免一次性载入全表
    qs = Article.objects.order_by("id")
    batch = []
    for obj in qs.iterator(chunk_size=1000):
        obj.code = "C%04d" % obj.pk
        batch.append(obj)
        if len(batch) >= 1000:
            Article.objects.bulk_update(batch, ["code"])
            batch = []
    if batch:
        Article.objects.bulk_update(batch, ["code"])
```

或者更简单（数据迁移里常用）：

```python
    # 按主键区间推进，每批 1000 条
    max_id = Article.objects.aggregate(m=Max("id"))["m"] or 0
    for start in range(0, max_id, 1000):
        rows = Article.objects.filter(id__gt=start, id__lte=start + 1000)
        for obj in rows:
            obj.code = "C%04d" % obj.pk
        Article.objects.bulk_update(rows, ["code"])
```

**必须同时说明**：`iterator()` 在 SQLite 上的行为与 PG 不同，批量更新会让事务变大 —— 需要在"自己环境上验证"。

---

## P1（应修）

### P1-1 自定义 Operation 的示例缺少 import 路径说明

**位置**：2.6 节

示例代码开头是：

```python
from django.db.migrations.operations.base import Operation
```

但讲义正文里写的是 `migrations.operations.base.Operation`（实验 30 的代码里用的是 `migrations.operations.base.Operation`）。

**我照着 2.6 节抄的时候不知道该写哪个 import**。而且实验 30 的代码里 `class CreateView(migrations.operations.base.Operation)` 这行，需要 `migrations` 已经被 import（迁移文件里通常有 `from django.db import migrations`），但**讲义没有说明这一点**。

**建议**：在 2.6 节明确写出完整的 import 部分，并说明两种写法的区别。

### P1-2 `squashmigrations` 的生产安全流程缺失

**位置**：3.6-3.8 节

讲义讲了 squash 是什么、`replaces` 是什么、生成的文件会 SyntaxError、要手工搬运函数。但**没有讲生产环境怎么安全地上线一个 squash**。

作为学员我会问：
1. squash 之后，老环境（已经应用过旧迁移的）会怎样？
2. 新环境（从零 migrate）会怎样？
3. 什么时候可以删除被 replaces 的旧迁移文件？删除了老环境会出问题吗？
4. 如果我在 squash 还没全量上线时就删了旧文件，会发生什么？

**建议**：补一小节"squash 的部署时序"，至少回答"**什么时候能删旧文件**"这个问题。这是 squash 最容易出生产事故的地方。

---

## P2（建议）

### P2-1 讲义里"状态"这个词有三层含义，建议加个术语表

我在读第二幕时反复卡住，因为"状态"在不同地方指不同的东西：
- `ProjectState`（Django 内部对模型的表示）
- 数据库状态（真实的表结构）
- 迁移应用状态（`django_migrations` 表里记录的应用情况）

建议在第二幕开头加一个三行术语表。

### P2-2 2.7 节的 `hints` 结论很重要，但埋得太深

2.7 节是"串联课 13"的内容，结论（`hints` 只是透传参数）非常有价值。但它放在第二幕最后一节，且标题是"串联课 13"，**我作为学员容易把它当成补充材料跳过**。

建议：在"本课核心结论"里已经提到了（✅ 已有），再在自检题里加一道题（当前 10 道题里没有专门考 hints 的）。

### P2-3 "动作三"的 grep 命令在 Windows 上跑不了

```bash
grep -rn "from .*models import" */migrations/*.py
```

本机是 Windows，用户用的是 PowerShell。建议补一条 PowerShell 等价命令：

```powershell
Get-ChildItem -Recurse -Filter *.py -Path *\migrations | Select-String -Pattern "from .*models import"
```

---

## 我读完后能回答的问题（自检）

| 问题 | 能否回答 |
|------|---------|
| 为什么不能用 import 模型？ | ✅ 能，而且知道是"特定条件下才炸" |
| `apps.get_model` 拿到的模型有什么不同？ | ✅ 能（三点不同） |
| 历史模型为什么没有自定义方法？ | ✅ 能 |
| `RunSQL` 建的东西 Django 为什么看不见？ | ✅ 能 |
| `SeparateDatabaseAndState` 什么时候用？ | ✅ 能 |
| 加唯一字段的三步是什么？ | ✅ 能 |
| `atomic=False` 的代价？ | ✅ 能 |
| squash 生成的文件为什么跑不了？ | ✅ 能 |
| **大表回填怎么写才不 OOM？** | ❌ **不能（P0）** |
| **squash 上线后什么时候能删旧文件？** | ❌ **不能（P1-2）** |

---

## 修复清单

> ✅ **全部已修复并验证**（2026-09-02）。修复后重跑：33 个实验 / 120 项断言 / 零失败，链接与索引校验 8 项全绿。

| 编号 | 问题 | 优先级 | 状态 |
|------|------|--------|------|
| P0-1 | 回填示例在大表上会 OOM | P0 | ✅ 已修：补实验 31-33 坐实（`_result_cache` 50/50 行、51 条 → 6 条 SQL），新增 3.2.1 节给出 `iterator()` + `bulk_update()` 生产写法，并标注三条需自验事项 |
| P1-1 | 自定义 Operation 缺完整 import | P1 | ✅ 已修：补 `from django.db.migrations.operations.base import Operation`，并说明两种基类写法的等价关系 + "迁移文件没有自动注入" |
| P1-2 | squash 生产部署时序缺失 | P1 | ✅ 已修：新增 3.8.1 节（三类环境对照表 + 删文件三条判据 + **中间态环境最危险**的说明 + `check_replacements` 源码） |
| P2-1 | "状态"术语多义，建议术语表 | P2 | ✅ 已修（以另一种形式）：新增「收束：三个知识点，其实是同一件事」，把三层"状态"统一成一张对照表 |
| P2-2 | hints 结论应进自检题 | P2 | ✅ 已修：自检题扩到 13 题，第 12 题专门考 hints |
| P2-3 | grep 命令需补 PowerShell 版 | P2 | ✅ 已修：两条命令都补了 PowerShell 等价写法 |

**修复后我能回答的问题**：

| 问题 | 修复前 | 修复后 |
|------|--------|--------|
| 大表回填怎么写才不 OOM？ | ❌ 不能 | ✅ 能（`iterator()` + `bulk_update()`，51 条 → 6 条 SQL） |
| squash 上线后什么时候能删旧文件？ | ❌ 不能 | ✅ 能（三条判据 + 中间态风险） |
| `bulk_update` 有什么副作用？ | ❌ 不知道 | ✅ 知道（不触发信号、不跑自定义 `save()`） |

> 💡 **评审元观察**：P0-1 的特殊之处在于——**它和讲义自己批判的错误是同一类**。讲义第一幕说"直接 import 在 CI 里跑得好好的，因为测试库不会从零重放"；而第三幕的回填示例在"几百行练手"时跑得好好的，因为不会 OOM。**两次都是"小样本掩盖了大样本才会暴露的问题"**。这类错误值得单独留意：当我们用一个简化示例演示"正确的做法"时，要检查这个示例本身在放大规模后是否仍然正确。
