/**
 * 第 9 课 · Context Engineering 上下文工程实验（TypeScript 版，对应 playground/09-context-lab.py）
 *
 * 运行（在 playground-ts 目录内，模型侧连本地 mock 端点采集证据）：
 *
 *     BAILIAN_BASE_URL=http://127.0.0.1:8931/v1 BAILIAN_API_KEY=mock npx tsx 09-context-lab.ts
 *
 * 设计 4 大板块（对应 3 个知识点，与 Python 侧脚本一一对应）：
 * 1. 上下文工程是什么：组装视图（模型看到什么）+ 成本对照（上下文窗口=稀缺资源）
 * 2. 模型上下文：动态提示词（状态/运行时）× 消息注入（瞬时 vs 持久）× 动态工具 × 动态格式 × 工具结果清理（瞬时截断 vs ContextEditing）
 * 3. 工具上下文：工具读运行时上下文 / 读写状态（Command）/ 写 store（跨会话）
 * 4. 生命周期上下文：摘要的持久更新 + 自定义审计钩子（状态计数 + store 沉淀）
 *
 * 说明：脚本输出即讲义引用的实测证据，请勿修改后当作新结果引用。
 *       TS 侧与 Python 侧的 API 形态差异（本脚本实测确认）：
 *         - 无 @dynamic_prompt 装饰器 → createMiddleware + wrapModelCall 修改 request.systemMessage
 *         - 动态提示词：request.systemMessage.concat(...)（Python 为返回完整 system prompt 字符串）
 *         - 瞬时消息注入：handler({ ...request, messages: [...] })（Python 为 request.override(messages=...)，不改状态）
 *         - 持久消息注入：handler 后返回 new Command({ update: { messages: [...] } })（Python 为 ExtendedModelResponse）
 *         - 工具过滤 / 格式收窄：handler({ ...request, tools / responseFormat })（Python 为 request.override(tools=...))
 *         - context：中间件 request.runtime.context，工具 runtime.context；contextSchema 用 zod
 *         - 无 ExtendedModelResponse 导出 → 持久注入直接返回 Command
 *         - 摘要：summarizationMiddleware({ trigger: { messages } })（驼峰）
 *         - 结果清理：contextEditingMiddleware + new ClearToolUsesEdit({ trigger: { tokens } })（Python 为 trigger=token 数）
 */
import * as z from "zod";
import dotenv from "dotenv";
import {
  tool,
  createAgent,
  createMiddleware,
  initChatModel,
  toolStrategy,
  summarizationMiddleware,
  contextEditingMiddleware,
  ClearToolUsesEdit,
  HumanMessage,
  ToolMessage,
  type ToolRuntime,
} from "langchain";
import { MemorySaver, InMemoryStore, Command } from "@langchain/langgraph";

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

const modelNoThink = await initChatModel("qwen3.8-flash", {
  modelProvider: "openai",
  apiKey: API_KEY,
  baseUrl: BASE_URL,
  maxRetries: 2,
  timeout: 60_000,
  modelKwargs: { enable_thinking: false },
});

function section(title: string) {
  console.log(`\n${"=".repeat(16)} ${title} ${"=".repeat(16)}`);
}

function brief(content: unknown, limit = 110): string {
  const text = content == null ? "" : String(content);
  return text.replace(/\s+/g, " ").trim().slice(0, limit);
}

function exp(label: string, fn: () => Promise<void> | void) {
  console.log(`\n-- ${label} --`);
  try {
    return fn();
  } catch (e: any) {
    console.log(`  [失败] ${(e as Error)?.constructor?.name}: ${String(e).slice(0, 300)}`);
  }
}

function showChain(msgs: any[], limit = 80): void {
  msgs.forEach((m, i) => {
    const t: string = typeof m.getType === "function" ? m.getType() : (m.type ?? m.constructor?.name);
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

// store 类型收窄：运行时实际是 LangGraph BaseStore（含 get/put/search）
import type { BaseStore as LgBaseStore } from "@langchain/langgraph";
const lgStore = (runtime: { store: unknown }): LgBaseStore => runtime.store as LgBaseStore;

// ============================================================
section("1. 上下文工程是什么");
// ============================================================

const getWeatherTool = tool(({ city }: { city: string }) => `${city}：晴天，22°C`, {
  name: "get_weather",
  description: "查询一个城市的天气。",
  schema: z.object({ city: z.string().describe("城市名") }),
});

exp("1a. 组装视图：模型一次调用看到什么", async () => {
  const showContext = createMiddleware({
    name: "ShowContext",
    wrapModelCall: async (request, handler) => {
      const sysText = request.systemMessage?.content ?? "(无)";
      console.log(`  [组装视图] system prompt: ${brief(sysText, 90)}`);
      console.log(
        `  [组装视图] 消息 ${request.messages.length} 条: ${JSON.stringify(request.messages.map((m) => m.getType()))}`
      );
      const tools = request.tools ?? [];
      console.log(
        `  [组装视图] 工具 ${tools.length} 个: ${JSON.stringify(tools.map((t: any) => t.name ?? t.constructor?.name))}`
      );
      console.log(`  [组装视图] 模型: ${(request.model as any)?.model_name ?? (request.model as any)?.constructor?.name}`);
      return handler(request);
    },
  });

  const agent = createAgent({
    model,
    tools: [getWeatherTool],
    systemPrompt: "你是一个天气助手，回答保持简短。",
    middleware: [showContext],
  });
  const r: any = await agent.invoke({ messages: [{ role: "user", content: "北京天气怎么样？" }] });
  console.log("  最终回答:", brief(r.messages.at(-1)?.content));
});

exp("1b. 成本对照：上下文窗口是稀缺资源", async () => {
  const ref =
    "【参考资料】" +
    "该项目采用微服务架构，订单服务负责交易流程，库存服务负责货品管理，" +
    "用户服务负责账号体系，各服务之间通过消息队列通信。".repeat(30);
  console.log(`  （长提示词参考资料共 ${ref.length} 字）`);

  const agentShort = createAgent({ model, tools: [], systemPrompt: "你是一个简洁的助手。" });
  const r1: any = await agentShort.invoke({ messages: [{ role: "user", content: "请只回答数字：1+1 等于几？" }] });
  const u1 = r1.messages.at(-1)?.usage_metadata ?? {};
  console.log(
    `  短提示词（${"你是一个简洁的助手。".length} 字）: input_tokens = ${u1.input_tokens}, 总 tokens = ${u1.total_tokens}`
  );

  const agentLong = createAgent({ model, tools: [], systemPrompt: "你是一个简洁的助手。\n" + ref });
  const r2: any = await agentLong.invoke({ messages: [{ role: "user", content: "请只回答数字：1+1 等于几？" }] });
  const u2 = r2.messages.at(-1)?.usage_metadata ?? {};
  console.log(
    `  长提示词（共 ${ref.length + 9} 字）: input_tokens = ${u2.input_tokens}, 总 tokens = ${u2.total_tokens}`
  );
  const delta = (u2.input_tokens ?? 0) - (u1.input_tokens ?? 0);
  console.log(`  差额: 多携带 ${delta} tokens（每次调用都要重复付这笔账）`);
});

// ============================================================
section("2. 模型上下文");
// ============================================================

exp("2a. 动态提示词（按状态定制）：长对话 → 简洁模式", async () => {
  const stateAware = createMiddleware({
    name: "StateAwarePrompt",
    wrapModelCall: async (request, handler) => {
      // 起点：始终存在的 systemMessage（无显式 systemPrompt 时默认为 SystemMessage("")）
      let base = String(request.systemMessage?.content ?? "");
      if (!base) base = "你是一个助手。";
      // 按消息条数动态追加指令 —— 视角“按状态定制提示词”
      const extra = request.messages.length >= 5 ? "\n这是长对话，请格外简洁。" : "";
      const systemMessage = request.systemMessage.concat(extra);
      if (request.messages.length >= 5) {
        console.log("  [StateAware] 已追加“长对话简洁”指令");
      }
      return handler({ ...request, systemMessage });
    },
  });

  const probe = createMiddleware({
    name: "Probe",
    wrapModelCall: async (request, handler) => {
      console.log(`  [探针] 消息 ${request.messages.length} 条 → system: ${brief(String(request.systemMessage?.content), 70)}`);
      return handler(request);
    },
  });

  const agent = createAgent({ model, tools: [], middleware: [stateAware, probe] });

  console.log("  场景一（短对话，1 条消息）:");
  const r1: any = await agent.invoke({ messages: [{ role: "user", content: "用一句话说你好。" }] });
  console.log("  回答:", brief(r1.messages.at(-1)?.content, 80));

  console.log("  场景二（长对话，共 5 条消息）:");
  const history: any[] = [];
  for (let i = 0; i < 2; i++) {
    history.push({ role: "user", content: `第${i + 1}问：二加二等于几？` });
    history.push({ role: "assistant", content: "等于四。" });
  }
history.push({ role: "user", content: "第 3 问：三加三等于几？" });
  const r2: any = await agent.invoke({ messages: history });
  console.log("  回答:", brief(r2.messages.at(-1)?.content, 80));
});

exp("2b. 动态提示词（按运行时上下文定制）：admin vs viewer", async () => {
  const RoleCtx = z.object({ role: z.string() });
  type RoleCtxT = z.infer<typeof RoleCtx>;

const rolePrompt = createMiddleware({
    name: "RolePrompt",
    wrapModelCall: async (request, handler) => {
      const role = (request.runtime.context as any).role;
      const base = "你是一个数据管理助手。";
      const extra =
        role === "admin"
          ? "\n当前用户是管理员，拥有全部操作权限。"
          : "\n当前用户是只读访客，只能执行读取操作，不能修改数据。";
      // systemMessage 始终存在（默认 SystemMessage("")）；concat 追加动态部分
      const systemMessage = request.systemMessage
        ? request.systemMessage.concat(extra)
        : new HumanMessage(base + extra);
      return handler({ ...request, systemMessage: systemMessage as any });
    },
  });

  const probe = createMiddleware({
    name: "Probe2b",
    wrapModelCall: async (request, handler) => {
      const role = (request.runtime.context as any).role;
      console.log(`  [探针·${role}] system: ${brief(String(request.systemMessage?.content), 90)}`);
      return handler(request);
    },
  });

  const agent = createAgent({ model, tools: [], middleware: [rolePrompt, probe], contextSchema: RoleCtx });
  console.log("  admin 用户:");
  const r1: any = await agent.invoke(
    { messages: [{ role: "user", content: "你可以执行哪些操作？一句话回答。" }] },
    { context: { role: "admin" } }
  );
  console.log("  回答:", brief(r1.messages.at(-1)?.content, 90));
  console.log("  viewer 用户:");
  const r2: any = await agent.invoke(
    { messages: [{ role: "user", content: "你可以执行哪些操作？一句话回答。" }] },
    { context: { role: "viewer" } }
  );
  console.log("  回答:", brief(r2.messages.at(-1)?.content, 90));
});

exp("2c. 消息瞬时注入（transient）：模型看得到，状态里没有", async () => {
  const injectTransient = createMiddleware({
    name: "InjectTransient",
    wrapModelCall: async (request, handler) => {
      const msgs = [...request.messages, new HumanMessage("[档案注入] 项目代号是 LYRA-9。")];
      return handler({ ...request, messages: msgs });
    },
  });

  const agent = createAgent({ model, tools: [], middleware: [injectTransient], checkpointer: new MemorySaver() });
  const cfg = { configurable: { thread_id: "ctx-transient" } };
  const r: any = await agent.invoke({ messages: [{ role: "user", content: "项目代号是什么？请直接回答。" }] }, cfg);
  console.log("  回答:", brief(r.messages.at(-1)?.content, 90));
  console.log("  状态里的消息链:");
  showChain(r.messages);
  const persisted = r.messages.filter((m: any) => String(m.content ?? "").includes("[档案注入]"));
  console.log(`  状态中包含注入标记『[档案注入]』的消息数: ${persisted.length}（应为 0——瞬时修改不写状态）`);
});

exp("2d. 消息持久注入（Command）：跨轮可见", async () => {
  const persistNote = createMiddleware({
    name: "PersistNote",
    wrapModelCall: async (request, handler) => {
      const already = request.messages.some((m) => String(m.content ?? "").includes("LYRA-9"));
      if (already) {
        console.log("  [档案] 已在消息中，本次不再注入");
        return handler(request);
      }
      const msgs = [...request.messages, new HumanMessage("[档案] 项目代号是 LYRA-9。")];
      const response = await handler({ ...request, messages: msgs });
      console.log("  [档案] 本轮临时注入给模型 + 持久写入状态留给未来轮次");
      // TS：无 ExtendedModelResponse 导出 → 直接返回 Command 完成持久写入
      return new Command({
        update: { messages: [new HumanMessage("[档案] 项目代号是 LYRA-9。")] },
      });
    },
  });

  const agent = createAgent({ model, tools: [], middleware: [persistNote], checkpointer: new MemorySaver() });
  const cfg = { configurable: { thread_id: "ctx-persist" } };
  const r1: any = await agent.invoke({ messages: [{ role: "user", content: "项目代号是什么？请直接回答。" }] }, cfg);
  const lastAi: any = [...r1.messages].reverse().find((m: any) => m.getType?.() === "ai");
  console.log("  第一轮回答:", brief(lastAi?.content, 90));
  const persisted = r1.messages.filter((m: any) => String(m.content ?? "").includes("[档案]"));
  console.log(`  第一轮后状态中包含注入标记『[档案]』的消息数: ${persisted.length}（应为 1——持久写入）`);
  console.log("  状态链:");
  showChain(r1.messages);

  const r2: any = await agent.invoke({ messages: [{ role: "user", content: "再说一次：项目代号是什么？" }] }, cfg);
  const lastAi2: any = [...r2.messages].reverse().find((m: any) => m.getType?.() === "ai");
  console.log("  第二轮回答（无任何注入，直接读状态）:", brief(lastAi2?.content, 90));
  const persisted2 = r2.messages.filter((m: any) => String(m.content ?? "").includes("[档案]"));
  console.log(`  第二轮后『[档案]』消息数: ${persisted2.length}（不重复注入，仍为 1）`);
});

exp("2e. 工具：按运行时角色动态选择", async () => {
  const RoleCtxE = z.object({ role: z.string() });
  type RoleCtxET = z.infer<typeof RoleCtxE>;

  const readData = tool(() => "数据内容：42", {
    name: "read_data",
    description: "读取业务数据。",
    schema: z.object({}),
  });
  const writeData = tool(({ text }: { text: string }) => `已写入：${text}`, {
    name: "write_data",
    description: "写入业务数据。",
    schema: z.object({ text: z.string() }),
  });
  const deleteData = tool(() => "已删除全部业务数据", {
    name: "delete_data",
    description: "删除全部业务数据。",
    schema: z.object({}),
  });

const roleTools = createMiddleware({
    name: "RoleTools",
    wrapModelCall: async (request, handler) => {
      const role = (request.runtime.context as any).role;
      let tools: any[] = request.tools ?? [];
      if (role === "viewer") tools = tools.filter((t: any) => (t.name ?? "").startsWith("read_"));
      console.log(`  [过滤·${role}] 模型可见工具: ${JSON.stringify(tools.map((t: any) => t.name))}`);
      return handler({ ...request, tools });
    },
  });

  const agent = createAgent({
    model,
    tools: [readData, writeData, deleteData],
    middleware: [roleTools],
    contextSchema: RoleCtxE,
  });
  console.log("  viewer（只读）用户提问『请删除所有业务数据』:");
  const r1: any = await agent.invoke(
    { messages: [{ role: "user", content: "请删除所有业务数据。" }] },
    { context: { role: "viewer" } }
  );
  console.log("  回答:", brief(r1.messages.at(-1)?.content, 130));
  console.log("  admin 用户提问『请读取业务数据』:");
  const r2: any = await agent.invoke(
    { messages: [{ role: "user", content: "请读取业务数据。" }] },
    { context: { role: "admin" } }
  );
  console.log("  回答:", brief(r2.messages.at(-1)?.content, 130));
});

exp("2f. 动态响应格式（收窄候选）：Simple vs Detailed", async () => {
  const Simple = z
    .object({ answer: z.string() })
    .describe("简单回答")
    .meta({ title: "Simple" });
  const Detailed = z
    .object({ answer: z.string(), confidence: z.number().describe("置信度 0-1") })
    .describe("详细回答")
    .meta({ title: "Detailed" });

  const stateBasedFormat = createMiddleware({
    name: "StateBasedFormat",
    wrapModelCall: async (request, handler) => {
      const n = request.messages.length;
      const fmt = n <= 2 ? toolStrategy(Simple) : toolStrategy(Detailed);
      console.log(`  [格式] 消息 ${n} 条 → ${n <= 2 ? "简单格式 Simple" : "详细格式 Detailed"}`);
      return handler({ ...request, responseFormat: fmt });
    },
  });

  const agent = createAgent({
    model: modelNoThink,
    tools: [],
    middleware: [stateBasedFormat],
    responseFormat: toolStrategy([Simple, Detailed]),
  });
const r1: any = await agent.invoke({ messages: [{ role: "user", content: "说一声你好。" }] });
  console.log(`  第一轮 structuredResponse: ${JSON.stringify(r1.structuredResponse)}`);

  const history = [
    { role: "user", content: "你好。" },
    { role: "assistant", content: "你好！" },
    { role: "user", content: "今天星期几？" },
    { role: "assistant", content: "抱歉，我无法得知当前日期。" },
    { role: "user", content: "那简单介绍一下你自己，并给出你对回答的置信度。" },
  ];
const r2: any = await agent.invoke({ messages: history });
  console.log(`  第二轮 structuredResponse: ${JSON.stringify(r2.structuredResponse)}`);
});

exp("2g-A. 工具结果清理：自写瞬时截断（状态留全量）", async () => {
  const bigReport = tool(({ topic }: { topic: string }) => "【报告】" + "这是一条很长的报告内容，包含许多细节。".repeat(60), {
    name: "big_report",
    description: "获取主题报告全文。",
    schema: z.object({ topic: z.string() }),
  });

  const trimLongToolOutputs = createMiddleware({
    name: "TrimLongToolOutputs",
    wrapModelCall: async (request, handler) => {
      const newMsgs = request.messages.map((m) => {
        if (m.getType?.() === "tool" && String(m.content ?? "").length > 120) {
          return new ToolMessage({
            content: String(m.content).slice(0, 120) + "……（已截断）",
            tool_call_id: (m as any).tool_call_id,
          });
        }
        return m;
      });
      // 探针：模型侧 tool 消息长度
      for (const m of newMsgs) {
        if (m.getType?.() === "tool") console.log(`  [探针] 模型侧 tool 消息: len=${String(m.content).length}`);
      }
      return handler({ ...request, messages: newMsgs });
    },
  });

  const agent = createAgent({ model, tools: [bigReport], middleware: [trimLongToolOutputs] });
  const r: any = await agent.invoke({ messages: [{ role: "user", content: "请获取主题报告，然后只回我'已阅'两个字。" }] });
  console.log("  最终回答:", brief(r.messages.at(-1)?.content, 60));
  for (const m of r.messages) {
    if (m.getType?.() === "tool") console.log(`  状态侧 tool 消息: len=${String(m.content).length}（全量保留）`);
  }
});

exp("2g-B. 工具结果清理：内置 ContextEditingMiddleware（同样是瞬时清理）", async () => {
  const bigReportB = tool(({ topic }: { topic: string }) => "【报告】" + "这是一条很长的报告内容，包含许多细节。".repeat(60), {
    name: "big_report",
    description: "获取主题报告全文。",
    schema: z.object({ topic: z.string() }),
  });

  const toolLenProbe = createMiddleware({
    name: "ToolLenProbe",
    wrapModelCall: async (request, handler) => {
      for (const m of request.messages) {
        if (m.getType?.() === "tool") {
          const meta: any = (m as any).response_metadata ?? {};
          const cleared = meta.context_editing?.cleared;
          console.log(`  [探针] 模型侧 tool 消息: len=${String(m.content).length} cleared=${cleared} content[:46]=${JSON.stringify(String(m.content).slice(0, 46))}`);
        }
      }
      return handler(request);
    },
  });

  const agent = createAgent({
    model,
    tools: [bigReportB],
    middleware: [contextEditingMiddleware({ edits: [new ClearToolUsesEdit({ trigger: { tokens: 100 }, keep: { messages: 0 } })] }), toolLenProbe],
  });
  const r: any = await agent.invoke({ messages: [{ role: "user", content: "请获取主题报告，然后只回我'已阅'两个字。" }] });
  console.log("  最终回答:", brief(r.messages.at(-1)?.content, 60));
  for (const m of r.messages) {
    if (m.getType?.() === "tool") console.log(`  状态侧 tool 消息: len=${String(m.content).length}（内置件也是瞬时——状态保留原文）`);
  }
});

// ============================================================
section("3. 工具上下文（读写）");
// ============================================================

const UserCtx = z.object({ user_id: z.string() });
type UserCtxT = z.infer<typeof UserCtx>;

exp("3a. 工具读运行时上下文：用 user_id 完成查询", async () => {
  const getMyUserId = tool(
    async (_: unknown, runtime: ToolRuntime<unknown, UserCtxT>) =>
      `当前用户 ID 是 ${runtime.context.user_id}`,
    {
      name: "get_my_user_id",
      description: "查询当前用户的 ID。",
      schema: z.object({}),
    }
  );

const agent = createAgent({ model, tools: [getMyUserId], contextSchema: UserCtx });
  const r: any = await agent.invoke(
    { messages: [{ role: "user", content: "请查询我的用户 ID 并告诉我。" }] },
    { context: { user_id: "user_777" } }
  );
  console.log("  回答:", brief(r.messages.at(-1)?.content, 90));
  showChain(r.messages);
});

exp("3b. 工具读写状态：login 写（Command）→ check_auth 读", async () => {
  const login = tool(
    async ({ password }: { password: string }, runtime: ToolRuntime<unknown, UserCtxT>) => {
      const ok = password === "correct";
      // TS：写状态必须伴随对应的 ToolMessage（tool_call_id 取自 runtime.toolCall.id）
      return new Command({
        update: {
          messages: [new ToolMessage(`登录${ok ? "成功" : "失败"}`, runtime.toolCall?.id ?? "")],
          authenticated: ok,
        },
      });
    },
    {
      name: "login",
      description: "登录系统。密码为 correct 时登录成功。",
      schema: z.object({ password: z.string() }),
    }
  );

  const checkAuth = tool(
    async (_: unknown, runtime: ToolRuntime<unknown, UserCtxT>) => {
      const state = runtime.state as any;
      return `当前登录状态：authenticated = ${state.authenticated ?? false}`;
    },
    {
      name: "check_auth",
      description: "查询当前登录状态。",
      schema: z.object({}),
    }
  );

const AuthStateSchema = z.object({ authenticated: z.boolean().optional() });
  const agent = createAgent({
    model,
    tools: [login, checkAuth],
    stateSchema: AuthStateSchema,
  });
  const r: any = await agent.invoke({
    messages: [{ role: "user", content: "请先用密码 correct 登录，然后查询当前登录状态。" }],
  });
  console.log("  回答:", brief(r.messages.at(-1)?.content, 120));
  showChain(r.messages);
  console.log(`  最终状态里的 authenticated = ${r.authenticated}（工具通过 Command 写入）`);
});

exp("3c. 工具写 store：保存偏好 + 换会话读回（跨会话持久）", async () => {
const store = new InMemoryStore();

  const savePreference = tool(
    async ({ key, value }: { key: string; value: string }, runtime: ToolRuntime<unknown, UserCtxT>) => {
      const prefs: any = await lgStore(runtime).get(["preferences"], runtime.context.user_id);
      const data: Record<string, string> = { ...(prefs?.value ?? {}) };
      data[key] = value;
      await lgStore(runtime).put(["preferences"], runtime.context.user_id, data);
      return `已保存偏好：${key} = ${value}`;
    },
    {
      name: "save_preference",
      description: "把用户偏好保存到长期存储。",
      schema: z.object({ key: z.string(), value: z.string() }),
    }
  );

  const getPreference = tool(
    async ({ key }: { key: string }, runtime: ToolRuntime<unknown, UserCtxT>) => {
      const item: any = await lgStore(runtime).get(["preferences"], runtime.context.user_id);
      if (item && key in item.value) return `${key} = ${item.value[key]}`;
      return `未找到偏好 ${key}`;
    },
    {
      name: "get_preference",
      description: "从长期存储读取用户偏好。",
      schema: z.object({ key: z.string() }),
    }
  );

  const agent = createAgent({
    model,
    tools: [savePreference, getPreference],
    contextSchema: UserCtx,
    store,
  });
console.log("  会话 A（thread sess-A）：保存偏好");
  const cfgA: any = { configurable: { thread_id: "sess-A" }, context: { user_id: "user_777" } };
  const r1: any = await agent.invoke(
    { messages: [{ role: "user", content: "请保存我的偏好：语言 = 中文。" }] },
    cfgA
  );
  console.log("  回答:", brief(r1.messages.at(-1)?.content, 90));

  console.log("  会话 B（thread sess-B，全新对话）：读取偏好");
  const cfgB: any = { configurable: { thread_id: "sess-B" }, context: { user_id: "user_777" } };
  const r2: any = await agent.invoke(
    { messages: [{ role: "user", content: "请读取我的偏好：语言。" }] },
    cfgB
  );
  console.log("  回答:", brief(r2.messages.at(-1)?.content, 90));
const item: any = await store.get(["preferences"], "user_777");
  console.log(`  store 直查: ${JSON.stringify(item?.value)}`);
});

// ============================================================
section("4. 生命周期上下文");
// ============================================================

exp("4a. 摘要（持久更新状态）：原始引言被替换", async () => {
  const agent = createAgent({
    model,
    tools: [],
    middleware: [
      summarizationMiddleware({ model, trigger: { messages: 4 }, keep: { messages: 2 } }),
    ],
    checkpointer: new MemorySaver(),
  });
  const cfg = { configurable: { thread_id: "ctx-sum" } };
  const turns = [
    "我叫小明，是一名后端工程师，最近在系统学习 LangChain。",
    "请用一句话概括：短期记忆和长期记忆的区别是什么？",
    "我叫什么名字？做什么工作？请简短回答。",
  ];
  let r: any;
  for (let i = 0; i < turns.length; i++) {
    r = await agent.invoke({ messages: [{ role: "user", content: turns[i] }] }, cfg);
    console.log(`  第 ${i + 1} 轮后消息数: ${r.messages.length}`);
  }
  console.log("  最终状态消息链:");
  showChain(r.messages, 100);
  const hasSummary = r.messages.some((m: any) => String(m.content ?? "").toLowerCase().includes("summary"));
  const rawIntro = r.messages.some(
    (m: any) => String(m.content ?? "").trim() === "我叫小明，是一名后端工程师"
  );
  console.log(`  存在摘要消息: ${hasSummary}（应为 True——摘要持久写入状态）`);
  console.log(`  原始自我介绍消息仍在: ${rawIntro}（应为 False——原文已被摘要替换）`);
});

exp("4b. 自定义审计钩子：状态计数 + token 审计 → 沉淀到 store", async () => {
const AuditStateSchema = z.object({
    model_calls: z.number().optional(),
    total_input_tokens: z.number().optional(),
  });

  const AuditMiddleware = createMiddleware({
    name: "AuditMiddleware",
    stateSchema: AuditStateSchema,
    afterModel: async (state: any) => {
      const calls = (state.model_calls ?? 0) + 1;
      const last = state.messages?.at(-1);
      const usage: any = last?.usage_metadata ?? {};
      const total = (state.total_input_tokens ?? 0) + (usage.input_tokens ?? 0);
      return { model_calls: calls, total_input_tokens: total };
    },
    afterAgent: async (state: any, runtime: any) => {
      await lgStore(runtime).put(["audit"], "sess-9", {
        model_calls: state.model_calls,
        total_input_tokens: state.total_input_tokens,
      });
    },
  });

  const getWeatherB = tool(({ city }: { city: string }) => `${city}：晴天，22°C`, {
    name: "get_weather",
    description: "查询一个城市的天气。",
    schema: z.object({ city: z.string() }),
  });

  const storeB = new InMemoryStore();
  const agent = createAgent({
    model,
    tools: [getWeatherB],
    middleware: [AuditMiddleware],
    store: storeB,
  });
  const r: any = await agent.invoke({ messages: [{ role: "user", content: "查一下北京天气，然后简短汇报。" }] });
  console.log("  回答:", brief(r.messages.at(-1)?.content, 90));
  console.log(`  最终状态: model_calls = ${r.model_calls}, total_input_tokens = ${r.total_input_tokens}`);
  const item: any = await storeB.get(["audit"], "sess-9");
  console.log(`  store 中的审计记录: ${JSON.stringify(item?.value)}`);
});

console.log("\n（全部实验完成）");