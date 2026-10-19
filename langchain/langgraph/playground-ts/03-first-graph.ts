// 对应课 3《Graph API 第一个图》4.1 机制验证
// 运行：npm run l03
import { StateGraph, Annotation, START, END, Overwrite } from "@langchain/langgraph";

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

// ---------- 验证一：默认覆盖 vs reducer 累加 ----------
const State = Annotation.Root({
  plain: Annotation<string[]>(),                                  // 默认 reducer：覆盖
  history: Annotation<string[]>({ reducer: (a, b) => a.concat(b), // 自定义 reducer：累加
                                 default: () => [] }),
});

const reduceGraph = new StateGraph(State)
  .addNode("n1", () => ({ plain: ["第一版"], history: ["第一版"] }))
  .addNode("n2", () => ({ plain: ["第二版"], history: ["第二版"] }))
  .addEdge(START, "n1")
  .addEdge("n1", "n2")
  .addEdge("n2", END)
  .compile();

const r1 = await reduceGraph.invoke({});
console.log("验证一（覆盖 vs 累加）:", JSON.stringify(r1));

// ---------- 验证二：并发写同一字段 ----------
const LogNoReducer = Annotation.Root({
  log: Annotation<string[]>(),   // 不声明 reducer
});
const badGraph = new StateGraph(LogNoReducer)
  .addNode("fork", () => ({}))
  .addNode("a", () => ({ log: ["分支一"] }))
  .addNode("b", () => ({ log: ["分支二"] }))
  .addEdge(START, "fork")
  .addEdge("fork", "a").addEdge("fork", "b")
  .addEdge("a", END).addEdge("b", END)
  .compile();
try {
  await badGraph.invoke({});
  console.log("验证二（无 reducer）: 未报错（不应发生）");
} catch (e) {
  console.log("验证二（无 reducer）:", (e as Error).name);
}

const LogWithReducer = Annotation.Root({
  log: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
});
const okGraph = new StateGraph(LogWithReducer)
  .addNode("fork", () => ({}))
  .addNode("a", () => ({ log: ["分支一"] }))
  .addNode("b", () => ({ log: ["分支二"] }))
  .addEdge(START, "fork")
  .addEdge("fork", "a").addEdge("fork", "b")
  .addEdge("a", END).addEdge("b", END)
  .compile();
console.log("验证二（加 reducer）:", JSON.stringify((await okGraph.invoke({})).log.sort()));

// ---------- 验证三：reducer 字段能不能清空 ----------
const ErrState = Annotation.Root({
  errors: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
});
const clearEmpty = new StateGraph(ErrState)
  .addNode("first", () => ({ errors: ["第一次不合格"] }))
  .addNode("clear", () => ({ errors: [] }))
  .addEdge(START, "first").addEdge("first", "clear").addEdge("clear", END).compile();
console.log("验证三（返回空数组）:", JSON.stringify((await clearEmpty.invoke({})).errors));

const clearOverwrite = new StateGraph(ErrState)
  .addNode("first", () => ({ errors: ["第一次不合格"] }))
  .addNode("clear", () => ({ errors: new Overwrite([]) }))
  .addEdge(START, "first").addEdge("first", "clear").addEdge("clear", END).compile();
console.log("验证三（Overwrite）:", JSON.stringify((await clearOverwrite.invoke({})).errors));

// ---------- 验证四：节点不返回、START/END 是虚拟节点 ----------
const NodeState = Annotation.Root({
  a: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  b: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  c: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
});
const nodeGraph = new StateGraph(NodeState)
  .addNode("A", () => ({ a: "由节点 A 写入" }))
  .addNode("B", () => ({}))                       // 什么都不改
  .addNode("named_by_fn", () => ({ c: "由 named_by_fn 写入" }))
  .addEdge(START, "A").addEdge("A", "B").addEdge("B", "named_by_fn").addEdge("named_by_fn", END)
  .compile();

let round = 0;
for await (const chunk of await nodeGraph.stream({}, { streamMode: "updates" })) {
  console.log(`  第 ${++round} 轮 ->`, JSON.stringify(chunk));
}
console.log("验证四（最终状态）:", JSON.stringify(await nodeGraph.invoke({})));
const g4 = await nodeGraph.getGraphAsync({});
console.log("验证四（节点清单）:", JSON.stringify(Object.keys(g4.nodes).sort()));
console.log("验证四（END 的值）:", JSON.stringify(END));

// ---------- 验证五：质检循环 + recursionLimit ----------
const LoopState = Annotation.Root({
  draft: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  rounds: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
  verdict: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
});

const buildLoop = (maxRounds: number | null) => {
  const builder = new StateGraph(LoopState)
    .addNode("generate", async (s) => {
      await sleep(0);
      return { draft: `第${s.rounds.length + 1}版回复`, rounds: [`生成第${s.rounds.length + 1}版`] };
    })
    .addNode("check", (s) => ({
      verdict: maxRounds !== null && s.rounds.length >= maxRounds ? "通过" : "打回",
    }))
    .addEdge(START, "generate")
    .addEdge("generate", "check");

  builder.addConditionalEdges("check", (s): string => {
    if (s.verdict === "通过") return END;
    return "generate";
  });
  return builder.compile();
};

const loopOk = buildLoop(3);
console.log("验证五（有终止条件）:", JSON.stringify(await loopOk.invoke({})));

const loopBad = buildLoop(null);
try {
  await loopBad.invoke({}, { recursionLimit: 6 } as never);
} catch (e) {
  console.log("验证五（不写终止条件）:", (e as Error).message.split("\n")[0]);
}
