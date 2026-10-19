/**
 * 第 1 课 · 第一个 Agent（TypeScript 版）：让"只会聊天"的模型学会用工具。
 *
 * 与 playground/01-first-agent.py 一一对应。
 *
 * 运行（在 playground-ts 目录内）：
 *
 *     npm run l01           # 等价于 npx tsx 01-first-agent.ts
 *
 * 预期：模型先"决定"调用 get_weather 工具，拿到结果后组织成自然语言回答。
 */

import dotenv from "dotenv";
import { createAgent, initChatModel, tool } from "langchain";
import * as z from "zod";

dotenv.config({ path: [".env", "../playground/.env"] });

const getWeather = tool(
  ({ city }) => `${city}：晴，26℃，微风。`,
  {
    name: "get_weather",
    description: "查询指定城市的天气。",
    schema: z.object({ city: z.string().describe("城市名") }),
  },
);

const model = await initChatModel("qwen3.8-flash", {
  modelProvider: "openai",
  apiKey: process.env.BAILIAN_API_KEY!,
  baseUrl: process.env.BAILIAN_BASE_URL!,
});

const agent = createAgent({
  model,
  tools: [getWeather],
  systemPrompt: "你是一个乐于助人的助手，回答简洁。",
});

const result = await agent.invoke({
  messages: [{ role: "user", content: "北京今天天气怎么样？" }],
});

console.log("========== 完整消息流 ==========");
result.messages.forEach((message, index) => {
  const kind = message.constructor.name;
  const content = typeof message.content === "string" ? message.content : JSON.stringify(message.content);
  const toolCalls =
    "tool_calls" in message ? (message.tool_calls as Array<{ name: string }> | undefined) : undefined;
  const suffix = toolCalls?.length ? `  [tool_calls: ${toolCalls.map((tc) => tc.name).join(", ")}]` : "";
  console.log(`${index + 1}. [${kind}]${suffix} ${content.slice(0, 150)}`);
});

console.log();
console.log("========== 最终回复 ==========");
const last = result.messages.at(-1);
console.log(typeof last?.text === "string" ? last.text : last?.content);