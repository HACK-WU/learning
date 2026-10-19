// 对应课 1《环境准备》第三小节的「验证图能跑」
// 运行：npm run conn
import { StateGraph, Annotation, START, END } from "@langchain/langgraph";

const State = Annotation.Root({
  n: Annotation<number>({ reducer: (_prev, next) => next, default: () => 0 }),
});

const g = new StateGraph(State)
  .addNode("add_one", (s) => ({ n: s.n + 1 }))
  .addEdge(START, "add_one")
  .addEdge("add_one", END)
  .compile();

console.log(await g.invoke({ n: 0 })); // { n: 1 }
