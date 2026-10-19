/**
 * 探针：messages 模式 token 的 text / content / contentBlocks 三属性形态核对（课 6 文档改造用）
 */
import dotenv from "dotenv";
import { tool, createAgent, initChatModel } from "langchain";
import * as z from "zod";

dotenv.config({ path: [".env", "../playground/.env"] });

const model = await initChatModel("qwen3.8-flash", {
  modelProvider: "openai",
  apiKey: process.env.BAILIAN_API_KEY,
  baseUrl: process.env.BAILIAN_BASE_URL,
  maxRetries: 2,
  timeout: 60_000,
});

const getWeather = tool(
  async ({ city }: { city: string }) => `${city}：晴天，22°C，湿度 45%`,
  {
    name: "get_weather",
    description: "查询城市天气。",
    schema: z.object({ city: z.string() }),
  },
);

const agent = createAgent({ model, tools: [getWeather] });

console.log("=== messages 模式 token 属性形态 ===");
const stream = await agent.stream({ messages: [{ role: "user", content: "用一句话介绍北京。" }] } as any, {
  streamMode: "messages",
});
let n = 0;
let shown = 0;
for await (const [token, metadata] of stream as any) {
  n++;
  const textVal = token.text;
  const contentVal = token.content;
  const cbVal = token.contentBlocks;
  const hasText = typeof textVal === "string" && textVal.length > 0;
  if (hasText && shown < 3) {
    shown++;
    console.log(`token #${n}: text=${JSON.stringify(textVal.slice(0, 20))} | content=${JSON.stringify(typeof contentVal === "string" ? contentVal.slice(0, 20) : contentVal)} | contentBlocks=${JSON.stringify(cbVal).slice(0, 100)}`);
  }
  if (n === 1 && !hasText) {
    console.log(`token #1（空）: text=${JSON.stringify(textVal)} | content=${JSON.stringify(typeof contentVal === "string" ? contentVal : contentVal).slice(0, 60)} | contentBlocks=${JSON.stringify(cbVal).slice(0, 80)}`);
  }
}
console.log(`共 ${n} 个 chunk`);

// token.text 与 contentBlocks 一致性检查
let refill = 0;
const stream2 = await agent.stream({ messages: [{ role: "user", content: "用一句话介绍北京。" }] } as any, {
  streamMode: "messages",
});
for await (const [token] of stream2 as any) {
  const t = typeof token.text === "string" ? token.text : "";
  if (t.length > 0) refill++;
}
console.log(`token.text 非空块数: ${refill}`);
console.log("（探针完成）");