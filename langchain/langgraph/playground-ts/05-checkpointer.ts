// 对应课 5《Checkpointer 短期记忆》
// 运行：npm run l05
import { StateGraph, Annotation, START, END, MemorySaver } from "@langchain/langgraph";

const State = Annotation.Root({
  log: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
  last: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
});

const graph = new StateGraph(State)
  .addNode("append", () => ({ log: ["新起点"], last: "新起点" }))
  .addEdge(START, "append")
  .addEdge("append", END)
  .compile({ checkpointer: new MemorySaver() });

const config = { configurable: { thread_id: "user-123" } };

console.log("第 1 次:", JSON.stringify(await graph.invoke({ log: [], last: "" }, config)));
console.log("第 2 次（我以为会重新开始）:", JSON.stringify(await graph.invoke({ log: [], last: "" }, config)));

// 排查 4：把存档点逐个打出来
let n = 0;
for await (const s of await graph.getStateHistory(config)) {
  if (n++ < 3) {
    console.log(`  快照: values=${JSON.stringify(s.values)} next=${JSON.stringify(s.next)} step=${s.metadata?.step}`);
  }
}
console.log("快照总数:", n);

// 忘了传 thread_id 会直接报错
try {
  await graph.invoke({ log: [], last: "" });
} catch (e) {
  console.log("忘传 thread_id:", (e as Error).message.slice(0, 110));
}
