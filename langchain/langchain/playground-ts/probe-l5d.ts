/** 临时探针：结构化输出完整链路诊断 */
import * as z from "zod";
import dotenv from "dotenv";
import { createAgent, initChatModel, toolStrategy } from "langchain";

dotenv.config({ path: [".env", "../playground/.env"] });

const modelNoThink = await initChatModel("qwen3.8-flash", {
  modelProvider: "openai",
  apiKey: process.env.BAILIAN_API_KEY,
  baseUrl: process.env.BAILIAN_BASE_URL,
  modelKwargs: { enable_thinking: false },
});

const ContactInfo = z
  .object({
    name: z.string().describe("姓名"),
    email: z.string().describe("邮箱"),
    phone: z.string().describe("电话"),
  })
  .meta({ title: "ContactInfo" });

const agent = createAgent({
  model: modelNoThink,
  tools: [],
  responseFormat: toolStrategy(ContactInfo),
});

try {
  const r: any = await agent.invoke({
    messages: [{ role: "user", content: "从这段信息中提取联系人：John Doe, john@example.com, (555) 123-4567" }],
  });
  console.log("keys:", JSON.stringify(Object.keys(r)));
  console.log("structuredResponse:", JSON.stringify(r.structuredResponse));
  for (const m of r.messages) {
    const t = m.type ?? m.constructor?.name;
    const tcs = m.tool_calls?.map((tc: any) => `${tc.name}(${JSON.stringify(tc.args)})`).join(" | ");
    console.log(`[${t}] ${tcs ? "TC=" + tcs : String(m.content).slice(0, 140)}`);
  }
} catch (e: any) {
  console.log("ERR:", e.constructor.name, "|", String(e.message).slice(0, 300));
}