# 课 5：错误处理与健壮性

> 目标：把"能跑"的程序，变成"半夜不会挂"的程序。
> 前 4 课的代码有个共同假设——**每个请求都会成功**。这在 demo 里成立，在生产里不成立。
> 这一课专门处理"它会失败，以及失败时你怎么知道该干什么"。

**本课环境**：kubernetes **34.1.0** / Python **3.12.3** / kind 集群 **v1.34.0**（`kind-k8s-c1`）
**本课所有结论均在本机实测，凡未实测处均已显式标注。**

---

## 引子：一段能跑但会挂的代码

```python
cm = v1.read_namespaced_config_map(name="app-config", namespace="prod")
cm.data["version"] = "v2"
v1.replace_namespaced_config_map(name="app-config", namespace="prod", body=cm)
```

三行，逻辑正确，测试通过。上线后有一天报了个错：

```
(409) Reason: Conflict
```

你加了个 `try/except` 重试三次。**还是 409，三次都是。**

为什么？因为**这个错误靠重试解决不了**——本课会让你亲眼看到"重试三次全是 409"，并给出唯一正确的解法。

### 一眼全局

![课5全局图](../assets/lesson05-intuition.svg)

---

## 第一幕：ApiException 到底装了什么

### 1.1 三个属性，一个都别记错

实测一个 404：

```
e.status : 404   <- HTTP 状态码 int
e.reason : Not Found  <- HTTP 状态短语 str
e.body   : str  <- JSON 字符串，不是 dict
```

> ⚠️ **`e.body` 是 `str` 不是 `dict`。** 这是本课第一个坑。
> 很多教程直接写 `e.body["reason"]`，会报 `TypeError: string indices must be integers`。
> 必须先 `json.loads(e.body)`。

### 1.2 body 里就是 V1Status

把 body 解析开看结构（实测）：

```python
body 顶层键 : ['kind', 'apiVersion', 'metadata', 'status', 'message', 'reason', 'details', 'code']
kind        : Status
status      : Failure
reason      : NotFound
code        : 404
message     : configmaps "no-such-cm" not found
details     : {'name': 'no-such-cm', 'kind': 'configmaps'}
```

这就是 `V1Status` 模型。它的字段对照：

| V1Status 字段 | 实测值 | 含义 |
|---|---|---|
| `kind` | `Status` | 固定 |
| `status` | `Failure` / `Success` | 成功还是失败 |
| `message` | `configmaps "x" not found` | **给人看的完整描述** |
| `reason` | `NotFound` | **给程序看的语义码** |
| `details` | `{name, kind, causes}` | 出错对象与具体原因 |
| `code` | `404` | HTTP 状态码（与 `e.status` 相同） |

### 1.3 ⚠️ 两个 reason，别混淆

这是极易踩的坑：

```
e.reason（HTTP 短语）       = Not Found      <- 带空格
body.reason（K8s 语义原因）=  NotFound       <- 驼峰，无空格
```

**判断错误类型请用 `body.reason`**（或 `e.status`）。`e.reason` 是 HTTP 层的措辞，不适合做分支判断。

### 1.4 怎么把 body 变成对象

⚠️ **实测踩坑**：网上常见的写法是错的。

```python
# ❌ 错：deserialize 不接受字符串
api.deserialize(e.body, "V1Status")
# AttributeError: 'str' object has no attribute 'data'
```

看源码就明白了：

```python
def deserialize(self, response, response_type):
    ...
    try:
        data = json.loads(response.data)      # ← 它要的是 response 对象
    except ValueError:
        data = response.data
    return self.__deserialize(data, response_type)
```

**它调 `response.data`，字符串没有这个属性。**

✅ **两个正确姿势**：

```python
# 姿势1：走私有方法（要 V1Status 对象时用）
d = json.loads(e.body) if isinstance(e.body, str) else e.body
st = api._ApiClient__deserialize(d, client.models.V1Status)

# 姿势2：直接 json.loads（大多数时候够用，推荐）
d = json.loads(e.body)
print(d["reason"], d["details"]["kind"])
```

实测姿势1结果：

```
__deserialize -> V1Status | status: Failure | reason: NotFound | code: 404
```

> **一句话记住**：**90% 的场景用 `json.loads(e.body)` 就够了**。非要对象再走私有方法，别用 `deserialize()`。

---

## 第二幕：404 / 409 / 422 各自怎么办

### 2.1 实测五种错误的完整结构

我在专用 ns `py-lesson05-cm` 里逐个触发，结果如下：

| 触发方式 | status | body.reason | 典型含义 |
|---|---|---|---|
| 读不存在的 ConfigMap | **404** | `NotFound` | 对象不存在 |
| create 已存在的 Namespace | **409** | `AlreadyExists` | 名字被占了 |
| replace 时 resourceVersion 过期 | **409** | `Conflict` | 别人先改了 |
| create 名字非法的对象 | **422** | `Invalid` | 字段不合法 |
| 在不存在的 ns 下 create | **404** | `NotFound` | **ns 不存在也是 404** |

> ⚠️ 注意最后一行：我本以为会是 400，**实测是 404**。
> 因为服务端报的是"namespace 不存在"，而不是"你的请求格式错了"。

### 2.2 422 是唯一带 causes 的

422 的 `details` 里多了 `causes` 数组（实测）：

```
code   : 422
reason : Invalid
details: Bad Name!! / ConfigMap
causes : 数量 1
    - field  : metadata.name
      reason : FieldValueInvalid
      message: Invalid value: "Bad Name!!": a lowercase RFC 1123 subdomain must consist of...
```

**`causes[].field` 直接指出哪个字段错了**——这是排障时最有价值的信息，其他错误码都没有。

> **排障价值**：422 是**你的请求本身有问题**，重试毫无意义。
> 应该读 `causes` 修数据，而不是重试。

### 2.3 三种处置策略对照

| 错误 | 该不该重试 | 正确处置 |
|---|---|---|
| **404 NotFound** | ❌ | 对象不存在。要就先 create（get-or-create），不要就当作正常情况处理 |
| **409 AlreadyExists** | ❌ | **读回已有的**再用（幂等设计，见第四幕） |
| **409 Conflict** | ⚠️ 特殊 | **重读 → 重放修改 → 再写**（不是重试原请求！见第三幕） |
| **422 Invalid** | ❌ | 改数据。读 `causes[].field` |
| **5xx / 网络错** | ✅ | 退避重试（见第五幕） |

---

## 第三幕：409 Conflict —— 本课核心

### 3.1 它是怎么产生的

Kubernetes 用 **乐观锁**：每个对象带 `resourceVersion`，你改的时候要带着读到的版本回去，服务端发现对不上就拒绝。

实测两个人同时改同一个 ConfigMap：

```
两人各读一次，resourceVersion: 2679978 2679978
A 先改成功 -> v = {'v': 'A'} | 新 resourceVersion = 2679979
B 改 -> ApiException 409 Conflict
  message: Operation cannot be fulfilled on configmaps "conflict-demo":
           the object has been modified; please apply your changes to the
           latest version and try again
  details: {'name': 'conflict-demo', 'kind': 'configmaps'}

  >>> 关键：B 用的是过期的 resourceVersion 2679978，服务端现在是 2679979
```

**服务端把话说明白了**：`please apply your changes to the latest version and try again`。

注意它说的是 **apply your changes to the latest version**（把你的改动应用到最新版本上），**不是** `try the same request again`（把同一个请求再发一次）。

**这两个是天差地别的两件事。**

### 3.2 ❌ 错误做法：直接重试原请求

实测——带上过期的 rv 重试三次：

```
先改成功一次，stale 对象的 rv 现在是: 2679980
  重试1 -> 409 Conflict（原请求带着过期 rv，重试多少次都一样）
  重试2 -> 409 Conflict（原请求带着过期 rv，重试多少次都一样）
  重试3 -> 409 Conflict（原请求带着过期 rv，重试多少次都一样）
```

**三次全是 409。** 因为请求里那个 `resourceVersion` 是死的，服务端每次都比对它，每次都对不上。

> **这就是引子里那段代码的死因。** 加了重试只是让程序多失败两次，然后以同样的错误告终。

### 3.3 ✅ 正确做法：重读 → 重放修改 → 再写

关键区别在于：**每次循环都要重新读，并对新读到的对象重新施加"修改意图"**。

```python
def replace_with_conflict_retry(read_fn, write_fn, mutate_fn, tries=4):
    """409 专用：重读 -> 重放修改 -> 再写"""
    for i in range(1, tries + 1):
        obj = read_fn()          # ← 每次都重新读！
        mutate_fn(obj)           # ← 对新对象重新施加改动
        try:
            return write_fn(obj), i
        except ApiException as e:
            if e.status != 409:
                raise            # 非 409 不吞
            time.sleep(0.1 * i)  # 退避
    raise RuntimeError("重试耗尽")
```

实测效果：

```
第 1 次尝试 -> 成功, v = {'v': 'B'}, rv = 2679980
```

> **一句话记住**：**409 要重读，不是重试。**
> 重试 = 把同一个过期请求再发一遍（永远失败）
> 重读 = 拿最新版本，重新表达"我要改成什么"（会成功）

### 3.4 ⚠️ 重读也救不了的情况（必须知道）

我构造了一个"每次读之后服务端都会变"的场景，实测：

```
stale rv: 2680529
    第 1 次 -> 409，重读再写
    第 2 次 -> 409，重读再写
    第 3 次 -> 409，重读再写
  -> 重试耗尽
```

**重读重试不是万能的。** 如果冲突源持续存在（比如有个控制器在高频改这个对象），重试多少次都是徒劳。

> **工程纪律**：409 重试必须**设上限**，且**耗尽后要报错而不是静默吞掉**。
> 静默吞掉 = 你的修改根本没生效，但程序显示成功——这比崩溃危险得多。

---

## 第四幕：幂等设计

### 4.1 实测四种写法的幂等性

对同一个对象连续执行两次相同内容（实测）：

```
create 第1次              -> OK   rv=2680533
create 第2次（同内容）      -> 409 AlreadyExists
replace 第1次             -> OK   rv=2680533
replace 第2次（同对象）     -> OK   rv=2680533
patch 第1次               -> OK   rv=2680533
patch 第2次（同内容）       -> OK   rv=2680533
```

**两个结论**：

1. **`create` 不幂等**——第二次直接 409
2. **`replace` / `patch` 幂等**——第二次成功，且 **`resourceVersion` 没变**（还是 2680533）

> 第 2 点的 rv 不变很关键：说明**服务端识别出内容没变，没有产生新版本**。
> 这意味着重复执行 patch 不会引发无谓的 watch 事件，对写控制器很重要。

### 4.2 get-or-create：把不幂等的 create 变幂等

```python
def get_or_create_cm(name, data):
    try:
        return v1.create_namespaced_config_map(
            namespace=NS,
            body=client.V1ConfigMap(metadata=client.V1ObjectMeta(name=name), data=data)
        ), "created"
    except client.exceptions.ApiException as e:
        if e.status == 409:
            return v1.read_namespaced_config_map(name=name, namespace=NS), "existed"
        raise          # ← 非 409 一定要继续抛，别吞
```

实测：

```
第一次: created | 第二次: existed （不报错，直接读回已有的）
```

> ⚠️ **`raise` 那行不能省。** 如果只 catch 409 却不处理其他错误，网络故障会被伪装成"对象已存在"。

### 4.3 什么时候该用哪个

| 场景 | 推荐 | 理由 |
|---|---|---|
| 我要这个对象存在，内容由我定 | `patch`（或 apply） | 幂等，不存在时需先 create |
| 我确定它不存在，要新建 | `create` + 409 处理 | 明确语义 |
| 我要完整替换 | `replace` | 但注意课 3 讲的"静默删字段" |
| 只改一个字段 | `patch` | 最安全，不碰其他字段 |

---

## 第五幕：超时与重试

（课 4 已讲透机理，这里补齐错误处理视角。）

### 5.1 总耗时 = 超时 × (重试 + 1)

实测（不可达地址，固定 `_request_timeout=2`）：

```
retries=0 -> MaxRetryError  耗时 2.02s
retries=1 -> MaxRetryError  耗时 4.05s
retries=2 -> MaxRetryError  耗时 6.08s
```

**你设了 2 秒超时，实际可能卡 6 秒。**

### 5.2 `_request_timeout` 支持 tuple

实测传 `(1, 2)`（连接 1s / 读取 2s）：

```
tuple 形态 -> MaxRetryError 耗时 1.03s
```

**1.03s ≈ 连接超时 1s**，证明是 `(connect, read)` 语义生效。这在"连得上但读得慢"的场景很有用。

### 5.3 哪些错该重试

```python
def is_retryable(e):
    if isinstance(e, ApiException):
        return e.status in (429, 500, 502, 503, 504)   # 429 = 限流
    return False   # 网络错另算
```

> **429 TooManyRequests** 别漏了——apiserver 限流时返回它，必须退避重试。
> ⚠️ **本机未实测 429**（测试集群未触发限流），按官方语义列出。

### 5.4 退避重试封装

```python
def with_retry(fn, tries=3, base=0.2):
    for i in range(1, tries + 1):
        try:
            return fn()
        except Exception as e:
            if not is_retryable(e) or i == tries:
                raise
            time.sleep(base * (2 ** (i - 1)))     # 指数退避
```

> **一定要指数退避**。固定间隔重试会让所有客户端在同一时刻重试，制造"惊群"，把刚恢复的 apiserver 再打挂。

---

## 第六幕：调试日志——以及一个高危警告

### 6.1 怎么看真实 HTTP 报文

```python
import logging
cfg = client.Configuration.get_default_copy()
cfg.debug = True
logging.basicConfig(level=logging.DEBUG)
client.CoreV1Api(client.ApiClient(cfg)).list_namespace(limit=1)
```

实测输出：

```
send: b'GET /api/v1/namespaces?limit=1 HTTP/1.1\r\n
       Host: 127.0.0.1:37331\r\n
       Accept-Encoding: identity\r\n
       Accept: application/json\r\n
       User-Agent: OpenAPI-Generator/34.1.0/python\r\n
       Content-Type: application/json\r\n\r\n'
reply: 'HTTP/1.1 200 OK\r\n'
header: Audit-Id: 32e30f5e-...
header: Content-Type: application/json
```

**`send:` 是完整请求，`reply:` 是状态行，`header:` 逐行给出响应头。**

这个能力在"我的请求到底发出去没有""header 对不对"这类排障中无可替代——课 3 讲 `content_type=` 报 `ApiTypeError` 时，就是靠它确认头没设上。

### 6.2 🚨 高危：debug 日志会明文打印 token

我用伪造 token 实测（本机 kubeconfig 用证书，所以必须另造场景）：

```
send: b'GET /api/v1/namespaces?limit=1 HTTP/1.1\r\n
       Host: 127.0.0.1:37331\r\n
       ...
       authorization: Bearer FAKE-TOKEN-DO-NOT-REAL-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\r\n
       Content-Type: application/json\r\n\r\n'
```

**Bearer token 明文出现在日志里。**

> ⚠️ **生产纪律**：
> - **生产环境开 `debug=True` = 把 ServiceAccount token 写进日志**
> - 日志会被采集、落盘、转发，token 一旦泄露等同于集群权限泄露
> - 只在**排障窗口**临时开启，排完立即关掉
> - 如果日志要留存，**必须确认脱敏规则能过滤 `authorization:` 行**

**为什么本机默认看不到？** 因为本机 kubeconfig 用的是**客户端证书**（在 TLS 层认证），HTTP 头里没有 `Authorization`。只有用 token 认证（in-cluster、或手工设 `api_key`）时才会出现。

> ⚠️ **诚实标注**：本机 kubeconfig 走客户端证书，未直接产生 Bearer 场景。
> 上述证据来自**显式设置 `api_key` 的真跑实测**（伪造 token 值），结论可靠；
> in-cluster 下同样走 `api_key`，机制一致。

---

## 第七幕：动态客户端的错误不一样

### 7.1 ⚠️ 异常类型与 body 类型都不同

同样是 404，两种客户端的对比（实测）：

```
typed client   -> ApiException      404 Not Found | e.body 类型: str
dynamic client -> NotFoundError     404 Not Found | e.body 类型: bytes
```

**两个差异**：

1. **异常类型**：dynamic 抛 `NotFoundError`（`ApiException` 的子类）
2. **`e.body` 类型**：typed 是 `str`，**dynamic 是 `bytes`**

> ⚠️ 这意味着你写的 `json.loads(e.body)` 在两种客户端下都能跑（`json.loads` 接受 bytes），
> 但如果你写了 `e.body.startswith(...)` 或字符串拼接，在 dynamic 下会 `TypeError`。

**稳的写法**：

```python
b = e.body
if isinstance(b, bytes):
    b = b.decode()
d = json.loads(b)
```

### 7.2 好消息：`except ApiException` 两边都抓得住

`NotFoundError` 是 `ApiException` 的子类，所以 `except ApiException` 能同时覆盖两种客户端。

**但判断错误码时请用 `e.status`**，不要用异常类名——dynamic 有一堆子类（`NotFoundError`/`ConflictError`/...），枚举不完。

### 7.3 dynamic 也支持 `_request_timeout`

实测：

```
dynamic get _request_timeout=10 -> 成功, 3 条, 耗时 0.002s
```

---

## 收束：三张地图

### 地图一：错误码 → 处置速查

| status | body.reason | 重试？ | 处置 |
|---|---|---|---|
| 400 | `BadRequest` | ❌ | 请求格式错，改代码 |
| 401 | `Unauthorized` | ❌ | 凭据无效/过期（课 4） |
| 403 | `Forbidden` | ❌ | **没权限**，查 RBAC（课 4） |
| 404 | `NotFound` | ❌ | get-or-create，或当作正常 |
| 409 | `AlreadyExists` | ❌ | 读回已有的 |
| 409 | `Conflict` | ⚠️ | **重读→重放→再写**，有上限 |
| 422 | `Invalid` | ❌ | 读 `causes[].field` 改数据 |
| 429 | `TooManyRequests` | ✅ | 指数退避（⚠️ 本机未实测） |
| 5xx | - | ✅ | 指数退避 |
| 网络错 | - | ✅ | 退避；看 `Caused by`（课 4） |

### 地图二：写代码的检查清单

写完一段调集群的代码，逐条自查：

1. `except` 有没有**区分错误码**？还是一把 `except Exception` 全吞？
2. 处理 409 时，是**重读**还是**重试**？（本课核心）
3. 重试有没有**上限**？耗尽后是**报错**还是静默？
4. 重试有没有**指数退避**？
5. `create` 的地方有没有考虑**已存在**的情况？
6. 生产环境 `debug` 是不是关着的？
7. 有没有用 `e.status` 判断，而不是靠异常类名？

### 地图三：本课五个必须记住的结论

1. **`e.body` 是 `str`（typed）或 `bytes`（dynamic）**，不是 dict——先 `json.loads`
2. **`e.reason` ≠ `body.reason`**——判断用后者（或 `e.status`）
3. **409 Conflict 要重读，不是重试**——重试原请求永远失败
4. **`create` 不幂等，`replace`/`patch` 幂等**——且幂等时 rv 不变
5. **生产开 debug = token 进日志**——排障窗口才开，排完必关

---

## 本课实测环境说明

- 测试命名空间 `py-lesson05-cm` 内的对象为**临时创建**（ConfigMap 若干）
- ⚠️ **清理待办**：`py-lesson05-cm` 尚未删除（本课结束时会处理）
- 所有触发的错误均为**预期内**操作，未影响集群其他资源

---

## 延伸阅读

- [Kubernetes API 约定：错误响应](https://kubernetes.io/docs/reference/using-api/api-concepts/#success-and-failure-codes)
- [官方 Python 客户端：异常处理示例](https://github.com/kubernetes-client/python/blob/master/examples/apply_from_dict.py)
- [调试日志（devel）](https://github.com/kubernetes-client/python/blob/master/devel/debug_logging.md)
- [Kubernetes 并发控制与一致性（乐观并发）](https://kubernetes.io/docs/reference/using-api/api-concepts/#concurrency-control-and-consistency)
- [API 限流与 429](https://kubernetes.io/docs/concepts/cluster-administration/flow-control/)

---

## 课程导航

- **上一课**：[课 4：认证 · 多集群 · 配置](lesson-04-认证与多集群.md)
- **下一课**：课 6：watch · informer · 调谐循环（本课的错误处理是 watch 循环的基础）
- **返回**：[子教程 overview](../overview.md) ｜ [课程目录](../../../02-课程目录.md)

---

## 小测

1. `e.body` 是什么类型？想取 `reason` 该怎么取？
2. `e.reason` 和 `body.reason` 有什么区别？判断错误类型该用哪个？
3. 409 Conflict 时，直接重试原请求会怎样？正确做法是什么？
4. 422 与其他错误码相比，多了什么关键信息？该重试吗？
5. `create` / `replace` / `patch` 中哪个不幂等？如何让它变幂等？
6. patch 同样内容两次，`resourceVersion` 会变吗？这说明什么？
7. 生产环境开 `debug=True` 有什么风险？
8. dynamic client 与 typed client 抛的异常，`e.body` 类型一样吗？

<details>
<summary>答案</summary>

1. typed client 是 **str**，dynamic client 是 **bytes**（都不是 dict）。取 reason：`json.loads(e.body)["reason"]`，bytes 时先 `.decode()`。不要写 `e.body["reason"]`。
2. `e.reason` 是 HTTP 状态短语（如 `Not Found`，带空格），`body.reason` 是 K8s 语义码（如 `NotFound`，驼峰）。**判断用 `body.reason` 或 `e.status`**。
3. **重试多少次都是 409**（实测三次全失败），因为请求里的 `resourceVersion` 是死的。正确做法：**重读最新对象 → 对新对象重新施加修改 → 再写**。
4. 多了 `details.causes[]`，其中 `field` 直接指出出错字段（实测 `metadata.name`）。**不该重试**，要改数据。
5. **`create` 不幂等**（第二次 409 AlreadyExists）。用 **get-or-create**：409 时读回已有的。注意非 409 必须 `raise`。
6. **不变**（实测两次都是 2680533）。说明服务端识别出内容未变、未产生新版本，不会触发无谓的 watch 事件。
7. **Bearer token 会明文出现在日志里**（实测 `authorization: Bearer ...`）。生产开 debug = 凭据泄露，只在排障窗口临时开启，且确认脱敏规则能过滤。
8. **不一样**。typed 是 `str`，dynamic 是 `bytes`；异常类型也不同（`ApiException` vs `NotFoundError`）。但 `NotFoundError` 是 `ApiException` 子类，`except ApiException` 两边都能抓。

</details>

---

## 接力提示词

```
继续学 Kubernetes Python 客户端专项，我的学习档案在 k8s/子教程/Python客户端专项/overview.md，
刚学完课 5《错误处理与健壮性》（知识点：ApiException 三属性与 e.body 是 str/bytes 而非 dict、
V1Status 八字段与两个 reason 的区别、404/409/422 处置分野、409 Conflict 要重读再写而非重试原请求、
create 不幂等而 replace/patch 幂等且 rv 不变、指数退避、debug 日志会明文泄露 Bearer token、
dynamic client 抛 NotFoundError 且 body 为 bytes），
请按大纲继续讲解课 6《watch · informer · 调谐循环》。
```
