# 课 9　权限：你能干什么

> 📖 情节定位：**守门（二）** —— 不只是"登录了吗"，而是"这是你的吗"
> 🎯 本课目标：实现对象级权限，配置限流，理解权限层的执行顺序
> 🔗 承接：课 8 装好了第一个守门人（认证），它只回答"你是谁"
> 🔗 后续：课 10 回答分离架构下剩下的攻击面（CSRF、token 存放、越权与批量分配）

---

## 第一幕 · 场景引入

课 8 结束时，你按选型结论给文章接口配好了认证方式：

```python
class ArticleDetailView(generics.RetrieveUpdateDestroyAPIView):
    serializer_class = ArticleSerializer
    permission_classes = [IsAuthenticated]
    queryset = Article.objects.all()
```

你试了一下，感觉挺好：**没带凭据的请求一律被拒，带上凭据就能读写**。安全了。

**第二天，测试同学提了个 bug**：

> "我用 B 账号登录，把 URL 里的文章 ID 换成 A 账号那篇，`PATCH` 了一把——返回 `200`，标题真被我改了。"

你愣住了。`IsAuthenticated` 明明写着，认证也确实过了——**B 是个合法用户，他只是不该动 A 的数据**。

这就是认证与权限的分界线：

```text
认证（课 8）  你是谁          —— 进门查身份证
权限（本课）  你能干什么      —— 进门后，哪间房你能进
```

`IsAuthenticated` 只管"有没有身份证"，它**完全不关心你要动谁的东西**。

于是你加上对象级权限，改完再试，B 改 A 的文章返回 `403` 了。你以为收工了。

**一周后，安全扫描报告来了**：

> "文章列表接口存在水平越权：B 用户虽然改不了 A 的文章，但能看到 A 的全部草稿标题。"

你这才意识到——**列表接口压根不会走对象级权限**。拦住单行改动的那道关卡，对"列一批数据"这件事根本不起作用。

---

## 第二幕 · 认知困惑

### 困惑一：认证、权限、限流，谁先谁后？

文档里这三样都写在 `REST_FRAMEWORK` 配置里，看起来是平级的。但配置平级不等于执行平级。

顺序搞错，你会遇到两类莫名其妙的现象：

- 想限流，结果请求在权限层就被挡了，**限流一次都没执行**
- 想靠限流防刷，结果发现**非法请求根本不消耗配额**

本课会用探针把顺序钉死，而不是让你背结论。

### 困惑二：`has_object_permission` 和 queryset 过滤，是不是一回事？

不是。它们守的**方向不同**：

```text
has_object_permission   行级关卡   拿到某一个对象后，判断"这个你能动吗"
queryset 过滤           集合级关卡 圈定"你能看到哪些对象"
```

列表接口只会走后者。所以只写前者，列表照样漏数据。**两个都要写，缺一个就有一个方向的洞。**

### 困惑三：限流配了 `10/minute`，线上真的就是 10 次吗？

**大概率不是。** 限流计数存在缓存里，而开发环境的默认缓存是进程内内存。多进程部署时，每个进程各数各的。

本课会实测给你看：配 `5/minute`，两个进程实际放行几次。

### 困惑四：`throttle_scope` 写了就能改频率吗？

**不能，而且它不报错。** 这是本课最阴的一个坑——你写错写法，接口照样 `200`，你以为限住了，其实一次没限。

---

## 第三幕 · 层层揭示

### 知识点 1：权限四层与执行顺序

#### 四层是什么

一个请求从进来到拿到响应，要穿过四道关卡。其中**前三道在 `APIView.initial()` 里串行执行**，第四道在视图方法内由序列化器执行：

| 层 | 回答什么问题 | 失败响应 | 配置项 | 执行位置 |
|----|-------------|---------|--------|---------|
| **认证** Authentication | 你是谁 | `401`（有挑战头）/ `403`（无） | `DEFAULT_AUTHENTICATION_CLASSES` | `initial()` |
| **权限** Permission | 你能不能做这个操作 | `403` | `DEFAULT_PERMISSION_CLASSES` | `initial()` |
| **限流** Throttling | 你是不是做太频繁了 | `429` | `DEFAULT_THROTTLE_CLASSES` | `initial()` |
| **校验** Validation | 你传的数据对不对 | `400` | 序列化器 | 视图方法内 |

前三层**任一失败就中断**，后面的不再执行——这正是本课实验 5 要证明的事。

#### 源码里的顺序

```python
# rest_framework/views.py:404
def initial(self, request, *args, **kwargs):
    ...
    self.perform_authentication(request)   # ① 认证   ← line 419
    self.check_permissions(request)        # ② 权限   ← line 420
    self.check_throttles(request)          # ③ 限流   ← line 421
```

`perform_authentication` 只是访问 `request.user` 这个惰性属性，真正的认证动作延迟到那时才发生——**这也是为什么认证写在最前面，却看起来"没做什么"**。

#### 实测证据：探针打印

实验工程里给每层挂了探针，一次 `GET` 的打印结果：

```text
⓪ initial 开始
① 认证
② 权限
③ 限流
④ 视图方法
```

顺序确认：**认证 → 权限 → 限流 → 视图方法**。

#### 顺序的实际意义：权限失败时，限流还执行吗

这是顺序问题里最有价值的一条。实验做了两组对照：

```text
【对照组 A】权限放行（TracePermission 返回 True）：
    ⓪ initial 开始
    ① 认证
    ② 权限
    ③ 限流
    ④ 视图方法
    最终响应 -> 200

【对照组 B】权限拒绝（DenyPermission 返回 False）：
    ⓪ initial 开始
    － 认证（本视图 authentication_classes = []，故无此层）
    ② 权限（拒绝）
    最终响应 -> 403

权限被拒时，限流是否被调用？否
```

> 📌 对照 B 里没有"① 认证"，是因为 `DenyOrderView` 把 `authentication_classes` 设成了空列表。**真实项目里认证层总会出现在权限层之前**，这里刻意清空是为了让拒绝发生在权限层、从而观察"权限拒绝后限流还走不走"。

**权限一票否决，后面的限流和视图方法都不执行。**

这条推论有两面性：

- **好的一面**：被拒绝的非法请求**不消耗限流配额**——攻击者没法用一堆 403 请求把正常用户的配额挤占掉
- **坏的一面**：如果你的限流是针对"未授权探测"设计的（比如防密码爆破），那这个限流**必须在权限之前**才有效，否则根本数不到

> 🤔 **推论：那登录接口怎么防爆破？**
>
> 登录接口本来就是 `AllowAny`（不然没登录的人怎么登录），所以它的限流**一定会被执行**——上面的"坏的一面"对它不成立。
>
> 真正的问题在**计数维度**：`AnonRateThrottle` 按 IP 计数，而登录爆破往往针对**同一个用户名**。想按用户名限流，得自己重写 `get_cache_key`：
>
> ```python
> import hashlib
> from rest_framework.throttling import SimpleRateThrottle
>
> class LoginUsernameThrottle(SimpleRateThrottle):
>     scope = "login"
>
>     def get_cache_key(self, request, view):
>         username = (request.data.get("username") or "").lower().strip()
>         if not username:
>             return None          # 返回 None 表示"这个请求我不限"
>         ident = self.get_ident(request)              # IP
>         digest = hashlib.md5(username.encode()).hexdigest()[:12]
>         return f"throttle_login_{ident}_{digest}"    # IP + 用户名 双维度
> ```
>
> ```python
> # settings.py
> "DEFAULT_THROTTLE_RATES": {"login": "5/minute"}
> ```
>
> ⚠️ 两个细节：`get_cache_key` 返回 `None` 时该请求**完全不限流**——源码写得很直白（`throttling.py:119-121`）：
>
> ```python
> self.key = self.get_cache_key(request, view)   # ← line 119
> if self.key is None:                            # ← line 120
>     return True                                 # ← line 121，直接放行
> ```
>
> 另外别忘了前面说的——**内置实现有并发竞态**，登录爆破这种场景建议用 Redis 原子计数器。
>
> 这条正好回答了"为什么知识点 3 要讲 `get_cache_key`"。

> ⚠️ 注意对照 B 里没有"① 认证"。因为 `DenyOrderView` 把 `authentication_classes` 设成了空列表。真实项目里认证层总会出现在权限层之前。

#### 各层的职责边界

| 你想判断的事 | 该放哪层 | 放错会怎样 |
|-------------|---------|-----------|
| 这个请求带没带合法凭据 | 认证 | 放权限层 → 拿不到 `request.user` |
| 登录用户能不能调这个接口 | 权限 `has_permission` | 放视图里 → 散落各处，必然漏 |
| 这个用户能不能动**这条**记录 | 权限 `has_object_permission` | 放 queryset → 详情接口漏判 |
| 这个用户能**看到哪些**记录 | queryset 过滤 | 放权限 → 列表接口根本不走 |
| 请求是不是太频繁 | 限流 | 放权限 → 拿不到历史计数 |
| 数据格式对不对 | 序列化器校验 | 放权限 → 拿不到反序列化结果 |

---

### 知识点 2：自定义对象级权限

#### 两个钩子

DRF 的权限类有两个方法，分别对应两个方向：

```python
class BasePermission:
    def has_permission(self, request, view):
        """集合级：这个请求能不能进这个视图？"""
        return True

    def has_object_permission(self, request, view, obj):
        """行级：这个用户能不能动 obj 这一条？"""
        return True
```

源码层面看得很清楚。对象级权限是在 `GenericAPIView.get_object()` 里触发的：

```python
# rest_framework/generics.py
def get_object(self):                                  # ← line 79
    ...
    self.check_object_permissions(self.request, obj)   # ← line 103
```

`get_object()` 只在详情路由（`/articles/1/`）被调用，列表路由走的是 `get_queryset()` + `filter_queryset()`，压根不碰 `get_object()`。

#### 实测证据：列表路由根本不调对象级权限

实验用 mock 记录了调用：

```text
列表 /api/articles/   -> 调用记录 （空）
详情 /api/articles/1/ -> 调用记录 ['has_object_permission(alice 自己)']
```

**列表接口一次都没调用 `has_object_permission`。** 这是文档里没有明说、但会直接导致越权漏洞的事实。

想自己复现，用 mock 把这个方法替换成"只记录、仍放行"的版本：

```python
from unittest import mock
from apps.articles import views

def probe(self, request, view, obj):
    views.CALL_LOG.append(f"has_object_permission({obj.title[:8]})")
    return True       # 仍然放行，只观察"有没有被调用"

with mock.patch.object(views.IsAuthorOrReadOnly, "has_object_permission", probe):
    c_alice.get("/api/articles/")                 # 输出：（空）
    views.CALL_LOG.clear()
    c_alice.get(f"/api/articles/{alice_art.pk}/")  # 输出：['has_object_permission(...)']
```

> 💡 如果写成 lambda 一行式，常见的写法是 `side_effect=lambda *a: (CALL_LOG.append(...) or True)`。这里 `or True` 不是多余的——`list.append()` 返回 `None`，而 DRF 会把 `None` 当作假值拒绝请求，所以必须让它返回一个真值。

#### 标准写法：作者本人可写，他人只读

```python
class IsAuthorOrReadOnly(permissions.BasePermission):
    def has_object_permission(self, request, view, obj):
        # 安全方法（GET/HEAD/OPTIONS）一律放行
        if request.method in permissions.SAFE_METHODS:
            return True
        # 写操作必须是作者本人
        return obj.author == request.user
```

配套的详情视图：

```python
class ArticleDetailView(generics.RetrieveUpdateDestroyAPIView):
    serializer_class = ArticleSerializer
    permission_classes = [permissions.IsAuthenticated, IsAuthorOrReadOnly]
    queryset = Article.objects.all()
```

#### 实测：别人的文章改不了

```text
【GET 详情】bob 读 alice 的文章 -> 200  title=alice 的文章
【PATCH 详情】
  bob 改 alice 的文章   -> 403  detail=您没有执行该操作的权限。
  alice 改自己的文章    -> 200  title=alice 自己改
```

注意 `GET` 是 `200`——`SAFE_METHODS` 放行了读取。**这是设计选择，不是默认安全**：如果你不想让别人读到草稿，`SAFE_METHODS` 那句就不能写，得改成显式判断。

#### 另一半：列表的 queryset 过滤

对象级权限管不了列表，所以列表必须自己圈范围：

```python
class ArticleListCreateView(generics.ListCreateAPIView):
    serializer_class = ArticleSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        # 只返回自己的文章 —— 这是对象级权限的"另一半"
        return Article.objects.filter(author=self.request.user)

    def perform_create(self, serializer):
        serializer.save(author=self.request.user)
```

实测结果：

```text
alice 的列表 -> 200，2 条：['alice 自己改', 'alice 的第二篇']
  bob 的文章出现在列表里？否 ✓
```

#### 🚨 反例：只写 IsAuthenticated 的越权漏洞

实验里保留了一个"错误写法"的对照视图：

```python
class ArticleDetailNoGuardView(generics.RetrieveUpdateDestroyAPIView):
    """反例：只校验"登录了"，不校验"是不是你的"。"""
    serializer_class = ArticleSerializer
    permission_classes = [permissions.IsAuthenticated]     # ← 只有这个
    queryset = Article.objects.all()                       # ← 没有过滤
```

实测：

```text
bob 通过 noguard 接口改 alice 的文章 -> 200
  ❌ 越权成功！title 被改成 = bob 越权篡改成功
  数据库里的真实值 = bob 越权篡改成功
```

**返回 `200`，而且数据库里的值真的被改了。** 这不是"看起来能改"，是实打实的数据污染。

#### 两张关卡的对照表

| | 守什么 | 列表 `/articles/` | 详情 `/articles/1/` |
|---|---|---|---|
| `has_object_permission` | 单行 | ❌ 不执行 | ✅ 执行 |
| queryset 过滤 | 集合 | ✅ 执行 | ✅ 执行（决定 404 还是 403） |

> 📌 **一个容易被忽略的细节**：如果详情视图的 queryset 也做了过滤，那么访问别人的文章会返回 **`404`** 而不是 `403`。
>
> - `404` = "没有这条记录"（连存在都不告诉你）
> - `403` = "有这条，但你不能动"
>
> 从安全角度 `404` 更好——不泄漏"这个 ID 存在"这个信息。本课实验里详情视图用的是 `Article.objects.all()`，所以是 `403`。

#### 多个权限类的组合规则

在 `permission_classes` 里列多个，**默认是 AND 语义**：

```python
permission_classes = [IsAuthenticated, IsAuthorOrReadOnly]
```

全部返回 `True` 才放行，任何一个 `False` 就拒绝。而且 `has_permission` 全部通过后，才会去调 `has_object_permission`。

**想要 OR 语义，DRF 内置了组合类**（`rest_framework/permissions.py`）：

```python
from rest_framework.permissions import OR, AND, NOT, IsAdminUser

class ArticleDetailView(generics.RetrieveUpdateDestroyAPIView):
    # 用本课前面定义过的 IsAuthorOrReadOnly：
    # 作者本人可读可写 或 管理员可写，任一满足即可
    permission_classes = [IsAuthenticated, OR(IsAuthorOrReadOnly, IsAdminUser)]
```

`IsAuthorOrReadOnly` 就是知识点 2 开头定义的那个（安全方法放行、写操作须为作者）。它也支持嵌套组合：

```python
permission_classes = [IsAuthenticated, OR(IsAuthorOrReadOnly, AND(IsAdminUser, IsInSameOrg))]
```

> 📌 注意别写出 `OR(IsAdminUser, IsAuthenticated)` 这种组合——管理员必然是已认证用户，这个 OR 恒为真，等于什么都没限制。OR 的两侧必须是**真正互斥或有区分度**的条件。

源码里这三个类的定义位置：

```text
rest_framework/permissions.py:61   class AND
rest_framework/permissions.py:79   class OR
rest_framework/permissions.py:100  class NOT
```

它们通过 `BasePermissionMetaclass` 支持 `&`、`|`、`~` 运算符，所以下面两种写法等价：

```python
permission_classes = [OR(IsAdminUser, IsAuthenticated)]
permission_classes = [IsAdminUser | IsAuthenticated]
```

> 📌 `IsAuthenticatedOrReadOnly` 就是 DRF 用这套机制预置好的常用组合（`permissions.py:163`），自己写 `OR(...)` 前先看它够不够用。

---

### 知识点 3：限流 Throttling

#### 三个内置限流类

| 类 | 计数键的构成 | 默认 scope | 典型用途 |
|----|-------------|-----------|---------|
| `AnonRateThrottle` | 客户端 IP | `anon` | 未登录的公开接口（登录、注册、验证码） |
| `UserRateThrottle` | 用户 `pk`（未认证时回退 IP） | `user` | 登录用户的写操作 |
| `ScopedRateThrottle` | **`throttle_scope` + 用户 `pk` 或 IP** | 取自视图的 `throttle_scope` | 按视图/动作区分频率 |

> 📌 注意三者的"计数维度"不是同一类东西：前两个按**身份**计数，第三个按**scope + 身份**计数——所以它的键里既含 scope 名，也含用户 ID 或 IP。

#### 配置方式

```python
# settings.py
REST_FRAMEWORK = {
    "DEFAULT_THROTTLE_CLASSES": [
        "rest_framework.throttling.AnonRateThrottle",
        "rest_framework.throttling.UserRateThrottle",
    ],
    "DEFAULT_THROTTLE_RATES": {
        "anon": "5/minute",
        "user": "10/minute",
    },
}
```

频率格式是 `数量/周期`，周期支持 `second` / `minute` / `hour` / `day`。

#### 实测证据 1：匿名限流 5 次/分钟

> ⚠️ **实验设计说明（重要）**：本工程全局配了 `DEFAULT_PERMISSION_CLASSES = IsAuthenticated`。直接打原端点的话，匿名请求会在**权限层**就被挡成 `403`，**根本走不到限流层**。
>
> 所以实验额外做了一个 `AllowAny` 的探针端点来观测限流本身。这不是业务写法，是为了把限流层单独隔离出来看。

```text
【对照】先打未豁免的原端点 /api/throttle-anon/：
  匿名请求 -> 403 身份认证信息未提供。
  -> 权限先拦，限流没机会执行

【实验】再打豁免端点的探针 /api/probe/throttle-anon/：
  第 1 次 -> 200
  第 2 次 -> 200
  第 3 次 -> 200
  第 4 次 -> 200
  第 5 次 -> 200
  第 6 次 -> 429 请求已被限流。 预计 60 秒后可用。
           Retry-After: 60 秒
```

三个可复用的事实：

1. **第 6 次才被拒**——配 `5/minute` 就是放行 5 次，不是 4 次也不是 6 次
2. **429 响应带 `Retry-After` 头**（60 秒），前端可以直接拿它做倒计时
3. **权限层在限流之前**——这是"对照"那一行最想说明的事

> 📌 这条对照在真实项目里非常实用：**你配了限流却发现从来没触发过，先查权限层是不是把它挡了。**

#### 实测证据 2：用户限流按用户隔离

> ⚠️ **配额污染警告**：`UserRateThrottle` 按 `user.pk` 计数，**与访问哪个端点无关**。前面实验里 alice 打过的请求会消耗同一份配额，不清缓存会得到"第 9 次就被限"这种错误的结论。

实验前显式清空缓存后：

```text
alice 连续请求 /api/probe/throttle-user/（user=10/minute）：
  前 12 次状态码：[200, 200, 200, 200, 200, 200, 200, 200, 200, 200, 429, 429]
  -> 第 11 次开始被限流

bob 此时请求（独立计数）：
  bob 第 1 次 -> 200
  bob 第 2 次 -> 200
  -> alice 已耗尽配额，bob 不受影响
```

**alice 被限到 429 了，bob 完全不受影响。** 这就是"按用户隔离"的含义。

缓存键印证了这一点：

```text
限流写入的缓存键：[':1:throttle_user_1']
取一个键拆解：:1:throttle_user_1
  -> 键中含 user.pk=1，这就是"按用户隔离"的实现方式
```

> ⚠️ **一个文档里写了但很容易忽略的点**：`UserRateThrottle` 遇到**未认证**请求时，会**回退用 IP 地址**做计数键（官方文档原话：*Unauthenticated requests will fall back to using the IP address of the incoming request*）。
>
> 推论：如果你把 `UserRateThrottle` 挂在一个 `AllowAny` 的接口上，它实际在当 `AnonRateThrottle` 用——同一出口 IP 的所有人共享一份配额。

#### ⚠️ 并发竞态：内置限流不是严格计数

官方文档有一句很容易被跳过的话：

> *The built-in throttle implementations are open to race conditions, so under high concurrency they may allow a few extra requests through.*

即：内置限流的「读计数 → 判断 → 写回」不是原子操作，**高并发下会多放行几个请求**。

- 一般接口：多放行几个无所谓
- 支付、发短信、限量抢购这类**必须精确**的场景：不能依赖内置实现，要用 Redis `INCR` + `EXPIRE` 这类原子计数器自己写

这条和上面的"多进程翻倍"是**两个独立的问题**：翻倍是缓存不共享导致的，竞态是单进程内并发导致的。即使你换成了 Redis，竞态依然存在。

#### 实测证据 3：限流依赖缓存后端

开发环境默认的缓存后端是 `LocMemCache`——**进程内内存**。

```text
【实测】模拟两个进程（两个独立缓存实例）各自的计数：
  worker1 进程内：第 6 次被拒
  worker2 进程内：第 6 次被拒
  -> 每个进程都各自放行 5 次。配 5/minute，2 个 worker 实际放行 10 次。
     gunicorn 开 4 个 worker，真实配额就是配置值的 4 倍。
```

这不是理论推演，是**用两个独立的 `LocMemCache` 实例真跑出来的**。

**结论：生产环境限流必须用 Redis / Memcached 这类共享缓存**，否则你配的数字只是"单进程数字"，真实配额要乘以 worker 数。

落地配置（以 Redis 为例）：

```python
# settings.py
CACHES = {
    "default": {
        "BACKEND": "django.core.cache.backends.redis.RedisCache",
        "LOCATION": "redis://127.0.0.1:6379/1",
        "KEY_PREFIX": "throttle",   # 便于排查：所有限流键都以它开头
    }
}
```

如果只想让限流走独立缓存、业务缓存仍用本地内存，官方推荐的做法是**给限流类显式绑定 `cache`**：

```python
# throttles.py
from django.core.cache import caches
from rest_framework.throttling import UserRateThrottle

class RedisUserRateThrottle(UserRateThrottle):
    cache = caches["throttle"]        # 类属性，指向另一个缓存别名
```

```python
# settings.py
CACHES = {
    "default": {...},                 # 业务缓存
    "throttle": {
        "BACKEND": "django.core.cache.backends.redis.RedisCache",
        "LOCATION": "redis://127.0.0.1:6379/2",
    },
}
```

> 📌 这正是本课实验 8 里 `SimpleRateThrottle.cache` 是类属性的实际用途——实验用 mock 替换它来模拟多进程，生产里用它来切换到共享缓存。

#### 🔴 实测证据 4：`throttle_scope` 的静默失效陷阱

这是本课最值得记住的一个坑。

假设你想给某个视图单独配一个更严格的频率，于是这么写：

```python
class ThrottleScopedView(APIView):
    throttle_classes = [UserRateThrottle]     # ← 问题在这
    throttle_scope = "burst"                  # ← 写了，但没用

    def get(self, request):
        return Response({"ok": True})
```

然后在 settings 里补上 `burst`:

```python
"DEFAULT_THROTTLE_RATES": {"anon": "5/minute", "user": "10/minute", "burst": "3/minute"}
```

实测结果：

```text
【写法 A · 错】UserRateThrottle   -> 连续 5 次 [200, 200, 200, 200, 200]
   -> 全部 200，burst=3/minute 完全没生效
【写法 B · 对】ScopedRateThrottle -> 连续 5 次 [200, 200, 200, 429, 429]
   -> 第 4 次开始被限流，burst=3/minute 生效
```

**写法 A 配了 `burst=3/minute`，连续 5 次全部 200——一次都没限住，而且不报错。**

源码层面看得很清楚（`rest_framework/throttling.py`）：

```python
class UserRateThrottle(SimpleRateThrottle):
    scope = 'user'          # ← line 191，硬编码，不看视图

class ScopedRateThrottle(SimpleRateThrottle):
    scope_attr = 'throttle_scope'                        # ← line 212
    def __init__(self):
        ...
        self.scope = getattr(view, self.scope_attr, None)  # ← line 221，才去读视图
```

`UserRateThrottle` 的 `scope` 是类属性、硬编码 `'user'`，它从头到尾没看过 `throttle_scope` 一眼。而 `ScopedRateThrottle` 在 `__init__` 里用 `getattr(view, 'throttle_scope', None)` 主动去读。

正确写法：

```python
from rest_framework.throttling import ScopedRateThrottle

class ThrottleScopedView(APIView):
    throttle_classes = [ScopedRateThrottle]   # ← 必须是 ScopedRateThrottle
    throttle_scope = "burst"

    def get(self, request):
        return Response({"ok": True})
```

#### 两种限流类在"未配置 scope"时的行为差异

| 限流类 | 未配 `burst` rate 时会怎样 | 危险程度 |
|--------|--------------------------|---------|
| `UserRateThrottle` + `throttle_scope='burst'` | **静默忽略**，请求全部放行 | 🔴 高——你以为限住了 |
| `ScopedRateThrottle` + `throttle_scope='burst'` | 抛 `ImproperlyConfigured: No default throttle rate set for 'burst' scope` | 🟢 低——启动就炸 |

实测：

```text
UserRateThrottle   + 未配 burst -> 200（静默放行，scope 被忽略）
ScopedRateThrottle + 未配 burst -> ❌ 抛异常
   ImproperlyConfigured: No default throttle rate set for 'burst' scope
```

**报错的反而更安全**，因为它逼你当场发现。静默失效是最难排查的一类问题——接口正常返回 `200`，日志干净，直到被刷爆你都不知道自己从来没限住过。

#### ⚠️ 附带陷阱：`override_settings` 改不了限流频率

实验里想用 `override_settings` 临时加上 `burst` rate，结果发现：

```text
改前 api_settings 里的 rate = {'anon': '5/minute', 'user': '10/minute'}
override_settings 内 api_settings = {'anon': '5/m', 'user': '10/m', 'burst': '3/m'}
但 SimpleRateThrottle.THROTTLE_RATES = {'anon': '5/minute', 'user': '10/minute'}
-> APISettings 跟着 Django settings 变了，限流类里的快照没变。
   源码里它是类属性，在 import 时就绑死了。
```

`api_settings`（DRF 的配置对象）确实跟着变了，但 `SimpleRateThrottle.THROTTLE_RATES` 是**类属性，在模块导入时就绑定了**，不会随之更新。

**推论：给限流写单元测试时，`override_settings` 是无效的**，必须直接 patch 类属性：

```python
from unittest import mock
from rest_framework.throttling import SimpleRateThrottle

RATES = {"anon": "5/minute", "user": "10/minute", "burst": "3/minute"}
with mock.patch.object(SimpleRateThrottle, "THROTTLE_RATES", RATES):
    ...
```

这条和课 8 的 `override_settings(SIMPLE_JWT=...)` 无效是同一类问题——**模块级/类级的配置快照，跟不上 Django settings 的运行时变更**。

---

## 第四幕 · 实操验证

### 验证环境

| 组件 | 版本 | 说明 |
|------|------|------|
| Python | 3.13.14 | Windows 托管（`dj-course` venv） |
| Django | 6.1 | 课程基线版本 |
| djangorestframework | 3.18.0 | Django 6.1 必须配 ≥ 3.18.0 |
| 数据库 | SQLite | 实验工程自带，随脚本重建 |

实验工程在仓库外的临时目录（`%TEMP%/dj-lesson09-demo/perm_lab`），运行 `python run_lab.py` 一键复现全部结论。

### 实验 1：四层执行顺序

```text
⓪ initial 开始
① 认证
② 权限
③ 限流
④ 视图方法

结论：认证 → 权限 → 限流 → 视图方法，且 initial() 在最前。
```

### 实验 2：对象级权限

```text
【GET 详情】bob 读 alice 的文章 -> 200  title=alice 的文章
【PATCH 详情】
  bob 改 alice 的文章 -> 403  detail=您没有执行该操作的权限。
  alice 改自己的文章  -> 200  title=alice 自己改
```

### 实验 2b：对象级权限在哪一步被调用

```text
列表 /api/articles/   -> 调用记录 （空）
详情 /api/articles/1/ -> 调用记录 ['has_object_permission(alice 自己)']
-> has_object_permission 只在详情路由（get_object）执行；
   列表路由一次都不调。所以列表必须靠 queryset 过滤兜底。
```

### 实验 3：列表的 queryset 过滤

```text
alice 的列表 -> 200，2 条：['alice 自己改', 'alice 的第二篇']
  bob 的文章出现在列表里？否 ✓
```

### 实验 4：🚨 只写 IsAuthenticated 的越权漏洞

```text
bob 通过 noguard 接口改 alice 的文章 -> 200
  ❌ 越权成功！title 被改成 = bob 越权篡改成功
  数据库里的真实值 = bob 越权篡改成功

结论：has_object_permission 是行级关卡；queryset 过滤是集合级关卡。
      只做其中一个，另一个方向就有洞。
```

### 实验 5：顺序的实际意义

```text
【对照组 A】权限放行 -> ⓪ initial 开始 → ① 认证 → ② 权限 → ③ 限流 → ④ 视图方法，最终 200
【对照组 B】权限拒绝 -> ⓪ initial 开始 → ② 权限（拒绝），最终 403
             （本视图 authentication_classes = []，故无 ① 认证层）

权限被拒时，限流是否被调用？否
```

### 实验 6：匿名限流 5 次/分钟

```text
【对照】原端点（受全局 IsAuthenticated 保护）-> 403，限流没机会执行
【实验】探针端点（AllowAny）-> 前 5 次 200，第 6 次 429，Retry-After: 60 秒
```

### 实验 7：用户限流 10 次/分钟，按用户区分

```text
alice 前 12 次：[200×10, 429, 429]  -> 第 11 次开始被限流
bob 此时请求   -> 200, 200          -> 不受 alice 影响
```

### 实验 8：限流依赖缓存后端

```text
限流写入的缓存键：[':1:throttle_user_1']   -> 含 user.pk，证明按用户隔离

模拟两个进程：
  worker1：第 6 次被拒
  worker2：第 6 次被拒
-> 配 5/minute，2 个 worker 实际放行 10 次
```

### 实验 9：scope 限流

```text
【实验 A】未配置 burst rate 时：
  UserRateThrottle   -> 200（静默放行）
  ScopedRateThrottle -> 抛 ImproperlyConfigured

【实验 B】补上 burst=3/minute 后：
  UserRateThrottle   -> [200, 200, 200, 200, 200]  完全没生效
  ScopedRateThrottle -> [200, 200, 200, 429, 429]  第 4 次起被限
```

### 附：实验工程结构

```text
perm_lab/
├── manage.py
├── config/
│   ├── settings.py      # REST_FRAMEWORK 全局配置（IsAuthenticated + 限流）
│   └── urls.py
└── apps/
    ├── users/           # 自定义用户模型
    └── articles/
        ├── models.py    # Article(author, title, status)
        ├── serializers.py
        ├── views.py     # 权限类 + 探针视图
        └── urls.py
```

`views.py` 里的关键组件：

| 组件 | 用途 |
|------|------|
| `OrderView` / `TraceAuth` / `TracePermission` / `TraceThrottle` | 实验 1/5 的顺序探针 |
| `IsAuthorOrReadOnly` | 实验 2 的对象级权限 |
| `ArticleDetailNoGuardView` | 实验 4 的越权反例 |
| `DenyOrderView` / `DenyPermission` | 实验 5 的权限拒绝对照 |
| `ThrottleAnonProbeView` 等 `Probe` 视图 | 实验 6/7/9 的 `AllowAny` 隔离端点 |
| `ThrottleScopedCorrectView` | 实验 9 的正确写法对照 |

---

## 第五幕 · 体系收束

### 本课在全局中的位置

```text
课 8  认证：你是谁        → request.user 有了值
课 9  权限：你能干什么    →  request.user 能碰哪些数据      ← 本课
课 10 安全实践           →  剩下的攻击面（CSRF / token 存放 / 批量分配）
```

阶段 2 搭好了 serializer + ViewSet，课 8 给它加了身份，本课给它加了**边界**。到这一课为止，视图才算真正"瘦且安全"——校验在 serializer，权限在 permission 类，视图只剩编排。

### 你现在会了什么

1. **说清四层顺序**——认证 → 权限 → 限流 → 校验，且权限拒绝时后面不执行
2. **写对象级权限**——`has_object_permission` 守单行，知道它只在详情路由生效
3. **用 queryset 过滤兜底**——列表接口必须自己圈范围，否则漏数据
4. **配限流并知道它的真实配额**——按用户隔离、依赖共享缓存、多进程会翻倍
5. **避开 `throttle_scope` 的静默失效**——必须用 `ScopedRateThrottle`

### 一图总结

```text
请求进来
   │
   ├─① 认证      request.user 是谁？        失败 → 401 / 403
   │
   ├─② 权限      这个操作允许吗？           失败 → 403（后面不执行）
   │   ├─ has_permission        集合级，每次请求都调
   │   └─ has_object_permission 行级，只有详情路由调
   │
   ├─③ 限流      是不是太频繁？             失败 → 429 + Retry-After
   │   └─ 计数存在缓存里，多进程要共享后端
   │
   └─④ 校验      数据对不对？               失败 → 400
```

### 埋下的伏笔

- **限流为什么能防住爆破？** 权限拒绝的请求不计入配额（实验 5），那登录接口的防爆破该怎么做？→ 课 10
- **"越权"只有改 ID 这一种吗？** 还有一个更隐蔽的方向：批量分配（前端多传一个 `is_staff` 字段）→ 课 10
- **限流放在 Django 中间件层行不行？** 中间件在 DRF 之前，顺序完全不同 → 课 18

### 阶段 3 进度

| 课 | 主题 | 状态 |
|----|------|------|
| 课 8 | 认证：你是谁 | ✅ 已完成 |
| 课 9 | 权限：你能干什么 | ✅ 已完成（本课） |
| 课 10 | 分离架构下的安全实践 | ⬜ 未开始 |

---

## 🐞 本课误区速查

| 误区 | 真相 |
|------|------|
| "写了 `IsAuthenticated` 就安全了" | 它只管"登录没登录"。**改个 ID 就能改别人的数据**（实测返回 200 且入库） |
| "对象级权限能挡住列表越权" | `has_object_permission` **列表路由一次都不调**（实测调用记录为空） |
| "权限和限流是平级的" | 权限在前，**权限拒绝时限流根本不执行**（实测对照 B） |
| "限流配 10/minute 就是 10 次" | 多进程下每个 worker 各数各的，实际是 **10 × worker 数**（实测两个进程各放行 5 次） |
| "`throttle_scope` 写了就能改频率" | **只有 `ScopedRateThrottle` 会读它**。`UserRateThrottle` 下写了也白写，不报错（实测全 200） |
| "未配置的 scope 会报错提醒我" | `UserRateThrottle` 静默放行；只有 `ScopedRateThrottle` 才抛 `ImproperlyConfigured` |
| "`override_settings` 能改限流频率" | 无效。`SimpleRateThrottle.THROTTLE_RATES` 是 import 时绑死的类属性（实测） |
| "限流计数存在数据库里" | 存在**缓存**里。用 LocMemCache 就是进程内存，重启即清零 |
| "`UserRateThrottle` 一定按用户计数" | 未认证请求会**回退用 IP** 计数（文档明示） |
| "限流的次数是精确的" | 内置实现**有并发竞态**，高并发下会多放行几个（文档明示） |
| "权限类只能 AND 组合" | 列表形式确实是 AND，但 DRF 内置了 `OR` / `AND` / `NOT` 组合类（`permissions.py:61/79/100`），也支持 `\|` `&` `~` 运算符 |
| "访问别人的资源应该返回 403" | 若 queryset 也做了过滤，返回的是 **404**，从安全角度这更好（不泄漏 ID 是否存在） |

---

## 📚 官方文档

| 主题 | 链接 | 说明 |
|------|------|------|
| DRF · Permissions | https://www.django-rest-framework.org/api-guide/permissions/ | 内置权限类、`has_permission` / `has_object_permission` |
| DRF · Throttling | https://www.django-rest-framework.org/api-guide/throttling/ | 三个内置限流类、缓存后端要求、`throttle_scope` |
| DRF · Settings | https://www.django-rest-framework.org/api-guide/settings/ | `DEFAULT_THROTTLE_RATES` 等配置默认值 |
| Django · Cache | https://docs.djangoproject.com/en/6.1/topics/cache/ | `LocMemCache` 与 Redis / Memcached 后端配置 |

### 「文档明示」与「实测确认」的区分

| 结论 | 来源 |
|------|------|
| 执行顺序为认证 → 权限 → 限流 | ✅ 源码明示（`rest_framework/views.py:404` `initial()` 内 419–421 行） |
| `has_object_permission` 在 `get_object()` 中调用 | ✅ 文档明示 + 源码核实（`generics.py:79` / `:103`） |
| DRF 内置 `AND` / `OR` / `NOT` 组合类 | ✅ 源码核实（`permissions.py:61` / `:79` / `:100`） |
| `AnonRateThrottle` 按 IP、`UserRateThrottle` 按 user pk | ✅ 文档明示 |
| `ScopedRateThrottle` 读取视图的 `throttle_scope` | ✅ 文档明示 |
| 限流需要缓存后端，LocMemCache 不适用多进程 | ✅ 文档明示 |
| 权限类为 AND 语义 | ✅ 文档明示 |
| 429 响应带 `Retry-After` 头 | ✅ 文档明示 |
| `UserRateThrottle` 对未认证请求回退用 IP 计数 | ✅ 文档明示 |
| 内置限流存在并发竞态，高并发下可能多放行 | ✅ 文档明示（"open to race conditions"） |
| `ScopedRateThrottle` 只在视图有 `throttle_scope` 时生效 | ✅ 文档明示 + 源码核实（`throttling.py:221`） |
| **权限拒绝时限流不执行** | 🔬 **实测确认**（对照 A/B，文档未直接说明） |
| **`has_object_permission` 在列表路由完全不调用** | 🔬 **实测确认**（mock 记录为空，文档未强调） |
| **多进程下配额 = 配置值 × worker 数** | 🔬 实测确认（两个 LocMemCache 实例各放行 5 次） |
| **`UserRateThrottle` + `throttle_scope` 静默失效** | 🔬 **实测确认**（文档未警告，高危） |
| **未配 scope 时两种限流类行为相反** | 🔬 实测确认（一静默一抛异常） |
| **`override_settings` 改不了 `THROTTLE_RATES`** | 🔬 实测确认（类属性 import 时绑定） |
| 限流缓存键形如 `throttle_user_<pk>` | 🔬 实测确认 |
| 配 `5/minute` 时第 6 次才被拒（放行 5 次） | 🔬 实测确认 |

---

## 🚀 下一批接力提示词

**继续下一课**：

```text
继续学 Django 进阶（前后端分离）。我的学习档案在 django/00-学习档案.md，
刚学完阶段 3《认证权限与鉴权》的课 9《权限：你能干什么》
（知识点：权限四层与执行顺序、自定义对象级权限、限流 Throttling），
请按大纲继续讲解课 10《分离架构下的安全实践》。
```

**如果想先巩固本课**：

```text
我在做一个 Django + DRF 的前后端分离项目，已经配好 JWT 认证。
请帮我审查下面这份权限与限流配置，重点看四个问题：
1. 列表接口有没有水平越权风险（对象级权限管不到列表）
2. 限流在多进程部署下的真实配额是多少
3. 我用了 throttle_scope，限流类选对了吗
4. 有没有比 403 更合适的返回（比如 404）
（贴出你的 permission_classes 与 REST_FRAMEWORK 配置）
```

---

## 🧭 课程导航

**上一课**：[阶段 3 · 课 8《认证：你是谁》](./lesson-08-认证你是谁.md)
**下一课**：[阶段 3 · 课 10《分离架构下的安全实践》](./lesson-10-分离架构下的安全实践.md)
**阶段概览**：[阶段 3：认证、权限与鉴权](../overview.md)
**返回**：[阶段 3 概览](../overview.md) ｜ [课程目录](../../../02-课程目录.md)

---

> **本课一句话**：认证只回答"你是谁"，权限才回答"你能碰什么"。而"能碰什么"有**两个方向**——单行改动靠 `has_object_permission`，批量可见靠 queryset 过滤；**只守一个方向，另一个方向就是敞开的**。限流同理：你配的数字从来不是真实配额，它还要乘以进程数，并且在 scope 写错时静默归零。
