/**
 * 第 7 课 · Memory 记忆实验（TypeScript 版，对应 playground/07-memory-lab.py）
 *
 * 运行（在 playground-ts 目录内）：
 *
 *     npx tsx 07-memory-lab.ts
 *
 * 设计 5 大板块（与 Python 侧脚本一一对应）：
 * 1. 记忆机制总览：无状态对照（无 checkpointer / 有 checkpointer / 换线程）
 * 2. 短期记忆：全量增长 → 裁剪 → 摘要 → 自定义 state（工具读写）
 * 3. 长期记忆：store 直接操作 → 跨线程召回 → 用户隔离 → 更新
 * 4. 记忆工程实践：profile 合并更新（含覆盖写对照）+ 三种策略成本对比
 *
 * 说明：脚本输出即讲义引用的实测证据，请勿修改后当作新结果引用。
 *       模型侧经本地 OpenAI 兼容 mock 端点回放固定剧本（与 Python 侧共用同一服务）。
 *       TS 侧与 Python 侧的 API 形态差异（本脚本实测确认）：
 *         - 内存 checkpointer 是 MemorySaver（Python 为 InMemorySaver）
 *         - 自定义 state 用 StateSchema 实例（Python 为 AgentState 子类）
 *         - 裁剪中间件用 createMiddleware({ beforeModel })（Python 为 @before_model 装饰器）
 *         - 摘要中间件是工厂函数 summarizationMiddleware({...})（Python 为 SummarizationMiddleware 类）
 *         - 工具读写状态：config.state / new Command({ update })（Python 为 runtime.state / Command(update=...)）
 *         - store 命名空间是数组 ["users"]（Python 为元组 ("users",)）
 *         - 状态核验走 agent.graph.getState()（Python 为 agent.get_state()）
 */
import * as z from "zod";
import dotenv from "dotenv";
import {
  tool,
  createAgent,
  createMiddleware,
  initChatModel,
  summarizationMiddleware,
  ToolMessage,
  countTokensApproximately,
  type ToolRuntime,
} from "langchain";
import {
  MemorySaver,
  InMemoryStore,
  StateSchema,
  REMOVE_ALL_MESSAGES,
  Command,
  type BaseStore as LgBaseStore,
} from "@langchain/langgraph";
import { RemoveMessage } from "@langchain/core/messages";

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

// 类型收窄：ToolRuntime.store 的声明类型来自 @langchain/core（仅 mget/mset），
// 而运行时实际是 LangGraph 的 BaseStore（含 put/get/search）——统一收窄一次，
// 脚本其余部分保持官方文档的调用写法（runtime.store.put/get/search）。
const lgStore = (runtime: { store: unknown }): LgBaseStore =>
  runtime.store as unknown as LgBaseStore;

function section(title: string) {
  console.log(`\n${"=".repeat(16)} ${title} ${"=".repeat(16)}`);
}

function brief(content: unknown, limit = 110): string {
  const text = content == null ? "" : String(content);
  return text.replace(/\s+/g, " ").trim().slice(0, limit);
}

// 打印消息链（角色 + 摘要，工具调用单列）
function showChain(msgs: any[], limit = 70): void {
  msgs.forEach((m, i) => {
    const t: string = typeof m.getType === "function" ? m.getType() : (m.type ?? m.constructor.name);
    if (t === "ai" && m.tool_calls?.length) {
      const calls = m.tool_calls
        .map((tc: any) => `${tc.name}(${JSON.stringify(tc.args)})`)
        .join("; ");
      console.log(`    [${i}] ai → 调用工具: ${calls}`);
    } else {
      console.log(`    [${i}] ${t}: ${brief(m.content, limit)}`);
    }
  });
}

async function chat(agent: any, text: string, label: string, config?: any): Promise<any> {
  const r = await agent.invoke({ messages: [{ role: "user", content: text }] }, config);
  console.log(`  [${label}] ${brief(r.messages.at(-1)?.content)}`);
  console.log(`       （消息数: ${r.messages.length}）`);
  return r;
}

// ============================================================
section("1. 记忆机制总览：无状态对照");
// ============================================================

console.log("\n-- 1a. 无 checkpointer：两次 invoke 相互独立 --");
const agentBare = createAgent({ model, tools: [] });
let r: any = await agentBare.invoke({ messages: [{ role: "user", content: "你好，我叫小明。" }] });
console.log("  [无记忆·第1轮]", brief(r.messages.at(-1)?.content));
r = await agentBare.invoke({ messages: [{ role: "user", content: "我叫什么名字？" }] });
console.log("  [无记忆·第2轮]", brief(r.messages.at(-1)?.content));

console.log("\n-- 1b. 有 checkpointer + 同一 thread_id：历史自动接续 --");
const agentMem = createAgent({ model, tools: [], checkpointer: new MemorySaver() });
const cfgA = { configurable: { thread_id: "thread-A" } };
await chat(agentMem, "我叫小明，最喜欢蓝色。请记住。", "同线程·第1轮", cfgA);
const st: any = await agentMem.graph.getState(cfgA);
console.log("  状态核验（graph.getState）——已持久化的消息链:");
showChain(st.values.messages);
await chat(agentMem, "我叫什么？最喜欢什么颜色？", "同线程·第2轮", cfgA);

console.log("\n-- 1c. 换一个 thread_id：记忆相互隔离 --");
const cfgB = { configurable: { thread_id: "thread-B" } };
await chat(agentMem, "我叫什么？", "新线程·问名字", cfgB);

// ============================================================
section("2. 短期记忆：增长、裁剪、摘要、自定义 state");
// ============================================================

const TURNS = ["你好，我叫小明。", "我喜欢蓝色。", "我住在北京。", "我养了一只猫，叫咪咪。"];
const CHECK = "我叫什么名字？我喜欢什么颜色？";

console.log("\n-- 2a. 默认行为：全量积累（越聊越长） --");
const agentFull = createAgent({ model, tools: [], checkpointer: new MemorySaver() });
const cfgF = { configurable: { thread_id: "growth" } };
let rFull: any;
for (const [i, msg] of TURNS.entries()) {
  rFull = await agentFull.invoke({ messages: [{ role: "user", content: msg }] }, cfgF);
  console.log(`  第 ${i + 1} 轮后消息数: ${rFull.messages.length}`);
}
rFull = await agentFull.invoke({ messages: [{ role: "user", content: CHECK }] }, cfgF);
console.log("  [全量·检查]", brief(rFull.messages.at(-1)?.content));
console.log(`       （消息数: ${rFull.messages.length}）`);
const fullMsgs = rFull.messages;

console.log("\n-- 2b. 裁剪：只保留「首条 + 最近 4 条」 --");
const trimMessages = createMiddleware({
  name: "TrimMessages",
  beforeModel: (state) => {
    const messages = state.messages;
    if (messages.length <= 6) return;
    const first = messages[0];
    const recent = messages.slice(-4);
    return {
      messages: [new RemoveMessage({ id: REMOVE_ALL_MESSAGES }), first, ...recent],
    };
  },
});

const agentTrim = createAgent({
  model,
  tools: [],
  middleware: [trimMessages],
  checkpointer: new MemorySaver(),
});
const cfgT = { configurable: { thread_id: "trimmed" } };
let rTrim: any;
for (const [i, msg] of TURNS.entries()) {
  rTrim = await agentTrim.invoke({ messages: [{ role: "user", content: msg }] }, cfgT);
  console.log(`  第 ${i + 1} 轮后消息数: ${rTrim.messages.length}`);
}
rTrim = await agentTrim.invoke({ messages: [{ role: "user", content: CHECK }] }, cfgT);
console.log("  [裁剪·检查]", brief(rTrim.messages.at(-1)?.content));
console.log(`       （消息数: ${rTrim.messages.length}）`);
console.log("  最终保留的消息链:");
showChain(rTrim.messages);
const trimMsgs = rTrim.messages;

console.log("\n-- 2c. 摘要：超阈值时把早期历史压缩为一条摘要 --");
const agentSum = createAgent({
  model,
  tools: [],
  middleware: [
    summarizationMiddleware({
      model,
      trigger: { messages: 6 },
      keep: { messages: 4 },
    }),
  ],
  checkpointer: new MemorySaver(),
});
const cfgS = { configurable: { thread_id: "summarized" } };
let rSum: any;
for (const [i, msg] of TURNS.entries()) {
  rSum = await agentSum.invoke({ messages: [{ role: "user", content: msg }] }, cfgS);
  console.log(`  第 ${i + 1} 轮后消息数: ${rSum.messages.length}`);
}
rSum = await agentSum.invoke({ messages: [{ role: "user", content: CHECK }] }, cfgS);
console.log("  [摘要·检查]", brief(rSum.messages.at(-1)?.content));
console.log(`       （消息数: ${rSum.messages.length}）`);
console.log("  最终保留的消息链:");
showChain(rSum.messages, 110);
const sumMsgs = rSum.messages;

console.log("\n-- 2d. 自定义 state：工具读 / 写短期记忆 --");
const CustomState = new StateSchema({
  userName: z.string().optional(),
});

const saveName = tool(
  async ({ name }: { name: string }, runtime: ToolRuntime<typeof CustomState.State>) => {
    return new Command({
      update: {
        userName: name,
        messages: [
          new ToolMessage({
            content: `已记录：${name}`,
            tool_call_id: runtime.toolCall?.id ?? "",
          }),
        ],
      },
    });
  },
  {
    name: "save_name",
    description: "记录用户的名字到状态。",
    schema: z.object({ name: z.string().describe("用户名字") }),
  },
);

const getName = tool(
  async (_: unknown, runtime: ToolRuntime<typeof CustomState.State>) => {
    const name = runtime.state.userName;
    return `之前记录的用户名是：${name}`;
  },
  {
    name: "get_name",
    description: "查询之前记录的用户名字。",
    schema: z.object({}),
  },
);

const agentState = createAgent({
  model,
  tools: [saveName, getName],
  stateSchema: CustomState,
  checkpointer: new MemorySaver(),
});
const cfgSt = { configurable: { thread_id: "custom-state" } };
const rSt1: any = await agentState.invoke(
  { messages: [{ role: "user", content: "我的名字是小明，请记录下来。" }] },
  cfgSt,
);
console.log("  [写状态] 消息链:");
showChain(rSt1.messages);
const rSt2: any = await agentState.invoke(
  { messages: [{ role: "user", content: "我之前说我的名字是什么？" }] },
  cfgSt,
);
console.log("  [读状态]", brief(rSt2.messages.at(-1)?.content));

// ============================================================
section("3. 长期记忆：store 与跨会话");
// ============================================================

console.log("\n-- 3a. store 基础操作（直接操作，不经模型） --");
const store1 = new InMemoryStore();
await store1.put(["users"], "user_123", { name: "小明", language: "中文" });
await store1.put(["users"], "user_456", { name: "小红", language: "英文" });
const item1 = await store1.get(["users"], "user_123");
console.log("  get(['users'], 'user_123'):", item1?.value);
const items1 = await store1.search(["users"]);
console.log("  search(['users']) 全部:", items1.map((i) => i.value));
const items2 = await store1.search(["users"], { filter: { language: "中文" } });
console.log("  search(filter={language: '中文'}):", items2.map((i) => i.value));
const items3 = await store1.search(["users"], { query: "名字" });
console.log("  search(query='名字')（未配嵌入函数）:", items3.map((i) => i.value));

console.log("\n-- 3b. 跨线程召回：session-1 里教，session-2 里查 --");
const ContextSchema = z.object({
  userId: z.string(),
});

const store2 = new InMemoryStore();

const saveUserName = tool(
  async ({ name }: { name: string }, runtime: ToolRuntime<unknown, z.infer<typeof ContextSchema>>) => {
    await lgStore(runtime).put(["users"], runtime.context.userId, { name });
    return `已保存：${name}`;
  },
  {
    name: "save_user_name",
    description: "保存用户名字到长期记忆（跨会话）。",
    schema: z.object({ name: z.string().describe("用户名字") }),
  },
);

const getUserName = tool(
  async (_: unknown, runtime: ToolRuntime<unknown, z.infer<typeof ContextSchema>>) => {
    const item = await lgStore(runtime).get(["users"], runtime.context.userId);
    return item?.value ? String(item.value.name) : "没有找到该用户的记录";
  },
  {
    name: "get_user_name",
    description: "从长期记忆读取用户名字（跨会话）。",
    schema: z.object({}),
  },
);

const agentLt = createAgent({
  model,
  tools: [saveUserName, getUserName],
  store: store2,
  contextSchema: ContextSchema,
  checkpointer: new MemorySaver(),
});
const cfgS1: any = { configurable: { thread_id: "session-1" }, context: { userId: "user_123" } };
const cfgS2: any = { configurable: { thread_id: "session-2" }, context: { userId: "user_123" } };
const cfgS3: any = { configurable: { thread_id: "session-3" }, context: { userId: "user_456" } };

let rLt: any = await agentLt.invoke(
  { messages: [{ role: "user", content: "你好，记住：我叫小明。" }] },
  cfgS1,
);
console.log("  [session-1·教] 消息链:");
showChain(rLt.messages);
console.log("  直连 store 查看:", (await store2.get(["users"], "user_123"))?.value);

rLt = await agentLt.invoke({ messages: [{ role: "user", content: "我叫什么名字？" }] }, cfgS2);
console.log("  [session-2·查]", brief(rLt.messages.at(-1)?.content));
console.log("       （session-2 的新消息链只有本轮问答——见下方链）");
showChain(rLt.messages);

console.log("\n-- 3c. 用户隔离：换个 user_id 查不到 --");
rLt = await agentLt.invoke({ messages: [{ role: "user", content: "我叫什么名字？" }] }, cfgS3);
console.log("  [session-3·user_456 查]", brief(rLt.messages.at(-1)?.content));

console.log("\n-- 3d. 更新记忆：改名字（put 覆盖同 key） --");
rLt = await agentLt.invoke(
  { messages: [{ role: "user", content: "我要改个名字：以后叫我大明。" }] },
  cfgS1,
);
console.log("  [session-1·改名] 消息链:");
showChain(rLt.messages);
console.log("  直连 store 查看:", (await store2.get(["users"], "user_123"))?.value);

// ============================================================
section("4. 记忆工程实践：更新模式与成本对比");
// ============================================================

console.log("\n-- 4a. profile 合并更新（读取 → 合并 → 写回） --");
const store3 = new InMemoryStore();
await store3.put(["users"], "u1", { name: "小明", city: "北京" });

const rememberPreference = tool(
  async ({ preference }: { preference: string }, runtime: ToolRuntime<unknown, z.infer<typeof ContextSchema>>) => {
    const ns = ["users"];
    const key = runtime.context.userId;
    const item = await lgStore(runtime).get(ns, key);
    const profile: Record<string, any> = item?.value ? { ...item.value } : {};
    const prefs: string[] = [...(profile.preferences ?? [])];
    prefs.push(preference);
    profile.preferences = prefs;
    await lgStore(runtime).put(ns, key, profile);
    return `已记住。当前档案: ${JSON.stringify(profile)}`;
  },
  {
    name: "remember_preference",
    description: "记住用户的偏好（读取现有档案，追加到 preferences 列表后写回）。",
    schema: z.object({ preference: z.string().describe("用户偏好") }),
  },
);

const agentProf = createAgent({
  model,
  tools: [rememberPreference],
  store: store3,
  contextSchema: ContextSchema,
});
console.log("  更新前:", (await store3.get(["users"], "u1"))?.value);
const rProf: any = await agentProf.invoke(
  { messages: [{ role: "user", content: "记住：我喜欢喝咖啡。" }] },
  { context: { userId: "u1" } },
);
console.log("  [合并更新] 消息链:");
showChain(rProf.messages);
console.log("  更新后（合并）:", (await store3.get(["users"], "u1"))?.value);

await store3.put(["users"], "u1", { preferences: ["喜欢喝咖啡"] });
console.log("  对照·若直接覆盖写（只写新内容不读旧档案）:", (await store3.get(["users"], "u1"))?.value);

console.log("\n-- 4b. 同对话三策略成本对比（消息数 / token 估算） --");
console.log(`  ${"策略".padEnd(4)} | ${"消息数".padEnd(4)} | ${"token 估算".padEnd(8)} | 检查问题的回答`);
for (const [name, msgs] of [["全量", fullMsgs], ["裁剪", trimMsgs], ["摘要", sumMsgs]] as const) {
  const est = countTokensApproximately(msgs as any[]);
  console.log(
    `  ${name.padEnd(4)} | ${String(msgs.length).padEnd(6)} | ${String(est).padEnd(12)} | ${brief((msgs as any[]).at(-1)?.content, 60)}`,
  );
}

console.log("\n（全部实验完成）");