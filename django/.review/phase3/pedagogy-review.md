# 结课实战项目 pedagogy 视角评审

> 评审对象：`projects/orderflow/`（Phase 3 结课实战项目）
> 评审方式：逐字执行代码与命令，不是通读
> 评审日期：2026-09-04

---

## 总评

**结论：P0 = 0，可交付。** P1 有 6 条，均已修复。

本项目最值得肯定的一点是：**验收标准被严格执行了**。课 22 接力提示词要求"跑通一条从提交到上线的完整链路"，本项目四条 CI 门禁 + 五阶段部署脚本 + 回滚演练，把这条链路真的跑了一遍，而不是画在文档里。

---

## P1 问题（应修，已修）

### P1-1　seed_demo 第二次运行直接崩溃

**问题严重度：高。这是真 bug，不是措辞问题。**

原实现：
```python
Product.objects.filter(name__startswith="演示商品-").delete()
```

`OrderItem.product` 是 `on_delete=PROTECT`，第一轮灌的数据已经产生订单明细，第二轮运行时 `delete()` 抛 `ProtectedError`，命令直接崩。

**这是评审必查项 #28 该抓的典型**：示例第一次跑没事，第二次就炸。

**已修**：改为增量创建（已有 N 个就补到目标数），不删除已有数据。并把这个坑写进了代码注释——它本身就是一个好教材。

### P1-2　`select_for_update()` 在 SQLite 上导致并发测试全灭

**问题**：第一版 `create_order` 用了行锁。实测在 SQLite 上两条线程双双抛 `database table is locked`，结果是 **0 单成功**（期望 1 单）。

**更关键的是这个锁是多余的**：`filter(stock__gte=qty).update(stock=F("stock")-qty)` 本身已经是原子的——检查与扣减在同一条 SQL 的 WHERE 与 SET 里完成。

**已修**：移除行锁，并在注释里说明为什么它是多余的。

### P1-3　E003 安全检查会把测试全拦下来

**问题**：`check_security_settings` 最初写成 `if settings.DEBUG: return []`。但 **Django 测试运行器会强制把 DEBUG 设为 False**，于是"不是 DEBUG"被误判成"是生产"，一跑测试就报 3 条 E003。

这是"检查写对了但触发条件写错了"的典型——检查本身没错，错在判据。

**已修**：改为检查显式哨兵 `IS_PRODUCTION_DEPLOY = True`（只在 `settings_prod.py` 里设）。

### P1-4　drf-spectacular 有 4 条 schema 警告

**问题**：`MeView` 没有 `serializer_class`，导致 `/api/v1/me/` **根本不出现在文档里**（"Ignoring view for now"）——又是一次静默降级。`OrderViewSet.get_queryset()` 在 schema 生成期因 `AnonymousUser` 抛错。两个 `SerializerMethodField` 类型推断为 string。

**已修**：补 `MeSerializer`、`swagger_fake_view` 判断、`@extend_schema_field` 类型声明。现在 `--fail-on-warn` 零警告。

### P1-5　E002 元检查读错了 registry 容器

**问题**：`getattr(registry, "registered_checks")` 拿到的是 `None`，因为 `registered_checks` 挂在 **CheckRegistry 实例**上（`django.core.checks.registry.registry.registered_checks`），而 `registry` 是模块。结果 check 明明全部注册了，却误报"一条都没注册"。

**讽刺但真实**：这个"检查检查机制是否生效"的检查，自己就没生效。

**已修**：改为读 `checks_registry.registry.registered_checks`，并补了"部分缺失"的 W004 分支。

### P1-6　`OrderViewSet.get_queryset()` 对匿名用户抛错

见 P1-4，已合并修复。

---

## P2 问题（建议，已修）

1. **deploy.sh 的 `backups/` 目录依赖脚本内 mkdir** —— 手工演练时因目录不存在而失败。已确认脚本内有 `mkdir -p`，并在本机验证时补建。
2. **测试断言写死了明细数量** —— `seed_demo` 每单随机 1-3 个明细，断言 `== 5` 会偶发失败。已改为区间断言。

---

## 做得好的地方（值得保留）

1. **每一处"改对了"都留下了为什么**。六个 P1 问题全部写进了代码注释，说明"第一版为什么错"。这让代码本身成了教材，而不是让人只能看到正确答案。
2. **诚实标注了没覆盖的知识点**。`22课能力索引.md` 末尾列了连接池、多库路由、异步视图等 5 项未覆盖内容，并说明是环境限制而非遗漏。
3. **外部副作用在事务提交之后**这一点，用 `create_order` 与 `create_order_and_notify` 两个函数的拆分把课 17 的结论固化成了代码结构，而不只是注释。
4. **E002 元检查的存在本身**就是课 17/21 那条暗线的体现——"不报错的错误最危险"。哪怕它自己先出了一次 bug，这个设计方向是对的。

---

## 与验收标准的对照

| 验收项 | 状态 |
|--------|------|
| 跑通从提交到上线的完整链路 | ✅ 四条门禁 + 五阶段部署 + 回滚演练 |
| 不是功能齐全 | ✅ 只有一条下单链路 |
| 每条命令真跑过 | ✅ 18/18 验收项含实测 |
| 结论有可验证的自检手段 | ✅ README 第七节给了 7 条验证命令 |

**最终状态**：验收 18/18 通过，测试 27 项零失败，schema 零警告，真实部署端到端验证通过。
