# 课 9 评审 · 视角 A：pedagogy（教学设计与事实准确性）

评审对象：`stages/3-认证权限与鉴权/lessons/lesson-09-权限你能干什么.md`
评审时间：2026-09-02
评审方式：独立通读全文 + 源码/文档交叉核实

---

## 一、事实准确性核查（逐条对照源码与文档）

| # | 讲义断言 | 核实结果 | 依据 |
|---|---------|---------|------|
| 1 | 执行顺序 认证→权限→限流 | ✅ 正确 | `views.py:404` `initial()`，419–421 行 |
| 2 | `has_object_permission` 只在 `get_object()` 调用 | ✅ 正确 | `generics.py:79` / `:103` |
| 3 | DRF 内置 `AND`/`OR`/`NOT` 组合类 | ✅ 正确 | `permissions.py:61/79/100` |
| 4 | `ScopedRateThrottle` 读 `throttle_scope`，`UserRateThrottle` 不读 | ✅ 正确 | `throttling.py:212/221`（`scope_attr`、`getattr`）；`UserRateThrottle.scope='user'` 在 191 行 |
| 5 | 权限拒绝时限流不执行 | ✅ 正确（实测） | 实验 5 对照 B：CALL_LOG 只有 ⓪② |
| 6 | 列表路由不调对象级权限 | ✅ 正确（实测） | 实验 2b：mock 记录为空 |
| 7 | 多进程配额 = 配置值 × worker 数 | ✅ 正确（实测） | 实验 8b：两个 LocMemCache 各放行 5 次 |
| 8 | `UserRateThrottle` 未认证回退 IP 计数 | ✅ 正确 | 官方文档明示 |
| 9 | 内置限流有并发竞态 | ✅ 正确 | 官方文档 "open to race conditions" |
| 10 | 配 `5/minute` 第 6 次被拒 | ✅ 正确（实测） | 实验 6 |
| 11 | 429 带 `Retry-After` | ✅ 正确（实测） | 实验 6 输出 `Retry-After: 60 秒` |
| 12 | `override_settings` 改不了 `THROTTLE_RATES` | ✅ 正确（实测） | 实验 9：类属性未同步 |
| 13 | 未配 scope：UserRate 静默 / ScopedRate 抛异常 | ✅ 正确（实测） | 实验 9 实验 A |

**结论：13 条断言全部经源码或实测核实，无事实性错误。**

---

## 二、发现的问题

### P0 级（必修）

**无。**

### P1 级（建议修）

#### P1-1：`DenyOrderView` 的 `authentication_classes = []` 削弱了实验 5 的说服力

- **问题**：对照 B 的 CALL_LOG 是 `⓪ initial 开始 → ② 权限（拒绝）`，**缺少"① 认证"**。讲义虽然用引用块说明了原因，但读者第一眼看到的是"权限在认证之前"，与知识点 1 的核心结论**视觉上冲突**。
- **影响**：教学上这是一个"结论与证据表面矛盾"的点，容易被读者误读。
- **建议**：在对照 B 的输出里直接补一行注释说明，而不是放在后面的引用块。例如把输出写成：
  ```
  ⓪ initial 开始
  （认证层：本视图 authentication_classes = []，故无 ①）
  ② 权限（拒绝）
  ```
- **当前状态**：已有引用块说明，属可接受，但建议内联。

#### P1-2：`has_object_permission` 示例类名与正文不一致

- **问题**：知识点 2 的"标准写法"用的是 `IsAuthorOrReadOnly`，但 OR 组合示例里写的是 `IsAuthor`，后者在全文未定义。
- **影响**：学员照抄会 `NameError`。
- **建议**：要么定义 `IsAuthor`，要么把 OR 示例改回 `IsAuthorOrReadOnly`。

#### P1-3：实验 2b 的 mock 副作用函数可读性差

- **问题**：`side_effect=lambda self, request, view, obj: (CALL_LOG.append(...) or True)` 这个"利用 `or` 短路返回 True"的技巧，对初学者不友好。
- **影响**：学员想自己复现实验时会卡住。
- **建议**：在附录的实验工程说明里补一句"这里用 `or True` 是因为 `list.append()` 返回 `None`，需要让 side_effect 返回一个真值"。

### P2 级（可选优化）

#### P2-1：知识点 3 缺少"限流类与缓存后端的绑定关系"的官方写法

- 讲义提到了"`SimpleRateThrottle.cache` 是类属性"，也提到了多进程问题，但没给**官方推荐的修法**（`cache = caches['alternate']`）。
- 建议补一个三行示例，让"知道问题"落到"知道怎么改"。

#### P2-2：课 8 的衔接可以更紧

- 第一幕提到"课 8 结束时你挂上了 JWT"，但课 8 实际交付的是 `SessionAuthentication` + JWT 的对比选型。
- 建议：把"你给文章接口挂上了 JWT"改成"你按课 8 的方案配好了认证"，避免与课 8 具体内容冲突。

---

## 三、认可点

1. **实验设计有真实的纠错过程**：原骨架的实验 6/7/9 存在配额污染、权限拦截、scope 失效三类设计缺陷，本轮全部修正并保留了"对照"输出。这种"把错误设计也展示出来"的做法比直接给正确结论更有教学价值。

2. **区分「文档明示」与「实测确认」**：这是本门课的核心规范，本课执行到位，15 条结论逐条标注来源，且实测项占 10 条——说明本课的价值主要在官方文档未覆盖的边界。

3. **三个高危发现都有实测支撑**：
   - `throttle_scope` 静默失效（文档未警告）
   - 列表路由不调对象级权限（文档未强调）
   - `override_settings` 对限流无效（文档未提及）

4. **源码行号精确**：`views.py:404`、`generics.py:79/103`、`permissions.py:61/79/100`、`throttling.py:191/212/221` 均已逐一核实。

---

## 四、补充场景（建议纳入但非必须）

1. **`DjangoModelPermissions`**：基于 Django 权限系统的权限类，本课完全没提。它是"Admin 权限复用到 API"的常见做法，课 19 讲 Admin 时会用到。
2. **限流的 `get_cache_key` 自定义**：讲义提了 ScopedRateThrottle 的坑，但没提"想按用户名限流必须重写 `get_cache_key`"这个高频需求（登录防爆破）。
3. **`throttle_scope` 在 ViewSet 的 `@action` 上的用法**：`@action(detail=True, throttle_classes=[...])`。

---

## 五、评审结论

**通过（P0 = 0）。**

P1 共 3 条，其中 P1-2（`IsAuthor` 未定义，会导致照抄报错）建议务必修复；P1-1、P1-3 为可读性优化。
