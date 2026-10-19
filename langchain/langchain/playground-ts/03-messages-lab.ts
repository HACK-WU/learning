/**
 * 第 3 课 · 消息体系实验（TypeScript 版，对应 playground/03-messages-lab.py）
 *
 * 运行（在 playground-ts 目录内）：
 *
 *     npx tsx 03-messages-lab.ts
 *
 * 说明：脚本输出即讲义引用的 TS 侧证据；如需真实链路请在 .env 中配置端点。
 */

import dotenv from "dotenv";
import zlib from "node:zlib";
import { initChatModel, AIMessage, HumanMessage, SystemMessage, ToolMessage } from "langchain";
import { load } from "@langchain/core/load";

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

/** 生成一张纯红色 32x32 PNG（标准库实现，不引入额外依赖） */
function makeRedPng(size = 32): Buffer {
  const row = Buffer.concat([Buffer.from([0]), Buffer.from(Array.from({ length: size }, () => [255, 0, 0]).flat())]);
  const raw = Buffer.concat(Array.from({ length: size }, () => row));
  const chunk = (tag: string, data: Buffer): Buffer => {
    const payload = Buffer.concat([Buffer.from(tag), data]);
    const crc = Buffer.alloc(4);
    crc.writeUInt32BE(zlib.crc32(payload) >>> 0);
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length);
    return Buffer.concat([len, payload, crc]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0);
  ihdr.writeUInt32BE(size, 4);
  ihdr[8] = 8;
  ihdr[9] = 2;
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", ihdr),
    chunk("IDAT", zlib.deflateSync(raw)),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

/** 打印内容块时把 base64 数据折叠成长度提示 */
function brief(block: any): any {
  const b = { ...block };
  if ("base64" in b) b.base64 = `<${b.base64.length} 个字符的 base64>`;
  return b;
}

// ================= 1. 三种构造格式 =================
section("1a. 字符串快捷（单次请求）");
let r: any = await model.invoke("用一句话向我问好。");
console.log(`返回类型: ${r.constructor.name} | 内容: ${(r.text ?? "").slice(0, 60)}`);

section("1b. 消息对象列表（含 System）");
r = await model.invoke([new SystemMessage("你是一位唐诗专家，回答保持简短。"), new HumanMessage("用一句诗描述春天。")]);
console.log(`返回类型: ${r.constructor.name} | 内容: ${(r.text ?? "").slice(0, 60)}`);

section("1c. 字典格式（OpenAI 风格）");
r = await model.invoke([
  { role: "system", content: "你是一位唐诗专家，回答保持简短。" },
  { role: "user", content: "用一句诗描述夏天。" },
]);
console.log(`返回类型: ${r.constructor.name} | 内容: ${(r.text ?? "").slice(0, 60)}`);

// ================= 2. 四类消息构造 =================
section("2. 四类消息对象（构造与关键字段）");
const sysMsg = new SystemMessage("你是一个严谨的客服助手。");
const humMsg = new HumanMessage({ content: "北京今天天气怎么样？", name: "alice", id: "msg_h1" });
const aiMsg = new AIMessage({
  content: "",
  tool_calls: [{ name: "get_weather", args: { city: "北京" }, id: "call_demo_1" }],
});
const toolMsg = new ToolMessage({ content: "北京：晴，26℃。", tool_call_id: "call_demo_1", name: "get_weather" });

console.log(`[${sysMsg.constructor.name}] content=${JSON.stringify(sysMsg.content)}`);
console.log(`[${humMsg.constructor.name}] content=${JSON.stringify(humMsg.content)} | name=${JSON.stringify(humMsg.name)} | id=${JSON.stringify(humMsg.id)}`);
console.log(`[${aiMsg.constructor.name}] content=${JSON.stringify(aiMsg.content)}`);
console.log(`    tool_calls=${JSON.stringify(aiMsg.tool_calls)}`);
console.log(`[${toolMsg.constructor.name}] content=${JSON.stringify(toolMsg.content)} | tool_call_id=${JSON.stringify(toolMsg.tool_call_id)} | name=${JSON.stringify(toolMsg.name)}`);

// ================= 3. 工具调用消息流 =================
section("3. 工具调用消息流（真实模型）");
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
const hum = new HumanMessage("北京今天天气怎么样？");

const r1: any = await modelWt.invoke([hum]);
const tc = r1.tool_calls[0];
console.log(`第 1 轮 AI 消息: content=${JSON.stringify(r1.content)}`);
console.log(`  tool_calls: name=${JSON.stringify(tc.name)} | args=${JSON.stringify(tc.args)} | id=${JSON.stringify(tc.id)}`);
console.log(`  该消息的 contentBlocks: ${JSON.stringify(r1.contentBlocks)}`);

const tm = new ToolMessage({ content: `${tc.args.city}：晴，26℃，微风。`, tool_call_id: tc.id, name: tc.name });
console.log(`Tool 消息: content=${JSON.stringify(tm.content)} | tool_call_id=${JSON.stringify(tm.tool_call_id)}`);

const r2: any = await modelWt.invoke([hum, r1, tm]);
console.log(`第 2 轮 AI 消息: ${(r2.text ?? "").slice(0, 80)}`);

// ================= 4. 消息属性 =================
section("4. 消息对象的属性（以第 2 轮 AI 消息为例）");
console.log(`text: ${JSON.stringify((r2.text ?? "").slice(0, 50))}`);
console.log(`content 类型: ${Array.isArray(r2.content) ? "array" : typeof r2.content}`);
console.log(`contentBlocks: ${JSON.stringify(r2.contentBlocks)}`);
console.log(`id: ${JSON.stringify(r2.id)}`);
console.log(`usage_metadata: ${JSON.stringify(r2.usage_metadata)}`);
console.log(`response_metadata 键: ${JSON.stringify(Object.keys(r2.response_metadata ?? {}))}`);

// ================= 5. 无状态实验 =================
section("5. 『消息列表就是模型的全部输入』——无状态实验");
const q1 = new HumanMessage("请记住：我的幸运数字是 42。只回复：好的");
const r_1: any = await model.invoke([q1]);
console.log(`第 1 轮（告知幸运数字）: ${JSON.stringify((r_1.text ?? "").trim().slice(0, 40))}`);

const q2 = new HumanMessage("我的幸运数字是多少？");
const r_no: any = await model.invoke([q2]);
console.log(`第 2 轮（不携带历史）: ${JSON.stringify((r_no.text ?? "").trim().slice(0, 90))}`);

const r_yes: any = await model.invoke([q1, r_1, q2]);
console.log(`第 2 轮（携带历史）: ${JSON.stringify((r_yes.text ?? "").trim().slice(0, 90))}`);

// ================= 6. 多模态内容块 =================
section("6. 多模态内容块（标准格式构造）");
const pngB64 = makeRedPng().toString("base64");
const msg = new HumanMessage({
  content: [
    { type: "text", text: "这张图是什么颜色？只回答颜色名。" },
    { type: "image", source_type: "base64", mime_type: "image/png", data: pngB64 },
  ],
} as any);
console.log("构造后的 content 块类型:", JSON.stringify((msg.content as any[]).map((b) => b.type)));
console.log("构造后的 contentBlocks 块类型:", JSON.stringify(msg.contentBlocks.map((b: any) => b.type)));

const resp: any = await model.invoke([msg]);
console.log(`模型回答: ${JSON.stringify((resp.text ?? "").trim())}`);
console.log(`响应的 contentBlocks: ${JSON.stringify(resp.contentBlocks)}`);

// ================= 7. 序列化 =================
section("7. 序列化与恢复");
const serializedH = humMsg.toJSON();
console.log(`toJSON(HumanMessage) 前 200 字符: ${JSON.stringify(serializedH).slice(0, 200)}`);
const restoredH = await load<HumanMessage>(JSON.stringify(serializedH));
console.log(`load 恢复: ${restoredH.constructor.name} | content=${JSON.stringify(restoredH.content)}`);

const restoredAI = await load<AIMessage>(JSON.stringify(r1.toJSON()));
console.log(`AI 消息恢复后 tool_calls 保留: ${JSON.stringify(restoredAI.tool_calls)}`);