import { describe, expect, it } from "vitest";
import { entrypoint, task, MemorySaver } from "@langchain/langgraph";

// Functional API 的确定性单测：不需要真实模型，也不需要密钥
describe("Functional API", () => {
  it("task 可并行调度，entrypoint 汇总结果", async () => {
    const addOne = task("add", async (x: number) => x + 1);

    const workflow = entrypoint(
      { name: "workflow", checkpointer: new MemorySaver() },
      async (numbers: number[]) => {
        const results = await Promise.all(numbers.map((n) => addOne(n)));
        return results;
      }
    );

    const out = await workflow.invoke([1, 2, 3], {
      configurable: { thread_id: "functional-1" },
    });

    expect(out).toEqual([2, 3, 4]);
  });
});

describe("递归上限", () => {
  it("无终止条件的环会抛 GraphRecursionError", async () => {
    const { StateGraph, Annotation, START } = await import("@langchain/langgraph");
    const S = Annotation.Root({
      n: Annotation<number>({ reducer: (_a, b) => b, default: () => 0 }),
    });

    const graph = new StateGraph(S)
      .addNode("loop", (s: { n: number }) => ({ n: s.n + 1 }))
      .addEdge(START, "loop")
      .addEdge("loop", "loop")
      .compile();

    await expect(graph.invoke({ n: 0 }, { recursionLimit: 6 } as never)).rejects.toThrow(
      /Recursion limit/
    );
  });
});
