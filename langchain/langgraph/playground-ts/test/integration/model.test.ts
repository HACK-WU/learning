import { describe, expect, it } from "vitest";

const hasKey = Boolean(process.env.OPENAI_API_KEY && process.env.OPENAI_API_KEY.length > 10);

// 真层：需要真实模型端点。缺密钥整组跳过，而不是失败。
describe.skipIf(!hasKey)("真实模型链路", () => {
  it("能创建并调用一次模型", async () => {
    const { ChatOpenAI } = await import("@langchain/openai");
    const model = new ChatOpenAI({ model: "gpt-4o-mini", temperature: 0 });
    const res = await model.invoke("回答一个字：好");
    expect(String(res.content).length).toBeGreaterThan(0);
  });
});
