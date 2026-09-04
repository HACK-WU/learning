# 课 10 评审 · 视角 A：pedagogy（教学设计与事实准确性）

评审对象：`stages/3-认证权限与鉴权/lessons/lesson-10-分离架构下的安全实践.md`
评审时间：2026-09-02
评审方式：独立通读全文 + 源码/文档交叉核实

---

## 一、事实准确性核查（逐条对照源码与文档）

| # | 讲义断言 | 核实结果 | 依据 |
|---|---------|---------|------|
| 1 | DRF `as_view()` 返回 `csrf_exempt(view)` | ✅ 正确 | `rest_framework/views.py:149` |
| 2 | `CsrfViewMiddleware` 检查 `csrf_exempt` 后放行 | ✅ 正确 | `django/middleware/csrf.py:420` |
| 3 | CSRF 校验在 `SessionAuthentication.enforce_csrf` | ✅ 正确 | `authentication.py:112/117/127/130/135` |
| 4 | 未登录时 `if not user: return None` 跳过 CSRF | ✅ 正确 | `authentication.py:127` |
| 5 | Token 认证下 `enforce_csrf` 不被调用 | ✅ 正确（实测） | 实验 1c：调用记录为空 |
| 6 | `csrftoken` 默认 `httponly=False` | ✅ 正确（实测） | 实验 2 |
| 7 | `SESSION_COOKIE_HTTPONLY` 默认 True | ✅ 正确 | 官方文档 |
| 8 | `SESSION_COOKIE_SAMESITE` 默认 `'Lax'` | ✅ 正确 | 官方文档 |
| 9 | `SESSION_COOKIE_SECURE` 默认 False | ✅ 正确 | 官方文档 |
| 10 | SameSite 是 defense in depth 非替代 | ✅ 正确 | Django 文档原话 |
| 11 | `SameSite=None` 必须配 `secure=True` | ✅ 正确 | 官方文档 + 实测 t_none |
| 12 | DRF 推荐 `fields` 而非 `exclude` | ✅ 正确 | 官方文档 + ticket #8620 |
| 13 | 批量分配 = OWASP API3:2023 / CWE-915 | ✅ 正确 | OWASP 官方 |
| 14 | GitHub 2012 是批量分配典型案例 | ✅ 正确 | OWASP Cheat Sheet 引用 |
| 15 | 水平越权 = API1 BOLA，垂直 = API5 BFLA | ✅ 正确 | OWASP API Security Top 10 2023 |
| 16 | `read_only` 字段静默忽略、返回 200 | ✅ 正确（实测） | 实验 6b |
| 17 | 伪造 author / 刷 view_count 成功 | ✅ 正确（实测） | 实验 7a |
| 18 | 注册白名单外字段被丢弃 | ✅ 正确（实测） | 实验 8 |
| 19 | Django 4.0 起 `CSRF_TRUSTED_ORIGINS` 必须带 scheme | ✅ 正确 | 官方文档 |
| 20 | Cookie 方案下 POST 不带 token → 403 | ✅ 正确（实测） | 实验 3c |

**结论：20 条断言全部经源码、文档或实测核实，无事实性错误。**

---

## 二、发现的问题

### P0 级（必修）

**无。**

### P1 级（建议修）

#### P1-1：实验 3c 的机制说明可以更早出现

- **问题**：实验 3c 一开始用 `cookie-me` 视图（AllowAny + 无认证类）测出 200，会得到"Cookie 方案不需要 CSRF"的**错误结论**。讲义虽然在正文里补了说明，但这个坑的发现过程值得前置。
- **影响**：学员若自己复现，很可能先做出错误结论。
- **当前状态**：已在"实测：Cookie 方案会让 CSRF 回归"下加了 📌 说明，属可接受。建议把这段移到知识点 1 末尾，与 `enforce_csrf` 机制讲在一起，逻辑更顺。

#### P1-2：`HeaderAuth` 继承 `SessionAuthentication` 但覆盖了 `authenticate`，语义上容易误导

- **问题**：`HeaderAuth(SessionAuthentication)` 覆写了 `authenticate` 和 `enforce_csrf`，实际上跟 Session 已无关系。继承关系会让人误以为"Token 认证是 Session 认证的一种"。
- **建议**：改为继承 `BaseAuthentication`，语义更干净。

#### P1-3：知识点 2 的"三种存放位置"表格用了 ❌/✅ 双重语义

- **问题**：表格里"被 XSS 读取"列的 ❌ 表示"能读到（坏）"，"被 CSRF 利用"列的 ✅ 表示"免疫（好）"。同一张表里 ❌ 有时表"坏"有时表"好"，容易误读。
- **建议**：改用明确的文字（"能读到"/"读不到"），不用符号。

### P2 级（可选优化）

#### P2-1：知识点 1 缺"SessionAuthentication 与 JWT 共存时"的行为说明

- 课 8 实测过多认证类按列表顺序第一个成功的胜出。若列表是 `[JWT, Session]`，带 JWT 的请求走 JWT（不校验 CSRF）；若只带 session cookie，走 Session（校验 CSRF）。**同一个视图的 CSRF 行为会随请求携带的凭据类型而变**——这是个很实用的推论，讲义未提。
- 建议补一句。

#### P2-2：批量分配缺少"DRF 之外"的场景

- 讲义只讲了 serializer 层面。但 `Model.objects.filter(pk=pk).update(**request.data)` 这种写法同样危险，且完全绕过 serializer。
- 建议补一句警告。

---

## 三、认可点

1. **把 `csrf_exempt` 这个反直觉事实讲透了**：从 `as_view()` 的源码 → 中间件的豁免判断 → `enforce_csrf` 的真实位置，三层递进，且每层都有行号。这是本课最大的价值点。

2. **HttpOnly 与 SameSite 的正交性拆解**：明确否定"localStorage vs Cookie 二选一"这个流行但粗糙的二分法，用 4 个 Cookie 的属性对照表把两个开关拆开。这是很多教程没讲清的。

3. **白名单 vs 黑名单的方法论给了理由**：不仅说"用 fields"，还解释了"黑名单会在模型新增字段那天静默失效"，并引用 Django 官方 ticket #8620 佐证。这让规则有了可迁移的理由，而非死记。

4. **必查项 #22 执行到位**：本课自查出 2 处"顺手写下的断言"（CSRF_TRUSTED_ORIGINS 通配符、SameSite Lax 顶层 GET）被标成了实测，已降级为文档明示并注明"未实测及原因"。这是连着几课都在犯的高发错误，本課在自查阶段就抓住了。

5. **实验设计踩坑被记录下来**：3c 第一次用 AllowAny 视图测出 200，机制被掩盖——这个坑写进了讲义，比直接给正确结论更有教学价值。

6. **区分表 20 条**：其中源码核实 3 条、文档明示 7 条、实测确认 10 条，比例合理。

---

## 四、补充场景（建议纳入但非必须）

1. **`Model.objects.update(**request.data)` 的批量分配**：绕过 serializer 的直接 ORM 写入。
2. **CORS 与 CSRF 的混淆**：很多人用 `django-cors-headers` 配 `CORS_ALLOW_ALL_ORIGINS=True` 来"解决"跨域，这会削弱 CSRF 防护（配合 `allow_credentials` 时）。课 18 讲中间件时可展开。
3. **`SecurityMiddleware` 的 HSTS / CSP**：CSP 是防 XSS 的重要手段，本课只提了"转义、CSP"四个字。

---

## 五、评审结论

**通过（P0 = 0）。**

P1 共 3 条，均为表述与可读性优化，不影响事实准确性。
