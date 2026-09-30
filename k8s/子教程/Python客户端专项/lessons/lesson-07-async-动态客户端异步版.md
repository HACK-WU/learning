# 课 7 番外：动态客户端的异步版

> 前置：[课 7：自定义资源与动态客户端](lesson-07-自定义资源与动态客户端.md)、[番外 1：异步改写](lesson-06-async-调谐循环的异步改写.md)
> 环境：k8s v1.34.0（`kind-k8s-c1`）；`kubernetes-asyncio` 36.1.0
> 代码：[dynamic_async.py](../assets/lesson06-async/dynamic_async.py)、[test_dynamic_async.py](../assets/lesson06-async/test_dynamic_async.py)
> 本文所有数字均为 2026-09-29 本机实测，未实测处已显式标注。

---

## 引子：把课 7 换成 async，不是加个 await 就完事

课 7 讲的是 `DynamicClient`：不手写 plural、运行时问 apiserver"你有哪些资源"。它解决的是**类型未知**的问题。

番外 1 讲的是 async：把同步调谐改成异步，让一个 worker 在等 IO 时去干别的。它解决的是**吞吐**的问题。

**把两者叠起来**（异步 + 动态），不是简单相加。实测下来，课 7 的五个硬结论里：

- 两个**完全一致**（`ResourceNotUniqueError` / `ResourceNotFoundError`）
- 两个**换了形态**（初始化方式、watch 参数名）
- 一个**变得更危险**（415 从抛异常变成静默返回）

最后这个是本文的核心。

---

## 第一幕：异步版的两个"新坑"

### 1.1 🚨 `DynamicClient` 构造后必须初始化

同步版：

```python
dyn = DynamicClient(client.ApiClient())      # 直接就能用
```

异步版这么写，第一次访问 `.resources` 就炸：

```text
✓ RuntimeError: Discoverer is not initialized, use 'async with' or await the client directly
```

原因：异步版的 discoverer 初始化本身是 coroutine（要做发现请求），构造函数没法 `await`。库给了两条路：

```python
dyn = await DynamicClient(api)              # ① await 直接初始化
async with DynamicClient(api) as dyn:       # ② async with
    ...
```

实测：`await` 初始化耗时 **0.0008s**（Lazy，此刻还没发请求），`async with` 得到 `LazyDiscoverer`。

> 这个坑好在**报错很响**，不容易漏。下面那个就不是了。

### 1.2 🚨 `resources.get` 是 coroutine

同步版 `dyn.resources.get(...)` 是普通方法；异步版它是 **coroutine**。

忘了 `await` 会怎样？**不会立刻报错**：

```python
r = dyn.resources.get(api_version="v1", kind="ConfigMap")
# 此刻 r 是 coroutine 对象，一切正常
print(r.name)     # ← 到这儿才炸
```

```text
不 await → coroutine
✓ AttributeError: 'coroutine' object has no attribute 'name'
await → configmaps (namespaced=True)
```

而且 Python 会额外给一条容易忽略的警告：

```text
RuntimeWarning: coroutine 'Discoverer.get' was never awaited
```

**判据：异步版里凡是"要发请求"的调用都要 await，包括"发现"这一步本身。**

### 1.3 与同步版一致的：两个发现类异常

课 7 的两个坑在异步下原样保留：

```text
✓ ResourceNotUniqueError: Multiple matches found for {'api_version': 'v1'}: [<Resource(v1/bindings)>, ...]
✓ ResourceNotFoundError: No matches found for {'api_version': 'v1', 'kind': 'Nope'}
```

**判据一致：只给 `api_version` → `ResourceNotUniqueError`；`kind` 写错 → `ResourceNotFoundError`。**

---

## 第二幕：🚨 415 从"抛异常"变成"静默返回"

这是本文最重要的部分。课 7 第四幕说：`DynamicClient.patch` 必须传 `content_type`，否则 415。

### 2.1 同步版 vs 异步版的表现

同一个错误（不传 `content_type` 去 patch 一个 CRD），两个客户端的反应完全不同：

| | 同步版（课 7） | 异步版（本课） |
|---|---|---|
| 表现 | 抛 `DynamicApiError` **415** | **返回** `ResourceInstance[Status]`，code=415 |
| 你能察觉吗 | 能，程序立刻崩 | **不能，除非你主动检查** |

实测：

```text
--- 裸 patch（用库默认 strategic-merge-patch）---
不抛异常         返回类型=ResourceInstance kind=Status
is_status=True  code=415
→ 读回 spec.n=1  !! 改动静默丢失
```

服务端**确实返回了 415**，但异步客户端把它包装成一个 `ResourceInstance` 交还给你。这个对象看起来跟正常返回值是同一个类型，只是内容其实是 `Status`：

```text
返回值 = ResourceInstance[Status]:
  apiVersion: v1
  code: 415
  kind: Status
  message: 'the body of the request was in an unknown format - accepted media types
    include: application/json-patch+json, application/merge-patch+json,
    application/apply-patch+yaml'
  reason: UnsupportedMediaType
  status: Failure
```

### 2.2 为什么这比同步版更危险

同步版炸在**出错的那一行**，栈指得清清楚楚。

异步版不炸。你拿到返回值继续往下走，于是有两种下场：

```python
r = await dyn.patch(dd, name="d1", namespace=NS, body={"spec": {"n": 999}})
print(r.spec.n)        # ① 在这里 AttributeError: 'NoneType' has no attribute 'n'
                       #    报错地点离真正的原因已经隔了一层
```

```python
# ② 更糟：你根本不读返回值
await dyn.patch(dd, name="d1", namespace=NS, body={"spec": {"n": 999}})
log.info("patched")    # ← 打了日志，以为成功了
# 实际 spec.n 还是旧值，没有任何人知道
```

**第 ② 种是真正的灾难：控制器以为自己调谐成功了，实际状态一直在漂移，而监控系统看到的是一片"正常"。**

这与番外 1 的 `await queue.add()`、番外 3 的 `?watch=true`、番外 4 的四个缺陷同源——**程序不报错，但功能已失效**。这是本系列第五次抓到同一类病。

### 2.3 不止 patch：create 和 replace 也一样

实测确认，同一个静默模式覆盖三个写操作：

```text
--- create 缺必填字段 ---
裸 create → kind=Status is_status=True code=403
🚨 静默（不抛异常）

--- replace 缺字段 ---
✓ 拦截: [400] BadRequest: the name of the object (life based on URL) was undeterminable
```

**判据：异步版 `DynamicClient` 的 create / patch / replace 都可能返回 Status 而不抛异常。**

### 2.4 解法：把 Status 提升为异常

```python
def is_status(obj):
    """判断 ResourceInstance 是否为 Status（而非真实资源）"""
    if obj is None:
        return False
    try:
        kind = getattr(obj, "kind", None)
    except Exception:
        return False
    if kind != "Status":
        return False
    return getattr(obj, "status", None) in ("Failure", "Success")


def raise_if_status(obj):
    if is_status(obj):
        raise DynamicApiErrorAsync(obj)
    return obj
```

> ⚠️ 判据不能只看"有没有 `code` 字段"——有些业务资源自己也带 `code`。必须看 **`kind == "Status"` 且 `status in ("Failure", "Success")`** 两个条件。

封装后的 `safe_patch`：

```python
async def safe_patch(dyn, resource, name, body, namespace=None,
                     content_type="application/merge-patch+json", **kw):
    r = await dyn.patch(resource, name=name, namespace=namespace,
                        body=body, content_type=content_type, **kw)
    return raise_if_status(r)
```

注意**默认 `content_type` 用的是 `merge-patch`**，不是库的默认 `strategic-merge-patch`——因为 CRD 不支持 strategic-merge-patch（这正是 415 的来源）。实测：

```text
--- safe_patch ---
✓ 成功 n=42

--- safe_patch 故意触发错误（传 json-patch 数组但用 merge）---
✓ 拦截: [400] BadRequest: error decoding patch: json: cannot unmarshal array into Go val
```

### 2.5 裁定

```text
裁定: 裸 patch 静默失败 = 是 🚨；safe_patch 显式抛错 = 是
```

这个裁定**连跑两轮稳定复现**——见下面第三幕，第一轮曾因实验污染判反过。

---

## 第三幕：🚨 我在这里犯的实验污染错误

第一版测试跑出来的结论是「**静默失败 = 否**」。差点就写进讲义了。

**根因：上一轮的 CRD / namespace 没清干净。**

```text
--- 裸 patch ---
不抛异常   kind=Status  is_status=True  code=415
→ 读回 spec.n=102  生效        ← 假的！
```

`spec.n=102` 是**上一轮测试遗留的值**，不是本轮 patch 的结果。我拿残留数据当基线，得出"改动生效"的结论——**完全反了**。

第二次污染更隐蔽：namespace 处于 `Terminating` 状态时建资源，得到 `403 Forbidden`，整轮报废。

修复：启动即**彻底清理并等待真正消失**。

```python
async def clean_all(v1, apiext):
    await apiext.delete_custom_resource_definition(name=CRD_NAME)
    await v1.delete_namespace(name=NS)
    # 等 CRD 消失
    for _ in range(40):
        await asyncio.sleep(1)
        try:
            await apiext.read_custom_resource_definition(name=CRD_NAME)
        except Exception:
            break
    # 等 ns **真正消失**（Terminating 期间建资源会 403）
    for _ in range(60):
        await asyncio.sleep(1)
        try:
            await v1.read_namespace(name=NS)
        except Exception:
            break
```

> 这与 Kafka 课 13 的「实验污染」（测试脚本复用了运行中服务的 `group.id`）是同一种病：
> **在脏环境里测出来的数字，反映的是上一轮的残留，不是本轮的行为。**
> 清干净后连跑两轮，结论稳定为「静默失败 = 是」。

---

## 第四幕：watch —— 同一个坑换了个名字

课 7 说同步版 `dyn.watch(..., timeout_seconds=...)` 会 `TypeError`。异步版一样，只是参数名换成了 `timeout`：

```text
✓ timeout_seconds → TypeError: DynamicClient.watch() got an unexpected keyword argument 'timeout_seconds'
```

正确写法：

```python
async for e in dyn.watch(resource, namespace=NS, timeout=4):
    ...
```

实测收到 5 个事件：

```text
✓ dyn_watch(timeout=4) 收到 5 事件: [('ADDED', None), ('ADDED', 42),
                                     ('MODIFIED', 100), ('MODIFIED', 101), ('MODIFIED', 102)]
```

> ⚠️ 第一个 `ADDED` 的 `spec` 是 `None`——CR 刚建立时 spec 可能还没就绪。取值要用 `getattr` 兜底，别直接 `.spec.n`。

这个坑是**显式**的（TypeError 立刻炸），属于好排查的那类。

---

## 第五幕：server_side_apply —— 一次"我判错了"的更正

上一版讲义里我写了一句：

> **未实测标注 1 处**：`server_side_apply`（课 7 §4.5）在异步 `DynamicClient` 下未做实测——异步版 `DynamicClient` 未暴露同名方法（方法清单中无 `server_side_apply`）。

**这句是错的。** 异步版有 `server_side_apply`。

### 5.1 我错在哪

当时我这么查的：

```python
for m in ("get", "create", "patch", "replace", "delete", "watch", "list"):
    if hasattr(DynamicClient, m):
        ...
```

我拿**预设的 7 个方法名**去 `hasattr`，清单里没有 `server_side_apply`，于是下了"未暴露"的结论。

正确做法是列全量：

```python
sorted(n for n in dir(DynamicClient) if not n.startswith("_"))
# ['create', 'delete', 'ensure_namespace', 'get', 'patch', 'replace',
#  'request', 'resources', 'serialize_body', 'server_side_apply',
#  'validate', 'version', 'watch']
```

**`server_side_apply` 就在里面，签名与同步版完全一致**：

```python
(resource, body=None, name=None, namespace=None,
 force_conflicts=None, **kwargs)
```

这与 Kafka 课 13「把空 poll 时间算进分子」是同一种病：**核验了，但核验方法本身是错的**。用一张漏了刻度的尺子量，量出"没有"就信了。

> 顺带一提，我那个预设清单里还有个 `list`——异步版其实**也没有** `list`（列举用的是 `get` 不带 name）。这次一并更正。

### 5.2 实测：异步 SSA 可用，但同样静默

**基本可用**：

```text
正常 safe_apply: (1, 'init')
managedFields: [('mgr-v', 'Apply')]     ← operation=Apply，SSA 生效
```

**但它跟 patch 一样会静默返回 Status**：

```text
--- 裸 SSA 缺 apiVersion/kind ---
裸 → is_status=True code=400  🚨 静默

--- 缺 field_manager ---
裸 → is_status=True code=422  🚨 静默
```

所以 `safe_apply` 同样要过 `raise_if_status`：

```python
async def safe_apply(dyn, resource, body, name=None, namespace=None,
                     field_manager="pyclient", force_conflicts=False, **kw):
    r = await dyn.server_side_apply(
        resource, body=body, name=name, namespace=namespace,
        field_manager=field_manager, force_conflicts=force_conflicts, **kw)
    return raise_if_status(r)
```

实测拦截效果：

```text
✓ 拦截: [400] BadRequest: invalid object type: /, Kind=
```

### 5.3 SSA 的三个特性（异步下均成立）

**幂等**——同一个 body 连发两次，`resourceVersion` 不变：

```text
第一次 rv=113694
第二次 rv=113694
→ ✓ 幂等
```

**冲突检测**——别人的 manager 改过同一字段，你再 apply 就 409：

```text
先用 merge-patch 改 n=50（manager=OpenAPI-Generator）
✓ 拦截冲突: [409] Conflict: Apply failed with 1 conflict:
  conflict with "OpenAPI-Generator" using lesson.pyclient.io/v1: .spec.n
```

`force_conflicts=True` 可强制抢占：

```text
force_conflicts=True → (70, None)  managers=['mgr-v']
```

> **用不用 force 是产品决策，不是技术选择。** 强抢意味着你认为自己的声明比别人的对——在 Operator 场景通常成立（你才是控制器），但要多想一秒。

**字段归属**——这是 SSA 最反直觉的地方，实测确认：

```text
E1 跨 manager：A 只交 n → (12, 'from-b')   note 保留 ✓
E2 同 manager：先 n+note 再只交 note → (None, 'only')  n 被清 ✓
```

- **别人管的字段**：你不提交，它**保留**
- **你自己管的字段**：你这次不提交，就被**删除**

因为 SSA 是**声明式**的——你的 body 就是"这份资源应该长什么样"的完整声明，不在声明里的（且归你管的）就是要删掉。

### 5.4 我在这里第二次栽进实验污染

第一版 SSA 实测跑出：

```text
SSA 只提交 note 后: n=None  → n 被清
```

当时看着像"异步 SSA 实现有 bug、违反声明式语义"。**又是假象。**

原因：前面 S4 用 `force_conflicts=True` 把 `n` 抢到了 `async-mgr` 名下。所以后面同一个 manager 只提交 `note`，等于**主动删掉自己管的 `n`**——这是 SSA 的**正确行为**。

设计了对照实验才裁定清楚：

```text
G1 跨 manager 保留: ✓
G2 同 manager 清除: ✓
→ 异步 SSA 语义与标准一致。n=None 是我的测法制造的假象。
```

**判据：看到反直觉结果时，先设计一个能把两种解释分开的对照实验，再下结论。**

---

## 第六幕：并发 —— 异步版真正的收益

同步版的 `DynamicClient` 一次只能处理一个请求；异步版可以并发。

**实测：单个 `DynamicClient` 能否被多个协程共用？**

```text
20 次并发 get (max=10): 成功 20/20  失败 无  耗时 0.025s
→ ✓ 可共用
```

**可以。** 底层是 aiohttp 连接池，无需每个协程建一个 client。

这意味着异步 + 动态的组合拳可以这样打：

```python
async def concurrent_get(dyn, resource, names, namespace=None,
                         max_concurrency=8):
    sem = asyncio.Semaphore(max_concurrency)

    async def one(n):
        async with sem:
            try:
                r = await dyn_get(dyn, resource, n, namespace)
                return n, r, None
            except Exception as e:
                return n, None, e

    return await asyncio.gather(*[one(n) for n in names])
```

> 注意 `Semaphore` 仍然需要——并发不等于无限并发，课 9 讲过的连接池上限在这里依然适用。

---

## 第七幕：端到端 —— 异步调谐 CRD

把课 7 的 CRD 知识 + 番外 1 的异步调谐 + 本文的 `safe_patch` 组合起来：

```python
async def reconcile(name):
    async with sem:
        o = await dyn_get(dyn, dd, name, NS)
        if o.spec.note != "done":
            await safe_patch(dyn, dd, name, {"spec": {"note": "done"}}, NS)
            stats["reconciled"] += 1
        else:
            stats["no_op"] += 1

await asyncio.gather(*[reconcile(f"t{i}") for i in range(5)])
```

实测：

```text
5 个 CR 并发调谐: stats={'reconciled': 5}  done=['t0','t1','t2','t3','t4']
→ ✓ 5/5
二次调谐: stats={'reconciled': 5, 'no_op': 5}  (no_op 应为 5 → 幂等)
```

**5/5 成功，二次调谐 5 个 `no_op` —— 幂等成立。**

完整 CRUD 生命周期也实测通过（注意 `replace` 需要 `resourceVersion`，这是课 3 的乐观锁知识）：

```text
create: n=5 note=c
get   : n=5
patch : n=6
replace: n=7 note=r
delete : OK
```

---

## 速览

| 项 | 同步版（课 7） | 异步版（本课） | 判定 |
|----|---------------|---------------|------|
| 构造 DynamicClient | 直接用 | **必须 await / async with** | 🚨 新坑（报错响） |
| `resources.get` | 普通方法 | **coroutine** | 🚨 新坑（延迟报错） |
| 只给 api_version | `ResourceNotUniqueError` | 同 | ✓ 一致 |
| kind 写错 | `ResourceNotFoundError` | 同 | ✓ 一致 |
| patch 415 | 抛 `DynamicApiError 415` | **静默返回 Status** | 🚨 **更危险** |
| create / replace 出错 | 抛异常 | **同样静默返回 Status** | 🚨 更危险 |
| `server_side_apply` | 有 | **也有**（签名一致） | ✓ 可用（也静默） |
| watch 参数名 | `timeout_seconds` → TypeError | **`timeout`** → TypeError | 🚨 换名（显式） |
| 多协程共用 | N/A | 20/20 成功，0.025s | ✓ 安全 |
| 端到端调谐 | N/A | 5/5，二次 no_op=5 | ✓ 幂等 |

---

## 什么时候该用

| 场景 | 建议 |
|------|------|
| 一次性脚本、运维工具 | 同步版够了，简单直接 |
| 控制器、Operator | **异步 + 动态**，但**必须**用 `safe_patch` 类封装 |
| 已知类型的资源 | 用 `CoreV1Api` 等强类型客户端，有类型检查 |
| 类型在运行时才知道 | `DynamicClient`（这正是课 7 的选型结论） |
| 需要并发处理大量对象 | 异步版，配 `Semaphore` 限流 |

⚠️ **铁律：用异步 `DynamicClient` 做任何写操作，都要检查返回值是不是 `Status`。** 这是本课唯一必须记住的一条。

⚠️ **别在生产裸调 `dyn.patch` / `dyn.create` / `dyn.replace`。** 它们的失败是静默的，你的控制器会在"以为成功"的状态下持续漂移。

---

## 小测

1. 异步版 `DynamicClient` 构造后直接用 `.resources` 会怎样？为什么同步版不会？
2. 忘了 `await dyn.resources.get(...)`，程序会在哪里报错？
3. 异步版 patch 出 415 时，客户端是抛异常还是返回什么？为什么这比同步版危险？
4. 判断 `ResourceInstance` 是否为 Status 的正确判据是什么？只看 `code` 字段为什么不行？
5. 我在第一轮测试里把"静默失败"误判为"否"，根因是什么？
6. 我说过"异步版没有 `server_side_apply`"，这个结论错在哪？正确查法是什么？
7. SSA 下，同一个 manager 这次不提交它上次设的字段，会怎样？换成别的 manager 的字段呢？

<details>
<summary>答案</summary>

1. 抛 `RuntimeError: Discoverer is not initialized, use 'async with' or await the client directly`。因为异步版的 discoverer 初始化本身是 coroutine（要发发现请求），构造函数无法 `await`，所以库把它挪到了 `await` / `async with` 里。同步版的初始化是普通函数调用，构造函数里就能完成。

2. **不会在调用那一行报错**。`dyn.resources.get(...)` 返回 coroutine 对象，一切正常；直到你访问 `.name` 才 `AttributeError: 'coroutine' object has no attribute 'name'`。Python 还会额外给一条 `RuntimeWarning: coroutine 'Discoverer.get' was never awaited`。这种"延迟报错"让排查变难。

3. **返回** `ResourceInstance[Status]`（code=415, reason=UnsupportedMediaType），**不抛异常**。危险在于：同步版炸在出错那一行，栈清清楚楚；异步版你拿到返回值继续走，若不去读返回值（比如只打个日志），就会**以为调谐成功但实际改动丢失**——控制器持续漂移而监控一片正常。实测 `读回 spec.n=1`，改动确实丢了。

4. 正确判据是 **`kind == "Status"` 且 `status in ("Failure", "Success")`** 两个条件同时成立。只看 `code` 不行——部分业务资源自己也带 `code` 字段（比如 CRD 里定义 `spec.code`），会被误判为 Status 而误报。

5. **实验污染**：上一轮的 CRD / namespace 没清干净，`d1` 残留 `spec.n=102`。我拿残留值当基线比较，得出"改动生效"的错误结论。第二次更隐蔽——namespace 处于 `Terminating` 时建资源会 `403 Forbidden`，整轮报废。修复方式是启动即彻底删除并**轮询等待资源真正消失**，之后连跑两轮结论稳定。这与 Kafka 课 13 复用运行中服务 `group.id` 导致 rebalance 是同一种病。

6. 错在**用预设方法名清单去 `hasattr`，而不是列全量 `dir()`**。我查的 7 个名字里既没有 `server_side_apply`（实际有），还混进了一个并不存在的 `list`（异步版列举资源用的是不带 name 的 `get`）。正确查法：`sorted(n for n in dir(DynamicClient) if not n.startswith("_"))`。这与 Kafka 课 13「把空 poll 时间算进分子」同型——**核验了，但核验方法本身是错的**，用漏刻度的尺子量出"没有"就信了。

7. **同一个 manager** 这次不提交它上次设的字段 → 该字段被**删除**。**别的 manager** 的字段 → 你只提交自己的，他的字段**保留**。因为 SSA 是声明式：你的 body 就是"这份资源应该长什么样"的完整声明，不在声明里且归你管的即视为要删。实测：`E1 跨 manager → note 保留`；`E2 同 manager → n 被清`。

</details>

---

## 课程导航

- **前置**：[课 7：自定义资源与动态客户端](lesson-07-自定义资源与动态客户端.md)
- **异步基础**：[番外 1：调谐循环的异步改写](lesson-06-async-调谐循环的异步改写.md)、[课 9：异步客户端与并发](lesson-09-异步客户端与并发.md)
- **番外 3**：[SharedInformer 共享 watch](lesson-06-async3-SharedInformer共享watch.md)
- **番外 4**：[重试与指数退避](lesson-06-async4-重试与指数退避.md)
- **返回**：[Python 客户端专项总览](../overview.md)

---

## 评审结论（2026-09-29）

本文由主 agent 内联评审（pedagogy + learner 双视角，独立性受限），P0 = 0。

**实测裁定**：对课 7 五个硬结论逐条在异步下复验——两个**完全一致**（`ResourceNotUniqueError` / `ResourceNotFoundError`），两个**换了形态**（初始化必须 `await`/`async with`，watch 参数 `timeout_seconds` → `timeout`），一个**变得更危险**（415 由抛异常变为静默返回 Status）。

**核心发现**：异步版 `DynamicClient` 的 **create / patch / replace 三个写操作**在出错时均**不抛异常**，而是返回 `ResourceInstance[Status]`（实测 415 / 403 / 400 / 422 均如此）。若调用方不读返回值，控制器会在"以为成功"下持续漂移且监控无异常——这是本系列**第五次**抓到"程序不报错但功能已失效"（前四次：番外 1 `await queue.add()`、番外 3 `?watch=true` 静默退化、番外 4 四个缺陷）。已交付 `safe_patch` / `dyn_create` / `dyn_replace` + `is_status` / `raise_if_status` 封装，判据为 `kind == "Status"` 且 `status in ("Failure","Success")`（仅看 `code` 会误判业务字段）。

**测法错误 1 处（实验污染）**：首轮判定"静默失败 = 否"，根因是上一轮 CRD/namespace 未清干净、`d1` 残留 `spec.n=102` 被当作基线；次轮 namespace 处于 `Terminating` 时建资源得 `403` 致整轮报废。修复为启动即删除并**轮询等待资源真正消失**，此后**连跑两轮结论稳定**（此点与 Kafka 课 13 复用运行中 `group.id` 属同一类病）。

**其他实测**：并发共用安全（20 次并发 get，20/20 成功，0.025s，单 `DynamicClient` 可多协程共用）；端到端 5 个 CR 并发调谐 **5/5**，二次调谐 `no_op=5`（幂等成立）；`replace` 须带 `resourceVersion`（课 3 乐观锁知识，实测漏传报 422）。

**验证通过项**：`py_compile` 全部通过；V1–V8 八项验证全绿；测试 ns `py-lesson07-verify` / `-async` / `-415` / `-silent` 与 CRD `doodads`/`gadgets`/`widgets.lesson.pyclient.io` 均已删除；讲义本地链接全在、外链 0 条、敏感信息 0 命中。

**更正（2026-09-29 当日二次核验）**：初版标注「异步 `DynamicClient` 未暴露 `server_side_apply`」**是误判**——当时只查了预设 7 个方法名（含并不存在的 `list`），未列全量 `dir()`；实际**存在**且签名与同步版一致。已补做完整实测（[test_ssa_async.py](../assets/lesson06-async/test_ssa_async.py)）并新增第五幕：SSA 异步下**同样静默返回 Status**（缺 `apiVersion`/`kind` → 400；缺 `field_manager` → 422；非法字段 → 500），已交付 `safe_apply` 防护；幂等（重复 apply `resourceVersion` 不变）；冲突 → 409，`force_conflicts=True` 可抢占；字段归属语义（跨 manager 保留 / 同 manager 删除）经对照实验确认**与标准一致**。此次误判与初版「实验污染」合计，本轮共 **2 处测法错误**，均属「核验了但核验方法错」。
