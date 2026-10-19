// 课 13 部署示例用图：被 langgraph.json 的 graphs 引用
// 启动：npx @langchain/langgraph-cli dev
import { Annotation, END, START, StateGraph } from "@langchain/langgraph";

const State = Annotation.Root({
  n: Annotation<number>({ reducer: (_prev, next) => next, default: () => 0 }),
});

export const graph = new StateGraph(State)
  .addNode("n1", () => ({ n: 1 }))
  .addEdge(START, "n1")
  .addEdge("n1", END)
  .compile();
