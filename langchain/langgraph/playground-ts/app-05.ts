// 应用实战 05 · Checkpointer 短期记忆（TypeScript 侧）
// 对照：../../应用实战/05-Checkpointer 短期记忆.md
// 运行：npm run a05
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Annotation, END, MemorySaver, START, StateGraph } from "@langchain/langgraph";
import { SqliteSaver } from "@langchain/langgraph-checkpoint-sqlite";

const line = (t: string) => console.log(`\n===== ${t} =====`);

const State = Annotation.Root({
  question: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  // 累加：每句话都留下（等价于 Python 的 Annotated[list[str], add]）
  history: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
  answer: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
});

const record = (s: typeof State.State) => ({ history: [s.question] });
const answer = (s: typeof State.State) => {
  const n = s.history.length;
  return { answer: `已收到你的 ${n} 条消息，最新一条是：${s.history[s.history.length - 1]}` };
};

const builder = new StateGraph(State)
  .addNode("record", record)
  // ⚠️ 节点名不能与状态字段同名（课 3 已记录），Python 里叫 answer 可以，TS 侧必须改名
  .addNode("reply", answer)
  .addEdge(START, "record")
  .addEdge("record", "reply")
  .addEdge("reply", END);

// ---------------------------------------------------------------- 第 1 跳
line("第 1 跳：让客服记住上文");
{
  // ⚠️ TS 是 MemorySaver（Python 是 InMemorySaver），且 compile 收对象参数
  const graph = builder.compile({ checkpointer: new MemorySaver() });
  const cfg = { configurable: { thread_id: "user-001" } };

  for (const q of ["我的订单还没发货", "那能退款吗", "算了，发货就行"]) {
    const r = await graph.invoke({ question: q, history: [], answer: "" }, cfg);
    console.log(`  问：${q}`);
    console.log(`  答：${r.answer}`);
  }

  // -------------------------------------------------------------- 第 2 跳·多用户隔离
  line("第 2 跳之一：多用户不串台");
  for (const [user, q] of [
    ["user-001", "我是张三"],
    ["user-002", "我是李四"],
  ]) {
    const r = await graph.invoke(
      { question: q, history: [], answer: "" },
      { configurable: { thread_id: user } }
    );
    console.log(`  ${user}:`, r.history);
  }
}

// ---------------------------------------------------------------- 第 2 跳·崩溃续跑
line("第 2 跳之二：崩了接着跑");
{
  const flakyState = State;
  const answerFlaky = (s: typeof flakyState.State) => {
    if (s.history.length >= 3) throw new Error("下游服务超时");
    return { answer: `已收到 ${s.history.length} 条` };
  };

  // 两个图共用同一个 saver，才等效于 Python 里「同一个 graph 换掉节点实现再重跑」
  const saver = new MemorySaver();

  const bFlaky = new StateGraph(flakyState)
    .addNode("record", record)
    .addNode("reply", answerFlaky)
    .addEdge(START, "record")
    .addEdge("record", "reply")
    .addEdge("reply", END);

  const bFixed = new StateGraph(flakyState)
    .addNode("record", record)
    .addNode("reply", answer)
    .addEdge(START, "record")
    .addEdge("record", "reply")
    .addEdge("reply", END);

  const graphFlaky = bFlaky.compile({ checkpointer: saver });
  const graphFixed = bFixed.compile({ checkpointer: saver });
  const cfg = { configurable: { thread_id: "user-003" } };

  for (const q of ["我的订单还没发货", "那能退款吗", "算了，发货就行"]) {
    try {
      await graphFlaky.invoke({ question: q, history: [], answer: "" }, cfg);
    } catch (e: any) {
      console.log("  崩了:", e.name + ":", e.message);
    }
  }

  const st = await graphFixed.getState(cfg);
  console.log("  崩溃后 history:", st.values.history);
  console.log("  崩溃后 next:  ", st.next);

  // TS 侧续跑同样传 null
  const r = await graphFixed.invoke(null, cfg);
  console.log("  续跑结果 history:", r.history);
  console.log("  续跑结果 answer: ", r.answer);
}

// ---------------------------------------------------------------- 第 3 跳
line("第 3 跳：换 SQLite，让记忆活过重启");
{
  const dir = mkdtempSync(join(tmpdir(), "lgjs-a05-"));
  const db = join(dir, "customer-service.sqlite");

  // 第一个连接
  {
    const graph = builder.compile({ checkpointer: SqliteSaver.fromConnString(db) });
    const cfg = { configurable: { thread_id: "user-001" } };
    for (const q of ["我的订单还没发货", "那能退款吗"]) {
      await graph.invoke({ question: q, history: [], answer: "" }, cfg);
    }
    console.log("  进程内连跑两次:", (await graph.getState(cfg)).values.history);
  }

  // 换一个独立连接再读同一个文件
  {
    const graph = builder.compile({ checkpointer: SqliteSaver.fromConnString(db) });
    const cfg = { configurable: { thread_id: "user-001" } };
    console.log("  换个连接再读:  ", (await graph.getState(cfg)).values.history);
  }

  console.log("  -> 换个连接读，上次的还在");
  rmSync(dir, { recursive: true, force: true });
}

// ---------------------------------------------------------------- 误解验证
line("最容易踩的坑：以为「再 invoke 一次是重新开始」");
{
  const graph = builder.compile({ checkpointer: new MemorySaver() });
  const cfg = { configurable: { thread_id: "t1" } };
  const a = await graph.invoke({ question: "A", history: [], answer: "" }, cfg);
  console.log("  第1次:          ", a.history);

  // 第二次传一份"新起点"
  const b = await graph.invoke({ question: "B", history: ["新起点"], answer: "" }, cfg);
  console.log("  第2次(传新起点): ", b.history);

  // 想真从头开始 -> 换 thread_id
  const cfgNew = { configurable: { thread_id: `t-${Date.now()}` } };
  const c = await graph.invoke({ question: "B", history: ["新起点"], answer: "" }, cfgNew);
  console.log("  换新编号:       ", c.history);
  console.log("  -> 带 reducer 的字段是叠加不是覆盖");
}
