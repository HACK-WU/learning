/**
 * 课 13 · 集成层：真模型轨迹评分（agentevals）
 *
 * 对应文档：应用实战/13-Testing与Observability.md（第 3 版 · 集成层代码块）
 *
 * 运行：
 *   BAILIAN_BASE_URL=... BAILIAN_API_KEY=... npm run test:integration
 *
 * 📌 本文件是"真层"：真调模型端点，有成本、要密钥。
 *    - 无密钥时整组 skip（对应 Python conftest.py 的 require_api_key fixture）
 *    - 断言对象是"轨迹"（调了哪些工具、顺序对不对），不是最终文案
 *
 * ⚠️ TS 侧 agentevals 的 LLM judge 只接受「字符串 model 标识」而非模型实例，
 *    本文件用轨迹匹配（确定性、无需裁判模型）作为主力断言。
 */
import { describe, it, expect } from "vitest";
import { createAgent, initChatModel, tool } from "langchain";
import { AIMessage, HumanMessage } from "@langchain/core/messages";
import { z } from "zod";
import { createTrajectoryMatchEvaluator } from "agentevals";

const hasKey = Boolean(process.env.BAILIAN_API_KEY);

const applyReturn = tool(
  async ({ orderId }: { orderId: string }) => `已为订单 ${orderId} 发起退货申请。`,
  {
    name: "apply_return",
    description: "为指定订单发起退货申请。",
    schema: z.object({ orderId: z.string().describe("订单号") }),
  },
);

const queryOrder = tool(
  async ({ orderId }: { orderId: string }) => `订单 ${orderId}：已签收。`,
  {
    name: "query_order",
    description: "查询订单状态。",
    schema: z.object({ orderId: z.string().describe("订单号") }),
  },
);

// 参考轨迹（期望行为）：查订单 → 发起退货
const REFERENCE = [
  new HumanMessage("订单 A12345 我要退货"),
  new AIMessage({
    content: "",
    tool_calls: [{ name: "query_order", args: { orderId: "A12345" }, id: "call_q" }],
  }),
  new AIMessage({
    content: "",
    tool_calls: [{ name: "apply_return", args: { orderId: "A12345" }, id: "call_r" }],
  }),
  new AIMessage("已为您发起退货申请。"),
];

describe.skipIf(!hasKey)("integration: return trajectory", () => {
  it("真模型跑完退货任务，轨迹必须包含 apply_return", async () => {
    const model = await initChatModel(process.env.BAILIAN_MODEL ?? "qwen3.8-flash", {
      modelProvider: "openai",
      configuration: { baseURL: process.env.BAILIAN_BASE_URL },
      apiKey: process.env.BAILIAN_API_KEY,
    });

    const agent = createAgent({ model, tools: [queryOrder, applyReturn] });
    const result = await agent.invoke({
      messages: [new HumanMessage("订单 A12345 我要退货，先帮我查下状态")],
    });

    // ① 确定性断言：必须真的调过 apply_return（幂等设计：重复调用被视为缺陷）
    const called = result.messages
      .filter((m) => m._getType() === "ai")
      .flatMap((m) => (m as AIMessage).tool_calls ?? [])
      .map((c) => c.name);
    expect(called).toContain("apply_return");

    // ② 轨迹匹配（superset：允许比参考轨迹多做事，但不许少做必须的那件）
    const evaluator = createTrajectoryMatchEvaluator({ trajectoryMatchMode: "superset" });
    const evaluation = await evaluator({
      outputs: result.messages,
      referenceOutputs: REFERENCE,
    });
    expect(evaluation.score).toBe(true);
  });
});
