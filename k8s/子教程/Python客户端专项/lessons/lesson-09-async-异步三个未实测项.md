# 课 9 番外：异步的三个未实测项 —— 写共享 · 429 限流 · 重试风暴

> 前置：[课 9：异步客户端与并发](lesson-09-异步客户端与并发.md)、[课 5 错误处理与健壮性](lesson-05-错误处理与健壮性.md)、[课 6 番外 4：重试与指数退避](lesson-06-async4-重试与指数退避.md)
> 环境：k8s v1.34.0（`kind-k8s-c1`）；同步库 `kubernetes` **34.1.0**；异步包 `kubernetes-asyncio` **36.1.0**；`aiohttp` 3.14.3；Python 3.12.3
> 本课所有数字均为本机实测，未实测处已显式标注。

---

## 引子：课 9 留下的三个"没测"

课 9 交付时，我在结尾如实标注了三处**未实测**：

1. 写操作并发共享 client 的安全性（只读共享已测 10/10，写路径没测）
2. apiserver 429 限流触发（测试集群从未触发过）
3. 重试风暴（并发失败后的重试放大效应）

这三处不是"懒得测"，而是各有各的难处：写共享要区分三种语义、429 在本机根本打不出来、重试风暴需要能观测"放大倍数"否则只是讲故事。

这篇番外就是把这三个坑填上。填的过程中，我**又犯了两次测法错误**（本系列第 6、7 次应验"先核验测量方法"），也都一并记下来——因为它们比结论更有教学价值。

**先说三个结论**（详细证据在后面）：

- 写操作共享 client **是安全的**，20/20 成功且值无错乱；同名写撞 409 是服务端语义，不是客户端缺陷
- 429 在本机**打不出来**，且我证明了这不是测法问题（23096 请求 / 2852 QPS 仍为 0，根因是 `global-default` 是 Queue 型不是 Reject 型）
- 重试确实放大流量（最坏 4.11x），但**退避+jitter 的真正价值不在降低放大倍数，而在打散重试**（1ms 窗口内扎堆比例 0.583 → 0.121，差 4.8 倍）

---

## 第一部分：先修两件"课 9 说得不够准"的事

在测新东西之前，先把课 9 的两个表述核准。不是推翻，是**补精确**。

### 1.1 异步方法不是 `async def`，是"返回协程的普通函数"

课 9 说"412 个方法完全同名，迁移只加 `await`"。这句是对的，但**机制**说法容易误导。

我以为异步包里的方法是 `async def`，一查发现不是：

```python
import inspect
from kubernetes_asyncio.client.api import core_v1_api as a

f = a.CoreV1Api.list_namespaced_pod
print(inspect.iscoroutinefunction(f))     # False  ← 竟然不是协程函数
```

我当时就下了个结论"异步包没有协程方法"，**这是错的**（测法错误第 1 次）。

正确的判据是**调用之后**看返回值：

```python
api = a.CoreV1Api(api_client)
r = api.list_namespaced_pod("default")    # 注意：还没 await
print(type(r))                            # <class 'coroutine'>
print(inspect.isawaitable(r))             # True
```

**为什么？** 因为协程是**内层**造的：

```text
list_namespaced_pod              普通 def  → 转发
  └─ list_namespaced_pod_with_http_info   普通 def  → 调用
       └─ self.api_client.call_api(...)   ← 这里才是 async def
```

源码首行实测：

```text
异步 __call_api: iscoroutinefunction=True, 首行 'async def __call_api('
```

所以准确的结论是：**异步包的 API 方法本质是普通函数，靠内层 `__call_api` 是 `async def` 而整体成为可等待对象**。对你的代码没影响（照常 `await`），但影响你**怎么判断一个方法要不要 await**——别用 `iscoroutinefunction` 去看类属性，要调一下看返回值。

顺带把课 9 的结论复核了一遍，仍然成立：

```text
async CoreV1Api 成员数: 412     sync CoreV1Api 成员数: 412
仅异步有: []                    仅同步有: []
逐个方法比对参数名: 412 个方法，参数名有差异的 0 个
```

| 配置函数 | 是否协程 | 备注 |
|---------|---------|------|
| `load_kube_config` | ✅ 是 | 忘 `await` 只给 RuntimeWarning |
| `load_config` | ✅ 是 | |
| `load_incluster_config` | ❌ **不是** | 三个里唯一非协程，不一致陷阱 |

### 1.2 `async_req=True` 在异步包里不是"假异步"，是**完全坏掉**

课 9 说 `async_req=True` 是"假异步"（`pool_threads=1` 导致串行）。实测之后，我觉得这个说法**太温和了**。

在异步包里传 `async_req=True`：

```python
r = api.list_namespaced_pod("default", async_req=True)
print(type(r))                # <class 'multiprocessing.pool.ApplyResult'>
print(inspect.iscoroutine(r)) # False
await r                       # TypeError: object ApplyResult can't be used in 'await' expression
```

**它返回的是多进程线程池的 `ApplyResult`，根本不能 await。**

为什么？看源码（`api_client.py`）：

```python
from multiprocessing.pool import ThreadPool     # ← 异步包里还 import 了这个

def pool(self):
    if self._pool is None:
        self._pool = ThreadPool(self.pool_threads)   # 默认 pool_threads=1
    return self._pool

# async_req=True 时：
return self.pool.apply_async(self.__call_api, (...))   # 把协程塞进线程池
```

**这是从同步包照搬过来的残留机制**：把 `__call_api`（一个协程对象）丢给线程池执行，线程池里的普通线程根本不会 await 它，于是：

- 你拿到 `ApplyResult`，`.get()` 得到的是**那个没被 await 的协程对象本身**，不是结果
- 控制台会刷 `RuntimeWarning: coroutine 'ApiClient.__call_api' was never awaited`

**结论修正**：异步包里的 `async_req=True` 不是"串行版本"，而是**结构性错配**——协程不能塞进线程池。异步并发请用 `asyncio.gather`，永远不要碰 `async_req`。

---

## 第二部分：未实测项 1 —— 写操作并发共享 client 安全吗？

### 2.1 先厘清"共享"的三种语义

课 9 只测了只读共享。写路径要分开看三种情况，混为一谈会得出错结论：

| 场景 | 含义 | 关注点 |
|------|------|--------|
| S1 | 共享 client，并发写**不同**对象 | 客户端状态是否串扰 |
| S2 | 共享 client，并发写**同一**对象 | 必然撞 409，看是不是客户端问题 |
| S3 | 每协程独立 client | 对照基线 |

### 2.2 S1：并发写不同对象（20 个 ConfigMap）

```python
async with aclient.ApiClient() as ac:
    core = aclient.CoreV1Api(ac)
    results = await asyncio.gather(
        *[create_cm(core, f"cm-{i:03d}", f"val-{i}") for i in range(20)],
        return_exceptions=True)
```

实测：

```text
并发 20 次 create（不同名）: 成功 20/20, 耗时 0.037s
回读 21 个, 值不符 0 个
```

**注意"回读 21 个"这个数字**——我写了 20 个，回读却是 21。按铁律，数字对不上先怀疑测量方法，别急着下结论。

查了一下，空命名空间里本来就有 1 个 ConfigMap：

```text
【空 ns 里已有的 ConfigMap】共 1 个:
  - kube-root-ca.crt  (data keys=['ca.crt'])
```

是 k8s **自动注入**的 CA 证书，不是上一轮的残留污染。所以真实结果是 20/20 全对，**值无错乱**（`值不符 0 个`）。

### 2.3 S2：并发写同一对象

```text
并发 10 次 create（同名）: {'OK': 1, 409: 9}
回读: 存在, v=val-0
```

1 个成功 9 个 409——**这是正确的服务端语义**（对象已存在），跟客户端共享不共享无关。课 5 讲过：create 不幂等，冲突要改用 patch。

### 2.4 S3：每协程独立 client（对照）

```text
并发 20 次 create（各自 client）: 成功 20/20, 耗时 0.053s
```

对比 S1 的 0.037s：**独立 client 反而慢 43%**，因为每个 client 都要建一次 TCP 连接 + aiohttp `ClientSession`。

### 2.5 S4：真实控制器场景——并发 patch 同一对象

这才是控制器真正会遇到的（多个 worker 调谐同一个对象的不同字段）：

```text
并发 15 次 patch（同一对象不同 key）: {'OK': 15}
回读 data 键数: 16（含 init=init）
```

**15 次全成功**，因为 patch 不带 `resourceVersion` 时不冲突（课 6 番外 1 也印证过这点）。

### 2.6 结论

**写操作共享 client 是安全的**。20/20 成功、值无错乱、patch 并发 15/15。

但要区分两个层面的"安全"：

- **客户端层面**：安全。aiohttp 连接池本身支持并发复用，协程共用 `ApiClient` 没有状态串扰
- **业务层面**：不安全的是**同名 create**（409）和**带 rv 的 replace**（409），这是服务端语义，与共享无关

另外发现一个真正致命的约束（下一部分详述）：**`ApiClient` 不能跨事件循环使用**。

---

## 第三部分：`ApiClient` 的线程亲和性（顺手抓到的硬坑）

测写共享时顺手验了 client 的生命周期，抓到一个课 9 完全没提到的坑。

### 3.1 `ApiClient` 必须在事件循环内实例化

```python
aclient.ApiClient()     # 在 asyncio.run() 之外调用
# RuntimeError: no running event loop
```

因为 `RESTClientObject` 构造 aiohttp `TCPConnector` 时需要 running loop。**这是异步包和同步包最直观的行为差异**——同步包哪儿都能 new。

### 3.2 不能跨线程跨 loop 复用（真坑）

如果你把 `ApiClient` 传到另一个线程的新事件循环里用：

```text
RuntimeError: Task ... got Future ... attached to a different loop
```

根因：`RESTClientObject` 持有的 `pool_manager`（aiohttp `ClientSession`）**绑定创建时的那个 loop**。属性实测：

```text
rest_client 全部属性: ['server_hostname', 'proxy', 'proxy_headers', 'pool_manager']
pool_manager: ClientSession closed=False
```

**反证**：在线程里**新建** loop 并**新建** client，就正常：

```text
跨线程跨 loop 复用（同一 client）: RuntimeError ... attached to a different loop
线程内新建 loop + 新建 client     : 成功, items=0
```

**实践含义**：多线程 + 异步混合的架构里（比如用 `run_in_executor` 跑同步遗留代码），**每个线程要有自己的事件循环和自己的 client**，不能把主循环的 client 传进去。

### 3.3 `close()` 关的是 `ClientSession`，且幂等

```text
close 前 closed 状态: [False]
close 后 closed 状态: [True]
二次 close: OK（幂等）
close 后调用: RuntimeError: Session is closed
```

关掉之后继续用会明确报错（`Session is closed`），这点比"静默失败"友好。

---

## 第四部分：未实测项 2 —— 429 限流，以及"打不出来"怎么证明

### 4.1 先试图打出来（失败）

三级递进加压：

```text
L1（50 × 3 轮）   : 总请求 150,   QPS 1379.4, 分布 {'OK': 150}
L2（300 × 5 轮）  : 总请求 1500,  QPS 3074.4, 分布 {'OK': 1500}
L3（800 × 5 轮）  : 总请求 4000,  QPS 3562.6, 分布 {'OK': 4000}
```

再加码：

```text
R1（8 秒 × 并发 600）: 总请求 23096, QPS 2852.5, 分布 {'OK': 23096}
R3（瞬时 1200 并发）  : 总请求 1200,  0.31s,      分布 {'OK': 1200}
```

**429 次数：0。**

### 4.2 关键一步：证明这不是"我测错了"

按铁律，数字异常（这里是"零"）先怀疑测量方法。我做了三条独立取证：

**E1. 请求真的打到 apiserver 了吗？**（会不会被缓存/短路）

```text
HTTP status : 200
Audit-Id: c60f5467-9e34-4c7c-b820-bbc24593b80
X-Kubernetes-Pf-Flowschema-Uid: d7f1bc4d-...
```

有 `Audit-Id` 说明请求被 apiserver **真实处理**了。

**E2. 客户端有能力识别 429 吗？**（会不会把 429 吞了）

这里我犯了**测法错误第 2 次**：我拿"读不存在的 namespace"当 404 正对照，结果它没报错：

```text
read 不存在的 ns（list）: HTTP status 200, 返回 V1PodList, items 0 个
```

**空 namespace 名的 list 返回 200 + 空列表，这是 k8s 的正常语义**，根本不是 404。正对照选错了对象。

换成 read 具体对象才对：

```text
read 不存在 pod        : ApiException, status=404
read 不存在 ConfigMap  : ApiException, status=404
```

异常捕获通路正常，`ApiException.status` 能正确读出状态码。所以"零 429"不是因为客户端吞了异常。

**E3. 限流阈值到底是多少？**

读 APF（API Priority and Fairness）配置。这里又踩了个坑——我先用下划线风格去取值，全是 `None`：

```python
spec.get("limited", {}).get("nominal_concurrency_shares")   # None  ← 错
```

CustomObjectsApi 返回的是**驼峰**键。修正后：

```text
catch-all        nominal=5   limitResponse={"type": "Reject"}
global-default   limitResponse={"type": "Queue", "queuing": {"queues": 128, "handSize": 6, "queueLengthLimit": 50}}
workload-high    limitResponse={"type": "Queue", ...}
workload-low     limitResponse={"type": "Queue", ...}
system           limitResponse={"type": "Queue", ...}
node-high        limitResponse={"type": "Queue", ...}
leader-election  limitResponse={"type": "Queue", ...}
exempt           Exempt（不限流）
```

我方请求归属：

```text
→ 命中 FlowSchema: global-default（优先级 9900）
→ 命中 PriorityLevel: global-default
```

**根因找到了**：我落在 `global-default`，它是 **Queue 型**（128 个队列、每个队列上限 50）——**排队等待，而不是拒绝**。唯一 `Reject` 型的 `catch-all` 我命中不了（正常身份请求会先匹配到 `global-default`）。

想用匿名身份打到 `catch-all` 也不行：

```text
匿名访问: ClientConnectorError  → kind 默认拒绝匿名
```

### 4.3 结论（如实标注为环境级）

**在本机 kind 集群上，客户端可打出的量级下无法触发 429。**

这不是缺陷，是环境特性：

- kind 单节点、APF 默认配置宽松
- 我的请求走 `global-default`（Queue 型）→ 过载时排队，不拒绝
- 真实生产集群（多租户、低配额 SA、APF 自定义策略）**完全可能**触发

**所以 429 的处置代码仍要写**，只是本机测不了。给一个可落地的写法：

```python
from kubernetes_asyncio.client.rest import ApiException

async def call_with_429_handling(fn, *args, **kwargs):
    try:
        return await fn(*args, **kwargs)
    except ApiException as e:
        if e.status == 429:
            # 服务端会带 Retry-After（秒）
            retry_after = int(e.headers.get("Retry-After", 1)) if e.headers else 1
            await asyncio.sleep(retry_after)
            return await fn(*args, **kwargs)
        raise
```

> ⚠️ **未实测标注**：上述 429 分支在本机未触发过（0 次），`Retry-After` 的取值方式依据 HTTP 标准与库源码推断，**未经真实验证**。生产使用前需在你的集群上验证。

---

## 4.4 附：亲手造出真 429 的 APF 方案（⚠️ 未执行，仅记录）

> **状态：本方案已勘察但未执行。** 改 APF 配置属**改环境操作**，按协作规矩需你明确点头才落地。此处只把方案与依据记录下来，供你决定。
>
> 勘察脚本：[`_verify_apf_prereq.py`](../assets/lesson09-async/_verify_apf_prereq.py)（2026-09-29 实跑，**全程只读**，未 apply/patch/delete 任何资源）

### 4.4.1 勘察到的硬证据

| 事实 | 实测值 | 对方案的意义 |
|------|--------|--------------|
| `catch-all` 的 `limitResponse.type` | **`Reject`** | 现成的 429 出口，**不必新建 Reject 级别** |
| `catch-all` 的 `nominalConcurrencyShares` | **5** | 并发份额极低，很容易撑爆 |
| `service-accounts` 的 `matchingPrecedence` | 9000 | 新 FS 插 9001~9899 即可抢在 `global-default`(9900) 前命中 |
| `global-default` 的 `matchingPrecedence` | 9900 | 我的请求当前落这里 |
| `catch-all` 的 `matchingPrecedence` | 10000 | 兜底，正常身份到不了这里 |
| 名称占用 | `test-429-reject` / `reject-low` 均**可用** | 无需换名 |
| APF 生效 | P6 端点可取到实时数据 | 未被 `--enable-priority-and-fairness=false` 关掉 |

P6 实时数据再次印证 4.3 的结论：

```text
PriorityLevelName, DispatchedRequests, RejectedRequests
catch-all,         44,                 0
exempt,            226051,             0
global-default,    35910,              0
```

`global-default` 已调度 35910 次、**拒绝 0 次**——它只在排队，不拒绝。`catch-all` 是唯一拒绝型，但我命中不了它。

### 4.4.2 方案 A（推荐）：新建 FlowSchema 复用现成的 `catch-all`

**思路**：`catch-all` 已经是 Reject 型，我只需**把测试流量导过去**，不必新建 PriorityLevel。改动最小、可逆性最好。

```yaml
# ⚠️ 未执行：仅供你审阅
apiVersion: flowcontrol.apiserver.k8s.io/v1
kind: FlowSchema
metadata:
  name: test-429-reject
spec:
  # 9001~9899 之间即可：要 < 9900 才能抢在 global-default 之前命中
  matchingPrecedence: 9500
  priorityLevelConfiguration:
    name: catch-all          # 复用现成的 Reject 型级别
  distinguisherMethod:
    type: ByUser
  rules:
    - subjects:
        - kind: ServiceAccount
          serviceAccount:
            name: default
            namespace: default
      resourceRules:
        - verbs: ["list", "get"]
          apiGroups: [""]
          resources: ["pods", "configmaps"]
```

**验证方式**（SA token 身份下并发打）：

```bash
# 取 SA token
TOKEN=$(kubectl -n default create token default --duration=1h)

# 并发打，观察 429
curl -k -H "Authorization: Bearer $TOKEN" \
  https://127.0.0.1:45145/api/v1/namespaces/default/pods
```

**预期**：`catch-all` 只有 5 个并发份额，稍微并发就该返回 429 + `Retry-After`。

**回退**：`kubectl delete flowschema test-429-reject`（一条命令，无残留）。

### 4.4.3 方案 B：新建专属 Reject 级别（想精确控制配额时）

方案 A 的 `catch-all` 份额是全局共享的（5），如果你想**单独给测试流量一个可控的拒绝阈值**，就用方案 B：

```yaml
# ⚠️ 未执行：仅供你审阅
apiVersion: flowcontrol.apiserver.k8s.io/v1
kind: PriorityLevelConfiguration
metadata:
  name: test-reject-pl
spec:
  type: Limited
  nominalConcurrencyShares: 1      # 极小，一打就拒
  limitResponse:
    type: Reject                   # 关键：Reject 而非 Queue
---
apiVersion: flowcontrol.apiserver.k8s.io/v1
kind: FlowSchema
metadata:
  name: test-429-reject
spec:
  matchingPrecedence: 9500
  priorityLevelConfiguration:
    name: test-reject-pl
  distinguisherMethod:
    type: ByUser
  rules:
    - subjects:
        - kind: ServiceAccount
          serviceAccount:
            name: default
            namespace: default
      resourceRules:
        - verbs: ["list", "get"]
          apiGroups: [""]
          resources: ["pods"]
```

**回退**：删 FS 再删 PL（注意顺序，先 FS 后 PL）。

### 4.4.4 两个方案的取舍

| 维度 | 方案 A（复用 catch-all） | 方案 B（新建 Reject 级别） |
|------|--------------------------|------------------------------|
| 改动量 | 1 个 FlowSchema | 1 PL + 1 FS |
| 回退 | 1 条命令 | 2 条（且有顺序要求） |
| 配额可控 | 否（吃全局 5 份额） | 是（`nominalConcurrencyShares: 1`） |
| 影响面 | 会挤占真实 catch-all 流量 | 隔离，只影响测试 SA |
| 推荐场景 | 只想**见到一次**真 429 | 要**量化**拒绝率/阈值 |

**我的建议**：先 A 后 B。A 用来确认"能造出来"，B 用来做精确实验。

### 4.4.5 ⚠️ 必须注意的三件事

1. **别用 `kubernetes-admin` 做测试身份**——它匹配 `exempt`（优先级 1，Exempt 不限流），你怎么打都不会 429。必须用 SA token 或新建低权限用户。
2. **`matchingPrecedence` 必须 < 9900**，否则仍落 `global-default`（Queue 型），白改。
3. **改完要立刻验证并回退**——APF 配置会影响整个 apiserver 的调度行为，不要长期留在集群里。

### 4.4.6 方案验证后能补上什么

如果执行并获得真 429，可以补齐课 9 番外与课 10 中**目前标注"未实测"**的部分：

- `Retry-After` 的**真实取值形式**（是 `delay-seconds` 还是 `HTTP-date`）→ 课 10 中间件 A2 的 HTTP-date 分支目前只有注入验证
- k8s 的 429 是否**真的带 `Retry-After` 头**（部分实现可能只返回 429 不带头）→ 这直接决定课 10 中间件 `respect_retry_after` 的默认值是否该保持 `True`
- 429 的**响应体结构**（`reason` 字段是否为 `TooManyRequests`）

---

## 第五部分：未实测项 3 —— 重试风暴

### 5.1 怎么测才有意义

重试风暴不能靠"真把 apiserver 压垮"（本机压不垮，上部分已证）。标准做法是**注入故障**：包一层假 apiserver，按概率抛 503，然后统计"打到后端的请求总量"。

这样"放大倍数"就是可观测的：`放大 = 后端请求数 / 业务请求数`。

### 5.2 放大是真实存在的

注入失败率 p=0.5，并发 N=200：

```text
D1 无重试              后端请求   200 (放大 1.00x) 成功  97/200
D2 朴素重试(3次/固定)    后端请求   351 (放大 1.75x) 成功 179/200
D3 退避+jitter(3次)     后端请求   346 (放大 1.73x) 成功 178/200
```

后端已崩时（p=0.9）：

```text
D1 无重试              后端请求   200 (放大 1.00x) 成功  19/200
D2 朴素重试(3次/固定)    后端请求   538 (放大 2.69x) 成功  53/200
D3 退避+jitter(3次)     后端请求   538 (放大 2.69x) 成功  56/200
```

重试次数加码（p=0.9，5 次）：

```text
D2 朴素(5次)         后端请求   820 (放大 4.10x)
D3 退避+jitter(5次)  后端请求   821 (放大 4.11x)
```

**注意一个反直觉的点**：D2 和 D3 的放大倍数**几乎一样**（2.69x vs 2.69x，4.10x vs 4.11x）。

如果你的结论是"jitter 没用"，那就错了——因为我第一版就是这么写的，**这是测法错误第 3 次**。

### 5.3 测法错误：惊群指标失效

我第一版用"1ms/5ms 窗口内最多多少请求"衡量惊群，结果：

```text
D1 无重试              最大同窗 200
D2 朴素重试(3次)        最大同窗 200
D3 退避+jitter(3次)     最大同窗 200
```

**三个都是 200，等于并发数 N**——恒定不变，说明指标根本没有区分力。

原因：每次调用只 sleep 2ms，整个实验在几毫秒内跑完，而分桶窗口是 5ms，**所有请求都落在同一个桶里**。量的是"并发数"，不是"扎堆程度"。

### 5.4 修正：让时间尺度有意义 + 只看重试请求

两处修正：

1. 把模拟 RTT 拉到 20ms（与真实网络往返相当），分桶窗口缩到 1ms
2. **只看重试请求**——首轮齐发是业务行为，不是重试造成的，混在一起会稀释信号

修正后（N=100, p=0.7, rtt=20ms）：

```text
朴素(固定)      总请求 227 (首轮 100, 重试 127)  1ms窗口峰值 70
退避+jitter    总请求 224 (首轮 100, 重试 124)  1ms窗口峰值 12
```

用「峰值 / 重试总数」这个归一判据（越接近 1 越扎堆）：

```text
朴素(固定)      峰值/总数 = 0.583   (重试 127 个)
退避+jitter    峰值/总数 = 0.121   (重试 124 个)
```

**差 4.8 倍。**

### 5.5 真正的结论

**退避+jitter 的价值不在于降低放大倍数（实测证明几乎不降），而在于打散重试的时间分布。**

这个区别很重要：

- **放大倍数**决定"后端多挨多少打"——只由重试次数决定，jitter 救不了
- **扎堆程度**决定"会不会形成尖峰把后端二次打死"——jitter 的核心价值在这里

所以两者要配套用：

```python
# 控制放大倍数：限制重试次数（硬上限）
MAX_ATTEMPTS = 3

# 控制扎堆：指数退避 + full jitter
delay = random.uniform(0, base * (2 ** attempt))
```

课 6 番外 4 在"单对象重试"语境下测过 jitter，本课在"并发 + 后端已崩"语境下复核，**结论一致**。

---

## 速览

| 项 | 结论 | 证据 |
|----|------|------|
| 异步方法本质 | 普通 def，靠内层 `__call_api` 是 `async def` 成为可等待 | `iscoroutinefunction=False` 但调用返回 `coroutine` |
| 判据 | 别用 `iscoroutinefunction` 看类属性，要调用后看返回值 | 探针 2 |
| 参数名 | 412 个方法与同步版**完全一致** | 逐个 signature 比对，差异 0 |
| `async_req=True` | 异步包里返回 `ApplyResult`，**不能 await** | `TypeError: object ApplyResult can't be used in 'await' expression` |
| `ApiClient` 实例化 | **必须在 running loop 内** | `RuntimeError: no running event loop` |
| 跨线程跨 loop | **不可用**，`pool_manager` 绑定创建时的 loop | `attached to a different loop` |
| `close()` | 关 `ClientSession`，幂等，之后调用报 `Session is closed` | closed False→True |
| 写共享（不同对象） | **安全**，20/20，值无错乱 | S1 |
| 写共享（同一对象） | 1 OK + 9×409，服务端语义 | S2 |
| 独立 client | 慢 43%（0.053s vs 0.037s），因重复建连 | S3 |
| 并发 patch | 15/15 成功（不带 rv） | S4 |
| 429 | 本机**打不出来**，23096 请求 / 2852 QPS 仍 0 | R1 |
| 429 根因 | 请求落 `global-default`（Queue 型），非 `catch-all`（Reject 型） | APF 取证 |
| 重试放大 | p=0.9 时 3 次重试放大 2.69x，5 次放大 4.10x | 注入实验 |
| jitter 价值 | **不降**放大倍数，**打散**扎堆（0.583 → 0.121） | 修正后惊群度量 |

---

## 小测

1. 为什么 `inspect.iscoroutinefunction(CoreV1Api.list_namespaced_pod)` 返回 `False`，但你仍然必须 `await` 它？
2. 异步包里 `async_req=True` 会发生什么？为什么它比"串行"更糟？
3. 你想在多线程程序里把主事件循环的 `ApiClient` 传给工作线程用，会发生什么？正确做法是什么？
4. 并发向同一 namespace 创建 20 个**不同名** ConfigMap，共享 client 安全吗？回读数量比你写的多 1 个，为什么？
5. 你压测了 23096 次请求都没见到 429，能直接写"本集群不会限流"吗？还应该做什么？
6. 用"读不存在的 namespace"做 404 正对照，结果没报错。为什么？正确的正对照是什么？
7. 实测显示退避+jitter 与朴素重试的**放大倍数几乎相同**（2.69x vs 2.69x），那 jitter 还有用吗？用在哪？
8. 你用"5ms 窗口内最大请求数"衡量惊群，三种策略结果都是 200（等于并发数）。问题出在哪？怎么修？

<details>
<summary>答案</summary>

1. 因为外层方法是普通 `def`，真正的 `async def` 是内层的 `ApiClient.__call_api`。外层转发调用后返回的就是协程对象。判断要不要 await，要看**调用后的返回值**是否 `isawaitable`，而不是看函数本身是否是协程函数。
2. 返回 `multiprocessing.pool.ApplyResult`，`await` 它直接 `TypeError`。比"串行"更糟是因为它**根本用不了**——协程被丢进线程池不会被 await，你拿到的是没执行的协程，同时刷 `RuntimeWarning: coroutine was never awaited`。
3. 报 `RuntimeError: ... got Future ... attached to a different loop`。因为 `RESTClientObject.pool_manager`（`ClientSession`）绑定创建时的 loop。正确做法：每个线程用自己的事件循环 + 自己的 `ApiClient`。
4. 安全，20/20 成功。多出的 1 个是 k8s 自动注入的 `kube-root-ca.crt`（每个 namespace 都有），不是残留污染。
5. 不能。要先证明"不是测法问题"：① 确认请求真打到 apiserver（看 `Audit-Id`）② 确认客户端能识别目标状态码（用真正会 404 的操作做正对照，注意 list 空 ns 是 200）③ 查明限流配置（读 APF 的 PriorityLevel，注意 CustomObjectsApi 返回**驼峰**键）。确认后才可标为环境级结论，并说明生产仍可能触发。
6. 因为不存在的 namespace 上做 **list** 返回 200 + 空列表，这是 k8s 正常语义。正确的正对照是 **read 一个不存在的具体对象**（`read_namespaced_pod` / `read_namespaced_config_map`），会正常抛 `ApiException(status=404)`。
7. 有用。jitter 不降低总量（放大倍数只由重试次数决定），但把重试**打散**——实测 1ms 窗口内扎堆比例从 0.583 降到 0.121（差 4.8 倍）。它防的是"尖峰二次打死后端"。所以重试次数和 jitter 要配套：次数控制总量，jitter 控制尖峰。
8. 时间尺度不匹配：模拟 RTT 只有 2ms，整个实验几毫秒跑完，而分桶窗口 5ms 过大，所有请求落在同桶，量到的是并发数而非扎堆程度。修正：① 把 RTT 拉到与真实往返相当（20ms）、窗口缩到 1ms ② **只看重试请求**（首轮齐发是业务行为，会稀释信号）③ 用归一判据「峰值/重试总数」而非绝对峰值。

</details>

---

## 本课测法错误记录（第 6、7 次应验铁律）

本课又犯了两次测法错误，与 Kafka 课 13、课 7 番外同型：

| # | 错误 | 表现 | 修正 |
|---|------|------|------|
| 1 | 用 `iscoroutinefunction` 判协程性 | 得"异步包 0 个协程方法"的荒谬结论 | 改为调用后看返回值是否 `isawaitable` |
| 2 | 拿"读不存在的 ns"当 404 正对照 | 没报错，差点得出"异常捕获失效" | 改用 read 具体对象；list 空 ns 本就是 200 |
| 3 | 惊群分桶窗口与 RTT 尺度不匹配 | 三种策略"最大同窗"恒等于并发数 200 | RTT 拉到 20ms、窗口缩到 1ms、只看重试请求 |

**共同根因**：都在"核验了，但核验方法本身是错的"。对应记忆铁律「先核验测量方法，再核验被测对象」。

### 补记：第 10 次（2026-09-29 写 4.4 APF 方案时）

| # | 错误 | 表现 | 修正 |
|---|------|------|------|
| 4 | 用 `资源名 in kubectl输出` 判"资源是否存在" | 核验脚本报"test-429-reject **已被创建**"，一度以为误改了集群 | 改用 `returncode == 0 and "NotFound" not in out` |

**根因**：`kubectl get` 失败时，错误文本里**也含资源名**：

```text
Error from server (NotFound): flowschemas... "test-429-reject" not found
```

`in` 判断分不清"成功返回名字"与"失败说找不到"。复核后确认：FlowSchema 共 11 个、PriorityLevel 共 8 个，均无测试资源，**集群确实未被改动**。

**教训**：**判定命令结果要看退出码，不要看输出文本里有没有关键字**——错误信息和成功信息常常包含同一个词。这与第 1 条（`iscoroutinefunction`）同型：都拿一个"看起来相关"的信号当了结论。

⚠️ 附带教训：这类误报如果信了，会去执行"回退"操作——**在一个没被改动的集群上做删除**。先怀疑核验方法，能避免由误报引发的真实破坏。

---

## 相关

- **异步基础**：[课 9：异步客户端与并发](lesson-09-异步客户端与并发.md)
- **错误处理**：[课 5：错误处理与健壮性](lesson-05-错误处理与健壮性.md)
- **重试退避**：[课 6 番外 4：重试与指数退避](lesson-06-async4-重试与指数退避.md)
- **调谐循环异步化**：[课 6 番外 1：调谐循环的异步改写](lesson-06-async-调谐循环的异步改写.md)
- **动态客户端异步版**：[课 7 番外：动态客户端异步版](lesson-07-async-动态客户端异步版.md)
- **中间件成品**：[课 10：重试中间件工程化](lesson-10-重试中间件工程化.md)
- **返回**：[子教程 overview](../overview.md)

> 本子教程到课 9 及其番外全部完结。推荐方向：① **用 APF 造真 429**——方案已写入本章 [4.4 节](#44-附亲手造出真-429-的-apf-方案️-未执行仅记录)（勘察完毕、**未执行**，属环境改动需你授权）；② 重试策略中间件化——**已在 [课 10](lesson-10-重试中间件工程化.md) 完成**（306 行，48 项断言全通过）。
