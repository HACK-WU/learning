/**
 * 第 12 课 · Multi-Agent 多智能体实验（TypeScript 版，对应 playground/12-multi-agent-lab.py）
 *
 * 运行（在 playground-ts 目录内，连本地 mock 模型端点采集证据）：
 *
 *     npx tsx 12-multi-agent-lab.ts
 *
 * 设计 3 大板块（与 Python 侧脚本一一对应）：
 * 1. 为什么需要多智能体：单 agent 全能架构的上下文成本 vs 拆分后的隔离
 * 2. 核心模式：subagents（含并行调度/上下文隔离）/ handoffs（中间件型 + 子图型）
 *    / router（分类-并行-综合）
 * 3. 进阶模式与选择：skills（渐进披露）/ custom workflow（确定性+agentic 混合）
 *    / 四模式同名任务对照（one-shot + repeat 调用次数）
 *
 * 说明：脚本输出即讲义引用的实测证据，请勿修改后当作新结果引用。
 *       TS 与 Python 的 API 形态差异（本脚本实测确认）：
 *         - @tool 装饰器 → tool(fn, { name, description, schema: z.object({...}) })
 *         - init_chat_model → initChatModel
 *         - create_agent → createAgent
 *         - AgentState 子类 → new StateSchema({...})（字段/默认值）
 *         - @wrap_model_call 装饰器 → createMiddleware({ wrapModelCall })，
 *           中间件内用 handler({ ...request, systemPrompt, tools }) 覆盖 model request
 *         - 工具写状态的 Command(update=...) → new Command({ update: {...} })
 *         - 子图交接 Command(goto=..., graph=Command.PARENT) → 同结构，
 *           但 createAgent 结果作为 RunnableLike 直接 addNode 进父 StateGraph
 *         - 并行 fan-out：Send(t['agent'], {...}) → new Send(t['agent'], {...})
 *         - 回调 on_chat_model_start → CountHandler(handleChatModelStart)
 */
import * as z from "zod";
import dotenv from "dotenv";
import { readdirSync, readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { randomUUID } from "node:crypto";
import {
  tool,
  createAgent,
  createMiddleware,
  initChatModel,
  ToolMessage,
  ToolRuntime,
} from "langchain";
import { BaseCallbackHandler } from "@langchain/core/callbacks/base";
import { Document } from "@langchain/core/documents";
import { VectorStore } from "@langchain/core/vectorstores";
import { OpenAIEmbeddings } from "@langchain/openai";
import {
  MemorySaver,
  StateGraph,
  StateSchema,
  Command,
  Send,
  START,
  END,
} from "@langchain/langgraph";

dotenv.config({ path: [".env", "../playground/.env"] });

const API_KEY = process.env.BAILIAN_API_KEY;
const BASE_URL = process.env.BAILIAN_BASE_URL;
const SILICONFLOW_MODEL = process.env.SILICONFLOW_EMBEDDING_MODEL ?? "Qwen/Qwen3-Embedding-8B";
// 采集证据时连本地 mock 的 /embeddings（确定性向量）；生产为真实 SiliconFlow 地址
const EMBED_BASE_URL = process.env.MOCK_EMBED_URL ?? "http://127.0.0.1:8931/v1";

const model = await initChatModel("qwen3.8-flash", {
  modelProvider: "openai",
  apiKey: API_KEY,
  baseUrl: BASE_URL,
  maxRetries: 2,
  timeout: 60_000,
});

// 关闭思考的输出更稳定，适合分类/改写等确定性节点
const modelNoThink = await initChatModel("qwen3.8-flash", {
  modelProvider: "openai",
  apiKey: API_KEY,
  baseUrl: BASE_URL,
  maxRetries: 2,
  timeout: 60_000,
  modelKwargs: { enable_thinking: false },
});

// ============ 统计模型调用次数的回调 ============
// 对应 Python 的 BaseCallbackHandler + on_chat_model_start
class CountHandler extends BaseCallbackHandler {
  name = "CountHandler";
  calls = 0;
  async handleChatModelStart(): Promise<void> {
    this.calls += 1;
  }
}

// ============ 输出辅助 ============
function section(title: string) {
  console.log(`\n${"=".repeat(16)} ${title} ${"=".repeat(16)}`);
}

function brief(content: unknown, limit = 140): string {
  const text = content == null ? "" : String(content);
  return text.replace(/\s+/g, " ").trim().slice(0, limit);
}

async function exp(label: string, fn: () => Promise<void> | void) {
  console.log(`\n-- ${label} --`);
  const t0 = Date.now();
  try {
    await fn();
  } catch (e: any) {
    console.log(`  [失败] ${String((e as Error)?.message ?? e).slice(0, 200)}`);
  }
  console.log(`  [本项耗时 ${((Date.now() - t0) / 1000).toFixed(1)}s]`);
}

function showChain(msgs: any[], limit = 80): void {
  msgs.forEach((m: any) => {
    const type: string = typeof m.getType === "function" ? m.getType() : (m.type ?? m?.constructor?.name);
    if (type === "ai" && m.tool_calls?.length) {
      const calls = m.tool_calls
        .map((tc: any) => `${tc.name}(${JSON.stringify(tc.args)})`)
        .join("; ");
      console.log(`    [${type}] ai -> 调用工具 ${calls}`);
    } else if (type === "tool") {
      console.log(`    [${type}] tool 返回: ${brief(m.content, limit)}`);
    } else if (type === "ai" && m.content) {
      console.log(`    [${type}] ai 最终回答: ${brief(m.content, 360)}`);
    } else {
      console.log(`    [${type}]: ${brief(m.content, 70)}`);
    }
  });
}

// ============================================================
// 工具集（对应 Python 的 8 个 @tool）
// ============================================================
const getWeather = tool(({ city }: { city: string }) => `上海：晴，22°C，湿度 40%（mock，city=${city}）`, {
  name: "get_weather",
  description: "查询指定城市的当前天气。",
  schema: z.object({ city: z.string().describe("城市名称") }),
});

const getStock = tool(({ symbol }: { symbol: string }) => {
  const data: Record<string, string> = { AAPL: "189.5 美元", TSLA: "242.1 美元", "0700.HK": "378 港元" };
  return `${symbol} 当前价格：${data[symbol] ?? "未收录"}`;
}, {
  name: "get_stock",
  description: "查询股票的当前价格。",
  schema: z.object({ symbol: z.string().describe("股票代码") }),
});

const convertCurrency = tool(
  ({ amount, fromCore, to }: { amount: number; fromCore: string; to: string }) =>
    `${amount} ${fromCore} ≈ ${(amount * 7.1).toFixed(1)} ${to}（示例汇率 7.1）`,
  {
    name: "convert_currency",
    description: "货币换算。",
    schema: z.object({
      amount: z.number().describe("金额"),
      fromCore: z.string().describe("源币种"),
      to: z.string().describe("目标币种"),
    }),
  }
);

const explainSql = tool(({ sql }: { sql: string }) => `执行计划：全表扫描 -> 索引过滤 -> 排序。共 3 步。（针对: ${sql.slice(0, 40)}...）`, {
  name: "explain_sql",
  description: "解释 SQL 查询的执行计划。",
  schema: z.object({ sql: z.string().describe("SQL 语句") }),
});

const sendEmail = tool(({ to, subject }: { to: string; subject: string }) => `邮件已发送给 ${to}，主题：${subject}`, {
  name: "send_email",
  description: "发送邮件。",
  schema: z.object({ to: z.string().describe("收件人"), subject: z.string().describe("主题") }),
});

const createEvent = tool(({ title, date }: { title: string; date: string }) => `已创建日程：${title} @ ${date}`, {
  name: "create_event",
  description: "创建日历事件。",
  schema: z.object({ title: z.string().describe("事件标题"), date: z.string().describe("日期") }),
});

const translateText = tool(({ text, target_lang }: { text: string; target_lang: string }) => `[${target_lang}] ${text}`, {
  name: "translate_text",
  description: "翻译文本。",
  schema: z.object({ text: z.string().describe("待翻译文本"), target_lang: z.string().describe("目标语言") }),
});

const searchDocs = tool(({ query }: { query: string }) => `找到 3 篇与「${query}」相关的文档：A 指南、B 规范、C 手册`, {
  name: "search_docs",
  description: "搜索内部文档。",
  schema: z.object({ query: z.string().describe("检索词") }),
});

const ALL_TOOLS = [getWeather, getStock, convertCurrency, explainSql, sendEmail, createEvent, translateText, searchDocs];

const DOMAIN_KNOWLEDGE: Record<string, string> = {
  weather: "天气领域知识：本系统覆盖全国 300+ 城市的实时天气；数据每 10 分钟刷新；空气质量指数按国标计算。",
  finance: "金融领域知识：支持 A 股/港股/美股行情；汇率为示例数据；所有价格延迟 15 分钟；本系统不提供投资建议。",
  database: "数据库领域知识：支持 MySQL/PostgreSQL 执行计划解释；建议关注索引命中率与扫描行数；慢查询阈值 1 秒。",
  office: "办公领域知识：邮件发送要求填写完整收件人；日程创建需含日期；文档搜索覆盖内部 wiki。",
};

const OMNI_PROMPT =
  "你是全能助手，覆盖四个领域：\n" +
  Object.values(DOMAIN_KNOWLEDGE).join("\n") +
  "\n根据用户问题选择合适的工具完成任务。";

const omniAgent = createAgent({
  model,
  tools: ALL_TOOLS,
  systemPrompt: OMNI_PROMPT,
});

// 统计工具 schema 字符数（对应 Python tool_schema_chars）
function toolSchemaChars(tools: any[]): number {
  let total = 0;
  for (const t of tools) {
    const schema = (t.schema as any)?.shape ?? {};
    total += JSON.stringify(schema).length;
    total += (t.name?.length ?? 0) + (t.description?.length ?? 0);
  }
  return total;
}

// ============ 站一：为什么需要多智能体 ============
async function exp1a() {
  // 单 agent 全能架构
  const omniCost = OMNI_PROMPT.length + toolSchemaChars(ALL_TOOLS);
  console.log(`  [单 agent 全能架构] system_prompt ${OMNI_PROMPT.length} 字符 + 工具 schema ${toolSchemaChars(ALL_TOOLS)} 字符 = 共 ${omniCost} 字符（每次模型调用都携带）`);
  console.log(`    挂载工具数: ${ALL_TOOLS.length}（四个领域混在一起）`);
  console.log();
  // 拆分架构
  const splits: Record<string, [any[], string]> = {
    weather: [[getWeather], DOMAIN_KNOWLEDGE.weather],
    finance: [[getStock, convertCurrency], DOMAIN_KNOWLEDGE.finance],
    database: [[explainSql], DOMAIN_KNOWLEDGE.database],
    office: [[sendEmail, createEvent, translateText, searchDocs], DOMAIN_KNOWLEDGE.office],
  };
  console.log("  [拆分架构] 每个子代理只带自己领域的工具与知识：");
  const subCosts: number[] = [];
  for (const [name, [tools, knowledge]] of Object.entries(splits)) {
    const cost = knowledge.length + toolSchemaChars(tools);
    subCosts.push(cost);
    console.log(`    ${name.padEnd(9)}: ${tools.length} 个工具 + 领域知识 = ${cost} 字符`);
  }
  console.log();
  // 主代理只带子代理工具
  const subagentToolChars = "weather_expert".length + "finance_expert".length + "database_expert".length + "office_expert".length;
  const subagentDescChars =
    ['查询任意城市的天气。输入城市名称。', '查询股票价格与货币换算。输入查询内容。',
     '解释 SQL 执行计划。输入 SQL 语句。', '处理邮件、日程、翻译、文档搜索。输入任务内容。']
      .reduce((a, s) => a + s.length, 0) + 120;
  const mainCost = "你是总协调员。按任务领域调度子代理。".length + subagentToolChars + subagentDescChars;
  console.log(`  [拆分架构 · 主代理] 只带 4 个子代理工具（无领域知识）= ${mainCost} 字符`);
  console.log(`  [对照] 单 agent 每次调用携带 ~${omniCost} 字符；拆分后主代理 ~${mainCost} 字符，子代理按需 ~${Math.min(...subCosts)}-${Math.max(...subCosts)} 字符`);
}

async function exp1b() {
  const counter = new CountHandler();
  const q = "帮我做两件事：1) 查一下上海现在的天气；2) 给我看看 AAPL 的股价。";
  console.log(`  问题: ${q}`);
  const r: any = await omniAgent.invoke({ messages: [{ role: "user", content: q }] }, { callbacks: [counter] });
  console.log(`  模型调用: ${counter.calls} 次`);
  console.log("  消息路径：");
  showChain(r.messages, 100);
}

// ============ 站二：子代理工厂 makeSpecialist ============
function makeSpecialist(name: string, tools: any[], knowledge: string, desc: string) {
  const agent = createAgent({ model, tools, systemPrompt: knowledge });
  return tool(async ({ query }: { query: string }) => {
    const r: any = await agent.invoke({ messages: [{ role: "user", content: query }] });
    return r.messages.at(-1)?.content ?? "";
  }, {
    name,
    description: desc,
    schema: z.object({ query: z.string().describe("交给该专家的任务描述") }),
  });
}

const weatherExpert = makeSpecialist(
  "weather_expert",
  [getWeather],
  DOMAIN_KNOWLEDGE.weather,
  "查询天气。输入城市名称，返回该城市天气。"
);
const financeExpert = makeSpecialist(
  "finance_expert",
  [getStock, convertCurrency],
  DOMAIN_KNOWLEDGE.finance,
  "查询股票价格或做货币换算。输入查询内容。"
);
const databaseExpert = makeSpecialist(
  "database_expert",
  [explainSql],
  DOMAIN_KNOWLEDGE.database,
  "解释 SQL 执行计划。输入 SQL 语句。"
);

const MAIN_PROMPT =
  "你是总协调员。你自己不直接处理领域任务，而是调度相应的领域专家（子代理工具）：\n" +
  "- weather_expert：天气相关\n" +
  "- finance_expert：股票、汇率相关\n" +
  "- database_expert：SQL、数据库相关\n" +
  "接到任务后，把每个子任务交给对应的专家，最后汇总它们的答复回复用户。";

const mainAgent = createAgent({
  model,
  tools: [weatherExpert, financeExpert, databaseExpert],
  systemPrompt: MAIN_PROMPT,
});

// ============================================================
// 站二 · subagents：2a / 2b / 2c
// ============================================================

async function exp2a() {
  const counter = new CountHandler();
  const q = "杭州今天天气怎么样？";
  console.log(`  问题: ${q}`);
  const r: any = await mainAgent.invoke(
    { messages: [{ role: "user", content: q }] },
    { callbacks: [counter] }
  );
  console.log(`  模型调用总数: ${counter.calls} 次（主代理 2 + 子代理内部 2）`);
  console.log("  主会话消息路径（注意：子代理内部消息不可见）：");
  showChain(r.messages, 100);
}

async function exp2b() {
  const counter = new CountHandler();
  const q =
    "帮我并行处理三件事：1) 查一下成都的天气；2) 看看 TSLA 股价；3) 解释这条 SQL：SELECT * FROM orders WHERE user_id = 42";
  console.log(`  问题: ${q}`);
  const r: any = await mainAgent.invoke(
    { messages: [{ role: "user", content: q }] },
    { callbacks: [counter] }
  );
  console.log(`  模型调用总数: ${counter.calls} 次`);
  console.log("  消息路径（观测主代理是否一次发起多个子代理调用）：");
  showChain(r.messages, 90);
}

async function exp2c() {
  // 对照：直接把"帮我查一下天气"交给裸子代理（无历史）
  console.log("  [对照组] 直接把'帮我查一下天气'交给子代理（无任何历史）：");
  const bareWeather = createAgent({
    model,
    tools: [getWeather],
    systemPrompt: DOMAIN_KNOWLEDGE.weather,
  });
  const r0: any = await bareWeather.invoke({
    messages: [{ role: "user", content: "帮我查一下天气。" }],
  });
  console.log(`    子代理回复: ${brief(r0.messages.at(-1)?.content, 160)}`);
  console.log();

  // 实验组：主代理两轮对话（先用 checkpointer 记住城市）
  console.log("  [实验组] 主代理两轮对话（先用 checkpointer 记住城市）：");
  const agent = createAgent({
    model,
    tools: [weatherExpert],
    systemPrompt: MAIN_PROMPT + "\n用户之前提到的城市信息请记在心里，调度天气专家时把城市传给它。",
    checkpointer: new MemorySaver(),
  });
  const cfg = { configurable: { thread_id: "pre-2c" } };
  const r1: any = await agent.invoke(
    { messages: [{ role: "user", content: "我在上海工作。" }] },
    cfg
  );
  console.log(`    第 1 轮（告知信息）: 主代理回复 ${brief(r1.messages.at(-1)?.content, 90)}`);
  const r2: any = await agent.invoke(
    { messages: [{ role: "user", content: "帮我查一下天气。" }] },
    cfg
  );
  console.log(`    第 2 轮（未提城市）消息路径：`);
  showChain(r2.messages, 100);
  console.log(`    → 观测点：主代理是否从历史中取出'上海'并传给 weather_expert`);
}

// ============================================================
// 站二 · handoffs（single agent with middleware）三阶段流程 · 2d
// ============================================================

// 对应 Python SupportState(AgentState) —— TS 用 StateSchema
const SupportState = new StateSchema({
  current_step: z.string().default("triage"),
  device: z.string().optional(),
  warranty: z.string().optional(),
  symptom: z.string().optional(),
});
type SupportStateT = {
  current_step: string;
  device?: string;
  warranty?: string;
  symptom?: string;
};

// 工具写状态：返回 Command(update)（对应 Python runtime + Command(update=...)）
const recordWarranty = tool(
  async (
    { device, warranty }: { device: string; warranty: string },
    runtime: ToolRuntime<SupportStateT>
  ) => {
    return new Command({
      update: {
        messages: [
          new ToolMessage({ content: `已记录：${device} / ${warranty}`, tool_call_id: runtime.toolCall?.id ?? "" }),
        ],
        device,
        warranty,
        current_step: "diagnose",
      },
    });
  },
  {
    name: "record_warranty",
    description: "记录设备型号与保修状态，进入诊断阶段。warranty 取值: in_warranty / out_of_warranty",
    schema: z.object({
      device: z.string().describe("设备型号"),
      warranty: z.string().describe("保修状态: in_warranty / out_of_warranty"),
    }),
  }
);

const diagnoseIssue = tool(
  async ({ symptom }: { symptom: string }, runtime: ToolRuntime<SupportStateT>) => {
    return new Command({
      update: {
        messages: [
          new ToolMessage({ content: `诊断完成：${symptom}`, tool_call_id: runtime.toolCall?.id ?? "" }),
        ],
        symptom,
        current_step: "resolution",
      },
    });
  },
  {
    name: "diagnose_issue",
    description: "记录故障现象，进入解决方案阶段。",
    schema: z.object({ symptom: z.string().describe("故障现象") }),
  }
);

const provideSolution = tool(() => "解决方案：符合免费换屏条件，预约后 3 个工作日完成。", {
  name: "provide_solution",
  description: "给出最终解决方案。",
  schema: z.object({}),
});

const STEP_CONFIGS: Record<string, { prompt: string; tools: any[] }> = {
  triage: {
    prompt: "你是客服分诊员（triage 阶段）。礼貌地询问设备型号与保修状态，并用 record_warranty 工具记录。",
    tools: [recordWarranty],
  },
  diagnose: {
    prompt: "你是故障诊断员（diagnose 阶段）。设备与保修已知，请询问故障现象并用 diagnose_issue 工具记录。",
    tools: [diagnoseIssue],
  },
  resolution: {
    prompt: "你是维修专家（resolution 阶段）。请先用 provide_solution 工具获取方案，再用友好的语气向用户说明。",
    tools: [provideSolution],
  },
};

const MIDDLEWARE_LOG: [string, string[]][] = [];

// 对应 Python @wrap_model_call 装饰器 —— TS 用 createMiddleware({ wrapModelCall })
// TS 差异：中间件通过 handler({ ...request, 覆盖字段 }) 展开覆盖 model request；
// 这里只覆盖 systemPrompt（字符串）与 tools，不碰 systemMessage，
// 因为 AgentNode 不允许在同一请求里同时修改 systemPrompt 与 systemMessage。
const applyStepConfig = createMiddleware({
  name: "ApplyStepConfig",
  wrapModelCall: async (request: any, handler: any) => {
    const step = (request.state?.current_step as string) ?? "triage";
    const cfg = STEP_CONFIGS[step];
    const toolNames = cfg.tools.map((t: any) => t.name);
    MIDDLEWARE_LOG.push([step, toolNames]);
    console.log(`      [中间件] step=${step} | 工具集=${JSON.stringify(toolNames)}`);
    // 覆盖本轮 model request 的 system prompt 与可用工具子集
    return handler({
      ...request,
      systemPrompt: cfg.prompt,
      tools: cfg.tools,
    });
  },
});

const supportAgent = createAgent({
  model,
  tools: [recordWarranty, diagnoseIssue, provideSolution],
  stateSchema: SupportState,
  middleware: [applyStepConfig],
  checkpointer: new MemorySaver(),
});

async function exp2d() {
  const cfg = { configurable: { thread_id: "pre-2d" } };
  const turns = ["我的手机屏幕碎了想修。", "华为 P60，还在保修期内。", "就是昨天摔了一下，屏幕左上角裂了。"];
  for (let i = 0; i < turns.length; i++) {
    console.log(`  [第 ${i + 1} 轮] 用户: ${turns[i]}`);
    const r: any = await supportAgent.invoke(
      { messages: [{ role: "user", content: turns[i] }] },
      cfg
    );
    console.log(`    step=${r.current_step} | 回复: ${brief(r.messages.at(-1)?.content, 120)}`);
    console.log();
  }
  console.log(`  中间件调用轨迹（step 演进）: ${JSON.stringify(MIDDLEWARE_LOG)}`);
}

// ============================================================
// 站二 · handoffs（multiple agent subgraphs）· 2e
// ============================================================

// 对应 Python MultiAgentState(AgentState) —— 仅 messages + active_agent
const MultiAgentState = new StateSchema({
  messages: z.array(z.any()).default([]),
  active_agent: z.string().optional(),
});
type MultiAgentStateT = {
  messages: any[];
  active_agent?: string;
};

// 转交工具：返回 Command(goto, update, graph=Command.PARENT)，
// goto 指向父图中的子图节点名，Command.PARENT 表示向上交给父图路由
const transferToSupport = tool(async (_: any, runtime: ToolRuntime<MultiAgentStateT>) => {
  const msgs = runtime.state?.messages ?? [];
  const lastAi = [...msgs].reverse().find((m: any) => (typeof m.getType === "function" ? m.getType() : m.type) === "ai");
  return new Command({
    goto: "support_agent",
    update: {
      active_agent: "support_agent",
      messages: [
        lastAi,
        new ToolMessage({ content: "已转接到技术支持代理", tool_call_id: runtime.toolCall?.id ?? "" }),
      ],
    },
    graph: Command.PARENT,
  });
}, {
  name: "transfer_to_support",
  description: "把对话转交给技术支持代理。",
  schema: z.object({}),
});

const transferToSales = tool(async (_: any, runtime: ToolRuntime<MultiAgentStateT>) => {
  const msgs = runtime.state?.messages ?? [];
  const lastAi = [...msgs].reverse().find((m: any) => (typeof m.getType === "function" ? m.getType() : m.type) === "ai");
  return new Command({
    goto: "sales_agent",
    update: {
      active_agent: "sales_agent",
      messages: [
        lastAi,
        new ToolMessage({ content: "已转接到销售代理", tool_call_id: runtime.toolCall?.id ?? "" }),
      ],
    },
    graph: Command.PARENT,
  });
}, {
  name: "transfer_to_sales",
  description: "把对话转交给销售代理。",
  schema: z.object({}),
});

const gatewaySales = createAgent({
  model,
  tools: [transferToSupport],
  systemPrompt: "你是销售代理，负责报价与购买咨询。若客户问技术问题，调用 transfer_to_support 转交。",
});
const gatewaySupport = createAgent({
  model,
  tools: [transferToSales],
  systemPrompt: "你是技术支持代理，负责技术问题排查。若客户问价格，调用 transfer_to_sales 转交。",
});

// TS 差异：createAgent 结果是编译后的图，不能直接作为 addNode 的 node 传入
// （_coerceToRunnable 无法识别），需包一层函数再安装，与 Python 的 call_sales/call_support 一致。
function callSales(state: any) {
  return gatewaySales.invoke(state);
}
function callSupport(state: any) {
  return gatewaySupport.invoke(state);
}

function isAiNoTools(m: any): boolean {
  const type = typeof m.getType === "function" ? m.getType() : m.type;
  return type === "ai" && (!m.tool_calls || m.tool_calls.length === 0);
}

function routeAfter(state: any): string {
  const msgs = state?.messages ?? [];
  if (msgs.length) {
    const last = msgs[msgs.length - 1];
    if (isAiNoTools(last)) return END;
  }
  return state?.active_agent ?? "sales_agent";
}

function routeInitial(state: any): string {
  return state?.active_agent ?? "sales_agent";
}

// TS 注：StateGraph 用 new (StateGraph as any) 构造（channels 形式在 strict 下
// 会被 TS 误解析为 {__root__} 通道），messages 用累加 reducer、active_agent 用覆盖 reducer。
const gatewayGraph = new (StateGraph as any)({
  channels: {
    messages: (cur: any[], upd: any) =>
      upd == null ? cur : Array.isArray(upd) ? [...(cur ?? []), ...upd] : [...(cur ?? []), upd],
    active_agent: (_cur: any, upd: any) => upd,
  },
})
.addNode("sales_agent", callSales)
  .addNode("support_agent", callSupport)
  .addConditionalEdges(START, routeInitial, ["sales_agent", "support_agent"])
  .addConditionalEdges("sales_agent", routeAfter, ["sales_agent", "support_agent", END])
  .addConditionalEdges("support_agent", routeAfter, ["sales_agent", "support_agent", END])
  .compile();

async function exp2e() {
  const q = "你们这个设备多少钱？另外它连不上网怎么修？";
  console.log(`  问题: ${q}`);
  const r: any = await gatewayGraph.invoke({
    messages: [{ role: "user", content: q }],
  });
  console.log("  消息路径：");
  showChain(r.messages, 95);
  console.log(`  最终 active_agent: ${r.active_agent}`);
}

// ============================================================
// 站二 · router（分类 -> 并行分派 -> 综合）· 2f
// ============================================================

// 对应 Python RouterState(TypedDict) + operator.add 规约 —— 用数组做累积字段
const RouterState = new StateSchema({
  query: z.string().default(""),
  subtasks: z.array(z.any()).default([]),
  results: z.array(z.string()).default([]),
  final: z.string().default(""),
});
type RouterStateT = {
  query: string;
  subtasks: any[];
  results: string[];
  final: string;
};

const ROUTER_MATERIAL: Record<string, string> = {
  tech: "自研大模型平台已支持智能体框架；上线三个月调用量增长 300%。",
  finance: "差旅报销需在费用发生后 30 天内提交；住宿一线城市上限 600 元/晚。",
  hr: "年假按司龄阶梯：1-3 年 5 天，3-5 年 10 天，5 年以上 15 天。",
};

async function routerClassify(state: RouterStateT) {
  const prompt =
    "判断下面这个问题涉及哪些领域，可多选。领域列表：tech（研发技术）、finance（财务报销）、hr（人事制度）。\n" +
    "只输出 JSON 数组，如 [\"tech\",\"finance\"]，不要其他文字。\n" +
    `问题：${state.query}`;
  const r: any = await modelNoThink.invoke(prompt);
  const content = typeof r === "string" ? r : r?.content ?? "";
  let domains: string[] = [];
  try {
    const m = content.match(/\[[^\]]*\]/);
    domains = JSON.parse(m ? m[0] : "[]");
  } catch {
    domains = [];
  }
  domains = domains.filter((d) => d in ROUTER_MATERIAL);
  if (!domains.length) domains = ["tech"];
  console.log(`  [分类] 命中领域: ${JSON.stringify(domains)}`);
  return { subtasks: domains.map((d) => ({ agent: d, query: state.query })) };
}

function makeDomainNode(domain: string) {
  const material = ROUTER_MATERIAL[domain];
  const searchTool = tool(({ q }: { q: string }) => `[${domain}知识库] 与"${q}"相关：${material}`, {
    name: `search_${domain}`,
    description: `在${domain}知识库中搜索`,
    schema: z.object({ q: z.string().describe("检索词") }),
  });
  const agent = createAgent({
    model,
    tools: [searchTool],
    systemPrompt: `你是${domain}领域专家。先检索再基于结果回答。`,
  });
  return async function node(state: any) {
    const r: any = await agent.invoke({ messages: [{ role: "user", content: state.query }] });
    return { results: [`[${domain}] ${r.messages.at(-1)?.content ?? ""}`] };
  };
}

function routerFanOut(state: RouterStateT) {
  return state.subtasks.map((t) => new Send(t.agent, { query: t.query }));
}

async function routerSynthesize(state: RouterStateT) {
  const joined = state.results.join("\n");
  const r: any = await modelNoThink.invoke(
    `把以下多来源信息综合成一段连贯回答（保留关键数字）：\n${joined}`
  );
  return { final: typeof r === "string" ? r : r?.content ?? "" };
}

function buildRouter() {
  // results 用累加 reducer（对应 Python operator.add 规约）
  const g: any = new (StateGraph as any)({
    channels: {
      query: (_cur: any, upd: any) => upd,
      subtasks: (_cur: any, upd: any) => upd,
      results: (cur: string[], upd: string[]) => [...(cur ?? []), ...(upd ?? [])],
      final: (_cur: any, upd: any) => upd,
    },
  });
  g.addNode("classify", routerClassify);
  g.addNode("synthesize", routerSynthesize);
  g.addEdge(START, "classify");
  g.addEdge("synthesize", END);
  for (const domain of Object.keys(ROUTER_MATERIAL)) {
    g.addNode(domain, makeDomainNode(domain));
    g.addEdge(domain, "synthesize");
  }
  const domainTargets = Object.keys(ROUTER_MATERIAL);
  g.addConditionalEdges("classify", routerFanOut, domainTargets);
  return g.compile();
}

const routerGraph = buildRouter();

async function exp2f() {
  const counter = new CountHandler();
  const q = "我们研发同事去上海出差，住宿能报多少？顺便说下我们平台的进展。";
  console.log(`  问题: ${q}`);
  const r: any = await routerGraph.invoke(
    { query: q, subtasks: [], results: [] },
    { callbacks: [counter] }
  );
  console.log(`  模型调用总数: ${counter.calls} 次（分类 1 + 各领域代理 + 综合 1）`);
  console.log(`  并行结果 ${r.results.length} 条：`);
  for (const res of r.results) console.log(`    ${brief(res, 110)}`);
  console.log(`  综合回答: ${brief(r.final, 220)}`);
}

// ============================================================
// 站三 · 进阶模式与选择
// ============================================================

// ---- 3a: skills（渐进式披露 + 行为对照）----
const SKILLS: Record<string, string> = {
  sql_expert:
    "你是 SQL 专家。写查询时必须遵守：\n" +
    "1) 禁止 SELECT *，必须显式列出字段；\n" +
    "2) 时间过滤用 WHERE，不要全表扫描；\n" +
    "3) 输出结构：先给 SQL，再给一句性能提示。",
  legal_reviewer:
    "你是合同审查专家。审查时逐项检查：违约责任 / 知识产权归属 / 争议解决方式。输出风险清单。",
};

const loadSkill = tool(({ skill_name }: { skill_name: string }) => {
  if (skill_name in SKILLS) return `[技能已加载: ${skill_name}]\n${SKILLS[skill_name]}`;
  return `未知技能: ${skill_name}。可用: ${JSON.stringify(Object.keys(SKILLS))}`;
}, {
  name: "load_skill",
  description: "加载专业技能包。可用技能：sql_expert（SQL 查询编写专家）、legal_reviewer（合同审查专家）",
  schema: z.object({ skill_name: z.string().describe("技能名") }),
});

async function exp3a() {
  const counterS = new CountHandler();
  const skillAgent = createAgent({
    model,
    tools: [loadSkill],
    systemPrompt:
      "你是通用助手。有两个技能：sql_expert（SQL 编写）与 legal_reviewer（合同审查）。" +
      "任务涉及这些领域时，必须先调用 load_skill 加载对应技能，再按技能要求完成。",
  });
  const q = "帮我写一条 SQL：查询用户表里最近 7 天注册的用户。";
  console.log(`  [A 有技能] ${q}`);
  const r: any = await skillAgent.invoke(
    { messages: [{ role: "user", content: q }] },
    { callbacks: [counterS] }
  );
  console.log(`    模型调用: ${counterS.calls} 次`);
  console.log("    消息路径：");
  showChain(r.messages, 160);
  console.log();

  const counterN = new CountHandler();
  const bareAgent = createAgent({ model, tools: [], systemPrompt: "你是通用助手。简洁回答。" });
  console.log(`  [B 无技能对照] ${q}`);
  const r2: any = await bareAgent.invoke(
    { messages: [{ role: "user", content: q }] },
    { callbacks: [counterN] }
  );
  console.log(`    模型调用: ${counterN.calls} 次`);
  console.log(`    回答: ${brief(r2.messages.at(-1)?.content, 200)}`);
}

// ---- 3b: custom workflow（rewrite -> retrieve -> agent 的 RAG 流水线）----
// 复用 11 课的自实现内存向量库（余弦）与 ./kb 语料
type RagDoc = Document<Record<string, any>>;

class MiniMemoryVectorStore extends VectorStore {
  FilterType = {};
  private vectors: number[][] = [];
  private docs: RagDoc[] = [];
  private ids: string[] = [];
  _vectorstoreType(): string {
    return "mini_memory";
  }
  get size(): number {
    return this.vectors.length;
  }
  async addVectors(vectors: number[][], documents: RagDoc[]): Promise<string[]> {
    const createdIds = documents.map(() => randomUUID());
    for (let i = 0; i < documents.length; i++) {
      this.vectors.push(vectors[i] ?? []);
      this.docs.push(documents[i]);
      this.ids.push(createdIds[i]);
    }
    return createdIds;
  }
  async addDocuments(documents: RagDoc[]): Promise<string[]> {
    const texts = documents.map((d) => d.pageContent);
    const vectors = await this.embeddings.embedDocuments(texts);
    return this.addVectors(vectors, documents);
  }
  async similaritySearchVectorWithScore(query: number[], k: number): Promise<[RagDoc, number][]> {
    const cos = (a: number[], b: number[]) => {
      let dot = 0, na = 0, nb = 0;
      for (let i = 0; i < a.length; i++) { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i]; }
      const denom = Math.sqrt(na) * Math.sqrt(nb);
      return denom === 0 ? 0 : dot / denom;
    };
    return this.vectors
      .map((v, i) => [this.docs[i], cos(query, v)] as [RagDoc, number])
      .sort((a, b) => b[1] - a[1])
      .slice(0, k);
  }
}

const KB_DIR = join(dirname(fileURLToPath(import.meta.url)), "../playground/kb");

async function exp3b() {
  const embeddings = new OpenAIEmbeddings({
    model: SILICONFLOW_MODEL,
    apiKey: process.env.SILICONFLOW_API_KEY ?? "mock",
    configuration: { baseURL: EMBED_BASE_URL },
    timeout: 60_000,
    stripNewLines: false,
  });
  const docs: RagDoc[] = readdirSync(KB_DIR)
    .filter((f) => f.endsWith(".md"))
    .sort()
    .map((f) => new Document({
      pageContent: readFileSync(join(KB_DIR, f), "utf-8"),
metadata: { source: f },
    }));
  const store = new MiniMemoryVectorStore(embeddings, {});
  await (store as any).addDocuments(docs);
  console.log(`  [准备] 知识库 ${docs.length} 份文档已入库（复用课 11 语料）`);

  // WFState: question / rewritten / docs / answer
  async function nodeRewrite(state: any) {
    const r: any = await modelNoThink.invoke(
      "把下面的问题改写成适合检索的关键词（一行，不加解释）：\n" + state.question
    );
    const rw = (typeof r === "string" ? r : r?.content ?? "").trim();
    console.log(`    [rewrite 节点] '${state.question}' -> '${rw.slice(0, 60)}'`);
return { rewritten: rw };
  }
  async function nodeRetrieve(state: any) {
    const hits = await (store as any).similaritySearch(state.rewritten, 2);
    const texts = (hits as any[]).map((d: any) => `[${d.metadata.source}] ${d.pageContent.slice(0, 120)}`);
    console.log(`    [retrieve 节点] 命中 ${hits.length} 块: ${JSON.stringify((hits as any[]).map((d: any) => d.metadata.source))}`);
    return { docs: texts };
  }
  const answerAgent = createAgent({
    model,
    tools: [getWeather],
    systemPrompt: "你是企业助手。基于给定资料回答问题并注明来源；资料不足时如实说明。",
  });
  async function nodeAgent(state: any) {
    const context = state.docs.join("\n");
    const r: any = await answerAgent.invoke({
      messages: [{ role: "user", content: `资料：\n${context}\n\n问题：${state.question}` }],
    });
    return { answer: r.messages.at(-1)?.content ?? "" };
  }

  const WFState = new StateSchema({
    question: z.string().default(""),
    rewritten: z.string().default(""),
    docs: z.array(z.string()).default([]),
    answer: z.string().default(""),
  });
  const wf = new StateGraph(WFState)
    .addNode("rewrite", nodeRewrite as any)
    .addNode("retrieve", nodeRetrieve as any)
    .addNode("agent", nodeAgent as any)
    .addEdge(START, "rewrite")
    .addEdge("rewrite", "retrieve")
    .addEdge("retrieve", "agent")
    .addEdge("agent", END)
    .compile();

  const q = "年假怎么请";
  console.log(`  问题: ${q}`);
  const r: any = await wf.invoke({ question: q });
  console.log(`  回答: ${brief(r.answer, 260)}`);
  console.log(`  节点轨迹: rewrite(模型) -> retrieve(确定性) -> agent(agentic)`);
}

// ---- 3c: 四模式同名任务对照（南京天气）----
async function exp3c() {
  console.log("  任务统一为：'南京今天天气怎么样？'（one-shot 与 repeat 各测一轮）");
  console.log();

  // --- A. subagents ---
  console.log("  [A: subagents]");
  const aMain = createAgent({
    model,
    tools: [weatherExpert],
    systemPrompt: "你是总协调员，调度 weather_expert 处理天气任务。",
  });
  const cA1 = new CountHandler();
  await aMain.invoke({ messages: [{ role: "user", content: "南京今天天气怎么样？" }] }, { callbacks: [cA1] });
  console.log(`    turn1 模型调用: ${cA1.calls} 次（主代理决策 + 子代理内部 + 主代理汇总）`);
  const cA2 = new CountHandler();
  await aMain.invoke({ messages: [{ role: "user", content: "南京今天天气怎么样？" }] }, { callbacks: [cA2] });
  console.log(`    turn2 模型调用: ${cA2.calls} 次（无状态，重走全流程）`);
  console.log();

  // --- B. skills ---
  console.log("  [B: skills]");
  const loadWeatherSkill = tool(
    () =>
      "[weather 技能已加载]\n天气查询流程：1) 确认城市；2) 调用 get_weather 工具；3) 用一句话播报结果（含温度）。",
    {
      name: "load_weather_skill",
      description: "加载天气流程技能。任务涉及天气查询时必须先加载此技能。",
      schema: z.object({}),
    }
  );
  const skillAgent = createAgent({
    model,
    tools: [loadWeatherSkill, getWeather],
    systemPrompt:
      "你是助手。执行天气任务前必须先调用 load_weather_skill 加载流程技能，再按技能指引完成。如果技能已在对话中加载过，则直接执行。",
  });
  const cB1 = new CountHandler();
  await skillAgent.invoke({ messages: [{ role: "user", content: "南京今天天气怎么样？" }] }, { callbacks: [cB1] });
  console.log(`    turn1 模型调用: ${cB1.calls} 次（加载技能 + 查询 + 回复）`);
  const cB2 = new CountHandler();
  await skillAgent.invoke({ messages: [{ role: "user", content: "南京今天天气怎么样？" }] }, { callbacks: [cB2] });
  console.log(`    turn2 模型调用: ${cB2.calls} 次（技能已在历史，直接执行）`);
  console.log();

  // --- C. router ---
  console.log("  [C: router]");
  const MiniRouterState = new StateSchema({
    query: z.string().default(""),
    final: z.string().default(""),
  });
  const weatherNodeAgent = createAgent({
    model,
    tools: [getWeather],
    systemPrompt: "你是天气领域专家。用工具查询后简洁回答。",
  });
  async function miniRoute(state: any) {
    const r: any = await modelNoThink.invoke(
      "判断问题是否与天气相关。只输出 WEATHER 或 OTHER。\n问题：" + state.query
    );
    const content = typeof r === "string" ? r : r?.content ?? "";
    console.log(`    [分类] ${content.trim().slice(0, 20)}`);
    return {};
  }
  async function miniWeather(state: any) {
    const r: any = await weatherNodeAgent.invoke({ messages: [{ role: "user", content: state.query }] });
    return { final: r.messages.at(-1)?.content ?? "" };
  }
  const miniRouter = new StateGraph(MiniRouterState)
    .addNode("classify", miniRoute as any)
    .addNode("weather", miniWeather as any)
    .addEdge(START, "classify")
    .addEdge("classify", "weather")
    .addEdge("weather", END)
    .compile();
  const cC1 = new CountHandler();
  await miniRouter.invoke({ query: "南京今天天气怎么样？" }, { callbacks: [cC1] });
  console.log(`    turn1 模型调用: ${cC1.calls} 次（分类 + 领域代理 + 回复）`);
  const cC2 = new CountHandler();
  await miniRouter.invoke({ query: "南京今天天气怎么样？" }, { callbacks: [cC2] });
  console.log(`    turn2 模型调用: ${cC2.calls} 次（无状态，重新分类走全流程）`);
  console.log();

  // --- D. handoffs ---
  console.log("  [D: handoffs]");
  const WState = new StateSchema({
    current_step: z.string().default("ask_city"),
    city: z.string().optional(),
  });
  const confirmCity = tool(
    async ({ city }: { city: string }, runtime: ToolRuntime<{ current_step: string; city?: string }>) =>
      new Command({
        update: {
          messages: [
            new ToolMessage({ content: `城市已确认：${city}`, tool_call_id: runtime.toolCall?.id ?? "" }),
          ],
          city,
          current_step: "ready",
        },
      }),
    {
      name: "confirm_city",
      description: "确认城市并进入查询就绪状态。",
      schema: z.object({ city: z.string().describe("城市名") }),
    }
  );
  const wfConfig = createMiddleware({
    name: "WfConfig",
    wrapModelCall: async (request: any, handler: any) => {
      const step: string = (request.state?.current_step as string) ?? "ask_city";
      if (step === "ask_city") {
        return handler({
          ...request,
          systemPrompt: "你在询问用户的出行城市。用 confirm_city 工具记录城市。",
          tools: [confirmCity],
        });
      }
      const city = (request.state?.city as string) ?? "";
      return handler({
        ...request,
        systemPrompt: `城市已确认（${city}）。用 get_weather 查询并用一句话回复。`,
        tools: [getWeather],
      });
    },
  });
  const handoffAgent = createAgent({
    model,
    tools: [confirmCity, getWeather],
    stateSchema: WState,
    middleware: [wfConfig],
    checkpointer: new MemorySaver(),
  });
  const cfgD = { configurable: { thread_id: "pre-3c-d" } };
  const cD1 = new CountHandler();
  await handoffAgent.invoke(
    { messages: [{ role: "user", content: "今天天气怎么样？" }] },
    { ...cfgD, callbacks: [cD1] }
  );
  console.log(`    turn1（未给城市）模型调用: ${cD1.calls} 次（ask_city 阶段——询问城市）`);
  const cD2 = new CountHandler();
  await handoffAgent.invoke(
    { messages: [{ role: "user", content: "南京" }] },
    { ...cfgD, callbacks: [cD2] }
  );
  console.log(`    turn2（补充城市）模型调用: ${cD2.calls} 次（迁移到 ready → 查询 → 回复）`);
  const cD3 = new CountHandler();
  await handoffAgent.invoke(
    { messages: [{ role: "user", content: "再看看天气" }] },
    { ...cfgD, callbacks: [cD3] }
  );
  console.log(`    turn3（重复请求）模型调用: ${cD3.calls} 次（状态保持 ready，直接执行）`);
}

// ============================================================
// 主流程
// ============================================================
console.log("课 12《Multi-Agent 多智能体》· 全流程实测");
console.log(`环境: langchain-js | @langchain/langgraph | 模型 qwen3.8-flash（本地 mock 端点）`);

section("站一 · 单 agent 极限与拆分");
await exp("1a 静态上下文成本对照", exp1a);
await exp("1b 单 agent 跨领域工具选择", exp1b);

section("站二 · 三大核心模式");
await exp("2a subagents：单体调度", exp2a);
await exp("2b subagents：并行调度", exp2b);
await exp("2c subagents：上下文隔离", exp2c);
await exp("2d handoffs（middleware）：三阶段迁移", exp2d);
await exp("2e handoffs（subgraph）：销售↔客服", exp2e);
await exp("2f router：分类-并行-综合", exp2f);

section("站三 · 进阶模式与选择");
await exp("3a skills：加载与行为对照", exp3a);
await exp("3b custom workflow：RAG 流水线", exp3b);
await exp("3c 四模式调用次数对照", exp3c);

console.log("\n全部实验执行完毕。");