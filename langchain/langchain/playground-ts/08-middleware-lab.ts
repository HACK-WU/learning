/**
 * 第 8 课 · Middleware 中间件实验（TypeScript 版，对应 playground/08-middleware-lab.py）
 *
 * 运行（在 playground-ts 目录内）：
 *
 *     npx tsx 08-middleware-lab.ts
 *
 * 设计 4 大板块（与 Python 侧脚本一一对应）：
 * 1. 机制：单中间件钩子全景（六个钩子的触发时刻与顺序）
 * 2. 内置：ModelCallLimit / ToolCallLimit / ToolRetry / ToolError / ModelFallback / PII / ToolSelector / TodoList
 * 3. 自定义：createMiddleware 工厂（计数 + 自定义 state）、jump 提前结束（canJumpTo / jumpTo）
 * 4. 组合：三中间件执行顺序（before 正序 / after 逆序 / wrap 嵌套）、顺序影响行为（工具选择器与观察者换位）
 *
 * 说明：脚本输出即讲义引用的实测证据，请勿修改后当作新结果引用。
 *       模型侧经本地 OpenAI 兼容 mock 端点回放固定剧本（与 Python 侧共用同一服务）。
 *       TS 侧与 Python 侧的 API 形态差异（本脚本实测确认）：
 *         - 装饰器式（@before_model）→ createMiddleware({ beforeModel }) 工厂函数（无装饰器）
 *         - 类式（AgentMiddleware 子类）→ createMiddleware 配置对象（钩子写在配置里）
 *         - 限额参数 runLimit / threadLimit / exitBehavior（驼峰）
 *         - 自定义 state：StateSchema 实例 + stateSchema 字段（Python 为 AgentState 子类）
 *         - 跳转声明：beforeModel: { canJumpTo: ["end"], hook } 对象形态（Python 为装饰器参数）
 *         - 中间件重名：构造期即抛 `Middleware X is defined multiple times`（Python 为运行期 AssertionError）
 *         - 工具选择器走 OpenAI 原生 response_format: json_schema（非虚拟工具，本脚本 mock 日志确认）
 *         - **默认工具错误处理相反**：TS 默认把工具异常转成 ToolMessage（附 "Please fix your mistakes."），
 *           Python 默认冒泡中断——ToolErrorMiddleware 在 TS 侧是"自定义文案"、Python 侧是"从崩到不崩"
 */
import * as z from "zod";
import dotenv from "dotenv";
import {
  tool,
  createAgent,
  createMiddleware,
  initChatModel,
  toolErrorMiddleware,
  toolRetryMiddleware,
  modelCallLimitMiddleware,
  toolCallLimitMiddleware,
  modelFallbackMiddleware,
  piiMiddleware,
  llmToolSelectorMiddleware,
  todoListMiddleware,
} from "langchain";

dotenv.config({ path: [".env", "../playground/.env"] });

const model = await initChatModel("qwen3.8-flash", {
  modelProvider: "openai",
  apiKey: process.env.BAILIAN_API_KEY,
  baseUrl: process.env.BAILIAN_BASE_URL,
  maxRetries: 0,
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

// 打印消息链（角色 + 摘要，工具调用单列）
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

// ---------------- 公共工具 ----------------

const calculator = tool(({ expression }: { expression: string }) => `${expression} = ${eval(expression)}`, {
  name: "calculator",
  description: "计算一个算术表达式，例如 '12*8'。",
  schema: z.object({ expression: z.string() }),
});

const getWeather = tool(({ city }: { city: string }) => `${city}：晴天，22°C`, {
  name: "get_weather",
  description: "查询一个城市的天气。",
  schema: z.object({ city: z.string() }),
});

const getTime = tool(({ city }: { city: string }) => `${city} 当前时间 14:30`, {
  name: "get_time",
  description: "查询一个城市的当前时间。",
  schema: z.object({ city: z.string() }),
});

// ============================================================
section("1. 机制：单中间件钩子全景");
// ============================================================

const hookTour = createMiddleware({
  name: "HookTourMiddleware",
  beforeAgent: () => {
    console.log("  【钩子】before_agent（每次调用一次）");
  },
  beforeModel: (state) => {
    console.log(`  【钩子】before_model（第 ${state.messages.length} 条消息已就位）`);
  },
  afterModel: () => {
    console.log("  【钩子】after_model（模型刚返回）");
  },
  afterAgent: () => {
    console.log("  【钩子】after_agent（agent 结束）");
  },
  wrapModelCall: async (request, handler) => {
    console.log("  【钩子】wrap_model_call 进入 →（调用内层/模型）");
    const resp = await handler(request);
    console.log("  【钩子】wrap_model_call 返回");
    return resp;
  },
  wrapToolCall: async (request, handler) => {
    const name = request.toolCall.name;
    console.log(`  【钩子】wrap_tool_call 进入 → 即将执行工具 ${name}`);
    const result = await handler(request);
    console.log(`  【钩子】wrap_tool_call 返回 ← 工具 ${name} 完成`);
    return result;
  },
});

const agentHook = createAgent({ model, tools: [calculator], middleware: [hookTour] });

console.log("\n-- 1a. 一次带工具的调用，钩子触发顺序 --");
{
  const r: any = await agentHook.invoke({ messages: [{ role: "user", content: "请用计算器算 6*7。" }] });
  console.log("  最终回答:", brief(r.messages.at(-1)?.content));
  console.log("  消息链:");
  showChain(r.messages);
}

console.log("\n-- 1b. 结构核验（无模型调用）：编译图节点与注册工具 --");
{
  const agentTodo = createAgent({ model, tools: [calculator], middleware: [todoListMiddleware()] });
  const g: any = await agentTodo.graph.getGraphAsync({});
  console.log("  图节点:", JSON.stringify(Object.keys(g.nodes ?? {})));
  console.log(
    "  todoListMiddleware 注册的工具:",
    JSON.stringify((todoListMiddleware() as any).tools?.map((t: any) => t.name))
  );
}

// ============================================================
section("2. 内置中间件");
// ============================================================

console.log("\n-- 2a. modelCallLimitMiddleware：runLimit=2，超额优雅收尾 --");
{
  const agentMcl = createAgent({
    model,
    tools: [getWeather, getTime],
    middleware: [modelCallLimitMiddleware({ runLimit: 2, exitBehavior: "end" })],
  });
  const r: any = await agentMcl.invoke({
    messages: [{ role: "user", content: "先查北京天气，再查北京当前时间，最后给一句出行建议。" }],
  });
  console.log("  最终回答:", brief(r.messages.at(-1)?.content));
  console.log("  消息链（注意最后一条）:");
  showChain(r.messages);
}

console.log("\n-- 2b. toolCallLimitMiddleware：calculator 限 1 次，超额拦下 --");
{
  const agentTcl = createAgent({
    model,
    tools: [calculator],
    middleware: [toolCallLimitMiddleware({ toolName: "calculator", runLimit: 1 })],
  });
  const r: any = await agentTcl.invoke({
    messages: [{ role: "user", content: "请连续用计算器算两次：先算 12*8，再算 15*7。" }],
  });
  console.log("  最终回答:", brief(r.messages.at(-1)?.content));
  console.log("  消息链（注意被拦下的第二次调用）:");
  showChain(r.messages);
}

console.log("\n-- 2c. toolRetryMiddleware：前两次失败、第三次成功 --");
let attempts = 0;
const flakyService = tool(
  ({ query }: { query: string }) => {
    attempts += 1;
    const n = attempts;
    console.log(`    （工具实际被执行：第 ${n} 次）`);
    if (n <= 2) throw new Error(`服务暂时不可用（第 ${n} 次尝试失败）`);
    return `查询成功：${query} 的结果是 42`;
  },
  { name: "flaky_service", description: "查询一个不稳定的外部服务。", schema: z.object({ query: z.string() }) }
);
{
  const agentRetry = createAgent({
    model,
    tools: [flakyService],
    middleware: [toolRetryMiddleware({ maxRetries: 3, initialDelayMs: 50, backoffFactor: 0, jitter: false })],
  });
  const r: any = await agentRetry.invoke({ messages: [{ role: "user", content: "请查询订单 A100 的结果。" }] });
  console.log("  最终回答:", brief(r.messages.at(-1)?.content));
  console.log("  消息链:");
  showChain(r.messages);
}

console.log("\n-- 2d. toolErrorMiddleware：统一错误文案交给模型（附 TS 默认兜底对照） --");
const strictDivide = tool(
  ({ a, b }: { a: number; b: number }) => {
    if (b === 0) throw new Error("除数不能为 0");
    return `${a} / ${b} = ${a / b}`;
  },
  {
    name: "strict_divide",
    description: "做除法，除数为 0 时抛异常。",
    schema: z.object({ a: z.number(), b: z.number() }),
  }
);
{
  console.log("  对照组（TS 默认：异常转 ToolMessage，不中断）：");
  const agentPlain = createAgent({ model, tools: [strictDivide] });
  const r0: any = await agentPlain.invoke({ messages: [{ role: "user", content: "请算 10 除以 0。" }] });
  const toolMsg0 = r0.messages.find((m: any) => m.type === "tool");
  console.log("    工具消息（默认文案）:", brief(toolMsg0?.content, 150));
  console.log("    最终回答:", brief(r0.messages.at(-1)?.content));

  console.log("  实验组（toolErrorMiddleware 自定义文案）：");
  const agentErr = createAgent({
    model,
    tools: [strictDivide],
    middleware: [
      toolErrorMiddleware({
        onError: (error: any, request) => {
          if (error instanceof Error) {
            return `\`${request.toolCall.name}\` 执行失败（${error.constructor.name}），请调整输入后重试。`;
          }
        },
      }),
    ],
  });
  const r: any = await agentErr.invoke({ messages: [{ role: "user", content: "请算 10 除以 0。" }] });
  console.log("  最终回答:", brief(r.messages.at(-1)?.content));
  console.log("  消息链:");
  showChain(r.messages);
}

console.log("\n-- 2e. modelFallbackMiddleware：主模型不可用，自动降级 --");
{
  const badModel = await initChatModel("qwen3.8-flash-nonexistent", {
    modelProvider: "openai",
    apiKey: process.env.BAILIAN_API_KEY,
    baseUrl: process.env.BAILIAN_BASE_URL,
    maxRetries: 0,
    timeout: 60_000,
    modelKwargs: { enable_thinking: false },
  });
  const agentFb = createAgent({ model: badModel, tools: [], middleware: [modelFallbackMiddleware(model)] });
  try {
    const r: any = await agentFb.invoke({ messages: [{ role: "user", content: "用一个词回答：你还好吗？" }] });
    console.log("  最终回答（来自降级模型）:", brief(r.messages.at(-1)?.content));
  } catch (e: any) {
    console.log(`  降级未生效：${e.constructor?.name}: ${String(e.message).slice(0, 150)}`);
  }
}

console.log("\n-- 2f. piiMiddleware：邮箱脱敏 + 卡号掩码 --");
{
  const agentPii = createAgent({
    model,
    tools: [],
    middleware: [
      piiMiddleware("email", { strategy: "redact", applyToInput: true }),
      piiMiddleware("credit_card", { strategy: "mask", applyToInput: true }),
    ],
  });
  const r: any = await agentPii.invoke({
    messages: [{ role: "user", content: "请原样复述这两个信息：邮箱 zhangsan@example.com，卡号 4111 1111 1111 1111。" }],
  });
  console.log("  最终回答:", brief(r.messages.at(-1)?.content, 160));
}

console.log("\n-- 2g. llmToolSelectorMiddleware：maxTools=2 过滤工具 --");
const translateText = tool(({ text }: { text: string }) => `[EN] ${text}`, {
  name: "translate_text",
  description: "把文本翻译成英文。",
  schema: z.object({ text: z.string() }),
});
const tellJoke = tool(() => "为什么程序员总是分不清万圣节和圣诞节？因为 Oct 31 == Dec 25。", {
  name: "tell_joke",
  description: "讲一个笑话。",
  schema: z.object({}),
});
const unitConvert = tool(({ value, unit }: { value: number; unit: string }) => `${value} ${unit} 已换算`, {
  name: "unit_convert",
  description: "换算单位。",
  schema: z.object({ value: z.number(), unit: z.string() }),
});
const bookFlight = tool(({ city }: { city: string }) => `已预订飞往 ${city} 的机票`, {
  name: "book_flight",
  description: "预订机票。",
  schema: z.object({ city: z.string() }),
});

const pool = [getWeather, translateText, tellJoke, unitConvert, bookFlight, getTime];

{
  const agentSel = createAgent({
    model,
    tools: pool,
    middleware: [llmToolSelectorMiddleware({ maxTools: 2 })],
  });
const r: any = await agentSel.invoke({ messages: [{ role: "user", content: "北京今天天气怎么样？" }] });
  console.log("  最终回答:", brief(r.messages.at(-1)?.content));
  console.log("  消息链（实际调用的工具）:");
  showChain(r.messages);
}

console.log("\n-- 2h. todoListMiddleware：两段观察（自主跳过 vs 明确要求闭环） --");
{
  const agentTodo = createAgent({ model, tools: [getWeather, getTime], middleware: [todoListMiddleware()] });
  console.log("  场景一（多步任务、未要求清单）：");
  const r1: any = await agentTodo.invoke({
    messages: [{ role: "user", content: "这是一个多步任务：第一步查北京天气，第二步查北京当前时间，第三步把两者汇总成一句出行建议。请按步骤执行。" }],
  });
  console.log("  最终回答:", brief(r1.messages.at(-1)?.content));
  console.log("  消息链（注意有无 write_todos 调用）:");
  showChain(r1.messages, 100);

  console.log("  场景二（明确要求先用待办清单）：");
  const r2: any = await agentTodo.invoke({
    messages: [{ role: "user", content: "这是一个多步任务：第一步查北京天气，第二步查北京当前时间，第三步把两者汇总成一句出行建议。请先用待办清单列出计划，再按步骤执行。" }],
  });
  console.log("  最终回答:", brief(r2.messages.at(-1)?.content));
  console.log("  消息链（注意 write_todos 调用）:");
  showChain(r2.messages, 100);
}

// ============================================================
section("3. 自定义中间件");
// ============================================================

console.log("\n-- 3a. createMiddleware 工厂：计数 + 自定义 state（modelCallCount） --");
{
  const counterMiddleware = createMiddleware({
    name: "CallCounterMiddleware",
    stateSchema: z.object({ modelCallCount: z.number().default(0) }),
    beforeModel: (state) => {
      console.log(`  [自定义] before_model：即将进行第 ${state.modelCallCount + 1} 次模型调用`);
    },
    afterModel: (state) => {
      const c = state.modelCallCount + 1;
      console.log(`  [自定义] after_model：模型调用计数 → ${c}`);
      return { modelCallCount: c };
    },
  });

  const agentCnt = createAgent({ model, tools: [calculator], middleware: [counterMiddleware] });
  const r: any = await agentCnt.invoke({ messages: [{ role: "user", content: "请用计算器算 8*9。" }] });
  console.log("  最终回答:", brief(r.messages.at(-1)?.content));
  console.log("  最终状态里的计数 modelCallCount =", r.modelCallCount);
}

console.log("\n-- 3b. jump 提前结束：内容守护（canJumpTo + jumpTo） --");
{
  const contentGuard = createMiddleware({
    name: "ContentGuard",
    beforeModel: {
      canJumpTo: ["end"],
      hook: (state) => {
        const last = state.messages.at(-1);
        const text = String(last?.content ?? "");
        if (text.includes("禁止话题")) {
          console.log("  [守护] 检测到敏感输入，跳过模型直接收尾");
          return {
            messages: [{ role: "ai" as const, content: "抱歉，这个话题我不能处理。" } as any],
            jumpTo: "end" as const,
          };
        }
        return;
      },
    },
  });

  const agentGuard = createAgent({ model, tools: [], middleware: [contentGuard] });

  console.log("  场景一（正常输入）：");
  const r1: any = await agentGuard.invoke({ messages: [{ role: "user", content: "用一句话说你好。" }] });
  console.log("  最终回答:", brief(r1.messages.at(-1)?.content));

  console.log("  场景二（触发守护）：");
  const r2: any = await agentGuard.invoke({ messages: [{ role: "user", content: "我们来聊禁止话题吧。" }] });
  console.log("  最终回答:", brief(r2.messages.at(-1)?.content));
  console.log("  消息数（应为 2：输入 + 兜底回复，无模型输出）:", r2.messages.length);
  showChain(r2.messages);
}

// ============================================================
section("4. 组合与执行顺序");
// ============================================================

const mkOrder = (tag: string) =>
  createMiddleware({
    name: `order-${tag}`,
    beforeAgent: () => {
      console.log(`  [${tag}] before_agent`);
    },
    beforeModel: () => {
      console.log(`  [${tag}] before_model`);
    },
    afterModel: () => {
      console.log(`  [${tag}] after_model`);
    },
    afterAgent: () => {
      console.log(`  [${tag}] after_agent`);
    },
    wrapModelCall: async (request, handler) => {
      console.log(`  [${tag}] wrap_model_call 进入`);
      const resp = await handler(request);
      console.log(`  [${tag}] wrap_model_call 返回`);
      return resp;
    },
    wrapToolCall: async (request, handler) => {
      console.log(`  [${tag}] wrap_tool_call 进入`);
      const result = await handler(request);
      console.log(`  [${tag}] wrap_tool_call 返回`);
      return result;
    },
  });

console.log("\n-- 4a. 三个中间件（M1, M2, M3）的钩子触发顺序 --");
{
  const agentOrder = createAgent({
    model,
    tools: [calculator],
    middleware: [mkOrder("M1"), mkOrder("M2"), mkOrder("M3")],
  });
  const r: any = await agentOrder.invoke({ messages: [{ role: "user", content: "请用计算器算 1234*5678。" }] });
  console.log("  最终回答:", brief(r.messages.at(-1)?.content));
}

console.log("\n-- 4b. 顺序影响行为：观察者与工具选择器换位 --");
const toolObserver = createMiddleware({
  name: "ToolObserver",
  wrapModelCall: async (request, handler) => {
    const names = (request.tools ?? []).map((t: any) => (typeof t === "string" ? t : t.name));
    console.log(`  [观察者] 模型可见工具（${names.length} 个）: ${JSON.stringify(names)}`);
    return handler(request);
  },
});

{
  console.log("  顺序 A：selector 在前（外层），观察者在后（内层）");
  const agentO1 = createAgent({
    model,
    tools: pool,
    middleware: [llmToolSelectorMiddleware({ maxTools: 2 }), toolObserver],
  });
const r1: any = await agentO1.invoke({ messages: [{ role: "user", content: "北京今天天气怎么样？" }] });
  console.log("  最终回答:", brief(r1.messages.at(-1)?.content));

  console.log("  顺序 B：观察者在前（外层），selector 在后（内层）");
  const agentO2 = createAgent({
    model,
    tools: pool,
    middleware: [toolObserver, llmToolSelectorMiddleware({ maxTools: 2 })],
  });
const r2: any = await agentO2.invoke({ messages: [{ role: "user", content: "北京今天天气怎么样？" }] });
  console.log("  最终回答:", brief(r2.messages.at(-1)?.content));
}

console.log("\n-- 4c. 同类中间件重名：构造期报错（对照 Python 运行期 AssertionError） --");
{
  try {
    createAgent({ model, tools: [], middleware: [mkOrder("A"), mkOrder("A")] });
    console.log("  （未报错——需要复核）");
  } catch (e: any) {
    console.log(`  构造报错: ${e.constructor?.name}: ${String(e.message).slice(0, 120)}`);
  }
}

console.log("\n（全部实验完成）");