// 对应课 2《LangGraph 是什么（定位与心智模型）》4.1 机制验证
// 运行：npm run l02
import { StateGraph, Annotation, START, END } from "@langchain/langgraph";

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

const State = Annotation.Root({
  note: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  doc: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  ticket: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
});

// 四个节点：a 之后同时接 b、c，最后都汇到 d
const app = new StateGraph(State)
  .addNode("a", () => ({ note: "原始请求：导出 PDF 报错" }))
  .addNode("b", async () => {
    await sleep(1000);
    return { doc: "查到文档：PDF 导出需开启字体嵌入" };
  })
  .addNode("c", async () => {
    await sleep(1000);
    return { ticket: "已建缺陷单 BUG-1024" };
  })
  .addNode("d", (s) => ({ note: `${s.note} | 汇总：${s.doc} / ${s.ticket}` }))
  .addEdge(START, "a")
  .addEdge("a", "b")
  .addEdge("a", "c")
  .addEdge("b", "d")
  .addEdge("c", "d")
  .addEdge("d", END)
  .compile();

// 验证一：一次运行被切成一轮一轮
let round = 0;
for await (const chunk of await app.stream(
  { note: "", doc: "", ticket: "" },
  { streamMode: "updates" }
)) {
  console.log(`第 ${++round} 轮 ->`, JSON.stringify(chunk));
}

// 验证二：两个分支到底是不是同一轮？用秒表证明
const t0 = performance.now();
await app.invoke({ note: "", doc: "", ticket: "" });
const seconds = (performance.now() - t0) / 1000;
console.log(`两个各睡 1 秒的分支，总耗时 = ${seconds.toFixed(2)} 秒`);
console.log(seconds < 1.5 ? "-> 并行（同一轮）" : "-> 串行");

// 验证三：不声明 reducer 时，并发写同一字段会报错
const BadState = Annotation.Root({
  note: Annotation<string>(),
  log: Annotation<string>(),
});
const bad = new StateGraph(BadState)
  .addNode("a", () => ({ note: "x" }))
  .addNode("b", () => ({ log: "来自 b" }))
  .addNode("c", () => ({ log: "来自 c" }))
  .addEdge(START, "a")
  .addEdge("a", "b")
  .addEdge("a", "c")
  .addEdge("b", END)
  .addEdge("c", END)
  .compile();

try {
  await bad.invoke({ note: "", log: "" });
  console.log("未报错（不应发生）");
} catch (e) {
  const err = e as Error;
  console.log(`\n验证三：${err.name}`);
  console.log(err.message.replace(/\n/g, " ").slice(0, 200));
}
