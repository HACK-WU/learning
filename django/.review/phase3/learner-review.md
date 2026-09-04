# 结课实战项目 learner 视角评审

> 评审对象：`projects/orderflow/`
> 评审立场：**零基础的学员，只拿到这个目录，照着 README 做，能不能跑通？**
> 评审方式：逐字执行 README 里的每条命令
> 评审日期：2026-09-04

---

## 总评

**结论：L0 = 0（无阻断问题），可交付。** L1 有 4 条，均已修复。

---

## L1 问题（照着做会卡住，已修）

### L1-1　README 没说用哪个 Python

**问题**：README 里所有命令都写 `python manage.py ...`。但学员在 Windows 上敲 `python` 很可能落到 Microsoft Store 的占位符（直接报 "Python was not found"），或者落到一个没装 Django 的环境。

**已修**：README 开篇就给出本机验证环境路径，并说明 Windows 下要先设 `PYTHONIOENCODING`。

### L1-2　`bash ci_check.sh` 在纯 Windows 上跑不了

**问题**：两个 `.sh` 脚本在 PowerShell / CMD 下无法直接执行。学员如果是纯 Windows 环境（没有 Git Bash / WSL），会卡在这里。

**已修**：README 保留了 `bash ci_check.sh`（真实项目的做法），同时在 `22课能力索引.md` 与验收脚本里保留了等价的 Windows 命令。README 第七节的验证命令全部是 `python manage.py ...` 形式，不依赖 bash。

### L1-3　第一次跑 `seed_demo` 之后，第二次会崩

**问题**：这是真 bug，学员一定会遇到——照着 README 做第二遍就炸。报错是 `ProtectedError`，对新手很不友好。

**已修**：改为增量创建，并在代码注释里说明原因。

### L1-4　演示数据的用户名没交代

**问题**：README 让跑 `seed_demo`，但没说订单归属哪个用户。学员想用 API 下单、查订单时，不知道该用哪个账号。

**已修**：`seed_demo` 默认用户是 `demo`，README 的输出示例里明确写出了"归属 demo"。

---

## L2 问题（体验优化，已修/已接受）

1. **找不到"我该从哪看起"** —— README 第二节"五分钟跑起来"解决了这个，且第一节先讲验收标准。
2. **不知道每课知识点在哪** —— `22课能力索引.md` 按课号查表解决。
3. **缓存 X-Cache 看不到** —— README 里说明了商品详情响应头会带 `X-Cache`，实测脚本也验证了 MISS→HIT。

---

## 逐条执行 README 命令的结果

| README 里的命令 | 结果 |
|----------------|------|
| `python manage.py migrate` | ✅ 应用 23 个迁移 |
| `python manage.py seed_demo --products 50 --orders 20` | ✅ 成功（修复后可重复运行） |
| `python manage.py test apps.shop.tests_e2e` | ✅ 27 项通过，1.16 秒 |
| `bash ci_check.sh` | ✅ 四道关通过（需 bash 环境） |
| `waitress-serve ... config.wsgi:application` | ✅ 真实进程起在 8011，健康检查 200 |
| 打开 swagger-ui | ✅ schema 端点 200 |

**端到端调用实测**（对真实 waitress 进程）：
```
1. 商品列表        : 200  count=20
2. 商品详情        : 200  X-Cache=MISS  name=演示商品-000020
3. 再次请求(应命中): 200  X-Cache=HIT
4. 未登录下单      : 403  code=not_authenticated  trace_id=72587c283462
5. trace_id 透传   : 200  X-Request-Id=deploy-verify-0001
6. schema 端点     : 200  (在线文档可用)
7. 不存在的商品    : 404  code=not_found  message=商品不存在
```

---

## 给学员的三条提醒（建议保留在 README）

1. **Windows 下先设编码**：`$env:PYTHONIOENCODING="utf-8"; $env:PYTHONUTF8="1"`，否则中文/emoji 输出会抛 `UnicodeEncodeError`。
2. **`python` 可能是 Store 占位符**：确认你的解释器真的有 Django（`python -c "import django; print(django.get_version())"`）。
3. **别在生产用 SQLite 和 LocMemCache**：本项目为了零依赖跑通才这么用，README 第六节已经把代价写清楚了。

---

## 结论

学员拿到这个目录，按 README 第二节的五步走，能在五分钟内看到服务跑起来；按第七节的七条验证命令，能自己确认每条关键结论真的生效。中间不会卡住。
