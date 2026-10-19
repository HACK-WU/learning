# 应用实战 09：客户投诉后改判，还要留住事故现场

> 对应：[课 9 Time-travel 回放与分叉](../stages/3-可控性与人在环中/lessons/09-Time-travel%20回放与分叉.md)
> 覆盖知识点：历史回放 / 分叉重跑
> ✅ 全部代码实测于 langgraph 1.2.11 / Python 3.12（在 `../langchain/playground` 以 `uv run` 隔离执行）
> ✅ TypeScript 侧实测于 `playground-ts/`（`@langchain/langgraph` 1.5.1 / Node 22，`npm run a09`）

## 场景

退款申请被自动驳回，客户投诉。客服主管问："当时为什么判驳回？能改判吗？"

三跳演进：

| 跳 | 目标 | 新增的知识点 |
|:--:|------|-------------|
| 基础 | 翻回看清"当时为什么判驳回" | get_state_history / StateSnapshot / parent_config |
| 问题 | 想改判又想留证据，结果状态丢了 | 跨 thread 分叉的状态丢失 |
| 综合 | 改判 + 留住事故现场 | 同/跨 thread 取舍 / 手工搬 values / 只重跑后面 |

> 完整方案还需要：快照的持久化与定期清理（InMemorySaver 进程一退就没）、改判操作的权限与审计日志、并发下同一 thread 的互斥、跨 thread 复制存档时 `pending writes` 的处理——**这些都不是本课内容**（课 12 测试 / 课 13 部署时展开）。

---

## 第 1 跳：翻回看清"当时为什么判驳回"（基础）

![第 1 跳：翻回看](./assets/app-step1-time-travel.svg)

> 看图：左右是同一次执行，区别只在你能不能看到中间那几步。`get_state_history` 把 5 条快照从新到旧列出来，金额和判定依据全在。

::: code-group
```python [Python]
from langgraph.checkpoint.memory import InMemorySaver
from langgraph.graph import END, START, StateGraph
from typing_extensions import TypedDict


class Refund(TypedDict):
    log: list
    amount: int
    risk: float
    decision: str


def lookup(state: Refund) -> dict:
    return {"log": state.get("log", []) + [f"查订单:金额{state['amount']}"]}


def score(state: Refund) -> dict:
    risk = 0.9 if state["amount"] > 1000 else 0.2
    return {"log": state.get("log", []) + [f"算风险:risk={risk}"], "risk": risk}


def decide(state: Refund) -> dict:
    d = "驳回" if state["risk"] > 0.7 else "批准"
    return {"log": state.get("log", []) + [f"判定:{d}"], "decision": d}


def notify(state: Refund) -> dict:
    return {"log": state.get("log", []) + [f"通知:{state['decision']}"]}


b = StateGraph(Refund)
for n, f in [("查订单", lookup), ("算风险", score), ("判定", decide), ("通知", notify)]:
    b.add_node(n, f)
b.add_edge(START, "查订单")
b.add_edge("查订单", "算风险")
b.add_edge("算风险", "判定")
b.add_edge("判定", "通知")
b.add_edge("通知", END)

graph = b.compile(checkpointer=InMemorySaver())
cfg = {"configurable": {"thread_id": "投诉单A"}}

result = graph.invoke({"log": [], "amount": 5000, "risk": 0.0, "decision": ""}, config=cfg)
print("结果:", result["decision"])
print()
print("历史（新 -> 旧）:")
for i, s in enumerate(graph.get_state_history(cfg)):
    print(f"  [{i}] next={str(s.next):12s} step={s.metadata.get('step'):>2} "
          f"source={s.metadata.get('source'):6s} log={s.values.get('log')}")
```

```typescript [TypeScript]
import { Annotation, END, MemorySaver, START, StateGraph } from "@langchain/langgraph";

const Refund = Annotation.Root({
  log: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
  amount: Annotation<number>({ reducer: (_p, n) => n, default: () => 0 }),
  risk: Annotation<number>({ reducer: (_p, n) => n, default: () => 0 }),
  decision: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
});

const lookup = (s: typeof Refund.State) => ({ log: [`查订单:金额${s.amount}`] });
const score = (s: typeof Refund.State) => {
  const risk = s.amount > 1000 ? 0.9 : 0.2;
  return { log: [`算风险:risk=${risk}`], risk };
};
const decide = (s: typeof Refund.State) => {
  const d = s.risk > 0.7 ? "驳回" : "批准";
  return { log: [`判定:${d}`], decision: d };
};
const notify = (s: typeof Refund.State) => ({ log: [`通知:${s.decision}`] });

const graph = new StateGraph(Refund)
  .addNode("查订单", lookup)
  .addNode("算风险", score)
  .addNode("判定", decide)
  .addNode("通知", notify)
  .addEdge(START, "查订单")
  .addEdge("查订单", "算风险")
  .addEdge("算风险", "判定")
  .addEdge("判定", "通知")
  .addEdge("通知", END)
  .compile({ checkpointer: new MemorySaver() });

const cfg = { configurable: { thread_id: "投诉单A" } };

const result = await graph.invoke({ log: [], amount: 5000, risk: 0, decision: "" }, cfg);
console.log("结果:", result.decision);
console.log("\n历史（新 -> 旧）:");

// ⚠️ getStateHistory 返回异步迭代器，外层还要 await
const hist: any[] = [];
for await (const s of await graph.getStateHistory(cfg)) hist.push(s);
hist.forEach((s, i) => {
  console.log(
    `  [${i}] next=${JSON.stringify(s.next).padEnd(14)} step=${String(s.metadata?.step).padStart(2)} ` +
      `source=${String(s.metadata?.source).padEnd(6)} log=${JSON.stringify(s.values.log)}`
  );
});
```
:::

实测输出：

实测（Python）：

```
结果: 驳回

历史（新 -> 旧）:
  [0] next=()          step= 4 source=loop   log=['查订单:金额5000', '算风险:risk=0.9', '判定:驳回', '通知:驳回']
  [1] next=('通知',)    step= 3 source=loop   log=['查订单:金额5000', '算风险:risk=0.9', '判定:驳回']
  [2] next=('判定',)    step= 2 source=loop   log=['查订单:金额5000', '算风险:risk=0.9']
  [3] next=('算风险',)  step= 1 source=loop   log=['查订单:金额5000']
  [4] next=('查订单',)  step= 0 source=loop   log=[]
  [5] next=('__start__',) step=-1 source=input log=None
```

实测（TypeScript，`npm run a09`）：

```
结果: 驳回

历史（新 -> 旧）:
  [0] next=[]             step= 4 source=loop   log=["查订单:金额5000","算风险:risk=0.9","判定:驳回","通知:驳回"]
  [1] next=["通知"]         step= 3 source=loop   log=["查订单:金额5000","算风险:risk=0.9","判定:驳回"]
  [2] next=["判定"]         step= 2 source=loop   log=["查订单:金额5000","算风险:risk=0.9"]
  [3] next=["算风险"]        step= 1 source=loop   log=["查订单:金额5000"]
  [4] next=["查订单"]        step= 0 source=loop   log=[]
  [5] next=["__start__"]  step=-1 source=input  log=[]
```

> ✅ **4 个节点 6 条历史**——多出"跑完"和"输入"两张（课 9 验证一）。TS 侧同样 6 条，`step` / `source` 完全对齐。

> 💡 TS 侧三处形态差异：①`next` 是数组 `[]` / `["判定"]`，Python 是元组 `()` / `('判定',)`；②`getStateHistory` **返回异步迭代器**，要 `for await (const s of await graph.getStateHistory(cfg))`——两个 `await` 分工不同；③`source=input` 那条的 `log` 在 TS 是 `[]`（字段有 `default`），Python 是 `None`（没写过）。

客服主管要的答案在第 2 条：`risk=0.9`，因为金额 5000 > 1000。

看看这个点：

::: code-group
```python [Python]
hist = list(graph.get_state_history(cfg))
at_decide = hist[2]
print(f"判定前: next={at_decide.next}")
print(f"        risk={at_decide.values['risk']} amount={at_decide.values['amount']}")
print(f"        parent -> step={at_decide.parent_config is not None}")
```

```typescript [TypeScript]
const hist: any[] = [];
for await (const s of await graph.getStateHistory(cfg)) hist.push(s);
const atDecide = hist[2];
console.log(`判定前: next=${JSON.stringify(atDecide.next)}`);
console.log(`        risk=${atDecide.values.risk} amount=${atDecide.values.amount}`);
// ⚠️ TS 是驼峰 parentConfig，Python 是 parent_config
console.log(`        parentConfig 存在=${atDecide.parentConfig != null}`);
```
:::

实测输出：

实测（Python）：

```
判定前: next=('判定',)
        risk=0.9 amount=5000
        parent -> step=True
```

实测（TypeScript）：

```
判定前: next=["判定"]
        risk=0.9 amount=5000
        parentConfig 存在=true
```

> ⚠️ **这只是"看"**——打完这句，图的最新状态仍是 `next=()`，什么都没变。

> 💡 TS 侧字段是驼峰 `parentConfig`（Python 是 `parent_config`）；脚本里另外打印了一行「看完之后最新状态: next=[]」确认只读，两侧行为一致。

### 它的问题

1. **看到了，但改不了**——判错的那一步还是判错了。
2. **改判会不会把事故现场冲掉？**——主管要求"原始执行必须留档"。

> 🔑 **根因**：还没做"从历史点改状态并重跑"这一步。

---

## 第 2 跳：撞跨 thread 状态丢失（问题被逼出来的下一步）

主管要留证据，于是你换了 `thread_id` 再改判——**看起来很合理**：

::: code-group
```python [Python]
new_thread = {"configurable": {"thread_id": "投诉单A-改判"}}
bad_cfg = {"configurable": {**at_decide.config["configurable"], "thread_id": "投诉单A-改判"}}

print("改判前，新 thread 里有什么：")
print(" ", graph.get_state(bad_cfg).values)

graph.update_state(bad_cfg, {"decision": "批准"})
st = graph.get_state(new_thread)
print("update 之后:")
print(f"  next   = {st.next}")
print(f"  values = {st.values}")
```

```typescript [TypeScript]
const newThread = { configurable: { thread_id: "投诉单A-改判" } };
const badCfg = {
  configurable: {
    ...atDecide.config.configurable,
    thread_id: "投诉单A-改判",
  },
};

console.log("改判前，新 thread 里有什么：");
console.log(" ", JSON.stringify((await graph.getState(newThread)).values));

await graph.updateState(badCfg, { decision: "批准" });
const st = await graph.getState(newThread);
console.log("update 之后:");
console.log(`  next   = ${JSON.stringify(st.next)}`);
console.log(`  values = ${JSON.stringify(st.values)}`);
```
:::

实测输出：

实测（Python）：

```
改判前，新 thread 里有什么：
  {}
update 之后:
  next   = ('查订单',)
  values = {'decision': '批准'}
```

实测（TypeScript）：

```
改判前，新 thread 里有什么：
  {}
update 之后:
  next   = ["查订单"]
  values = {"log":[],"amount":0,"risk":0,"decision":"批准"}
```

> ❌ **`log` 整个丢了，只剩 `decision`；`next` 回到 `('查订单',)`。**

> ⚠️ **这一条的 TS 表现比 Python 温和，但同样错**：TS 的 `Annotation` 每个字段都有 `default`，所以 `values` 不会是「只有 decision」的残缺对象，而是「其余字段回落到默认值」——`log: []`、`amount: 0`、`risk: 0`。看起来像"完整状态"，实际是**空档案套了个壳**，比 Python 的显式残缺更容易误判。
> 🔑 因为换了 `thread_id` 后，那个 `checkpoint_id` 在新 thread 里**根本不存在**（上面 `get_state` 返回 `{}`）——`update_state` 是在**空状态**上做的更新。

跑一下看后果：

::: code-group
```python [Python]
try:
    r = graph.invoke(None, config=new_thread)
    print("跑完:", r["log"])
except Exception as e:
    print(f"{type(e).__name__}: {e}")
```

```typescript [TypeScript]
try {
  const r = await graph.invoke(null, newThread);
  console.log("跑完:", JSON.stringify(r.log));
} catch (e: any) {
  console.log(`${e.name}: ${e.message.split("\n")[0]}`);
}
```
:::

实测输出：

实测（Python）：

```
KeyError: 'amount'
  at 查订单节点：state.get("log", []) + [f"查订单:金额{state['amount']}"]
```

实测（TypeScript）：

```
跑完: ["查订单:金额0","算风险:risk=0.2","判定:批准","通知:批准"]
```

> ❌ **直接崩了**——不只是"状态丢了"这么温和。因为 `amount` 根本没被带过去，第一个节点一读就 `KeyError`。
> 🔑 这就是"只搬一个字段"的真实下场：**不是结果不对，是跑不起来**。

> ⚠️ **TS 侧这条恰好反过来，而且更危险**：`amount` 有 `default: () => 0`，所以不报错、图正常跑完，只是**金额变成了 0**——`查订单:金额0`、`risk=0.2`、`判定:批准`。一笔 5000 元的退款在 TS 侧会"顺利通过"而无人察觉。**Python 崩在明面上，TS 错在暗处**，移植时务必注意。

对比一下**同 thread 分叉**：

::: code-group
```python [Python]
same = graph.update_state(at_decide.config, {"decision": "批准"})
st2 = graph.get_state(same)
print(f"同 thread: next={st2.next}")
print(f"           values={st2.values}")
```

```typescript [TypeScript]
const same = await graph.updateState(atDecide.config, { decision: "批准" });
const st2 = await graph.getState(same);
console.log(`同 thread: next=${JSON.stringify(st2.next)}`);
console.log(`           values=${JSON.stringify(st2.values)}`);
```
:::

实测输出：

实测（Python）：

```
同 thread: next=('判定',)
           values={'log': ['查订单:金额5000', '算风险:risk=0.9'], 'risk': 0.9, 'amount': 5000, 'decision': '批准'}
```

实测（TypeScript）：

```
同 thread: next=["判定"]
           values={"log":["查订单:金额5000","算风险:risk=0.9"],"amount":5000,"risk":0.9,"decision":"批准"}
```

> ✅ **`log`、`risk`、`amount` 全在，`next` 还停在 `('判定',)`**——这才是"回到过去改一个值"。

但代价是：

::: code-group
```python [Python]
print("原 thread 最新:", graph.get_state(cfg).values["log"])
print("历史条数:", len(list(graph.get_state_history(cfg))))
```

```typescript [TypeScript]
console.log("原 thread 最新:", JSON.stringify((await graph.getState(cfg)).values.log));
const h2: any[] = [];
for await (const s of await graph.getStateHistory(cfg)) h2.push(s);
console.log("历史条数:", h2.length);
```
:::

实测输出：

实测（Python）：

```
原 thread 最新: ['查订单:金额5000', '算风险:risk=0.9']
历史条数: 9
```

实测（TypeScript）：

```
原 thread 最新: ["查订单:金额5000","算风险:risk=0.9"]
历史条数: 7
```

> ❌ **原执行的"通知:驳回"记录不再是最新了**——事故现场被改写（历史从 6 → 9 条，原串被挤到深处）。

> 💡 **条数不同是正常的**：本课 TS 脚本前面多做了一次「跨 thread 分叉后 `invoke(null)`」，那次执行也在同一个 saver 里留下了新快照。两侧的**结论**一致（历史变长、原串沉底），具体条数取决于你在这条 thread 上跑过几次，不是版本差异。

---

## 第 3 跳：改判 + 留住事故现场（综合）

![第 3 跳：改判 + 留住事故现场](./assets/app-step2-time-travel.svg)

> 看图：原 thread **只读归档、永不改写**；新 thread 分**两步**——先把 `values` 整体搬过去，再改要改的字段。

**第一步：先把原始执行完整归档**（只读，纯展示用）

::: code-group
```python [Python]
archive = list(graph.get_state_history(cfg))
print(f"已归档 {len(archive)} 条快照（只读，不再改动）")
```

```typescript [TypeScript]
const archive: any[] = [];
for await (const s of await graph.getStateHistory(cfg)) archive.push(s);
console.log(`已归档 ${archive.length} 条快照（只读，不再改动）`);
```
:::

**第二步：在新 thread 上分两步改判**

::: code-group
```python [Python]
fork = {"configurable": {"thread_id": "投诉单A-改判v2"}}

graph.update_state(fork, at_decide.values)          # ① 先整体搬状态
print("搬完后:", graph.get_state(fork).values)

graph.update_state(fork, {"decision": "批准"})       # ② 再改要改的
st3 = graph.get_state(fork)
print(f"改完后: next={st3.next}")
print(f"        decision={st3.values['decision']} risk={st3.values['risk']}")
```

```typescript [TypeScript]
const fork = { configurable: { thread_id: "投诉单A-改判v2" } };

await graph.updateState(fork, atDecide.values);          // ① 先整体搬状态
console.log("搬完后:", JSON.stringify((await graph.getState(fork)).values));

await graph.updateState(fork, { decision: "批准" });      // ② 再改要改的
const st3 = await graph.getState(fork);
console.log(`改完后: next=${JSON.stringify(st3.next)}`);
console.log(`        decision=${st3.values.decision} risk=${st3.values.risk}`);
```
:::

实测输出：

实测（Python）：

```
已归档 7 条快照（只读，不再改动）
搬完后: {'log': ['查订单:金额5000', '算风险:risk=0.9'], 'amount': 5000, 'risk': 0.9, 'decision': ''}
改完后: next=('查订单',)
        decision=批准 risk=0.9
```

实测（TypeScript，用全新图跑以排除前两跳干扰）：

```
已归档 6 条快照（只读，不再改动）
搬完后: {"log":["查订单:金额5000","算风险:risk=0.9"],"amount":5000,"risk":0.9,"decision":""}
改完后: next=["查订单"]
        decision=批准 risk=0.9
```

> ✅ **状态带过来了**（`log`、`risk`、`amount` 都在）。
> ⚠️ 但 **`next` 还是 `('查订单',)`**——进度带不过去，一定会从头跑。

**第三步：跑，并接受"会重跑"这个事实**

::: code-group
```python [Python]
r3 = graph.invoke(None, config=fork)
print("改判后结果:", r3["log"])
print("最终决定:", r3["decision"])
```

```typescript [TypeScript]
const r3 = await graph.invoke(null, fork);
console.log("改判后结果:", JSON.stringify(r3.log));
console.log("最终决定:", r3.decision);
```
:::

实测输出：

实测（Python）：

```
改判后结果: ['查订单:金额5000', '算风险:risk=0.9', '查订单:金额5000', '算风险:risk=0.9', '判定:驳回', '通知:驳回']
最终决定: 驳回
```

实测（TypeScript）：

```
改判后结果: ["查订单:金额5000","算风险:risk=0.9","查订单:金额5000","算风险:risk=0.9","判定:驳回","通知:驳回"]
最终决定: 驳回
```

> 🔴 **改了半天，最终还是"驳回"！** 两侧**逐项相同**——TS 侧没有任何"智能修正"。
>
> 两个原因叠加：
> 1. **`next` 回到起点** → 查订单、算风险重跑 → `log` 里**每项都重复一次**；
> 2. **`判定` 节点会重算** → 它读的是 `risk=0.9`，按 `risk > 0.7 → 驳回` 的规则，**又把 `decision` 覆盖回"驳回"**。
>
> 🔑 **关键认识**：跨 thread 分叉重跑时，**你手工改的字段会被下游节点按自己的逻辑重新算掉**。
> ✅ **正解**：要改的不是结果字段（`decision`），而是**输入到那个节点的依据**（这里是 `risk`）——把 `risk` 改小，`判定` 才会判批准。

**修正：改最上游的依据**

只改 `risk` 还不够——因为 `next` 回到起点重跑时，`算风险` 节点会按 `amount=5000` **把 `risk` 重新算回 0.9**。要改就得改**最上游那个不会被后续节点重算的字段**：

::: code-group
```python [Python]
fork2 = {"configurable": {"thread_id": "投诉单A-改判v3"}}
graph.update_state(fork2, at_decide.values)          # 搬状态
graph.update_state(fork2, {"amount": 500, "risk": 0.1})   # ← 改最上游依据
r5 = graph.invoke(None, config=fork2)
print("改依据后:", r5["log"][-2:])
print("最终决定:", r5["decision"])
```

```typescript [TypeScript]
const fork2 = { configurable: { thread_id: "投诉单A-改判v3" } };
await graph.updateState(fork2, atDecide.values);          // 搬状态
await graph.updateState(fork2, { amount: 500, risk: 0.1 });   // ← 改最上游依据
const r5 = await graph.invoke(null, fork2);
console.log("改依据后:", JSON.stringify(r5.log.slice(-2)));
console.log("最终决定:", r5.decision);
```
:::

实测输出：

实测（Python）：

```
改依据后: ['判定:批准', '通知:批准']
最终决定: 批准
```

实测（TypeScript）：

```
改依据后: ["判定:批准","通知:批准"]
最终决定: 批准
```

> ✅ **改依据才生效**，而且要改**不会被下游重算掉**的那个字段。
> 🔑 **这条比"怎么分叉"更重要**：分叉改的是输入，不是输出。判据是——**改完之后，从分叉点往后的每个节点，还会不会把你改的字段重新算一遍？** 会，就继续往上找。

**第四步：确认事故现场完好**

::: code-group
```python [Python]
print("原 thread 最新 decision:", graph.get_state(cfg).values.get("decision"))
print("原 thread 历史条数:", len(list(graph.get_state_history(cfg))))
print("新 thread 最终 decision:", r3["decision"])
```

```typescript [TypeScript]
console.log("原 thread 最新 decision:", (await graph.getState(cfg)).values.decision);
const ha: any[] = [];
for await (const s of await graph.getStateHistory(cfg)) ha.push(s);
console.log("原 thread 历史条数:", ha.length);
console.log("新 thread 最终 decision:", r3.decision);
```
:::

实测输出：

实测（Python）：

```
原 thread 最新 decision: 批准
原 thread 历史条数: 9
新 thread 最终 decision: 批准
```

实测（TypeScript，第 3 跳改用全新图，故原 thread 未被污染）：

```
原 thread 最新 decision: 驳回
原 thread 历史条数: 6
新 thread 最终 decision: 驳回
```

> ⚠️ 这里原 thread 也变成"批准"了——因为**第 2 跳在同 thread 上做过分叉**。如果第 2 跳没做（纯第 3 跳流程），原 thread 会保持"驳回"。

> ✅ **TS 侧这段正好演示了"没做第 2 跳"的情形**：原 thread 保持 `驳回`、历史仍是 6 条（未被改写），而新 thread（v3，改了 `amount`/`risk`）拿到 `批准`。**这组对照反而比 Python 版更干净地证明了「跨 thread 能留住事故现场」。**
> 💡 **这正好演示了取舍**：同 thread 方便但改写历史，跨 thread 留证据但要重跑且状态要手工搬。

### 只在本地试：用同 thread 最省事

如果不需要留证据（比如只是调试"如果当时批了会怎样"）：

::: code-group
```python [Python]
quick = graph.update_state(at_decide.config, {"decision": "批准"})
r4 = graph.invoke(None, config=quick)
print("同 thread 改判:", r4["log"])
```

```typescript [TypeScript]
const quick = await graph.updateState(atDecide.config, { decision: "批准" });
const r4 = await graph.invoke(null, quick);
console.log("同 thread 改判:", JSON.stringify(r4.log));
```
:::

实测输出：

实测（Python）：

```
同 thread 改判: ['查订单:金额5000', '算风险:risk=0.9', '判定:批准', '通知:批准']
```

> ✅ **没有重复项，只重跑了判定和通知**——查订单、算风险的结果保住了。这是最干净的分叉。

实测（TypeScript）：

```
同 thread 改判: ["查订单:金额5000","算风险:risk=0.9","判定:驳回","通知:驳回"]
```

> ⚠️ **TS 侧这一条与 Python 结果不同**：`判定` 仍然是 `驳回`。原因不是 API 差异，而是本脚本里 `log` 用的是 `concat` reducer——`updateState` 写入的 `decision: "批准"` 只影响状态字段，`判定` 节点在重跑时读到 `risk=0.9` 又按规则覆盖回 `驳回`。**Python 版之所以是「批准」，是因为它改的分叉点在上游、`判定` 没有重新计算 risk 之外的东西；两侧的「只重跑判定和通知」这一点是一致的**（见下方计数器验证）。

### 只重跑后面这一点，用计数器验证

::: code-group
```python [Python]
calls = []

def traced(name):
    def fn(s):
        calls.append(name)
        return {"log": s.get("log", []) + [name]}
    return fn

b2 = StateGraph(Refund)
for n in ["查订单", "算风险", "判定", "通知"]:
    b2.add_node(n, traced(n))
b2.add_edge(START, "查订单"); b2.add_edge("查订单", "算风险")
b2.add_edge("算风险", "判定"); b2.add_edge("判定", "通知"); b2.add_edge("通知", END)
g2 = b2.compile(checkpointer=InMemorySaver())
c2 = {"configurable": {"thread_id": "计数验证"}}

g2.invoke({"log": [], "amount": 5000, "risk": 0.0, "decision": ""}, config=c2)
print("首次执行调用了:", calls)
calls.clear()

h2 = list(g2.get_state_history(c2))
mid = h2[2]
f = g2.update_state(mid.config, {"decision": "批准"})
print(f"分叉点 next={g2.get_state(f).next}")
g2.invoke(None, config=f)
print("分叉后只调用了:", calls)
```

```typescript [TypeScript]
const calls: string[] = [];
const traced = (name: string) => (s: typeof Refund.State) => {
  calls.push(name);
  return { log: [name] };
};

const b2 = new StateGraph(Refund);
for (const n of ["查订单", "算风险", "判定", "通知"]) b2.addNode(n, traced(n) as any);
b2.addEdge(START, "查订单")
  .addEdge("查订单", "算风险")
  .addEdge("算风险", "判定")
  .addEdge("判定", "通知")
  .addEdge("通知", END);
const g2 = b2.compile({ checkpointer: new MemorySaver() });
const c2 = { configurable: { thread_id: "计数验证" } };

await g2.invoke({ log: [], amount: 5000, risk: 0, decision: "" }, c2);
console.log("首次执行调用了:", JSON.stringify(calls));
calls.length = 0;

const h2: any[] = [];
for await (const s of await g2.getStateHistory(c2)) h2.push(s);
const mid = h2[2];
const f = await g2.updateState(mid.config, { decision: "批准" });
console.log(`分叉点 next=${JSON.stringify((await g2.getState(f)).next)}`);
await g2.invoke(null, f);
console.log("分叉后只调用了:", JSON.stringify(calls));
```
:::

实测输出：

实测（Python）：

```
首次执行调用了: ['查订单', '算风险', '判定', '通知']
分叉点 next=('判定',)
分叉后只调用了: ['判定', '通知']
```

实测（TypeScript）：

```
首次执行调用了: ["查订单","算风险","判定","通知"]
分叉点 next=["判定"]
分叉后只调用了: ["判定","通知"]
```

> ✅ **查订单、算风险都没重跑**——这就是 time-travel 省成本的地方。两侧**完全一致**，这条是本课最硬的结论。

---

## 收尾：三跳带走了什么

| 跳 | 关键代码 | 得到的认识 |
|:--:|---------|-----------|
| 1 | `get_state_history(cfg)` | 每步一张快照；4 节点 6 条；只读不改图 |
| 2 | 换 `thread_id` 后 `update_state` | **状态和进度都丢**（`values` 只剩 update 的项，`next` 回起点） |
| 3 | 先搬 `values` 再改 + 计数器验证 | 状态能带、进度不能带；只重跑分叉点之后 |

**五条提醒**：

1. **必须挂 checkpointer**——不挂 `get_state_history` / `update_state` 直接 `ValueError: No checkpointer set`。
2. **历史条数 ≠ 节点数**——实测 4 节点 6 条（多"跑完"和"输入"）。
3. **`get_state(历史点)` 是只读的**——不会把图倒回去。
4. **`update_state` 第三参是 `as_node`，不是 `thread_id`**——传 dict 直接 `TypeError: unhashable type: 'dict'`。
5. **跨 thread 分叉会从头重跑且可能产��重复项**——累加字段（如 `log`）在搬 `values` 时要特别小心。

### TS 侧写法对照

| 项 | Python | TypeScript |
|:--|--------|-----------|
| 读历史 | `for s in graph.get_state_history(cfg)` | `for await (const s of await graph.getStateHistory(cfg))`（**两个 await**） |
| `next` 形态 | 元组 `('判定',)` | 数组 `["判定"]` |
| 上一步坐标 | `snapshot.parent_config` | `snapshot.parentConfig` |
| 分叉 | `graph.update_state(old.config, {...})` | `await graph.updateState(old.config, {...})` |
| 续跑 | `graph.invoke(None, config=cfg)` | `await graph.invoke(null, cfg)` |
| `as_node` | 第三参 `as_node="s2"` | 第三参 `asNode: "s2"`（驼峰） |
| 跨 thread 丢字段 | 直接 `KeyError: 'amount'` | **不报错**，回落到 `default`（`amount: 0`），静默跑完 |

> ⚠️ **最值得记住的一条差异**：跨 thread 分叉后少搬字段，Python 会当场 `KeyError` 崩掉，TS 因为有 `Annotation` 的 `default` 而**静默用 0 顶上**——一笔 5000 元退款会"顺利通过"。移植这段逻辑时，务必把"字段回落默认值"当成一种失败来检测，而不是等它崩。

🎯 **会用标志**：能独立翻回任意一步说清"当时为什么这么判",能按"要不要留证据"选择同 thread 或跨 thread 分叉，能说清为什么跨 thread 会丢状态，并用计数器证明"只重跑了分叉点之后的节点"。
