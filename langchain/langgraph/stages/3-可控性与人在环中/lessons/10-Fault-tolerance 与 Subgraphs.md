# 课 10：Fault-tolerance 与 Subgraphs

> 所属阶段：阶段 3《可控性与人在环中》｜ 水平：进阶 ｜ 本课知识点：节点级容错 / 子图与状态隔离
> 故事情节：故事主线「敢让它上生产」的第三章——会暂停会回放了，还得不怕错、能拆开
> 📖 结论已按官方文档核对（核对于 2026-10 ｜ 来源：LangGraph Fault tolerance / Subgraphs 官方文档 + 本机 langgraph 1.2.11 源码与实测）

## 🎯 本课目标

- 会给单个节点配 **超时 / 重试 / 错误处理**，让一个节点失败不炸掉整张图
- 会用 **子图** 拆分复杂流程，并说清 **状态隔离** 到底隔离了什么、**排障代价** 在哪

---

## 第一幕：起源与场景引入

课 9 结尾留了个伏笔：

> "**子图有自己的 `checkpoint_ns`**（实测主图是 `''`），历史会再深一层。"

今天兑现它——顺带解决一个更急的问题。

**场景**：流程上了生产，然后事故来了：

1. **"外部接口抖了一下，整单就报错退出了，前面的活全白干。"**——一次网络抖动 = 整单重来。
2. **"我想给它加个重试，可配了 `RetryPolicy` 它一次都不重试。"**——配置写了，行为没变。
3. **"流程越来越长，改一个节点要动整张图，谁都不敢碰。"**——单体图改不动了。

这三个恐惧分两类：**前两个是"扛不住错"**，**第三个是"拆不开"**。

> 🎬 **场景**：前两个是容错问题（一次抖动不该整单废掉），第三个是结构问题（大图改不动）。

> 📌 **一句话本质**：**容错靠 `add_node` 的三个 per-node 参数（`/`）：`retry_policy` 决定"失败了再试几次"、`error_handler` 决定"试完了还不行就走兜底"、`timeout` 决定"多久算不行"——三者可以按节点单独配，也可以用 `set_node_defaults` 全图默认；子图则是**把编译好的图当节点挂上去**，父子之间**只传两边 schema 都声明了的字段**。
>
> ⚖️ **处境对照**：不知道这层，错误会直接冒泡炸掉整跑（前面的状态白算），或者你自己写 try/except 把重试逻辑和业务逻辑混在一起；知道了，一个节点的抖动在节点内就被消化掉——**代价是三条硬约束**：① **默认 `retry_on` 把 `ValueError`/`RuntimeError`/`TypeError` 一律视为"代码 bug"不重试**（配了 `max_attempts=3` 也只跑 1 次）；② **`error_handler` 的签名是 `(state)` 单参数**，写成 `(state, error)` 直接 `TypeError`；③ **同步节点配 `timeout` 在 `compile()` 阶段就抛 `ValueError`**——只有 async 节点才支持。

---

## 第二幕：认知冲突

外部接口抖动，你给它配了重试：

::: code-group

```python [Python]
from langgraph.types import RetryPolicy

def call_api(state):
    raise ValueError("接口超时了")          # 模拟外部故障

builder.add_node("call_api", call_api, retry_policy=RetryPolicy(max_attempts=3))
graph = builder.compile()
graph.invoke({"log": [], "n": 0})
```

```typescript [TypeScript]
import { Annotation, END, START, StateGraph } from "@langchain/langgraph";

const S = Annotation.Root({ log: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }), n: Annotation<number>({ reducer: (_p, x) => x, default: () => 0 }) });

const callApi = () => { throw new Error("接口超时了"); };   // 模拟外部故障

new StateGraph(S)
  .addNode("call_api", callApi, { retryPolicy: { maxAttempts: 3, initialInterval: 500, jitter: false } })
  .addEdge(START, "call_api").addEdge("call_api", END)
  .compile()
  .invoke({ log: [], n: 0 });
```

:::

你以为会重试 3 次。**实际**：

```
── Python ──
ValueError: 接口超时了
节点实际执行次数: 1        ← 一次都没重试！

── TypeScript ──
Retrying task "call_api" after 500.00ms (attempt 1) ...
Retrying task "call_api" after 1000.00ms (attempt 2) ...
Error: 接口超时了
节点实际执行次数: 3        ← 反而重试满了！
```

> 🔴 **第一个大坑先说清**：Python 抛 `ValueError` **一次都不重试**，TypeScript 抛普通 `Error` **重试到用尽**——**两边的默认 `retry_on` 是相反的**。（注意：这里的"重试到用尽"是**上面这段代码已经配了 `retryPolicy`** 之后的默认行为；什么都不配则一次都不重试，见后文「验证零」。）Python 是"白名单挑外部故障"（`ValueError` 认为是代码 bug 直接放弃），TS 是"黑名单排除明确不该重试的"（除 `AbortError`、`GraphValueError`、`ECONNABORTED`、400/401/402/403/404/405/406/407/409、`insufficient_quota` 之外**一律重试**）。下文知识点 1 会把两张表都列出来。

**接着你给同步节点配超时**：

::: code-group

```python [Python]
builder.add_node("slow", slow_node, timeout=0.5)
builder.compile()          # ← 这里就炸了
```

```typescript [TypeScript]
new StateGraph(S)
  .addNode("slow", slowNode, { timeout: 100 })   // 单位是毫秒，不是秒
  .compile();                                    // ← 这里不炸，能过
```

:::

```
── Python ──
ValueError: Node timeouts are only supported for async nodes because
sync Python execution cannot be safely cancelled in-process. Node 'b' is sync.

── TypeScript ──
compile() -> ok
invoke  -> NodeTimeoutError: Node "b" exceeded its run timeout of 100ms (elapsed: 302ms).
```

> 🔴 **第二个大坑**：Python **同步节点在 `compile()` 就拦下**，TS **编译期放行，运行期才超时**——因为 Node.js 用 `AbortSignal` 做协作式取消，同步阻塞代码停不下来但写出的结果会被丢弃。TS 的 `timeout` 单位是**毫秒**（`runTimeout`），Python 是**秒**。

> ❓ **问题**：**配置明明写了，为什么两边行为差这么多？默认 `retry_on` 到底怎么挑异常？子图又隔离了什么？**

---

## 第三幕：层层揭示

### 一眼全局图（进入细节前先看一眼）

![一处出错就得整单重来，还是重试一下就好](../assets/langgraph-fault-tolerance.svg)

> 看图：上面**一个环节卡住，整单就废了**——前面接单的活全白干，后面两步没轮到；下面**卡住的那一环自己重试**，别的照走，真不行再走兜底。**右边那块是第三幕第二半：大流程拆成子流程，代价是外面看不到里面。**

### 本课地图（分几步走）

| 步 | 这一步要解决什么（人话） | 对应知识点 |
|:--:|------------------------|-----------|
| 1 | 一个节点失败了，怎么让它自己重试 / 兜底 / 别拖太久 | 知识点 1：节点级超时 / 重试 / 错误处理 |
| 2 | 流程太大改不动，怎么拆，拆完的代价是什么 | 知识点 2：子图与状态隔离 |

---

### 知识点 1：节点级超时 / 重试 / 错误处理

> 🧭 第 1/2 步｜承接：第二幕"配了不生效" → 本步：搞清三个参数各自的语义与硬约束
> 本知识点关键点：per-node 配置怎么给 / RetryPolicy 的策略项 / 错误处理器与兜底分支

#### 一句话定义

**`add_node` 直接接受 `retry_policy` / `error_handler` / `timeout` 三个参数（也可 `set_node_defaults` 全图默认），节点级配置覆盖全局默认；三者组合成"失败先重试 → 试完还不行走兜底 → 太久算失败"这一条容错链。**

#### 直觉建立（类比）

把它想成**快递站点**：

- **重试**（`RetryPolicy`）：快递员第一次上门没人，他会**再试几次**（`max_attempts`），每次**隔得越久**（`initial_interval` × `backoff_factor`）；
- **兜底**（`error_handler`）：试完还不行，就**放快递柜**——不叫整单作废；
- **超时**（`timeout`）：等太久（比如超过 30 秒）就算这次失败。

> 💡 **类比的边界**：真实机制里 ① 快递员**挑单**——默认的 `retry_on` 只认"外部故障"（`ConnectionError`、HTTP 5xx、不认识的自定义异常），**你抛 `ValueError` 他看都不看就放弃**（认为是收件人地址写错了，再送也没用）；② 兜底员**只收包裹不收异常**——`handler` 拿到的**只有 state**，错误要从 `config` 里翻；③ 超时员**只管异步任务**——同步的他管不了（Python 掐不干净），索性在 `compile()` 就告诉你"这个我接不了"。

#### 核心原理

**三个参数的位置**（Python 源码 `langgraph/graph/state.py:677`｜TS 类型 `dist/graph/state.d.ts` 的 `NodePolicyOptions`）：

::: code-group

```python [Python]
builder.add_node(
    "call_api", call_api,
    retry_policy=RetryPolicy(...),     # 失败了再试几次
    error_handler=my_fallback,         # 试完还不行就走它
    timeout=5.0,                       # 太久算失败（秒）
)
```

```typescript [TypeScript]
new StateGraph(S).addNode(
  "call_api", callApi,
  {
    retryPolicy: { maxAttempts: 3 },   // 失败了再试几次
    errorHandler: myFallback,          // 试完还不行就走它
    timeout: 5000,                     // 太久算失败（毫秒）
  },
);
```

:::

或者全图默认（`set_node_defaults` / `setNodeDefaults`），节点级覆盖全局：

::: code-group

```python [Python]
builder.set_node_defaults(retry_policy=RetryPolicy(max_attempts=3))
builder.add_node("b", node_b, retry_policy=RetryPolicy(max_attempts=2))   # 覆盖
```

```typescript [TypeScript]
new StateGraph(S)
  .setNodeDefaults({ retryPolicy: { maxAttempts: 3 } })
  .addNode("b", nodeB, { retryPolicy: { maxAttempts: 2 } });               // 覆盖
```

:::

实测：**全局 5、节点级 2 → 实际执行 2 次**（节点级生效，两侧一致）。

---

##### `RetryPolicy` 的字段（Python 六个｜TS 七个）

::: code-group

```python [Python]
RetryPolicy(
    initial_interval=0.5,      # 第一次重试前等多久（秒）
    backoff_factor=2.0,        # 每次等待 × 几倍
    max_interval=128.0,        # 等待上限
    max_attempts=3,            # 最多跑几次（含第一次）
    jitter=True,               # 是否加随机抖动
    retry_on=default_retry_on, # 哪些异常才重试
)
```

```typescript [TypeScript]
{
  initialInterval: 500,        // 第一次重试前等多久（毫秒）
  backoffFactor: 2,            // 每次等待 × 几倍
  maxInterval: 128_000,        // 等待上限（毫秒）
  maxAttempts: 3,              // 最多跑几次（含第一次）
  jitter: true,                // 是否加随机抖动
  retryOn: (e) => boolean,     // 哪些异常才重试
  logWarning: true,            // ← TS 独有：是否打印 "Retrying task ..." 日志
}
```

:::

> ⚠️ **单位是最大的认知陷阱**：Python 全用**秒**（`0.5` = 500ms），TS 全用**毫秒**（`500` = 500ms）。把 Python 的 `initial_interval=0.5` 直译成 `initialInterval: 0.5`，在 TS 里就是等 0.5 毫秒——等于没等。
> ⚠️ **TS 多一个 `logWarning`**（默认 `true`）：每重试一次都会往控制台打 `Retrying task "b" after 500.00ms (attempt 1) ...`。生产里嫌吵可以关掉，但排障时这行日志很有用。

**`max_attempts` 含第一次**（实测）：

```
max_attempts=1 -> 实际执行 1 次
max_attempts=2 -> 实际执行 2 次
max_attempts=3 -> 实际执行 3 次
```

**退避间隔**（实测，`jitter=False` 时精确）：

```
initial=0.3 backoff=2 -> 实测间隔 ['0.30s', '0.60s', '1.20s']
```

> ⚠️ **`jitter` 默认 `True`**，所以实测间隔会抖：`['0.50s', '0.92s', '1.34s']`。想验证退避公式要显式关掉。

---

##### 🔴 默认 `retry_on` 才是第二幕的答案（而且两侧逻辑相反）

Python 源码 `langgraph/_internal/_retry.py:1`｜TS 源码 `dist/pregel/retry.js` 的 `DEFAULT_RETRY_ON_HANDLER`：

::: code-group

```python [Python]
# Python：白名单思路——明确列出"代码 bug 类"，命中就不重试
def default_retry_on(exc: Exception) -> bool:
    if isinstance(exc, ConnectionError):
        return True
    if isinstance(exc, httpx.HTTPStatusError):
        return 500 <= exc.response.status_code < 600
    if isinstance(exc, requests.HTTPError):
        return 500 <= exc.response.status_code < 600 if exc.response else True
    if isinstance(exc, (ValueError, TypeError, ArithmeticError, ImportError,
                        LookupError, NameError, SyntaxError, RuntimeError,
                        ReferenceError, StopIteration, StopAsyncIteration, OSError)):
        return False          # ← 一律不重试
    return True               # ← 不认识的异常反而重试
```

```typescript [TypeScript]
// TS：黑名单思路——只有明确"不该重试"的才放弃，其余一律重试
const DEFAULT_RETRY_ON_HANDLER = (error: any) => {
  if (error.message.startsWith("Cancel") || error.message.startsWith("AbortError")
      || error.name === "AbortError") return false;      // 取消 / 中断
  if (error.name === "GraphValueError") return false;    // 图结构错误
  if (error?.code === "ECONNABORTED") return false;      // 客户端主动放弃
  const status = error?.response?.status ?? error?.status;
  if (status && [400, 401, 402, 403, 404, 405, 406, 407, 409].includes(+status)) return false;
  if (error?.error?.code === "insufficient_quota") return false;   // 额度用尽
  return true;                                           // ← 其余（含 ValueError 类）全重试
};
```

:::

实测对照表：

| 抛的异常 | Python 默认重试吗 | TypeScript 默认重试吗 |
|---|---|---|
| `ValueError('x')` / `new Error('x')` | ❌ 不重试 | ✅ 重试 |
| `RuntimeError('x')` / `new RangeError('x')` | ❌ 不重试 | ✅ 重试 |
| `TypeError('x')` | ❌ 不重试 | ✅ 重试 |
| `KeyError('x')` / `TypeError` 派生 | ❌ 不重试 | ✅ 重试 |
| `OSError('x')` | ❌ 不重试 | ✅ 重试 |
| `ConnectionError('x')` / `code: "ECONNREFUSED"` | ✅ 重试 | ✅ 重试 |
| HTTP 500 | ✅ 重试 | ✅ 重试 |
| HTTP 404 | ❌（非 5xx） | ❌（在黑名单里） |
| 自定义 `NetError('x')` | ✅ 重试（不认识 → `True`） | ✅ 重试（不在黑名单 → `True`） |

> 🔑 **设计意图相同，实现相反**：Python 把 `ValueError`/`TypeError` 当**代码写错了**（重试一百次也一样错），于是显式点名排除；TS 没法可靠区分"哪些是代码 bug"，索性只排除**语义上确定不该重试**的（取消、图结构错误、4xx、额度耗尽），其余交给调用方自己用 `retryOn` 收窄。
> ⚠️ **对写代码的影响**：**同一段"抛 Error 让节点失败"的代码，Python 跑 1 次、TS 跑 3 次**。移植时必须回头看 `retryOn`——TS 侧想"只重试网络抖动"，得自己写 `retryOn: (e) => e?.code === "ECONNRESET"`。

**想让 Python 的 `ValueError` 也重试 / 想让 TS 收窄？显式指定**：

::: code-group

```python [Python]
RetryPolicy(max_attempts=4, retry_on=ValueError)                    # 指定类型
RetryPolicy(max_attempts=5, retry_on=lambda e: "可重试" in str(e))   # 用函数判断
```

```typescript [TypeScript]
{ maxAttempts: 4, retryOn: (e) => e instanceof TypeError }              // 指定类型
{ maxAttempts: 5, retryOn: (e) => String(e.message).includes("可重试") }  // 用函数判断
{ maxAttempts: 5, retryOn: () => false }                                // 全关：只跑 1 次
```

:::

实测：Python `retry_on=ValueError` 后抛 `ValueError` 的节点执行 3 次后成功；TS `retryOn` 传 `TypeError` 判断或函数判断同样执行 3 次成功，传 `() => false` 则执行 1 次。

> ⚠️ **TS 的 `retryOn` 只接受函数**（`(e: any) => boolean`），**不能直接传异常类**——`retryOn: TypeError` 是类型错误。想要"按类型"必须写成 `(e) => e instanceof TypeError`。

**重试用尽后**：两侧都抛**原始异常**（不是包装异常）。实测 `NetError: 永远失败`。

---

##### `error_handler`：兜底不炸图（🔴 两侧签名完全不同）

::: code-group

```python [Python]
def handler(state):                    # ← 只有一个参数！
    return {"log": state.get("log", []) + [f"兜底"], "n": -1}

builder.add_node("b", risky, retry_policy=RetryPolicy(max_attempts=2),
                 error_handler=handler)
```

```typescript [TypeScript]
// ← 三个参数：state, error, config
const handler = (state: State, error: NodeError, config?: LangGraphRunnableConfig) => {
  return { log: [...(state.log ?? []), "兜底"], n: -1 };
};

new StateGraph(State).addNode("b", risky, {
  retryPolicy: { maxAttempts: 2 },
  errorHandler: handler,
});
```

:::

实测：

```
── Python ──
handler 收到 state={'log': ['ok'], 'n': 1}
结果: ['ok', '兜底1']  n=-1
节点 b 执行 3 次        ← 先重试，用尽后才走 handler

── TypeScript ──
handler 收到: {"state":{"log":["ok"],"n":1},"errorName":"NodeError","hasConfig":true}
结果: {"log":["ok","兜底"],"n":-1}
节点 b 执行 2 次        ← 重试用尽后才走 handler
```

> 🔴 **最大的认知冲突在这里**：Python 的 `error_handler` 是 **`(state)` 单参数**，写两个参数直接 `TypeError`；TypeScript 的 `errorHandler` 是 **`(state, error, config?)` 三参数**，异常**直接摆在第二个参数位**。
> 💡 所以 **Python 里"从 config 翻 `__pregel_node_error`"那套在 TS 完全不存在**——TS 根本没有这个 key，`error` 就是第二个入参。

**Python 怎么拿到错误？——从 `config` 里翻**（TS 不需要这一步）：

::: code-group

```python [Python]
def handler(state, config):
    err = config.get("configurable", {}).get("__pregel_node_error")
    print(type(err).__name__, err)      # NodeError
    return {...}
```

```typescript [TypeScript]
// TS 无需从 config 翻：error 就是第二个参数，结构相同（node + error）
const handler = (state: State, error: NodeError) => {
  console.log(error.constructor.name, error.node, error.error);
  return { log: ["兜底"], n: -1 };
};
```

:::

实测：

```
config 里的 error: NodeError: NodeError(node='b', error=NetError('崩了'))
```

> ✅ 是个 `NodeError` 对象，带 `node`（哪个节点）和 `error`（原始异常）。
> 💡 **TS 侧同名对象直接可得**：`error.node`（失败的节点名）、`error.error`（原始异常）。实测 `Object.keys(error)` 恰好就是 `['node', 'error']`，`error.message` 是 `undefined`（它不自带 message，要看 `error.error.message`）。

> ⚠️ **handler 自己崩了 = 整跑崩**（Python 源码注释 `handler failures fail the run`）。两侧实测一致：handler 抛错直接冒出去，没人再兜它。

##### 🔴 兜底会截断流程（实战里撞出来的）

`error_handler` 返回一个普通 dict 时，**流程不会继续走原来的边**：

```
结果: ['查库存:有货', '调风控:兜底放行']      ← 没有"出结论"和"通知"！
```

要让它继续往下走，得返回 `Command(goto=...)`：

::: code-group

```python [Python]
def handler(state):
    return Command(goto="出结论", update={"log": [...], "risk": 0.5})
```

```typescript [TypeScript]
const handler = () =>
  new Command({ goto: "出结论", update: { log: ["调风控:兜底放行"], risk: 0.5 } });
```

:::

实测：

```
── Python ──
Command(goto='出结论') -> ['查库存:有货', '调风控:兜底放行', '出结论:通过', '通知:通过']

── TypeScript ──
普通对象  -> ["查库存:有货","调风控:兜底放行"]
Command   -> ["查库存:有货","调风控:兜底放行","出结论:通过","通知:通过"]
```

> 🔑 **判据（两侧完全一致）**：兜底返回 **普通对象** → 流程到此为止；返回 **`Command({ goto })`** → 跳到指定节点继续。
> 💡 **TS 的写法差别**：`Command` 是**类**，必须 `new Command({ goto, update })`；Python 是 dataclass，直接 `Command(goto=..., update=...)`。

---

##### `timeout`：Python 只支持 async，TS 同步节点也能跑到超时

::: code-group

```python [Python]
builder.add_node("b", sync_slow_node, timeout=0.4)   # 单位：秒
builder.compile()
```

```typescript [TypeScript]
new StateGraph(S)
  .addNode("b", syncSlowNode, { timeout: 400 })      // 单位：毫秒
  .compile();                                         // ← 能过，不抛错
```

:::

实测 **两侧行为完全不同**：

```
── Python ──
compile() -> ValueError: Node timeouts are only supported for async nodes because
             sync Python execution cannot be safely cancelled in-process. Node 'b' is sync.

── TypeScript ──
compile() -> ok
invoke()  -> NodeTimeoutError: Node "b" exceeded its run timeout of 100ms (elapsed: 302ms).
```

> 🔑 **原因**：Python 同步代码没法在进程内安全取消，官方索性在编译期拦下；Node.js 用 `AbortSignal` 做**协作式取消**——同步阻塞代码停不下来，但**它写出的结果会被丢弃**，然后抛 `NodeTimeoutError`。
> ⚠️ **代价**：TS 的超时是"事后判罚"，不是"当场掐断"。一个死循环的同步节点配 `timeout: 100`，实际上会**跑完整个死循环**才报超时（实测 `elapsed: 302ms` 就是节点自己跑完的时间）。**想真取消，节点必须接收并响应 `signal`**。

**async 节点两侧都生效**：

::: code-group

```python [Python]
async def async_slow(state):
    await asyncio.sleep(2)
    return {...}

builder.add_node("b", async_slow, timeout=0.4, error_handler=handler)
```

```typescript [TypeScript]
const asyncSlow = async (state: State) => {
  await new Promise((r) => setTimeout(r, 2000));
  return { log: ["跑完"] };
};

new StateGraph(S)
  .addNode("b", asyncSlow, { timeout: 400, errorHandler: handler })
```

:::

实测：

```
── Python ──
handler 收到 state={'log': [], 'n': 0}
结果: ['超时兜底']  耗时 0.40s

── TypeScript ──
结果: ["超时兜底"]  耗时 0.10s
```

> ✅ **超时能触发 `errorHandler`**——所以它和兜底是串在一条链上的（两侧一致）。

`TimeoutPolicy` 三个字段（两侧字段含义一致，命名与单位不同）：

::: code-group

```python [Python]
TimeoutPolicy(
    run_timeout=0.3,     # 从开始到结束的总时长上限（秒）
    idle_timeout=0.15,   # 没有进展多久算超时（秒）
    refresh_on=...,      # 什么事件算"有进展"
)
```

```typescript [TypeScript]
{
  runTimeout: 300,                  // 从开始到结束的总时长上限（毫秒）
  idleTimeout: 150,                 // 没有进展多久算超时（毫秒）
  refreshOn: "auto" | "heartbeat",  // 什么事件算"有进展"
}
```

:::

实测：

```
── Python ──
TimeoutPolicy: ['run_timeout', 'idle_timeout', 'refresh_on']
TimeoutPolicy(run_timeout=0.3, idle_timeout=0.15)
-> NodeTimeoutError: exceeded its idle timeout of 0.150s
   耗时 0.15s（不是 0.30s）

── TypeScript ──
timeout: { runTimeout: 300, idleTimeout: 150 }
-> NodeTimeoutError: Node "b" exceeded its idle timeout of 150ms without making progress (elapsed: 151ms).
   耗时 0.15s  <- 150ms 触发，不是 300ms
```

- `run_timeout` / `runTimeout`：从开始到结束的总时长上限，**不会**被任何进展信号刷新
- `idle_timeout` / `idleTimeout`：**没有进展**多久算超时（实测比总时长先触发）
- `refresh_on` / `refreshOn`：什么事件算"有进展"。Python 传事件配置，TS 只接受 `"auto"`（默认，图进展信号或显式 heartbeat）或 `"heartbeat"`（只认显式 `runtime.heartbeat()`）

> ⚠️ **没有 `max_attempts`**——`TimeoutPolicy` 只管单次尝试的时长，重试次数归 `RetryPolicy`。Python 传了 `TypeError: unexpected keyword argument`；TS 是类型错误（`runTimeout`/`idleTimeout`/`refreshOn` 之外无此键）。
> 💡 **超时会被 `RetryPolicy` 重试（叠乘）**：实测 Python `timeout=0.3` + `max_attempts=3` → 执行 3 次、耗时 1.35s；TS `timeout: 100` + `maxAttempts: 3` → 执行 3 次、耗时 0.32s。配的时候要算总时长。

#### 常见误区

1. **"配了 `retry_policy` 就会重试"**——错，**Python 默认 `retry_on` 不认 `ValueError`/`RuntimeError`**；TS 只有"配了 `retryPolicy`"之后才反过来（默认几乎全重试），**不配则一次都不重试**。
2. **"`max_attempts=3` = 失败后重试 3 次"**——错，**含第一次**，总共最多跑 3 次（两侧一致）。
3. **"`error_handler(state, error)`"**——Python 错（**单参数**，两参数 `TypeError`）；**TS 恰恰就是这个签名**（`(state, error, config?)`）。
4. **"同步节点也能配 timeout"**——**Python 错**（`compile()` 就抛 `ValueError`）；**TS 能编译过**，运行期才抛 `NodeTimeoutError`。
5. **"`TimeoutPolicy` 有 `max_attempts`"**——错，只有三个字段，管时长不管次数。
6. **"TS 可以直接 `retryOn: ValueError`"**——错，`retryOn` **只接受函数**，要写 `(e) => e instanceof TypeError`。
7. **"`timeout` 单位两边一样"**——错，**Python 是秒，TS 是毫秒**。

#### 一句话记住

**Python：`retry_policy` 挑异常（默认不认 ValueError）、`error_handler` 只收 state（签名单参）、`timeout` 只认 async（同步在编译期就拦）。TS：不配 `retryPolicy` 压根不重试，配了之后默认 `retryOn` 几乎都重试、`errorHandler(state, error, config?)` 异常在第二个参数（且被 `NodeError` 包一层）、`timeout` 是毫秒且同步节点运行期才判罚。三者按"重试 → 兜底"串成一条链（这点两侧一致）。**

#### 🗣️ 行话对照

| 本课说法（人话） | 行业标准叫法 | Python 写法 | TypeScript 写法 |
|---|---|---|---|
| 失败再试几次 | **RetryPolicy** | `retry_policy=RetryPolicy(max_attempts=3)` | `{ retryPolicy: { maxAttempts: 3 } }` |
| 挑哪些异常重试 | **retry_on / retryOn** | `retry_on=ValueError`（可传类或函数） | `retryOn: (e) => e instanceof TypeError`（只能函数） |
| 隔多久再试 | **initial_interval / backoff_factor** | `RetryPolicy(initial_interval=0.5, backoff_factor=2)`（秒） | `{ initialInterval: 500, backoffFactor: 2 }`（毫秒） |
| 试完还不行走兜底 | **error_handler / errorHandler** | `error_handler=fn`，签名 `(state)` | `errorHandler: fn`，签名 `(state, error, config?)` |
| 太久算失败 | **timeout / TimeoutPolicy** | `timeout=5.0`（秒，仅 async） | `timeout: 5000`（毫秒，同步也能过编译） |
| 全图默认 | **set_node_defaults / setNodeDefaults** | `builder.set_node_defaults(retry_policy=...)` | `.setNodeDefaults({ retryPolicy: ... })` |
| 错误对象 | **NodeError** | `config['configurable']['__pregel_node_error']` | 直接是第 2 个参数 |

> 中文均为社区常用译法 / 本文自拟，官方未定名中文，检索用英文。

#### 官方文档

- Python：[Fault tolerance（容错配置）](https://docs.langchain.com/oss/python/langgraph/fault-tolerance)｜[Graph API overview](https://docs.langchain.com/oss/python/langgraph/graph-api)
- TypeScript：[Fault tolerance（JS 容错配置）](https://docs.langchain.com/oss/javascript/langgraph/fault-tolerance)｜[Graph API overview（JS）](https://docs.langchain.com/oss/javascript/langgraph/graph-api)

---

### 知识点 2：子图与状态隔离

> 🧭 第 2/2 步｜承接：一个节点的错能扛住了 → 本步：流程太大改不动，怎么拆
> 本知识点关键点：子图编译后如何挂载 / 父子状态如何传递 / 事件冒泡与"父图看不见子图内部"的调试代价

#### 一句话定义

**把 `sub_builder.compile()` 的结果当普通节点 `add_node("sub", sub)` 挂到父图上；父子之间只传递两边 State schema 都声明了的字段，单向私有字段各自保留、互不干扰。**

#### 直觉建立（类比）

把它想成**公司里的部门**：

- 一个部门内部怎么分工、有几个人、墙上贴什么报表，**其他部门管不着也看不见**（状态隔离）；
- 部门之间只通过**规定好的对接表**传递信息（共享字段）；
- 部门内部的八卦（私有字段）**传不出去**——不是被拦下报错，是**根本没人接收**。

> 💡 **类比的边界**：真实机制里 ① **"对接表"是双向的**——父图有 `secret` 但子图没声明，子图**也收不到**（实测子图只看到 `['log']`）；② **私有字段是静默丢弃**，不报错不警告（实测 `only_sub` 直接消失）；③ 部门**没有独立档案室**时不单独存档——子图不挂 checkpointer 时，它的内部步骤**不会在父图历史里单列**（实测父图历史 4 条，子图内部 2 步合成 1 步）。

#### 核心原理

**挂载方式**（两侧完全一致，只有编译选项的键名不同）：

::: code-group

```python [Python]
sub = sub_builder.compile()          # 先编译
builder.add_node("sub", sub)         # 当普通节点挂上去
```

```typescript [TypeScript]
const sub = subBuilder.compile();    // 先编译
new StateGraph(Outer).addNode("sub", sub);   // 当普通节点挂上去
```

:::

**状态传递：只传共享 key**

::: code-group

```python [Python]
class Outer(TypedDict):     # 父图
    secret: str
    log: list

class Inner(TypedDict):     # 子图
    log: list               # ← 只有 log 是共享的
```

```typescript [TypeScript]
const Outer = Annotation.Root({      // 父图
  secret: Annotation<string>({ reducer: (_p, x) => x, default: () => "" }),
  log: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
});

const Inner = Annotation.Root({      // 子图
  log: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),  // ← 只有 log 是共享的
});
```

:::

实测：

```
父图有 secret -> ["子图看到的 keys=['log']"]      ← 子图收不到 secret
```

> 💡 **TS 侧要自己打印确认**：子图节点的 `state` 参数就是"交集后的结果"。实测在子图节点里 `Object.keys(state)` 得到 `["log"]`，跟 Python 的观察完全对上——`Annotation.Root` 没声明 `secret`，它压根不会出现在子图的 state 里。

**反向一样**：子图写了 `only_sub`，父图 schema 没声明——

```
父图最终结果 keys: ['log', 'secret']
🔑 only_sub 被父图 schema 吞掉了 —— 静默丢弃，不报错
```

> ⚠️ **这是最阴的坑**：不报错、不警告，字段就这么消失了。**想让子图结果传出来，必须在父图 State 里也声明那个字段。**

#### 事件冒泡与排障代价

课 7 讲过：子图事件默认不可见，要 `subgraphs=True`。本课从**存档**角度再看一遍。

![子图状态隔离](../assets/langgraph-subgraph-isolation.svg)

> 看图：父子之间只传"两边都声明了的字段"（`log`），两边的私有字段（`secret` / `only_sub`）各自留着。**下面两块是代价**：子图不挂 checkpointer 时内部不单独存档，要看必须开 `subgraphs=True`。

**子图不挂 checkpointer**——父图历史里看不到子图内部：

```
── Python ──
ns=''  next=()        log=['子图内 foo=A', '子图内第二步', '父收尾']
ns=''  next=('o',)    log=['子图内 foo=A', '子图内第二步']
ns=''  next=('sub',)  log=[]
ns=''  next=('__start__',) log=None

── TypeScript ──
ns="" next=[]              log=["子图内 foo=A","子图内第二步","父收尾"]
ns="" next=["o"]           log=["子图内 foo=A","子图内第二步"]
ns="" next=["sub"]         log=[]
ns="" next=["__start__"]   log=[]
```

> ⚠️ **子图内部两个节点合成了一条**——父图只看到"sub 这一步做完了"。**排障时你不知道卡在子图第几个节点。**
> 💡 顺带对上课 9 的差异：TS 的 `next` 是数组 `[]` / `["o"]`，Python 是元组 `()` / `('o',)`；初始状态下 TS 的 `log` 是 `[]`，Python 是 `None`。

**开 `subgraphs: true` 才看得到内部**（课 7 已验证，本课从 ns 角度复核）：

::: code-group

```python [Python]
for chunk in graph.stream({"log": []}, subgraphs=True):
    ns, data = chunk          # ns 是元组
    print(ns, data)
```

```typescript [TypeScript]
for await (const [ns, chunk] of await graph.stream({ log: [] }, { subgraphs: true })) {
  console.log(ns, chunk);     // ns 是数组
}
```

:::

实测：

```
── Python ──
ns=('sub:b44bbf92-80ba-34bc-1fc0-2b4dc00f01e1',)  chunk=['i1']
ns=('sub:b44bbf92-80ba-34bc-1fc0-2b4dc00f01e1',)  chunk=['i2']
ns=()                                             chunk=['sub']
ns=()                                             chunk=['o']

── TypeScript ──
ns=["sub:9569ed79-0427-5b18-8f24-683d7a8f668a"]  chunk={"i1":{"log":["i1"]}}
ns=["sub:9569ed79-0427-5b18-8f24-683d7a8f668a"]  chunk={"i2":{"log":["i2"]}}
ns=[]                                             chunk={"sub":{"log":["i1","i2"]}}
ns=[]                                             chunk={"o":{"log":["o"]}}
```

> ✅ **课 9 埋的 `checkpoint_ns` 伏笔在这里兑现**：子图的命名空间是 `节点名:uuid`（主图是空串 `''`）。
> 🔑 但注意：**`getStateHistory` 里全是 `ns=''`**——命名空间只在 `stream({ subgraphs: true })` 里才显形。
> 💡 **两处形态差异**：① Python 的 `ns` 是**元组**、TS 是**数组**；② Python 的 chunk 直接就是该节点的**输出值**（`['i1']`），TS 是**节点名映射到输出**（`{"i1": {"log": ["i1"]}}`）。深挖日志时这个包装层要多剥一次。

**给子图单独挂 checkpointer**（Python `compile(checkpointer=True)`｜TS `compile({ checkpointer: true })`）：

实测父图历史仍是 `ns=''` 三条，且**子图自己查历史拿不到东西**——子图不能脱离父图独立回溯。

```
── Python ──
父图历史 3 条，ns 仍为 ''
子图独立查 get_state_history -> 0 条

── TypeScript ──
父图历史条数: 3 （ns 仍为 ""）
子图独立查历史 -> Error: checkpointer: true cannot be used for root graphs.
子图脱离父图查历史: 0 条
```

> 🔴 **TS 的额外限制**：`checkpointer: true` **只允许挂在子图上**，直接给根图用会抛 `checkpointer: true cannot be used for root graphs.`——根图必须给一个真的 saver 实例（如 `new MemorySaver()`）。Python 没有这条限制。

#### 容错在子图上怎么用

**子图内部抛错，父图能兜住**（实测）：

::: code-group

```python [Python]
builder.add_node("sub", sub, error_handler=parent_handler)
# -> ['父图兜住了']   ✅ 不炸整张图
```

```typescript [TypeScript]
new StateGraph(Outer).addNode("sub", sub, { errorHandler: () => ({ log: ["父图兜住了"] }) });
// -> ["父图兜住了"]   ✅ 不炸整张图
```

:::

**也可以兜在子图内部**（实测）：

::: code-group

```python [Python]
sub_builder.add_node("i", risky, error_handler=inner_handler)
# -> ['子图内兜底']
```

```typescript [TypeScript]
subBuilder.addNode("i", risky, { errorHandler: () => ({ log: ["子图内兜底"] }) });
// -> ["子图内兜底"]
```

:::

> ✅ **两层都能兜**（两侧一致），选哪层取决于"这个兜底是子图的局部策略还是父图的全局策略"。

**`retry_policy` / `retryPolicy` 要配在子图内部节点上**（实测）：

::: code-group

```python [Python]
sub_builder.add_node("i", flaky, retry_policy=RetryPolicy(max_attempts=3))
# 子图内部节点执行 3 次
```

```typescript [TypeScript]
subBuilder.addNode("i", flaky, { retryPolicy: { maxAttempts: 3 } });
// 子图内部节点执行 3 次
```

:::

> ⚠️ 配在父图的 `add_node("sub", ...)` 上，管不到子图内部的具体节点。

#### 常见误区

1. **"子图能看到父图所有字段"**——错，**只传两边都声明的**（两侧实测子图都只看到 `["log"]`）。
2. **"子图私有字段传不出来会报错"**——错，**静默丢弃**，不报错。
3. **"子图内部每步都有独立 checkpoint"**——错，不挂 checkpointer 时**内部不单独存档**。
4. **"子图挂在父图上就能给它配重试"**——错，**要配在子图内部节点上**。
5. **"TS 也能给根图传 `checkpointer: true`"**——错，抛 `checkpointer: true cannot be used for root graphs.`。

#### 一句话记住

**子图 = 编译好的图当节点挂上去；父子只传共享字段（私有的静默丢弃），不挂 checkpointer 时内部不单独存档——排障必须靠 `subgraphs: true`。**

#### 🗣️ 行话对照

| 本课说法（人话） | 行业标准叫法 | Python 写法 | TypeScript 写法 |
|---|---|---|---|
| 把图当节点挂 | **Subgraph** | `add_node("sub", sub.compile())` | `.addNode("sub", sub)` |
| 只传两边都有的 | **共享 key / state schema** | 父子 `TypedDict` 都声明的字段 | 父子 `Annotation.Root` 都声明的字段 |
| 子图的命名空间 | **checkpoint_ns** | `ns=('sub:uuid',)` 元组 | `ns=["sub:uuid"]` 数组 |
| 子图单独存档 | **compile(checkpointer=...)** | `sub.compile(checkpointer=True)` | `sub.compile({ checkpointer: true })`（仅子图可用） |
| 让子图显形 | **subgraphs=True** | `graph.stream(..., subgraphs=True)` | 输出变 `(ns, data)` 元组 |

> 中文均为社区常用译法。

#### 官方文档

- [Subgraphs（子图与状态隔离）](https://docs.langchain.com/oss/python/langgraph/use-subgraphs)
- [Fault tolerance（容错）](https://docs.langchain.com/oss/python/langgraph/fault-tolerance)

---

## 第四幕：实操验证

### 4.1 机制验证

> ✅ 实测于 langgraph 1.2.11 / Python 3.12（在 `../langchain/playground` 以 `uv run` 隔离执行）

**验证一：默认 `retry_on` 的异常对照表**

```
ValueError('x')        -> ❌不重试
RuntimeError('x')      -> ❌不重试
TypeError('x')         -> ❌不重试
KeyError('x')          -> ❌不重试
OSError('x')           -> ❌不重试
ConnectionError('x')   -> ✅重试
自定义 NetError('x')   -> ✅重试
```

**验证二：默认配置下抛 ValueError，配了 retry 也不重试**

```
invoke -> ValueError: 临时故障
实际执行 1 次   <- max_attempts=3 但只跑了 1 次！
```

**验证三：抛自定义异常 NetError —— 默认就重试**

```
结果: ['ok', 'b成功', 'ok']
实际执行 3 次   <- 第 3 次成功
```

**验证四：抛 ConnectionError —— 默认重试**

```
结果: ['ok', 'b重连成功', 'ok']
实际执行 2 次
```

**验证五：`retry_on=ValueError` 显式指定**

```
结果: ['ok', 'b成功', 'ok']
实际执行 3 次
```

**验证六：`retry_on` 用函数**

```
结果: ['ok', '成功', 'ok']
实际执行 3 次
```

**验证七：retry 用尽后抛原始异常**

```
invoke -> NetError: 永远失败
实际执行 3 次
```

**验证八：`max_attempts` 含第一次**

```
max_attempts=1 -> 1 次
max_attempts=2 -> 2 次
max_attempts=3 -> 3 次
```

**验证九：退避间隔（jitter=False）**

```
总耗时 2.10s (4 次尝试 = 3 次间隔)
实测间隔: ['0.30s', '0.60s', '1.20s']
期望: initial=0.3 backoff=2 -> 0.30s, 0.60s, 1.20s
```

**验证十：jitter 默认 True 会抖**

```
jitter 默认(True) 实测间隔: ['0.50s', '0.92s', '1.34s']
```

**验证十一：`error_handler` 单参数**

```
h1 收到 state={'log': ['ok'], 'n': 1}
结果: ['ok', '兜底1']  n=-1
```

**验证十二：error 从 config 拿**

```
config 里的 error: NodeError: NodeError(node='b', error=NetError('崩了'))
```

**验证十三：两参数 (state, error) 报错**

```
两参数 -> TypeError: h3() missing 1 required positional argument: 'error'
```

**验证十四：参数名不重要**

```
参数名叫 x 也能收到: {'log': ['ok'], 'n': 1}
```

**验证十五：error_handler + retry**

```
h1 收到 state={'log': ['ok'], 'n': 1}
结果: ['ok', '兜底1']
节点 b 执行 3 次          <- 先重试，用尽后才走 handler
```

**验证十六：handler 自己抛错**

```
handler 抛错 -> RuntimeError: handler 自己也崩了
```

**验证十七：`set_node_defaults` 全图默认**

```
全局默认 retry -> ['ok', 'b成功']
节点 b 执行 3 次
```

**验证十八：节点级覆盖全局**

```
全局 max_attempts=5，节点级 =2 -> 实际 2 次
```

**验证十九：同步节点配 timeout，compile 就抛**

```
compile -> ValueError: Node timeouts are only supported for async nodes
           because sync Python execution cannot be safely cancelled in-process.
```

**验证二十：async 节点 timeout 生效**

```
ainvoke -> NodeTimeoutError: Node 'b' exceeded its run timeout of 0.400s (elapsed: 0.401s).
           耗时 0.40s
```

**验证二十一：超时触发 error_handler**

```
handler 收到 state={'log': [], 'n': 0}
结果: ['超时兜底']  耗时 0.40s
```

**验证二十二：TimeoutPolicy 只有三个字段**

```
TimeoutPolicy: ['run_timeout', 'idle_timeout', 'refresh_on']
传 max_attempts -> TypeError: unexpected keyword argument 'max_attempts'
```

**验证二十三：idle_timeout 比 run_timeout 先触发**

```
TimeoutPolicy(run_timeout=0.3, idle_timeout=0.15)
-> NodeTimeoutError: exceeded its idle timeout of 0.150s
   耗时 0.15s（不是 0.30s）
```

**验证二十四：超时 + retry 会叠乘**

```
timeout=0.3 + RetryPolicy(max_attempts=3)
节点 b 执行 3 次  耗时 1.35s
```

**验证二十五：子图不挂 checkpointer，父图历史**

```
ns=''  next=()        log=['子图内 foo=A', '子图内第二步', '父收尾']
ns=''  next=('o',)    log=['子图内 foo=A', '子图内第二步']
ns=''  next=('sub',)  log=[]
ns=''  next=('__start__',) log=None
（子图内部两步合成一条）
```

**验证二十六：`subgraphs=True` 下的 ns**

```
ns=('sub:b44bbf92-80ba-34bc-1fc0-2b4dc00f01e1',)  chunk=['i1']
ns=('sub:b44bbf92-80ba-34bc-1fc0-2b4dc00f01e1',)  chunk=['i2']
ns=()  chunk=['sub']
ns=()  chunk=['o']
```

**验证二十七：父图私有字段子图收不到**

```
父图有 secret -> ["子图看到的 keys=['log']"]
```

**验证二十八：子图私有字段父图吞掉**

```
父图最终结果 keys: ['log', 'secret']
父图 log: ['子图写了', "父 keys=['log', 'secret']"]
（only_sub 静默消失）
```

**验证二十九：子图抛错，父图 error_handler 兜住**

```
父图 error_handler -> ['父图兜住了']
```

**验证三十：error_handler 放子图内部也行**

```
子图内 error_handler -> ['子图内兜底']
```

**验证三十一：retry 配在子图内部节点**

```
子图内部节点执行 3 次
```

#### 🇹🇸 TS 侧实测（`playground-ts/10-fault-tolerance.ts`，`@langchain/langgraph` 1.5.x）

> ✅ 实测于 `@langchain/langgraph` 1.5.0 / Node.js（`npm run l10`，共 26 项验证，三闸门全绿）

**验证零：不配 `retryPolicy` 到底会不会重试（实测）**

```
普通 Error     -> 调用 1 次  <- 无 policy = 不重试
HTTP 404       -> 调用 1 次  <- 无 policy = 不重试
HTTP 500       -> 调用 1 次  <- 无 policy = 不重试
HTTP 404 + policy(maxAttempts=4) -> 调用 1 次  <- 404 在默认黑名单
```

源码依据：`pregel/retry.js` 的 `if (resolvedRetryPolicy === void 0) break;` 直接跳出重试循环。所以 TS 侧是"**要么不重试，要么按黑名单几乎全重试**"两档，没有 Python 那种"默认策略仍在"的中间态。

**验证一：默认 `retryOn` 的异常对照表（与 Python 相反）**

> ⚠️ 前提：这张表描述的是「**已经配了 `retryPolicy`** 之后，`retryOn` 的默认判定」，不是"不配也生效"。

```
ValueError / new Error('x')   -> ✅重试      ← Python 不重试
TypeError                     -> ✅重试      ← Python 不重试
RangeError                    -> ✅重试      ← 相当于 Python 的 RuntimeError
连接错误(ECONNREFUSED)         -> ✅重试
HTTP 500                      -> ✅重试
HTTP 404                      -> ❌不重试     ← 在黑名单
普通自定义异常                  -> ✅重试
```

**验证二：普通 `Error` + `retryPolicy(maxAttempts=3)`**

> ⚠️ **`retryPolicy` 的挂载位置只有两个**：`addNode(name, fn, { retryPolicy })` 或 `.setNodeDefaults({ retryPolicy })`。写进 `compile({ retryPolicy })` 会踩双坑——`tsc` 报 `TS2353: 'retryPolicy' does not exist in type ...`，而 `tsx` 直接运行时把它当普通字段**静默忽略**（本机实测：那里写 `maxAttempts: 4`，节点仍只调 1 次）。

```
Retrying task "b" after 10.00ms (attempt 1) after Error: Error: 临时故障
Retrying task "b" after 20.00ms (attempt 2) after Error: Error: 临时故障
invoke -> Error: 临时故障
实际执行 3 次   <- 与 Python 的"只跑 1 次"完全相反
```

**验证三：`maxAttempts` 含第一次**

```
maxAttempts=1 -> 1 次
maxAttempts=2 -> 2 次
maxAttempts=3 -> 3 次
```

**验证四：退避间隔（`jitter: false`）**

```
总耗时 2.11s (4 次尝试 = 3 次间隔)
实测间隔: ['0.30s', '0.60s', '1.20s']
期望: initialInterval=300 backoffFactor=2 -> 0.30s, 0.60s, 1.20s
```

**验证五：`jitter` 默认 `true` 会抖**

```
jitter 默认实测间隔: ['1.28s', '1.06s', '2.88s']   ← 在 base 上再叠加 0~1s 随机
```

**验证六 / 七：`errorHandler` 签名与 `NodeError` 结构**

```
handler 收到: {"state":{"log":["ok"],"n":1},"errorName":"NodeError","hasConfig":true}
结果: {"log":["ok","兜底"],"n":-1}

NodeError 自己的键: ['node', 'error']
node = b   error = Error:崩了
message = undefined      ← NodeError 不自带 message
```

**验证八 / 九：兜底返回普通对象 vs `Command`**

```
普通对象  -> ["查库存:有货","调风控:兜底放行"]                      ← 截断，没有后续
Command   -> ["查库存:有货","调风控:兜底放行","出结论:通过","通知:通过"]
```

**验证十：`errorHandler` 自己抛错**

```
-> Error: handler 自己也崩了
```

**验证十一：同步节点配 `timeout`（毫秒）**

```
compile() -> ok                                                  ← Python 在这里就炸了
invoke()  -> NodeTimeoutError: Node "b" exceeded its run timeout of 100ms (elapsed: 302ms).
```

**验证十二 / 十三：async 节点超时与兜底**

```
-> NodeTimeoutError: Node "b" exceeded its run timeout of 100ms (elapsed: 100ms).
耗时 0.10s

超时 + errorHandler -> 结果: ["超时兜底"]  耗时 0.10s
```

**验证十四：`TimeoutPolicy` 的 `idleTimeout` 先触发**

```
timeout: { runTimeout: 300, idleTimeout: 150 }
-> NodeTimeoutError: Node "b" exceeded its idle timeout of 150ms without making progress (elapsed: 151ms).
耗时 0.15s  <- 150ms 触发，不是 300ms
```

**验证十五：超时 + retry 叠乘**

```
节点执行 3 次  耗时 0.32s
```

**验证十六 / 十七：子图状态隔离**

```
父图传了 secret=S -> ["子图看到的 keys=["log"]"]   子图实收 keys: ["log"]
父图结果 keys: ["secret","log"]     onlySub 在? false
```

**验证十八 / 十九：父图历史与 `subgraphs: true` 的 ns**

```
ns="" next=[]              log=["子图内 foo=A","子图内第二步","父收尾"]
ns="" next=["o"]           log=["子图内 foo=A","子图内第二步"]
ns="" next=["sub"]         log=[]
ns="" next=["__start__"]   log=[]

ns=["sub:9569ed79-..."]  chunk={"i1":{"log":["i1"]}}
ns=["sub:9569ed79-..."]  chunk={"i2":{"log":["i2"]}}
ns=[]                    chunk={"sub":{"log":["i1","i2"]}}
ns=[]                    chunk={"o":{"log":["o"]}}
```

**验证二十 / 二十一：子图容错两层都能兜**

```
子图抛错 -> 父图 errorHandler -> ["父图兜住了"]
子图内部 errorHandler        -> ["子图内兜底"]
子图内部节点配 retryPolicy   -> 执行 3 次
```

**验证二十二 / 二十三：`setNodeDefaults` 与自定义 `retryOn`**

```
只配全局 maxAttempts=5     -> 执行 5 次
全局 5 + 节点级 2          -> 执行 2 次   <- 节点级覆盖全局

retryOn=(e)=>e instanceof TypeError     -> 执行 3 次
retryOn=(e)=>e.message.includes("可重试") -> 执行 3 次
retryOn=()=>false                       -> 执行 1 次
```

**验证二十四：retry 用尽后抛原始异常**

```
-> NetError: 永远失败   <- 与 Python 一致，不是包装异常
```

**验证二十五 / 二十六：子图 checkpointer 的 TS 限制**

```
父图历史 3 条，ns 仍为 ""
子图独立查历史 -> Error: checkpointer: true cannot be used for root graphs.
子图脱离父图查历史: 0 条
```

**✅ 两侧一致的 7 条**

1. `maxAttempts` 含第一次（`max_attempts=3` 就跑 3 次）
2. 退避公式与默认值：`initial×backoff^n`，`initialInterval` 默认 500ms、`backoffFactor` 默认 2
3. `jitter` 默认开启，且是"在 base 上再加 0~1s 随机"
4. 重试用尽后抛**原始异常**，不做包装
5. 兜底返回**普通对象截断流程**，返回 `Command(goto)` 才能续
6. 子图**只传两边都声明了的字段**，私有字段**静默丢弃**
7. 子图容错**两层都能兜**；`retryPolicy` 必须配在子图内部节点上

**🔴 两侧不同的 8 条**

| 维度 | Python | TypeScript |
|---|---|---|
| 默认重试策略 | 白名单：`ValueError`/`TypeError`/`RuntimeError`/`OSError` 等**不重试** | 黑名单：除取消/图错误/4xx/额度耗尽外**一律重试** |
| `retry_on` 传值 | 可传异常类 `ValueError` 或函数 | **只能传函数** `(e) => boolean` |
| 时间单位 | 秒（`timeout=0.4`） | 毫秒（`timeout: 400`） |
| `error_handler` 签名 | `(state)` 单参数，写两参数 `TypeError` | `(state, error, config?)` 三参数，异常在第 2 位 |
| 拿 error 的路径 | `config['configurable']['__pregel_node_error']` | 第二个参数，无需翻 config |
| 同步节点配 `timeout` | `compile()` **立即抛 `ValueError`** | **编译通过**，运行期抛 `NodeTimeoutError`（协作式取消，写出的结果被丢弃） |
| `RetryPolicy` 字段 | 六个 | 七个（多 `logWarning`，默认 `true` 会打重试日志） |
| 子图 `checkpointer: true` | 根图/子图都能用 | **仅子图可用**，根图抛 `checkpointer: true cannot be used for root graphs.` |

> 💡 **移植检查清单**：把 Python 的容错配置搬到 TS 时，必须逐项确认 ① 时间单位从秒换成毫秒；② `retryOn` 要不要显式收窄（否则原本"只跑 1 次"的 `ValueError` 会变成跑满 3 次）；③ `errorHandler` 改成三参数、异常从第二参数取；④ 同步节点的 `timeout` 在 TS 能过编译但只是"事后判罚"，节点若不响应 `signal` 就取消不了。

### 4.2 应用实战

🎯 [练一练：应用实战 10「外部接口抖了就整单失败，还不能拖垮别的环节」](../../../应用实战/10-Fault-tolerance 与 Subgraphs.md)

> 基础 → 问题 → 综合三跳：先让调用节点自己重试，再撞上"ValueError 不重试"和"同步节点配不了超时"，最后重试 + 兜底 + 子图拆分收口。

---

## 第五幕：体系收束

今天给图装上了"抗压 + 可拆"两件事。三句话带走：

1. **重试挑异常**——默认 `retry_on` 把 `ValueError`/`RuntimeError`/`TypeError` 当代码 bug 不重试，只有 `ConnectionError`、HTTP 5xx、不认识的自定义异常才试；`max_attempts` 含第一次。
2. **兜底和超时串在一条链上**——`error_handler` 签名是 `(state)` 单参数（error 在 config 里），超时触发后会走它；**同步节点配 `timeout` 在 `compile()` 就抛错**。
3. **子图换来了拆分复用，代价是"看不见"**——父子只传共享字段（私有的静默丢弃），不挂 checkpointer 时内部不单独存档，排障必须 `subgraphs=True`。

> 📍 **全局定位**：阶段 3 第三章——课 8 能暂停、课 9 能回放、课 10 能扛错能拆开。**容错是"节点内消化"，子图是"结构上隔离"**，两条路互补。
> 🔗 **下一步**：课 11《Functional API 与选型》——`@entrypoint` / `@task` 是另一套心智模型，以及两套 API 怎么选。

顺带埋个伏笔：**"子图 + 容错"正是多智能体的地基**——课 11 之后进入阶段 4，你会发现多智能体编排本质上就是"多个子图 + 各自的容错策略 + 一个协调者"。

---

## 🐞 常见误区

1. **"配了 `retry_policy` 就会重试"**——错，默认 `retry_on` **不认 `ValueError`**。
2. **"`max_attempts=3` = 失败后重试 3 次"**——错，**含第一次**。
3. **"`error_handler(state, error)`"**——错，**单参数**，两参数 `TypeError`。
4. **"同步节点也能配 timeout"**——错，**`compile()` 就抛 `ValueError`**。
5. **"`TimeoutPolicy` 有 `max_attempts`"**——错，传了 `TypeError`。
6. **"子图能看到父图所有字段"**——错，**只传两边都声明的**。
7. **"子图私有字段传不出来会报错"**——错，**静默丢弃**。
8. **"子图内部每步都有独立 checkpoint"**——错，不挂 checkpointer 时**不单独存档**。
9. **"容错配置挂在父图的子图节点上就行"**——错，**retry 要配在子图内部节点上**（error_handler 两层都行）。
10. **"超时和重试各管各的"**——错，**叠乘**：`timeout=0.3` + `max_attempts=3` → 最坏 0.9s+。
11. **"兜底完流程会接着往下走"**——错，**返回普通 dict 会截断流程**；要 `Command(goto=...)` 才能续上。

### ⏳ 与过时说法对照（写前核对有差异时才有，≤3 行）

| 旧说法（网上过时教程 / 训练知识里的说法） | 官方文档 / 本机现状 | 来源 |
|---|---|---|
| "`add_node(..., retry_policy=RetryPolicy(max_attempts=3))` 就会对任何异常重试 3 次" | 实测抛 `ValueError` **只执行 1 次**：默认 `retry_on=default_retry_on` 对 ValueError/TypeError/RuntimeError/OSError 等**返回 False**；仅 ConnectionError、HTTP 5xx、不认识的自定义异常才重试 | 实测 + `_internal/_retry.py:1` |
| "`error_handler` 签名是 `(state, error)` 两个参数" | 实测两参数 → `TypeError: handler() missing 1 required positional argument: 'error'`；正确是 `(state)` 单参，error 从 `config['configurable']['__pregel_node_error']` 取（是个 `NodeError`） | 实测 + `_algo.py:1110` |
| "给任意节点加 `timeout=秒数` 即可限制执行时长" | 实测**同步节点在 `compile()` 阶段**抛 `ValueError: Node timeouts are only supported for async nodes`；async 节点才抛 `NodeTimeoutError` 并可触发 `error_handler` | 实测 + `_utils.py:137` |

## 一图总结

![课 10 知识全景](../assets/langgraph-lesson10-summary.svg)

> 看图：四列——重试（含 ★ 的 `retry_on` 默认行为）、兜底（含 ★ 的单参签名）、超时（含 ★ 的同步限制）、子图（含 ★ 的静默丢弃）。**与课首那张图的区别**：课首那张给没学过的人看"为什么要能扛错能拆"，这张给刚学完的你复习"三个参数各自的硬约束"。

## 课后小测

**Q1**：节点抛 `ValueError`，配了 `RetryPolicy(max_attempts=3)`，会执行几次？
- A. 1 次
- B. 3 次
- C. 4 次
- D. 取决于 backoff_factor

<details><summary>答案与解析</summary>

**答案：A**。默认的 `retry_on=default_retry_on` 对 `ValueError` **返回 False**（源码把它列在"代码 bug"那一组），所以一次都不重试。想要重试必须显式 `retry_on=ValueError`，或者抛 `ConnectionError` / 自定义异常（默认会重试）。

</details>

**Q2**：`error_handler` 想拿到原始异常，正确的做法是？
- A. `def handler(state, error)` 两个参数
- B. `def handler(state)` 单参数，从 `config['configurable']['__pregel_node_error']` 取
- C. 抛出的异常会自动塞进 state
- D. 用全局 `sys.exc_info()`

<details><summary>答案与解析</summary>

**答案：B**。实测两参数写法直接 `TypeError: h3() missing 1 required positional argument: 'error'`——error **不走参数位**。正确是单参数收 state，异常从 `config` 里翻，拿到的是 `NodeError(node='b', error=NetError('崩了'))`。参数名叫什么都行（按位置传）。

</details>

**Q3**：子图里写了一个父图 State 没声明的字段，会怎样？
- A. 抛 TypeError 提示字段不存在
- B. 静默丢弃，父图拿不到
- C. 自动加到父图 State 里
- D. 运行时警告但不影响

<details><summary>答案与解析</summary>

**答案：B**。实测父图最终结果 `keys = ['log', 'secret']`，子图写的 `only_sub` **直接消失**，没有任何报错或警告。这是最阴的坑——**想让子图结果传出来，必须在父图 State 里也声明那个字段**。反向同理：父图的 `secret` 子图没声明也收不到（实测子图只看到 `['log']`）。

</details>

---

## 🚀 下一批接力提示词

> 学完本批后，**复制下面这段文字发给 AI**，即可无缝进入下一批：

```
继续学 LangGraph。我的学习档案在 langchain/langgraph/00-学习档案.md，
刚学完阶段 3《可控性与人在环中》的课 10《Fault-tolerance 与 Subgraphs》
知识点「节点级超时 / 重试 / 错误处理 / 子图与状态隔离」，
请按大纲继续讲解课 11《Functional API 与选型》的知识点。
```

## 🧭 课程导航

- 上一课：[课 9 Time-travel 回放与分叉](09-Time-travel 回放与分叉.md)
- 返回 [课程目录](../../../02-课程目录.md)
- 下一课：[课 11 Functional API 与选型](11-Functional API 与选型.md)
- 🎯 练一练：应用实战 10（见 4.2）
