# 应用实战 10：外部接口抖了就整单失败，还不能拖垮别的环节

> 对应：[课 10 Fault-tolerance 与 Subgraphs](../stages/3-可控性与人在环中/lessons/10-Fault-tolerance%20与%20Subgraphs.md)
> 覆盖知识点：节点级超时 / 重试 / 错误处理 / 子图与状态隔离
> ✅ 全部代码实测于 langgraph 1.2.11 / Python 3.12（在 `../langchain/playground` 以 `uv run` 隔离执行）
> ✅ TypeScript 侧实测于 `playground-ts/`（`@langchain/langgraph` 1.5.1 / Node 22，`npm run a10`）

## 场景

下单流程：查库存 → 调风控 → 出结论 → 通知。风控是外部接口，偶尔抖一下。

三跳演进：

| 跳 | 目标 | 新增的知识点 |
|:--:|------|-------------|
| 基础 | 让调用节点自己重试，别整单废掉 | retry_policy / per-node 配置 |
| 问题 | 撞上"ValueError 不重试"和"同步配不了超时" | 默认 retry_on / timeout 的 async 限制 |
| 综合 | 重试 + 兜底 + 拆子图收口 | 自定义异常 / error_handler / 子图状态隔离 |

> 完整方案还需要：重试的幂等性保证（重试会不会重复下单）、熔断与降级、外部接口的错误分类、子图版本演进时的契约管理、以及重试指标的上报——**这些都不是本课内容**（课 13 部署与可观测时展开）。

---

## 第 1 跳：给调用节点挂上重试（基础）

![第 1 跳：挂上重试](./assets/app-step1-fault-tolerance.svg)

> 看图：左右是同一个流程，区别只在"外部抖一下"之后——左边整单报错退出，右边抖的那一下自己重试，别的照常走完。

::: code-group

```python [Python]
import random

from langgraph.graph import END, START, StateGraph
from langgraph.types import RetryPolicy
from typing_extensions import TypedDict


class Order(TypedDict):
    order_id: str
    log: list
    risk: float
    decision: str


ATTEMPTS = {"risk": 0}


def check_stock(state: Order) -> dict:
    return {"log": state.get("log", []) + ["查库存:有货"]}


def call_risk(state: Order) -> dict:
    ATTEMPTS["risk"] += 1
    if ATTEMPTS["risk"] < 3:
        raise ConnectionError(f"风控接口抖动 {ATTEMPTS['risk']}")
    return {"log": state.get("log", []) + ["调风控:成功"], "risk": 0.3}


def decide(state: Order) -> dict:
    d = "通过" if state["risk"] < 0.7 else "拒绝"
    return {"log": state.get("log", []) + [f"出结论:{d}"], "decision": d}


def notify(state: Order) -> dict:
    return {"log": state.get("log", []) + [f"通知:{state['decision']}"]}


b = StateGraph(Order)
b.add_node("查库存", check_stock)
b.add_node("调风控", call_risk, retry_policy=RetryPolicy(max_attempts=3, initial_interval=0.01))
b.add_node("出结论", decide)
b.add_node("通知", notify)
b.add_edge(START, "查库存")
b.add_edge("查库存", "调风控")
b.add_edge("调风控", "出结论")
b.add_edge("出结论", "通知")
b.add_edge("通知", END)

graph = b.compile()
r = graph.invoke({"order_id": "SO-1", "log": [], "risk": 0.0, "decision": ""})
print("结果:", r["log"])
print(f"调风控实际执行: {ATTEMPTS['risk']} 次")
```

```typescript [TypeScript]
import { StateGraph, START, END, Annotation } from "@langchain/langgraph";

const Order = Annotation.Root({
  order_id: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  log: Annotation<string[]>({ reducer: (_p, n) => n, default: () => [] }),
  risk: Annotation<number>({ reducer: (_p, n) => n, default: () => 0 }),
  decision: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
});

const ATTEMPTS = { risk: 0 };

const checkStock = (s: typeof Order.State) => ({
  log: [...s.log, "查库存:有货"],
});

const callRisk = (s: typeof Order.State) => {
  ATTEMPTS.risk += 1;
  if (ATTEMPTS.risk < 3) {
    // TS 没有内置 ConnectionError，自定义同名类即可
    throw new ConnectionError(`风控接口抖动 ${ATTEMPTS.risk}`);
  }
  return { log: [...s.log, "调风控:成功"], risk: 0.3 };
};

const decide = (s: typeof Order.State) => {
  const d = s.risk < 0.7 ? "通过" : "拒绝";
  return { log: [...s.log, `出结论:${d}`], decision: d };
};

const notify = (s: typeof Order.State) => ({ log: [...s.log, `通知:${s.decision}`] });

const graph = new StateGraph(Order)
  .addNode("查库存", checkStock)
  .addNode("调风控", callRisk, {
    retryPolicy: {
      maxAttempts: 3,
      initialInterval: 10, // 毫秒（Python 是秒）
      logWarning: false,   // TS 独有字段，默认 true 会往 stdout 打重试日志
    },
  })
  .addNode("出结论", decide)
  .addNode("通知", notify)
  .addEdge(START, "查库存")
  .addEdge("查库存", "调风控")
  .addEdge("调风控", "出结论")
  .addEdge("出结论", "通知")
  .addEdge("通知", END)
  .compile();

const r = await graph.invoke({ order_id: "SO-1", log: [], risk: 0, decision: "" });
console.log("结果:", JSON.stringify(r.log));
console.log(`调风控实际执行: ${ATTEMPTS.risk} 次`);
```

:::


实测输出：

```
结果: ['查库存:有货', '调风控:成功', '出结论:通过', '通知:通过']
调风控实际执行: 3 次
```

TypeScript 侧（`npm run a10` 第一段）：

```
结果: ["查库存:有货","调风控:成功","出结论:通过","通知:通过"]
调风控实际执行: 3 次
```

> ✅ **只动了出错的那个节点**——`查库存`、`出结论`、`通知` 一行没改。这就是 per-node 配置的价值。
> 💡 这里抛的是 `ConnectionError`，属于默认 `retry_on` 认的"外部故障"，所以不用写 `retry_on`。

> ⚠️ **TS 侧有两处不能照抄**：① 参数名是 `retryPolicy: { maxAttempts, initialInterval }`，而且 `initialInterval` 的单位是**毫秒**（Python 是秒）——照抄 `initialInterval: 0.01` 等于配了 0.01 毫秒，退化成"立即狂重试"；② TS 多一个 `logWarning`，默认 `true`，每次重试都往 **stdout** 打一行 `Retrying task "调风控" after 442.18ms (attempt 1) ...`（Python 走 `logging`，默认打到 stderr）。要安静就得显式 `logWarning: false`。
> 💡 另外 TS 没有内置 `ConnectionError`，示例里是自定义了一个同名类；真实项目里这类故障通常是 `fetch` 抛出的 `TypeError: fetch failed`（`cause.code === "ECONNREFUSED"`）。

### 它的问题

1. **抛 `ValueError` 就不重试了**——换个异常类型试试就露馅。
2. **接口不是抖，是卡住了怎么办？**——重试只会让它卡更久。

> 🔑 **根因**：只做了"重试"，没做"哪些错该重试"和"多久算不行"。

---

## 第 2 跳：撞上两个硬约束（问题被逼出来的下一步）

**坑一：抛 `ValueError` 时，配了 retry 也不重试**

::: code-group

```python [Python]
ATTEMPTS2 = {"n": 0}


def call_risk_ve(state: Order) -> dict:
    ATTEMPTS2["n"] += 1
    raise ValueError("风控返回了非法数据")


b2 = StateGraph(Order)
b2.add_node("调风控", call_risk_ve,
            retry_policy=RetryPolicy(max_attempts=3, initial_interval=0.01))
b2.add_edge(START, "调风控")
b2.add_edge("调风控", END)
try:
    b2.compile().invoke({"order_id": "SO-2", "log": [], "risk": 0.0, "decision": ""})
except Exception as e:
    print(f"{type(e).__name__}: {e}")
print(f"调风控实际执行: {ATTEMPTS2['n']} 次   <- max_attempts=3 但只跑了 1 次")
```

```typescript [TypeScript]
const ATTEMPTS2 = { n: 0 };

const callRiskVe = (s: typeof Order.State) => {
  ATTEMPTS2.n += 1;
  // TS 没有独立的 ValueError，new Error 就是最"普通"的错误
  throw new Error("风控返回了非法数据");
};

const b2 = new StateGraph(Order)
  .addNode("调风控", callRiskVe, {
    retryPolicy: { maxAttempts: 3, initialInterval: 10, logWarning: false },
  })
  .addEdge(START, "调风控")
  .addEdge("调风控", END);

try {
  await b2.compile().invoke({ order_id: "SO-2", log: [], risk: 0, decision: "" });
} catch (e: any) {
  console.log(`${e.name}: ${e.message}`);
}
console.log(`调风控实际执行: ${ATTEMPTS2.n} 次   <- Python 是 1 次，TS 会跑满 3 次`);
```

:::


实测输出：

```
ValueError: 风控返回了非法数据
调风控实际执行: 1 次   <- max_attempts=3 但只跑了 1 次
```

TypeScript 侧（抛 `new Error("风控返回了非法数据")`）：

```
Error: 风控返回了非法数据
调风控实际执行: 3 次   <- Python 是 1 次，TS 跑满 maxAttempts
显式排除后: Error: 风控返回了非法数据
显式排除后实际执行: 1 次
```

> ❌ **配了等于没配。**
> 🔑 默认的 `retry_on` 把 `ValueError` 归为"代码 bug"——**重试一百次也一样错**。要重试就得显式 `retry_on=ValueError`，或者（更好的做法）定义一个**领域异常**。

> ⚠️ **这一条 TS 侧结论完全相反，是本课最需要小心的地方**：Python 的默认 `retry_on` 是**白名单**（`ValueError` / `TypeError` / `RuntimeError` / `OSError` 等一律不重试），TS 的默认是**黑名单**（源码 `dist/pregel/retry.js` 的 `DEFAULT_RETRY_ON_HANDLER`：只排除取消类、`GraphValueError`、`ECONNABORTED`、HTTP 400–407 与 409、`insufficient_quota`）。所以同一个 `new Error("...")`，Python 只跑 1 次、TS 老老实实跑满 3 次。
> ⚠️ 而且 TS 的 `retryOn` **只能传函数**——写 `retryOn: TypeError` 过不了类型检查，必须 `retryOn: (e) => e instanceof TypeError`。上例是用消息包含"非法数据"来演示"如何主动关掉重试"，生产里应该按错误码或错误类型判断。

**坑二：给同步节点配 timeout，编译期就炸**

::: code-group

```python [Python]
import time


def slow_sync(state: Order) -> dict:
    time.sleep(2)
    return {"log": state.get("log", []) + ["慢完成"]}


b3 = StateGraph(Order)
b3.add_node("调风控", slow_sync, timeout=0.5)
b3.add_edge(START, "调风控")
b3.add_edge("调风控", END)
try:
    b3.compile()
    print("compile 成功")
except Exception as e:
    print(f"compile -> {type(e).__name__}: {str(e)[:110]}")
```

```typescript [TypeScript]
const sleepSync = (ms: number) => {
  const t0 = Date.now();
  while (Date.now() - t0 < ms) {
    /* 同步阻塞 */
  }
};

const slowSync = (s: typeof Order.State) => {
  sleepSync(2000);
  return { log: [...s.log, "慢完成"] };
};

const b3 = new StateGraph(Order)
  .addNode("调风控", slowSync, { timeout: 500 }) // 毫秒
  .addEdge(START, "调风控")
  .addEdge("调风控", END);

const g3 = b3.compile(); // Python 在这一步就抛，TS 能过
try {
  const r = await g3.invoke({ order_id: "SO-3", log: [], risk: 0, decision: "" });
  console.log("invoke 返回:", JSON.stringify(r.log));
} catch (e: any) {
  console.log(`${e.name}: ${String(e.message).split("\n")[0]}`);
}
```

:::


实测输出：

```
compile -> ValueError: Node timeouts are only supported for async nodes because
sync Python execution cannot be safely cancelled in-process. Node '调风控' is sync.
```

TypeScript 侧（`timeout: 500`，节点同步阻塞 2 秒）：

```
compile 成功（TS 不像 Python 那样在编译期拦截同步节点 + timeout）
invoke -> NodeTimeoutError: Node "调风控" exceeded its run timeout of 500ms (elapsed: 2001ms).  elapsed=2003ms
```

> ❌ **连编译都过不去**——不是运行时静默失效，是 `compile()` 阶段就拦下。
> 🔑 原因：同步 Python 代码没法在进程内安全取消。**想用 `timeout`，节点必须是 `async def`。**

> ⚠️ **TS 侧这里又相反**：`compile()` 照常通过，等到 `invoke()` 才抛 `NodeTimeoutError`。注意报错里的 `elapsed: 2001ms`——同步节点根本停不下来，TS 是"让节点跑完，再把结果丢掉"，属于**事后判罚**。所以同样的 bug，Python 在启动时就告诉你，TS 要等线上真的卡了 2 秒才发现。
> 💡 单位同样是毫秒：`timeout: 500` 是 0.5 秒，Python 的 `timeout=0.5` 才是 0.5 秒。

> 💡 这两个坑的共性：**配置写了不代表生效**。容错配置是"声明式"的，错了要么静默不生效（坑一），要么在编译期炸给你看（坑二，还算友好）。

---

## 第 3 跳：重试 + 兜底 + 拆子图（综合）

![第 3 跳：重试 + 兜底 + 拆子图](./assets/app-step2-fault-tolerance.svg)

> 看图：风控拆成子图、内部各管各的容错；四块分别对应"自定义异常保证重试"、"同步配不了超时"、"兜底链"、"共享字段"。

### 第一步：用领域异常，保证一定重试

::: code-group

```python [Python]
class RiskAPIError(Exception):
    """风控接口故障 —— 属于可重试的外部故障"""


ATTEMPTS3 = {"n": 0}


def call_risk_v2(state: Order) -> dict:
    ATTEMPTS3["n"] += 1
    if ATTEMPTS3["n"] < 3:
        raise RiskAPIError(f"风控故障 {ATTEMPTS3['n']}")
    return {"log": state.get("log", []) + ["调风控:成功"], "risk": 0.3}


b4 = StateGraph(Order)
b4.add_node("调风控", call_risk_v2,
            retry_policy=RetryPolicy(max_attempts=3, initial_interval=0.01))
b4.add_edge(START, "调风控")
b4.add_edge("调风控", END)
r4 = b4.compile().invoke({"order_id": "SO-3", "log": [], "risk": 0.0, "decision": ""})
print("结果:", r4["log"])
print(f"实际执行: {ATTEMPTS3['n']} 次")
```

```typescript [TypeScript]
class RiskAPIError extends Error {
  constructor(m: string) {
    super(m);
    this.name = "RiskAPIError";
  }
}

const ATTEMPTS3 = { n: 0 };

const callRiskV2 = (s: typeof Order.State) => {
  ATTEMPTS3.n += 1;
  if (ATTEMPTS3.n < 3) throw new RiskAPIError(`风控故障 ${ATTEMPTS3.n}`);
  return { log: [...s.log, "调风控:成功"], risk: 0.3 };
};

const b4 = new StateGraph(Order)
  .addNode("调风控", callRiskV2, {
    retryPolicy: { maxAttempts: 3, initialInterval: 10, logWarning: false },
  })
  .addEdge(START, "调风控")
  .addEdge("调风控", END);

const r4 = await b4.compile().invoke({ order_id: "SO-3", log: [], risk: 0, decision: "" });
console.log("结果:", JSON.stringify(r4.log));
console.log(`实际执行: ${ATTEMPTS3.n} 次`);
```

:::


实测输出：

```
结果: ['调风控:成功']
实际执行: 3 次
```

TypeScript 侧：

```
结果: ["调风控:成功"]
实际执行: 3 次
```

> ✅ **自定义异常默认就重试**（`default_retry_on` 末尾 `return True`——不认识的异常反而算可重试）。
> 💡 TS 侧这条"反而是好消息"：因为默认是黑名单，自定义异常本来就会重试；`class RiskAPIError extends Error` 记得把 `this.name` 设成 `"RiskAPIError"`，否则日志里只会显示 `Error`。
> 💡 **这比 `retry_on=ValueError` 更好**：异常类型本身就携带了"这是外部故障"的语义。

### 第二步：加兜底，重试用尽也不炸图

::: code-group

```python [Python]
def risk_fallback(state) -> dict:
    print(f"  兜底收到 state: log={state.get('log')}")
    return {"log": state.get("log", []) + ["调风控:兜底放行"], "risk": 0.5}


ATTEMPTS4 = {"n": 0}


def always_down(state: Order) -> dict:
    ATTEMPTS4["n"] += 1
    raise RiskAPIError("风控彻底挂了")


b5 = StateGraph(Order)
b5.add_node("查库存", check_stock)
b5.add_node("调风控", always_down,
            retry_policy=RetryPolicy(max_attempts=2, initial_interval=0.01),
            error_handler=risk_fallback)
b5.add_node("出结论", decide)
b5.add_node("通知", notify)
b5.add_edge(START, "查库存")
b5.add_edge("查库存", "调风控")
b5.add_edge("调风控", "出结论")
b5.add_edge("出结论", "通知")
b5.add_edge("通知", END)

r5 = b5.compile().invoke({"order_id": "SO-4", "log": [], "risk": 0.0, "decision": ""})
print("结果:", r5["log"])
print(f"调风控执行: {ATTEMPTS4['n']} 次（重试用尽后才走兜底）")
```

```typescript [TypeScript]
const riskFallback = (state: typeof Order.State) => {
  console.log(`  兜底收到 state: log=${JSON.stringify(state.log)}`);
  return { log: [...state.log, "调风控:兜底放行"], risk: 0.5 };
};

const ATTEMPTS4 = { n: 0 };

const alwaysDown = (s: typeof Order.State) => {
  ATTEMPTS4.n += 1;
  throw new RiskAPIError("风控彻底挂了");
};

const b5 = new StateGraph(Order)
  .addNode("查库存", checkStock)
  .addNode("调风控", alwaysDown, {
    retryPolicy: { maxAttempts: 2, initialInterval: 10, logWarning: false },
    errorHandler: riskFallback,
  })
  .addNode("出结论", decide)
  .addNode("通知", notify)
  .addEdge(START, "查库存")
  .addEdge("查库存", "调风控")
  .addEdge("调风控", "出结论")
  .addEdge("出结论", "通知")
  .addEdge("通知", END);

const r5 = await b5.compile().invoke({ order_id: "SO-4", log: [], risk: 0, decision: "" });
console.log("结果:", JSON.stringify(r5.log));
console.log(`调风控执行: ${ATTEMPTS4.n} 次（重试用尽后才走兜底）`);
```

:::


实测输出：

```
  兜底收到 state: log=['查库存:有货']
结果: ['查库存:有货', '调风控:兜底放行']
调风控执行: 2 次（重试用尽后才走兜底）
```

TypeScript 侧：

```
  兜底收到 state: log=["查库存:有货"]
结果: ["查库存:有货","调风控:兜底放行"]
调风控执行: 2 次（重试用尽后才走兜底）
```

> ⚠️ **注意：结果里没有"出结论"和"通知"！**
>
> 🔑 因为 `error_handler` 的返回值**直接结束了这个分支**——它不像普通节点那样接着走 `调风控 → 出结论 → 通知` 的边。实测只到"兜底放行"就停了。
>
> 💡 **要让它继续往下走**，有两个办法：① 兜底里把该做的都做完（自包含）；② 用 `Command(goto=...)` 显式跳转（课 4 学过）。这是 `error_handler` 最容易踩的坑——**兜底完流程就断了**。

改法（用 `Command` 续上）：

::: code-group

```python [Python]
from langgraph.types import Command


def risk_fallback_goto(state) -> dict:
    return Command(goto="出结论",
                   update={"log": state.get("log", []) + ["调风控:兜底放行"], "risk": 0.5})
```

```typescript [TypeScript]
import { Command } from "@langchain/langgraph";

const riskFallbackGoto = (state: typeof Order.State) =>
  new Command({
    goto: "出结论",
    update: { log: [...state.log, "调风控:兜底放行"], risk: 0.5 },
  });

// ⚠️ 要让 errorHandler 返回的 Command 生效，必须在 addNode 的 ends 里声明去处：
// .addNode("调风控", alwaysDown, { errorHandler: riskFallbackGoto, ends: ["出结论"] })
// 漏写会抛 UnreachableNodeError（编译期）
```

:::


实测（已验证）：

```
Command(goto='出结论') -> ['查库存:有货', '调风控:兜底放行', '出结论:通过', '通知:通过']
decision = 通过
调风控执行 2 次
```

TypeScript 侧：

```
Command({goto:'出结论'}) -> ["查库存:有货","调风控:兜底放行","出结论:通过","通知:通过"]
decision = 通过
调风控执行 2 次
```

> ⚠️ **TS 侧还要多做一步**：`Command` 必须 `new Command({ goto, update })`（Python 是 `Command(goto=..., update=...)`），而且**要在 `addNode` 的第 3 个参数里用 `ends: ["出结论"]` 声明去处**，否则编译期直接抛 `UnreachableNodeError`。这是课 4、课 10 都踩过的同一条护栏——TS 侧对 `Command` 的去向是静态校验的。

> ✅ **流程完整续上了**——`出结论`、`通知` 都跑到了，`decision` 也正常产出。
> 🔑 **判据**：兜底返回值是**普通 dict** → 流程到此为止；返回 **`Command(goto=...)`** → 能跳到指定节点继续。**这是 `error_handler` 最容易踩的坑。**
> ⚠️ 注意 `error_handler` 是**单参数**（只收 state）。想拿异常要从 `config` 里翻：

::: code-group

```python [Python]
def risk_fallback_v2(state, config) -> dict:
    err = config.get("configurable", {}).get("__pregel_node_error")
    return {"log": state.get("log", []) + [f"兜底:{type(err).__name__}"], "risk": 0.5}
```

```typescript [TypeScript]
// ⚠️ TS 的 errorHandler 是 (state, error, config?) —— 异常就在第二个参数位
//    没有 Python 那个 config["configurable"]["__pregel_node_error"]
//    而且第二参数被包了一层 NodeError：{ node, error }
const riskFallbackV2 = (state: typeof Order.State, error: any) => {
  const err = error?.error ?? error; // 解包拿真正的异常
  return { log: [...state.log, `兜底:${err?.name}`], risk: 0.5 };
};

// 实测 err = { node: "调风控", error: RiskAPIError("风控彻底挂了") }
//      Object.keys(err) === ["node", "error"]，err.message === undefined
```

:::


实测 `err` 是 `NodeError(node='调风控', error=RiskAPIError('风控彻底挂了'))`。

### 第三步：async 节点才配得上 timeout

::: code-group

```python [Python]
import asyncio


async def slow_async(state: Order) -> dict:
    await asyncio.sleep(2)
    return {"log": state.get("log", []) + ["慢完成"]}


b6 = StateGraph(Order)
b6.add_node("调风控", slow_async, timeout=0.4, error_handler=risk_fallback)
b6.add_edge(START, "调风控")
b6.add_edge("调风控", END)
r6 = asyncio.run(b6.compile().ainvoke({"order_id": "SO-5", "log": [], "risk": 0.0, "decision": ""}))
print("结果:", r6["log"])
```

```typescript [TypeScript]
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

const slowAsync = async (s: typeof Order.State) => {
  await sleep(2000);
  return { log: [...s.log, "慢完成"] };
};

const b6 = new StateGraph(Order)
  .addNode("调风控", slowAsync, {
    timeout: 400, // 毫秒
    errorHandler: riskFallback,
  })
  .addEdge(START, "调风控")
  .addEdge("调风控", END);

const r6 = await b6.compile().invoke({ order_id: "SO-5", log: [], risk: 0, decision: "" });
console.log("结果:", JSON.stringify(r6.log));
```

:::


实测输出：

```
  兜底收到 state: log=[]
结果: ['调风控:兜底放行']
```

TypeScript 侧（`timeout: 400` + 兜底）：

```
  兜底收到 state: log=[]
结果: ["调风控:兜底放行"]
```

`timeout × retry` 叠乘（`timeout: 300` + `maxAttempts: 3`）：

```
timeout×retry 叠乘: ["调风控:兜底放行"]  执行 3 次  耗时 1536ms
```

> ✅ **超时 0.4s 触发，走了兜底**——超时和兜底是串在一条链上的。
> ⚠️ **timeout 和 retry 会叠乘**：`timeout=0.3` + `max_attempts=3` 实测耗时 1.35s。配的时候要算总时长。

### 第四步：把风控拆成子图

::: code-group

```python [Python]
class RiskIn(TypedDict):
    order_id: str
    log: list
    risk: float


risk_b = StateGraph(RiskIn)
risk_b.add_node("调风控", call_risk_v2,
                retry_policy=RetryPolicy(max_attempts=3, initial_interval=0.01),
                error_handler=risk_fallback)
risk_b.add_node("判定", lambda s: {"log": s.get("log", []) + [f"风控判定:{s['risk']}"]})
risk_b.add_edge(START, "调风控")
risk_b.add_edge("调风控", "判定")
risk_b.add_edge("判定", END)
risk_sub = risk_b.compile()

main_b = StateGraph(Order)
main_b.add_node("查库存", check_stock)
main_b.add_node("风控", risk_sub)          # ← 编译好的图当节点挂
main_b.add_node("出结论", decide)
main_b.add_node("通知", notify)
main_b.add_edge(START, "查库存")
main_b.add_edge("查库存", "风控")
main_b.add_edge("风控", "出结论")
main_b.add_edge("出结论", "通知")
main_b.add_edge("通知", END)

ATTEMPTS3["n"] = 0
r7 = main_b.compile().invoke({"order_id": "SO-6", "log": [], "risk": 0.0, "decision": ""})
print("结果:", r7["log"])
print(f"子图内调风控执行: {ATTEMPTS3['n']} 次")
```

```typescript [TypeScript]
const RiskIn = Annotation.Root({
  order_id: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  log: Annotation<string[]>({ reducer: (_p, n) => n, default: () => [] }),
  risk: Annotation<number>({ reducer: (_p, n) => n, default: () => 0 }),
});

const riskSub = new StateGraph(RiskIn)
  .addNode("调风控", callRiskV2 as any, {
    retryPolicy: { maxAttempts: 3, initialInterval: 10, logWarning: false },
    errorHandler: riskFallback as any,
  })
  .addNode("判定", (s: typeof RiskIn.State) => ({
    log: [...s.log, `风控判定:${s.risk}`],
  }))
  .addEdge(START, "调风控")
  .addEdge("调风控", "判定")
  .addEdge("判定", END)
  .compile();

const mainB = new StateGraph(Order)
  .addNode("查库存", checkStock)
  .addNode("风控", riskSub) // ← 编译好的图当节点挂
  .addNode("出结论", decide)
  .addNode("通知", notify)
  .addEdge(START, "查库存")
  .addEdge("查库存", "风控")
  .addEdge("风控", "出结论")
  .addEdge("出结论", "通知")
  .addEdge("通知", END);

ATTEMPTS3.n = 0;
const r7 = await mainB.compile().invoke({ order_id: "SO-6", log: [], risk: 0, decision: "" });
console.log("结果:", JSON.stringify(r7.log));
console.log(`子图内调风控执行: ${ATTEMPTS3.n} 次`);
```

:::


实测输出：

```
结果: ['查库存:有货', '调风控:成功', '风控判定:0.3', '出结论:通过', '通知:通过']
子图内调风控执行: 3 次
```

TypeScript 侧：

```
结果: ["查库存:有货","调风控:成功","风控判定:0.3","出结论:通过","通知:通过"]
子图内调风控执行: 3 次
```

> ✅ **重试配在子图内部节点上才生效**——配在父图的 `add_node("风控", risk_sub)` 上管不到里面。
> ✅ 主流程清爽了：风控那一坨（调接口 + 重试 + 兜底 + 判定）收进一个节点。

### 第五步：撞"状态隔离"——字段为什么没了

给子图加个父图没有的字段：

::: code-group

```python [Python]
class RiskIn2(TypedDict):
    order_id: str
    log: list
    risk: float
    risk_detail: str        # ← 子图私有，父图没声明


risk_b2 = StateGraph(RiskIn2)
risk_b2.add_node("调风控", lambda s: {"risk": 0.3, "risk_detail": "评分明细",
                                      "log": s.get("log", []) + ["调风控:成功"]})
risk_b2.add_edge(START, "调风控")
risk_b2.add_edge("调风控", END)
sub2 = risk_b2.compile()

main_b2 = StateGraph(Order)
main_b2.add_node("风控", sub2)
main_b2.add_node("出结论", lambda s: {"log": s.get("log", []) + [f"父图keys={sorted(s.keys())}"]})
main_b2.add_edge(START, "风控")
main_b2.add_edge("风控", "出结论")
main_b2.add_edge("出结论", END)

r8 = main_b2.compile().invoke({"order_id": "SO-7", "log": [], "risk": 0.0, "decision": ""})
print("结果:", r8["log"])
print("父图最终 keys:", sorted(r8.keys()))
```

```typescript [TypeScript]
const RiskIn2 = Annotation.Root({
  order_id: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  log: Annotation<string[]>({ reducer: (_p, n) => n, default: () => [] }),
  risk: Annotation<number>({ reducer: (_p, n) => n, default: () => 0 }),
  risk_detail: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }), // ← 子图私有
});

const sub2 = new StateGraph(RiskIn2)
  .addNode("调风控", (s: typeof RiskIn2.State) => ({
    risk: 0.3,
    risk_detail: "评分明细",
    log: [...s.log, "调风控:成功"],
  }))
  .addEdge(START, "调风控")
  .addEdge("调风控", END)
  .compile();

const mainB2 = new StateGraph(Order)
  .addNode("风控", sub2)
  .addNode("出结论", (s: typeof Order.State) => ({
    log: [...s.log, `父图keys=${JSON.stringify(Object.keys(s).sort())}`],
  }))
  .addEdge(START, "风控")
  .addEdge("风控", "出结论")
  .addEdge("出结论", END);

const r8 = await mainB2.compile().invoke({ order_id: "SO-7", log: [], risk: 0, decision: "" });
console.log("结果:", JSON.stringify(r8.log));
console.log("父图最终 keys:", JSON.stringify(Object.keys(r8).sort()));
```

:::


实测输出：

```
结果: ['调风控:成功', "父图keys=['decision', 'log', 'order_id', 'risk']"]
父图最终 keys: ['decision', 'log', 'order_id', 'risk']
```

TypeScript 侧：

```
结果: ["调风控:成功","父图keys=[\"decision\",\"log\",\"order_id\",\"risk\"]"]
父图最终 keys: ["decision","log","order_id","risk"]
```

> ❌ **`risk_detail` 静默消失了**——不报错、不警告。
> 🔑 **想让子图结果传出来，必须在父图 State 里也声明那个字段。** 反向同理：父图独有的字段子图也收不到。

### 第六步：子图内部排障要开 subgraphs=True

::: code-group

```python [Python]
from langgraph.checkpoint.memory import InMemorySaver

g9 = main_b.compile(checkpointer=InMemorySaver())
cfg = {"configurable": {"thread_id": "so-8"}}
g9.invoke({"order_id": "SO-8", "log": [], "risk": 0.0, "decision": ""}, config=cfg)

print("默认视角（父图历史）:")
for s in g9.get_state_history(cfg):
    print(f"  ns={s.config['configurable'].get('checkpoint_ns')!r:6s} next={str(s.next)}")

print("subgraphs=True 视角:")
for ns, chunk in g9.stream({"order_id": "SO-9", "log": [], "risk": 0.0, "decision": ""},
                            {"configurable": {"thread_id": "so-9"}},
                            stream_mode="updates", subgraphs=True):
    print(f"  ns={ns}  chunk={list(chunk.keys())}")
```

```typescript [TypeScript]
const saver = new MemorySaver();
const g9 = mainB.compile({ checkpointer: saver });
const cfg = { configurable: { thread_id: "so-8" } };
await g9.invoke({ order_id: "SO-8", log: [], risk: 0, decision: "" }, cfg);

console.log("默认视角（父图历史）:");
// ⚠️ getStateHistory 返回异步迭代器，外层还要 await
for await (const s of await g9.getStateHistory(cfg)) {
  const ns = s.config?.configurable?.checkpoint_ns ?? "";
  console.log(`  ns=${JSON.stringify(ns).padEnd(5)} next=${JSON.stringify(s.next)}`);
}

console.log("subgraphs: true 视角:");
// ⚠️ TS 的 stream 第二参数同时承载 config 与流选项（Python 是三个位置参数）
for await (const pair of (await g9.stream(
  { order_id: "SO-9", log: [], risk: 0, decision: "" },
  { streamMode: "updates", subgraphs: true, configurable: { thread_id: "so-9" } }
)) as any) {
  const [ns, chunk] = pair as [string[], Record<string, unknown>];
  // ⚠️ TS 的 chunk 是「节点名 → 输出」映射，ns 是数组（Python 是元组）
  console.log(`  ns=${JSON.stringify(ns)}  chunk=${JSON.stringify(Object.keys(chunk))}`);
}
```

:::


实测输出：

```
默认视角（父图历史）:
  ns=''     next=()
  ns=''     next=('通知',)
  ns=''     next=('出结论',)
  ns=''     next=('风控',)
  ns=''     next=('查库存',)
  ns=''     next=('__start__',)
subgraphs=True 视角:
  ns=()                                              chunk=['查库存']
  ns=('风控:e51a716e-3fc2-53ce-cfcf-552753981193',)  chunk=['调风控']
  ns=('风控:e51a716e-3fc2-53ce-cfcf-552753981193',)  chunk=['判定']
  ns=()                                              chunk=['风控']
  ns=()                                              chunk=['出结论']
  ns=()                                              chunk=['通知']
```

TypeScript 侧：

```
默认视角（父图历史）:
  ns=""    next=[]
  ns=""    next=["通知"]
  ns=""    next=["出结论"]
  ns=""    next=["风控"]
  ns=""    next=["查库存"]
  ns=""    next=["__start__"]
subgraphs: true 视角:
  ns=[]                                             chunk=["查库存"]
  ns=["风控:ebf7bf5c-c666-5d78-969e-1715d253d329"]  chunk=["调风控"]
  ns=["风控:ebf7bf5c-c666-5d78-969e-1715d253d329"]  chunk=["判定"]
  ns=[]                                             chunk=["风控"]
  ns=[]                                             chunk=["出结论"]
  ns=[]                                             chunk=["通知"]
```

> ⚠️ **三处形态差异**：① `next` 是数组（`[]`）不是元组（`()`）；② `ns` 是数组（`[]`）不是元组（`()`）；③ **`stream()` 的第二参数同时承载 config 与流选项**——Python 是 `stream(输入, config, stream_mode=..., subgraphs=True)` 三个位置参数，TS 要写成 `stream(输入, { streamMode: "updates", subgraphs: true, configurable: { thread_id } })`，config 和流选项合在一个对象里。另外 TS 的 chunk 是「节点名 → 输出」的映射，取键才能看到节点名。

> ⚠️ 注意 `subgraphs=True` 的输出顺序：**父图的 `查库存` 排在最前，子图内部两步夹在中间**，最后才是父图视角的 `风控` 汇总——**子图的事件是"就地插入"的，不是集中排在末尾**。

> ✅ **课 9 埋的 `checkpoint_ns` 伏笔在这里兑现**：子图命名空间是 `节点名:uuid`（主图是 `''`）。
> ⚠️ 但 `get_state_history` 里全是 `ns=''`——**命名空间只在 `subgraphs=True` 里显形**。子图内部卡住了，不开这个开关你只知道"风控这一步出事了"，不知道卡在第几个节点。

---

## 收尾：三跳带走了什么

| 跳 | 关键代码 | 得到的认识 |
|:--:|---------|-----------|
| 1 | `retry_policy=RetryPolicy(max_attempts=3)` | 只动出错的节点；但抛 ValueError 不重试 |
| 2 | 抛 ValueError / 同步配 timeout | **配置写了 ≠ 生效**：默认 retry_on 挑异常；同步在编译期就炸 |
| 3 | 领域异常 + error_handler + 子图 | 自定义异常默认重试；兜底单参；子图只传共享字段 |

**五条提醒**：

1. **默认 `retry_on` 不认 `ValueError`/`RuntimeError`/`TypeError`**——用领域异常（如 `RiskAPIError`）最稳。
2. **`error_handler` 是 `(state)` 单参数**——异常在 `config['configurable']['__pregel_node_error']`。
3. **同步节点配 `timeout` 编译期就抛错**——要 `async def` + `ainvoke`。
4. **`timeout` × `retry` 会叠乘**——配之前算好最坏总时长。
5. **子图只传共享字段**——私有的静默丢弃；排障要开 `subgraphs=True`。

🎯 **会用标志**：能给易失败节点独立配重试与兜底并解释"为什么抛 ValueError 不重试"，能把一段流程拆成子图并说清哪些字段传得出来、哪些会丢，能用 `subgraphs=True` 定位子图内部卡在第几步。

### 🇹🇸 五条提醒在 TS 侧是否还成立

| # | Python 说法 | TS 侧实测 |
|:--:|------------|-----------|
| 1 | 默认 `retry_on` 不认 `ValueError`/`RuntimeError`/`TypeError` | ❌ **不成立**：TS 默认是黑名单，普通 `Error` 照样重试；要"不重试"必须写 `retryOn` 函数 |
| 2 | `error_handler` 是 `(state)` 单参数，异常在 `config['configurable']['__pregel_node_error']` | ⚠️ **不同**：TS 是 `(state, error, config?)`，异常在第二参数，且被 `NodeError { node, error }` 包了一层，那个 config key 不存在 |
| 3 | 同步节点配 `timeout` 编译期就抛错 | ❌ **不成立**：TS `compile()` 照常通过，`invoke()` 才抛 `NodeTimeoutError`（且是事后判罚） |
| 4 | `timeout` × `retry` 会叠乘 | ✅ 成立：`timeout: 300` + `maxAttempts: 3` 实测 1536ms、执行 3 次 |
| 5 | 子图只传共享字段，私有的静默丢弃 | ✅ 成立：`risk_detail` 静默消失，父图 keys 仍是那 4 个 |

### 🇹🇸 TS 写法对照表

| Python | TypeScript |
|--------|-----------|
| `RetryPolicy(max_attempts=3, initial_interval=0.01)` | `retryPolicy: { maxAttempts: 3, initialInterval: 10 }`（毫秒） |
| `retry_on=ValueError` | `retryOn: (e) => e instanceof TypeError`（只能传函数） |
| `timeout=0.5` | `timeout: 500`（毫秒） |
| `error_handler=fn`，`fn(state)` | `errorHandler: fn`，`fn(state, error)`，`error.error` 才是原异常 |
| `error_handler` 返回 `Command(goto=...)` | 返回 `new Command({ goto })`，并在 `addNode` 加 `ends: [...]` |
| `custom exception` 默认重试（白名单机制） | 默认也重试，但原因相反（黑名单兜底） |
| `stream(inp, cfg, stream_mode="updates", subgraphs=True)` | `stream(inp, { streamMode: "updates", subgraphs: true, configurable: cfg })` |
| `next=('通知',)` / `ns=('风控:uuid',)` | `next=["通知"]` / `ns=["风控:uuid"]` |
