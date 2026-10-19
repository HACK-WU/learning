import { describe, expect, it } from "vitest";
import { StateGraph, Annotation, START, END, MemorySaver } from "@langchain/langgraph";

// 对应课 3《Graph API 第一个图》的状态定义与 reducer 行为
const GraphState = Annotation.Root({
  plain: Annotation<string[]>({
    reducer: (_left: string[], right: string[]) => right,
    default: () => [],
  }),
  history: Annotation<string[]>({
    reducer: (left: string[], right: string[]) => left.concat(right),
    default: () => [],
  }),
});

describe("State reducer 语义", () => {
  it("无自定义 reducer 时覆盖，有 reducer 时累加", async () => {
    const graph = new StateGraph(GraphState)
      .addNode("n1", () => ({ plain: ["第一版"], history: ["第一版"] }))
      .addNode("n2", () => ({ plain: ["第二版"], history: ["第二版"] }))
      .addEdge(START, "n1")
      .addEdge("n1", "n2")
      .addEdge("n2", END)
      .compile();

    const result = await graph.invoke({});

    // 默认 reducer 直接替掉：第一版消失且不报错
    expect(result.plain).toEqual(["第二版"]);
    // 自定义 reducer 累加：两个版本都在
    expect(result.history).toEqual(["第一版", "第二版"]);
  });
});

describe("checkpointer 与 thread_id", () => {
  it("同一 thread_id 续接，不同 thread_id 隔离", async () => {
    const State = Annotation.Root({
      log: Annotation<string[]>({
        reducer: (a: string[], b: string[]) => a.concat(b),
        default: () => [],
      }),
    });

    const graph = new StateGraph(State)
      .addNode("append", () => ({ log: ["新起点"] }))
      .addEdge(START, "append")
      .addEdge("append", END)
      .compile({ checkpointer: new MemorySaver() });

    const cfgA = { configurable: { thread_id: "user-123" } };
    const cfgB = { configurable: { thread_id: "user-456" } };

    const first = await graph.invoke({ log: [] }, cfgA);
    const second = await graph.invoke({ log: [] }, cfgA);
    const other = await graph.invoke({ log: [] }, cfgB);

    expect(first.log).toEqual(["新起点"]);
    // 同线程续接：状态累加而非重来
    expect(second.log).toEqual(["新起点", "新起点"]);
    // 不同线程隔离
    expect(other.log).toEqual(["新起点"]);
  });
});
