# 课 22　部署与运维

> **阶段 6《工程化与生产》第 5 课（5/5）｜全课程最后一课**
>
> 本课要回答的三个问题（来自课 21 的接力）：
> 1. **课 21 的检查清单该进 `--deploy`** —— 课 21 实验 45 实测 `--deploy` 报出 6 条 `security.W*`。本课逐条解释每一条在生产意味着什么、怎么修，并补上 check 覆盖不到的部分（密钥管理、监控、备份）
> 2. **课 21 的"启动开销"决定了部署形态** —— 探针 A 实测一次 `manage.py` 要 632ms。本课回答：哪些任务该常驻（worker / beat）、哪些该起进程、`--skip-checks` 在生产能不能用
> 3. **课 21 的四个命令是运维入口** —— 把它们排进真实的发布流水线（pre-deploy / deploy / post-deploy），并说明每一步失败了该回滚到哪里

---

# 第一幕　场景引入：上线前那个"应该没事吧"

## 1.1 周五下午六点的一次发布

**你**：配置都改好了，跑一遍检查。

```powershell
python manage.py check --deploy
```

```text
System check identified no issues (0 silenced).
```

**你**：全绿。发吧。

---

**二十分钟后，群里炸了。**

> **运维**：后台登录不上了，一直跳回登录页。
> **你**：……我看看。本地明明好的。
> **运维**：还有，用户头像全挂了。
> **你**：？
> **运维**：还有个更怪的 —— 用 HTTPS 访问一直在重定向，浏览器报"重定向次数过多"。

你打开生产配置，逐行看：

```python
DEBUG = False
SECRET_KEY = os.environ["SECRET_KEY"]
ALLOWED_HOSTS = ["api.example.com"]
STATIC_URL = "/static/"
MEDIA_URL = "/media/"
SESSION_COOKIE_SECURE = True
SECURE_SSL_REDIRECT = True
```

**每一行都是对的。**

- `check --deploy` 全绿 ✅
- 迁移跑完了 ✅
- `collectstatic` 跑完了，157 个文件 ✅
- 进程起来了，健康检查 200 ✅（**一个只返回 `{"status":"ok"}` 的 `/health/` 端点** —— 它不查数据库，所以后面那三个问题它一个都发现不了）

**三个问题，全都出在 check 看不见的地方。**

## 1.2 这三个问题，check 一条都查不出来

| 现象 | 根因 | `check --deploy` 能查吗 | 在哪一节解决 |
|------|------|------------------------|-------------|
| 登录一直跳回登录页 | 新机器**没有 `SECRET_KEY` 环境变量** → 每次进程重启生成新密钥 → 所有 session 作废 | ❌ 查不到。`SECRET_KEY` 为空时 `manage.py check` **退出码 0，一句话不说**（实验 5-8） | 3.1.3 / 3.1.4 |
| 用户头像全挂 | `DEBUG=False` 后 Django **不托管 `/media/`**，而 Nginx 没配这个 location | ❌ 查不到。这是**部署拓扑**问题，不是 Django 配置问题 | 3.2.1 / 3.2.3 |
| HTTPS 无限重定向 | `SECURE_SSL_REDIRECT=True` 但**没配 `SECURE_PROXY_SSL_HEADER`** → Django 不知道前面有 Nginx，把每个请求都当 HTTP | ❌ 查不到。两个设置**都是对的**，错的是它们的组合 | 3.2.5 |

**最要命的是第一个。**

`SECRET_KEY` 没配，Django 不报错。你跑 `check`、跑 `check --deploy`、跑 `migrate`、跑 `collectstatic`——**全部退出码 0**。进程也能起来，健康检查也能过。

直到第一个用户点登录，签名 session 的那一行代码执行到，`ImproperlyConfigured` 才炸出来。而如果 session 用的是别的存储方式，它可能连炸都不炸，只是**每个人登录完刷新一下就掉线**。

## 1.3 本课要解决的事

前面四课，我们让代码变得**可观测**（课 18）、**可维护**（课 19/20）、**可检查**（课 21）。

这一课面对的是最后一公里：**代码离开你的机器之后，会发生什么。**

它分三块：

1. **配置管理与密钥**（知识点 1）—— 环境变量怎么读才不会读反、`SECRET_KEY` 是什么、轮换一次会死多少数据（**对应故障①**）
2. **静态资源与前后端联调部署**（知识点 2）—— `/static/` 和 `/media/` 到底该谁提供、`DEBUG` 一变哪些 URL 会变、反向代理后面怎么配（**对应故障②③**）
3. **生产部署与上线清单**（知识点 3）—— 什么该常驻什么该起进程、发布流水线怎么排、每一步失败回滚到哪里（**这三个故障本都该被它拦住**）

> 💡 一句话概括本课：**前面四课解决"代码对不对"，本课解决"环境对不对"。**
> 而环境错了最难受的地方在于 —— **它通常在代码全对的情况下发生。**

---

# 第二幕　认知冲突：你以为的，和实测出来的

课 21 的五个冲突，共同点是"Django 提供扩展点而非默认行为"。

本课的冲突换了个方向：**它们全都是"看起来对、跑起来错"，而且不报错。**

## 2.1 冲突一：`DEBUG=False` 会让 DEBUG 变成 False 吗？

生产环境，你在服务器上设了环境变量：

```powershell
$env:DEBUG = "False"
```

然后 settings 里这么写：

```python
DEBUG = bool(os.getenv("DEBUG", ""))
```

**你以为 `DEBUG` 是 `False`。实测：**

```text
环境变量          bool(os.getenv)      白名单解析
--------------- ------------------ --------------
未设置                     False          False
DEBUG=False                True           False
DEBUG=0                    True           False
DEBUG=1                    True           True
```

（实验 3-4 实测）

**`DEBUG=False` 和 `DEBUG=0` 全都被解析成了 `True`。**

因为 `os.getenv` 返回的是**字符串**。`"False"` 是非空字符串，`bool("False")` 就是 `True`。`"0"` 同理。

**这意味着什么**：你以为关掉了 DEBUG，实际上生产环境正在跑 DEBUG=True。用户的每一次报错都会把完整的堆栈、SQL、环境变量打在浏览器上——而你的监控面板一片绿，因为 `check --deploy` 在你本地跑的时候是好好的。

> ⚠️ 这不是危言耸听。`bool(os.getenv(...))` 是这个领域最常见的写法，因为它看起来"很合理"。

## 2.2 冲突二：`SECRET_KEY` 没配，Django 会告诉我吗？

**你以为**：缺这么重要的配置，启动肯定会报错。

**实测**（实验 5-8）：

```text
$ manage.py check                                    -> rc=0
   'System check identified no issues (0 silenced).'

$ manage.py check --deploy                           -> rc=0

$ manage.py shell -c "print('import ok')"            -> rc=0

$ manage.py shell -c "Signer().sign('x')"            -> rc=1
   django.core.exceptions.ImproperlyConfigured:
   The SECRET_KEY setting must not be empty.
```

**前三个全是 0。只有第四个，在你真正用到签名的那一瞬间，才炸。**

`check` 不报错，是因为它压根没检查这一项。`--deploy` 也不报——它会报 `security.W009`（"你的 SECRET_KEY 太短"），但那是**密钥存在但太弱**的情况；**密钥压根不存在**，它不查。

所以一开头那个"登录一直掉线"的故事，真相是：**进程起来了，`SECRET_KEY` 是空的，没人发现，直到有人登录。**

## 2.3 冲突三：`--skip-checks` 能给 `check` 命令加速吗？

课 21 说过命令启动要 632ms，其中 system checks 占 273ms。那给 `check` 命令自己加 `--skip-checks`，是不是能省下这 273ms？

**实测**（实验 31a）：

```text
$ manage.py check --skip-checks
  rc=2
  manage.py check: error: unrecognized arguments: --skip-checks
```

**退出码 2，参数根本不存在。**

看源码就明白了：

```python
# django/core/management/base.py —— BaseCommand.create_parser()
if self.requires_system_checks:
    parser.add_argument(
        "--skip-checks",
        action="store_true",
        help="Skip system checks.",
    )
```

**`--skip-checks` 只在 `requires_system_checks` 非空时才注册。** 而 `check` 命令自己就是跑检查的，它把 `requires_system_checks` 设成了 `[]`——所以它压根不接受这个参数。

> 🔴 这个是我在备课时踩到的：我第一次测的时候拿 `check` 命令做基准，测出"`--skip-checks` 省了 41%"，差点写进讲义。**那 41% 是 argparse 快速失败省下来的时间，不是跳过检查省下来的。** 换成真正跑 check 的命令（`exportdocs`）重测，实际只省 10%（实验 32）。

## 2.4 冲突四：静态文件是谁在提供？

**你以为**：`DEBUG=True` 时 `staticfiles` 自动托管 `/static/`，所以 `DEBUG=False` 就不托管了。

**实测**（实验 15）：`DEBUG=True` 时，URLconf 里**根本没有 `/static/` 这条路由**。

```text
DEBUG = True
staticfiles 已装 = True
URLconf 里的全部 pattern:
     admin/
     api/orders/summary/
     api/schema/
     api/
含 static 路由 = False
```

那为什么本地开发的时候 `/static/` 能访问？看 `runserver` 的源码：

```python
# django/contrib/staticfiles/management/commands/runserver.py
def get_handler(self, *args, **options):
    handler = super().get_handler(*args, **options)
    use_static_handler = options["use_static_handler"]
    insecure_serving = options["insecure_serving"]
    if use_static_handler and (settings.DEBUG or insecure_serving):
        return StaticFilesHandler(handler)
    return handler
```

**是 `runserver` 这个命令在 WSGI handler 外面包了一层 `StaticFilesHandler`，不是 URLconf 里有路由。**

这个区别非常重要，因为它意味着三件事：

1. **只有 `runserver` 能这么做。** 换成 gunicorn / uwsgi / waitress，`StaticFilesHandler` 就不存在了，哪怕 `DEBUG=True`。
2. **`DEBUG` 只是 `runserver` 的判断条件之一。** 你可以用 `runserver --nostatic` 关掉，也可以用 `runserver --insecure` 在 `DEBUG=False` 下强行开。
3. **生产环境无论如何都不该由 Django 提供静态文件**，这不是"性能不好"，是 Django 一开始就没打算干这件事。

## 2.5 冲突五：`--fail-level WARNING` 是好的 CI 门禁吗？

课 21 说过：只有 Warning 时退出码是 0，想让 CI 拦住必须加 `--fail-level WARNING`。

那生产配置下加这句，应该全绿吧？

**实测**（实验 43）：

```text
$ manage.py check --deploy --fail-level WARNING
  rc=1
  WARNINGS:
  ?: (lab_docs.W001) schema.yaml 与当前代码不一致
  ?: (lab_docs.W002) 14/16 个序列化器字段缺 help_text
```

**6 条 `security.W*` 一条都没有了**（生产配置已修好），**但被课 21 自己写的两条 check 拦住了。**

这不是 bug，但说明一件事：**`--fail-level` 是全局的，它分不清"安全问题"和"文档没同步"。**

正确做法是用 `--tag` 分开（实验 43b）：

```text
$ check --deploy --tag security --fail-level WARNING   -> 只查安全项
$ check --deploy --tag lab_docs --fail-level WARNING   -> 只查文档项
```

安全项该阻断，文档项该记账。混在一起，你的流水线会一直红，然后被人习惯性忽略。

## 2.6 五个冲突的共同点

| 冲突 | 你以为 | 实测 | 报错了吗 |
|------|--------|------|---------|
| `DEBUG=False` | DEBUG 是 False | **是 True** | 没报 |
| 缺 `SECRET_KEY` | 启动会报错 | **rc=0，用到才炸** | 没报 |
| `check --skip-checks` | 能加速 | **参数不存在，rc=2** | 报了（但是另一种错） |
| 静态文件 | DEBUG 控制托管 | **runserver 控制托管** | 没报 |
| `--fail-level WARNING` | 是好的门禁 | **误伤非安全项** | 没报 |

**五个里四个不报错。**

这就是部署这件事最难受的地方：**代码全对，环境错了，而没有任何东西告诉你。**

**再往下一层看，这五个里其实分两类**：

| 类型 | 哪些 | 特点 |
|------|------|------|
| **归因错误**（现象对，原因错） | 2.1、2.3、2.4 | 你知道 `DEBUG` 该关、知道 check 该跳过、知道该有 `/static/` 路由 —— **错的不是知识，是"为什么会这样"** |
| **知识缺失** | 2.2、2.5 | 你压根不知道 `SECRET_KEY` 缺失不报错、不知道 `--fail-level` 是全局的 |

**归因错误比知识缺失更难修。** 因为现象的"正确性"会一直在支持你的错误归因——开发时 `/static/` 确实能访问，所以你以为机制是"DEBUG 控制托管"，而真相是"runserver 控制托管"，两者在开发环境下**表现完全一致**。

> 💡 这也是为什么本课每个冲突都给了源码或实验输出：**只讲结论，你会把它归到已有的（错误的）心智模型里；把证据摆出来，才能逼你自己修正归因。**

课 21 那句判据在这里依然成立 —— 把相关代码全删掉，没报错只是"少了一点效果"，那就是扩展点。**但部署领域的扩展点有个更坏的性质：它连"少了一点效果"你都看不出来，因为少了的那个效果要到生产流量进来才显现。**

> 💡 所以本课的方法论只有一条：**凡是你没法在上线前验证的东西，就得设计成"上线瞬间就会暴露"的形式。**
> 比如让进程在缺 `SECRET_KEY` 时立刻拒绝启动，而不是等到有人登录。这个写法下面 3.1.3 会给。

---

# 第三幕　层层揭示：配置、资源与部署形态

## 3.1 知识点 1：配置管理与密钥

### 3.1.1 环境变量的真值陷阱

先看清问题。`os.getenv` 返回的一定是字符串（或 `None`），而**任何非空字符串的布尔值都是 `True`**：

```text
raw           = 'False'
bool(raw)     = True
raw == 'True' = False
in 白名单     = False
```

（实验 1-2）

三种写法的实测对照（实验 3-4）：

| 环境变量 | `bool(os.getenv("DEBUG", ""))` | 白名单解析 |
|----------|-------------------------------|-----------|
| 未设置 | False | False |
| `DEBUG=False` | **True** ❌ | False ✅ |
| `DEBUG=0` | **True** ❌ | False ✅ |
| `DEBUG=1` | True ✅ | True ✅ |

**错误的写法**（两种都错）：

```python
# ❌ 错法一：非空字符串一律为真
DEBUG = bool(os.getenv("DEBUG", ""))

# ❌ 错法二：只认 'True'，DEBUG=1 会漏
DEBUG = os.getenv("DEBUG") == "True"
```

**正确的写法**：

```python
import os


def env_bool(name, default=False):
    """把环境变量解析成布尔值。

    要点：① 认一批"真"的写法；② 认不出来就返回 default；
    ③ default 取安全的那个方向（这里默认关）。
    """
    raw = os.environ.get(name)
    if raw is None:
        return default
    return raw.strip().lower() in ("1", "true", "yes", "on")


DEBUG = env_bool("DEBUG", False)
```

> 💡 **为什么默认值要取"关"**：这样即使环境变量忘了配，你得到的是安全的那个状态。反过来写 `default=True`，忘配就等于开着 DEBUG 上线。

**怎么确认它真的生效了**（必查项 #11）：

```powershell
python manage.py shell -c "from django.conf import settings; print('DEBUG =', settings.DEBUG)"
```

别信你的环境变量，要看 Django 实际读到的值。这条对下面所有配置都适用。

### 3.1.2 配置分层的三种做法

讲密钥之前，先说 settings 怎么组织。常见三种：

| 做法 | 形态 | 适用 | 代价 |
|------|------|------|------|
| 多文件 | `settings/base.py` + `local.py` + `prod.py` | 团队项目，配置差异大 | 文件多，import 链要理清 |
| 单文件 + 环境变量 | 一个 `settings.py`，差异全靠 `os.environ` | 小项目、容器化部署 | 配置散落，看不出某环境长什么样 |
| 多文件 + 环境变量兜底 | 分文件，但敏感值从环境读 | **推荐** | 两端都要维护 |

本课实验工程用的是第三种 —— `config/settings.py`（开发）与 `config/settings_prod.py`（生产）分开，而 `SECRET_KEY` / `ALLOWED_HOSTS` 这些从环境变量读。

**关键约束：settings 里不要出现任何密钥字面量。** 判断标准很简单 —— 这个文件能不能安全地提交到公开仓库？不能，就说明有东西该挪走。

### 3.1.3 `SECRET_KEY` 是什么，缺了会怎样

一句话：**它是 Django 所有"防篡改"能力的根密钥。**

具体用它签名的地方：

- **session cookie**（如果你用 signed_cookies 后端）与 session 数据
- **密码重置链接**里的 token
- **`messages` 框架**（那个"操作成功"提示）
- **`get_signed_cookie()` / `dumps()` / `loads()`**
- **CSRF token**（部分场景）

所以"缺了会怎样"这个问题，实测答案是（实验 5-8）：

```text
$ manage.py check                          -> rc=0   ← 不报
$ manage.py check --deploy                 -> rc=0   ← 不报
$ manage.py shell -c "print('ok')"         -> rc=0   ← 不报
$ manage.py shell -c "Signer().sign('x')"  -> rc=1
   ImproperlyConfigured: The SECRET_KEY setting must not be empty.
```

**只有真正签名时才炸。**

这就是开头那个事故的机制。所以正确的做法是**别让进程带病启动** —— 在 settings 里主动检查：

```python
# settings.py
import os


def env_bool(name, default=False):
    raw = os.environ.get(name)
    if raw is None:
        return default
    return raw.strip().lower() in ("1", "true", "yes", "on")


DEBUG = env_bool("DEBUG", False)          # ← 必须先有这一行

SECRET_KEY = os.environ.get("SECRET_KEY")

if not SECRET_KEY:
    if not DEBUG:
        # 生产环境缺密钥：立刻失败，不要带病启动
        raise RuntimeError(
            "生产环境必须提供 SECRET_KEY 环境变量，且长度 >= 50、"
            "不能是自动生成的 'django-insecure-' 前缀。"
        )
    SECRET_KEY = "dev-only-insecure-key-do-not-use-in-production"
```

**这个 `raise` 是本课最重要的一段代码。**

它把"上线 20 分钟后才发现"变成了"进程起不来，发布流水线当场失败"。用一次快速的、响亮的失败，换掉一次缓慢的、安静的失败。

> ⚠️ **照抄时注意两点**：
> ① 这段必须放在 `DEBUG` 定义**之后** —— 它靠 `DEBUG` 判断是不是生产环境；
> ② `DEBUG` 必须用 3.1.1 的 `env_bool` 解析。**如果这里写成 `bool(os.getenv("DEBUG"))`，`DEBUG` 恒为 True，这段检查就永远不会触发** —— 用错误的方式实现一个正确的检查，等于没检查。
>
> 另外注意判据本身：只在 `not DEBUG` 时抛。开发环境允许用固定值，否则每次跑测试都要配环境变量。

**怎么确认它真的生效了**：

```powershell
# 不设 SECRET_KEY，应该起不来
python -c "import os,django; os.environ['DJANGO_SETTINGS_MODULE']='config.settings_prod'; django.setup()"
# 期望：RuntimeError: 生产环境必须提供 SECRET_KEY 环境变量...
```

### 3.1.4 轮换一次密钥，会死多少数据

假设你的密钥泄露了（员工离职、误传公开仓库、日志打了出来）。你要换掉它。

**换掉之后，这些东西会立刻全部失效**（实验 9-11）：

```text
普通签名     -> BadSignature
时间戳签名   -> BadSignature
签名 cookie  -> BadSignature
```

翻译成业务语言：

- **所有已登录用户掉线**（session 签名作废）
- **所有已发出的密码重置链接作废**
- **所有购物车 / 未登录态的临时数据作废**

如果这些你都能接受，直接换就行。如果用户正在下单，就得用官方给的方案。

**`SECRET_KEY_FALLBACKS`：无痛轮换**

Django 支持一个"旧密钥列表"，只用来**解密**，不用来**加密**：

```python
SECRET_KEY = "新的密钥"
SECRET_KEY_FALLBACKS = [
    "上一个密钥",
    "上上一个密钥",
]
```

实测（实验 12-14）：

```text
带 fallback 解旧签名   = order-42      ← 旧签名仍可解
撤掉 fallback 解旧签名 = BadSignature  ← 撤掉就立刻失效
新签名在新 key 下      = order-99      ← 新签的一直用新 key
```

**轮换流程**：

1. 生成新密钥，放进 `SECRET_KEY_FALLBACKS`（此时主密钥还是旧的）
2. 发版，等所有实例都读到新配置
3. 把新密钥挪到 `SECRET_KEY`，旧密钥移到 `SECRET_KEY_FALLBACKS`
4. 再发一次版
5. 等一个周期（比如 session 有效期 + 密码重置链接有效期），把旧密钥从 `FALLBACKS` 里删掉

第 5 步的等待期不能省 —— 它决定了"旧签名的东西还能用多久"。

**等待期怎么算**：取所有"用旧密钥签出来的东西"的**最长有效期**：

```text
等待期 = max(
    SESSION_COOKIE_AGE,          # 实测 1209600 秒 = 14 天
    PASSWORD_RESET_TIMEOUT,      # 实测 259200 秒 = 72 小时
    你自己用 dumps() 签的业务数据的过期时间,
)
```

> ⚠️ **这两个默认值是实测的**（`shell -c "print(settings.SESSION_COOKIE_AGE, settings.PASSWORD_RESET_TIMEOUT)"`），不是查文档得来的。改过这两个设置的项目，要按你自己的值算。
> 另外注意：**`PASSWORD_RESET_TIMEOUT_DAYS` 在新版本里已经不存在了**（实测 `ImportError`），只有 `PASSWORD_RESET_TIMEOUT`（单位是秒）。网上很多旧教程还在写前者。

本工程的等待期就是 **14 天**（由 `SESSION_COOKIE_AGE` 决定）。撤早了，第 14 天登录的那些用户会掉线；撤晚了，泄露窗口就多开一天。

> ⚠️ **轮换解决不了"密钥已经泄露"这件事本身。** 它只是止损。真正要防的是泄露：密钥进环境变量 / 密钥管理服务，**不进代码、不进镜像、不进日志**。

### 3.1.5 密钥该放哪儿

从差到好：

| 方案 | 问题 |
|------|------|
| 写死在 settings | 进仓库，一次误传公开就完了 |
| `.env` 文件放服务器 | 文件可能被备份、被打包进镜像 |
| 环境变量 | ✅ 及格线。缺点：进程内可见、`docker inspect` 能看到 |
| 密钥管理服务（Vault / 云厂商 KMS / Kubernetes Secret） | ✅ 推荐。有审计、有轮转、有权限控制 |

**一条硬规则：密钥绝不进版本库。** 哪怕仓库是私有的——私有仓库会变公开，离职员工有拷贝，CI 日志会打印。

配套的：

```gitignore
.env
*.env
!.env.example
```

只提交 `.env.example`（列出变量名，不列值），让下一个人知道要配什么。

### 3.1.6 check 覆盖不到的部分

`--deploy` 能查配置，但有三大类它**查不了**：

| 类别 | 为什么查不了 | 怎么补 |
|------|-------------|--------|
| **密钥管理** | check 只判断"密钥够不够强"，不知道它从哪来、有没有泄露 | 密钥进密钥管理服务；仓库扫描（gitleaks / trufflehog）进 CI |
| **监控** | 完全是应用之外的东西 | 上线清单里必须有一栏"监控是否就位"，人工确认 |
| **备份** | check 连不上你的备份系统 | 定期演练恢复（不是定期备份 —— 没验证过恢复的备份等于没有） |

**这三类里，备份最容易被忽略，也最致命。**

差别在这儿：

- **备份**：`pg_dump` 每天跑，文件堆在磁盘上 —— 看起来在做事
- **恢复**：有没有人真的拿某个备份文件还原过一次，并验证数据是对的？

没做过恢复演练的备份，和没备份的区别只在于**前者让你以为自己安全**。

---

## 3.2 知识点 2：静态资源与前后端联调部署

> 本节回指课 19（文件存储与 Admin）。课 19 讲"上传成功但下载 404"的根因是 `django.conf.urls.static()` 只在 `DEBUG=True` 时挂载；本课把它放到完整部署拓扑里看。

### 3.2.1 三类文件，三个去处

前后端分离项目里有三类文件，容易混：

| 类别 | 是什么 | 谁提供 | 配置项 |
|------|--------|--------|--------|
| **static** | 代码自带的：Admin 的 CSS/JS、DRF 的样式 | 构建期 `collectstatic` 收集，由 **Nginx / CDN** 提供 | `STATIC_URL` / `STATIC_ROOT` |
| **media** | 用户上传的：头像、附件 | **Nginx / 对象存储** 提供 | `MEDIA_URL` / `MEDIA_ROOT` |
| **前端产物** | React / Vue 构建出来的 `index.html` + bundle | **Nginx** 直接提供，Django **完全不参与** | 无（Django 侧无配置） |

**第三类是最容易被搞混的。** 前后端分离之后，前端产物跟 Django 没有任何关系——它不需要 `collectstatic`，不需要进 `STATIC_ROOT`，Django 甚至不知道它存在。

典型的生产拓扑：

```text
                    ┌─────────────┐
   /api/*  ───────► │   Nginx     │ ──────► gunicorn/uwsgi ─────► Django
   /admin/* ──────► │             │
   /static/* ─────► │  (直接读盘) │ ──────► /var/www/static/
   /media/* ──────► │  (直接读盘) │ ──────► /var/www/media/
   /* ───────────► │             │ ──────► /var/www/frontend/  (前端产物)
                    └─────────────┘
```

**只有 `/api/` 和 `/admin/` 走到 Django。**

> ⚠️ **一个容易漏的依赖**：`/admin/` 除了要转发到 Django，**还必须能访问 `/static/`** —— Admin 的 CSS/JS 全在静态文件里。
> 只配了 `/admin/` 转发，结果是"Admin 能打开但没样式"：页面能登录、能用，但全部元素挤在左上角。这是前后端分离项目里最常见的 Admin 部署故障，因为它**看起来是好的**。

### 3.2.2 `/static/` 到底谁在提供

前面 2.4 已经把机制讲清楚了，这里给结论：

```python
# django/contrib/staticfiles/management/commands/runserver.py
if use_static_handler and (settings.DEBUG or insecure_serving):
    return StaticFilesHandler(handler)
```

**三个推论**：

1. **开发时**：`runserver` 包一层 `StaticFilesHandler`，`/static/` 能用。URLconf 里没这条路由（实测）。
2. **生产时**：你用 gunicorn/uwsgi/waitress，`StaticFilesHandler` 不存在，`/static/` 必然 404（实测实验 16）。
3. **想在生产强行让 Django 提供**：`python manage.py runserver --insecure`。**别这么干**——单线程、无缓存、无 gzip，性能灾难。

**`collectstatic` 干什么**：把 `INSTALLED_APPS` 里各个 app 的 `static/` 目录，加上 `STATICFILES_DIRS`，**复制**到 `STATIC_ROOT` 这一个地方，交给 Nginx。

```powershell
python manage.py collectstatic --noinput
```

实测（探针 B）：

```text
rc=0  耗时 669 ms
文件数 157  总大小 2.9 MB
```

> ⚠️ `--clear` 会**先删光再重建**，期间静态资源 404。生产上要么不用 `--clear`（新旧文件共存，靠文件名哈希区分版本），要么接受短暂空窗。

### 3.2.3 `DEBUG=False` 之后，哪些 URL 会变

这是课 19 那个坑的完整版。同一份代码，只改 `DEBUG`：

| URL | `DEBUG=True`（runserver） | `DEBUG=False`（WSGI 服务器） |
|-----|--------------------------|------------------------------|
| `/api/products/` | 200 | 200（业务不受影响） |
| `/static/...` | 200（runserver 包了 handler） | **404** |
| `/media/...` | 200（如果你挂了 `static()`） | **404** |
| 不存在的路径 | 404（含详细堆栈） | 404（**无堆栈**） |

实测（实验 16-20）：

```text
DEBUG = False
/media/avatar.png  -> 404
/api/products/     -> 200
/nonexistent/      -> 404
```

**"上传成功但下载 404"的完整因果链**：

1. 开发时 `urls.py` 里挂了 `+ static(settings.MEDIA_URL, document_root=...)`
2. `static()` 的实现里有一句 `if not settings.DEBUG: return []`
3. 上线后 `DEBUG=False`，这行路由**静默消失**
4. 数据库里有记录、磁盘上有文件，就是 404

`static()` 的源码值得看一眼 —— 它就是本课"环境错了不报错"的又一个例子：

```python
# django/conf/urls/static.py
def static(prefix, view=serve, **kwargs):
    if not settings.DEBUG or (prefixes and settings.STATIC_URL in prefixes):
        return []   # ← 安静地返回空列表，什么都不告诉你
    ...
```

**怎么确认它真的生效了**：上线后第一件事，手动请求一个 `/static/` 和一个 `/media/` 的真实文件。别只看健康检查——健康检查通常只打 `/api/health/`。

### 3.2.4 `ALLOWED_HOSTS` 与 Host 头

生产配置里必须有 `ALLOWED_HOSTS`，否则 `DEBUG=False` 时所有请求 400。

实测（实验 21-22）：

```text
api.example.com  -> 200   （在白名单里）
evil.com         -> 400   （不在白名单里）
localhost        -> 400   （也不在）
```

注意是 **400 不是 403**。因为 Host 头不合法意味着"这个请求根本不是发给我的"，Django 直接拒绝，不做进一步处理。

`ALLOWED_HOSTS` 从环境变量读时，记得处理逗号分隔：

```python
ALLOWED_HOSTS = [
    h.strip()
    for h in os.environ.get("ALLOWED_HOSTS", "api.example.com").split(",")
    if h.strip()
]
```

> ⚠️ 别写 `ALLOWED_HOSTS = ["*"]`。那等于没设。课 21 的实验工程里这么写是为了方便跑测试，生产上不允许。

### 3.2.5 反向代理后面：无限重定向的根因

这是开头第三个问题。`SECURE_SSL_REDIRECT=True` 想让 HTTP 跳 HTTPS，但 Django 不知道前面有 Nginx：

```text
Nginx → Django 走的是 HTTP（内网）
Django 看到 scheme=http，于是 301 到 https://...
用户重新请求 → Nginx → Django，看到的还是 http
→ 又 301 → 循环
```

**修法：配 `SECURE_PROXY_SSL_HEADER`，告诉 Django 该信哪个头。**

```python
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
```

第一个元素是 Django 会从 `request.META` 里读的键名，第二个是"看到这个值就认为是 HTTPS"。

实测对照（实验 23-25）：

```text
【配了 SECURE_PROXY_SSL_HEADER】
  无 X-Forwarded-Proto -> 301 https://testserver/api/products/
  带 X-Forwarded-Proto -> 200        ✅

【没配 SECURE_PROXY_SSL_HEADER】
  无 X-Forwarded-Proto -> 301
  带 X-Forwarded-Proto -> 301        ❌ 照样重定向
```

**配了才认，没配就一直重定向。**

对应的 Nginx 配置：

```nginx
location /api/ {
    proxy_pass http://127.0.0.1:8000;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;   # ← 这一行是关键
}
```

> ⚠️ **安全前提**：`SECURE_PROXY_SSL_HEADER` 等于"我信任上游传来的这个头"。如果 Django 能被直接访问（不经过 Nginx），攻击者可以伪造 `X-Forwarded-Proto: https` 绕过 SSL 检查。**所以必须保证 Django 只监听内网地址，且防火墙只放行 Nginx。**

### 3.2.6 生产配置清单（承接课 21 的 6 条 `security.W*`）

课 21 实验 45 实测出 6 条告警。这里逐条给修法和生产含义：

| 编号 | 告警 | 生产意味着什么 | 修法 |
|------|------|---------------|------|
| **W001** | 缺 `SecurityMiddleware` | 那五个 `SECURE_*` 设置**全部无效** —— 你配了但没生效，而且没有任何提示 | `MIDDLEWARE` 最前面加 `django.middleware.security.SecurityMiddleware` |
| **W002** | 缺 `XFrameOptionsMiddleware` | 你的页面可被嵌进别人的 `<iframe>`，可做点击劫持 | 加 `django.middleware.clickjacking.XFrameOptionsMiddleware`，或设 `X_FRAME_OPTIONS = "DENY"` |
| **W003** | 缺 `CsrfViewMiddleware` | CSRF 保护失效 | 加 `django.middleware.csrf.CsrfViewMiddleware`。**纯 DRF + JWT 的项目也可能要**，取决于是否有 session 登录入口（Admin 就是） |
| **W009** | `SECRET_KEY` 不合格 | 长度 < 50、或唯一字符 < 5、或是 `django-insecure-` 前缀 | 生成强随机值：`python -c "from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())"` |
| **W012** | `SESSION_COOKIE_SECURE` 未开 | session cookie 会走明文 HTTP，可被嗅探劫持 | 设 `SESSION_COOKIE_SECURE = True`（HTTPS 已就位才能开，否则登录会坏） |
| **W018** | `DEBUG=True` | 堆栈、SQL、环境变量全部打到浏览器 | `DEBUG = False`（用 3.1.1 的正确写法） |

**修完之后**（实验 29 实测）：

```text
生产配置 --deploy: rc=0, 安全告警 0 条
```

**但注意**（实验 29b）：只要关掉其中任何一项，它会**换一个编号**重新出现：

```text
把 SECURE_SSL_REDIRECT 关掉 -> 1 条新告警
?: (security.W008) Your SECURE_SSL_REDIRECT setting is not set to True...
```

所以 `--deploy` 是个**活检查**，不是一次性任务。每次改配置都该重跑。

---

## 3.3 知识点 3：生产部署与上线清单

### 3.3.1 进程模型：什么该常驻，什么该起进程

课 21 留下的数据：一次 `manage.py` 启动要 632.8ms，其中 Django 启动 402.5ms、system checks 272.9ms。

本课在同样的机器上重测（实验 31-33）：

```text
manage.py check                中位   896.1 ms
django.setup()                 中位   476.1 ms   ← 光这一步就占一半
exportdocs（跑 checks）        中位  1868.8 ms
exportdocs --skip-checks      中位  1686.5 ms   ← 只省 182ms（10%）
```

**关键数字：每次冷启动，约 476ms 是"把 Django 装进内存"的固定成本，与你要干什么无关。**

对照常驻进程（探针 A，waitress 实测）：

| 线程数 | 启动耗时 | 首个请求 | 中位延迟 |
|--------|---------|---------|---------|
| 1 | 570.6 ms | 209.8 ms | 29.87 ms |
| 4 | 676.0 ms | 196.8 ms | **22.93 ms** |
| 16 | 571.5 ms | 181.4 ms | 26.58 ms |

**常驻进程的单请求中位延迟是冷启动的 2.55%。**

**盈亏平衡**（实验 35-38），设任务本身耗时 T，冷启动固定成本约 896ms：

| 任务耗时 T | 冷启动占比 | 每分钟 1 次的 CPU | 建议 |
|-----------|-----------|------------------|------|
| 1 ms | 99.9% | 1.50% | 常驻 |
| 10 ms | 98.9% | 1.51% | 常驻 |
| 50 ms | 94.7% | 1.58% | 常驻 |
| 200 ms | 81.8% | 1.83% | 常驻 |
| 1000 ms | 47.3% | 3.16% | 可冷启 |
| 5000 ms | 15.2% | **9.83%** | **常驻** |

**判据是两个维度，不是一个**：

1. **启动占比高** → 常驻（T 小的时候，你付的成本全是启动）
2. **即使占比低，但跑得频繁导致 CPU 高** → 还是常驻（看 T=5000ms 那行：占比只有 15%，但每分钟一次就吃掉 9.8% CPU）

**这两列是怎么算出来的**：

```text
启动占比 = C / (C + T)
  T=1ms    -> 896 / 897    = 99.9%
  T=5000ms -> 896 / 5896   = 15.2%

每分钟 1 次，相当于每 60 秒付一次 (C + T)：
CPU 占比 = (C + T) / 60000
  T=1ms    -> 897 / 60000  = 1.50%
  T=5000ms -> 5896 / 60000 = 9.83%
```

**第二个维度容易被忽略**：T=5000ms 时启动只占 15%，看起来"冷启动完全没问题"——但它每分钟跑一次，光是启动就吃掉 9.8% 的 CPU。工程上一般把 **5%** 当作"要不要为它单独开一个常驻进程"的分界线。

**所以**：

- **Web 请求**：必须常驻（gunicorn / uwsgi / waitress）
- **定时任务**：看频率。每分钟跑的该常驻（Celery beat / `django.tasks` 的 worker），每天跑一次的可以起进程（cron）
- **一次性运维动作**：起进程（`manage.py` 命令）

### 3.3.2 `--skip-checks` 在生产能不能用

结论：**能，但只在你知道自己在做什么的时候。**

实测（实验 39-42）—— 在生产配置里注入一条 Error 级 check：

```text
$ manage.py check                                    -> rc=1   （拦住了）
$ exportdocs（默认）                                  -> rc=1   （拦住了）
$ exportdocs --skip-checks                           -> rc=0   （Error 被跳过，命令照跑）
```

**`--skip-checks` 会把 Error 一起跳过。**

它不是"跳过那些无关紧要的警告"，是"跳过全部检查"。所以：

| 场景 | 能不能用 |
|------|---------|
| CI 里跑 `check` | ❌ 绝对不行，那正是要检查的地方 |
| 高频定时任务（每分钟一次） | ⚠️ 可以，但前提是同一份代码在 CI 里已经跑过 `check` |
| 一次性的数据修复命令 | ✅ 可以 |
| 为了"让命令跑快点" | ❌ 不行，实测只省 10% |

### 3.3.3 发布流水线：pre-deploy / deploy / post-deploy

把课 21 的四个命令和本课的命令排进去。实测的每一步（实验 43-46）：

```text
[pre-deploy ] check --deploy --tag security --fail-level WARNING  ← 安全门禁（阻断）
[pre-deploy ] check --deploy --tag lab_docs                       ← 文档门禁（记账，不阻断）
[pre-deploy ] migrate --plan                                      ← 预演迁移，不执行
[deploy     ] collectstatic --noinput                             ← 静态资源就位
[deploy     ] migrate                                             ← 应用迁移
[post-deploy] exportdocs --api-version v1 --file schema.yaml      ← 导出文档产物
[post-deploy] testhealth --json                                   ← 上线后体检
```

**每一步在哪台机器上跑**（照抄前先看这列）：

| 阶段 | 命令 | 在哪跑 | 失败后果 | 回滚点 |
|------|------|--------|---------|--------|
| pre-deploy | `check --deploy --tag security --fail-level WARNING` | **CI runner**（不需要连生产库） | 配置有问题 | **不用回滚**，代码还没上。修配置重跑 |
| pre-deploy | `check --deploy --tag lab_docs` | **CI runner** | 文档没同步 | **不用回滚**，记账即可 |
| pre-deploy | `migrate --plan` | **CI runner** 或部署机（要连库，只读） | 迁移有冲突 | **不用回滚**。这是预演，没执行任何东西 |
| deploy | `collectstatic --noinput` | **部署机**（构建产物） | 静态文件缺失 | **回滚到上一个镜像**。此时代码已部署但服务未切流 |
| deploy | `migrate` | **部署机**（要连生产库） | DDL 执行了一半 | ⚠️ **最危险**。见下 |
| post-deploy | `exportdocs --api-version v1 --file schema.yaml` | **部署机** 或 CI（产出归档） | 文档没更新 | **不用回滚**。不影响线上功能，重试即可 |
| post-deploy | `testhealth --json` | **生产环境**（上线后） | 测试跑挂了 | **回滚到上一个镜像 + 回滚迁移** |

> 💡 注意 `migrate --plan` 与 `migrate` 的区别：前者只是打印将要执行的迁移列表，**不连库也不写库**（实测 rc=0），可以安全地放在 CI 里；后者要连生产库并执行 DDL，是整个流水线里唯一不可逆的一步。

**迁移是唯一不可逆的步骤，要单独说。**

`migrate` 跑的是 DDL（`ALTER TABLE` 之类）。Django 的 `transaction.atomic` **管不了 DDL**——它只能回滚 DML。

实测各数据库的差异（实验 48）：

```python
from django.db import connection
print(connection.features.can_rollback_ddl)
```

| 数据库 | `can_rollback_ddl` | 含义 |
|--------|-------------------|------|
| SQLite | `True`（实测） | DDL 在事务里，可回滚 |
| PostgreSQL | `True` | 同上，这是它最大的优势之一 |
| MySQL 8 以前 | **`False`** | ⚠️ DDL 会自动提交，跑到一半失败**留下半截表结构** |

**所以正确的回滚策略是：回滚到上一个已验证的镜像（代码 + 数据快照），而不是回滚 SQL。**

配套的前置动作：

1. **迁移前备份**（或确认有 PITR / 快照）
2. **迁移与代码分开部署**（先跑兼容旧代码的迁移，再发新代码，再跑清理性迁移）—— 这是"向前兼容迁移"的三步走
3. **破坏性操作延后**（删字段、改类型放在确认新版本稳定之后）

### 3.3.4 上线清单：check 查不到的那些

`--deploy` 查配置，但下面这些它一条都查不了。**每次上线逐条过**：

**监控与告警**

- [ ] 健康检查端点可达（且它真的查了数据库，不是只返回 `{"status":"ok"}`）
- [ ] 错误率告警已配（5xx 比例、关键接口失败数）
- [ ] 延迟告警已配（P95 / P99，不是平均值）
- [ ] 日志采集已通（能看到刚产生的日志）

**可观测性**（承接课 18）

- [ ] 结构化日志已开（JSON 格式，机器可读）
- [ ] trace_id 贯穿（日志 / 异常响应 / 下游调用）
- [ ] 慢查询记录已开且有截断（课 18 的两道防线）

**数据与备份**

- [ ] 迁移前已备份
- [ ] 恢复演练做过（**不是**备份做过）
- [ ] 知道回滚到哪个版本号

**配置与密钥**

- [ ] `SECRET_KEY` 已配且够强（不是默认值）
- [ ] `DEBUG=False` 已生效（**用 `shell -c` 确认，别信环境变量**）
- [ ] `ALLOWED_HOSTS` 已配具体域名（不是 `["*"]`）
- [ ] 反向代理的 `X-Forwarded-Proto` 已配

**静态与媒体**

- [ ] `collectstatic` 已跑
- [ ] 手动请求过一个 `/static/` 真实文件
- [ ] 手动请求过一个 `/media/` 真实文件

> 💡 这张清单里，**没有一项能被 `manage.py check --deploy` 覆盖**。
> 这就是为什么本课要单独列它。

### 3.3.5 结构化的生产日志（承接课 18）

课 18 讲了结构化日志和 trace_id，这里把它接到标准库 `logging` 上，因为生产环境日志要交给采集 agent：

```python
# config/logfmt.py
import json
import logging


class JsonFormatter(logging.Formatter):
    """把每条日志渲染成一行 JSON。

    为什么要自己写：默认格式是人类可读的多行文本，
    日志采集（Filebeat / Fluent Bit）按行读取时会把它切碎。
    """

    def format(self, record):
        payload = {
            "ts": self.formatTime(record, "%Y-%m-%dT%H:%M:%S"),
            "level": record.levelname,
            "logger": record.name,
            "msg": record.getMessage(),
        }
        # 把 extra 里带的字段原样带出来（trace_id 之类）
        for key, value in record.__dict__.items():
            if key not in (
                "args", "asctime", "created", "exc_info", "exc_text", "filename",
                "funcName", "levelname", "levelno", "lineno", "module", "msecs",
                "message", "msg", "name", "pathname", "process", "processName",
                "relativeCreated", "stack_info", "thread", "threadName", "taskName",
            ):
                payload[key] = value
        if record.exc_info:
            payload["exc"] = self.formatException(record.exc_info)
        return json.dumps(payload, ensure_ascii=False)
```

接到 settings：

```python
LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "json": {"()": "config.logfmt.JsonFormatter"},
    },
    "handlers": {
        "console": {"class": "logging.StreamHandler", "formatter": "json"},
    },
    "root": {"handlers": ["console"], "level": "INFO"},
    "loggers": {
        "django": {"handlers": ["console"], "level": "INFO", "propagate": False},
        "django.request": {"handlers": ["console"], "level": "ERROR", "propagate": False},
    },
}
```

**必查项 #28 检验这个 formatter**（探针 B）：

```text
格式化 100000 条: 531 ms  (5.31 µs/条)
一个请求打 20 条日志 = 0.106 ms

含 traceback 的单条长度: 298 字节
超长消息（10 万字符）单条长度: 100073 字节
```

两个结论：

1. **formatter 本身不是瓶颈**（5.31 µs/条，一个请求打 20 条约 0.1 ms）。真正的风险是磁盘慢，那要靠采集 agent 解决。
2. **日志体不截断**。msg 本身可以任意长（实测 10 万字符原样输出），所以**打日志时必须自己截断**——这正是课 18 慢查询那节"只记最慢 N 条 + SQL 截断"两道防线里的一环。

**怎么确认它真的生效了**：

```powershell
python manage.py shell -c "import logging; logging.getLogger('django').error('测试')"
# 期望输出：{"ts": "...", "level": "ERROR", "logger": "django", "msg": "测试"}
```

---

# 第四幕　实操验证

## 4.0 实验工程

**实验规模**：**48 个实验 / 63 项断言 / 2 个独立探针 / 零失败**。

工程在 `%TEMP%/dj-lesson22-demo/ops`，由课 21 的 `cmdlab` 复制而来（四个命令与 `labkit.py` 直接复用）。

```text
%TEMP%/dj-lesson22-demo/ops/
├── manage.py
├── labkit.py                    # Check 断言器 + Timer（沿用课 18/20/21）
├── config/
│   ├── settings.py              # 开发配置（课 21 原样）
│   ├── settings_prod.py         # ★ 本课生产配置（env_bool / 密钥校验 / 安全开关）
│   ├── settings_static.py       # 对照：开发配置 + staticfiles
│   ├── settings_badenv.py       # 对照：bool(os.getenv) 错误写法
│   ├── settings_goodenv.py      # 对照：白名单解析正确写法
│   ├── settings_err.py          # 对照：注入一条 Error 级 check
│   ├── logfmt.py                # ★ JSON 日志 formatter
│   ├── wsgi.py                  # ★ WSGI 入口（waitress 的服务对象）
│   └── urls.py
├── apps/shop/                   # 沿用课 21（models / checks / 四个命令）
├── run_lab1.py                  # 实验 1-14　配置管理与密钥（17 项断言）
├── run_lab2.py                  # 实验 15-30　静态资源与联调部署（22 项断言）
├── run_lab3.py                  # 实验 31-48　部署形态与发布流水线（24 项断言）
├── probe_wsgi.py                # 探针 A：waitress 常驻 vs 冷启动
├── probe_scale.py               # 探针 B：必查项 #28 生产规模检验
└── count_assertions.py          # 全量回归
```

**与课 21 的关系**：本课不重新验证课 21 的结论（`--verbosity`、check 级别、`call_command` 的 patch 位置等），只在此之上叠加"部署"这一层。

## 4.1 运行方式

```powershell
$env:PYTHONIOENCODING="utf-8"; $env:PYTHONUTF8="1"
cd "$env:TEMP\dj-lesson22-demo\ops"

# 全量回归（python 请用你自己的虚拟环境解释器）
python count_assertions.py
```

> **关于 `python` 是谁**：本课所有实测数据来自 `dj-course` 虚拟环境的 **Python 3.13.14 / Django 6.1 / Windows 11**（作者本机路径形如 `%USERPROFILE%\.workbuddy\binaries\python\envs\dj-course\Scripts\python.exe`，读者的环境必然不同，所以命令主体一律写 `python`）。你只要保证 `python -c "import django; print(django.get_version())"` 输出 6.1 即可。

单独跑某一部分：

```powershell
python run_lab1.py      # 配置管理与密钥
python run_lab2.py      # 静态资源与联调部署
python run_lab3.py      # 部署形态与发布流水线
python probe_wsgi.py    # WSGI 常驻 vs 冷启动（会临时占用 127.0.0.1:8099）
python probe_scale.py   # #28 生产规模检验
```

**关键环境变量**（`run_lab*.py` 会自己重置，手动跑命令时需要）：

```powershell
$env:SECRET_KEY = "k22-prod-secret-key-abcdefghijklmnopqrstuvwxyz-0123456789"
$env:ALLOWED_HOSTS = "localhost,127.0.0.1,testserver"
$env:DJANGO_SETTINGS_MODULE = "config.settings_prod"
```

下面这一组命令**依赖上面三条环境变量**，请先执行它们再复制命令块：

```powershell
$env:SECRET_KEY = "k22-prod-secret-key-abcdefghijklmnopqrstuvwxyz-0123456789"
$env:ALLOWED_HOSTS = "localhost,127.0.0.1,testserver"
$env:DJANGO_SETTINGS_MODULE = "config.settings_prod"
```

然后每条命令都跑一遍：

```powershell
python manage.py check --deploy --tag security --fail-level WARNING
python manage.py migrate --plan
python manage.py collectstatic --noinput
python manage.py migrate
python manage.py exportdocs --api-version v1 --file schema.yaml
python manage.py testhealth --json
```

## 4.2 实验清单

> **分级说明**：**核心必跑** 5 组是不跑就白学的部分（每组 1-3 分钟，合计 10 分钟内）；**推荐** 是需要理解但看结论也能吸收的。
> 全量回归（`run_lab1`~`run_lab3` + 2 个探针）本课实测耗时 **56.4 秒**（63 项断言全过）。
>
> **只有 20 分钟的话**（不跑实验，只读）：1.2（三个故障）→ 2.1 / 2.2 / 2.5（三个最典型的冲突）→ 3.1.3（那段 `raise`）→ 5.5（误区表）。

| 实验 | 内容 | 关键结论 | 耗时 | 建议 |
|------|------|---------|------|------|
| 1-2 | 环境变量真值陷阱 | `bool('False')` 是 `True` | 2s | **核心必跑** |
| 3-4 | DEBUG 四种值 × 两种写法对照 | `DEBUG=False` / `DEBUG=0` 全被读成 True | 4s | **核心必跑** |
| 5-8 | `SECRET_KEY` 缺失时的真实行为 | `check` rc=0、`--deploy` rc=0、**用到签名才炸** | 3s | **核心必跑** |
| 9-11 | 轮换密钥会作废什么 | 普通签名 / 时间戳签名 / 签名 cookie **全部 BadSignature** | 3s | **核心必跑** |
| 12-14 | `SECRET_KEY_FALLBACKS` 无痛轮换 | 旧签名可解、撤掉即失效、新签名只认新 key | 3s | 推荐 |
| 15 | `DEBUG=True` 时 URLconf 有 `/static/` 吗 | **没有**。预设被推翻 | 2s | **核心必跑** |
| 16-17 | 谁在托管静态文件 | 是 `runserver` 的 `StaticFilesHandler`；显式挂 `static()` 才有 200 | 4s | 推荐 |
| 18-20 | `DEBUG=False` 下 `/media/` 与 API | `/media/` 404、API 200 | 2s | 推荐 |
| 21-22 | `ALLOWED_HOSTS` | 白名单外返回 **400**（不是 403） | 2s | 推荐 |
| 23-25 | `SECURE_SSL_REDIRECT` 与反向代理 | 不配 `SECURE_PROXY_SSL_HEADER` 就**无限重定向** | 3s | **核心必跑** |
| 26-29 | `--deploy` 开发 vs 生产配置 | 开发 6 条 `W*`、生产 0 条；关掉任一项会**换新编号**出现 | 4s | 推荐 |
| 29b | 关掉 SSL 后的新告警 | 冒出第 7 条 `security.W008` | 2s | 推荐 |
| 30 | `--fail-level WARNING` | 退出码变 1，CI 才能拦住 | 2s | 推荐 |
| 31 | `check --skip-checks` | **参数不存在，rc=2**。预设被推翻 | 2s | **核心必跑** |
| 31b-31c | 源码依据 | 只在 `requires_system_checks` 非空时注册 | 1s | 推荐 |
| 32 | 在真跑 check 的命令上测 | `--skip-checks` 只省 **10%** | 12s | 推荐 |
| 33 | `django.setup()` 单独计时 | 476ms，占冷启动一半以上 | 3s | 推荐 |
| 35-38 | 常驻 vs 冷启动盈亏平衡 | 两个维度：启动占比 + CPU 总量 | 1s | 推荐 |
| 39-42 | `--skip-checks` 会不会跳过 Error | **会**。命令照跑，Error 消失 | 8s | **核心必跑** |
| 43 | `--fail-level WARNING` 误伤 | 把课 21 的 `lab_docs.W001` 也拦住了 | 2s | 推荐 |
| 43b | `--tag` 分开门禁 | security 阻断 / lab_docs 记账 | 4s | 推荐 |
| 43c | 单独跑 `lab_docs` tag | rc=1，这类该记账不该阻断 | 2s | 推荐 |
| 44-46 | 流水线四步 | `migrate --plan` / `collectstatic` / `migrate` 均 rc=0 | 8s | 推荐 |
| 47-48 | 迁移的回滚点 | 能列出已应用/未应用迁移；`can_rollback_ddl` 因库而异 | 2s | 推荐 |
| 探针 A | waitress 常驻 vs 冷启动 | 中位延迟 22.93ms vs 冷启动 896ms（**2.55%**） | 6s | 推荐 |
| 探针 B | #28 生产规模检验 | 日志 5.31µs/条；日志体**不截断** | 2s | 推荐 |

> **核心必跑 5 组**合计约 **17 秒**（1-4 / 5-8 / 15 / 23-25 / 31）。三个脚本单独跑：`run_lab1` 7.9s、`run_lab2` 11.6s、`run_lab3` 约 33s。

## 4.3 关键量化数据

| 指标 | 实测值 | 出处 |
|------|--------|------|
| `manage.py check` 冷启动 | 896.1 ms（中位） | 实验 31 |
| `django.setup()` 单独耗时 | 476.1 ms（中位） | 实验 33 |
| `exportdocs` 跑 checks | 1868.8 ms | 实验 32 |
| `exportdocs --skip-checks` | 1686.5 ms（**只省 10%**） | 实验 32 |
| waitress 启动（threads=4） | 676.0 ms | 探针 A |
| waitress 首个请求 | 196.8 ms | 探针 A |
| waitress 稳定态中位延迟 | **22.93 ms** | 探针 A |
| 常驻 vs 冷启动（100 请求） | 3230 ms vs 90000 ms（**27.9x**） | 探针 A |
| JSON 日志格式化 | 5.31 µs/条（10 万条 531ms） | 探针 B |
| 单条日志（10 万字符 msg） | 100073 字节（**不截断**） | 探针 B |
| `collectstatic` | 157 个文件 / 2.9 MB / 669 ms | 探针 B |

> ⚠️ **环境强相关**：以上全部来自 Windows 11 + SQLite + waitress。**Linux + PostgreSQL + gunicorn 上，冷启动会更快、常驻进程的优势会更明显、DDL 可回滚性更好。** 换环境请重新量一遍 —— 这正是课 20「先量后改」的方法论。

---

# 第五幕　体系收束

## 5.1 决策表：这件事该在哪一层解决

部署中遇到的问题，先判断该在哪一层修，比直接动手重要：

| 症状 | 该在哪修 | 判据 |
|------|---------|------|
| 配置项的值不对 | **settings / 环境变量** | `shell -c "print(settings.X)"` 能看出差异 |
| 某个 URL 访问不到 | **部署拓扑（Nginx）** | Django 侧路由表里没有这条 |
| 请求进来了但行为不对 | **代码** | `shell -c` 里复现得出来 |
| 现象只在生产出现、本地无法复现 | **环境差异** | 逐项对比 `diffsettings` |
| 上线后才暴露、上线前无征兆 | **缺启动期断言** | 参见 3.1.3 的 `raise` |

> 💡 **排查顺序：先看 Django 实际读到的配置（`shell -c print(settings.X)`），再看路由，最后看代码。**
> 本课的三个故障，全都在第一步就能定位。

## 5.2 本课的三条硬结论

1. **环境变量必须白名单解析。** `bool(os.getenv("DEBUG"))` 会把 `"False"` 和 `"0"` 都读成 `True`——你在生产开着 DEBUG 而监控全绿。判据：默认值取安全的那个方向。

2. **缺 `SECRET_KEY` 时 Django 一句话不说。** `check`、`check --deploy`、`migrate`、`collectstatic` 全部退出码 0，进程能起来、健康检查能过，直到有人登录才炸。判据：在 settings 里主动 `raise`，让进程起不来。

3. **`--skip-checks` 会把 Error 一起跳过，而且它只省 10%。** 它不是"跳过无关警告"，是"跳过全部检查"。判据：只用于 CI 已验证过的命令。

## 5.3 与前面课程的连线

| 本课内容 | 承接自 |
|---------|--------|
| 结构化日志 + trace_id | 课 18（中间件与请求链路） |
| `/media/` 404、孤儿文件 | 课 19（文件存储与 Admin） |
| `testhealth` / `exportdocs` / `payorders` | 课 21（自定义管理命令） |
| `lab_routes` / `lab_docs` 等自定义 check | 课 21（System checks） |
| "先量后改" | 课 20（测试提速与文档） |
| `--parallel` 的盈亏平衡点 | 课 20（同款"固定开销 vs 收益"思维） |
| 中间件顺序 | 课 18（`SecurityMiddleware` 必须在最前） |
| `SECURE_SSL_REDIRECT` 与代理 | 课 2（CORS 白名单，同为"边界由谁守"） |

## 5.4 术语表

| 术语 | 含义 |
|------|------|
| **WSGI** | Python Web 应用与服务器之间的接口标准。Django 通过 `wsgi.py` 暴露一个可调用对象 |
| **反向代理** | 位于应用前面的服务器（Nginx）。负责 TLS、静态文件、负载均衡、缓冲 |
| **`collectstatic`** | 把各 app 的静态文件复制到 `STATIC_ROOT`，供 Nginx / CDN 提供 |
| **`STATIC_ROOT`** | `collectstatic` 的输出目录。生产上 Nginx 直接读它 |
| **`MEDIA_ROOT`** | 用户上传文件的存储目录。生产上不该由 Django 提供 |
| **常驻进程** | 启动一次、长期运行、反复处理任务的进程形态（gunicorn / worker） |
| **冷启动** | 每次执行都新建一个进程，付一次 `django.setup()` 的成本 |
| **`SECURE_PROXY_SSL_HEADER`** | 告诉 Django"信这个头判断 HTTPS"。不配会导致无限重定向 |
| **PITR** | Point-In-Time Recovery，时间点恢复。比全量备份更精细的恢复能力 |
| **`SECRET_KEY_FALLBACKS`** | 旧密钥列表，只用于解密不用于加密，用于无痛轮换 |

## 5.5 高频误区表

| 误区 | 真相 |
|------|------|
| "`DEBUG=False` 我就关掉 DEBUG 了" | 用 `bool(os.getenv())` 读的话，`"False"` 是 `True` |
| "缺 `SECRET_KEY` 启动会报错" | **不会**。`check` rc=0，用到签名才炸 |
| "`staticfiles` 会自动托管 `/static/`" | 是 **`runserver`** 在托管，换 WSGI 服务器就没了 |
| "`collectstatic` 之后 `/static/` 就能访问了" | Django 在生产**根本不托管** `/static/`，要 Nginx 配 |
| "`--skip-checks` 能大幅加速" | 只省 **10%**，而且会跳过 Error |
| "`check --deploy` 全绿就安全了" | 它查不了密钥来源、监控、备份 |
| "`--fail-level WARNING` 是好门禁" | 会误伤非安全项，要用 `--tag` 分开 |
| "定时备份就够了" | 没做过**恢复演练**的备份等于没有 |
| "`ALLOWED_HOSTS = ["*"]` 省事" | 等于没设，任何人都能用任意域名访问 |
| "HTTPS 重定向配了就行" | 不配 `SECURE_PROXY_SSL_HEADER` 就是**无限重定向** |
| "回滚就是把 SQL 反过来跑" | 回滚到**上一个已验证的镜像**；MySQL 8 前 DDL 不可回滚 |
| "`/admin/` 能打开就配好了" | Admin 的 CSS/JS 在 `/static/`，那边没配就是**能打开但没样式** |
| "Django 能直接对外提供服务" | 不该。静态文件、TLS 缓冲、慢客户端防护都得靠前面的 Nginx |

## 5.6 自检题

**A 组：概念**

1. 为什么 `bool(os.getenv("DEBUG"))` 是错的？给出三种会出错的输入值。
2. `SECRET_KEY` 变了之后，哪些业务数据会失效？
3. 生产环境 `/static/` 应该由谁提供？`collectstatic` 在其中起什么作用？

**B 组：动手**

1. 写一个 `env_bool()`，然后用四种输入（`False` / `0` / `1` / 未设置）验证它。
2. 给你的 settings 加上"生产缺 `SECRET_KEY` 就拒绝启动"的检查，然后**不设该环境变量跑一次**，确认进程真的起不来。
3. 用 `runserver` 和用 WSGI 服务器分别请求同一个 `/static/` 文件，记录两次的状态码差异。
4. 故意不配 `SECURE_PROXY_SSL_HEADER` 而开 `SECURE_SSL_REDIRECT`，用 `curl -v` 观察重定向循环。

**C 组：排障**

1. 上线后用户头像全挂，但数据库有记录、磁盘有文件。列出三种可能并给出验证方法。
   > 方向：①`DEBUG=False` 导致 `static()` 返回空（查 `urls.py` 有没有挂 `static()`）；②Nginx 没配 `/media/` 的 location（直接 `curl` 该 URL 看是谁返回的 404）；③`MEDIA_ROOT` 指向了错误路径（查 `settings.MEDIA_ROOT` 与实际文件位置）。最快的区分手段是**看 404 页面长什么样**——Django 的 404 和 Nginx 的 404 页面完全不同。
2. 你的 `check --deploy` 在本地全绿、CI 上红。列出三种可能。
   > 方向：①环境变量差异（CI 上 `SECRET_KEY` 是另一个值、`DEBUG` 未设）；②`--fail-level` 把自定义 check 也算了进去（用 `--tag` 分开）；③CI 跑的 settings 模块与本地不同。最快的定位手段：在 CI 上跑 `manage.py diffsettings` 并把关键几项打印出来对比。
3. 一个每分钟跑一次的定时任务，用 `manage.py` 命令实现，上线后 CPU 涨了 10%。为什么？
   > 方向：冷启动固定成本约 900ms，每分钟一次就是 1.5% 的 CPU，再加上任务本身耗时。判据见 3.3.1 的盈亏平衡表——**启动占比只是维度之一，CPU 总量是另一个**。解法：改成常驻 worker。
   > **怎么验证**：先用 `time python manage.py <你的命令>` 量出单次耗时 T，再算 `(900 + T) / 60000`，看是否接近观测到的 CPU 涨幅。也可以直接用课 21 的 `manage.py testhealth --json`（它会把三段耗时分开报），确认其中有多少是建库/造数而非任务本身。

## 5.7 事实来源标注

| 结论 | 来源 | 说明 |
|------|------|------|
| `bool("False")` 为 `True` | Python 语义 | 通用知识，实测确认（实验 1） |
| `SECRET_KEY` 为空时 `check` rc=0 | **实测** | 实验 5-8，官方文档未明示"检查阶段不校验 SECRET_KEY" |
| 轮换后三类签名全部 `BadSignature` | **实测** | 实验 9-11 |
| `SECRET_KEY_FALLBACKS` 行为 | 官方文档 + 实测 | 文档说明其用途，实验 12-14 确认行为 |
| URLconf 中无 `/static/` 路由 | **实测** | 实验 15，文档未明确说明这一点 |
| `runserver` 用 `StaticFilesHandler` 包装 | 源码 + 实测 | 实验 16，源码见 `staticfiles/management/commands/runserver.py` |
| `--skip-checks` 仅当 `requires_system_checks` 非空时注册 | **源码** | `BaseCommand.create_parser`，实验 31c |
| 六条 `security.W*` 的编号与含义 | **实测** | 实验 26-27，与课 21 一致 |
| `security.W008` | **实测** | 实验 29b，课 21 未出现（因配置不同） |
| `ALLOWED_HOSTS` 外返回 400 | **实测** | 实验 22 |
| `SECURE_PROXY_SSL_HEADER` 缺失导致持续 301 | **实测** | 实验 25 |
| `can_rollback_ddl`：SQLite `True` | **实测** | 实验 48 |
| `SESSION_COOKIE_AGE` = 1209600 秒（14 天） | **实测** | `shell -c "print(settings.SESSION_COOKIE_AGE)"` |
| `PASSWORD_RESET_TIMEOUT` = 259200 秒（72 小时） | **实测** | 同上 |
| `PASSWORD_RESET_TIMEOUT_DAYS` 已不存在 | **实测** | 实测 `ImportError`；网上旧教程仍在用，注意区分 |
| 冷启动 / 常驻延迟数据 | **实测** | 实验 31-33、探针 A，强依赖环境 |
| `can_rollback_ddl`：MySQL 8 前 `False` | 官方文档 | ⚠️ 本课**未实测**（本机无 MySQL），属文档结论 |
| 冷启动 / 常驻延迟数据 | **实测** | 实验 31-33、探针 A，强依赖环境 |
| 日志 formatter 吞吐 | **实测** | 探针 B |

> ⚠️ **未实测项已在表中标注。** 涉及 MySQL 与 Linux 上 gunicorn 的结论均为文档推断，换环境请重新验证。

## 5.8 验证环境

| 项目 | 值 |
|------|-----|
| 操作系统 | Windows 11 |
| Python | 3.13.14（Windows 托管，`dj-course` venv） |
| Django | 6.1 |
| DRF | 3.18.0 |
| waitress | **3.0.2**（本课新装） |
| 数据库 | SQLite 文件库（沿用课 21） |
| 静态文件 | `django.contrib.staticfiles`（课 21 未装，本课补上） |

**受限说明**：

1. **未用 WSL**（本机安全策略拦截），命令均为 PowerShell 形式
2. **未用 gunicorn** —— 它不支持 Windows。改用 **waitress**（纯 Python、跨平台）做 WSGI 服务器实测。Linux 生产环境通常用 gunicorn / uwsgi，进程模型结论一致，但**具体数字需在你的环境重测**
3. **未接真实 Nginx** —— `SECURE_PROXY_SSL_HEADER` 的效果用测试客户端伪造 `X-Forwarded-Proto` 头验证（实验 23-25）
4. **未测 MySQL / PostgreSQL** —— `can_rollback_ddl` 只实测了 SQLite，另外两个是文档结论
5. **未接真实监控与备份系统** —— 上线清单里这两块只给了检查项，没有实测环境
6. **未做真实域名与 TLS** —— HTTPS 相关配置通过请求头模拟验证

## 5.9 坑位记录

⚠️ **环境与工具坑（与 Django 知识无关，但最费时间）**

1. **🔴 `subprocess` 只传自定义 `env` 导致服务起不来** —— 写 `probe_wsgi.py` 时给子进程传了只含本课变量的干净环境，缺 `PATH` / `SystemRoot`，waitress 起不来；而 `stderr=DEVNULL` 又把报错吞了，表现为"启动失败"三个字，看不出原因。**修法：子进程一律 `dict(os.environ)` 再覆盖，启动失败时把 stderr 打出来。** 这是本课最费时间的一个坑。
2. **🔴 `%` 格式化与代码里的 `%.1f` 冲突** —— 用 `'''...%.1f...''' % KEY` 拼接子进程代码时，`TypeError: not enough arguments for format string`。**修法：改用 `@KEY@` 占位符 + `.replace()`。** 与课 21 的中文引号同属"字符串里嵌代码"类问题。
3. **Python 里写中文字符串不能用中文引号** —— 本课沿用 `『』` 规避。**课 17/19/21 之后第四次遇到。**
4. **实验脚本的顺序依赖** —— 实验 17 依赖 `collectstatic` 的产物，删掉 `staticfiles/` 后就失败。**修法：脚本内先跑 `collectstatic` 再断言**，保证从零状态可重复。
5. **Windows 控制台 GBK** —— 必须设 `$env:PYTHONIOENCODING="utf-8"`。

🔴 **备课预设被实测推翻（两处）**

1. **以为 `DEBUG=True` 时 `staticfiles` 自动托管 `/static/`** → 实测 URLconf 里根本没有这条路由，是 `runserver` 在 WSGI handler 外包了一层 `StaticFilesHandler`。这个错误很典型，因为"现象"是对的（开发时确实能访问），只是归因错了。
2. **以为 `check --skip-checks` 能测出跳过检查的收益** → 实测该参数在 `check` 命令上**根本不存在**（rc=2）。我最初拿它做基准测出"省 41%"，那是 argparse 快速失败省的时间。**换成真正跑 check 的 `exportdocs` 重测，实际只省 10%。**

> 💡 这两处的共同点：**它们都在"看起来应该如此"的地方。** 第一条的现象支持错误归因，第二条的错误结果看起来很合理（41% 是个"正常"的数字）。**凡是"结论看起来很合理"的时候，反而要回头检查测量方法本身。**

## 5.10 本课核心收获

1. **环境变量必须白名单解析，`bool(os.getenv())` 是错的。** `DEBUG=False` 和 `DEBUG=0` 都会被读成 `True`。
2. **`SECRET_KEY` 缺了不报错，用到签名才炸。** 所以在 settings 里主动 `raise`，让进程起不来。
3. **`SECRET_KEY` 轮换会作废所有已登录会话、密码重置链接、签名 cookie。** 用 `SECRET_KEY_FALLBACKS` 做无痛轮换，等待期不能省。
4. **生产环境 Django 不托管 `/static/` 和 `/media/`。** 开发时能访问是 `runserver` 的 `StaticFilesHandler` 功劳，不是 URLconf 里有路由。
5. **反向代理后必须配 `SECURE_PROXY_SSL_HEADER`**，否则 `SECURE_SSL_REDIRECT` 会造成无限重定向。
6. **冷启动约 900ms，其中 `django.setup()` 占 476ms。** 常驻进程的中位延迟只有 23ms。判断常驻还是冷启看两个维度：启动占比 + CPU 总量。
7. **`--skip-checks` 会跳过 Error，且只省 10%。** 它只在 `requires_system_checks` 非空时存在，`check` 命令自己不接受它。
8. **`--fail-level` 是全局的**，会误伤非安全项。用 `--tag` 把"安全门禁（阻断）"和"文档门禁（记账）"分开。
9. **`migrate` 跑的是 DDL，`transaction.atomic` 管不了。** MySQL 8 以前 DDL 不可回滚，所以要回滚到镜像而不是回滚 SQL。
10. **`--deploy` 查不了密钥来源、监控、备份。** 这三类必须人工过清单，其中"恢复演练"最容易被当成"备份做过"而忽略。

## 5.11 🎉 阶段 6 结课，也是全部 22 课结课

**阶段 6《工程化与生产》五课回答的是同一个问题：「代码写完到能上线之间，还差什么」。**

| 课 | 回答的是 | 一句话 |
|-----|---------|--------|
| 课 18 | 出事了能不能查 | 请求链路要可追溯（中间件顺序 / trace_id / 结构化日志） |
| 课 19 | 文件归谁管 | 上传与后台的归属要划清（`STORAGES` / Admin 收敛 / staticfiles 归属前端） |
| 课 20 | 改坏了敢不敢改 | 测试要跑得动、文档要说得清（先量后改 / OpenAPI 自动生成） |
| 课 21 | 约定有人查吗 | 运维动作要可重复、团队约定要可检查（BaseCommand / System checks） |
| 课 22 | 上线之后呢 | 环境要对、形态要对、清单要过（配置与密钥 / 部署拓扑 / 上线清单） |

**贯穿全课程的一条暗线：不报错的错误。**

从课 1 模板变量静默渲染空字符串，到课 5 路由遮蔽静默 404，到课 17 信号不注册全程静默，到课 21 的 check 不注册报 0 条，再到本课 —— **缺 `SECRET_KEY` 时 `check` 退出码 0、`DEBUG=False` 被读成 `True` 时监控全绿、`static()` 返回空列表时不发一言。**

它们的共同形状是：**你少了一层保护，但没有任何东西告诉你。**

所以各课给出的解药也是同一个：**把静默失败改成显式失败。** 课 19 用 `check` 扫孤儿文件，课 21 用 `check` 固化团队约定，本课用 settings 里的 `raise` 让进程起不来。

> 💡 如果这套课只留一句话：**凡是你没法在上线前验证的东西，就把它设计成上线瞬间就会暴露的形状。**

### 22 课的五条主线

| 阶段 | 回答的问题 | 代表作（最该回看的一课） |
|------|-----------|------------------------|
| **1**（课 1-2） | 为什么要前后端分离、工程怎么搭 | 课 1：分离后哪些能力退场 |
| **2**（课 3-7） | API 的边界在哪、逻辑该放哪 | 课 5：view 变胖会泄漏不一致的错误结构 |
| **3**（课 8-11） | 你是谁、你能干什么 | 课 8：登出后 access 仍有效、不装黑名单时登出是假成功 |
| **4**（课 12-14） | 数据怎么存、怎么迁 | 课 14：数据迁移与 `bulk_*` 的规模意识 |
| **5**（课 15-17） | 怎么查得快、怎么不出事 | 课 15：N+1 的四种形态与 `fetch_mode()` |
| **6**（课 18-22） | 怎么上线、上线后怎么活 | 课 21：把团队约定变成 CI 能拦住的 check |

**如果只回看三课**：课 1（范围边界）、课 5（架构腐化的起点）、课 21（把经验固化成自动化检查）。

**如果把 22 课压缩成一句可执行的话**：

> 让每一条团队约定都有一个 `check`，让每一个运维动作都有一条 `manage.py` 命令，让每一次上线都有一条能回滚的路径。

---

## 🚀 下一批接力提示词

> **本课是全部 22 课的最后一课。** 下一阶段进入 Phase 3 收尾产物：
>
> 1. **结课实战项目**（`projects/`，Phase 3，默认必做）—— 把 22 课的能力串成一个可运行的项目。建议带上的：课 18 的 trace_id 中间件、课 19 的 `STORAGES` 与上传接口、课 20 的测试提速三件套、课 21 的四个管理命令与四条 check、本课的生产配置与发布流水线。**验收标准是"能跑通一条从提交到上线的完整链路"，不是"功能齐全"。**
> 2. **`08-实战经验.md`**（Phase 5，学习态）—— 汇总全课程的适用边界、高频故障模式、落地 Checklist。高频故障模式的素材已经攒够了：本仓库"不报错的错误"累计已超过 20 处。
> 3. **`09-排障速查手册.md`**（Phase 5，使用态）—— 按症状倒查的条件-动作表。每条都要能在实验工程里复现，不得凭印象写（必查项 #6）。
> 4. **`10-场景解法库.md`**（Phase 5，设计态）—— 新要求来了怎么设计。按课 21 的决策表体例组织。
>
> 实验工程：`%TEMP%/dj-lesson22-demo/ops`（48 个实验 / 63 项断言 / 2 个探针 / 零失败）。可复用件：`config/settings_prod.py`（生产配置范本，含 `env_bool` + 密钥校验 + 安全开关全套）、`config/logfmt.py`（JSON 日志 formatter）、`config/wsgi.py`（WSGI 入口）、`probe_wsgi.py`（常驻 vs 冷启动基准）。
>
> ⚠️ 环境提醒：Windows 下跑实验前必须设 `$env:PYTHONIOENCODING="utf-8"`；**含中文的 Python 文件不要用 PowerShell 管道修改**；Python 里写中文字符串时**不要用中文引号**（课 17/19/21/22 已四次踩到，用 `『』` 代替）；**子进程 env 一律基于 `dict(os.environ)` 覆盖**，不要只传自定义变量（本课最费时间的坑）。

---

## 5.12 本课的质量门禁（评审结论，对学员可见）

本课交付前经过**双视角交叉评审**（pedagogy 视角看"教得对不对、够不够"，learner 视角看"零基础读者照着做能不能跑通"），评审是**逐字执行讲义里的每条命令**完成的，不是通读一遍。

- **P0（必须修，否则不能交付）：0 条**
- **P1（pedagogy 视角，4 条）**：①静态文件托管的机制讲错 → 补 `StaticFilesHandler` 包装层与 URLconf 对照实验；②进程模型的盈亏平衡只算了启动占比 → 补 CPU 总量维度与 5% 分界线；③密钥轮换只说"要等"没说等多久 → 补 `SESSION_COOKIE_AGE` / `PASSWORD_RESET_TIMEOUT` 取最大值的公式；④发布流水线只排了命令没说在哪跑 → 补"在哪跑"列。**已全修**
- **P2（pedagogy 视角，3 条）**：补 `--tag` 分开门禁的做法；`can_rollback_ddl` 标注 MySQL 部分未实测；两个超时默认值改为实测值。**已全修**
- **L1（learner 视角，4 条）**：3.1.3 的 `raise` 补两条照抄注意（必须在 `DEBUG` 之后 / `DEBUG` 必须用 `env_bool`）；命令统一写 `python` 不写本机绝对路径；`collectstatic` 与断言的顺序依赖改脚本内自包含；`--skip-checks` 的用法补 `requires_system_checks` 前提。**已全修**
- **L2（learner 视角，4 条）**：1.1 场景补具体时间点与后果；补"命令名=文件名"式的名词表；自检题给方向性答案；标出全量回归耗时 56.4 秒。**已全修**

**评审与实测中抓出的三处硬伤**（都不是措辞问题，是事实问题）：

1. **`DEBUG=True` 时 staticfiles 自动托管 `/static/`，我最初的预设是错的。** 以为 URLconf 里有一条 `/static/` 路由，实测**根本没有**。查 `runserver.get_handler` 源码才发现是 `StaticFilesHandler` 在 WSGI handler 外包了一层——既不是 URLconf 路由，也不是 `DEBUG` 直接控制。这条已作为本课最好的教学素材写进 3.2。
2. **`check --skip-checks` 我最初测出的"省 41%"是假象。** 实际 rc=2（argparse 根本不认这个参数），我量到的是"参数错误快速失败"的时间，不是"跳过检查"的时间。改用 `exportdocs` 重测，实际只省 10%（182.3ms）。**结论从"生产可用"改成"生产不值得用"**。
3. **`--fail-level WARNING` 是全局的，会误伤非安全项。** 实测把课 21 自写的 `lab_docs.W001` 也拦住了。改为 SSL 开关对照 + `--tag security` 把安全门禁与其他检查分开。

**验证状态**：全量回归 63 项断言零失败（48 实验 + 2 个独立进程探针，耗时 56.4 秒，从零状态可重复），全仓 61 文件 / 180 条本地链接零断链，终检 48/48 全绿。

---

## 🧭 课程导航

- ⬅️ 上一课：[课 21《自定义管理命令与 System checks》](./lesson-21-自定义管理命令与System checks.md)
- 📖 阶段概览：[阶段 6：工程化与生产](../overview.md)
- 📚 课程目录：[02-课程目录.md](../../../02-课程目录.md)
- 🏠 学习路径：[01-学习路径总览.md](../../../01-学习路径总览.md)
- 🎓 结课项目：[projects/orderflow/](../../../projects/orderflow/README.md)（Phase 3，**✅ 2026-09-04 已交付**）

> 📌 **阶段 6 进度**：课 18、19、20、21、22 全部完成（**5/5**）。
> 📌 **全课程进度**：22 课全部完成，下一步进入 Phase 3 结课实战项目。
