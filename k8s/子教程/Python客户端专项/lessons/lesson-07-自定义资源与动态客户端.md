# 课 7：自定义资源与动态客户端

> 目标：前 6 课操作的都是 **Kubernetes 内置资源**（Pod、ConfigMap…）。
> 但 CRD（自定义资源）是 Operator、Gateway API、cert-manager 的地基。
> 内置资源有 `CoreV1Api` 这种 **typed 客户端**，CRD 没有——本课讲怎么操作它们。

**本课环境**：kubernetes **34.1.0** / Python **3.12.3** / kind 集群 **v1.34.0**（`kind-k8s-c1`）
**本课所有结论均在本机实测，凡未实测处均已显式标注。**

---

## 引子：为什么 CRD 需要另一套客户端

内置资源：库里**写死了** `V1ConfigMap`、`V1Pod` 这些模型，编译期就知道结构。

CRD：你的 `Widget`、Traefik 的 `IngressRoute`、Gateway API 的 `HTTPRoute`——
**库不可能预知你的 CRD 长什么样**。

所以有两种办法：

| | 思路 | 代价 |
|---|---|---|
| **`CustomObjectsApi`** | 不管结构，dict 进 dict 出 | 没有类型校验，路径要手写 |
| **`DynamicClient`** | **运行时问 apiserver**"你有哪些资源" | 多一次发现请求 |

### 一眼全局

![课7全局图](../assets/lesson07-intuition.svg)

---

## 第一幕：先看集群里有什么 CRD

```bash
kubectl --context kind-k8s-c1 get crd
```

本机实测有 **50 个** CRD，分四大家族：

```
traefik.io / hub.traefik.io          （26 个：IngressRoute、Middleware…）
gateway.networking.k8s.io            （Gateway API：HTTPRoute、GatewayClass…）
gateway.envoyproxy.io                （Envoy 扩展）
snapshot.storage.k8s.io              （VolumeSnapshot 系列）
```

> 本课主要拿 **`snapshot.storage.k8s.io/v1` 的 `VolumeSnapshot`** 做实验——
> 它是真装好的 CRD，比临时造的更真实。后半段会自建一个 `Widget` CRD。

---

## 第二幕：CustomObjectsApi —— 最朴素的办法

### 2.1 签名：group / version / plural 全靠手写

```python
co = client.CustomObjectsApi()
co.list_namespaced_custom_object(
    group="snapshot.storage.k8s.io",   # ← 手写
    version="v1",                      # ← 手写
    namespace="default",
    plural="volumesnapshots",          # ← 手写（复数！）
)
```

**没有 `kind` 参数，要写的是 `plural`（复数名）。** 这是第一处容易错的地方。

### 2.2 返回值是 dict

实测：

```
返回类型: dict
顶层键: ['apiVersion', 'items', 'kind', 'metadata']
```

取字段就是裸字典操作：

```python
r = co.list_namespaced_custom_object(...)
for item in r['items']:
    print(item['metadata']['name'])
```

### 2.3 集群级资源

```python
co.list_cluster_custom_object(group=GROUP, version="v1", plural="volumesnapshotclasses")
```

实测拿到 `csi-hostpath-snapclass`。

> ⚠️ **命名空间级用 `*_namespaced_*`，集群级用 `*_cluster_*`** —— 两套方法，选错了会 404。

### 2.4 ⚠️ 无类型校验的真实后果

我做了两个实验。

**实验一**：spec 里引用一个不存在的 PVC

```python
spec={"source": {"persistentVolumeClaimName": "no-such-pvc"}}
```

结果：**创建成功**。

> CRD 的 schema 只校验**结构**，不校验**业务引用**。
> PVC 存不存在要等快照控制器去处理，API 层不管。

**实验二**：加一个 CRD schema 里根本没定义的字段

```python
spec={"source": {...}, "totallyMadeUpField": 12345}
```

结果：**创建成功**，但回读：

```
spec 回读: {"source": {"persistentVolumeClaimName": "x"}}
```

> 🚨 **`totallyMadeUpField` 被服务端静默丢弃了。**
> 这就是 **CRD pruning**：未在 `openAPIV3Schema` 中声明的字段会被自动剪掉，
> 不报错、不警告。这是 CRD 调试时最隐蔽的坑之一——
> "我明明传了，怎么没了？"

### 2.5 错误形态（承接课 5）

```
status: 404 | reason: Not Found
body 类型: str
```

和课 5 的 typed 客户端一致（`e.body` 是 `str`）。

---

## 第三幕：DynamicClient —— 运行时发现

### 3.1 核心：不用手写 plural，`resources.get` 帮你找

```python
dyn = DynamicClient(client.ApiClient())
vs = dyn.resources.get(api_version='snapshot.storage.k8s.io/v1', kind='VolumeSnapshot')
print(vs)   # <Resource(snapshot.storage.k8s.io/v1/volumesnapshots)>
```

一次拿到全部元信息：

```
kind:          VolumeSnapshot
name:          volumesnapshots          ← plural 自动推出来
group_version: snapshot.storage.k8s.io/v1
namespaced:    True
verbs:  [delete, deletecollection, get, list, patch, create, update, watch]
short_names:   ['vs']
singular_name: volumesnapshot
```

> `verbs` 直接告诉你**这个资源支持哪些操作**——写通用工具时非常有用。

### 3.2 ⚠️ 坑1：只给 api_version 会炸

```python
dyn.resources.get(api_version='v1')
# ResourceNotUniqueError: Multiple matches found for {'api_version': 'v1'}: [...]
```

`v1` 下有 17 个资源。**必须再给 `kind` 或 `name`。**

要列出全部，用 `search`：

```python
for r in dyn.resources.search(api_version='v1'):
    print(r.kind, r.name, r.namespaced)
```

实测 `v1` 有 **147 条**记录（含 `XxxList` 变体）。

### 3.3 ⚠️ 坑2：kind 写错是另一个错

```python
dyn.resources.get(group=..., api_version='v1', kind='VolumeSnapshotXYZ')
# ResourceNotFoundError: No matches found for {...}
```

> 两个异常不一样：**`ResourceNotUniqueError`（匹配太多）vs `ResourceNotFoundError`（一个都没匹配）**。
> 写通用代码时都要 catch。

### 3.4 LazyDiscoverer：什么时候才真正发请求？

实测：

```
构造 DynamicClient: 0.001s   （Lazy，未发请求）
首次 get:           0.000s
二次 get:           0.000s
```

> ⚠️ **诚实标注**：本机三次计时都在毫秒级，因为 kind 集群响应极快且发现结果被缓存。
> **"首次 get 才触发 /api 发现"这一机制来自 `LazyDiscoverer` 的命名与实现（源码级），
> 但本机未通过耗时差异实测出明显的"首次 vs 缓存"分界。**
> 生产大集群（数百 CRD）上这个差异会非常显著。

### 3.5 返回值：`ResourceInstance`，不是 dict

```python
r = vs.get(namespace="default")
print(type(r))          # ResourceInstance
print(r.items[0].metadata.name)   # ← 属性式访问
d = r.to_dict()                    # ← 转回 dict
```

⚠️ **注意一个反直觉点**：list 返回的 `ResourceInstance` 是个 **List 对象**：

```
kind 属性: VolumeSnapshotList
r.metadata.name = None    ← 没有 name！
```

要取内容用 `r.items`：

```python
for item in r.items:
    print(item.metadata.name)
```

> `ResourceInstance` 只有两个方法：`to_dict()` 和 `to_str()`。
> 字段访问全靠 `instance.metadata.name` 这种**属性链**——
> 属性不存在会抛 `AttributeError` 而不是返回 `None`，这点和 dict 的 `.get()` 不同。

### 3.6 CRUD 实测

```
create  -> ResourceInstance, name=dyn-create-test, rv=2701629
replace -> labels = {'replaced': 'true'}
delete  -> OK
```

---

## 第四幕：🚨 patch 的 415 —— 本课最大的坑

### 4.1 现象

```python
dyn.patch(vs, namespace=NS, name="patchtest", body={"metadata": {"labels": {"a": "1"}}})
```

报：

```
DynamicApiError 415
Reason: Unsupported Media Type
body: b'{"kind":"Status",...,"message":"the body of the request was in an unknown format - accepted media types include: application/json-patch+json, applicati...'
```

### 4.2 根因

`DynamicClient.patch` **不会自动猜 patch 类型**，必须显式传 `content_type`。

而 **`CustomObjectsApi.patch` 不用传**：

```python
co.patch_namespaced_custom_object(..., body={"metadata": {"labels": {"co": "1"}}})
# OK，不需要 content_type
```

> ⚠️ **这是两个客户端最容易被忽略的行为差异。**
> 同样的 patch，`CustomObjectsApi` 能跑，`DynamicClient` 报 415。

### 4.3 解法与第二个发现：CRD 只支持 merge-patch

我逐个试了三种 content_type（在 **VolumeSnapshot** 这个 CRD 上）：

| content_type | 结果 |
|---|---|
| `application/merge-patch+json` | ✅ **OK** |
| `application/strategic-merge-patch+json` | ❌ **415** |
| `application/json-patch+json` | ❌ **415** |

但对**内置资源 ConfigMap** 做同样测试：

| content_type | 结果 |
|---|---|
| `merge-patch+json` | ✅ OK |
| `strategic-merge-patch+json` | ✅ OK |
| `json-patch+json` | ✅ OK |

> 🚨 **CRD 不支持 strategic-merge-patch 和 JSON Patch**（实测 415）。
> 这是 CRD 与内置资源的关键差异：**strategic merge 依赖 Go struct tag，CRD 没有 Go 结构体**。
>
> 所以 **CRD 的 patch 只能用 `application/merge-patch+json`**。

### 4.4 413/415/422 别混淆

顺带记一笔：`content_type="text/plain"` 得到的是

```
DynamicApiError 0
Reason: Cannot prepare a request message for provided arguments
```

`status=0` —— **说明这是客户端侧构造请求失败，压根没发出去**（课 5 的知识在这里复用）。

### 4.5 server_side_apply（dynamic 版）

```python
dyn.server_side_apply(vs, namespace=NS, name="patchtest", body={...}, field_manager="lesson07")
```

实测：

```
SSA -> OK labels = {'ssa': '1'}
managedFields:
  manager=lesson07        operation=Apply     ← 课 3 的 SSA
  manager=OpenAPI-Generator operation=Update
```

---

## 第五幕：🚨 watch 的两种写法不通用

### 5.1 课 6 那套在 dynamic 上会炸

```python
w = watch.Watch()
for e in w.stream(vs.get, namespace=NS, timeout_seconds=4):   # ← 报错
```

```
AttributeError: 'str' object has no attribute 'close'
```

**根因**（源码）：

```python
resp = func(*args, **kwargs)
...
resp.close()          # ← dynamic 返回的不是 urllib3 响应对象
```

`watch.Watch()` 假定 `func` 返回可 close 的响应；dynamic 的资源方法返回的是 `ResourceInstance`。

### 5.2 ✅ 正确写法：`dyn.watch(resource, ...)`

```python
for e in dyn.watch(vs, namespace=NS, timeout=5):
    print(e['type'], e['object'].metadata.name)
```

实测：

```
事件: [('ADDED', 'dw3'), ('MODIFIED', 'dw3'), ('DELETED', 'dw3')]
```

**event 三键和课 6 完全一致**：

```
键: ['object', 'raw_object', 'type']
object 类型 : ResourceInstance
raw_object  : dict
object.kind : VolumeSnapshot
```

### 5.3 ⚠️ 参数名不一样！

```
dyn.watch(vs, namespace=NS, timeout_seconds=2)
# TypeError: DynamicClient.watch() got an unexpected keyword argument 'timeout_seconds'
```

> **`dyn.watch` 用的是 `timeout`，课 6 的 `w.stream` 用的是 `timeout_seconds`。**
> 源码里 `dyn.watch` 内部会转成 `timeout_seconds=timeout` 再调 `watcher.stream`。

### 5.4 优雅停止

源码 docstring 给的做法：

```python
watcher = watch.Watch()
for e in dyn.watch(vs, namespace=NS, timeout=6, watcher=watcher):
    ...
    watcher.stop()
```

实测收到 2 个事件后 `stop()` 正常退出。

> ⚠️ 但别忘记课 6 的结论：`stop()` 只是置标志位，**空闲时不会立刻生效**。
> 这里能退出是因为**有事件**在推。

---

## 第六幕：命名空间级 vs 集群级

### 6.1 用 `namespaced` 属性判断

实测：

| 资源 | namespaced |
|---|---|
| `VolumeSnapshot` | ✅ True |
| `VolumeSnapshotClass` | ❌ False |
| `GatewayClass` | ❌ False |
| `ConfigMap` | ✅ True |
| `Node` | ❌ False |

```python
if vs.namespaced:
    r = dyn.get(vs, namespace="default")
else:
    r = dyn.get(vs)          # 集群级不传 namespace
```

### 6.2 ⚠️ 不传 namespace 不报错，但语义变了

实测对 `VolumeSnapshot`（namespaced=True）不传 namespace：

```
不传 namespace -> 返回 kind: VolumeSnapshotList
items 数: 0
```

**没报错**，但它变成了**跨所有 namespace 的查询**。

> ⚠️ 这是静默的语义切换：你以为在查 default，实际在查全集群。
> 权限够的话会把所有 ns 的对象都拉回来。

---

## 第七幕：自建一个 CRD，看完整生命周期

前面用的都是现成 CRD。现在从头建一个 `Widget`。

### 7.1 安装 CRD

用 `ApiextensionsV1Api`：

```python
apiext.create_custom_resource_definition(body={
    "spec": {
        "group": "lesson07.example.com",
        "names": {"plural": "widgets", "singular": "widget",
                  "kind": "Widget", "shortNames": ["wg"]},
        "scope": "Namespaced",
        "versions": [{
            "name": "v1", "served": True, "storage": True,
            "schema": {"openAPIV3Schema": {
                "type": "object",
                "properties": {"spec": {
                    "type": "object",
                    "properties": {
                        "color": {"type": "string"},
                        "size": {"type": "integer", "minimum": 1, "maximum": 100}},
                    "required": ["color"]}}}},
            "subresources": {"status": {}},
        }]}})
```

安装后要**等 Established**：

```python
for _ in range(30):
    c = apiext.read_custom_resource_definition(name=crd_name)
    if any(cd.type == "Established" and cd.status == "True" for cd in (c.status.conditions or [])):
        break
    time.sleep(0.5)
```

实测 `CRD Established ✓`。

> ⚠️ **不等 Established 就创建 CR 会 404**——因为 apiserver 还没注册这个 endpoint。

### 7.2 schema 校验实测（三种）

**① 数值超范围**

```python
spec={"color": "blue", "size": 999}     # schema 规定 max=100
```

```
-> 422 Unprocessable Entity
   message: Widget... "w-bad" is invalid: spec.size: Invalid value: 999: spec.size in body should be less than or equal to 100
   causes : [{'reason': 'FieldValueInvalid', 'message': '...', 'field': 'spec.size'}]
```

> 课 5 说过：**422 是唯一带 `details.causes[].field` 的**。这里正是它最有用的场景——
> CRD schema 校验失败会精确告诉你是哪个字段。

**② 缺必填字段**

```
-> 422 Unprocessable Entity
   message: Widget... "w-nocolor" is invalid: spec.color: Required value
```

**③ 未知字段被静默丢弃**

```python
spec={"color": "green", "bogusField": "abc"}
```

```
创建成功，回读 spec: {'color': 'green'}
>>> bogusField 是否被丢弃: True
```

### 7.3 status 子资源

**关键设计**：`status` 是**独立子资源**，主资源 patch 改不了它。

我实测了三步：

**第一步**：CRD 只声明了 `spec`，没声明 `status`

```
GET 顶层键: ['apiVersion', 'kind', 'metadata', 'spec']
status: None
status 子资源 patch 后 -> 仍是 None
```

> ⚠️ **status 同样受 pruning 约束**——没在 schema 里声明就存不进去。

**第二步**：给 CRD 补上 `status` 的 schema

⚠️ 这里踩了个 Python 模型的坑：

```python
v.schema.open_api_v3_schema     # AttributeError！
```

正确属性名是 **`open_apiv3_schema`**（不是 `open_api_v3_schema`）：

```
V1CustomResourceValidation 属性: [..., 'open_apiv3_schema', ...]
```

> 更省事的做法：**直接用 dict patch CRD**，绕开模型属性名：
> ```python
> apiext.patch_custom_resource_definition(name=crd, body={"spec": {"versions": [...]}})
> ```
> 这是我实际采用并成功的方式。

**第三步**：再写 status

```
status 子资源 patch -> {'phase': 'Ready'}
GET status: {'phase': 'Ready'}
```

**对照实验**：用主资源 patch 试图改成 `Hacked`

```
主资源 patch 写 status -> {'phase': 'Ready'}   ← 响应里看到的是旧值
回读 status: {'phase': 'Ready'}                ← 没变成 Hacked
```

> ✅ **status 子资源确实生效**：主资源 patch 改不动 status。
> 这是 Operator 的标准设计——控制器用 status 子资源回报状态，用户改 spec 不会误伤。

---

## 第八幕：选型决策

### 8.1 实测对照表

| 维度 | `CustomObjectsApi` | `DynamicClient` |
|---|---|---|
| 返回值 | `dict` | `ResourceInstance` |
| 字段访问 | `r['items'][0]['metadata']['name']` | `r.items[0].metadata.name` |
| 资源发现 | ❌ 手写 group/version/plural | ✅ 运行时发现，还能拿 `verbs` |
| **patch** | ✅ 不传 `content_type` 即可 | 🚨 **必须传，否则 415** |
| **watch** | 用 `watch.Watch().stream` | 🚨 **必须用 `dyn.watch(resource, timeout=)`** |
| 404 异常 | `ApiException(404)`，`e.body` 是 **`str`** | `NotFoundError(404)`，`e.body` 是 **`bytes`** |

> 最后一行**印证了课 5 的伏笔**：dynamic 的 `e.body` 是 `bytes`，要 `.decode()` 或 `json.loads`。

### 8.2 什么时候用哪个

**用 `CustomObjectsApi` 当**：

- 资源类型**固定且已知**（你就操作这一种 CRD）
- 想要**最小依赖**、最快上手
- 写一次性脚本、CI 里的胶水代码

**用 `DynamicClient` 当**：

- 要写**通用工具**（不知道用户集群里有什么 CRD）
- 需要**运行时判断**资源是否 namespaced、支持哪些 verbs
- 要遍历多种资源做批量操作

**两者都别用，改用 typed 客户端当**：

- 资源是**内置资源**（Pod、ConfigMap…）——用 `CoreV1Api`，有类型补全和 IDE 提示

### 8.3 request_timeout

两者都支持（大纲要点）：

```python
co.list_namespaced_custom_object(..., _request_timeout=2)
dyn.get(vs, namespace=NS, _request_timeout=2)
```

实测都正常返回。

> ⚠️ **诚实标注**：本机 kind 集群响应在 10ms 内，`_request_timeout` 的**超时触发**未能实测
> （试了 `_request_timeout=0.001` 也只用了 0.001s 就成功返回，未触发超时）。
> 超时参数**被正确接受**（不报 TypeError）已验证；**真实超时行为**承接课 4 的结论——
> 那里实测过 `总耗时 ≈ 超时 × (retries+1)`。

---

## 收束：三张地图

### 地图一：本课五个硬结论

1. **`CustomObjectsApi` 用 `plural`，不是 `kind`**；`DynamicClient` 用 `kind` 且必须配 `api_version`
2. **CRD 的未知字段会被静默 prune**——不报错，回读就没了
3. 🚨 **`DynamicClient.patch` 必须传 `content_type="application/merge-patch+json"`**，`CustomObjectsApi` 不用
4. 🚨 **CRD 不支持 strategic-merge-patch / JSON Patch**（实测 415），只有 merge-patch
5. 🚨 **`watch.Watch()` 不能用于 dynamic**，必须用 `dyn.watch(resource, timeout=)`（注意是 `timeout`）

### 地图二：异常对照（承接课 5）

| 场景 | `CustomObjectsApi` | `DynamicClient` |
|---|---|---|
| 资源不存在 | `ApiException(404)` | `NotFoundError(404)` |
| `e.body` 类型 | `str` | **`bytes`** |
| 匹配太多 | — | `ResourceNotUniqueError` |
| 一个没匹配 | — | `ResourceNotFoundError` |
| schema 校验失败 | `ApiException(422)` + `causes[].field` | `UnprocessibleEntityError(422)` |
| patch 类型不对 | — | `DynamicApiError(415)` |

### 地图三：写 CRD 代码的检查清单

1. `plural` 写对了吗？（不是 `kind`）
2. 命名空间级 vs 集群级，方法选对了吗？
3. CRD schema 里**声明了**你要写的每个字段吗？（否则被 prune）
4. `status` 也在 schema 里吗？用**子资源**写吗？
5. `DynamicClient.patch` 带 `content_type` 了吗？
6. 用 merge-patch 了吗？（CRD 不支持另两种）
7. watch 用 `dyn.watch` 而不是 `watch.Watch` 了吗？参数名是 `timeout` 吗？
8. `e.body` 是 `bytes` 吗？（dynamic）——要不要 `.decode()`

---

## 本课实测环境说明

- 自建 CRD `widgets.lesson07.example.com` 与测试 CR `w1` **保留在集群中**（后续课程可能复用）
- 临时对象 `bad-field-test` / `unknown-field-test` / `patchtest` / `pt2-4` / `dw1-6` / `dyn-create-test` 均已删除
- ⚠️ **清理待办**：CRD `widgets.lesson07.example.com` 与 `default/w1` 未删除

---

## 延伸阅读

- [官方 dynamic-client 示例目录](https://github.com/kubernetes-client/python/tree/master/examples/dynamic-client)
- [Kubernetes：Custom Resources 概念](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/)
- [CRD 结构定义（apiextensions.k8s.io/v1）](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/)
- [CRD 的 field pruning](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/#pruning-versus-preserving-unknown-fields)
- [status 子资源设计](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/#subresources)

> ✅ 以上 5 条链接**已于 2026-09-28 实测全部返回 200**。

---

## 课程导航

- **上一课**：[课 6：watch · informer · 调谐循环](lesson-06-watch与informer.md)
- **下一课**：课 8：工程化：日志 · exec · 权限
- **番外**：[动态客户端异步版](lesson-07-async-动态客户端异步版.md)（异步下 create/patch/replace 会**静默返回 Status** 而不抛异常，需 `safe_patch` 防护）
- **返回**：[子教程 overview](../overview.md) ｜ [课程目录](../../../02-课程目录.md)

---

## 小测

1. `CustomObjectsApi` 的参数是 `kind` 还是 `plural`？`DynamicClient.resources.get` 呢？
2. CRD 中未在 schema 声明的字段会怎样？会报错吗？
3. `DynamicClient.patch` 不传 `content_type` 会怎样？`CustomObjectsApi.patch` 呢？
4. CRD 支持哪几种 patch 类型？内置资源呢？
5. `watch.Watch().stream(vs.get, ...)` 为什么报错？正确写法是什么？
6. `dyn.watch` 的超时参数叫什么？和课 6 的有什么不同？
7. dynamic 的 404 是什么异常类型？`e.body` 是什么类型？（对比课 5）
8. 怎么判断一个资源是命名空间级还是集群级？
9. namespaced 资源调用时不传 namespace，会报错吗？实际语义是什么？
10. status 子资源的作用是什么？主资源 patch 能改到 status 吗？（实测结论）

<details>
<summary>答案</summary>

1. `CustomObjectsApi` 用 **`plural`**（复数名，如 `volumesnapshots`），参数列表是 `group/version/namespace/plural`；`DynamicClient.resources.get` 用 **`kind`**（如 `VolumeSnapshot`），且**必须同时给 `api_version`**。
2. **被服务端静默 prune（剪掉）**——不报错、不警告，创建成功但回读时字段已经没了。实测传 `totallyMadeUpField: 12345`，回读 `spec` 只剩声明过的字段。解决办法是在 CRD 的 `openAPIV3Schema` 里声明该字段。
3. `DynamicClient.patch` 不传会报 **`DynamicApiError 415 Unsupported Media Type`**；`CustomObjectsApi.patch` **不用传**，默认就能工作。这是两者最容易踩的行为差异。
4. CRD **只支持 `application/merge-patch+json`**（实测 `strategic-merge-patch+json` 和 `json-patch+json` 都返回 415）；内置资源（如 ConfigMap）**三种都支持**。原因是 strategic merge 依赖 Go struct tag，CRD 没有 Go 结构体。
5. 报 `AttributeError: 'str' object has no attribute 'close'`。因为 `watch.Watch().stream` 内部会对返回值调用 `resp.close()`，而 dynamic 的资源方法返回的是 `ResourceInstance` 而非 urllib3 响应对象。正确写法：**`dyn.watch(resource, namespace=..., timeout=N)`**。
6. **`timeout`**（单数）。课 6 的 `w.stream` 用 **`timeout_seconds`**。传错会 `TypeError: unexpected keyword argument`。`dyn.watch` 内部会把 `timeout` 转成 `timeout_seconds` 再调 `watcher.stream`。
7. **`NotFoundError`**（`ApiException` 的子类），**`e.body` 是 `bytes`**——这印证了课 5 的伏笔：typed 客户端的 `e.body` 是 `str`，dynamic 的是 `bytes`，需要 `.decode()` 或 `json.loads` 处理。
8. 用 **`Resource.namespaced`** 属性：`dyn.resources.get(...).namespaced` 返回 `True`/`False`。集群级资源（如 `VolumeSnapshotClass`、`Node`）调用时不传 `namespace`。
9. **不报错**，但语义变成**跨所有 namespace 的全量查询**——你以为在查 default，实际在查全集群。这是静默的语义切换，权限够时会拉回所有 ns 的对象。
10. status 作为独立子资源，**主资源 patch 改不动它**（这样用户改 spec 不会误伤控制器写的状态）。实测：主资源 patch 试图把 `phase` 改成 `Hacked`，回读仍是 `Ready`。前提是 CRD 里要 `subresources: {status: {}}` **且**在 schema 里声明 `status` 字段——否则 status 也会被 prune 掉（实测第一步就遇到了）。

</details>

---

## 接力提示词

```
继续学 Kubernetes Python 客户端专项，我的学习档案在 k8s/子教程/Python客户端专项/overview.md，
刚学完课 7《自定义资源与动态客户端》（知识点：CustomObjectsApi 用 plural 而 DynamicClient 用 kind、
CRD 未知字段被静默 prune、DynamicClient.patch 必须传 content_type 否则 415 而 CustomObjectsApi 不用、
CRD 只支持 merge-patch 不支持 strategic/json patch、watch.Watch() 不适用于 dynamic 必须用
dyn.watch(resource, timeout=)、dynamic 404 是 NotFoundError 且 e.body 为 bytes、
namespaced 属性判级与不传 namespace 的静默语义切换、CRD status 子资源与 schema pruning），
请按大纲继续讲解课 8《工程化：日志 · exec · 权限》。
注意：课 8 大纲中"读 metrics（本机 metrics-server 实测可用）"的基线已失效——
metrics-server 当前 CrashLoopBackOff，开课前需先确认是否修复或改为仅讲原理。
```
