# OrderFlow — Django 进阶课程结课实战项目

> 把 22 课的散装知识点，焊成一个**能跑通"从提交到上线"完整链路**的项目。
> 交付日期：2026-09-04　｜　Django 6.1 / DRF 3.18 / Python 3.13.14

---

## 一、这个项目的验收标准是什么

**不是"功能齐全"，是"跑通一条完整链路"。**

课 22 的接力提示词把验收标准写死了：

> 验收标准是"能跑通一条从提交到上线的完整链路"，不是"功能齐全"。

所以本项目的主链路只有一条——**下单**：

```
POST /api/v1/orders/
```

但这一条链路向下会依次撞上六个阶段的能力。链路本身很简单，**让它安全、可查、可回滚、能上线**才是难的部分。

### 完整链路（提交 → 上线）

| 阶段 | 动作 | 命令 | 失败时会怎样 |
|------|------|------|-------------|
| 1 | 写代码 | — | — |
| 2 | CI 门禁 | `bash ci_check.sh` | **拦住**，退出码非 0 |
| 3 | 备份 | `deploy.sh` 阶段 1 | 中止部署，环境不变 |
| 4 | 迁移 | `deploy.sh` 阶段 2 | 回滚到备份文件 |
| 5 | 静态文件 | `deploy.sh` 阶段 3 | 告警，可重跑 |
| 6 | 启动 + 验证 | `deploy.sh` 阶段 4-5 | 自动回滚并停服 |

**四道 CI 门禁**（`ci_check.sh`），每一道对应一课的结论：

1. 配置检查 —— 课 22 的生产配置与密钥
2. 团队约定检查 —— 课 21 的自定义 System checks
3. 测试 —— 课 20 的"先量后改"
4. 文档同步 —— 课 20 的文档与代码一致

---

## 二、五分钟跑起来

> ⚠️ 环境：本机验证用的是
> `C:\Users\<你>\.workbuddy\binaries\python\envs\dj-course\Scripts\python.exe`
> （Python 3.13.14 + Django 6.1 + waitress 3.0.2）。
> Windows 下跑任何含中文/emoji 输出的脚本前，先设：
> `$env:PYTHONIOENCODING="utf-8"; $env:PYTHONUTF8="1"`

```bash
cd projects/orderflow

# 1. 建库
python manage.py migrate

# 2. 灌演示数据
python manage.py seed_demo --products 50 --orders 20

# 3. 跑验收测试（27 项，约 1.2 秒）
python manage.py test apps.shop.tests_e2e

# 4. 过一遍 CI 门禁
bash ci_check.sh

# 5. 起服务
waitress-serve --host=127.0.0.1 --port=8000 config.wsgi:application
```

打开 `http://127.0.0.1:8000/api/v1/schema/swagger-ui/` 看在线文档。

---

## 三、目录结构

```
projects/orderflow/
├── manage.py
├── requirements.txt          # 版本基线：Django 6.1 / DRF 3.18
├── schema.yaml               # 已提交的 OpenAPI 文档（CI 校验它是否过期）
├── ci_check.sh               # CI 门禁：四道关
├── deploy.sh                 # 部署：备份 → 迁移 → 静态 → 启动 → 验证 → 回滚
├── README.md                 # 本文件
├── 22课能力索引.md            # 每课的知识点落在哪个文件哪一行
├── config/
│   ├── settings.py           # 开发/测试配置
│   ├── settings_prod.py      # 生产配置（缺密钥直接 raise）
│   ├── logfmt.py             # 结构化日志（JSON）
│   ├── urls.py               # 路由（手写路径排在 router 之前）
│   └── wsgi.py               # WSGI 入口
└── apps/
    ├── common/
    │   ├── middleware.py     # 课 18：trace_id
    │   ├── logging_filters.py# 课 18：trace_id 注入日志
    │   └── exceptions.py     # 课 5：统一错误结构
    └── shop/
        ├── models.py         # 课 4/12：约束下沉、索引、状态机
        ├── services.py       # 课 7/11/14/16/17：业务逻辑核心
        ├── serializers.py    # 课 3/4/19/20：API 边界
        ├── views.py          # 课 5/9/15：view 只做三件事
        ├── permissions.py    # 课 9：权限的两个方向
        ├── checks.py         # 课 21：6 条 System checks
        ├── factories.py      # 课 20：测试数据工厂
        ├── tests_e2e.py      # 验收标准本身（27 项）
        └── management/commands/
            ├── testhealth.py # 课 21：体检命令（原实验 41 脚本）
            ├── exportdocs.py # 课 21：文档导出（原实验 30 脚本）
            └── seed_demo.py  # 课 14：批量造数（规模意识）
```

---

## 四、主链路：一次下单经过了什么

```
POST /api/v1/orders/  + Header: Idempotency-Key
        │
        ├─[课 8/9]  认证：你是谁          → Token / Session
        ├─[课 9]    限流：下单 20/min      → 超过返回 429
        ├─[课 3/4]  入参校验               → items/remark，合并同一商品
        │
        ▼  services.create_order_and_notify()   ← 业务逻辑全在这里，不在 view
        │
        ├─[课 11]   幂等：Idempotency-Key   → 重复提交返回原订单，不新建
        ├─[课 11]   F() 原子扣库存           → UPDATE ... WHERE stock >= qty
        │           └─ 检查与扣减在同一条 SQL，并发不超卖
        ├─[课 14]   事务边界                → 数据库操作原子
        ├─[课 14]   bulk_create 明细         → 明细再多也只有一条 SQL
        ├─[课 17]   审计日志                → **显式调用**，不是 signal
        ├─[课 16]   缓存失效                → 库存变了，详情缓存 delete
        │
        ▼  事务提交之后
        └─[课 17]   外部通知                → 发短信/MQ，失败不影响已创建的订单
```

**为什么要分 `create_order` 和 `create_order_and_notify` 两个函数？**

这是课 17 最重要的一条结论：**外部副作用不能放在事务里**。

放在事务里的后果是——事务最终回滚了，但短信已经发出去，收不回来。用户收到"下单成功"短信，订单却不存在。

---

## 五、贯穿全课程的那条暗线：不报错的错误

课 22 结课时点出了这条暗线：从课 1 的模板变量静默渲染空字符串，到课 21 的 check 不注册报 0 条——**它们的共同形状是"你少了一层保护，但没有任何东西告诉你"**。

本项目把这些"不报错的错误"逐个改成了显式失败：

| 静默失败 | 怎么变成显式失败 | 落点 |
|---------|----------------|------|
| 手写路径被 router 遮蔽，静默 405 | `check_route_order`，问 URL 解析器 | `checks.py` E001 |
| check 模块没被 import，检查全不执行 | 元检查 `check_checks_registered` | `checks.py` E002 |
| 生产配置缺安全开关 | 生产配置下缺密钥直接 `raise` | `settings_prod.py` |
| 文档过期但没人知道 | `exportdocs --check`，CI 拦 | `exportdocs.py` |
| 限流 scope 没配，静默失效 | 显式 `scope` + settings 配置 | `views.py` |
| signal 不注册，全程静默 | 改用 service 显式调用 | `services.py` |
| 缓存挂了但健康检查全绿 | 健康检查真的查一次库 | `views.py` HealthView |

---

## 六、几个刻意的设计取舍

**1. 用 SQLite，不用 PostgreSQL**

让学员零依赖跑通全链路。代价是：课 12/13 的连接池、多库路由结论在此环境无法演示，已显式标注单机边界。

**2. 商品 API 是只读的**

增删改走 Admin / 管理命令。真实项目里"谁能改商品"涉及运营权限体系，与本项目要演示的链路无关。

**3. 缓存用 LocMemCache**

环境限制。**但这是有代价的**：`LocMemCache` 每个进程各有一份，多进程部署时"改了 A 进程的缓存，B 进程看不到"。生产必须换 Redis，已在 `settings_prod.py` 标注。

**4. 只用一条主链路，不铺开多条**

用户明确选择"只做下单这一条主链路把它做透"。功能少，但每一层都经得起追问。

---

## 七、怎么确认它真的生效了

每条关键结论都有可验证的自检手段（评审必查项 #11）：

```bash
# 并发不超卖
python manage.py test apps.shop.tests_e2e.OrderFlowEndToEndTest.test_no_oversell_under_concurrency

# N+1 治好了
python manage.py test apps.shop.tests_e2e.OrderFlowEndToEndTest.test_order_list_query_count_is_bounded

# 权限的两个方向都生效
python manage.py test apps.shop.tests_e2e.OrderFlowEndToEndTest.test_queryset_filters_other_users_orders
python manage.py test apps.shop.tests_e2e.OrderFlowEndToEndTest.test_object_permission_rejects_status_change_by_stranger

# 自定义 check 真的注册了（而不是静默失效）
python manage.py check --list | findstr orderflow

# 文档没过期
python manage.py exportdocs --file schema.yaml --check

# 生产配置会不会起不来（缺密钥应当直接失败）
set SECRET_KEY=
python manage.py check --settings=config.settings_prod
```

---

## 八、本次交付的实测记录

| 项目 | 结果 |
|------|------|
| 验收测试 | **27 项全通过**，耗时 1.16 秒（从零状态可重复） |
| CI 门禁 | 四道关全过，退出码 0 |
| 自定义 checks | 6 条全部注册；E/W 清零，仅剩 I001 提示 |
| OpenAPI 文档 | 18,340 字节，`--validate --fail-on-warn` 零警告 |
| 真实部署 | waitress 进程起在 127.0.0.1:8011，健康检查 200 |
| 端到端调用 | 列表 200 / 缓存 MISS→HIT / 未登录 403 / trace_id 透传 / 404 统一结构 |
| 回滚演练 | 备份-恢复字节一致（233,472 字节） |
| 环境 | Python 3.13.14 / Django 6.1 / DRF 3.18.0 / waitress 3.0.2 |

---

## 九、下一步

课 22 的接力提示词还列了三项 Phase 5 收尾产物：

1. `08-实战经验.md` —— 学习态：适用边界 / 高频故障模式 / 落地 Checklist
2. `09-排障速查手册.md` —— 使用态：按症状倒查的条件-动作表
3. `10-场景解法库.md` —— 设计态：新要求来了怎么设计

本项目是它们的素材来源：`22课能力索引.md` 已经把每课的知识点映射到了具体文件与行号，写这三份时可以直接回链。
