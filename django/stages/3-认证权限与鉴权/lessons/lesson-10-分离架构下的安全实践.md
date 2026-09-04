# 课 10　分离架构下的安全实践

> 📖 情节定位：**守门（三）** —— 分家之后，新的攻击面
> 🎯 本课目标：说清 CSRF 的真实边界，堵住越权与批量分配，为 Cookie 方案留好退路
> 🔗 承接：课 8 认证（你是谁）、课 9 权限（你能干什么）
> 🔗 收尾：本課是阶段 3 的最后一课

---

## 第一幕 · 场景引入

课 8 和课 9 做完，你的 API 看起来已经很安全了：

```python
REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": ["rest_framework_simplejwt.authentication.JWTAuthentication"],
    "DEFAULT_PERMISSION_CLASSES": ["rest_framework.permissions.IsAuthenticated"],
}
```

登录要 token，改别人文章返回 403，限流也配好了。你把这份配置发到技术群里征求意见。

**第一条回复就让你愣住了**：

> "CSRF 防护呢？你 `MIDDLEWARE` 里有 `CsrfViewMiddleware`，但 DRF 的视图是不是被 exempt 掉了？"

你翻了翻配置，中间件确实在。可你隐约记得——**DRF 的视图好像全部 `csrf_exempt`**。那 CSRF 到底还防不防？如果 exempt 了，是漏洞还是设计？

**第二条回复更扎心**：

> "你们用户资料更新的接口，我用 `PATCH` 传了个 `is_staff: true`，返回 200。"

你赶紧去查数据库——**那个测试账号真的变成 superuser 了**。

你还什么都没做，他就是改了一下请求体里的一个字段名。

这一课要处理的，就是这三件**都不在认证和权限范围内**的事：

```text
课 8  认证     你是谁
课 9  权限     你能干什么
课 10 本课     你的凭据会被怎么偷用、你的字段会被怎么写  ← 新攻击面
```

分家之后，前后端之间的信任边界变了，攻击面也跟着变了。

---

## 第二幕 · 认知困惑

### 困惑一：DRF 视图全部 csrf_exempt，那 CSRF 还防不防？

这是本课最反直觉的一点。你查源码会发现 `APIView.as_view()` 最后一行是：

```python
return csrf_exempt(view)
```

**所有 DRF 视图都绕过了 Django 的 CSRF 中间件。** 那 CSRF 防护是不是形同虚设？

答案是：**没失效，只是换了执行位置**——从中间件挪到了认证类里。但这一挪带来一个关键后果：**只有 Session 认证会做 CSRF 校验**。

### 困惑二："用 JWT 就不用管 CSRF" —— 这句话对吗？

对，但**只对一半**。真实的条件不是"用了 JWT"，而是"**凭据不放在 Cookie 里**"。

如果你把 token 存进 Cookie（很多人为了防 XSS 会这么做），浏览器照样自动带上它，**CSRF 风险原样回归**。

### 困惑三：XSS 和 CSRF 是不是攻防相反、必须二选一？

常见的说法是"localStorage 防 CSRF 但有 XSS 风险，Cookie 防 XSS 但有 CSRF 风险"。这个二分法**过于粗糙**——它把两个正交的 Cookie 属性混成了一件事。

本课会把 `HttpOnly` 和 `SameSite` 拆开看：**它们各防各的，谁也替代不了谁**。

### 困惑四：权限都配好了，怎么还能提权？

因为权限管的是"**你能不能访问这个接口**"，而批量分配攻击钻的是"**你能往这个接口传哪些字段**"。

课 9 的对象级权限再完美，也拦不住一个合法用户给自己的请求体多加一个 `is_staff: true`。

---

## 第三幕 · 层层揭示

### 知识点 1：CSRF 在前后端分离下的重新理解

#### CSRF 的本质

CSRF（Cross-Site Request Forgery，跨站请求伪造）的攻击链条只有三步：

```text
① 用户登录了 bank.com，浏览器存着 bank.com 的 cookie
② 用户访问了恶意站点 evil.com
③ evil.com 的页面自动发起 POST bank.com/transfer
   → 浏览器"热心地"带上 bank.com 的 cookie
   → bank.com 认为这是用户的真实操作
```

**核心前提只有一个：浏览器会自动携带目标站点的 Cookie。**

所以判断 CSRF 风险的标准非常朴素——**看你的凭据是不是由浏览器自动附带**：

| 凭据携带方式 | 浏览器自动带吗 | CSRF 风险 |
|-------------|---------------|----------|
| Cookie（sessionid / token 存 Cookie） | ✅ 自动带 | ⚠️ 有 |
| `Authorization` 请求头（JWT / Token） | ❌ 必须 JS 显式设置 | ✅ 无 |

这就是"Token 方案免疫 CSRF"的**全部原因**——不是因为加密，不是因为签名，仅仅是因为**攻击者没法让受害者的浏览器自动带上一个请求头**。

#### 🔴 关键机制：DRF 把 CSRF 从中间件挪进了认证类

这是本课最需要记住的一条。

Django 原生 CSRF 靠 `CsrfViewMiddleware` 中间件。但 DRF 的 `APIView.as_view()` 最后一行是：

```python
# rest_framework/views.py:123
@classmethod
def as_view(cls, **initkwargs):
    ...
    view = super().as_view(**initkwargs)
    ...
    # Note: session based authentication is explicitly CSRF validated,
    # all other authentication is CSRF exempt.
    return csrf_exempt(view)          # ← line 149，所有 DRF 视图都被 exempt
```

而 `CsrfViewMiddleware.process_view()` 开头就检查这个标记：

```python
# django/middleware/csrf.py:420
if getattr(callback, "csrf_exempt", False):
    return None                        # ← 直接放行
```

**那么真正的 CSRF 校验在哪？** 在 `SessionAuthentication` 里：

```python
# rest_framework/authentication.py:112  class SessionAuthentication
#                             :117  def authenticate
def authenticate(self, request):
    user = getattr(request._request, 'user', None)

    # Unauthenticated, CSRF validation not required
    if not user or not user.is_active:
        return None                    # ← line 127，未登录：直接跳过 CSRF

    self.enforce_csrf(request)         # ← line 130，已登录：才校验
    return (user, None)

#                             :135  def enforce_csrf
def enforce_csrf(self, request):
    check = CSRFCheck(dummy_get_response)
    check.process_request(request)
    reason = check.process_view(request, None, (), {})
    if reason:
        raise exceptions.PermissionDenied('CSRF Failed: %s' % reason)
```

**三个推论**：

1. **CSRF 是绑在认证方式上的，不是绑在中间件上的。** 只有 `SessionAuthentication` 会调 `enforce_csrf`。
2. **未登录请求不做 CSRF 校验**（`if not user: return None`）——合理，因为没登录就没有可被伪造的身份。
3. **JWT/Token 认证下 `enforce_csrf` 根本不会被调用**，所以"免疫 CSRF"是真的，但机制是"没人调用"而不是"校验通过"。

#### 实测证据：三种情况的对照

```text
【1a】Session 认证 + 不带 CSRF token 的 POST
  -> 403  CSRF Failed: CSRF cookie not set.

【1b】Session 认证 + 带上 X-CSRFToken
  -> 200  {'ok': True, 'data': {'title': 'x'}}

【1c】Authorization 头携带凭据 + 不带任何 CSRF token
  -> 200  {'ok': True, 'data': {'title': 'x'}}
     enforce_csrf 调用记录 = （空）

【1d】同一个视图，但不带 Authorization 头
  -> 403  {'detail': '身份认证信息未提供。'}
```

**1c 是核心**：带了 `Authorization` 头就一路绿灯，`enforce_csrf` 一次都没被调用。这正是"Token 方案免疫 CSRF"的机制证据。

**1d 说明**：不带凭据时是**认证层**在拦，跟 CSRF 无关。别把这两种 403 混为一谈——它们的 `detail` 完全不同。

#### CSRF Cookie 的属性

```text
csrftoken:
   httponly = False      ← 注意！不是 HttpOnly
   samesite = Lax
   secure   = False
   path     = /

settings.CSRF_COOKIE_HTTPONLY  = False
settings.SESSION_COOKIE_HTTPONLY = True
```

> 📌 **为什么 `csrftoken` 默认不是 HttpOnly？**
>
> 因为前后端分离场景下，前端 JS 必须能**读出**这个 token，才能把它放进 `X-CSRFToken` 请求头。设成 HttpOnly 反而没法用。
>
> 这与 `sessionid` 恰好相反——`sessionid` 默认 `HttpOnly=True`，因为 JS 永远不需要读它。
>
> ⚠️ 但这也意味着：**如果你站点有 XSS，攻击者能读到 csrftoken，从而绕过 CSRF 防护。** 所以 CSRF 防护的前提是"没有 XSS"。

#### 一句话结论

```text
用 JWT（Authorization 头）        → 不用管 CSRF，DRF 根本不校验
用 cookie + session（Session 认证）→ 必须配 CSRF，DRF 会在认证时强制校验
把 token 存进 Cookie              → CSRF 风险原样回归，见知识点 2
```

> ⚠️ **注意这个结论的适用范围**：它成立的前提是"前后端分离 + 纯 API"。
> 如果你的 Django 站点同时提供服务端渲染页面（`django.contrib.admin` 就是），那些页面**不走 DRF**，仍由 `CsrfViewMiddleware` 保护，一切照旧。

#### 🔴 多认证类共存时，CSRF 行为会随请求而变

课 8 实测过：**多个认证类按列表顺序，第一个成功的胜出**。把它和本课的 `enforce_csrf` 结合起来，会得到一个很实用、也很容易踩的推论：

```python
REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": [
        "rest_framework_simplejwt.authentication.JWTAuthentication",   # ← 先
        "rest_framework.authentication.SessionAuthentication",         # ← 后
    ],
}
```

| 请求携带 | 命中的认证类 | CSRF 校验 |
|---------|------------|----------|
| `Authorization: Bearer ...` | JWT | ❌ 不校验 |
| 只有 session cookie | `SessionAuthentication` | ✅ 强制校验 |
| 两者都带 | JWT（列表靠前先成功） | ❌ 不校验 |

**同一个视图的 CSRF 行为，会随着这次请求携带的凭据类型而改变。**

这个推论有两个实际用途：

- **排查**：接口有时报 `CSRF Failed` 有时不报，先确认请求到底带了哪种凭据
- **设计**：如果前端只用 `Authorization` 头，**可以把 `SessionAuthentication` 整个移出配置**——留着它反而让行为变得不确定

> 📌 反过来也成立：如果你的前端用 session cookie（同域部署），那 JWT 认证类就是多余的，留着它只会让"到底走哪条路"变模糊。

#### `CSRF_TRUSTED_ORIGINS` 的坑

HTTPS 下 Django 会校验 `Referer`/`Origin` 头。跨域部署时必须配：

```python
CSRF_TRUSTED_ORIGINS = ["https://admin.example.com"]     # ✅ 带 scheme
```

两个必须注意的点：

- **Django 4.0 起必须带 scheme**（`https://`），写裸域名 `admin.example.com` 会启动报错
- **别用通配符** `https://*.example.com`

> ⚠️ 关于通配符：Django 4.0 要求带 scheme，**正是为了收紧信任边界**——裸域名条目会把 `evil-admin.example.com` 这类子域也纳入信任。所以随手改成 `https://*.example.com` 图省事，等于用一条通配符把刚关上的门又推开。
>
> **有多个子域怎么办？逐个列出来**，别用通配符：
>
> ```python
> CSRF_TRUSTED_ORIGINS = [
>     "https://admin.example.com",
>     "https://ops.example.com",
>     "https://api.example.com",
> ]
> ```
>
> 📌 这两条是**文档与安全实践资料**的结论，本課未做实测（通配符行为需要真实域名的浏览器环境才能验证）。

---

### 知识点 2：Cookie 存放 token 的取舍

#### 三种存放位置的对比

| 存放位置 | XSS 能偷到 token 吗 | CSRF 能利用吗 | 说明 |
|---------|-------------------|--------------|------|
| `localStorage` | ⚠️ **能**（JS 可读） | ✅ 安全（不会自动随请求发出） | 需自己防范 XSS |
| Cookie（无 HttpOnly） | ⚠️ **能** | ⚠️ **能** | **两头都不设防，最差** |
| Cookie（`HttpOnly` + `SameSite`） | ✅ 读不到 | ✅ 大部分拦住 | 折中方案 |

> 📌 读法：这张表的"✅"统一表示**安全**。所以 `localStorage` 那一行是"XSS 能偷到（危险）、CSRF 安全"。

#### 🔑 HttpOnly 与 SameSite 是两个正交的属性

这是本知识点最容易被搞混的地方。很多人把"Cookie 方案"当成一件事，其实它至少由两个独立开关组成：

```text
Cookie 名      HttpOnly  SameSite  secure
t_http_only   True      Lax       False
t_plain       False     Lax       False
t_strict      True      Strict    False
t_none        True      None      True      ← 配 None 必须带 secure
```

**能力边界（各自防各自的）**：

| 属性 | 防什么 | 防不住什么 |
|------|-------|-----------|
| `HttpOnly=True` | ✅ JS 读不到 `document.cookie`，**缓解 XSS 窃取 token** | ❌ 防不住 XSS 本身——脚本仍能以你的身份发请求 |
| `SameSite=Lax` | ✅ 跨站 POST/PUT 不带此 Cookie，**缓解 CSRF** | ❌ 防不住同站内的恶意请求；顶层 GET 导航仍会带 |
| `SameSite=None` | — | ❌ 放弃 CSRF 防护（且必须配 `secure=True`） |

> 📌 **关键认知**：两个属性**各防各的，谁也替代不了谁**。
>
> - 只设 `HttpOnly` 不设 `SameSite`：XSS 难窃取，但 **CSRF 依然成立**
> - 只设 `SameSite` 不设 `HttpOnly`：CSRF 拦住了，但 **XSS 能直接读到 token**
>
> 所以"localStorage 还是 Cookie"这个二选一问法是错的，正确问法是"**HttpOnly 设不设、SameSite 设成什么**"这两个独立问题。

#### 实测：Cookie 方案会让 CSRF 回归

> 📌 下面的 3c 用**真实的 Session 登录**来验证写操作是否被拦。之所以不用 `cookie-me` 那个视图，是因为它 `authentication_classes = []`，`SessionAuthentication` 根本不参与，`enforce_csrf` 自然不会被调用——那样测出来的 200 会掩盖真实机制（这是本課实验设计上踩的第一个坑，记录在此）。

```text
【3a】登录，服务端下发 HttpOnly Cookie：
  -> 200 {'ok': True, 'user': 'alice'}
  响应 Set-Cookie：['access_token']
  access_token: httponly=True, samesite=Lax

【3b】后续请求自动携带 Cookie：
  客户端 cookie jar = ['access_token']
  GET  -> 200 {'token_from_cookie': 'demo-token-for-alice'}

【3c】Cookie 方案下，写操作还需要 CSRF 吗？
  POST 不带 X-CSRFToken -> 403  CSRF Failed: CSRF token missing.
  POST 带上 X-CSRFToken -> 200
```

**即使 token 是 HttpOnly 的，浏览器照样自动带上它**——这正是知识点 1 说的"CSRF 的核心前提"。

所以折中方案的完整形态是：

```python
# 登录接口下发 token
resp.set_cookie(
    "access_token",
    token,
    httponly=True,        # 防 XSS 读取
    samesite="Lax",       # 防 CSRF 跨站携带
    secure=True,          # 生产必须，仅 HTTPS
    path="/",
)
```

```python
# settings.py —— Django 的默认值
SESSION_COOKIE_HTTPONLY = True      # 默认 True（文档明示）
SESSION_COOKIE_SAMESITE = 'Lax'     # 默认 'Lax'（文档明示）
SESSION_COOKIE_SECURE = False       # ⚠️ 默认 False，生产必须改成 True
```

> ⚠️ **`SESSION_COOKIE_SECURE` 默认是 `False`**，意味着 session cookie 可以走明文 HTTP 被嗅探。这是三个默认值里唯一需要你主动改的。

#### 折中方案的真实代价

即便配齐了三个属性，Cookie 方案仍然不完美：

1. **XSS 依然致命**：`HttpOnly` 只挡住"读取 token"，挡不住"以你的身份发请求"。有 XSS 的站点，攻击者不需要拿到 token，直接调用你的接口就行。
2. **SameSite=Lax 有缝隙**：顶层 GET 导航仍会带 Cookie（文档明示：*the session cookie would be allowed when following a regular link from an external website*）。所以如果你有**用 GET 做状态变更**的接口（这是个反模式，但内部系统里很常见），Lax 拦不住它。
3. **SameSite 不是 CSRF 的替代品**：Django 文档原话是 *"SameSite isn't supported by all browsers, so it's not a replacement for Django's CSRF protection, but rather a defense in depth measure"*——它是**纵深防御**，不是替代。

> 📌 第 2、3 条均为**文档明示**，本課未做实测——验证它们需要真实浏览器环境（跨站页面 + Cookie 行为），超出本課实验工程的能力范围。

#### 决策建议

```text
纯 API + 前后端分离（前端独立域名）
  → token 放 Authorization 头，不进 Cookie
  → 不用管 CSRF，但必须做好 XSS 防护（转义、CSP）

同域部署（前端和 API 一个域名）
  → 可以直接用 session + CSRF，最简单也最安全
  → 这也是课 8 说的"别盲从 JWT"的典型场景

既要防 XSS 又要防 CSRF
  → HttpOnly + SameSite=Lax/Strict + secure + 仍然开启 CSRF
  → 但要清楚：这只是缩小暴露面，不是根治
```

---

### 知识点 3：越权与批量分配的防线

#### 两类越权

| 类型 | 英文 | 定义 | 例子 |
|------|------|------|------|
| **水平越权** | BOLA / IDOR | 同级别用户之间互相访问资源 | bob 改 alice 的文章 |
| **垂直越权** | Privilege Escalation | 低权限用户访问高权限功能 | member 访问管理员接口 |

课 9 解决的是**水平越权**（`has_object_permission`）。垂直越权在课 9 没展开，这里补上。

#### 实测：水平越权

```text
【4a】有对象级权限的详情接口：
  bob PATCH alice 的文章 -> 403  您没有执行该操作的权限。
  数据库实际值 = 'alice 的草稿'      ← 没被改

【4b】反例接口（只有 IsAuthenticated）：
  bob PATCH alice 的文章 -> 200
  数据库实际值 = 'bob 越权篡改成功'   ← ❌ 真的写库了
```

#### 实测：垂直越权

```text
【5a】有角色校验的接口：
  alice(member) -> 403  您没有执行该操作的权限。
  root(admin)   -> 200  {'secret': '只有管理员能看到'}

【5b】反例接口（只校验 IsAuthenticated）：
  alice(member) -> 200  {'secret': '只有管理员能看到'}   ← ❌ 越权成功
```

垂直越权的修法很直接——**加一个角色权限类**：

```python
class IsAdminRole(permissions.BasePermission):
    def has_permission(self, request, view):
        return getattr(request.user, "role", None) == "admin"

class AdminOnlyView(views.APIView):
    permission_classes = [permissions.IsAuthenticated, IsAdminRole]
```

> 📌 **别用 `is_superuser` 做业务角色判断。** `is_staff`/`is_superuser` 是 Django Admin 的开关，业务权限应该有独立的角色字段。混用会导致"为了进某个业务功能而给人开 superuser"。

#### 批量分配（Mass Assignment）

这是本课最危险、也最容易被忽略的一类。

**定义**：API 把客户端传来的字段**直接绑定到模型**上，不检查"这个调用方有没有资格设置这个字段"。

- OWASP API Security Top 10 2023 编号：**API3:2023 Broken Object Property Level Authorization**
- CWE 编号：**CWE-915**
- 典型案例：**2012 年 GitHub 被 researcher 用 mass assignment 把自己的 SSH key 加进 Rails 组织**

**它和越权的关系**：

```text
水平/垂直越权  →  你有没有资格访问"这个对象"
批量分配       →  你有没有资格写"这个字段"

关键区别：批量分配的受害者"本来就有权访问这个接口"。
          PATCH /api/users/me/ 对自己操作，完全合法——
          只是他多传了一个 is_staff。
```

**DRF 的默认行为是危险的**：`ModelSerializer` 会把模型的字段**全部生成为可写字段**，除非你显式声明 `read_only`。

#### 实测：提权

```text
【6a】危险写法（所有字段可写）：
  PATCH /api/profile-vuln/  {"role":"admin","is_staff":true,"is_superuser":true}
  -> 200
  alice 变更后：role=admin, is_staff=True, is_superuser=True
  ❌ 提权成功

【6b】正确写法（敏感字段 read_only）：
  PATCH /api/profile-safe/  {"role":"admin",...,"email":"a@b.com"}
  -> 200
  alice 变更后：role=member, is_staff=False, is_superuser=False
  email 是否被改: a@b.com
  ✅ 提权被阻断
```

**注意 6b 的两个细节**：

1. **返回 200，不是 403**。`read_only` 字段被**静默忽略**，不是报错拒绝。
2. **`email` 照常更新了**。也就是说白名单内的字段正常工作，只有敏感字段被丢弃。

> ⚠️ **"静默忽略"既是优点也是坑**：
> - 优点：不会因为客户端多传了字段就报错，兼容性好
> - 坑：**你不会收到任何告警**。攻击者试探你的字段时，日志里一片正常

#### 实测：伪造 author 与刷量

```text
【7a】危险写法（author / view_count 可写）：
  POST {"title":"bob 冒名发文","author":1,"view_count":999999}
  -> 201  author=1, view_count=999999
  alice.pk=1, bob.pk=2
  ❌ 冒名成功（文章挂到 alice 名下）
  ❌ 刷量成功

【7b】正确写法（author / view_count / is_pinned 只读）：
  POST {"title":"bob 正常发文","author":1,"view_count":999999,"is_pinned":true}
  -> 201  author=2, view_count=0, is_pinned=False
  ✅ author 未被篡改（被 perform_create 强制注入为 bob）
  ✅ view_count 未被刷
  ✅ is_pinned 未生效
```

#### 三条防线

**防线一：显式 `fields` 白名单（首选）**

```python
class UserRegisterSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ["id", "username", "email", "password"]   # ← 白名单
        extra_kwargs = {"password": {"write_only": True}}
```

实测（注册接口被塞 `is_superuser`）：

```text
【8】攻击者注册时给自己 admin + superuser：
  POST {"username":"mallory",...,"role":"admin","is_staff":true,"is_superuser":true}
  -> 201
  响应字段：['email', 'id', 'username']
  实际入库：role=member, is_staff=False, is_superuser=False
  ✅ 提权被阻断
```

> 🔴 **绝对不要用 `fields = "__all__"`。** 它等于把模型的每个字段都开放为可写，且**模型以后新增的字段会自动跟着开放**。

**防线二：`read_only_fields`**

```python
class UserSafeSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ["id", "username", "email", "role", "is_staff", "can_publish"]
        read_only_fields = ["role", "is_staff", "can_publish"]   # 能读不能写
```

适用于"**要展示给用户看，但不允许改**"的字段。

**防线三：`perform_create` / `perform_update` 注入归属**

```python
class ArticleCreateSafeView(generics.CreateAPIView):
    serializer_class = ArticleSafeSerializer

    def perform_create(self, serializer):
        serializer.save(author=self.request.user)      # ← 服务端决定，不信客户端
```

**这是最根本的一条**：凡是"归属关系"（author、owner、tenant），**永远不要从请求体里取**。

#### 🔴 白名单 vs 黑名单

这是本课最重要的方法论：

```python
# ❌ 黑名单（denylist）—— 新字段会自动开放
class Meta:
    model = User
    exclude = ["is_superuser"]       # 半年后新增 credit_limit，静默开放

# ✅ 白名单（allowlist）—— 新字段默认关闭
class Meta:
    model = User
    fields = ["id", "username", "email"]   # 新增字段不在列表里，自动安全
```

**为什么黑名单必然失败**：你今天列的黑名单是完整的，但**明天有人给模型加一个新字段时，他不会知道这里有个 exclude 需要同步更新**。而白名单天然免疫——新字段不在列表里，就是安全的。

> 📌 Django 官方文档对 `ModelForm` 的 `exclude` 也有同样的警告（ticket #8620 有长篇讨论）：**优先用 `fields` 而非 `exclude`**。DRF serializer 是同一个道理。

#### ⚠️ 别绕过 serializer 直接写 ORM

上面三条防线都建立在"数据经过 serializer"这个前提上。如果你写出这样的代码，**三条防线全部失效**：

```python
# 🔴 危险：完全绕过 serializer
def update_profile(request):
    User.objects.filter(pk=request.user.pk).update(**request.data)
    return Response({"ok": True})
```

`.update(**request.data)` 会把请求体里的**每一个键**都写进数据库，`role`、`is_staff`、`balance` 无一幸免。

另外两条同类陷阱：

```python
Article.objects.create(**request.data)      # 🔴 同样危险
for k, v in request.data.items():
    setattr(article, k, v)                   # 🔴 同样危险
```

**原则：凡是写操作，一律走 serializer 的 `validated_data`，绝不直接消费 `request.data`。**

> 📌 这就是为什么课 4 强调"校验必须在 serializer 里"——它不只是为了字段格式校验，更是**唯一的字段白名单执行点**。

#### 三者对照表

| | 水平越权 | 垂直越权 | 批量分配 |
|---|---|---|---|
| 攻击目标 | 别人的**对象** | 高权限的**功能** | 自己的**字段** |
| 用户有接口权限吗 | 有（接口合法） | 无 | **有（这是它的特点）** |
| 防线 | 对象级权限 + queryset 过滤 | 角色权限类 | serializer 白名单 |
| 在哪一课 | 课 9 | 本课 | 本课 |
| OWASP 编号 | API1:2023 BOLA | API5:2023 BFLA | API3:2023 |

---

## 第四幕 · 实操验证

### 验证环境

| 组件 | 版本 | 说明 |
|------|------|------|
| Python | 3.13.14 | Windows 托管（`dj-course` venv） |
| Django | 6.1 | 课程基线版本 |
| djangorestframework | 3.18.0 | Django 6.1 必须配 ≥ 3.18.0 |
| 数据库 | SQLite | 实验工程自带，随脚本重建 |

实验工程在仓库外的临时目录（`%TEMP%/dj-lesson10-demo/sec_lab`），运行 `python run_lab.py` 一键复现全部结论。

### 实验 1：CSRF 的三种情况

```text
【1a】Session 认证 + 不带 token -> 403  CSRF Failed: CSRF cookie not set.
【1b】Session 认证 + X-CSRFToken -> 200
【1c】Authorization 头 + 不带 token -> 200，enforce_csrf 调用记录为空
【1d】不带 Authorization 头 -> 403  身份认证信息未提供。（认证层，非 CSRF）
```

### 实验 2：CSRF Cookie 的属性

```text
csrftoken:  httponly=False, samesite=Lax, secure=False
CSRF_COOKIE_HTTPONLY = False
SESSION_COOKIE_HTTPONLY = True
-> csrftoken 故意不是 HttpOnly，因为前端 JS 必须读到它
```

### 实验 3：Cookie 存 token

```text
【3a】下发 httponly=True, samesite=Lax 的 access_token
【3b】后续请求自动携带
【3c】POST 不带 X-CSRFToken -> 403  CSRF Failed: CSRF token missing.
      POST 带上 -> 200
【3d】四个 Cookie 的属性对照（HttpOnly × SameSite 正交）
```

### 实验 4：水平越权

```text
【4a】有对象级权限 -> 403，数据库值未变
【4b】只有 IsAuthenticated -> 200，数据库值 = 'bob 越权篡改成功'
```

### 实验 5：垂直越权

```text
【5a】有角色校验 -> alice(member) 403 / root(admin) 200
【5b】无角色校验 -> alice(member) 200，拿到管理员数据
```

### 实验 6：批量分配 —— 提权

```text
【6a】危险写法 -> role=admin, is_staff=True, is_superuser=True  ❌
【6b】read_only -> role=member, is_staff=False, is_superuser=False
      email 照常更新为 a@b.com（read_only 字段被静默忽略，返回仍是 200）
```

### 实验 7：批量分配 —— 伪造 author 与刷量

```text
【7a】危险写法 -> author=1(alice), view_count=999999  ❌ 冒名 + 刷量
【7b】正确写法 -> author=2(bob), view_count=0, is_pinned=False
```

### 实验 8：注册接口最小化白名单

```text
POST 携带 role/is_staff/is_superuser -> 201
响应字段：['email', 'id', 'username']
实际入库：role=member, is_staff=False, is_superuser=False  ✅
```

### 附：实验工程结构

```text
sec_lab/
├── manage.py
├── config/
│   ├── settings.py     # SessionAuthentication + CsrfViewMiddleware
│   ├── urls.py
│   └── wsgi.py
└── apps/
    ├── users/
    │   └── models.py   # User(role, can_publish)
    └── articles/
        ├── models.py       # Article(author, title, status, is_pinned, view_count)
        ├── serializers.py  # 危险写法 vs 正确写法三组对照
        ├── views.py
        └── urls.py
```

`serializers.py` 里的三组对照：

| Serializer | 用途 |
|-----------|------|
| `UserSerializer` / `UserSafeSerializer` | 实验 6：提权的可写 vs read_only |
| `ArticleVulnerableSerializer` / `ArticleSafeSerializer` | 实验 7：author/view_count 可写 vs 只读 |
| `UserRegisterSerializer` | 实验 8：最小化白名单 |

`views.py` 里的关键组件：

| 组件 | 用途 |
|------|------|
| `SessionWriteView` | 实验 1：Session 认证的 CSRF 强制校验 |
| `HeaderAuth` / `HeaderWriteView` | 实验 1c/1d：Token 方案免疫 CSRF 的对照 |
| `CookieLoginView` / `CookieMeView` | 实验 3：Cookie 折中方案 |
| `ArticleDetailView` / `ArticleNoGuardView` | 实验 4：水平越权正反对照 |
| `AdminOnlyView` / `AdminNoGuardView` | 实验 5：垂直越权正反对照 |
| `ProfileVulnerableView` / `ProfileSafeView` | 实验 6：批量分配提权正反对照 |
| `ArticleCreateVulnerableView` / `ArticleCreateSafeView` | 实验 7：归属注入正反对照 |

## 第五幕 · 体系收束

### 阶段 3 完整收官

```text
课 8  认证：你是谁          → request.user 从哪来
课 9  权限：你能干什么      → request.user 能碰哪些数据
课 10 安全实践              → 凭据怎么被偷用、字段怎么被写坏  ← 本课
```

三个阶段性问题，对应三类不同的防线：

| 问题 | 防线 | 失效时的后果 |
|------|------|-------------|
| 你是谁 | 认证类 | 冒用身份 |
| 你能碰哪些数据 | 权限类 + queryset 过滤 | 越权 |
| 你的凭据怎么被偷用 | Cookie 属性 + CSRF | 身份被借 |
| 你的字段怎么被写坏 | serializer 白名单 | 提权、数据污染 |

**注意后两条的共同点**：它们都发生在"用户身份完全合法"的前提下。课 8/9 的防线对它们**完全无效**——这就是本课存在的理由。

### 你现在会了什么

1. **说清 CSRF 的真实边界**——不是"用不用 JWT"，而是"凭据在不在 Cookie 里"
2. **知道 DRF 把 CSRF 挪到了认证类**——`as_view()` 的 `csrf_exempt` + `SessionAuthentication.enforce_csrf`
3. **拆开 HttpOnly 与 SameSite**——两个正交属性，各防各的
4. **区分两类越权并各自设防**——水平靠对象级权限，垂直靠角色权限类
5. **堵住批量分配**——白名单优先于黑名单，`perform_create` 注入归属

### 一图总结

```text
                    你的凭据在哪？
                         │
        ┌────────────────┴────────────────┐
   Authorization 头                    Cookie
        │                                 │
   浏览器不自动带                    浏览器自动带
        │                                 │
   CSRF 免疫                        CSRF 风险回归
   （enforce_csrf 不调用）               │
                              ┌───────────┴───────────┐
                        HttpOnly=True            SameSite=Lax
                          防 XSS 读取               防跨站携带
                              └──────── 必须同时设 ────────┘


                    用户身份合法之后
                         │
        ┌────────────────┼────────────────┐
   碰别人的对象       碰高权限功能      多写一个字段
        │                 │                 │
   水平越权          垂直越权          批量分配
        │                 │                 │
  对象级权限         角色权限类      serializer 白名单
  + queryset         (IsAdminRole)   + perform_create
```

### 埋下的伏笔

- **中间件层的防护**：本课说 DRF 视图 `csrf_exempt` 了，那 Django 中间件在 API 场景还能做什么？→ 课 18
- **测试怎么写**：本课这些漏洞（越权、批量分配）都该有回归测试兜着 → 课 20
- **Admin 的安全收敛**：`is_staff`/`is_superuser` 是 Admin 的开关，业务角色该自己建 → 课 19

### 阶段 3 进度

| 课 | 主题 | 状态 |
|----|------|------|
| 课 8 | 认证：你是谁 | ✅ 已完成 |
| 课 9 | 权限：你能干什么 | ✅ 已完成 |
| 课 10 | 分离架构下的安全实践 | ✅ 已完成（本课） |

**阶段 3「认证、权限与鉴权」已全部完成。**

---

## 🐞 本课误区速查

| 误区 | 真相 |
|------|------|
| "配了 `CsrfViewMiddleware` 就有 CSRF 防护" | **DRF 所有视图都被 `csrf_exempt`**，中间件对它们无效；真正的校验在 `SessionAuthentication.enforce_csrf` |
| "用 JWT 就完全不用管 CSRF" | 前提是不把 token 放 Cookie。**放进 Cookie 就原样回归** |
| "HttpOnly 能防 XSS" | 只能防**读取** token。有 XSS 时脚本仍能**以你的身份发请求** |
| "SameSite 可以替代 CSRF 防护" | Django 文档明确说它是 **defense in depth**，不是替代 |
| "SameSite=Lax 拦住所有跨站" | 顶层 **GET 导航仍会带 Cookie**。用 GET 做状态变更的接口拦不住 |
| "Cookie 方案二选一：要么防 XSS 要么防 CSRF" | 错误二分。`HttpOnly` 和 `SameSite` 是**两个正交开关**，可以同时设 |
| "session cookie 默认就安全" | `SESSION_COOKIE_SECURE` **默认 False**，生产必须改 True |
| "权限配好了就不会被提权" | 批量分配绕的是**字段**不是接口。合法用户改自己的资料也能提权 |
| "`read_only` 字段被传会报错" | **静默忽略**，返回 200。你的日志里一片正常 |
| "用 `exclude` 和用 `fields` 差不多" | `exclude` 是**黑名单**，模型新增字段会静默开放。永远优先 `fields` |
| "`fields = "__all__"` 只是多返回点字段" | 它把模型**每个字段都开放为可写**，包括未来新增的 |
| "`is_superuser` 可以当业务角色用" | 它是 **Django Admin 的开关**。混用会导致为进某功能而开 superuser |
| "CSRF 失败和认证失败的 403 是一回事" | 完全不是。前者 `CSRF Failed: ...`，后者 `身份认证信息未提供。` |
| "多个认证类时 CSRF 行为是固定的" | **随请求携带的凭据类型而变**。带 JWT 头不校验，只带 session cookie 才校验 |
| "批量分配只在 serializer 层" | `Model.objects.update(**request.data)` **完全绕过 serializer**，三条防线全失效 |
| "用通配符配 `CSRF_TRUSTED_ORIGINS` 省事" | `https://*.example.com` 会把 `evil-admin.example.com` 也纳入信任。逐个列出域名 |

---

## 📚 官方文档

| 主题 | 链接 | 说明 |
|------|------|------|
| Django · CSRF | https://docs.djangoproject.com/en/6.1/ref/csrf/ | CSRF 机制、`CSRF_TRUSTED_ORIGINS`、使用场景 |
| Django · Settings | https://docs.djangoproject.com/en/6.1/ref/settings/ | `SESSION_COOKIE_*` / `CSRF_COOKIE_*` 全部默认值 |
| Django · set_cookie | https://docs.djangoproject.com/en/6.1/ref/request-response/ | `httponly` / `samesite` / `secure` 参数语义 |
| DRF · Authentication | https://www.django-rest-framework.org/api-guide/authentication/ | `SessionAuthentication` 与 CSRF 的关系 |
| OWASP · Mass Assignment Cheat Sheet | https://cheatsheetseries.owasp.org/cheatsheets/Mass_Assignment_Cheat_Sheet.html | 白名单 vs 黑名单、各框架修法 |
| OWASP API Security Top 10 2023 | https://owasp.org/API-Security/ | API1 BOLA / API3 属性级授权 / API5 BFLA |

### 「文档明示」与「实测确认」的区分

| 结论 | 来源 |
|------|------|
| `SESSION_COOKIE_HTTPONLY` 默认 `True` | ✅ 文档明示 |
| `SESSION_COOKIE_SAMESITE` 默认 `'Lax'` | ✅ 文档明示 |
| `SESSION_COOKIE_SECURE` 默认 `False` | ✅ 文档明示 |
| `SESSION_COOKIE_AGE` 默认 1209600 秒（2 周） | ✅ 文档明示 |
| `SameSite` 不是 CSRF 的替代品，是 defense in depth | ✅ 文档明示 |
| `SameSite=None` 必须配 `secure=True` | ✅ 文档明示 |
| Django 4.0 起 `CSRF_TRUSTED_ORIGINS` 必须带 scheme | ✅ 文档明示 |
| DRF 的 `SessionAuthentication` 强制 CSRF 校验 | ✅ 文档明示 |
| DRF 推荐用 `fields` 而非 `exclude` | ✅ 文档明示（同 Django ModelForm，ticket #8620） |
| `SameSite=Lax` 下顶层 GET 导航仍带 Cookie | ✅ 文档明示（原文：*allowed when following a regular link*） |
| 批量分配 = OWASP API3:2023 / CWE-915 | ✅ 文档明示 |
| **DRF 的 `APIView.as_view()` 返回 `csrf_exempt(view)`** | ✅ 源码核实（`views.py` `as_view`） |
| **CSRF 校验在 `SessionAuthentication.enforce_csrf` 里** | ✅ 源码核实（`authentication.py`） |
| **未登录时 `authenticate()` 直接 return None 跳过 CSRF** | ✅ 源码核实 |
| **Token 认证下 `enforce_csrf` 完全不被调用** | 🔬 **实测确认**（调用记录为空） |
| **`csrftoken` 默认 `httponly=False`，`sessionid` 为 `True`** | 🔬 实测确认 |
| **Cookie 方案下 POST 不带 token → 403 `CSRF token missing.`** | 🔬 实测确认 |
| **批量分配提权成功且返回 200** | 🔬 实测确认 |
| **`read_only` 字段静默忽略、白名单字段照常更新** | 🔬 实测确认 |
| **伪造 author 与刷 view_count 均成功** | 🔬 实测确认 |
| **注册接口白名单外的字段被直接丢弃** | 🔬 实测确认 |
| **`HttpOnly` × `SameSite` 四种组合的属性实测** | 🔬 实测确认 |

---

## 🚀 下一批接力提示词

**继续下一课（进入阶段 4）**：

```text
继续学 Django 进阶（前后端分离）。我的学习档案在 django/00-学习档案.md，
刚学完阶段 3《认证、权限与鉴权》的课 10《分离架构下的安全实践》
（知识点：CSRF 的重新理解、Cookie 存放 token 的取舍、越权与批量分配的防线），
阶段 3 已全部完成。请按大纲继续讲解阶段 4 的课 11《查询表达式进阶》。
```

**如果想先做一次安全自查**：

```text
我在做一个 Django + DRF 的前后端分离项目，已配好认证与权限。
请帮我做一次安全自查，重点看五个问题：
1. 我的凭据放在哪？（Authorization 头还是 Cookie）对应的 CSRF 配置对不对
2. 所有 ModelSerializer 里，有没有 fields = "__all__" 或用 exclude 的
3. 有没有敏感字段（role / is_staff / is_superuser / owner / 余额类）是可写的
4. 创建类接口的归属字段（author/owner）有没有从 request.user 注入
5. 生产环境的 SESSION_COOKIE_SECURE / SESSION_COOKIE_SAMESITE 配了没有
（贴出你的 settings 与 serializer 定义）
```

---

## 🧭 课程导航

**上一课**：[阶段 3 · 课 9《权限：你能干什么》](./lesson-09-权限你能干什么.md)
**下一课**：[阶段 4 · 课 11《查询表达式进阶》](../../4-数据层纵深/lessons/lesson-11-查询表达式进阶.md)
**阶段概览**：[阶段 3：认证、权限与鉴权](../overview.md)
**返回**：[阶段 3 概览](../overview.md) ｜ [课程目录](../../../02-课程目录.md)

---

> **本课一句话**：CSRF 的真正分界线不是"用不用 JWT"，而是"**凭据在不在 Cookie 里**"——DRF 把所有视图都 `csrf_exempt` 了，校验被挪进 `SessionAuthentication`，所以只有 Cookie 凭据才会被查。而比越权更隐蔽的是批量分配：**用户身份完全合法、接口权限完全正确，他只是往请求体里多加了一个字段名**，就把自己变成了 superuser。堵它的办法不是黑名单，而是白名单——因为黑名单会在模型新增字段的那天，静默失效。
