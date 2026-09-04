# 课 21　自定义管理命令与 System checks

> 📖 情节定位：**收尾（三）** —— 把运维动作和约定检查都固化成可执行、可 CI 的东西
> 🎯 本课目标：能写生产可用的管理命令，并把团队约定变成自动检查

## 本课要回答的三个问题（来自课 20 的接力）

1. 课 20 那三个脚本（体检 / schema 导出 / 多版本导出）怎么升级成 `manage.py testhealth`、`manage.py exportdocs --api-version v1` 这样的正式命令？
2. 课 20 发现的那些坑（路由遮蔽、迁移禁用、文档不同步）怎么变成 CI 能拦住的检查？**Error 还是 Warning，判据是什么？**
3. `call_command` 测命令时，patch 到底打在哪儿？

---

# 第一幕　场景引入：三个"跑得好好的"脚本

## 1.1 一个真实的周三下午

你的项目里现在有三个脚本，都是某次排查问题时写的：

```text
scripts/
├── check_test_speed.py     # 课 20 实验 41：把测试耗时拆成三段
├── export_schema.py        # 课 20 实验 33：导出 OpenAPI 文档
└── export_all_versions.py  # 课 20 实验 30：按版本导出多份文档
```

它们都"能跑"。其中一个长这样（`check_test_speed.py`，约 20 行）：

```python
"""测试太慢了，看看时间都花在哪。——2026-06-11 排查时用"""
import os
import time

os.environ["DJANGO_SETTINGS_MODULE"] = "config.settings"
import django

django.setup()

from django.test.runner import DiscoverRunner  # noqa: E402
from django.test.utils import setup_test_environment  # noqa: E402

N = 20          # ← 想改用例数？改这里然后重新跑
SEED = 50       # ← 这个和上面那个哪个是造数量来着？

setup_test_environment()
runner = DiscoverRunner(verbosity=0, interactive=False)

t0 = time.perf_counter()
old = runner.setup_databases()
print("SETUP", (time.perf_counter() - t0) * 1000)

# 造数
t1 = time.perf_counter()
from apps.shop.factories import ProductFactory

ProductFactory.create_batch(SEED)
print("SEED", (time.perf_counter() - t1) * 1000)

runner.teardown_databases(old)
# ← 忘了 teardown_test_environment()，也没算执行段
# ← 失败了退出码还是 0，cron 看不出来
```

**看见问题了吗？** 这段代码里藏着四类缺陷，而且它们在"我自己用"的时候一个都不会暴露：

| 缺陷 | 为什么自己用的时候没事 | 换了人/换到 cron 就出事 |
|------|---------------------|----------------------|
| 参数写死成常量 | 我知道改哪一行 | 别人得读源码 |
| `print` 输出，无级别 | 我就在屏幕前看 | cron 邮件几十行，找不到重点 |
| 失败退出码仍是 0 | 崩了我当场看见 | 监控全绿，三天后才发现 |
| 没有 `--help` | 我记得怎么用 | 得翻聊天记录 |

三个月后，团队里出现了这些对话：

> **新人**：`check_test_speed.py` 怎么调？里面那个 `N = 20` 是什么意思，能改吗？
> **你**：……我看看代码。哦，直接改那个常量就行。

> **运维**：`export_all_versions.py` 我挂 cron 了，每天凌晨 3 点跑。**上周三它根本没跑成功 —— 脚本在第 2 个版本导出时就抛异常退出了，但退出码还是 0，监控面板三天全绿。** 直到周五有人要用那份文档，才发现文件停留在上周二的。
> **你**：……等等，它抛异常了退出码还是 0？
> **运维**：对啊，`python export_all_versions.py` 抛异常是 1 啊。但你这个脚本最后一行是 `print("done")`，异常发生在循环里……哦不，是你用 `try/except: print("skip")` 兜住了，跑完正常结束，退出码就是 0。
> **你**：……我改。改成失败就 `sys.exit(1)`。
> **运维**：顺便问一句，凌晨 3 点那封 cron 邮件有 **40 多行**，我怎么知道哪一行是出事的那个版本？

> **CI**：（流水线全绿）
> **你**：不对，schema 上周就改过了，为什么没人发现文档没提交？
> **CI**：因为没人告诉我"文档和代码要一致"这件事。

> ⚠️ 最后一句才是关键：**"文档和代码要一致"是一条团队约定，但它只存在于人的脑子里。** CI 不知道这条约定，所以永远拦不住。这是本课知识点 2 要解决的问题。

## 1.2 这三条抱怨，对应三种缺失

| 抱怨 | 真正缺的东西 | 本课哪个知识点 |
|------|-------------|---------------|
| "参数怎么调？能改吗？" | **可配置的参数**与**可发现的帮助** | 知识点 1：BaseCommand |
| "cron 怎么接？失败了怎么知道？" | **退出码契约**与**进度输出** | 知识点 1：verbosity / 退出码 |
| "文档不一致 CI 为什么不管？" | **把团队约定变成自动检查** | 知识点 2：System checks |

## 1.3 先说清楚一件容易被搞混的事

**管理命令不是"脚本换了个地方放"。**

脚本是**写给自己看的**：参数写死、输出随意、失败就崩、跑完就忘。
命令是**给别人和机器用的**：参数可发现、输出分级别、失败有退出码、行为可预测。

这个区别不是形式主义。本课会反复回到一个判据：

> **这件事，机器能不能自己判断对错？**

能 → 就应该是命令或 check。不能 → 才留在文档里让人看。

---

# 第二幕　认知冲突：你以为的，和实测出来的

课 20 教的核心方法论是**先量后改**。这一课我们照做——但先说结论：**本课的五个"想当然"，实测全部翻车**。

## 2.1 冲突一：`--verbosity 0` 会自动变安静吗？

**直觉**：`--verbosity` 是 Django 内置的分级输出开关，给 0 就应该什么都不打印。

**实测（实验 1）**：

```text
verbosity=0 输出行数 = 1
verbosity=1 输出行数 = 2
verbosity=2 输出行数 = 4
    🔴 verbosity=0 时 self.stdout.write 依然输出（不自动抑制）
```

`hello alice` 在 verbosity=0 时**照样打印出来了**。

**为什么**：`verbosity` 只是 `options` 字典里的一个整数。Django 把它递给你，至于"要不要少打印"，**是你自己的 `if` 说了算**：

```python
if verbosity >= 1:
    self.stdout.write("开始处理…")   # 这一行被 gate 掉了
self.stdout.write(msg)                # 这一行没有，所以照样输出
```

**工程含义**：想让命令真的安静，必须在**每一条**输出前判断。忘了判断的那一句，就是你半夜被 cron 邮件吵醒的原因。

## 2.2 冲突二：`--no-input` 是 BaseCommand 自带的吗？

**直觉**：`--verbosity` 是全局选项，`--no-input` 应该也是。

**实测（实验 50）**：

```text
hello --no-input 退出码 = 2（2 = unrecognized）
    🔴 普通命令不接受 --no-input（它不是全局选项）
makemigrations --help 含 --no-input = True
```

**`--no-input` 只加在"可能需要交互"的命令上**（`migrate` / `makemigrations` / `collectstatic` / `squashmigrations`）。你自己写的命令如果没有交互，就**没有**这个选项。

⚠️ 这个坑的真实代价在课 14 已经付过一次：`squashmigrations` 不加 `--no-input` 会以 `EOFError` 崩在 CI 里——**因为 CI 没有 stdin 可以读**。

## 2.3 冲突三：`--help` 会显示默认值吗？

**直觉**：argparse 默认会在 help 里追加 `(default: 20)`。

**实测（实验 49）**：

```text
    🔴 --help 默认不显示 default（要自己写进 help 文本）
    ✅ 本命令把默认值写进了 help 文本
```

Django 的 `CommandParser` 定制过 help 格式化，**默认值不会自动追加**。

**工程含义**：你的 `--limit` 默认是 100，但 `--help` 里一个字都不提。使用者要么去读源码，要么猜。正确做法是把默认值写进 `help=` 文本：

```python
parser.add_argument("--limit", type=int, default=100, help="最多处理多少条（默认 100）")
```

## 2.4 冲突四：`CommandError` 会写进 stderr 吗？

**直觉**：会。`self.stderr.write()` 才写 stderr，但 `raise CommandError` 总得有个输出。

**实测（实验 33）**：

```python
with self.assertRaises(CommandError) as ctx:
    call_command("hello", "bob", "--times", "0", stderr=err)
self.assertIn("--times 必须", str(ctx.exception))
self.assertEqual(err.getvalue(), "")   # ✅ stderr 是空的
```

**`CommandError` 不写 stderr。** 它是被 `run_from_argv` 接住后打印的，而 `call_command` 走的是另一条路径——直接抛给调用方。

**工程含义**：**测命令时不要用 stderr 去 grep 错误信息**，要用 `assertRaises(CommandError)`。指望 grep stderr 的测试，会 silently pass 一个空字符串。

## 2.5 冲突五：退出码 —— 谁说了算？

**实测（实验 11、4）**：

| 情况 | 退出码 | 谁定的 |
|------|--------|--------|
| 命令正常完成 | **0** | 你（什么都不做） |
| `raise CommandError` | **1** | Django |
| 未知命令 | **1** | Django |
| 参数类型错误 / 缺必填参数 | **2** | argparse（Django 没改写） |
| `manage.py check` 有 Error | **1** | Django |
| `manage.py check` 只有 Warning | **0** | Django（Warning 不阻断！） |

最后一行是 CI 里最常踩的：**Warning 默认不阻断**。想让 Warning 也拦住，必须显式加 `--fail-level WARNING`。

## 2.6 五个冲突的共同点

它们全都是**"框架会替我做"的错觉**：

- verbosity 会替我安静 ❌
- `--no-input` 会替我准备好 ❌
- help 会替我写默认值 ❌
- CommandError 会替我输出到 stderr ❌
- Warning 会替我拦住 CI ❌

**Django 给你的是钩子，不是行为。** 这五个钩子都得你自己挂上去。

用一句更准确的话说：**Django 在这些地方提供的是扩展点（extension point），不是默认行为。**

- **扩展点**：框架把"在某个时机调用你"这件事做好（注册、`--verbosity` 传进来、`--fail-level` 可配），但"调用时做什么"完全由你写。你什么都不写，它就什么都不做，而且**不报错**。
- **默认行为**：框架已经替你选好了一种做法，你不动它也生效（比如 `manage.py test` 默认会建测试库、默认跑 `migrations` 检查）。

区分这两者的实用判据：**把它相关的代码全删掉，看有没有报错。** 没报错、只是"少了一点效果"——那是扩展点；报错或直接跑不起来——那是默认行为。本课四个命令和四条 check 全都是扩展点：删掉 `apps.py` 里那行 `from . import checks`，工程照常启动、测试照常通过、check 从 4 条变 0 条，全程零报错（实验 24 实测）。这个"安静地不做"正是 check 类 bug 最难发现的原因。

---

# 第三幕　层层揭示：命令与检查的构造

## 3.1 知识点 1：BaseCommand 的结构

### 3.1.1 命令放在哪、叫什么名字

**位置**：app 下的 `management/commands/` 目录，**命令名 = 文件名**。

```text
apps/shop/
└── management/
    └── commands/
        └── hello.py      →  python manage.py hello
```

⚠️ **两个刚性约束**：

1. `management/` 和 `commands/` 都**必须有 `__init__.py`**（哪怕是空文件），否则 Django 发现不了
2. **命令名就是文件名**。想叫 `hello-world` 就得把文件命名为 `hello_world.py`（连字符不合法）——`manage.py help` 里显示的还是 `hello_world`

想确认命令有没有被发现、属于哪个 app：

```bash
python manage.py help
```

```text
[shop]
    exportdocs
    hello
    payorders
    testhealth
```

### 3.1.2 最小骨架

把下面这段**保存为 `apps/shop/management/commands/hello.py`**：

```python
from django.core.management.base import BaseCommand, CommandError


class Command(BaseCommand):
    help = "一句话说明这个命令做什么（--help 会显示）"

    def add_arguments(self, parser):
        # 位置参数：必填
        parser.add_argument("name", type=str, help="要打招呼的对象")
        # 选项：带默认值（⚠️ 默认值要自己写进 help 文本）
        parser.add_argument("--times", type=int, default=1, help="重复几次（默认 1）")
        # 布尔开关
        parser.add_argument("--shout", action="store_true", help="是否大写输出")

    def handle(self, *args, **options):
        name = options["name"]
        times = options["times"]
        verbosity = options["verbosity"]

        if times < 1:
            raise CommandError("--times 必须 >= 1")

        if verbosity >= 1:
            self.stdout.write(f"开始处理 name={name}")
        if verbosity >= 2:
            self.stdout.write(f"[debug] options = {options}")

        msg = f"hello {name}".upper() if options["shout"] else f"hello {name}"
        for _ in range(times):
            self.stdout.write(self.style.SUCCESS(msg))
```

四条硬规则：

1. **所有输出走 `self.stdout` / `self.stderr`**，不要用 `print`（否则测试捕获不到）
2. **`raise CommandError` 表示"业务失败"**（退出码 1），不要用 `sys.exit()`
3. **每条非必要输出都要 gate 在 verbosity 后面**（实验 1 的教训）
4. **`help=` 里写明默认值**（实验 49 的教训）

### 3.1.3 命令在哪儿被发现

```
apps/shop/management/commands/hello.py
     └── Django 自动发现，命令名 = 文件名
```

**同名命令谁赢**：由 `INSTALLED_APPS` 里**靠前**的 app 胜出（实验 6）。

```text
dup 在前时输出：'FROM_DUP'
    ✅ 同名命令由 INSTALLED_APPS 里靠前的 app 胜出
```

⚠️ 更阴的是**参数表也跟着被换掉**（实验 6b）：shop 的 `hello` 支持 `--times`，dup 的不支持。dup 胜出后：

```text
manage.py hello x --times 2
→ exit 2，error: unrecognized arguments: --times
    ✅ dup 胜出后 --times 变成 unrecognized
```

**排障提示**：`manage.py help` 会标注每个命令属于哪个 app（`[shop]`），这是确认"到底哪个命令在生效"最快的方式。

### 3.1.4 改造课 20 的体检脚本：`manage.py testhealth`

课 20 的体检脚本是写死的常量 + 一堆 print。改成命令：

```python
class Command(BaseCommand):
    help = "体检：把一次测试跑拆成 建库 / 造数 / 执行 三段分别计时。"

    def add_arguments(self, parser):
        parser.add_argument("--cases", type=int, default=20, help="造多少个空用例（默认 20）")
        parser.add_argument("--seed", type=int, default=50, help="造多少条商品（默认 50）")
        parser.add_argument(
            "--warn-setup-ratio", type=float, default=0.5,
            help="建库占比超过这个值就告警（默认 0.5）",
        )
        parser.add_argument("--json", action="store_true", help="输出 JSON 供 CI 解析")
```

四个选项，对应四个"脚本做不到"的能力：

| 选项 | 解决的脚本问题 |
|------|---------------|
| `--cases` / `--seed` | 参数写死，改一次要动源码 |
| `--warn-setup-ratio` | 阈值在脑子里，CI 无法判定 |
| `--json` | `print` 输出机器读不了 |

跑起来：

```text
▶ 阶段 1/3　建库（create + migrate）…
▶ 阶段 2/3　造数（20 条商品）…
▶ 阶段 3/3　执行（10 个用例）…

体检结果
  建库     121.0 ms  ( 63.8%)
  造数      67.5 ms  ( 35.6%)
  执行       1.0 ms  (  0.5%)
  合计     189.6 ms

⚠️ 建库占 64%，超过阈值 50%——提速第一刀应砍在数据库上（--keepdb / MIGRATION_MODULES）
```

⚠️ **一个必须处理的细节**：`--json` 时进度行会污染 stdout，导致 CI 解析失败。所以 `--json` 要**强制静默**：

```python
quiet = options["json"]
if verbosity >= 1 and not quiet:
    self.stdout.write("▶ 阶段 1/3　建库（create + migrate）…")
```

### 3.1.5 改造多版本导出：`manage.py exportdocs --api-version v1`

课 20 实验 30 的核心结论是：**`DEFAULT_VERSION` 是导入时快照，运行时改无效**。所以多版本文档只能靠"每个版本一个 settings 模块"。

命令把这件事封装起来：

```python
VERSION_SETTINGS = {
    "v1": "config.settings_v1",
    "v2": "config.settings_v2",
}

def handle(self, *args, **options):
    module = VERSION_SETTINGS[version]
    # 子进程是必须的：DEFAULT_VERSION 是导入时快照，同进程内改不了
    env = dict(os.environ)
    env["DJANGO_SETTINGS_MODULE"] = module
    proc = subprocess.run([sys.executable, "manage.py", "spectacular", ...], env=env)
```

⚠️ **参数名踩坑（课 2 同款）**：

```python
# ❌ 这样写会崩
parser.add_argument("--version", ...)
# argparse.ArgumentError: argument --version: conflicting option string: --version
```

Django 的 `BaseCommand` 自带 `--version`（显示 Django 版本）。**自定义选项不能叫 `--version`**，本课改成 `--api-version`。

实测两个版本：

```text
▶ 导出 v1 文档（settings=config.settings_v1）
✅ v1 文档已写入 schema-v1.yaml（12983 字节）
▶ 导出 v2 文档（settings=config.settings_v2）
✅ v2 文档已写入 schema-v2.yaml（12983 字节）
```

字节数相同是巧合，内容确实不同：

```text
schema-v1.yaml:   /api/v1/orders/
schema-v1.yaml:   /api/v1/orders/{id}/
schema-v2.yaml:   /api/v2/orders/
schema-v2.yaml:   /api/v2/orders/{id}/
```

加上 `--check` 就是 CI 用的形态（不一致就退出码非 0）。

### 3.1.6 命令里的批处理与事务：`manage.py payorders`

这是"脚本"和"生产命令"差距最大的地方。四个问题：

**① 10 万行会不会把内存吃光？**（必查项 #28）

```python
qs = (Order.objects.filter(status=Order.Status.PENDING)
      .select_related("product").order_by("pk")[:limit])
for order in qs.iterator(chunk_size=batch_size):   # ✅ 边取边处理
    ...
```

放大检验（`probe_batch_scale.py`，N=5000）：

```text
A. .iterator() + 批量 update
   耗时    143.4 ms    SQL  11 条   峰值内存   0.31 MB
B. list() 全量读进内存（反例）
   耗时    161.0 ms    SQL   2 条   峰值内存   3.55 MB
```

⚖️ **这不是单方面的胜利，是一笔交易**：全量读内存是 **11.6 倍**，但 iterator 多出 9 条 SQL（每满 500 条提交一次）。

判据是：**内存是硬上限（OOM 直接崩），SQL 条数只是变慢**。10 万条时 `list()` 会吃到几十 MB，而 iterator 仍是 0.3 MB 量级。

**② 中途失败了怎么办？**

```python
except (GatewayError, ValueError, KeyError, OSError) as exc:
    # ✅ 只捕获可预期的业务异常
    failed += 1
    self.stderr.write(self.style.ERROR(f"  ✗ order={order.pk} 支付失败：{exc}"))
    if stop_on_error:
        raise CommandError(f"--stop-on-error 生效：第 {done} 条失败，整体回滚") from exc
```

⚠️ **`GatewayError` 必须显式列出**。这个坑是本课**真实踩到并记录下来的**：第一版只写了 `except (ValueError, KeyError, OSError)`，注入 0.5 失败率后命令直接崩：

```text
apps.shop.payments.GatewayError: 网关拒付 order=567
（进程退出码 1，整个批次中断）
```

补上 `GatewayError` 后（实验 19）：

```text
失败行数 = 9（失败率 0.5，20 条）
    ✅ 确实发生了部分失败
    ✅ 部分失败不影响退出码（默认继续跑完）  实测=0
    ✅ 失败被记下来而不是静默跳过
```

这与课 15 的 P0（裸 `except Exception` 让 200 行全部静默跳过）是**同一个问题的两面**：漏掉一个异常类型，失败就从"记录"变成"崩溃"。

**③ 重跑一次会重复扣款吗？**

命令只筛 `status=PENDING`，成功后改成 `PAID`。所以第二次跑是**空跑**（实验 48）：

```text
第一次处理 5 条，第二次处理 0 条
    ✅ 第二次是空跑（待支付已清零）
```

这就是被 cron 调度的前提：**幂等**。

**④ 跑的时候屏幕上有反应吗？**

```text
进度行数 = 2（batch=5，12 条）
    ✅ batch-size=5 时输出了分批进度
    ✅ 最后一批不足 batch_size 时不会打印进度（但会被 flush）
```

注意第二条：**最后一批不足 `batch_size` 时不会打印进度**（因为攒够了才 flush）。它的数据**确实被处理了**，只是没打印。想让尾巴也有反馈，得在循环结束后补一句。

### 3.1.7 怎么确认你的命令是"生产可用"的

上面四点讲完，给你一份可以照着逐条打勾的清单。**每条都配了一条能立刻跑的命令**，不是让你凭感觉判断：

| # | 检查项 | 怎么验 | 不合格的表现 |
|---|--------|--------|-------------|
| 1 | **参数可发现** | `python manage.py <cmd> --help` | 看不到选项说明，或说明里没写默认值 |
| 2 | **安静档真的安静** | `python manage.py <cmd> -v 0` | 屏幕上还有输出 |
| 3 | **失败有退出码** | 故意传个非法参数，看 `$LASTEXITCODE` / `echo $?` | 崩了但退出码是 0 |
| 4 | **dry-run 不落库** | `--dry-run` 跑一次，查库 | 数据被改了 |
| 5 | **幂等** | 连跑两次，第二次应为"0 条" | 第二次又处理了一遍 |
| 6 | **大数据量不炸** | 翻到每个 `for`，问循环体里有没有数据库/IO | 有 → 改 `.iterator()` + `bulk_*` |
| 7 | **异常类型显式列出** | grep 一下有没有裸 `except Exception` | 有 → 编程错误会被静默吞掉 |

第 6、7 两条就是**必查项 #28**，课 14/15 连续两课的 P0 都栽在这上面。本课 3.3.7 节会给出自查的完整执行过程。

⚠️ 第 3 条最容易被忽略，也最致命：**脚本崩了但退出码是 0，cron 和 CI 都会认为它成功了。** 本课 2.5 节的退出码表就是它的判据。

### 3.1.8 `--dry-run` 必须真的不落库

```python
if dry_run:
    if verbosity >= 1:
        self.stdout.write("  dry-run：回滚全部改动")
    raise _Rollback()   # 内部信号，触发一次干净回滚
```

实测（实验 16/17）：

```text
dry-run 后仍为待支付的 = 30 / 30    ✅
实跑后已支付 = 30                    ✅
```

⚠️ 别用"if dry_run 就跳过 update"的写法——那样你测的不是"会不会落库"，而是"跳没跳过那行代码"。**真的走一遍再回滚**，才能验证 SQL 本身是对的。

### 3.1.9 命令的启动开销（决定它能被调度多频繁）

`probe_command_startup.py` 实测（各取 5 次最小值）：

```text
裸 Python 启动           =    56.0 ms
Python + django.setup()  =   458.5 ms
完整命令（含 checks）    =   632.8 ms
命令 --skip-checks       =   359.9 ms

Django 启动开销    ≈   402.5 ms
system checks 开销 ≈   272.9 ms
```

**跑一次 `manage.py` 的绝大部分时间花在"启动 + checks"上，与命令做什么无关。**

工程含义：

- **频繁调度的小任务**（比如每分钟一次），别用 `manage.py` 起进程——改成常驻进程内的调用（Celery beat / `django.tasks`）
- **一次性批处理**无所谓，启动开销只付一次
- 想省 270ms 可以加 `--skip-checks`，但**那也意味着你跳过了自己写的 check**

## 3.2 知识点 2：System checks 框架

### 3.2.1 为什么约定必须进 check

课 20 遗留了四条团队约定。它们现在的形态是"写在讲义里"：

| 约定 | 出处 | 违反时的表现 |
|------|------|-------------|
| 手写路径必须在 `include(router.urls)` 之前 | 课 20 坑 1 | **静默 405** |
| 含 `RunPython` 的 app 不能被 `MIGRATION_MODULES` 禁用 | 课 20 实验 19 | **表在但数据为 0，不报错** |
| 文档字段必须与真实响应一致 | 课 20 实验 31 | 前端按错文档对接 |
| schema 文件必须与代码同步 | 课 20 实验 33 | 文档过期但能跑 |

**写在文档里的约定，新人一定会违反。** 因为他在写代码的时候，文档不在他眼前。

### 3.2.2 Error / Warning / Info 的判据

这是本课知识点 2 的核心问题。判据只有一条：

> **会不会直接导致失败？**

| 级别 | 常量 | 判据 | CI 默认行为 |
|------|------|------|------------|
| **Error** | 40 | 会直接导致测试失败或线上事故 | **阻断（exit 1）** |
| **Warning** | 30 | 现在能跑，但埋了雷 | 不阻断（exit 0） |
| **Info** | 20 | 只是提示 | 不阻断 |

按这个判据给课 20 的四条约定分级：

| 约定 | 级别 | 为什么 |
|------|------|--------|
| 路径被 router 遮蔽 | **Error** | 接口直接 405，测试必然红 |
| 含 RunPython 的 app 被禁用 | **Error** | 表在但数据为 0，依赖种子数据的测试全崩 |
| 字段缺 `help_text` | **Warning** | 代码照跑，只是文档没说明 |
| schema 文件过期 | **Warning** | 代码照跑，只是文档没更新 |

**⚠️ 但级别没有唯一正确答案——它取决于你的下游会不会因此失败。**

同样是"schema 文件过期"：

| 团队 | 下游做什么 | 合适的级别 |
|------|-----------|-----------|
| A | 文档只是给人看的站点 | **Warning**（过期一天无所谓） |
| B | 前端用 `openapi-generator` 生成 TS 类型，进 CI | **Error**（过期 = 编译失败） |

所以正确的问法不是"这条约定该用什么级别"，而是：

> **如果现在不管它，下一步会红在哪儿？**
> 红在测试/编译 → Error。只是不好看或埋雷 → Warning。

同理，`--fail-level` 也该按这个思路配：你的 CI 里如果所有 Warning 都必须修，那就直接用 `--fail-level WARNING`；如果只是想让 Error 拦住，默认的 ERROR 档就够。

⚠️ **Warning 默认不阻断 CI！** 实测（实验 22）：

```text
--fail-level=WARNING 在干净工程上的退出码 = 1
--fail-level=ERROR   在干净工程上的退出码 = 0
    ✅ --fail-level=WARNING 时 Warning 也能拦
    ✅ --fail-level=ERROR 时 Warning 不拦（只有 Error 才拦）
```

想让 Warning 也拦住，CI 里必须写 `--fail-level WARNING`。

### 3.2.3 注册一条 check

```python
from django.core.checks import Error, Warning, register


@register("lab_routes")
def check_route_order(app_configs, **kwargs):
    """约定 1：手写 API 路径必须在 include(router.urls) 之前。"""
    errors = []
    # ... 判定逻辑 ...
    if shadowed:
        errors.append(
            Error(
                f"{len(shadowed)} 条手写路径被 router 遮蔽",
                hint="把这些 path() 移到 include(router.urls) 之前。…",
                id="lab_routes.E001",
            )
        )
    return errors
```

id 命名规范：`{tag}.{级别首字母}{三位编号}`，实测本工程：

```text
lab_docs.W001  lab_docs.W002  lab_env.I001  lab_routes.E001
```

**关于 `app_configs` 参数**（照抄签名时容易忽略）：

```python
def check_route_order(app_configs, **kwargs):
    #          ↑ 这个参数是什么？
```

它是 **Django 传进来的"要检查哪些 app"**：

| 调用方式 | `app_configs` 的值 | 含义 |
|---------|------------------|------|
| `manage.py check` | **`None`** | 检查全部 app |
| `manage.py check shop` | `[<ShopConfig>]` | 只检查 shop |
| `manage.py test` | `None` | 检查全部 |

**所以你的 check 必须能处理"只检查一部分 app"的情况**。本课的写法是忽略它（因为路由和迁移配置是全局的，与具体 app 无关）：

```python
# ✅ 全局性检查（路由、迁移、文档同步）—— 忽略 app_configs
def check_route_order(app_configs, **kwargs):
    ...

# ✅ 按 app 检查——必须处理 None
def check_per_app(app_configs, **kwargs):
    from django.apps import apps as registry
    targets = app_configs or registry.get_app_configs()
    for conf in targets:
        ...
```

⚠️ 如果你写的是"按 app 检查"却忘了 `or registry.get_app_configs()`，那么 `manage.py check`（不带 app 参数）时会**一条都不检查**——又是静默失效。

### 3.2.4 挂载：不注册就是全程静默

```python
# apps/shop/apps.py
class ShopConfig(AppConfig):
    name = "apps.shop"

    def ready(self):
        from . import checks  # noqa: F401  导入即注册
```

⚠️ **这是课 17"信号不注册全程静默"的同款问题**。`probe_check_silent.py` 实测：

```text
已注册：退出码 = 1，报出 4 条自定义 check
不注册：退出码 = 0，报出 0 条自定义 check

SILENT = True
```

**checks.py 不被 import，就一次都不会跑，且没有任何报错。**

### 3.2.5 判定逻辑必须问框架，不能自己猜

这是本课**开发过程中真实踩到并修正**的一个坑，值得单独讲。

**第一版实现**：比较 `urlpatterns` 里的下标——手写路径的下标 > router 的下标，就算被遮蔽。

**问题**：误报。实测（实验 24）：

```text
坏配置下 /api/orders/summary/ → VIEW= OrderViewSet, KWARGS= {}
```

`KWARGS` 是空的！说明它**根本没被 `<pk>` 吃掉**。因为 router 注册在 `api/` 前缀下时，路径是 `orders/<pk>/`，而手写的是 `api/orders/summary/`——**两者不在同一层**。

**正确做法：问 URL 解析器。**

```python
from django.urls import Resolver404, resolve

try:
    match = resolve(sample_url)
except Resolver404:
    continue
if match.func is not getattr(p, "callback", None):
    shadowed.append((i, route, match.func.__name__))   # 落到别的视图 = 被吃掉了
```

修好后的实测（同前缀场景，`config/settings_shadowed.py`）：

```text
同前缀（真遮蔽）: VIEW= OrderViewSet | KWARGS= {'pk': 'summary'}
正常:            VIEW= view         | KWARGS= {}
    ✅ 顺序错时 check 报 E001
    ✅ 顺序正确时 check 不报 E001
```

**教训**：判断"框架行为"时，**让框架自己回答**。你自己推演的规则，总会有边界情况没覆盖到。这与课 19 的"先验证配置是否真的生效"、课 20 的"先量后改"是同一条原则。

改好后的报错信息也更有用（实验 47）：

```text
?: (lab_routes.E001) 1 条手写路径被 router 遮蔽（router 在第 0 项）
	HINT: 把这些 path() 移到 include(router.urls) 之前。
    - 第 2 项 api/orders/summary/ → 实际解析到 OrderViewSet
    router 的 <pk> 是 [^/.]+，会吃掉 /api/xxx/summary/ 这类路径，返回 405 且无任何报错。
```

**hint 里直接给出"实际解析到了哪个视图"**——接手的人不用再猜。

### 3.2.6 四条约定的实测效果

```text
=== 路由遮蔽（config.settings_shadowed）===
?: (lab_routes.E001) 1 条手写路径被 router 遮蔽（router 在第 0 项）
	HINT: … - 第 2 项 api/orders/summary/ → 实际解析到 OrderViewSet

=== 迁移禁用（config.settings_nomig）===
?: (lab_migration.E001) app 'auth' 含 RunPython 数据迁移，却被 MIGRATION_MODULES 禁用
?: (lab_migration.E001) app 'contenttypes' 含 RunPython 数据迁移，却被 MIGRATION_MODULES 禁用
?: (lab_migration.E001) app 'shop' 含 RunPython 数据迁移，却被 MIGRATION_MODULES 禁用
```

⚠️ **`auth` 和 `contenttypes` 也在里面** —— 很多人不知道 `django.contrib` 自带数据迁移。核查确认：

```text
auth         -> ['0011_update_proxy_permissions.py']
contenttypes -> ['0002_remove_content_type_name.py']
```

课 20 实验 18 说"只禁业务 app 无效，因为 contrib 那 18 个照跑"。**现在这条 check 把"为什么"说清楚了：它们里面有数据迁移，禁掉会丢数据。**

### 3.2.7 schema 同步 check 的 settings 相关性

`lab_docs.W001` 判定"已提交的 schema.yaml 是否与当前代码一致"。

⚠️ **它的基准是"当前 settings"**。实测（实验 28b）：

```text
同 settings 导出的基准文件 → W001 出现？False
    ✅ 用同 settings 的基准文件时 W001 不报（基线正确）
    ✅ 改坏后抓出 lab_docs.W001
    ✅ 复原后 W001 消失
实验 28b：
    ✅ 🔴 用 v1 settings 跑 check 时对默认 schema.yaml 报不一致（基准随 settings 变）
```

所以：

- 用 v1 settings 导出的 `schema.yaml`，在默认 settings 下跑 check **必然报不一致**（路径是 `/api/v1/` vs `/api/`）
- CI 里必须在**同一套 settings 下**导出与比对
- 多版本文档要每个版本各自存一份基准文件

另一个实现细节：比对必须用 **drf-spectacular 自己的渲染器**，不能用 `yaml.dump(generator.get_schema(...))` 自己拼——那跟 `spectacular --file` 的输出格式不一致，会产生永不消失的假告警（本课实测踩到）。

```python
from drf_spectacular.renderers import OpenApiYamlRenderer

schema = SchemaGenerator().get_schema(request=None, public=True)
renderer = OpenApiYamlRenderer()
current_yaml = renderer.render(schema, renderer_context={}).decode("utf-8")
```

## 3.3 知识点 3：命令与检查的测试与 CI

### 3.3.1 `call_command` 基本用法

```python
from io import StringIO
from django.core.management import call_command
from django.core.management.base import CommandError


def test_basic(self):
    out = StringIO()
    call_command("hello", "alice", "--times", "2", stdout=out)
    self.assertEqual(out.getvalue().count("hello alice"), 2)


def test_command_error(self):
    with self.assertRaises(CommandError) as ctx:      # ✅ 用 assertRaises
        call_command("hello", "bob", "--times", "0")  # ❌ 别去 grep stderr
    self.assertIn("--times 必须", str(ctx.exception))
```

### 3.3.2 🔴 patch 打在哪儿？（课 20 实验 10/11 的延伸）

课 20 的结论是"patch **使用处**而非定义处"。这个结论在测命令时**依然成立，而且更容易踩**。

本工程的绑定关系：

```python
# apps/shop/payments.py
def charge(order_id, amount): ...           # 定义处

# apps/shop/services.py
from .payments import charge                # ⚠️ 早绑定：绑定的是函数对象本身
def pay(order): return charge(order.id, amount)

# apps/shop/management/commands/payorders.py
from apps.shop.services import pay          # 命令 import 的是 pay
```

四组对照实测（实验 35-39）：

| 实验 | patch 目标 | 写法 | 结果 |
|------|-----------|------|------|
| 35 | `payments.Gateway.charge` | 晚绑定 `pay_via_gateway` | ✅ 有效 |
| 36 | `payments.charge` | 早绑定 `pay` | ❌ **无效** |
| 37 | `apps.shop.services.charge` | 早绑定 `pay` | ✅ 有效 |
| 38 | `apps.shop.services.charge` | 经由 `call_command` | ✅ 有效 |
| 39 | `apps.shop.payments.charge` | 经由 `call_command` | ❌ **无效** |

实验 39 的失败尤其值得注意：

```python
with mock.patch("apps.shop.payments.charge", return_value={"ok": True}) as m:
    call_command("payorders", "--limit", "10", stdout=out)
    m.assert_not_called()   # ✅ 没打中
```

**patch 打错时，命令会真的去调网关**——测试变慢（每笔 5ms）、变不稳定（依赖网络），而且**测试依然是绿的**。你以为测了逻辑，其实测了外部服务。

**判断方法**：看命令模块顶部写了什么 `from` 语句。

```python
# payorders.py 顶部
from apps.shop.services import pay
```

那么命令拿到的是 `services` 命名空间里的 `pay`。而 `pay` 内部调用的是 `services` 命名空间里的 `charge`。所以 patch `apps.shop.services.charge` 才打得中。

**如果你面对的是一个陌生命令，用这三条定位（不用读源码猜）**：

```python
# ① 命令模块顶部 import 了什么？
import apps.shop.management.commands.payorders as m
print("命令模块里的 pay 来自:", m.pay.__module__)      # apps.shop.services

# ② pay 内部是从哪个命名空间取 charge 的？
print("charge 在 globals 里吗:", "charge" in m.pay.__globals__)   # True
print("那个 charge 属于:", m.pay.__globals__["charge"].__module__)  # apps.shop.payments

# ③ 结论：patch "apps.shop.services.charge"
#    因为 ① 说命令会走 services，② 说 services.charge 存在（早绑定）
```

第 ② 条是**决定性判据**：如果 `charge` 出现在函数的 `__globals__` 里，说明它是**模块级名字**（早绑定），patch 该模块的这个属性有效。如果不在（每次用 `payments.Gateway.charge(...)` 现取），那就是晚绑定，patch 定义处有效。

**验证 patch 有没有打中的唯一可靠方法**——就是断言 mock 被调用了：

```python
with mock.patch("apps.shop.services.charge", return_value={"ok": True}) as m:
    call_command("payorders", "--limit", "10", stdout=out)
    m.assert_called_once()   # ← 这一行不能省
```

少了 `assert_called_once()`，patch 打错了也测不出来（实验 39 就是这么发现的）。

### 3.3.3 命令要能被自己测

`testhealth` 命令内部会 `setup_databases()`。当它自己被 `call_command` 在 `TestCase` 里调用时，会撞上 SQLite 的限制：

```text
django.db.utils.NotSupportedError: SQLite schema editor cannot be used
while foreign key constraint checks are enabled.
```

🔴 **这是个真问题，而且加"检测测试环境"也解决不了**。本课先试了这个办法：

```python
already_in_test = (dj_settings.EMAIL_BACKEND == "...locmem.EmailBackend")
if not already_in_test:
    setup_test_environment()
```

它解决了 `RuntimeError: setup_test_environment() was already called`，但**解决不了建库与外层事务的冲突**。

**正确做法**：这类"自己建库"的命令，放在**独立进程**里测：

```python
proc = subprocess.run(
    [sys.executable, "manage.py", "testhealth", "--cases", "3", "--seed", "0", "--json"],
    cwd=str(settings.BASE_DIR), env=env, capture_output=True, text=True,
)
payload = json.loads(proc.stdout.strip())
```

⚠️ 注意 `cwd` 必须用 `settings.BASE_DIR`——测试运行时的工作目录不一定是你以为的那个（本课实测因此拿到空 stdout，`json.loads` 报 `Expecting value: line 1 column 1`）。

### 3.3.4 check 的单测

check 是普通函数，可以直接调：

```python
from django.test import TestCase, override_settings
from apps.shop import checks


class CheckRouteOrderTest(TestCase):
    def test_45_good_order_no_error(self):
        self.assertEqual(checks.check_route_order(None), [])

    @override_settings(ROOT_URLCONF="config.urls_bad2")
    def test_46_bad_order_reports_error(self):
        msgs = checks.check_route_order(None)
        self.assertEqual(len(msgs), 1)
        self.assertEqual(msgs[0].id, "lab_routes.E001")
        self.assertEqual(msgs[0].level, 40)   # ERROR = 40
```

级别常量：`Error=40` / `Warning=30` / `Info=20`（实验 46/51/52 实测）。

✅ **好消息**：与课 2 的 `override_settings(MIDDLEWARE=...)` 不同，`override_settings(ROOT_URLCONF=...)` 对 check **确实生效**——因为 check 是在调用时才去读 `settings.ROOT_URLCONF` 并 `import_module`。这印证了课 19 的结论：**先验证生效，再决定要不要独立进程**。

### 3.3.5 接入 CI

一条完整流水线（实验 52 实测）：

```yaml
# .github/workflows/ci.yml
- name: 系统检查（含自定义 check）
  run: python manage.py check --fail-level WARNING

- name: 文档与代码同步
  run: |
    python manage.py exportdocs --api-version v1 --file schema-v1.yaml
    python manage.py exportdocs --api-version v1 --file schema-v1.yaml --check

- name: 跑测试
  run: python manage.py test
```

Windows 本地等价（PowerShell）：

```powershell
python manage.py check --fail-level WARNING
if ($LASTEXITCODE -ne 0) { throw "系统检查未通过" }

python manage.py exportdocs --api-version v1 --file schema-v1.yaml
if ($LASTEXITCODE -ne 0) { throw "文档导出失败" }

python manage.py exportdocs --api-version v1 --file schema-v1.yaml --check
if ($LASTEXITCODE -ne 0) { throw "schema 与代码不一致，请重新导出并提交" }
```

实测结果：

```text
    ✅ 系统检查（含自定义 check） → 退出码 0
    ✅ 导出并校验 schema → 退出码 0
    ✅ 跑测试 → 退出码 0
  反例：把 schema.yaml 改坏后
    ✅ 改坏 schema 后 check 报 W001
```

### 3.3.6 `--deploy` 是另一类检查

```text
manage.py check --deploy
```

只报**上线环境**相关的问题（`security.W*`）。实测（实验 45/46）：

```text
安全告警编号 = ['security.W001', 'security.W002', 'security.W003',
                'security.W009', 'security.W012', 'security.W018']
    ✅ --deploy 至少报 DEBUG=True 相关告警
    ✅ 普通 check 不含 security.W 告警
```

含义对照（均来自 Django 官方文档）：

| 编号 | 实测原文的含义 |
|------|------|
| `W001` | 没有 `SecurityMiddleware` → `SECURE_HSTS_SECONDS` 等五个设置**全部无效** |
| `W002` | 没有 `XFrameOptionsMiddleware` → 页面不会有 `x-frame-options` 头（点击劫持） |
| `W003` | 没有 `CsrfViewMiddleware`（DRF 虽自带 exempt，但 Admin 等仍在用 Session） |
| `W009` | `SECRET_KEY` 少于 50 字符 / 少于 5 种字符 / 带 `django-insecure-` 前缀（本课实验工程三者全中） |
| `W012` | `SESSION_COOKIE_SECURE` 不是 True |
| `W018` | **`DEBUG=True`**（上线绝不能有） |

⚠️ 我最初凭印象写的 W002/W003 含义是错的（写成 nosniff 和 CSRF 相关），核对原文后已修正。**这类错误不报错，但会让人修错地方。**

普通 `check` 不报这些，因为开发环境本来就该 `DEBUG=True`。**上线前跑一次 `--deploy`**，这是课 22 的伏笔。

### 3.3.7 必查项 #28 自查（本课执行过程）

按"翻到讲义里每一个 `for` 循环，问循环体里有没有数据库/IO 操作"自查，扫描全部 47 处循环：

**命中的生产代码循环**：

| 位置 | 循环体 | 处理 |
|------|--------|------|
| `payorders.py:77` | `for order in qs.iterator(...)` | ✅ `.iterator()` + 循环外 `flush()` 批量 update |
| `checks_helpers.py:93` | `for f in mdir.glob("0*.py")` | ✅ 只读迁移文件，check 阶段文件数有限 |
| `0002_seed_categories.py` | 种子数据 | ✅ 已用 `bulk_create` + `ignore_conflicts`（课 20 改过） |

**无裸 `except Exception`**：

自查时发现 `checks.py` 有两处，已改为显式类型：

```python
# ❌ 改前
except Exception:
    return errors

# ✅ 改后
except (ImportError, ImproperlyConfigured):
    # ROOT_URLCONF 配错时 check 不该崩——它要做的正是"把问题报出来"
    return errors
```

⚠️ 这里的取舍值得说明：**check 函数本身不应该崩**，否则用户看到的是 traceback 而不是"你的配置有问题"。所以这里需要兜底，但**必须列出具体类型**——`except Exception` 会把 `AttributeError`（自己代码写错了）也一起吞掉，那才是真正的灾难。

---

# 第四幕　实操验证

## 4.0 实验工程

**实验规模**：**52 个实验 / 120 项断言 / 22 个 Django 用例 / 3 个独立进程探针 / 零失败**。

```text
%TEMP%/dj-lesson21-demo/cmdlab/
├── manage.py
├── config/
│   ├── settings.py              # 基础配置（SQLite 文件库）
│   ├── settings_badurls.py      # 对照：异前缀的坏路由顺序
│   ├── settings_shadowed.py     # 对照：同前缀，真遮蔽
│   ├── settings_nomig.py        # 对照：禁用含 RunPython 的 app
│   ├── settings_nochecks.py     # 对照：不注册 checks
│   ├── settings_v1.py / settings_v2.py   # 多版本文档导出
│   ├── settings_dup_first.py    # 对照：同名命令谁赢
│   ├── urls.py                  # ✅ 正确顺序
│   ├── urls_bad.py              # 异前缀坏顺序
│   ├── urls_bad2.py             # 同前缀坏顺序（真遮蔽）
│   └── urls_versioned.py        # 版本化路由
├── apps/
│   ├── labkit.py                # Check 断言器 + Timer（沿用课 20）
│   └── shop/
│       ├── apps.py              # ready() 里 import checks
│       ├── apps_nochecks.py     # 对照：不注册
│       ├── checks.py            # 四条自定义 check
│       ├── checks_helpers.py    # 扫描辅助函数
│       ├── payments.py          # 外部网关（patch 靶子）
│       ├── services.py          # 早绑定 / 晚绑定两种写法
│       ├── factories.py         # factory_boy
│       ├── tests_commands.py    # 14 个命令测试
│       ├── tests_checks.py      # 8 个 check 测试
│       └── management/commands/
│           ├── hello.py         # 知识点 1 骨架演示
│           ├── testhealth.py    # 课 20 体检脚本升级版
│           ├── exportdocs.py    # 课 20 多版本导出升级版
│           ├── payorders.py     # 批处理 + 事务 + 进度
│           └── retcmd.py        # 返回值演示
├── run_lab1.py ~ run_lab4.py    # 实验 1-52
├── probe_command_startup.py     # 启动开销构成
├── probe_check_silent.py        # check 静默对照
├── probe_batch_scale.py         # #28 放大检验
└── count_assertions.py          # 全量回归
```

## 4.1 运行方式

```powershell
$env:PYTHONIOENCODING="utf-8"; $env:PYTHONUTF8="1"
cd "$env:TEMP\dj-lesson21-demo\cmdlab"

# 全量回归（python 请用你自己的虚拟环境解释器）
python count_assertions.py
```

> **关于 `python` 是谁**：本课所有实测数据来自 `dj-course` 虚拟环境的 **Python 3.13.14 / Django 6.1 / Windows 11**（作者本机路径形如 `%USERPROFILE%\.workbuddy\binaries\python\envs\dj-course\Scripts\python.exe`，读者的环境必然不同，所以命令主体一律写 `python`）。你只要保证 `python -c "import django; print(django.get_version())"` 输出 6.1 即可，路径差异不影响任何结论。

```text
【实验脚本】
  ✅ run_lab1.py                        通过  28，失败   0  (exit=0)
  ✅ run_lab2.py                        通过  26，失败   0  (exit=0)
  ✅ run_lab3.py                        通过  27，失败   0  (exit=0)
  ✅ run_lab4.py                        通过  17，失败   0  (exit=0)

【Django 测试】
  ✅ Django 测试（命令 + checks）       用例  22  (exit=0)

【独立进程探针】
  ✅ probe_command_startup.py           (exit=0)
  ✅ probe_check_silent.py              (exit=0)
  ✅ probe_batch_scale.py               (exit=0)

========================================================================
合计：120 项通过，0 项失败
========================================================================
```

# 单个命令试跑
python manage.py testhealth --cases 20 --seed 50
python manage.py exportdocs --api-version v1 --file schema-v1.yaml
python manage.py exportdocs --api-version v1 --file schema-v1.yaml --check
python manage.py check --settings=config.settings_shadowed
```

## 4.2 三个命令的用法

### `manage.py testhealth`

```text
用法：manage.py testhealth [options]

体检：把一次测试跑拆成 建库 / 造数 / 执行 三段分别计时。

options:
  --cases CASES           造多少个空用例（默认 20）
  --seed SEED             造多少条商品（默认 50）
  --warn-setup-ratio R    建库占比超过这个值就告警（默认 0.5）
  --json                  输出 JSON 供 CI 解析
```

### `manage.py exportdocs`

```text
用法：manage.py exportdocs --api-version {v1,v2} --file FILE [--check] [--fail-on-warn]
```

⚠️ `--api-version` 不能写成 `--version`（与 Django 内置选项冲突）。

### `manage.py payorders`

```text
用法：manage.py payorders [--limit N] [--batch-size N] [--dry-run]
                          [--stop-on-error] [--set-status STATUS]
```

## 4.3 实验清单


> **分级说明**：**核心必跑** 6 组是不跑就白学的部分（每组约 1-3 分钟，合计 10 分钟内）；
> **推荐** 是需要理解但看结论也能吸收的；**—** 是本课为完整性补的验证，可以直接采信数据。
> 全量回归（`run_lab1`~`run_lab4` + 22 个 Django 用例 + 3 个探针）本课实测耗时 **64.5 秒**（120 项断言全过）。

| 实验 | 内容 | 关键结论 | 建议 |
|------|------|---------|------|
| 1 | `--verbosity` 三档 | 🔴 **不自动抑制 `stdout.write`** | **核心必跑** |
| 2 | 位置参数与选项 | `--times 3` → 3 行输出 | — |
| 3 | `CommandError` 去向 | 🔴 **不写 stderr**，要用 `assertRaises` | 推荐 |
| 4 | 退出码分级 | 正常 0 / CommandError 1 / argparse 2 | 推荐 |
| 5 | 命令发现机制 | `management/commands/` + app 归属标注 | — |
| 6 | 同名命令谁赢 | `INSTALLED_APPS` 靠前者胜，**参数表也一起换掉** | **核心必跑** |
| 7 | `--help` 自动生成 | 显示 `help` 属性与选项 | — |
| 8 | `self.style` 与 `--no-color` | Windows 下默认无 ANSI | — |
| 9 | `handle()` 返回值 | 会被直接打印 | — |
| 10 | 命令启动耗时 | 约 700ms，绝大部分是 Django 启动 | — |
| 11-13 | 退出码契约 / verbosity / `--json` | CI 三要素 | — |
| 14 | 批处理 SQL 条数 | 100 行 1 条 UPDATE vs 逐条 20 行 20 条 | 推荐 |
| 15 | #28 静态自查 | `.iterator()` + 批量 update + 无裸 except | — |
| 16-17 | `--dry-run` 真的不落库 | 30/30 未变 vs 30 条已付 | 推荐 |
| 18 | 分批进度输出 | **最后一批不足 batch_size 时不打印** | 推荐 |
| 19 | 部分失败行为 | 漏掉 `GatewayError` 会让命令直接崩 | 推荐 |
| 20-21 | `check` 退出码 | Warning **默认不阻断** | **核心必跑** |
| 22 | `--fail-level` | WARNING 档才拦得住 Warning | 推荐 |
| 23-24 | 路由遮蔽 check | 🔴 **判定必须问框架，不能比下标** | **核心必跑** |
| 25-26 | 迁移禁用 check | `auth` / `contenttypes` 也含 RunPython | 推荐 |
| 27 | 字段注解 check | Warning 级，不阻断 | — |
| 28 | schema 同步 check | 🔴 **基准随 settings 变** | 推荐 |
| 29 | `--list` / `--tag` | 按 tag 跑指定 check | — |
| 30 | check 不注册 | **全程静默**（课 17 同款） | **核心必跑** |
| 31-34 | `call_command` 基础 | `skip_checks` 可跳过 checks | — |
| 35-39 | patch 位置四组对照 | 🔴 **打错位置命令会真调外部服务** | **核心必跑** |
| 40 | 业务异常被捕获 | 记下来继续跑，不崩 | — |
| 41-42 | dry-run / 实跑 | 落库差异 | — |
| 43 | `--json` 解析 | 需独立进程（建库与外层事务冲突） | 推荐 |
| 44 | choices 拦非法值 | `--api-version v9` 抛 CommandError | — |
| 45-46 | `--deploy` | 只报 `security.W*`，平时不报 | — |
| 47 | `--skip-checks` 提速 | 706 → 438 ms | — |
| 48 | 幂等性 | 第二次空跑 | 推荐 |
| 49 | `--help` 默认值 | 🔴 **不显示 default，要自己写进 help** | 推荐 |
| 50 | `--no-input` | 🔴 **不是全局选项** | 推荐 |
| 51-52 | check id 规范 / CI 流水线 | 每条命令都有退出码契约 | — |
| 探针 A | 启动开销构成 | Django 启动 402ms + checks 273ms | — |
| 探针 B | check 静默对照 | 注册 4 条 vs 不注册 0 条 | 推荐 |
| 探针 C | #28 放大检验 | 内存 11.6 倍差距（SQL 多 9 条是代价） | 推荐 |

## 4.4 关键量化数据

| 项目 | 数值 |
|------|------|
| 命令启动总耗时 | 632.8 ms |
| Django 启动开销 | 402.5 ms |
| system checks 开销 | 272.9 ms |
| `--skip-checks` 后 | 359.9 ms（省 43%） |
| 批量 update（100 行） | 1 条 UPDATE |
| 逐条 save（20 行） | 20 条 UPDATE |
| `.iterator()` 峰值内存（5000 条） | 0.31 MB |
| `list()` 全量峰值内存（5000 条） | 3.55 MB（**11.6x**） |
| 对应 SQL 条数 | 11 vs 2（iterator 多 9 条） |
| testhealth 三段（20 用例 / 20 条） | 建库 121.0ms (64%) / 造数 67.5ms (36%) / 执行 1.0ms (0.5%) |
| check 注册 vs 不注册 | 报 4 条 vs 报 0 条（退出码 1 vs 0） |

---

# 第五幕　体系收束

## 5.1 决策表：什么时候写命令、什么时候写 check

| 场景 | 用什么 | 判据 |
|------|--------|------|
| 一次性的数据修复 | 命令（带 `--dry-run`） | 要能被重放、能回滚 |
| 定期执行的任务 | 命令（幂等 + cron 友好） | 第二次跑必须是空跑 |
| 给运维用的工具 | 命令（`--help` + verbosity） | 别人要能自己学会用 |
| 团队约定（违反会挂） | check（**Error**） | 会直接导致失败 |
| 团队约定（违反埋雷） | check（**Warning**） | 现在能跑但不该这样 |
| 环境/依赖检查 | check（`--deploy`） | 只在上线时才有意义 |
| 纯文档说明 | 什么都不写 | 机器判断不了的才留给人 |

## 5.2 本课的四条硬结论

1. **`--verbosity` 是钩子不是行为。** 想安静就得自己 gate 每一条输出；`--help` 不会替你写默认值；`--no-input` 不是全局选项；`CommandError` 不写 stderr。
2. **Error / Warning 的判据是"会不会直接导致失败"。** Warning **默认不阻断 CI**，必须显式加 `--fail-level WARNING`。
3. **check 的判定要问框架。** 自己推演的规则（比如下标比较）总会有边界情况没覆盖。让 `resolve()` 自己回答。
4. **`call_command` 里 patch 依然打"使用处"。** 打错位置的测试**依然是绿的**，但命令会真的去调外部服务。

## 5.3 与前面课程的连线

| 本课内容 | 回指 |
|---------|------|
| `testhealth` 三段计时 | 课 20 实验 41（体检 78/18/4） |
| `exportdocs` 多版本 | 课 20 实验 30（`DEFAULT_VERSION` 是导入时快照） |
| 路由遮蔽 check | 课 20 坑 1、课 5（路由遮蔽） |
| 迁移禁用 check | 课 20 实验 19（表在但数据为 0） |
| patch 打使用处 | 课 20 实验 10/11 |
| check 不注册全程静默 | 课 17（信号不注册） |
| 裸 `except Exception` | 课 14/15（连续两课 P0）、必查项 #28 |
| `--no-input` 缺失 | 课 14（`squashmigrations` EOFError） |
| `override_settings` 先验证生效 | 课 19（STORAGES 确实生效） |
| 批处理 `bulk_*` | 课 14/15/17 |

## 5.3.1 往前看：本课给课 22 留下的三个待办

课 22（部署与运行）会接手本课没解决完的三件事，这里先挂上号：

1. **`--deploy` 报的 6 条 `W*` 谁来处理。** 本课实验 45-46 只是**把它们列出来**（`security.W001` / `W002` / `W003` / `W009` / `W012` / `W018`），没讲怎么修 —— 因为它们不是代码问题，是**部署配置问题**：`SECRET_KEY` 从哪注入、`DEBUG` 由哪个环境变量关掉、`ALLOWED_HOSTS` 在 Ingress 后面怎么填。这些要到讲部署形态时才有答案。

2. **命令的启动开销决定了它的部署形态。** 本课实测：命令启动 632.8ms，其中 Django 启动 402.5ms、system checks 272.9ms，加 `--skip-checks` 后降到 359.9ms。这个数字直接决定一件事 —— **它是能当 Web 请求跑，还是只能当定时任务跑**。启动 600ms 的进程塞不进请求链路，但可以每分钟起一次；反过来，如果你的命令只跑 50ms，那启动开销占 92%，就该考虑常驻进程而不是反复冷启动。课 22 讲进程模型时会回到这个数据。

3. **四个命令要进发布流水线。** `testhealth` / `exportdocs` / `payorders` / `hello` 现在只是"能跑"，还没回答"什么时候跑、谁跑、跑了失败怎么办"。课 22 要把它们接进流水线：`check` 进 CI 门禁（Error 阻断、Warning 记账）、`exportdocs` 进构建产物（每次发版导出文档并比对）、`payorders` 进定时任务（退出码进监控）、`testhealth` 进周期性体检（趋势比绝对值有用）。

> 💡 一句话串起来：**本课解决"这条约定有没有人检查"，课 22 解决"检查完了谁来响应"。**

## 5.4 术语表

| 术语 | 直白解释 |
|------|---------|
| `BaseCommand` | 管理命令的基类。继承它、写 `add_arguments` 和 `handle` 就得到一个命令 |
| `add_arguments` | 声明参数的方法。位置参数必填，选项带默认值 |
| `--verbosity` | 0/1/2/3 四档。**它只是个整数，要不要少打印得你自己判断** |
| `CommandError` | 表示"业务失败"的异常，退出码 1。**不写 stderr** |
| `self.style.SUCCESS` | 给输出加颜色。`--no-color` 会去掉 ANSI 转义 |
| System check | Django 启动时（或 `manage.py check` 时）跑的一组校验函数 |
| `Error` / `Warning` / `Info` | check 的三级严重度，常量分别是 **40 / 30 / 20** |
| `--fail-level` | 指定"到哪个级别就开始阻断"。**Warning 默认不阻断** |
| `--deploy` | 只在上线环境跑的那批检查（`security.W*`） |
| `call_command` | 在 Python 里调用命令的函数，可传 `stdout=` / `stderr=` 捕获输出 |
| 早绑定 | `from .payments import charge`——绑定的是函数对象，patch 定义处无效 |
| 晚绑定 | `payments.Gateway.charge(...)`——每次去模块取，patch 定义处有效 |
| 幂等 | 同一个命令跑 N 次与跑 1 次结果相同 |

## 5.5 高频误区表

| 误区 | 真相 |
|------|------|
| "`--verbosity 0` 命令就安静了" | **不自动抑制 `self.stdout.write`**，每条输出都要自己 gate |
| "`--no-input` 是 BaseCommand 自带的" | **不是**。只有可能交互的命令才有（课 14 因此 EOFError） |
| "`--help` 会显示默认值" | **不会**。Django 定制了 help formatter，默认值要自己写进 `help=` |
| "`raise CommandError` 会写 stderr" | **不写**。要用 `assertRaises` 断言，别 grep stderr |
| "Warning 会让 CI 变红" | **不会**。必须显式 `--fail-level WARNING` |
| "check 写在文件里就会跑" | **不 import 就一次都不跑**，且无任何报错（课 17 同款） |
| "路由顺序问题 check 比下标就能查出来" | **会误报**。必须 `resolve()` 问框架 |
| "禁用迁移只禁业务 app 就行" | `auth` / `contenttypes` **也含 RunPython**，禁掉会丢数据 |
| "patch 打在定义处总没错" | 早绑定写法下**无效**，命令会真的去调外部服务 |
| "命令加个 `--dry-run` 就是跳过写库" | 应该是**真的走一遍再回滚**，否则测不到 SQL 对不对 |
| "schema 同步 check 和导出用一个基准就行" | 基准**随 settings 变**，v1 导出的文件在默认 settings 下必然报不一致 |
| "命令可以直接在 TestCase 里 call_command" | 自建库的命令会撞 SQLite 事务限制，要放独立进程 |
| "命令名可以自己指定，文件名无所谓" | **命令名就是文件名**。`pay_orders.py` 只能叫 `pay_orders`，想叫 `pay-orders` 做不到 |
| "命令文件里类名叫什么命令就叫什么" | 类名随意（`Command` 是约定不是强制），**文件名才决定命令名** |

## 5.6 自检题

**A. 判断级别（Error 还是 Warning？）**

1. 项目的 `SECRET_KEY` 是硬编码的 —— **Error**（上线即事故）
2. 有个 serializer 字段没有 `help_text` —— **Warning**（能跑，文档没说明）
3. `DEBUG=True` 且 `ALLOWED_HOSTS=['*']` —— **Error**（`--deploy` 会报）
4. 某个 model 没写 `__str__` —— **Warning**（Admin 显示难看，不影响运行）
5. 手写路径被 router 遮蔽 —— **Error**（接口直接 405）

**B. 动手题**

1. 给你自己的项目加一条 check：要求所有 `ModelViewSet` 必须显式声明 `queryset`（不写会怎样？先跑一次看看）
2. 把你项目里最常用的那个脚本改成命令，加 `--dry-run` 与 `--json`
3. 用 `call_command` 给这个命令写测试，然后**故意把 patch 打在定义处**（`patch("apps.shop.payments.charge")`），跑一遍测试并回答两个问题：(a) 测试是绿还是红？(b) 如果绿，你的命令在这 3 秒里到底做了什么——去 `payments.py` 的 `Gateway.charge()` 里加一行 `print("REAL GATEWAY CALLED")`，再看它打不打印。
   > 提示：答案取决于你的命令是 `from .payments import charge` 还是 `payments.Gateway.charge(...)`。两种写法都试一次，你就再也不会记错这条规则了。

**C. 排障题**

1. cron 里的命令昨天没跑成功，但日志里什么都没有。可能是什么原因？（提示：退出码、`--no-input`、stdout 缓冲）
2. 你的 check 在本地报 Error，CI 上不报。列出三种可能。
   > 方向（答案不唯一，能说出任意两条并指出怎么验证即可）：① **settings 差异** —— 本地 `DEBUG=True` / 装了某个 app / `INSTALLED_APPS` 顺序不同，check 的判定前提就不成立（本课实验 28 就是活例子：schema check 的基准随 settings 变）；② **文件存在性** —— check 依赖某个本地有、CI 上没有的文件（比如导出的 schema 文档没提交进仓库），很多 check 会在文件不存在时直接 `return []` 跳过；③ **`--fail-level` 与 tag 过滤** —— CI 只跑了 `--tag xxx` 或没加 `--fail-level`，你的 check 根本没被执行。
   > 最快的定位手段：在 CI 上跑 `manage.py check --list`，确认你的 check id 在不在列表里 —— 不在就是③或注册没生效（课 17 同款），在就往前查①和②。

## 5.7 事实来源标注

| 结论 | 来源 | 实验 |
|------|------|------|
| `--verbosity` 不自动抑制输出 | **实测** | 1 |
| `--no-input` 非全局选项 | **实测** | 50 |
| `--help` 不显示 default | **实测** | 49 |
| `CommandError` 不写 stderr | **实测** | 33 |
| 退出码 0/1/2 分级 | **实测** | 4、11 |
| 同名命令由 app 顺序决定 | **实测**（+ 参数表一起换） | 6、6b |
| `--version` 与 Django 内置冲突 | **实测**（课 2 同款） | — |
| Warning 默认不阻断 CI | **实测** | 22 |
| check 不注册全程静默 | **实测** | 30、探针 B |
| 路由遮蔽判定必须 resolve | **实测**（第一版误报） | 24 |
| `auth`/`contenttypes` 含 RunPython | **实测**（核查源文件） | 25 |
| schema 基准随 settings 变 | **实测** | 28b |
| patch 早/晚绑定差异 | **实测**（四组对照） | 35-39 |
| `GatewayError` 漏捕获会让命令崩 | **实测**（开发过程真实踩到） | 19 |
| 建库与外层事务冲突 | **实测**（`NotSupportedError`） | 43 |
| 启动开销构成 | **实测**（5 次取最小） | 探针 A |
| `.iterator()` 内存 11.6 倍差距 | **实测**（N=5000） | 探针 C |
| `Error=40 / Warning=30 / Info=20` | **源码**（`django/core/checks/messages.py`） | 46、51、52 |
| `--deploy` 报 `security.W*` | **官方文档**明示 | 45 |

⏳ **未验证**：本课的启动开销数字（402ms / 273ms）来自 Windows + SQLite，在其他平台上量级会不同。**盈亏判断要在你自己的环境上重新量。**

## 5.8 验证环境

| 项目 | 值 |
|------|-----|
| 操作系统 | Windows 11 |
| Python | 3.13.14（Windows 托管，`dj-course` venv） |
| Django | 6.1 |
| DRF | 3.18.0 |
| drf-spectacular | 0.30.0 |
| factory_boy | 3.3.3 |
| PyYAML | 6.0.3 |
| 数据库 | SQLite **文件库**（刻意不用内存库——命令是进程级行为） |

**受限说明**：

1. **未用 WSL**（本机安全策略拦截），命令均为 PowerShell 形式
2. **未接真实 cron**，幂等性用"连跑两次"模拟
3. **未测真实外部服务**，`Gateway.charge` 是可注入失败率的假实现
4. **放大检验只跑到 5000 条**（10 万条太慢），趋势外推已在正文标注为外推
5. **未装 `django.contrib.staticfiles`**，所以无 `collectstatic` 命令可对照

## 5.9 坑位记录

⚠️ **环境与工具坑（与 Django 知识无关，但最费时间）**

1. **⏱️ 中文引号导致 `SyntaxError`** —— `print("...'上线才查'...")` 连用中文引号会报 `SyntaxError: invalid syntax`。改用 `『』`。**课 17、19 已踩过两次，本课第三次。**
2. **⏱️ Windows 控制台 GBK 编码** —— 中文输出必须设 `$env:PYTHONIOENCODING="utf-8"`，否则 `UnicodeEncodeError`。
3. **⏱️ 含中文的 Python 文件不能用 PowerShell 管道修改** —— `(Get-Content) -replace | Set-Content` 会破坏 UTF-8，**症状极隐蔽**：模块导入失败，导致命令"没跑"却看起来正常。
4. **`--version` 与 Django 内置选项冲突** —— 报 `argparse.ArgumentError: conflicting option string`，改成 `--api-version`。
5. **数据迁移生成顺序** —— `makemigrations` 会因 `0002` 依赖 `0001` 而报 `NodeNotFoundError`，要先移出 `0002` 再生成。
6. **`admin.W411` 告警** —— TEMPLATES 缺 `django.template.context_processors.request`。
7. **子进程 `cwd`** —— 测试里起子进程必须用 `settings.BASE_DIR`，否则拿到空输出。
8. **`@action(url_path="summary")` 会掩盖遮蔽实验** —— router 自己生成了 `orders/summary/`，实验变成"两个 summary 抢同一个 URL"。要移除它才能复现课 20 坑 1 的经典形态。

## 5.10 本课核心收获

| # | 收获 | 出处 |
|---|------|------|
| 1 | 🔴 **`--verbosity` 不自动抑制输出** —— 它是钩子不是行为 | 实验 1 |
| 2 | 🔴 **`--no-input` 不是全局选项** —— 只有交互命令才有 | 实验 50 |
| 3 | 🔴 **`--help` 不显示默认值** —— 要自己写进 `help=` | 实验 49 |
| 4 | 🔴 **`CommandError` 不写 stderr** —— 测试要用 `assertRaises` | 实验 33 |
| 5 | 🔴 **check 判定必须问框架** —— 比下标会误报，要 `resolve()` | 实验 24 |
| 6 | **Warning 默认不阻断 CI** —— 必须 `--fail-level WARNING` | 实验 22 |
| 7 | **check 不注册全程静默** —— 退出码 0，一条不报 | 实验 30 |
| 8 | **patch 打错位置，测试依然绿** —— 但命令真的调了外部服务 | 实验 39 |
| 9 | **漏捕获 `GatewayError` 会让命令直接崩** —— 显式列出异常类型 | 实验 19 |
| 10 | **命令启动 632ms，其中 checks 占 273ms** —— 决定调度频率 | 探针 A |
| 11 | **`.iterator()` 内存是 1/11.6** —— 代价是多 9 条 SQL，值得 | 探针 C |
| 12 | **`auth` / `contenttypes` 也含 RunPython** —— 禁用会丢数据 | 实验 25 |

---

## 5.11 本课的质量门禁（评审结论，对学员可见）

本课交付前经过**双视角交叉评审**（pedagogy 视角看"教得对不对、够不够"，learner 视角看"零基础读者照着做能不能跑通"），评审是**逐字执行讲义里的每条命令**完成的，不是通读一遍。

- **P0（必须修，否则不能交付）：0 条**
- **P1（ pedagogy 视角，4 条）**：①第一幕没给"改造前"的脚本形态 → 补约 20 行原文与四类缺陷表；②缺"怎么确认命令生产可用" → 新增 3.1.7 节七条自检清单；③check 级别判据太绝对 → 3.2.2 补灰色地带与团队 A/B 对照；④缺与下一课的衔接 → 新增 5.3.1 节三个待办。**已全修**
- **P2（pedagogy 视角，3 条）**：2.6 节补"扩展点 vs 默认行为"；自检题 B-3 改为动手任务；4.3 实验清单改三级分级。**已全修**
- **L1（learner 视角，4 条）**：3.1 开头先讲"命令放在哪、叫什么名字"；3.3.2 补 patch 定位三步骤；3.2.3 补 `app_configs` 参数与 None 陷阱；4.1 去掉写死的本机绝对路径。**已全修**
- **L2（learner 视角，4 条）**：1.1 运维对话改具体；5.5 补"命令名=文件名"；C-2 给方向性答案；4.3 标出全量回归耗时 64.5 秒。**已全修**

**评审中抓出的两处硬伤**（都不是措辞问题，是事实问题）：

1. **`--deploy` 的告警编号我最初凭印象写错了。** 第一稿写了四条编号，实测跑出来是**另外六条**（W001 / W002 / W003 / W009 / W012 / W018），而且其中两条的含义也写反了。已按实测原文全部修正——这条同时说明为什么"结论必须本机实测"是硬约束：**凭印象写编号，写出来的东西会读着很专业但全是错的**。
2. **路由遮蔽 check 的第一版会误报。** 我最初只比较 urlpatterns 里的下标，异前缀场景（`/api/orders/create/` vs `/api/products/`）会被误判为遮蔽。改为 `resolve()` 问框架"这个 URL 真正落到谁身上"，并专门新建了一个同前缀真遮蔽的对照组验证它确实报得出来。

**验证状态**：全量回归 120 项断言零失败（52 实验 + 22 个 Django 用例 + 3 个独立进程探针），全仓 59 文件 / 179 条本地链接零断链，终检全绿。

---

## 🚀 下一批接力提示词

> 下一课：课 22《部署与运维》（**本阶段最后一课**，阶段 6 共 5 课，本课是 5/5）。
>
> 带上这三个问题：
> 1. **本课的检查清单该进 `--deploy`** —— 本课实验 45 实测 `--deploy` 报出了 6 条 `security.W*`：W001（缺 `SecurityMiddleware`，那五个 `SECURE_*` 设置全部无效）/ W002（缺 `XFrameOptionsMiddleware`）/ W003（缺 `CsrfViewMiddleware`）/ W009（`SECRET_KEY` 不合格）/ W012（`SESSION_COOKIE_SECURE` 未开）/ W018（`DEBUG=True`）。课 22 讲部署检查清单时，请逐条解释**每一条在 prod 环境意味着什么**、怎么修，并补上 check 覆盖不到的部分（密钥管理、监控、备份）
> 2. **本课的"启动开销"决定了部署形态** —— 探针 A 实测一次 `manage.py` 要 632ms，其中 Django 启动 402ms、system checks 273ms。课 22 讲部署拓扑时，请回答：哪些任务该常驻（worker / beat）、哪些该起进程、`--skip-checks` 在生产能不能用
> 3. **本课的四个命令是运维入口** —— `testhealth` / `exportdocs` / `payorders`，加上课 20 的三个提速手段。课 22 讲上线流程时，请把它们排进一个真实的发布流水线（pre-deploy / deploy / post-deploy），并说明每一步失败了该回滚到哪里
>
> 提示：本课实验工程在 `%TEMP%/dj-lesson21-demo/cmdlab`，四个命令与四条 check 都可直接复用；`config/settings_shadowed.py` / `settings_nomig.py` / `settings_nochecks.py` 三个对照 settings 是"用配置隔离做 A/B"的现成范例，课 22 做环境差异对照时可以照搬。
>
> ⚠️ 环境提醒：Windows 下跑实验前必须设 `$env:PYTHONIOENCODING="utf-8"`；含中文的 Python 文件**不要用 PowerShell 管道修改**；Python 里写中文字符串时**不要用中文引号**（本课第三次踩到，用 `『』` 代替）。

---

## 🧭 课程导航

- ⬅️ 上一课：[课 20《测试提速与文档》](./lesson-20-测试提速与文档.md)
- ➡️ 下一课：[课 22《部署与运维》](./lesson-22-部署与运维.md)
- 📖 阶段概览：[阶段 6：工程化与生产](../overview.md)
- 📚 课程目录：[02-课程目录.md](../../../02-课程目录.md)
- 🏠 学习路径：[01-学习路径总览.md](../../../01-学习路径总览.md)

> 📌 **阶段 6 进度**：课 18、19、20、21 已完成（4/5）。下一课为课 22《部署与运维》。
