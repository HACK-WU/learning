# 课 6：watch · informer · 调谐循环

> 目标：让程序从"我查一次"变成"它一直在看"。
> 前 5 课的所有调用都是**一次性**的——你问、它答、结束。
> 但控制器、Operator、dashboard 需要的是**持续感知变化**。这一课讲这个。

**本课环境**：kubernetes **34.1.0** / Python **3.12.3** / kind 集群 **v1.34.0**（`kind-k8s-c1`）
**本课所有结论均在本机实测，凡未实测处均已显式标注。**

---

## 引子：为什么轮询是错的

要"知道 ConfigMap 什么时候变了"，最朴素的写法：

```python
while True:
    cms = v1.list_namespaced_config_map(namespace="prod")
    检查有没有变
    time.sleep(5)
```

三个问题：

1. **延迟**：最快 5 秒才发现
2. **浪费**：没变化也在全量查，每次都传整个列表
3. **打爆 apiserver**：100 个控制器 × 每 5 秒一次 = 每秒 20 次全量 list

Kubernetes 的答案是 **watch**：一次连接，服务端**主动推**变化给你。

### 一眼全局

![课6全局图](../assets/lesson06-intuition.svg)

---

## 第一幕：第一次 watch

### 1.1 最基础的形态

```python
from kubernetes import watch
w = watch.Watch()
for event in w.stream(v1.list_namespaced_config_map, namespace="py-lesson06"):
    print(event["type"], event["object"].metadata.name)
```

**注意它复用了 `list_*` 方法**——不是 `watch_*`。库内部会自动把 `watch=True` 塞进参数。

看源码就很清楚：

```python
return_type = self.get_return_type(func)
watch_arg = self.get_watch_argument_name(func)   # 找到 'watch' 这个参数名
kwargs[watch_arg] = True                          # ← 自动置 True
kwargs['_preload_content'] = False                # ← 必须流式，不能预加载
```

### 1.2 实测：边改边看

我在一个线程里跑 watch，主线程制造变更：

```
type=ADDED     name=kube-root-ca.crt  rv=2692712
type=ADDED     name=watched-cm        rv=2692715
type=MODIFIED  name=watched-cm        rv=2692718
type=DELETED   name=watched-cm        rv=2692719
```

三种事件类型全部拿到。**注意 `kube-root-ca.crt` 那个 ADDED**——它是 namespace 自带的，说明 **watch 会先把"当前已存在的对象"以 ADDED 形式推一遍**。

### 1.3 event 字典只有三个键

实测：

```
type         -> str
object       -> V1ConfigMap     <- 已反序列化成模型
raw_object   -> dict            <- 原始 JSON
```

> `object` 和 `raw_object` **内容相同、类型不同**。
> 处理业务用 `object`（有属性补全和类型）；要原样转发/存 JSON 用 `raw_object`（省一次反序列化）。

### 1.4 四种事件类型

| 类型 | 触发时机 | 缓存该怎么做 |
|---|---|---|
| `ADDED` | 对象出现（含 watch 启动时已存在的） | 加入缓存 |
| `MODIFIED` | 对象变更 | 覆盖缓存 |
| `DELETED` | 对象删除 | 从缓存移除 |
| `BOOKMARK` | 服务端定期推的"进度标记" | **只更新 rv，不动缓存** |

**BOOKMARK 实测拿到了**：

```
事件类型统计: {'ADDED': 1, 'BOOKMARK': 1}
```

⚠️ **BOOKMARK 必须显式开启**：

```python
w.stream(..., allow_watch_bookmarks=True)
```

> ⚠️ **BOOKMARK 最容易写错的地方**：把它当业务对象塞进缓存。
> 它没有实际数据，只有 `resourceVersion`。正确处理是**只更新 rv**。

---

## 第二幕：resource_version 与 410 Gone

### 2.1 rv 是 watch 的"续播书签"

每次事件都带 `resource_version`，你把它记下来，断线后从这儿续。

**实测一个关键语义**——`resource_version="0"`：

```
rv=0 -> 收到 1 个事件（0 表示"给我当前全量快照"）
```

> `rv=0` 不是"从最早开始"，而是 **"我不要历史，把当前状态给我一份"**。
> 这是 list-watch 两段式的起点语义。

### 2.2 410 的真身：流内嵌的 ERROR 事件

我用 RAW 请求探服务端对各类 rv 的响应（实测）：

| rv | 结果 |
|---|---|
| 不传（当前） | `OK len=1936` |
| `0` | `OK len=1936`（当前快照） |
| `1`（极旧） | `OK len=175` ← **里面是错误** |
| `999999999999`（未来） | `OK len=0` ← 挂起等待 |
| `abc`（非法） | `500 Internal Server Error` |

**注意 `rv=1` 那一行**：HTTP 状态码是 **200 OK**，但内容只有 175 字节。打开看：

```json
{"type":"ERROR","object":{"kind":"Status","apiVersion":"v1","metadata":{},
 "status":"Failure","message":"too old resource version: 1 (2692711)",
 "reason":"Expired","code":410}}
```

> ⚠️ **410 不是通过 HTTP 状态码返回的，而是流里嵌的一个 `type: ERROR` 事件。**
> 这是它和课 5 所有错误都不一样的地方。

### 2.3 库帮你把它转成异常

`stream()` 会识别这个 ERROR 事件并抛出：

```python
except ApiException as e:
    print(e.status, e.reason)
# 410 Expired: too old resource version: 1 (2692711)
```

⚠️ **但 `e.body` 是 `None`！**

课 5 说 `e.body` 是 JSON 字符串，这里失效了——因为 410 **不是** HTTP 响应体，是库从流里解析出来后手工构造的异常：

```python
raise client.rest.ApiException(status=obj['code'], reason="%s: %s" % (obj['reason'], obj['message']))
```

> **记住**：**处理 410 时不要去解析 `e.body`，它是 `None`。** 用 `e.status` 判断就够了。
> 这是课 5 知识的一个例外，值得单独记。

### 2.4 410 的唯一正确处置：回退全量 list

410 的含义是：**你那个 rv 太老了，etcd 已经 compact 掉了，我无法从那儿续**。

这时候**没得续，只能重新全量同步**：

```python
rv = None
while True:
    try:
        for event in w.stream(..., resource_version=rv, timeout_seconds=...):
            rv = event["object"].metadata.resource_version
    except ApiException as e:
        if e.status == 410:
            # 回退：全量 list 拿新 rv
            rv = v1.list_namespaced_config_map(namespace=ns).metadata.resource_version
            continue
        raise
```

**这就是官方 `watch_recovery.py` 的模式。**

### 2.5 库其实会替你自动重试一次

看源码：

```python
disable_retries = ('timeout_seconds' in kwargs)
retry_after_410 = False
...
if not disable_retries and not retry_after_410 and obj['code'] == HTTP_STATUS_GONE:
    retry_after_410 = True
    break          # 用 self.resource_version 重来一次
```

⚠️ **两个信息**：

1. 库**只自动重试一次**（`retry_after_410` 标志位用完就不再试）
2. ⚠️ **传了 `timeout_seconds` 就完全禁用自动重试**（`disable_retries = True`）

第 2 点很反直觉：你传 `timeout_seconds` 本意是"别卡太久"，**副作用是关掉了 410 自动恢复**。

我实测对照（都用 `rv=1` 触发 410）：

```
不传 timeout_seconds  -> ApiException 410 Expired
传 timeout_seconds=2  -> ApiException 410 Expired
```

两者都抛了——因为库重试后仍失败（rv=1 永远过期）。但**机制上的差异是真实存在的**：不传时库会静默重试一次，传了就直接抛。

> ⚠️ **诚实标注**：本机 kind 集群 **etcd compaction 默认 5 分钟窗口**，我制造了 150 次变更仍挤不出真实 410 场景。
> 上述 410 证据来自**显式传 `rv=1`** 触发（真实服务端响应），以及**注入假异常**验证恢复分支可执行。
> 恢复逻辑的正确性已验证，但"生产环境 etcd compact 后的自然 410"未在本机观测到。

---

## 第三幕：两种超时——本课最容易死人的地方

### 3.1 它们是两回事

| | `timeout_seconds` | `_request_timeout` |
|---|---|---|
| **谁管** | 服务端（apiserver） | 客户端（urllib3） |
| **写在** | URL 查询参数 | 客户端请求参数 |
| **含义** | "这个 watch 最多保持 N 秒" | "这个 HTTP 请求最多等 N 秒" |
| **到期行为** | **正常返回**（可续接） | **抛异常**（连接被掐断） |

### 3.2 实测：timeout_seconds 精确生效

```
timeout_seconds=1 -> 耗时 1.01s，收到 1 个事件（到期自动返回）
timeout_seconds=3 -> 耗时 3.00s，收到 1 个事件（到期自动返回）
```

**到期是"正常退休"，不是报错。** 所以外层套 `while` 就能持续 watch。

### 3.3 实测：两者冲突时客户端赢

```
timeout_seconds=10 + _request_timeout=2 -> ReadTimeoutError 耗时 2.00s
```

服务端说"我可以保持 10 秒"，客户端 2 秒就把连接掐了。

> ⚠️ **所以 `_request_timeout` 必须 > `timeout_seconds`**，否则每次都等不到服务端正常返回。

### 3.4 🚨 不设超时的后果：永久挂起

我实测——两个都不传，4 秒后检查：

```
4 秒后仍在挂起: True
```

源码说明为什么：

```python
resp = func(*args, **kwargs)          # 阻塞等响应
for line in iter_resp_lines(resp):    # 阻塞逐行读
```

**两处都没有默认超时。** 如果 TCP 连接没断、但服务端不推数据（网络分区、负载均衡器静默丢连接），`iter_resp_lines` 会**永远阻塞**。

> **这是 watch 最常见的生产事故**：程序看起来"活着"，其实卡死在一个永远不返回的读操作上，既不报错也不退出。
>
> ⚠️ **诚实标注**：本机无法安全模拟"TCP 连接建立后静默无数据"（需要 iptables 或代理）。
> 上述"4 秒后仍在挂起"证明的是**不设超时它不会自己回来**；
> "永久挂起"是源码机制推断（`iter_resp_lines` 无超时）+ 业界通识，本机未实测到无限期情形。

### 3.5 ✅ 正确姿势

```python
w.stream(
    v1.list_namespaced_config_map,
    namespace=ns,
    resource_version=rv,
    timeout_seconds=120,      # 服务端 2 分钟退休一次
    _request_timeout=180,     # 客户端 3 分钟兜底（必须 > 上面）
)
```

**`timeout_seconds` 管正常退休，`_request_timeout` 管异常兜底。两个都要，且后者更大。**

---

## 第四幕：informer —— 本地缓存

### 4.1 为什么不直接处理事件

事件流只告诉你"变了什么"，但你的业务逻辑通常需要"**现在全量是什么**"。

而且每次都 `read` 一遍太慢。**informer 的做法**：把事件累积成本地缓存，业务读缓存。

### 4.2 最小可用实现（实测跑通）

```python
class SimpleInformer:
    def __init__(self, list_fn, ns):
        self.list_fn, self.ns = list_fn, ns
        self.cache = {}          # name -> object
        self.rv = None

    def _full_list(self):
        """全量 list：重建缓存 + 拿新 rv"""
        r = self.list_fn(namespace=self.ns)
        self.cache.clear()
        for o in r.items:
            self.cache[o.metadata.name] = o
        self.rv = r.metadata.resource_version

    def sync(self, duration):
        self._full_list()                      # ① 先 list
        w = watch.Watch()
        while time.time() < deadline:          # ② 再 watch
            try:
                for e in w.stream(self.list_fn, namespace=self.ns,
                                  resource_version=self.rv,
                                  timeout_seconds=2, _request_timeout=5):
                    self._handle(e)
            except ApiException as ex:
                if ex.status == 410:
                    self._full_list()          # ③ 410 回退全量
                    continue
                raise

    def _handle(self, e):
        et, o = e['type'], e['object']
        self.rv = o.metadata.resource_version   # ← 关键：每次推进 rv
        if et in ('ADDED', 'MODIFIED', 'BOOKMARK'):
            self.cache[o.metadata.name] = o
        elif et == 'DELETED':
            self.cache.pop(o.metadata.name, None)
```

### 4.3 实测结果

```
[list] 全量同步 1 个对象, rv=2693414
最终缓存大小: 1
缓存中的名字: ['kube-root-ca.crt']
事件序列:
    ADDED     inf-0
    MODIFIED  inf-0
    DELETED   inf-0
    ADDED     inf-1
    MODIFIED  inf-1
    DELETED   inf-1
    ...
410 恢复次数: 0
```

**缓存一致性验证**（这一步不能省）：

```
服务端: ['kube-root-ca.crt']
本地缓存: ['kube-root-ca.crt']
一致: True
```

> ✅ 事件全部正确反映到缓存，且**与服务端真实状态一致**。
> 注意 `inf-0/1/2` 已被删除，所以最终缓存里只剩 `kube-root-ca.crt`——这是对的。

### 4.4 三个必须写对的点

1. **`self.rv = o.metadata.resource_version`**——每次事件都要推进，否则断线后从旧 rv 续，要么重复要么 410
2. **BOOKMARK 也要更新 rv 但不写业务**——它的存在就是为了推进 rv
3. **DELETED 要 pop**——忘了的话缓存里全是幽灵对象

---

## 第五幕：调谐循环

### 5.1 什么是调谐

**声明式**的核心：你不管"发生了什么事件"，只管"**现在状态对不对，不对就改**"。

```
事件: rc-0 被创建了
调谐: 读 rc-0 → 发现缺 managed 标记 → 打上
事件: 因为打标记，又触发 MODIFIED
调谐: 读 rc-0 → 已是期望状态 → 什么都不做
```

### 5.2 实测：完整跑通

```
informer 事件:
    ADDED     rc-0
    ADDED     rc-1
    ADDED     rc-2
    MODIFIED  rc-0
    MODIFIED  rc-1
    MODIFIED  rc-2

调谐统计: {'reconciled': 3, 'no_op': 3, 'errors': 0}

    rc-0.data = {'k': 'v', 'managed': 'true'}
    rc-1.data = {'k': 'v', 'managed': 'true'}
    rc-2.data = {'k': 'v', 'managed': 'true'}
```

**`reconciled=3`**——三个对象都被改成期望状态。
**`no_op=3`**——第二次调谐时发现已经对了，什么都不做。

**这个 `no_op` 就是调谐的灵魂。**

### 5.3 幂等性实测

同一个对象调谐两次：

```
[reconcile] reconcile-me: 缺 managed 标记 -> 打上
[reconcile] reconcile-me: 已是期望状态，无需动作（幂等）
```

> 课 5 讲的幂等在这里派上用场了：**调谐函数必须幂等**，因为同一个对象会被调谐无数次。

### 5.4 ⚠️ 陷阱一：用 replace 做调谐 → 409 风暴

实测两个 worker 同时改同一对象：

```
w2 -> 409 Conflict
```

课 5 说 409 要"重读再写"。但在调谐循环里，**根本不该让 409 发生**：

> ✅ **调谐一律用 `patch`，不用 `replace`。**
> patch 只提交差异，不带 `resourceVersion` 前提，天然避开乐观锁冲突。

### 5.5 ⚠️ 陷阱二：不幂等的调谐 → 自激振荡

如果你的调谐函数每次都改动对象（比如 `data["last_seen"] = now()`），那么：

```
调谐改对象 → 触发 MODIFIED → 又调谐 → 又改 → 又 MODIFIED → ...
```

实测故意连续 patch 5 次：

```
3 秒内 rc-0 相关事件: 5 个
```

**每次 patch 都产生一个 MODIFIED。**

> 🚨 如果调谐器自己也在 patch，就形成了**自激振荡**——无限循环，把 apiserver 打满。
>
> **判据**：调谐函数里如果要写，必须**先判断"是否已经是我要的状态"**。
> 已经对了就 `return`，一个字节都别改。

---

## 第六幕：stop() 的真相

### 6.1 🚨 stop() 不是立即生效的

先看源码——**它就一行**：

```python
def stop(self):
    self._stop = True
```

**它不关闭连接，不打断阻塞。** 真正的退出在 `stream` 里：

```python
if self._stop:
    break
```

而这一行在**处理完一个事件之后**才执行。

### 6.2 实测对照

| 场景 | 结果 |
|---|---|
| **空闲流**（无事件）上调 `stop()` | ❌ **6 秒都没退出**（`stopped: False`） |
| **有事件流**时调 `stop()` | ✅ 0.16 秒退出 |
| 只靠 `timeout_seconds=2` | ✅ 精确 2.00 秒退出 |

> ⚠️ **空闲时 stop() 会一直卡着**，直到下一个事件到达或服务端 timeout 到期。
> 这就是为什么很多人的程序"关不掉"。

### 6.3 ✅ 正确的退出姿势

```python
stop_flag = threading.Event()

def watch_loop():
    while not stop_flag.is_set():          # ← 外层判断
        for e in w.stream(..., timeout_seconds=10):
            if stop_flag.is_set():
                w.stop()
                return
            handle(e)
        # timeout 到期，回到 while 再判断一次
```

> **退出靠 `timeout_seconds` 到期后的外层 `while` 判断，不要指望 `stop()` 能立刻打断阻塞。**
> `stop()` 只能作为"处理完当前事件后尽快收尾"的辅助手段。

---

## 第七幕：选择器与多资源

### 7.1 用选择器缩小范围（服务端过滤）

实测：

```
label_selector='app=demo' 收到的对象: ['tagged-0', 'tagged-1']
```

`untagged` **完全没出现**——过滤发生在服务端，省带宽也省客户端 CPU。

```python
w.stream(v1.list_namespaced_config_map, namespace=ns,
         label_selector="app=demo",              # 标签过滤
         field_selector="metadata.name=tagged-0") # 字段过滤
```

实测 `field_selector` 只收到 `tagged-0`。

### 7.2 多资源 watch

每种资源一个线程（实测）：

```
configmaps   -> 8 个事件
pods         -> 0 个事件
secrets      -> 0 个事件
```

> ⚠️ **每个 watch 独占一条 TCP 连接。**
> 资源种类多了会耗尽连接池——这也是生产环境用 **SharedInformer**（共享一条连接、多种资源）的原因。
> ⚠️ 本机标准库**没有** SharedInformer（那是 `client-go` 的概念），Python 侧需自己实现或用 `kopf` 等框架。
>
> ⚠️ **措辞澄清（2026-09-29 实测，见[番外 3](lesson-06-async3-SharedInformer共享watch.md)）**：
> 上面“共享一条连接、多种资源”容易**被误读为“一条连接 watch 多种资源”——协议上做不到**。
> watch 的 path 必须指定具体资源集合（`.../configmaps?watch=true`）；
> `shared` 的真实含义是**多个消费者共享同一条资源 watch + 同一份缓存**，
> 收益是成本从「消费者数 × 资源种类」降为「资源种类」。
> 另：“会耗尽连接池”不准确——实测 aiohttp `limit_per_host=0`（不限），
> 准确说法是**连接数随资源种类线性增长**。
> 🚨 相关静默陷阱：`?watch=true` 加在**非集合路径**上**不报错**，
> 返回 200 + 完整快照后关闭，代码以为在 watch 却永不收后续变更。

---

## 收束：三张地图

### 地图一：watch 参数速查

| 参数 | 作用 | 不设会怎样 |
|---|---|---|
| `timeout_seconds` | 服务端保持时长 | **永久挂起** |
| `_request_timeout` | 客户端兜底超时 | 网络层静默时永久挂起 |
| `resource_version` | 从哪儿续 | 从当前开始（全量 ADDED） |
| `label_selector` | 标签过滤 | 全量推送 |
| `field_selector` | 字段过滤 | 全量推送 |
| `allow_watch_bookmarks` | 开启 BOOKMARK | 收不到进度标记 |

### 地图二：写 watch 代码的检查清单

1. `timeout_seconds` 和 `_request_timeout` **都设了吗**？后者 > 前者？
2. 外层有 `while` 循环**重新发起** watch 吗？
3. catch 到 **410** 会回退**全量 list** 吗？
4. 每次事件都**更新 rv** 了吗？
5. **BOOKMARK** 是只更新 rv 吗？（有没有误当业务对象）
6. **DELETED** 从缓存里删了吗？
7. 调谐函数**幂等**吗？会不会自激振荡？
8. 调谐用 **patch** 而不是 replace 吗？
9. 退出靠**外层 while 判断**，而不是指望 `stop()` 吗？

### 地图三：本课六个必须记住的结论

1. **event 只有三个键**：`type` / `object`(模型) / `raw_object`(dict)
2. **410 是流内 ERROR 事件**，不是 HTTP 状态码——**`e.body` 是 `None`**，别去解析
3. **`timeout_seconds` ≠ `_request_timeout`**：服务端退休 vs 客户端兜底，**两个都要设**
4. **传 `timeout_seconds` 会禁用库的 410 自动重试**（源码 `disable_retries`）
5. **`stop()` 只有一行 `self._stop = True`**，空闲时调它**不会立刻退出**
6. **调谐必须幂等 + 用 patch**——否则 409 风暴或自激振荡

---

## 本课实测环境说明

- 测试命名空间 `py-lesson06` 内的对象为**临时创建**（ConfigMap 若干，含 churn 测试）
- ⚠️ **清理待办**：`py-lesson06` 尚未删除（本课结束时会处理）
- 所有操作均为预期内，未影响集群其他资源

---

## 延伸阅读

- [官方示例：watch_recovery.py](https://github.com/kubernetes-client/python/blob/master/examples/watch/watch_recovery.py)
- [官方 watch 示例目录](https://github.com/kubernetes-client/python/tree/master/examples/watch)
- [Kubernetes：高效检测变更（API 概念）](https://kubernetes.io/docs/reference/using-api/api-concepts/#efficient-detection-of-changes)
- [控制器与调谐（架构概念）](https://kubernetes.io/docs/concepts/architecture/controller/)
- [etcd compaction 与 watch 历史窗口](https://etcd.io/docs/latest/op-guide/maintenance/)

> ⚠️ **链接勘误（2026-09-28 实测）**：常见教程引用的 `examples/watch_recovery.py` 与 `examples/informer.py` **均已 404**。
> 实际路径是 **`examples/watch/watch_recovery.py`**；而**官方 Python 库根本没有 informer 示例**——
> 这反过来印证了本课 7.2 节的说法：**SharedInformer 是 `client-go` 的概念，Python 侧需自己实现或用 `kopf` 等框架**。

---

## 课程导航

- **上一课**：[课 5：错误处理与健壮性](lesson-05-错误处理与健壮性.md)
- **下一课**：课 7：自定义资源与动态客户端
- **返回**：[子教程 overview](../overview.md) ｜ [课程目录](../../../02-课程目录.md)

---

## 小测

1. `event` 字典有几个键？`object` 和 `raw_object` 有什么区别？
2. BOOKMARK 事件该怎么写进缓存？要怎么开启？
3. 410 Gone 是怎么从服务端返回的？`e.body` 里有内容吗？
4. 处理 410 的正确做法是什么？
5. `timeout_seconds` 和 `_request_timeout` 分别管什么？两者该设成什么关系？
6. 两个都不设会怎样？
7. 传了 `timeout_seconds` 后，库的 410 自动重试还在吗？
8. `watch.stop()` 为什么在空闲时调不立刻生效？正确退出姿势是什么？
9. 调谐循环为什么要用 patch 而不是 replace？
10. 什么情况下调谐会自激振荡？

<details>
<summary>答案</summary>

1. **三个键**：`type`(str) / `object`(模型对象，如 `V1ConfigMap`) / `raw_object`(dict)。内容相同、类型不同：业务处理用 `object`，原样转发/存 JSON 用 `raw_object`。
2. **只更新 `resourceVersion`，不写进业务缓存**（它没有实际数据）。需 `allow_watch_bookmarks=True` 才会推送。
3. **不是 HTTP 状态码**，而是 watch 流里嵌的一个 `{"type":"ERROR","object":{...,"code":410,"reason":"Expired"}}` 事件，**HTTP 状态码仍是 200**。库把它转成 `ApiException(410)`，但 **`e.body` 是 `None`**（手工构造的异常，没有响应体）。
4. **回退全量 list**：重新 `list_*` 拿新的 `resourceVersion`，再从这个新 rv 继续 watch。没有别的办法。
5. `timeout_seconds` 是**服务端**参数（watch 最多保持 N 秒，到期**正常返回**）；`_request_timeout` 是**客户端**参数（urllib3 掐断连接，**抛异常**）。**`_request_timeout` 必须 > `timeout_seconds`**，否则每次都被客户端提前掐断。
6. **永久挂起**。源码里 `func()` 和 `iter_resp_lines()` 都没有默认超时，TCP 不断但无数据时会永远阻塞。（本机实测"4 秒后仍在挂起=True"；无限期情形未实测，为源码机制推断。）
7. **不在了**。源码 `disable_retries = ('timeout_seconds' in kwargs)`，传了它就关掉库内 410 自动重试，410 会直接抛给调用方。
8. `stop()` 源码只有 `self._stop = True`，**不关连接、不打断阻塞**；`stream` 里的 `if self._stop: break` 在**处理完一个事件之后**才执行。空闲流（无事件）时它要等下一个事件才生效——实测 6 秒都没退出。正确姿势：用 `timeout_seconds` 让 watch 定期退休，外层 `while not stop_flag.is_set()` 判断退出。
9. `replace` 带 `resourceVersion` 前提，并发时会 **409 Conflict**（实测）；`patch` 只提交差异、不带 rv 前提，天然避开冲突。
10. 调谐函数**每次都改动对象**（如写时间戳）时：改动 → 触发 MODIFIED → 又调谐 → 又改动，形成无限循环。判据：写之前先判断是否已是期望状态，是就 `return`，一个字节都别改。

</details>

---

## 接力提示词

```
继续学 Kubernetes Python 客户端专项，我的学习档案在 k8s/子教程/Python客户端专项/overview.md，
刚学完课 6《watch · informer · 调谐循环》（知识点：event 三键 type/object/raw_object、
BOOKMARK 只推 rv 且需 allow_watch_bookmarks 开启、resource_version 续播与 rv=0 语义、
410 Gone 是流内 ERROR 事件而非 HTTP 状态码且 e.body 为 None、410 唯一处置是回退全量 list、
timeout_seconds 服务端退休 vs _request_timeout 客户端兜底且后者须更大、
传 timeout_seconds 会禁用库内 410 自动重试、stop() 仅置标志位空闲时不生效、
informer list-watch 两段式与本地缓存、调谐循环必须幂等且用 patch 避免 409 与自激振荡），
请按大纲继续讲解课 7《自定义资源与动态客户端》。
```
