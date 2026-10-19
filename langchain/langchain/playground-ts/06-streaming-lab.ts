/**
 * 第 6 课 · Streaming 流式输出实验（TypeScript 版，对应 playground/06-streaming-lab.py）
 *
 * 运行（在 playground-ts 目录内）：
 *
 *     npx tsx 06-streaming-lab.ts
 *
 * 设计 5 大板块（与 Python 侧脚本一一对应）：
 * 1. 流式 vs 非流式对照（invoke vs stream）
 * 2. streamMode: "updates"（agent 进度）
 * 3. streamMode: "messages"（LLM token 逐块）
 * 4. streamMode: "custom"（自定义信号）
 * 5. streamEvents v3（事件流 API，官方推荐新写法）
 *
 * 说明：脚本输出即讲义引用的实测证据，请勿修改后当作新结果引用。
 *       模型侧经本地 OpenAI 兼容 mock 端点回放固定剧本（与 Python 侧共用同一服务）。
 *       TS 侧与 Python 侧的 API 形态差异（本脚本实测确认）：
 *         - TS 的 stream() 只有 streamMode 参数，没有 Python 的 version="v2" 统一包装；
 *           chunk 是"裸结构"（updates 直接是 {节点名: 输出}；messages 是 [token, metadata] 元组）
 *         - 自定义信号在工具内用 config.writer?.()（Python 为 get_stream_writer()）
 *         - v3 事件流为 agent.streamEvents(state, { version: "v3" })，返回带 .messages / .text 投影的运行流
 */
import * as z from "zod";
import dotenv from "dotenv";
import { tool, createAgent, initChatModel } from "langchain";
import type { LangGraphRunnableConfig } from "@langchain/langgraph";

dotenv.config({ path: [".env", "../playground/.env"] });

const API_KEY = process.env.BAILIAN_API_KEY;
const BASE_URL = process.env.BAILIAN_BASE_URL;

const model = await initChatModel("qwen3.8-flash", {
  modelProvider: "openai",
  apiKey: API_KEY,
  baseUrl: BASE_URL,
  maxRetries: 2,
  timeout: 60_000,
});

function section(title: string) {
  console.log(`\n${"=".repeat(16)} ${title} ${"=".repeat(16)}`);
}

// ================= 工具定义 =================

const getWeather = tool(
  async ({ city }: { city: string }) => {
    return `${city}：晴天，22°C，湿度 45%`;
  },
  {
    name: "get_weather",
    description: "查询城市天气。",
    schema: z.object({ city: z.string().describe("城市名") }),
  },
);

const slowSearch = tool(
  async ({ query }: { query: string }, config: LangGraphRunnableConfig) => {
    config.writer?.(`🔍 正在搜索：${query}`);
    await new Promise((r) => setTimeout(r, 500));
    config.writer?.(`📊 已检索 3 条数据库记录`);
    await new Promise((r) => setTimeout(r, 300));
    config.writer?.(`✅ 搜索完成`);
    return `关于「${query}」找到 3 条结果：……`;
  },
  {
    name: "slow_search",
    description: "模拟慢速搜索（用于演示流式进度信号）。",
    schema: z.object({ query: z.string().describe("搜索词") }),
  },
);

// ================= 1. 流式 vs 非流式对照 =================

section("1. 流式 vs 非流式对照");

const agent = createAgent({ model, tools: [getWeather] });
const askBeijing = { messages: [{ role: "user", content: "北京天气怎么样？一句话回答。" }] };

// 非流式：等全部完成
console.log("[非流式 invoke] 开始计时…");
let t0 = Date.now();
const result: any = await agent.invoke(askBeijing as any);
let elapsed = (Date.now() - t0) / 1000;
console.log(`  耗时 ${elapsed.toFixed(1)}s`);
console.log(`  终答: ${String(result.messages[result.messages.length - 1].content).slice(0, 80)}…`);

// 流式 updates：逐步输出
console.log("[流式 stream(updates)] 开始计时…");
t0 = Date.now();
const stream1 = await agent.stream(askBeijing as any, { streamMode: "updates" });
for await (const chunk of stream1) {
  console.log(`  [${((Date.now() - t0) / 1000).toFixed(1)}s] 收到 chunk: updates`);
  for (const [nodeName, nodeOutput] of Object.entries(chunk as Record<string, any>)) {
    if (nodeOutput?.messages?.length) {
      const msg = nodeOutput.messages[nodeOutput.messages.length - 1];
      const content = String(msg.content ?? "").slice(0, 60);
      console.log(`    节点 ${nodeName}: ${content || "（空内容——模型只申请了工具，还没说话）"}`);
    }
  }
}
elapsed = (Date.now() - t0) / 1000;
console.log(`  总耗时 ${elapsed.toFixed(1)}s`);

// ================= 2. streamMode: "updates"（agent 进度） =================

section('2. streamMode="updates"（agent 进度）');

const chunks2: any[] = [];
const stream2 = await agent.stream({ messages: [{ role: "user", content: "上海天气怎么样？" }] } as any, {
  streamMode: "updates",
});
for await (const chunk of stream2) {
  chunks2.push(chunk);
}

console.log(`共收到 ${chunks2.length} 个 chunk`);
chunks2.forEach((chunk, i) => {
  const nodes = Object.keys(chunk);
  console.log(`  chunk ${i + 1}: 节点 [${nodes.map((n) => `'${n}'`).join(", ")}]`);
  for (const [nodeName, nodeOutput] of Object.entries(chunk as Record<string, any>)) {
    if (nodeOutput?.messages?.length) {
      const msg = nodeOutput.messages[nodeOutput.messages.length - 1];
      const msgType = msg.constructor?.name ?? typeof msg;
      const hasToolCalls = Boolean(msg.tool_calls?.length);
      console.log(`    ${nodeName} → ${msgType} (tool_calls=${hasToolCalls})`);
    }
  }
});

// ================= 3. streamMode: "messages"（LLM token 逐块） =================

section('3. streamMode="messages"（LLM token 逐块）');

console.log("逐块输出（内容块一行，截断显示）:");
let contentN = 0; // 内容块数
let emptyN = 0; // 空增量 chunk 数
const stream3 = await agent.stream({ messages: [{ role: "user", content: "用一句话介绍北京。" }] } as any, {
  streamMode: "messages",
});
for await (const [token, metadata] of stream3 as any) {
  const node = metadata?.langgraph_node ?? "?";
  let hit = false;
  for (const block of token.contentBlocks ?? []) {
    if (block.type === "text" && block.text) {
      contentN += 1;
      hit = true;
      if (contentN <= 10) {
        console.log(`  [${node}] ${JSON.stringify(block.text.slice(0, 40))}`);
      }
    }
  }
  if (!hit) emptyN += 1;
}
console.log(`  （共 ${contentN + emptyN} 个 chunk：内容块 ${contentN} 个 + 空增量 ${emptyN} 个，空增量已跳过）`);

// ================= 4. streamMode: "custom"（自定义信号） =================

section('4. streamMode="custom"（自定义信号）');

const agentCustom = createAgent({ model, tools: [slowSearch] });

console.log("自定义进度信号:");
const stream4 = await agentCustom.stream(
  { messages: [{ role: "user", content: "搜索一下 LangChain streaming 的最新文档。" }] } as any,
  { streamMode: "custom" },
);
for await (const chunk of stream4) {
  console.log(`  📡 ${chunk}`);
}

// ================= 5. streamEvents v3（事件流 API） =================

section("5. streamEvents v3（事件流 API）");

console.log("v3 事件流（messages 投影）:");
const stream = await agent.streamEvents({ messages: [{ role: "user", content: "广州天气怎么样？" }] } as any, {
  version: "v3",
});

for await (const message of stream.messages) {
  const node = message.node ?? "?";
  let wrote = 0;
  for await (const delta of message.text) {
    if (wrote === 0) process.stdout.write(`  [${node}] `);
    process.stdout.write(delta);
    wrote++;
  }
  if (wrote === 0) {
    process.stdout.write(`  [${node}] （本轮无文本内容——工具调用轮）`);
  }
  process.stdout.write("\n");
}

const finalState: any = await stream.output;
console.log(`\n最终状态 keys: [${Object.keys(finalState).map((k) => `'${k}'`).join(", ")}]`);

console.log("\n（全部实验完成）");