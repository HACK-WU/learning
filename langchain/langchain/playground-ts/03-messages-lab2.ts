/**
 * 第 3 课 · 补充实验（TypeScript 版，对应 playground/03-messages-lab2.py）
 *
 * 运行（在 playground-ts 目录内）：
 *
 *     npx tsx 03-messages-lab2.ts
 *
 * 说明：采集"老教程写法""工具回执配对""懒解析"等边界场景的真实行为。
 */

import dotenv from "dotenv";
import { initChatModel, AIMessage, HumanMessage, ToolMessage, SystemMessage } from "langchain";
import { coerceMessageLikeToMessage } from "@langchain/core/messages";

dotenv.config({ path: [".env", "../playground/.env"] });

const model = await initChatModel("qwen3.8-flash", {
  modelProvider: "openai",
  apiKey: process.env.BAILIAN_API_KEY,
  baseUrl: process.env.BAILIAN_BASE_URL,
  maxRetries: 2,
  timeout: 60_000,
});

function section(title: string) {
  console.log(`\n${"=".repeat(16)} ${title} ${"=".repeat(16)}`);
}

section("A. 旧教程写法：字典里用 role='human'（旧版 LangChain 风格）");
try {
  const r: any = await model.invoke([{ role: "human", content: "你好" } as any]);
  console.log(`未报错 | 回答: ${(r.text ?? "").slice(0, 50)}`);
} catch (e: any) {
  console.log(`异常类型: ${e.constructor.name}`);
  console.log(`消息摘要: ${String(e.message).slice(0, 300)}`);
  console.log("--- 改为 role='user' 再试一次 ---");
  const r: any = await model.invoke([{ role: "user", content: "你好" }]);
  console.log(`成功 | 回答: ${(r.text ?? "").slice(0, 50)}`);
}

const modelWt = model.bindTools([
  {
    name: "get_weather",
    description: "查询指定城市的天气。",
    schema: {
      type: "object",
      properties: { city: { type: "string", description: "城市名" } },
      required: ["city"],
    },
  },
] as any);

section("B. 工具回执配对：tool_call_id 不匹配");
const hum = new HumanMessage("北京今天天气怎么样？");
const r1: any = await modelWt.invoke([hum]);
const tc = r1.tool_calls[0];
console.log(`AI 请求的 id: ${JSON.stringify(tc.id)}`);
const wrong = new ToolMessage({ content: "北京：晴。", tool_call_id: "call_WRONG_123", name: "get_weather" });
try {
  const r: any = await modelWt.invoke([hum, r1, wrong]);
  console.log(`未报错 | 回答: ${String(r.text).slice(0, 80)}`);
} catch (e: any) {
  console.log(`异常类型: ${e.constructor.name}`);
  console.log(`消息摘要: ${String(e.message).slice(0, 300)}`);
}

section("C. 缺少工具回执（只有请求，没有结果）");
try {
  const r: any = await modelWt.invoke([hum, r1]);
  console.log(`未报错 | 回答: ${String(r.text).slice(0, 80)}`);
} catch (e: any) {
  console.log(`异常类型: ${e.constructor.name}`);
  console.log(`消息摘要: ${String(e.message).slice(0, 300)}`);
}

section("D. ToolMessage 不传 name 能否构造");
try {
  const tm = new ToolMessage({ content: "测试内容", tool_call_id: "call_x" });
  console.log(`构造成功 | name=${JSON.stringify(tm.name)}`);
} catch (e: any) {
  console.log(`异常类型: ${e.constructor.name}`);
  console.log(`消息摘要: ${String(e.message).slice(0, 200)}`);
}

section("E. 懒解析：用供应商原生格式构造，contentBlocks 自动标准化（离线演示）");
const message = new AIMessage({
  content: [
    { type: "thinking", thinking: "先想一下……", signature: "sig_demo" },
    { type: "text", text: "最终回答" },
  ],
  response_metadata: { model_provider: "anthropic" },
} as any);
console.log("content 原样类型:", JSON.stringify((message.content as any[]).map((b) => b.type)));
console.log("contentBlocks 标准化:", JSON.stringify(message.contentBlocks));

section("F. 字典角色名单查证（离线，无 API 调用）");
for (const role of ["system", "user", "assistant", "human", "ai", "foo"]) {
  try {
    const m: any = coerceMessageLikeToMessage({ role, content: "x" } as any);
    console.log(`${JSON.stringify(role).padEnd(12)} -> ${m.constructor.name}`);
  } catch (e: any) {
    console.log(`${JSON.stringify(role).padEnd(12)} -> ${e.constructor.name}: ${String(e.message).slice(0, 130).replace(/\n/g, " ")}`);
  }
}
const msgs: any = coerceMessageLikeToMessage({ role: "tool", content: "回执", tool_call_id: "call_1" } as any);
console.log(`${JSON.stringify("tool").padEnd(12)} -> ${msgs.constructor.name}（需带 tool_call_id）`);
void SystemMessage;