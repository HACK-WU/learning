/**
 * 第 5 课 · Agents 实验（TypeScript 版，对应 playground/05-agent-lab.py）
 *
 * 运行（在 playground-ts 目录内）：
 *
 *     npx tsx 05-agent-lab.ts
 *
 * 覆盖：createAgent 参数回读 · agent loop 三站流转 · invoke 返回解读 ·
 *       结构化输出（含 thinking 模式适配）· systemPrompt 两形态 · 动态模型路由 ·
 *       checkpointer 多轮 · recursionLimit 保护。
 *
 * 说明：脚本输出即讲义引用的实测证据，请勿修改后当作新结果引用。
 *       TS 无运行时函数签名反射（Python inspect.signature 的等价物），参数全景以
 *       「运行时配置回读 + 官方类型定义键位」呈现；模型侧经本地 OpenAI 兼容 mock
 *       端点回放固定剧本（与 Python 侧共用同一服务）。
 */
import * as z from "zod";
import dotenv from "dotenv";
import {
  tool,
  createAgent,
  createMiddleware,
  initChatModel,
  toolStrategy,
  SystemMessage,
} from "langchain";
import { MemorySaver } from "@langchain/langgraph";

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

// 结构化输出专用：关闭 thinking 的同一模型（见 3a 段原因）
const modelNoThink = await initChatModel("qwen3.8-flash", {
  modelProvider: "openai",
  apiKey: API_KEY,
  baseUrl: BASE_URL,
  maxRetries: 2,
  timeout: 60_000,
  modelKwargs: { enable_thinking: false },
});

// 动态路由的"高级模型"
const modelAdvanced = await initChatModel("deepseek-v4.1-flash", {
  modelProvider: "openai",
  apiKey: API_KEY,
  baseUrl: BASE_URL,
  maxRetries: 2,
  timeout: 60_000,
});

function section(title: string) {
  console.log(`\n${"=".repeat(16)} ${title} ${"=".repeat(16)}`);
}

function dumpChain(res: any, limit = 100) {
  res.messages.forEach((m: any, i: number) => {
    const t = m.type ?? m.constructor?.name;
    if (t === "ai" && m.tool_calls?.length) {
      for (const tc of m.tool_calls) {
        console.log(`  [${i}] AI 请求: ${tc.name}(${JSON.stringify(tc.args)})`);
      }
    } else {
      console.log(`  [${i}] ${t}: ${String(m.content).slice(0, limit)}`);
    }
  });
}

function ledger(res: any) {
  const aiMsgs = res.messages.filter((m: any) => m.type === "ai");
  const toolMsgs = res.messages.filter((m: any) => m.type === "tool");
  const nCalls = aiMsgs.reduce((n: number, m: any) => n + (m.tool_calls?.length ?? 0), 0);
  console.log(
    `   [账本] 模型被调用 ${aiMsgs.length} 次；工具申请 ${nCalls} 条；工具回执 ${toolMsgs.length} 条；消息共 ${res.messages.length} 条`
  );
}

// ================= 1. 参数全景 =================
section("1. createAgent 参数（运行时配置回读）");

const probeAgent = createAgent({ model, tools: [] });
console.log("  运行时收到的配置键:", JSON.stringify(Object.keys(probeAgent.options)));
console.log("  官方类型定义（CreateAgentParams）键位清单:");
console.log(
  "   ",
  [
    "model",
    "tools",
    "systemPrompt",
    "stateSchema",
    "contextSchema",
    "checkpointer",
    "store",
    "responseFormat",
    "middleware",
    "name",
    "description",
    "includeAgentName",
    "signal",
    "version",
    "streamTransformers",
  ].join(" / ")
);

// ================= 1b. 引擎的图结构（拆开看） =================
const getOrder = tool(
  ({ order_id }) => {
    const orders: Record<string, string> = {
      A1024: "订单 A1024：机械键盘 x2，单价 349 元；运费 12 元",
      B2048: "订单 B2048：显示器支架 x1，单价 199 元；运费 0 元",
    };
    return orders[order_id] ?? `未找到订单 ${order_id}`;
  },
  {
    name: "get_order",
    description: "查询订单明细，返回商品、单价、数量、运费（不含总价）。",
    schema: z.object({ order_id: z.string().describe("订单号") }),
  }
);

section("1b. 引擎的图结构（拆开看）");
const agentG = createAgent({ model, tools: [getOrder] });
const g = await agentG.graph.getGraphAsync({});
console.log("节点清单:");
for (const n of Object.keys(g.nodes ?? {})) console.log("  -", n);
console.log("\n边清单:");
for (const e of g.edges ?? []) {
  const cond = (e as any).conditional ? "（条件边）" : "";
  console.log(`  ${e.source} -> ${e.target} ${cond}`);
}

// ================= 2. agent loop 三站 =================
// 工具 get_order 已在 1b 段定义，下面补充本课另两个工具。
const calc = tool(
  ({ expression }) => {
    const allowed = new Set("0123456789+-*/(). ".split(""));
    if ([...expression].some((c) => !allowed.has(c))) {
      return "仅支持数字与 +-*/() 运算";
    }
    return String(eval(expression));
  },
  {
    name: "calculator",
    description: "执行四则运算。任何数学计算都必须用它。",
    schema: z.object({ expression: z.string().describe("数学表达式") }),
  }
);

const setReminder = tool(
  ({ content, when }) => `已设置提醒 [${when}]：${content}`,
  {
    name: "set_reminder",
    description: "设置一条提醒。content 为提醒内容，when 为时间描述。",
    schema: z.object({
      content: z.string().describe("提醒内容"),
      when: z.string().describe("时间描述"),
    }),
  }
);

section("2a. 站一：无工具——一步结束（模型直接说话）");
const agent0 = createAgent({ model, tools: [] });
const res0 = await agent0.invoke({
  messages: [{ role: "user", content: "请用一句话说明什么是 agent loop。" }],
});
dumpChain(res0);
ledger(res0);

section("2b. 站二：两圈循环——查订单 → 算账 → 终答");
const agent1 = createAgent({ model, tools: [getOrder, calc] });
const res1 = await agent1.invoke({
  messages: [{ role: "user", content: "帮我算下订单 A1024 一共要付多少钱（含运费）" }],
});
dumpChain(res1);
ledger(res1);

section("2c. 站三：多圈任务——查订单 → 算账 → 设提醒 → 终答");
const agent2 = createAgent({ model, tools: [getOrder, calc, setReminder] });
const res2 = await agent2.invoke({
  messages: [
    {
      role: "user",
      content: "帮我算下订单 A1024 总共多少钱，算完再设一个明天上午 10 点的提醒：给客户回电话",
    },
  ],
});
dumpChain(res2);
ledger(res2);

section("2d. 返回结构：invoke 结果里有什么");
console.log("返回类型:", res2.constructor.name);
console.log("keys:", JSON.stringify(Object.keys(res2)));
console.log("最后一条消息类型:", res2.messages.at(-1)?.constructor?.name);
console.log("最后一条消息 tool_calls:", JSON.stringify((res2.messages.at(-1) as any)?.tool_calls ?? null));

// ================= 3. 结构化输出 =================
const ContactInfo = z
  .object({
    name: z.string().describe("姓名"),
    email: z.string().describe("邮箱"),
    phone: z.string().describe("电话"),
  })
  .meta({ title: "ContactInfo" });

const Q_CONTACT = "从这段信息中提取联系人：John Doe, john@example.com, (555) 123-4567";

section("3a. 结构化输出：默认模型（thinking 模式）→ 被服务端拒绝（复现）");
try {
  const agentS0 = createAgent({ model, tools: [], responseFormat: ContactInfo });
  const resS0: any = await agentS0.invoke({ messages: [{ role: "user", content: Q_CONTACT }] });
  console.log("未报错？structuredResponse:", JSON.stringify(resS0.structuredResponse));
} catch (e: any) {
  console.log("失败 →", e.constructor.name, "|", String(e.message).slice(0, 200));
}

section("3b. 结构化输出：关闭 thinking 后 → 成功");
const agentS = createAgent({ model: modelNoThink, tools: [], responseFormat: ContactInfo });
const resS: any = await agentS.invoke({ messages: [{ role: "user", content: Q_CONTACT }] });
console.log("返回 keys:", JSON.stringify(Object.keys(resS)));
const sr = resS.structuredResponse;
console.log("structuredResponse:", JSON.stringify(sr));
console.log("类型:", sr?.constructor?.name);
dumpChain(resS, 200);

const ProductRating = z
  .object({
    rating: z.number().min(1).max(5).describe("评分，1 到 5"),
    comment: z.string().describe("评价内容"),
  })
  .meta({ title: "ProductRating" });

section("3c. 结构化输出：校验失败 → 自动重试（10/10 超出 1-5）");
const agentR = createAgent({
  model: modelNoThink,
  tools: [],
  responseFormat: toolStrategy(ProductRating),
  systemPrompt: "你是评价解析助手，严格按用户输入解析，不要擅自改动数值。",
});
const resR: any = await agentR.invoke({
  messages: [{ role: "user", content: "解析这条评价：Amazing product, 10/10!" }],
});
console.log("structuredResponse:", JSON.stringify(resR.structuredResponse));
dumpChain(resR, 150);

const EventDetails = z
  .object({
    event_name: z.string().describe("事件名称"),
    date: z.string().describe("事件日期"),
  })
  .meta({ title: "EventDetails" });

section("3d. 结构化输出的重试机制：模型一次调了两个（Union 场景）");
const agentU = createAgent({
  model: modelNoThink,
  tools: [],
  responseFormat: toolStrategy([ContactInfo, EventDetails]),
});
const resU: any = await agentU.invoke({
  messages: [
    {
      role: "user",
      content: "Extract info: John Doe (john@email.com) is organizing Tech Conference on March 15th",
    },
  ],
});
console.log("structuredResponse:", JSON.stringify(resU.structuredResponse));
dumpChain(resU, 170);

// ================= 4. harness 配置 =================
section("4a. systemPrompt 对照：无提示词 vs 角色提示词");
const Q_SELF = "请介绍一下你自己。";
const agentNp = createAgent({ model, tools: [] });
const resNp: any = await agentNp.invoke({ messages: [{ role: "user", content: Q_SELF }] });
console.log("[无提示词]", String(resNp.messages.at(-1).content).slice(0, 110));

const agentP = createAgent({
  model,
  tools: [],
  systemPrompt: "你是海盗船长，用海盗口吻回答，不超过两句话。",
});
const resP: any = await agentP.invoke({ messages: [{ role: "user", content: Q_SELF }] });
console.log("[海盗提示词]", String(resP.messages.at(-1).content).slice(0, 110));

section("4b. systemPrompt 接收 SystemMessage 对象");
const agentP2 = createAgent({
  model,
  tools: [],
  systemPrompt: new SystemMessage("你是严谨的学术助手，每次回答必须以【学术模式】开头。"),
});
const resP2: any = await agentP2.invoke({ messages: [{ role: "user", content: Q_SELF }] });
console.log("[SystemMessage 形态]", String(resP2.messages.at(-1).content).slice(0, 130));

section("4c. 动态模型选择：wrapModelCall 按对话长度路由");

const dynamicModelSelection = createMiddleware({
  name: "DynamicModelSelectionMiddleware",
  wrapModelCall: (request, handler) => {
    const n = request.messages.length;
    const [chosen, m] =
      n > 2
        ? ["deepseek-v4.1-flash（高级）", modelAdvanced]
        : ["qwen3.8-flash（基础）", model];
    console.log(`    [路由] 当前 ${n} 条消息 → 选用 ${chosen}`);
    return handler({ ...request, model: m });
  },
});

const agentDyn = createAgent({
  model,
  tools: [],
  middleware: [dynamicModelSelection],
  checkpointer: new MemorySaver(),
});
const cfgDyn = { configurable: { thread_id: "thread-dyn" } };
console.log("第一轮（1 条消息）:");
const rD1: any = await agentDyn.invoke(
  { messages: [{ role: "user", content: "一句话解释什么是函数。" }] },
  cfgDyn
);
console.log("  →", String(rD1.messages.at(-1).content).slice(0, 100));
console.log("第二轮（携带历史，消息数变多）:");
const rD2: any = await agentDyn.invoke(
  { messages: [{ role: "user", content: "再举个例子。" }] },
  cfgDyn
);
console.log("  →", String(rD2.messages.at(-1).content).slice(0, 100));

section("4d. checkpointer + thread_id：多轮对话记住身份");
const agentC = createAgent({ model, tools: [], checkpointer: new MemorySaver() });
const cfg = { configurable: { thread_id: "thread-001" } };
const rC1: any = await agentC.invoke(
  { messages: [{ role: "user", content: "我叫小明，最喜欢蓝色。请记住。" }] },
  cfg
);
console.log("第一轮回复:", String(rC1.messages.at(-1).content).slice(0, 90));
const rC2: any = await agentC.invoke(
  { messages: [{ role: "user", content: "我叫什么？最喜欢什么颜色？" }] },
  cfg
);
console.log("第二轮回复:", String(rC2.messages.at(-1).content).slice(0, 130));
console.log("第二轮返回的消息总数（含本轮与历史）:", rC2.messages.length);

const agentNc = createAgent({ model, tools: [] });
const rC3: any = await agentNc.invoke({
  messages: [{ role: "user", content: "我叫什么？最喜欢什么颜色？" }],
});
console.log("对照（无 checkpointer 的新 agent）:", String(rC3.messages.at(-1).content).slice(0, 130));

// ================= 5. 保护机制 =================
section("5. recursionLimit 保护：步数预算耗尽会报错");
try {
  const res5: any = await agent1.invoke(
    { messages: [{ role: "user", content: "帮我算下订单 A1024 一共要付多少钱（含运费）" }] },
    { recursionLimit: 4 }
  );
  console.log("未触发保护，消息数:", res5.messages.length);
} catch (e: any) {
  console.log("触发 →", e.constructor.name, "|", String(e.message).slice(0, 260));
}

console.log("\n（全部实验完成）");