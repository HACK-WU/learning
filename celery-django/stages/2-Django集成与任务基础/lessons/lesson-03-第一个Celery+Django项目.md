# 第 3 课：第一个 Celery + Django 项目

> 所属阶段：阶段 2《Django 集成与任务基础》｜ 水平：入门 ｜ 本课知识点：环境与 Broker 选型、Django 标准集成姿势、@shared_task 与常用任务参数
> 故事情节：主角正式"入职" —— 从今天起它不再是概念，而是一段真实跑在你机器上的代码。第一道关卡：把它安顿到正确的位置

> ℹ️ **版本基线（核查于 2026-08）**：本文所有版本号、最低依赖要求均对照 Celery 5.6 官方 `whatsnew` 与官方文档核实。

## 🎯 本课目标

- 根据任务特征在 Redis / RabbitMQ 之间做出**有依据**的选型，而不是"别人用啥我用啥"
- 从零搭出官方标准的三步集成骨架，并**说清每一行的为什么**（而不只是抄）
- 正确地定义任务：统一用 `@shared_task`、显式命名、配置超时与重试

---

## 第一幕：场景引入

阶段 1 学完了，你摩拳擦掌准备在项目里落地。打开官方文档，还没写第一行代码就卡住了——因为**每个选择都有人踩过坑**：

**选择一：Broker 用什么？**
你搜了一圈，有人说"Redis 简单，够用"，有人说"生产必须 RabbitMQ，Redis 会重复执行任务"。谁对？

**选择二：`celery.py` 放哪？**
博客 A 把它放在项目根目录（和 `manage.py` 同级），博客 B 放在 `proj/proj/`（和 `settings.py` 同级）。官方文档用的是 B。差在哪？

**选择三：`@app.task` 还是 `@shared_task`？**
你照着教程抄了 `@app.task`，任务死活注册不上；换成 `@shared_task` 就好了。**为什么？**

🎬 **场景**：你要给内部的运营平台接入 Celery。这个决定一旦落地，后面几十个任务、几个月的运维都要建立在它之上。**选错骨架的代价，比选错一行代码的代价高得多。**

---

## 第二幕：认知冲突

你决定"先跑起来再说"，于是 `pip install celery`，照着博客抄了一遍，然后——

```bash
$ celery -A proj worker -l INFO
[ERROR] Cannot connect to redis://localhost:6379/0: Error 111 connecting to localhost:6379. Connection refused.
```
> 哦，broker 没起。装一个。

```bash
$ python manage.py shell -c "from reports.tasks import generate_statement; generate_statement.delay(1, '2026-08')"
celery.exceptions.NotRegistered: 'reports.tasks.generate_statement'
```
> 任务没注册上？可我明明写了 `@app.task` 啊。

```bash
$ celery -A proj worker -l INFO
[ERROR] AttributeError: module 'proj' has no attribute 'celery'
```
> app 找不到？`celery.py` 我放了啊……

❓ **问题**：为什么"能跑起来"和"能跑对"之间隔着这么多坑？**这三个选择背后的判断依据到底是什么？**

---

## 第三幕：层层揭示

### 知识点 1：环境与 Broker 选型

> 关键点：Redis vs RabbitMQ 的取舍维度 ／ 版本矩阵与依赖安装 ／ 本地起 broker（Docker 一条命令）

#### 一句话定义

Broker 选型的本质是回答一个问题：**你需要 broker 提供多精确的"投递语义"？** Redis 用运维简单换语义精度，RabbitMQ 用运维复杂度换语义完整。

#### 直觉建立（类比）

| Broker | 类比 | 特点 |
|--------|------|------|
| **Redis** | **便利店** | 快、便宜、就在楼下（多半你已经在用它做缓存了）；品类有限，但日常够用 |
| **RabbitMQ** | **大型仓储超市** | 品类齐全（原生 ack、交换机、优先级、quorum queue）、管理规范（管理台、vhost、权限）；但**得专门派人管它**（Erlang 节点、集群、监控） |

> 💡 **类比的边界**：便利店不是"没有收银台"，只是它的收银方式更简单——这恰恰是问题所在。Redis **不是没有 ack 机制**，而是用 `visibility_timeout`（默认 1 小时）**模拟** ack，这个模拟有个致命副作用：**任务跑太久，会被当成"人跑了"而重新上架**。RabbitMQ 用的是真正的消费者 ack。

#### 核心原理

**能力对比表**：

| 维度 | Redis | RabbitMQ |
|------|-------|----------|
| **确认机制** | `visibility_timeout` **模拟**（默认 3600s） | ✅ **原生 consumer ack** |
| **长任务（> 1h）** | ⚠️ 超时会被**重复投递** | ✅ 只要没 ack 就不会被别人拿走 |
| **延迟任务（ETA/countdown）** | ⚠️ 靠内存里持有消息；**ETA 必须 < visibility_timeout**，否则无限重投 | ✅ 原生支持（5.5+ 支持 quorum queue 的 native delayed delivery） |
| **路由能力** | 基础（kombu 用 `_kombu.binding.*` **模拟** exchange） | ✅ 完整的 exchange / binding / vhost |
| **优先级队列** | 有限支持 | ✅ 原生 |
| **持久化** | 依赖 RDB/AOF，极端情况会丢 | ✅ 更可靠的持久化与镜像队列 |
| **运维成本** | **低**（多半已有 Redis，可顺便用） | 高（单独部署 + 监控 Erlang 节点 + 管集群） |
| **官方定位** | feature complete | feature complete |

> ⚠️ **别被 "feature complete" 骗了**：Celery 官方文档说 "The RabbitMQ and Redis broker transports are feature complete"——这话的意思是**"功能都有"**，**不等于"语义等价"**。功能都能用，但实现方式和可靠性不同。

#### 决策规则（直接照着选）

```mermaid
flowchart TD
    A[开始选型] --> B{团队是否已有 Redis<br/>且不想多运维一个组件?}
    B -- 否 --> C[RabbitMQ]
    B -- 是 --> D{任务是否存在以下任一情况?<br/>① 单次执行可能 > 1 小时<br/>② 需要精确的延迟任务 ETA > 1h<br/>③ 需要复杂路由 / 优先级 / vhost 隔离<br/>④ 重复执行的业务代价很高}
    D -- 是 --> C
    D -- 否 --> E[Redis ✅]
    E --> F[⚠️ 配套两个动作:<br/>1. 调大 visibility_timeout<br/>2. 业务侧做幂等]
    C --> G[⚠️ 配套一个动作:<br/>接受更高的运维成本]
    style E fill:#e8f5e9,stroke:#2e7d32
    style C fill:#e3f2fd,stroke:#1565C0
    style F fill:#fff3e0,stroke:#ef6c00
```

**一句话版**：

- **选 Redis**：团队已有 Redis、任务是秒级/分钟级、能接受"至少一次" + 自己做幂等、不想多运维一个组件 → **80% 的 Django 项目从这里起步**
- **选 RabbitMQ**：任务长且时间不可控、需要可靠的延迟任务、需要复杂路由、业务上"重复执行一次"代价很高
- **过渡思路**：先用 Redis，等真的出现"任务被重复执行"或"延迟任务不准"的痛点再迁。**Celery 的代码不用改，只改 `CELERY_BROKER_URL`**——这正是 broker 抽象的价值

#### 版本矩阵（核查于 2026-08）

| 组件 | 版本 / 要求 | 说明 |
|------|------------|------|
| **Celery** | **5.6.x**（代号 *Recovery*，当前稳定版） | 5.6.3 于 2026-03 发布 |
| **Python** | **3.9 / 3.10 / 3.11 / 3.12 / 3.13** + PyPy3.11 | ⚠️ 5.6 起**不再支持 Python 3.8**（3.8 请用 Celery ≤ 5.5） |
| **Django** | **≥ 2.2.28** | ⚠️ Celery 5.6 把最低 Django 版本从 2.2 LTS 抬到了 **2.2.28** |
| **Kombu** | ≥ **5.6** | Celery 5.6 起的最低要求 |
| **redis-py** | ≥ **4.5.2** | Celery 5.6 起的最低要求 |
| **billiard** | ≥ **4.2.4** | prefork 池依赖 |
| django-celery-beat | **2.9.0**（2026-02 发布） | 已支持 Django 6.0 / 6.1，移除了 Django 版本上限 |
| django-celery-results | **2.6.0**（2026-04 发布） | 结果存进 Django 数据库 |

#### 示例演示：安装与起 broker

```bash
# ① 安装 —— 用 bundle 一次装齐 Redis 传输 + 结果后端的依赖
pip install "celery[redis]==5.6.*" "django>=4.2"

# 验证
python -c "import celery, kombu, redis; print(celery.__version__, kombu.__version__, redis.__version__)"
# → 5.6.3 5.6.x 7.x
```

> 💡 **为什么用 `celery[redis]` 而不是 `celery`？** 裸装 `celery` 不含 `redis-py`，跑起来会报 "Redis transport requires redis-py"。bundle 一次装齐，省一个排查回合。

```bash
# ② 本地起 Redis（Docker 一条命令）
docker run -d --name celery-redis -p 6379:6379 redis:7-alpine

docker exec -it celery-redis redis-cli ping
# → PONG
```

```bash
# （可选）想体验 RabbitMQ
docker run -d --name celery-rabbit -p 5672:5672 -p 15672:15672 rabbitmq:4-management
# 管理台：http://localhost:15672   默认账号 guest/guest
# 对应配置：CELERY_BROKER_URL = 'amqp://guest:guest@localhost:5672//'
```

#### 常见误区

1. **"`pip install celery` 就够了"**
   Redis 传输需要 `redis-py`，结果后端也需要它。**用 `celery[redis]` bundle**，一次装齐。

2. **"Redis 说 feature complete，那和 RabbitMQ 没区别"**
   feature complete ≠ 语义等价。Redis 靠 `visibility_timeout` **模拟** ack，长任务会被重复投递。这是线上事故的高发区（课 5 详解）。

3. **"生产环境 broker 和缓存共用同一个 Redis 实例"**
   ⚠️ **危险**。两个问题：
   - 缓存的 `maxmemory-policy`（淘汰策略）可能把队列 key 淘汰掉，导致 `InconsistencyError: Probably the key ('_kombu.binding.celery') has been removed`
   - 缓存流量会挤占队列的带宽与内存
   
   **最低要求：用不同的 db 号；推荐：用独立实例。**

#### 一句话记住

> **选 broker 就是选"你愿意为可靠性付出多少运维成本"——Redis 用简单换精度，RabbitMQ 用复杂度换完整。**

#### 官方文档

- Brokers 总览：https://docs.celeryproject.org/en/stable/getting-started/backends-and-brokers/index.html
- Using Redis：https://docs.celeryproject.org/en/stable/getting-started/backends-and-brokers/redis.html
- Using RabbitMQ：https://docs.celeryproject.org/en/stable/getting-started/backends-and-brokers/rabbitmq.html

---

### 知识点 2：Django 标准集成姿势

> 关键点：`proj/proj/celery.py` 为何放这里 ／ `__init__.py` 暴露 app 的作用 ／ `config_from_object(namespace='CELERY')` ／ `autodiscover_tasks` 与 tasks.py 约定

#### 一句话定义

Django 集成的核心是一个**三步骨架**：在项目包里创建 app → 在 `__init__.py` 里暴露 → 靠 `autodiscover_tasks()` 自动收集各 app 的任务。目的是**让 Celery app 在 Django 启动时就唯一地存在**。

#### 直觉建立（类比）

公司要设一个"工单中心"，三件事必须做对：

| 步骤 | 类比 | 对应代码 |
|------|------|---------|
| ① 有唯一的办公地点 | 工单中心得有个固定地址 | `celery.py` 里 `app = Celery('proj')` |
| ② 所有人上班第一眼就能看到它 | 地址写进员工手册，进公司就发下去 | `__init__.py` 里 `from .celery import app` |
| ③ 各部门知道往哪交单 | 自动通知所有部门"单据交到这儿" | `autodiscover_tasks()` 扫各 app 的 `tasks.py` |

> 💡 **类比的边界**：`autodiscover_tasks()` 只扫 `INSTALLED_APPS` 下名为 **`tasks.py`** 的模块。你要是把任务写在 `services.py` 或 `jobs.py` 里，它扫不到——要么遵守约定，要么用 `imports` 配置项显式列出来。

#### 核心原理：官方骨架逐行拆解

```mermaid
sequenceDiagram
    autonumber
    participant D as Django 启动
    participant I as proj/__init__.py
    participant C as proj/celery.py
    participant S as settings.py
    participant T as 各 app 的 tasks.py
    participant W as celery worker

    D->>I: 加载 proj 包
    I->>C: from .celery import app as celery_app
    C->>C: ① setdefault('DJANGO_SETTINGS_MODULE')
    C->>C: ② app = Celery('proj')
    C->>S: ③ config_from_object(namespace='CELERY')
    C->>T: ④ autodiscover_tasks() → 扫 tasks.py
    T-->>C: @shared_task 注册进 app
    W->>C: celery -A proj → 拿到同一个 app
    Note over C: ⑤ 同一个 app = Web 端与 worker 端<br/>看到完全相同的任务注册表
```

**文件一：`proj/proj/celery.py`（新建）**

```python
import os

from celery import Celery

# ① 给 celery 命令行程序设默认 settings 模块
#    必须在创建 app 之前 —— 否则 celery 命令找不到 Django 配置
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'proj.settings')

# ② 创建 Celery 应用实例（名字一般跟项目同名）
app = Celery('proj')

# ③ 从 Django settings 读取配置
#    - 用字符串 'django.conf:settings' 而不是 import 对象：
#      worker 用 prefork 会 fork 子进程，传字符串不必序列化配置对象
#    - namespace='CELERY'：所有 Celery 配置必须写成 CELERY_XXX 大写前缀
app.config_from_object('django.conf:settings', namespace='CELERY')

# ④ 自动发现各 app 下的 tasks.py
app.autodiscover_tasks()


@app.task(bind=True, ignore_result=True)
def debug_task(self):
    print(f'Request: {self.request!r}')
```

**文件二：`proj/proj/__init__.py`（修改）**

```python
# 保证 Django 启动时这个 app 一定被加载，
# 这样 @shared_task 才能找到"该注册到哪个 app"
from .celery import app as celery_app

__all__ = ('celery_app',)
```

#### 四个"为什么"（面试和排查都爱问）

| 写法 | 为什么必须这样 | 不这样的后果 |
|------|---------------|-------------|
| `celery.py` 放在 **`proj/proj/`**（与 `settings.py` 同级） | 它是**项目包的一部分**，`celery -A proj` 会按约定去找 `proj.celery` 模块 | 放错位置 → `AttributeError: module 'proj' has no attribute 'celery'` |
| 用**字符串** `'django.conf:settings'` | worker 用 prefork 会 **fork 子进程**；传对象需要序列化，传字符串不需要 | 传对象会在 fork 时报错或产生额外开销 |
| `namespace='CELERY'` | 防止 Celery 配置与 Django 配置**命名冲突** | 不写的话要用小写 `broker_url` 混在 Django settings 里，极易撞车 |
| **`__init__.py` 里 import** | `@shared_task` **本身不知道**要注册到哪个 app，它依赖"运行时已存在一个 app 实例" | 不 import → `ImproperlyConfigured: No celery app instance has been configured` |

#### ⚠️ 为什么 `@shared_task` 非得有 `__init__.py` 这一行？

这是新手第一大坑，值得单独讲：

```python
# @app.task：任务在定义时就绑定到具体的 app
from proj.celery import app      # ← 必须 import app

@app.task
def foo(): ...


# @shared_task：任务与具体 app 解耦，运行时才绑定
from celery import shared_task   # ← 不需要 import app

@shared_task
def foo(): ...
```

`@shared_task` 创建的是一个"**与具体 app 解耦**"的任务。它的价值：让你写**可复用的 Django app / 第三方包**时，不必依赖使用方的项目结构（第三方包怎么知道你的项目叫 `proj`？）。

**代价**：必须保证调用时**已经存在**一个 app 实例。这个保证就是 `__init__.py` 那一行提供的。

#### 文件三：`proj/proj/settings.py`（追加配置）

```python
# ① 时区（后面 beat 定时任务会用到，现在先设对）
TIME_ZONE = 'Asia/Shanghai'
USE_TZ = True

INSTALLED_APPS = [
    # ...
    'reports',        # 你的 app 必须注册，autodiscover 才会去扫它的 tasks.py
]

# ② Celery 配置（CELERY_ 前缀，全大写）
CELERY_BROKER_URL = 'redis://localhost:6379/0'       # 队列用 db0
CELERY_RESULT_BACKEND = 'redis://localhost:6379/1'   # 结果用 db1（与 broker 分开）
CELERY_TASK_TRACK_STARTED = True                     # 能看到 STARTED 状态（课 2 讲过）
CELERY_TASK_TIME_LIMIT = 30 * 60                     # 硬超时 30 分钟

# ③ 安全基线（显式声明，别依赖默认值）
CELERY_TASK_SERIALIZER = 'json'
CELERY_RESULT_SERIALIZER = 'json'
CELERY_ACCEPT_CONTENT = ['json']                     # 只接受 json，拒绝 pickle
```

> 💡 **为什么 broker 和 result backend 用不同的 db 号？**
> ① 监控队列长度时（`KEYS celery` / `LLEN celery`）不会被成千上万个结果 key 淹没；② 结果过期清理不会误伤队列。**用同一个 db 也能跑，但排查时会很难受。**

#### 怎么验证"任务真的注册上了"？

这是搭骨架时最高频的自检需求。三种方式，**按推荐度排序**：

```bash
# 方式 1（推荐）：不需要起 worker，直接在 Django shell 里列
python manage.py shell -c "
from proj.celery import app
print([t for t in sorted(app.tasks) if not t.startswith('celery.')])
"
# → ['proj.celery.debug_task', 'reports.generate_statement']
```

```bash
# 方式 2：起 worker，看启动日志的 [tasks] 段（第四幕会详细看）
celery -A proj worker -l INFO
# → [tasks]
#     . proj.celery.debug_task
#     . reports.generate_statement
```

```bash
# 方式 3：worker 已在跑的前提下，远程查询
celery -A proj inspect registered
# ⚠️ 这条必须有 worker 在线，否则报 No nodes replied within time constraint
#    它问的是"worker 注册了什么"，不是"我代码里有什么"
```

> 🎯 **方式 1 与方式 3 的区别要分清**：方式 1 查的是**你自己进程里的 app**（代码层面）；方式 3 查的是**远端的 worker**（运行层面）。`NotRegistered` 报错的本质就是**这两者不一致**——你投递的任务名，worker 那边的注册表里没有。

#### 常见误区

1. **`celery.py` 放错位置**
   必须放在**项目包内**（`proj/proj/`，与 `settings.py` 同级）。放到 `manage.py` 同级虽然某些情况下也能跑，但导入路径会变得脆弱，且不符合官方约定。

2. **忘记在 `__init__.py` 里 import**
   → 视图里调 `delay()` 报 `ImproperlyConfigured: No celery app instance has been configured`。**新手第一大坑。**

3. **配了 `namespace='CELERY'`，settings 里却用小写配置名**
   ```python
   broker_url = 'redis://...'          # ❌ 配了 namespace 后这样写，Celery 完全读不到
   CELERY_BROKER_URL = 'redis://...'   # ✅
   ```
   表现为"**明明配了 Redis，worker 却去连 RabbitMQ**"（因为读不到就退回默认值）。

4. **app 没加进 `INSTALLED_APPS` 却期待 `autodiscover_tasks()` 扫到它**
   `autodiscover` 只扫 `INSTALLED_APPS` 里已注册的应用。

#### 一句话记住

> **三步骨架 = `celery.py` 建 app → `__init__.py` 暴露 → `autodiscover` 收任务；少了第二步，`shared_task` 就找不到家。**

#### 官方文档

- Celery 与 Django 集成（官方）：https://docs.celeryproject.org/en/stable/django/first-steps-with-django.html

---

### 知识点 3：@shared_task 与常用任务参数

> 关键点：shared_task vs app.task（循环导入）／ bind 与 self.request ／ name / max_retries / soft_time_limit ／ 任务命名规范 ／ 薄任务体

#### 一句话定义

`@shared_task` 是"**不绑定具体 app 实例**"的任务装饰器，是 Django 项目里定义任务的**标准写法**；任务参数则决定了这个任务的**身份、重试行为和超时边界**。

#### 直觉建立（类比）

- `@app.task` = 直接把名字**写进某本特定的公司花名册**（你得先把花名册拿到手 = import app）
- `@shared_task` = 填一张**通用入职表**，交给哪家公司都行（只要现场有一本花名册）

> 💡 **类比的边界**："通用"是有代价的——它必须等别人先把花名册摆出来。如果 Django 没启动就 import 它，会直接报 `ImproperlyConfigured`。

#### 核心原理

**① `@shared_task` vs `@app.task`**

```python
# ❌ 可复用的 Django app 里不要这样写 —— 会造成循环导入 / 硬编码项目名
from proj.celery import app        # ← 第三方包怎么知道你的项目叫 proj？

@app.task
def generate_statement(...): ...
```

```python
# ✅ 标准写法
from celery import shared_task

@shared_task
def generate_statement(...): ...
```

| | `@app.task` | `@shared_task` |
|---|------------|----------------|
| 需要 import app 实例 | ✅ 需要 | ❌ 不需要 |
| 循环导入风险 | 有（app 模块要 import 任务模块时） | 无 |
| 适合场景 | 单体项目里你自己的任务 | **可复用的 Django app / 第三方包** |
| 前置条件 | app 已创建 | 运行时必须存在 app（靠 `__init__.py` 保证） |

**结论**：在 Django 项目里**统一用 `@shared_task`**。它更灵活，且没有额外成本。

**② `bind=True` 与 `self.request`**

```python
from celery import shared_task

@shared_task(bind=True)
def generate_statement(self, user_id, month):
    # self 是任务实例本身（Task 对象）
    print(self.request.id)         # 当前任务 id
    print(self.request.retries)    # 已重试次数
    print(self.request.args)       # 位置参数
    print(self.request.kwargs)     # 关键字参数
    print(self.request.hostname)   # 执行它的 worker 名

    # bind=True 才有 self，才能手动重试（课 5 详解）
    try:
        do_work()
    except TransientError as exc:
        raise self.retry(exc=exc, countdown=60)
```

⚠️ `bind=True` 后**第一个参数永远是 `self`**，但**调用时不用传**：

```python
generate_statement.delay(1, "2026-08")    # 只传 user_id, month，self 由 Celery 注入
```

**`self.request` 常用字段**（排查问题时救命）：

| 字段 | 用途 |
|------|------|
| `id` | 任务 id —— **用它串联全链路日志**（课 10） |
| `retries` | 当前是第几次重试 |
| `is_eager` | 是否同步执行（`CELERY_TASK_ALWAYS_EAGER` 打开时） |
| `hostname` | 哪个 worker 执行的（定位"某台机器有问题"） |
| `delivery_info` | 消息的投递信息（被重投的次数、路由） |
| `called_directly` | 是否被直接调用（而非走队列） |

**③ 常用参数速查**

```python
@shared_task(
    bind=True,
    name='reports.generate_statement',    # 显式任务名（强烈推荐）
    max_retries=3,                        # 最多重试 3 次
    default_retry_delay=60,               # 重试间隔 60 秒
    soft_time_limit=300,                  # 软超时 5 分钟（可捕获做清理）
    time_limit=360,                       # 硬超时 6 分钟（直接 kill 子进程）
    ignore_result=False,                  # 是否存结果
    acks_late=True,                       # 执行完才 ack（⚠️ 需配套幂等，课 5）
    autoretry_for=(TransientError,),      # 遇到这些异常自动重试（课 5）
    rate_limit='10/m',                    # 限流：每分钟 10 个（课 9）
)
def generate_statement(self, user_id, month):
    ...
```

| 参数 | 默认值 | 作用 | 不设的后果 |
|------|--------|------|-----------|
| `name` | `模块路径.函数名` | 任务在 broker 里的"身份证" | **重构模块路径后，旧消息找不到任务 → `NotRegistered`** |
| `max_retries` | **3** | 最大重试次数 | — |
| `default_retry_delay` | **180**（3 分钟） | 重试间隔 | — |
| `soft_time_limit` | 无 | 抛 `SoftTimeLimitExceeded`，**可被捕获做清理** | 长任务卡死没人管 |
| `time_limit` | 无 | 硬杀子进程 | **僵尸任务永久占着 worker 槽位** |
| `acks_late` | **False** | 执行完才 ack | **任务丢失**（课 2 已亲手复现） |
| `ignore_result` | **False** | 不存结果 | Redis 被结果撑爆 |

> 🎯 **`soft_time_limit` vs `time_limit` 的区别很重要**：软超时抛异常（你的代码能 `try/except` 捕获并优雅清理，比如关文件、回滚状态）；硬超时直接 kill 子进程（没有任何清理机会）。**生产任务至少配 `time_limit` 兜底，长任务两个都配。**

**④ 任务命名规范**（重要但常被忽略）

```python
# ❌ 默认命名 = 模块路径 + 函数名
@shared_task
def generate_statement(user_id, month): ...
# → 任务名: reports.tasks.generate_statement
```

**问题在哪？** 任务名会被**写进 broker 的消息里**（课 2 消息体的 `task` 字段）。一旦你把 `tasks.py` 拆成 `tasks/` 包、或者把函数挪到别的模块，**已经在队列里的旧消息就找不到任务了 → `NotRegistered`**。

```python
# ✅ 显式命名：把"外部契约"和"内部代码结构"解耦
@shared_task(name='reports.generate_statement')
def generate_statement(user_id, month): ...
```

**推荐规范**：`{app_label}.{action}_{object}`，全小写、点分隔、动词开头

```
reports.generate_statement
orders.export_order
notifications.send_email
```

> 💡 这个思路和你熟悉的资源命名风格（如 `resource.issue.list_user_tapd_workspace`）是同一个道理——**用显式名字把对外契约与内部代码结构解耦**，让重构不破坏线上正在跑的消息。

**⑤ 任务该放哪、代码该长啥样**

**约定**：`yourapp/tasks.py`（`autodiscover_tasks()` 只认这个文件名）

```python
# reports/tasks.py
import logging

from celery import shared_task

logger = logging.getLogger(__name__)


@shared_task(
    bind=True,
    name='reports.generate_statement',
    max_retries=3,
    soft_time_limit=300,
    time_limit=360,
)
def generate_statement(self, user_id, month):
    """生成月度对账单。

    注意：参数只传 id / 字符串，不传 ORM 对象（课 6 详解为什么）。
    """
    logger.info('[%s] 开始生成报表 user_id=%s month=%s',
                self.request.id, user_id, month)
    try:
        url = _do_generate(user_id, month)     # 真正的业务逻辑抽成普通函数
        logger.info('[%s] 生成完成 url=%s', self.request.id, url)
        return {'url': url}
    except Exception:
        logger.exception('[%s] 生成失败', self.request.id)
        raise


def _do_generate(user_id, month):
    """真正的业务逻辑 —— 这是普通函数，不依赖 Celery，可以单独测试。"""
    ...
```

> 🎯 **关键设计：任务函数要"薄"。** 它只负责四件事——**取参数、打日志、控制重试、转译异常**；真正的业务逻辑抽成普通函数（`_do_generate`）。
> **收益**：① 业务逻辑可以脱离 Celery 单独单元测试；② 未来换成别的任务框架，业务代码一行不用改。

#### 常见误区

1. **"`bind=True` 之后调用要传 `self`"** → 不用，`self` 由 Celery 自动注入。
2. **"任务参数可以传 ORM 对象"** → 千万别。消息要 JSON 序列化，传对象要么直接失败，要么传出一份**过期快照**。**传 id**（课 6 详解）。
3. **"任务名用默认的就行，反正能跑"** → 重构时会炸。显式命名是**零成本高回报**。
4. **"把业务逻辑全写在任务函数里"** → 难测试、难复用、难迁移。任务必须薄。
5. **"超时配置以后再说"** → 没配 `time_limit` 的任务一旦卡死，会**永久占住一个 worker 槽位**，攒够几个就把整个 worker 堵死。

#### 一句话记住

> **`@shared_task` + 显式 `name` + 薄任务体 —— 这是 Django 项目里写任务的"三件套习惯"。**

#### 官方文档

- Tasks 用户指南：https://docs.celeryproject.org/en/stable/userguide/tasks.html
- 配置与默认值：https://docs.celeryproject.org/en/stable/userguide/configuration.html

---

## 第四幕：实操验证

> 完整走一遍：**从零目录 → worker 跑起 → 任务执行成功 → 结果取回**。建议跟着敲一遍，不要只读。

### ① 环境准备

```bash
pip install "celery[redis]==5.6.*" "django>=4.2"
docker run -d --name celery-redis -p 6379:6379 redis:7-alpine
docker exec -it celery-redis redis-cli ping      # → PONG
```

### ② 建项目骨架

```bash
django-admin startproject proj
cd proj
python manage.py startapp reports
```

目标结构：

```
proj/
├── manage.py
├── proj/
│   ├── __init__.py      ← 要改
│   ├── celery.py        ← 新建
│   ├── settings.py      ← 要改
│   ├── urls.py
│   └── wsgi.py
└── reports/
    ├── __init__.py
    ├── models.py
    ├── tasks.py         ← 新建
    └── views.py
```

### ③ 写四个文件

按「第三幕」的代码片段依次创建/修改：

1. 新建 `proj/proj/celery.py`（官方骨架）
2. 修改 `proj/proj/__init__.py`（加 `from .celery import app as celery_app`）
3. 修改 `proj/proj/settings.py`（加 `INSTALLED_APPS += ['reports']` + `CELERY_*` 配置块）
4. 新建 `reports/tasks.py`：

以下这份**可直接复制运行**（`_do_generate` 用 `time.sleep` 模拟真实耗时，让你能完整看到"投递 → 执行 → 结果回传"的全链路）：

```python
# reports/tasks.py
import logging
import time

from celery import shared_task

logger = logging.getLogger(__name__)


@shared_task(
    bind=True,
    name='reports.generate_statement',
    max_retries=3,
    soft_time_limit=300,
    time_limit=360,
)
def generate_statement(self, user_id, month):
    """生成月度对账单（演示版：用 sleep 模拟 8 秒的真实耗时）。"""
    logger.info('[%s] 开始生成报表 user_id=%s month=%s',
                self.request.id, user_id, month)
    try:
        url = _do_generate(user_id, month)
        logger.info('[%s] 生成完成 url=%s', self.request.id, url)
        return {'url': url, 'user_id': user_id, 'month': month}
    except Exception:
        logger.exception('[%s] 生成失败', self.request.id)
        raise


def _do_generate(user_id, month):
    """真正的业务逻辑 —— 普通函数，不依赖 Celery，可单独测试。

    演示版：睡 8 秒模拟"拉数据 + 聚合 + 渲染 PDF + 上传"。
    真实项目里这里会是 ORM 查询 + PDF 渲染 + 对象存储上传。
    """
    time.sleep(8)
    return f'/media/stmt-{user_id}-{month}.pdf'
```

> 💡 第 1–3 步的代码请对照「第三幕」对应小节复制（那里有逐行注释的版本）。**第 4 步用上面这份完整版**，保证你能一次跑通并看到结果。

### ④ 四步验证

**步骤 1：起 worker，确认三件事**

```bash
celery -A proj worker -l INFO
```

预期日志（**重点看这三行**）：

```
 -------------- celery@DESKTOP-XXX v5.6.3 (recovery)
--- ***** -----
-- ******* ---- [config]
- *** --- * --- .> app:         proj:0x1f2a3b4c5d6          ← ① app 找到了
- ** ---------- .> transport:   redis://localhost:6379/0    ← ② broker 配对了
- ** ---------- .> results:     redis://localhost:6379/1
- *** --- * --- .> concurrency: 8 (prefork)
-- ******* ---- .> task events: OFF

[tasks]                                                     ← ③ autodiscover 生效
  . proj.celery.debug_task
  . reports.generate_statement
```

> ✅ 这三行分别验证了：`celery.py` 位置对、`CELERY_BROKER_URL` 读到了、`autodiscover_tasks()` 扫到了你的任务。**任何一行不对，回头检查对应环节。**

**步骤 2：投递任务**

```bash
python manage.py shell -c "
from reports.tasks import generate_statement
r = generate_statement.delay(1, '2026-08')
print(r.id, r.status)
"
# → 3f9a1c2e-7b41-4f0a-9d3e-1c8a5b2e7f10 PENDING
```

worker 日志：

```
[INFO/MainProcess] Received task: reports.generate_statement[3f9a1c2e-...]
[INFO/ForkPoolWorker-1] [3f9a1c2e...] 开始生成报表 user_id=1 month=2026-08
[INFO/ForkPoolWorker-1] Task reports.generate_statement[3f9a1c2e...] succeeded in 8.02s: {'url': '/media/stmt-2026-08.pdf'}
```

**步骤 3：确认结果进了 backend**

```bash
redis-cli -n 1 KEYS 'celery-task-meta-*'
# 1) "celery-task-meta-3f9a1c2e-7b41-4f0a-9d3e-1c8a5b2e7f10"

redis-cli -n 1 GET celery-task-meta-3f9a1c2e-7b41-4f0a-9d3e-1c8a5b2e7f10
```
```json
{"status": "SUCCESS", "result": {"url": "/media/stmt-2026-08.pdf"},
 "traceback": null, "task_id": "3f9a1c2e-...", "date_done": "2026-08-31T02:20:15.123456"}
```

**步骤 4：取回结果**

```python
python manage.py shell -c "
from celery.result import AsyncResult
r = AsyncResult('3f9a1c2e-7b41-4f0a-9d3e-1c8a5b2e7f10')
print(r.status, r.result)
"
# → SUCCESS {'url': '/media/stmt-2026-08.pdf'}
```

### ⑤ 故意踩坑（验证你真的理解了）

```bash
# 把 proj/proj/__init__.py 里那行注释掉，然后重开一个 shell：
python manage.py shell -c "
from reports.tasks import generate_statement
generate_statement.delay(1, '2026-08')
"
```

```python
celery.exceptions.ImproperlyConfigured:
    No celery app instance has been configured...
```

> ✅ **回扣知识点 2**：这就是"**少了第二步，`shared_task` 就找不到家**"的实证。把那行改回来再试一次，立刻正常。

> ✅ **回扣第一幕的三个问题**——现在都有了明确答案：
>
> | 问题 | 答案 |
> |------|------|
> | Redis 还是 RabbitMQ？ | 看任务时长与是否需要精确延迟/路由（决策流程图） |
> | `celery.py` 放哪？ | `proj/proj/`，即**项目包内、与 settings.py 同级** |
> | `@app.task` 还是 `@shared_task`？ | **统一用 `@shared_task`**（解耦、无循环导入），并配显式 `name` |

---

## 第五幕：体系收束

> 📍 **全局定位**：你现在有了一个**能跑的完整 Django + Celery 项目**。阶段 2 的前半段（"能跑起来"）完成。
>
> 但请注意这个骨架的**三个已知隐患**（都是默认配置留下的），它们会在后面的课被逐个拆掉：
>
> | 隐患 | 默认配置 | 后果 | 修复在 |
> |------|---------|------|--------|
> | ① **任务会丢** | `acks_late=False` | worker 被 kill 时正在执行的任务永久消失 | **课 5** |
> | ② **任务会重** | 至少一次投递 | 重复执行产生重复扣款/发券 | **课 5** |
> | ③ **事务脏读** | 无 `on_commit` | 任务查不到刚创建的数据 | **课 6** |
>
> **换句话说：现在这个骨架能跑通，但还不能上生产。**
>
> 🔗 **下一步**：课 4《调用任务与取回结果》—— 你会学到 `delay()` 其实只是 `apply_async()` 的**语法糖**，以及怎么用 `countdown` / `eta` / `expires` / `queue` 精确控制投递，还有结果查询的正确姿势与 `get()` 的反模式。

---

## 🐞 常见误区（本课汇总）

1. **`pip install celery` 就够了** → 需要 `celery[redis]` bundle 才带 `redis-py`。
2. **"Redis feature complete = 和 RabbitMQ 等价"** → Redis 用 `visibility_timeout` 模拟 ack，长任务会被重复投递。
3. **broker 与缓存共用同一个 Redis 实例** → 会被 key 淘汰策略搞出 `InconsistencyError`；至少分 db，最好分实例。
4. **`celery.py` 放错位置** → 必须在项目包内（`proj/proj/`）。
5. **忘记 `__init__.py` 里 import** → `ImproperlyConfigured`，新手第一大坑。
6. **配了 `namespace='CELERY'` 却用小写配置名** → 静默退回默认值，"明明配了 Redis 却去连 RabbitMQ"。
7. **app 没进 `INSTALLED_APPS` 却期待 autodiscover 扫到** → 只扫已注册的应用。
8. **`bind=True` 后调用要传 `self`** → 不用，Celery 自动注入。
9. **任务参数传 ORM 对象** → 传 id（课 6 详解）。
10. **不显式命名任务** → 重构后旧消息 `NotRegistered`。
11. **业务逻辑全塞进任务函数** → 难测试难复用，任务要薄。
12. **不配超时** → 卡死的任务永久占住 worker 槽位。

## 一图总结

```mermaid
flowchart TB
    subgraph S1["① 选型"]
        A1{"任务 > 1h 或<br/>需精确延迟/复杂路由?"}
        A1 -- 是 --> A2["RabbitMQ<br/>原生 ack / 完整路由"]
        A1 -- 否 --> A3["Redis ✅<br/>够用 + 运维简单<br/>⚠️ 调大 visibility_timeout<br/>⚠️ 业务侧做幂等"]
    end

    subgraph S2["② 集成三步骨架"]
        B1["proj/proj/celery.py<br/>app = Celery('proj')<br/>config_from_object(namespace='CELERY')<br/>autodiscover_tasks()"]
        B2["proj/proj/__init__.py<br/>from .celery import app as celery_app<br/>⚠️ 少了它 shared_task 找不到家"]
        B3["settings.py<br/>CELERY_BROKER_URL = redis://.../0<br/>CELERY_RESULT_BACKEND = redis://.../1"]
        B1 --> B2 --> B3
    end

    subgraph S3["③ 定义任务"]
        C1["@shared_task（不用 import app）"]
        C2["name='reports.generate_statement'<br/>显式命名 = 契约与代码解耦"]
        C3["bind=True → self.request.id/retries<br/>soft_time_limit / time_limit / max_retries"]
        C4["薄任务体：只做调度·日志·重试·异常转译<br/>业务逻辑抽成普通函数"]
        C1 --> C2 --> C3 --> C4
    end

    S1 --> S2 --> S3 --> D["worker 日志三验证<br/>① app: proj<br/>② transport: redis://...<br/>③ [tasks] 里有你的任务"]
    style A3 fill:#e8f5e9,stroke:#2e7d32
    style A2 fill:#e3f2fd,stroke:#1565C0
    style B2 fill:#ffebee,stroke:#ef9a9a
    style C2 fill:#fff3e0,stroke:#ef6c00
    style D fill:#e8f5e9,stroke:#2e7d32
```

## 课后小测

**Q1**：关于 `__init__.py` 中 `from .celery import app as celery_app` 这一行，下列说法正确的是？

- A. 它的作用是让 `celery` 命令行工具能找到 Django 配置
- B. 它保证 Django 启动时 Celery app 被创建，使 `@shared_task` 能找到注册目标
- C. 只有在使用 `@app.task` 时才需要它
- D. 它的作用是触发 `autodiscover_tasks()`

<details><summary>答案与解析</summary>

**答案：B**。

`@shared_task` 创建的任务**与具体 app 解耦**，运行时才绑定。它依赖"调用时已存在一个 app 实例"——这个保证就来自 `__init__.py` 的 import。缺了它，调 `delay()` 会报 `ImproperlyConfigured: No celery app instance has been configured`。

- A 错，那是 `celery.py` 里 `os.environ.setdefault('DJANGO_SETTINGS_MODULE', ...)` 的活。
- C 正好说反了：`@app.task` 显式 import 了 app，反而不依赖这一行。
- D 错，`autodiscover_tasks()` 是在 `celery.py` 里主动调用的。

</details>

**Q2**：你把 `reports/tasks.py` 里的 `generate_statement` 函数迁移到了 `reports/jobs/statement.py`，同时给所有任务加了 `@shared_task(name='reports.generate_statement')`。部署时队列里还有旧消息。**最可能发生什么？**

- A. 旧消息全部失败，因为函数位置变了
- B. 旧消息能正常执行，因为显式 `name` 让任务名与代码位置解耦
- C. 旧消息会被 `autodiscover_tasks()` 跳过
- D. 需要同时修改 `CELERY_IMPORTS` 才能生效

<details><summary>答案与解析</summary>

**答案：B**。这正是**显式命名的核心价值**。

任务名被写进 broker 的消息体（`task` 字段）。如果不显式命名，任务名 = 模块路径 + 函数名，迁移后旧消息里的 `reports.tasks.generate_statement` 就找不到任务了 → `NotRegistered`。显式命名后任务名恒为 `reports.generate_statement`，**代码怎么搬都不影响正在跑的消息**。

⚠️ 但注意题干里有个陷阱：迁移到 `reports/jobs/statement.py` 后，**`autodiscover_tasks()` 扫不到了**（它只扫各 app 下的 `tasks.py`）。所以正确的完整做法是：在 `reports/jobs/__init__.py` 里 import 它，或把它加进 `CELERY_IMPORTS`。**本题考察的是"显式 name 让旧消息不受影响"这一点，B 成立。**

</details>

**Q3**：关于 Redis 和 RabbitMQ 作为 broker 的区别，下列说法**错误**的是？

- A. Redis 用 `visibility_timeout`（默认 1 小时）模拟 ack，任务超时会被重复投递
- B. Celery 官方文档称两者都是 "feature complete"，因此它们的行为语义完全等价
- C. 使用 Redis 时，`countdown` 的延迟时间必须小于 `visibility_timeout`，否则会被无限重投
- D. RabbitMQ 提供原生 consumer ack，长任务只要没 ack 就不会被其他 worker 取走

<details><summary>答案与解析</summary>

**答案：B**。**"feature complete" 指"功能都有"，不等于"语义等价"**——这是最容易踩的坑。

- A、C、D 都是正确描述。C 尤其重要：`apply_async(countdown=7200)`（2 小时）在默认 1 小时 `visibility_timeout` 下，消息会在 ETA 到期前就重新可见 → 被重新投递 → 重新排期 → **无限循环放大**。
- 选 Redis 时的配套动作：① 调大 `broker_transport_options = {'visibility_timeout': ...}`；② 业务侧做幂等。

</details>

---

## 🚀 下一批接力提示词

> 学完本批后，**复制下面这段文字发给 AI**，即可无缝进入下一批（无需重新描述上下文）：

```
继续学 Celery + Django。我的学习档案在 celery-django/00-学习档案.md，
刚学完阶段 2《Django 集成与任务基础》的课《第一个 Celery + Django 项目》知识点
「环境与 Broker 选型」「Django 标准集成姿势」「@shared_task 与常用任务参数」，
请按大纲继续讲解下一批知识点（课 4《调用任务与取回结果》）。
```

## 🧭 课程导航

⬅️ **上一课**：[第 2 课：Celery 架构全景与消息流转](../../1-异步化的动因与Celery全景/lessons/lesson-02-Celery架构全景与消息流转.md)

➡️ **下一课**：[第 4 课：调用任务与取回结果](lesson-04-调用任务与取回结果.md)

📚 **返回目录**：[课程目录](../../02-课程目录.md)
