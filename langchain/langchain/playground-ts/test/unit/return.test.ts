/**
 * 课 13 · 第 2 版：用剧本模型（fakeModel）测「确定的部分」
 *
 * 对应文档：应用实战/13-Testing与Observability.md（第 2 版代码块）
 *           stages/4-组合与工程化/lessons/13-Testing与Observability.md（单元测试层）
 *
 * 运行：npm run test:unit
 *
 * 📌 本文件是"快层"：零网络、零成本、无密钥，每次改动都能跑。
 *    它验证的是"模型决定调工具时，agent 是否真的执行了"——不验证模型质量。
 */
import { describe, it, expect } from "vitest";
import { createAgent, fakeModel, tool } from "langchain";
import { AIMessage, HumanMessage } from "@langchain/core/messages";
import { z } from "zod";

const applyReturn = tool(
  async ({ orderId }: { orderId: string }) => `已为订单 ${orderId} 发起退货申请。`,
  {
    name: "apply_return",
    description: "为指定订单发起退货申请。",
    schema: z.object({ orderId: z.string().describe("订单号") }),
  },
);

describe("return task", () => {
  it("模型决定调工具时 agent 必须真的执行", async () => {
    // 📌 TS 无需 ScriptedToolModel 补丁：fakeModel 自动实现 bindTools
    const model = fakeModel()
      .respondWithTools([
        { name: "apply_return", args: { orderId: "A12345" }, id: "call_1" },
      ])
      .respond(new AIMessage("已为您发起退货申请。"));

    const agent = createAgent({ model, tools: [applyReturn] });
    const result = await agent.invoke({
      messages: [new HumanMessage("订单 A12345 我要退货")],
    });

    // 断言依据是「消息序列」，不是回复文本——工具被真的执行了吗
    const toolMessages = result.messages.filter((m) => m._getType() === "tool");
    expect(toolMessages.length).toBe(1);
    expect(String(toolMessages[0].content)).toContain("已为订单 A12345 发起退货申请。");
  });
});
