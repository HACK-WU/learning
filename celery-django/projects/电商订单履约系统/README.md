# 实战项目：电商订单履约系统

> 所属课程：Celery 与 Django 集成 ｜ 学习目标：**动手实操为主**（兼顾概念理解与生产实战）｜ 预计耗时：**6-8 小时**
> 环境基线：Python 3.12.3 ｜ Django **6.1** ｜ Celery **5.6.3** ｜ kombu 5.6.2 ｜ Redis **7.0.15** ｜ Flower 2.1.0（本机 2026-08 实测）

## 🎯 一句话需求

**做一个能扛住"双十一零点"的电商订单履约系统**：下单后 15 分钟未支付自动关单并回滚库存，支付成功后异步走「发券 → 通知 → 对账」编排链路，全程可观测、可排查，且任何环节崩溃都不能造成重复扣款或库存超卖。

## ✅ 目标与非功能约束

- **功能目标**：
  1. 订单创建后发起 15 分钟超时关单（未支付 → 关单 + 回滚库存）
  2. 支付成功后异步执行履约编排（发优惠券 + 发通知 + 写对账），任一步失败不影响主流程
  3. 提供订单状态查询接口，可查任务执行进度与失败原因

- **非功能约束**（4 项）：

| 约束 | 具体要求 |
|------|---------|
| **正确性** | 关单任务重复执行 N 次，库存**只能回滚 1 次**（幂等）；worker 被 SIGKILL 后任务必须能被重新执行且不丢 |
| **错误处理** | 外部依赖（短信/优惠券服务）超时或 5xx 必须自动重试；重试耗尽后进入死信队列，不阻塞其他订单 |
| **性能** | 快任务（通知）P99 < 1s，不被慢任务（对账，每件 2s）堵住 —— 队列隔离 |
| **可观测性** | 每条日志带 `task_id`，能从"用户投诉"反查到具体任务的执行记录 |
| **安全** | `accept_content = ['json']`，禁用 pickle；broker 带密码 |

## 🗺️ 覆盖知识点地图

> **这是"跨阶段整合"的证据，逐个回指课时。**

| # | 知识点 | 所属阶段 / 课 | 本项目用在何处 | 回指 |
|---|--------|--------------|---------------|------|
| 1 | 同步请求里的慢活儿 | 阶段 1 · 课 1 | 下单/支付接口不直接发短信、不直接对账 | [lesson-01](../../stages/1-异步化的动因与Celery全景/lessons/lesson-01-为什么需要异步任务.md) |
| 2 | 三大件 Producer / Broker / Worker | 阶段 1 · 课 2 | 整体架构：Django = Producer，Redis = Broker | [lesson-02](../../stages/1-异步化的动因与Celery全景/lessons/lesson-02-Celery架构全景与消息流转.md) |
| 3 | Result Backend 与任务状态机 | 阶段 1 · 课 2 | 前端轮询订单履约进度 | [lesson-02](../../stages/1-异步化的动因与Celery全景/lessons/lesson-02-Celery架构全景与消息流转.md) |
| 4 | Django 标准集成姿势 | 阶段 2 · 课 3 | `proj/celery.py` + `autodiscover_tasks` | [lesson-03](../../stages/2-Django集成与任务基础/lessons/lesson-03-第一个Celery+Django项目.md) |
| 5 | `@shared_task` 与常用任务参数 | 阶段 2 · 课 3 | 各任务的参数配置（`bind`、`ignore_result`） | [lesson-03](../../stages/2-Django集成与任务基础/lessons/lesson-03-第一个Celery+Django项目.md) |
| 6 | `delay` 与 `apply_async` | 阶段 2 · 课 4 | 关单用 `apply_async(countdown=)`，编排用 `delay` | [lesson-04](../../stages/2-Django集成与任务基础/lessons/lesson-04-调用任务与取回结果.md) |
| 7 | `AsyncResult` 跨进程重建 | 阶段 2 · 课 4 | 订单查询接口用 `task_id` 查进度 | [lesson-04](../../stages/2-Django集成与任务基础/lessons/lesson-04-调用任务与取回结果.md) |
| 8 | 确认机制（acks_late） | 阶段 3 · 课 5 | 全局 `task_acks_late=True` 保不丢 | [lesson-05](../../stages/3-可靠性与幂等/lessons/lesson-05-确认机制与重试策略.md) |
| 9 | 至少一次投递 → 幂等 | 阶段 3 · 课 5 | ⭐ **决策 3 的核心**：CAS 状态机幂等关单 | [lesson-05](../../stages/3-可靠性与幂等/lessons/lesson-05-确认机制与重试策略.md) |
| 10 | 重试策略（autoretry_for / 退避） | 阶段 3 · 课 5 | 短信/优惠券任务的指数退避重试 | [lesson-05](../../stages/3-可靠性与幂等/lessons/lesson-05-确认机制与重试策略.md) |
| 11 | Django 事务与 `on_commit` | 阶段 3 · 课 6 | ⭐ 订单落库提交后才发任务（否则任务查不到订单） | [lesson-06](../../stages/3-可靠性与幂等/lessons/lesson-06-Django事务与ORM的坑.md) |
| 12 | 传 id 而非 ORM 对象 | 阶段 3 · 课 6 | 所有任务参数只传 `order_id` | [lesson-06](../../stages/3-可靠性与幂等/lessons/lesson-06-Django事务与ORM的坑.md) |
| 13 | 连接清理钩子 | 阶段 3 · 课 6 | `task_postrun` 关闭 DB 连接，防泄漏 | [lesson-06](../../stages/3-可靠性与幂等/lessons/lesson-06-Django事务与ORM的坑.md) |
| 14 | beat 与周期性任务 | 阶段 4 · 课 7 | ⭐ **决策 2 方案 B**：兜底轮询扫描超时订单 + 心跳监控 | [lesson-07](../../stages/4-定时编排与生产运维/lessons/lesson-07-beat与周期性任务.md) |
| 15 | canvas 编排（chain / chord / group） | 阶段 4 · 课 8 | 履约链路：`chord`（并行发券+通知 → 汇总对账） | [lesson-08](../../stages/4-定时编排与生产运维/lessons/lesson-08-canvas任务编排.md) |
| 16 | 队列隔离与路由 | 阶段 4 · 课 9 | ⭐ **决策 1**：快/慢任务拆队列 + 专属 worker | [lesson-09](../../stages/4-定时编排与生产运维/lessons/lesson-09-生产部署与并发模型.md) |
| 17 | 并发模型与资源 | 阶段 4 · 课 9 | 通知用 gevent，对账用 prefork | [lesson-09](../../stages/4-定时编排与生产运维/lessons/lesson-09-生产部署与并发模型.md) |
| 18 | 优雅停机 | 阶段 4 · 课 9 | 发版不丢任务（soft shutdown + `TimeoutStopSec`） | [lesson-09](../../stages/4-定时编排与生产运维/lessons/lesson-09-生产部署与并发模型.md) |
| 19 | 可观测性（events / task_id 日志） | 阶段 4 · 课 10 | 信号钩子打 `task_id` + Flower 排障 | [lesson-10](../../stages/4-定时编排与生产运维/lessons/lesson-10-监控、排查与上线清单.md) |
| 20 | 超时保护（僵尸任务） | 阶段 4 · 课 10 | 所有任务配 `soft_time_limit` / `time_limit` | [lesson-10](../../stages/4-定时编排与生产运维/lessons/lesson-10-监控、排查与上线清单.md) |
| 21 | 序列化安全（禁 pickle） | 阶段 4 · 课 10 | `accept_content = ['json']` | [lesson-10](../../stages/4-定时编排与生产运维/lessons/lesson-10-监控、排查与上线清单.md) |
| 22 | result backend 清理 | 阶段 4 · 课 10 | 关单任务 `ignore_result=True` | [lesson-10](../../stages/4-定时编排与生产运维/lessons/lesson-10-监控、排查与上线清单.md) |

**跨阶段校验**：覆盖 **4 个阶段**（阶段 1 / 2 / 3 / 4），门槛 ≥3 ✅

## 🚀 运行方式

```bash
# 1. 进入项目目录
cd 实现/

# 2. 安装依赖（建议用虚拟环境）
pip install django==6.1 celery==5.6.3 redis flower

# 3. 起 Redis（本机用 6380，或改成你的端口）
redis-server --port 6380 --requirepass yourpassword

# 4. 初始化数据库
python manage.py migrate

# 5. 起三个组件（三个终端）
python manage.py runserver 8000              # Django
celery -A proj worker -Q fast -c 20 -P gevent -E -n fast@%h -l INFO
celery -A proj beat -l INFO                  # 兜底轮询
# 预期：看到 celery@fast ready，Flower 里能看到任务事件
```

> ⚠️ **注意**：本项目代码在 **Django 6.1 + Celery 5.6.3** 下实测通过。
> 若你的版本不同，`settings.py` 里的 `CELERY_*` 命名空间配置请对照 [Celery 配置文档](https://docs.celeryq.dev/en/stable/userguide/configuration.html) 核对。

## 📁 目录说明

| 路径 | 内容 |
|------|------|
| [`设计决策.md`](设计决策.md) | **5** 个真权衡点的完整论证（队列隔离 / 关单方案 / 幂等实现 / chord 队列 / 外部调用） |
| [`反例对照.md`](反例对照.md) | "能跑但很糟"的版本 + 6 条逐条对比 |
| [`实现/`](实现/) | 可运行代码（中文注释，关键处标注对应知识点） |
| [`验收清单.md`](验收清单.md) | 自测项，逐项勾选 |

## 🎬 本项目为什么不是玩具

| 门槛 | 本项目如何满足 |
|------|--------------|
| ① 跨阶段整合 | 覆盖 **4 个阶段 / 22 个知识点**，且每个都在代码里真实落地（见知识点地图） |
| ② 非功能约束 | 正确性 / 错误处理 / 性能 / 可观测性 / 安全 **5 项** |
| ③ 真权衡决策 | **5 个**决策点，每个都有"换了别人可能选另一个"的真实争议（见设计决策） |
| ④ 规模 | 多文件 Django 工程：配置层 / 业务层 / 任务层 / 视图层 / 运维脚本 |

## 🔬 本项目的实测依据

> 本项目的三个决策点**不是凭经验拍脑袋**，每个都在本机实测验证过：

| 决策 | 实测结论 | 验证脚本 |
|------|---------|---------|
| 关单方案（决策 2） | ETA 任务**可撤销**（执行 0 次）；但 **`revoke` 拦不住已开跑的任务**（DONE=1） | `playground/l10-test-cancel.sh` |
| 幂等必要性（决策 3） | 无幂等：**库存被回滚 3 次**（10→13，超卖）；CAS：`[1,0,0]` 库存 11 ✅；SET NX 同样有效 | `playground/l10-test-idempotent.sh` |
| 至少一次投递（决策 3） | worker 被 **SIGKILL** 后任务**重新执行**（START 次数 = 2） | `playground/l10-test-kill.sh` |
| visibility_timeout（决策 2） | countdown=20 vs visibility_timeout=1（差 20 倍）**仍只执行 1 次** —— 未复现网传的重复执行 | `playground/l10-test-eta.sh` |
| chord 挂死根因（决策 4） | 漏配 `fulfill_order` 路由 → 编排入口进 `default` 队列；补路由后 worker **不带 default** 也跑通 ✅ | `playground/l10-test-chord.sh` |
| 关单幂等（端到端实跑） | 真实 Django ORM + worker 执行 3 次 → `[True, already_processed, already_processed]`，库存 10→11 ✅ | `playground/l10-e2e-verify.sh` |

### 一键验证

```bash
# 重建环境（若 /tmp 下的 venv 被系统清理）
bash playground/l10-rebuild-env.sh

# 跑全量验收
bash playground/l10-final-verify.sh
```

**当前状态**：`verify.sh` **6/6 通过**，chord 对账落库成功（`coupon_ok=True, notify_ok=True`），端到端关单幂等验证通过。

### 🐛 本项目实跑抓出的真 bug

> 这些是"写完就跑"抓出来的，不是事后编的检查项 —— 也说明为什么验收清单不能只靠肉眼看：

1. 日志用相对路径 `logs/celery.log` 而目录不存在 → **Django 启动直接崩溃**（改为绝对路径 + `os.makedirs`）
2. 缺 `manage.py` → 项目跑不起来
3. `CELERY_TASK_ROUTES` 漏配 `issue_coupon` → 它进 `default` 队列，**chord 永不完成**
4. chord 的**编排入口** `fulfill_order` 漏配路由 → 进 `default` 队列，整个编排根本没开始，**chord 静默挂死**
   > ❗ 这里曾给过错结论（"chord 解锁任务走 default 队列，必须让 worker 消费 default"）。
   > 后来解出积压消息的真实任务名才发现是 `fulfill_order` 自己漏配了路由。
   > **"让 worker 消费 default" 能解决症状，但会永久掩盖漏配路由这个真因** —— 已改回补路由。详见设计决策 4。
5. 外部短信服务写死真实 URL → demo 开箱即挂（改为可注入 mock）
