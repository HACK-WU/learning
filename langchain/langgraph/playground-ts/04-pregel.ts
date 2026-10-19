// 对应课 4《Pregel 执行模型》—— Send 动态扇出 与 Command 状态更新+跳转
// 运行：npm run l04
import { StateGraph, Annotation, START, END, Send, Command } from "@langchain/langgraph";

// ---------- Send：动态扇出（map-reduce） ----------
const OverallState = Annotation.Root({
  subjects: Annotation<string[]>({ reducer: (_p, n) => n, default: () => [] }),
  jokes: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
});

const fanOut = new StateGraph(OverallState)
  .addNode("generate_joke", (s: { subject?: string }) => ({
    jokes: [`关于${s.subject}的笑话`],
  }))
  .addConditionalEdges(START, (s) =>
    s.subjects.map((subject) => new Send("generate_joke", { subject }))
  )
  .compile();

console.log("Send 扇出:", JSON.stringify(await fanOut.invoke({
  subjects: ["猫", "狗", "鱼"],
  jokes: [],
})));

// ---------- Command：一步同时改状态 + 跳转 ----------
const State = Annotation.Root({
  foo: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  path: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
});

const nodeA = (s: typeof State.State): Command => {
  if (s.foo === "b改过") {
    return new Command({ update: { foo: "收工", path: ["a:收工"] }, goto: END });
  }
  return new Command({ update: { foo: "去b", path: ["a"] }, goto: "node_b" });
};

const cmdGraph = new StateGraph(State)
  // ⚠️ 必须用 ends 声明 Command 的可达目标，否则抛 UnreachableNodeError
  .addNode("node_a", nodeA, { ends: ["node_b"] })
  .addNode("node_b", () => ({ foo: "b改过", path: ["b"] }))
  .addEdge(START, "node_a")
  .addEdge("node_b", "node_a")
  .compile();

let round = 0;
for await (const chunk of await cmdGraph.stream({ foo: "", path: [] }, { streamMode: "updates" })) {
  console.log(`  第 ${++round} 轮 ->`, JSON.stringify(chunk));
}
console.log("Command 最终:", JSON.stringify(await cmdGraph.invoke({ foo: "", path: [] })));
