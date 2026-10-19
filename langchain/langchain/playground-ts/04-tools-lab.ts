/**
 * 第 4 课 · 工具实验（TypeScript 版，对应 playground/04-tools-lab.py）
 *
 * 运行（在 playground-ts 目录内）：
 *
 *     npx tsx 04-tools-lab.ts
 *
 * 说明：脚本输出即讲义引用的实测证据，请勿修改后当作新结果引用。
 */
import * as z from "zod";
import dotenv from "dotenv";
import {
  tool,
  createAgent,
  createMiddleware,
  initChatModel,
  ToolMessage,
  type ToolRuntime,
} from "langchain";
import { Command, InMemoryStore } from "@langchain/langgraph";

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

function dumpChain(res: any, limit = 90) {
  for (const m of res.messages) {
    const t = m.type ?? m.constructor?.name;
    if (t === "ai" && m.tool_calls?.length) {
      for (const tc of m.tool_calls) {
        console.log(`   [AI 请求] ${tc.name}(${JSON.stringify(tc.args)})`);
      }
    } else if (t === "tool") {
      console.log(`   [Tool 回执] ${String(m.content).slice(0, limit)}`);
    } else {
      console.log(`   [${t}] ${String(m.content).slice(0, limit)}`);
    }
  }
}

function lastAi(res: any): string {
  for (const m of [...res.messages].reverse()) {
    if (m.type === "ai" && m.content) return String(m.content);
  }
  return "（无 AI 文本）";
}

// ================= 1. 定义一个工具 =================
section("1a. tool() 基本用法：description 与 zod schema");

const searchDatabase = tool(
  ({ query, limit }) => `Found ${limit} results for '${query}'`,
  {
    name: "search_database",
    description: "Search the customer database for records matching the query.",
    schema: z.object({
      query: z.string().describe("Search terms to look for"),
      limit: z.number().default(10).describe("Maximum number of results to return"),
    }),
  }
);

console.log("name:", searchDatabase.name);
console.log("description:", JSON.stringify(searchDatabase.description));
console.log("schema:");
console.log(JSON.stringify(z.toJSONSchema(searchDatabase.schema as any), null, 2));

section("1b. describe 与 default：参数级描述、默认值");

const searchV2 = tool(({ query }: { query: string }) => `Found results for '${query}'`, {
  name: "search_v2",
  description: "Search the customer database for records matching the query.",
  schema: z.object({
    query: z.string().describe("Search terms to look for"),
    limit: z.number().default(10).describe("Maximum number of results to return"),
  }),
});
console.log(JSON.stringify(z.toJSONSchema(searchV2.schema as any), null, 2));

section("1c. 属性定制：自定义名字与描述");

const webSearch = tool(({ query }: { query: string }) => `Results for: ${query}`, {
  name: "web_search",
  description: "Search the web for information.",
  schema: z.object({ query: z.string() }),
});

const ALLOWED_CHARS = new Set("0123456789+-*/(). ".split(""));
const calc = tool(
  ({ expression }: { expression: string }) => {
    if ([...expression].some((c) => !ALLOWED_CHARS.has(c))) {
      return "仅支持数字与 +-*/() 运算";
    }
    return String(eval(expression));
  },
  {
    name: "calculator",
    description: "Performs arithmetic calculations. Use this for any math problems.",
    schema: z.object({ expression: z.string().describe("Mathematical expression") }),
  }
);

console.log("name:", webSearch.name);
console.log("name:", calc.name, "| description:", calc.description);

section("1d. 不写 description / 不写 schema 会怎样");

const noDesc = tool(({ x }: { x: string }) => x, {
  name: "no_desc",
  description: "",
  schema: z.object({ x: z.string() }),
} as any);
console.log("空 description:", JSON.stringify(noDesc.description));

const noDescAtAll = tool(({ x }: { x: string }) => x, {
  name: "no_desc2",
  schema: z.object({ x: z.string() }),
} as any);
console.log("完全不传 description: ", JSON.stringify(noDescAtAll.description), "（自动生成，不报错）");

try {
  const noSchema = tool((input: any) => JSON.stringify(input), { name: "no_schema", description: "x" } as any);
  console.log("无 schema: 工具创建成功");
  try {
    await noSchema.invoke({} as any);
    console.log("无 schema: invoke 未报错");
  } catch (e: any) {
    console.log("无 schema: invoke 报错:", e.constructor.name, "|", String(e.message).slice(0, 120));
  }
} catch (e: any) {
  console.log("无 schema: 创建报错:", e.constructor.name, "|", String(e.message).slice(0, 150));
}

section("1e. zod schema：复杂参数与校验规则");

const WeatherInput = z.object({
  location: z.string().describe("City name or coordinates"),
  units: z.enum(["celsius", "fahrenheit"]).default("celsius").describe("Temperature unit preference"),
  include_forecast: z.boolean().default(false).describe("Include 5-day forecast"),
});

const getWeather = tool(
  ({ location, units, include_forecast }) => {
    const temp = units === "celsius" ? 22 : 72;
    let result = `Current weather in ${location}: ${temp} degrees ${units[0].toUpperCase()}`;
    if (include_forecast) result += "\nNext 5 days: Sunny";
    return result;
  },
  {
    name: "get_weather",
    description: "Get current weather and optional forecast.",
    schema: WeatherInput,
  }
);

console.log(JSON.stringify(z.toJSONSchema(getWeather.schema as any), null, 2));

section("1f. runtime 独立成第二参数（天然不进 schema、对模型隐藏）");

const getMessageCount = tool(
  async (_input, config: ToolRuntime) => {
    const n = (config.state as any)?.messages?.length ?? "?";
    return `共 ${n} 条消息`;
  },
  { name: "get_message_count", description: "Get the number of messages in the conversation.", schema: z.object({}) }
);

const getUserPreference = tool(
  async ({ pref_name }, _config: ToolRuntime) => `偏好 ${pref_name} 的值为 xxx`,
  {
    name: "get_user_preference",
    description: "Get a user preference value.",
    schema: z.object({ pref_name: z.string().describe("preference name") }),
  }
);

console.log("schema 字段（模型看到的参数表，函数入参）:");
console.log("  ", JSON.stringify(Object.keys((getUserPreference.schema as any).shape ?? {})));
console.log("get_user_preference 的 schema（模型实际收到）:");
console.log(JSON.stringify(z.toJSONSchema(getUserPreference.schema as any), null, 1));
console.log("（对比：TS 侧 runtime/config 是第二参数，不在 schema 里，天然对模型隐藏）");

section("1g. 参数命名为 config / runtime（保留名对照）");

const hasConfigField = tool((input: any) => JSON.stringify(input), {
  name: "has_config_field",
  description: "测试 zod 字段名 config。",
  schema: z.object({ config: z.string() }),
});
try {
  const out = await hasConfigField.invoke({ config: "hello" } as any);
  console.log("zod 字段名 config: 调用返回:", JSON.stringify((out as any).content ?? out));
} catch (e: any) {
  console.log("zod 字段名 config: 报错:", e.constructor.name, "|", String(e.message).slice(0, 150));
}

// ================= 2. 参数校验 =================
section("2. 参数校验行为（直接 invoke）");

console.log("正常调用:", await getWeather.invoke({ location: "北京" } as any));

for (const [payload, tag] of [
  [{ location: "北京", units: "kelvin" }, "units 非法值"],
  [{}, "缺 location"],
  [{ location: "北京", extra: 1 }, "多余参数"],
  [{ location: 123 }, "类型不对"],
] as [any, string][]) {
  try {
    const out = await getWeather.invoke(payload);
    console.log(`[${tag}] 未报错，返回: ${String((out as any).content ?? out).slice(0, 80)}`);
  } catch (e: any) {
    console.log(`[${tag}] ${e.constructor.name}: ${String(e.message).slice(0, 170).replace(/\n/g, " / ")}`);
  }
}

// ================= 3. 绑定与选择 =================
section("3. bindTools 与工具选择（真实模型）");
const mw = model.bindTools([searchDatabase, calc]);
const r: any = await mw.invoke("帮我算 23*17 是多少");
console.log("问题: 帮我算 23*17 是多少");
console.log("tool_calls:", JSON.stringify(r.tool_calls?.map((tc: any) => ({ name: tc.name, args: tc.args, id: tc.id }))));

// ================= 4. 并行调用 + 手动闭环 =================
section("4a. 并行工具请求（一个提问、两个调用）");
const mw2 = model.bindTools([getWeather]);
const q = "北京和上海的天气分别怎么样？";
const r1: any = await mw2.invoke(q);
console.log("tool_calls 数量:", r1.tool_calls?.length ?? 0);
for (const tc of r1.tool_calls ?? []) {
  console.log(`  - ${tc.name} args=${JSON.stringify(tc.args)} id=${String(tc.id).slice(0, 20)}...`);
}

section("4b. 手动执行循环（tool.invoke(toolCall) 直接吐 ToolMessage）");
const msgs: any[] = [{ role: "user", content: q }, r1];
for (const tc of r1.tool_calls ?? []) {
  const tm: any = await getWeather.invoke(tc);
  console.log(
    `执行 ${tc.args.location} -> 返回类型: ${tm.constructor.name}, ` +
      `tool_call_id 匹配: ${tm.tool_call_id === tc.id}`
  );
  msgs.push(tm);
}

const final: any = await mw2.invoke(msgs);
console.log("最终答复:", final.content);

// ================= 5. 错误处理 =================
section("5a. 工具抛异常（直接调用）");

const queryStockPrice = tool(
  ({ stock_code }: { stock_code: string }) => {
    const prices: Record<string, string> = {
      "600519": "贵州茅台：1688.00 元",
      "000001": "平安银行：12.34 元",
    };
    if (!(stock_code in prices)) {
      throw new Error(`股票代码 ${stock_code} 未收录`);
    }
    return prices[stock_code];
  },
  {
    name: "query_stock_price",
    description: "查询 A 股股票的最新价格。股票代码必须是 6 位数字（如 600519）。",
    schema: z.object({ stock_code: z.string() }),
  }
);

try {
  await queryStockPrice.invoke({ stock_code: "300999" });
} catch (e: any) {
  console.log("直接调用:", e.constructor.name, "|", String(e.message).slice(0, 130));
}

section("5b-1. 默认行为：TS 侧异常自动转为 ToolMessage（与 Python 不同）");

const dataState: { dataset: string | null } = { dataset: null };

const loadDataset = tool(
  ({ name }: { name: string }) => {
    dataState.dataset = name;
    return `数据集 ${name} 已加载，共 1000 行。`;
  },
  {
    name: "load_dataset",
    description: "从磁盘加载指定名称的数据集文件（仅当数据集尚未加载时使用）。",
    schema: z.object({ name: z.string() }),
  }
);

const analyze = tool(
  () => {
    if (dataState.dataset === null) {
      throw new Error("分析失败：尚未加载数据集。先调用 load_dataset（可试用 name='demo'）再重试。");
    }
    return `数据集 ${dataState.dataset}：共 1000 行，平均分 87.5，无缺失值。`;
  },
  { name: "analyze", description: "报告当前数据集的整体统计。", schema: z.object({}) }
);

const agentDefault = createAgent({ model, tools: [loadDataset, analyze] });
try {
  const res: any = await agentDefault.invoke({
    messages: [{ role: "user", content: "帮我看看数据集的整体情况" }],
  });
  console.log("未崩溃？完整消息链:");
  dumpChain(res, 110);
} catch (e: any) {
  console.log("5b-1 默认行为：agent 直接崩溃 →", e.constructor.name, "|", String(e.message).slice(0, 300));
}

section("5b-2. 自定义错误文案：wrapToolCall 中间件");

const handleToolErrors = createMiddleware({
  name: "HandleToolErrors",
  wrapToolCall: async (request: any, handler: any) => {
    try {
      return await handler(request);
    } catch (error: any) {
      return new ToolMessage({
        content: `Tool error: Please check your input and try again. (${error})`,
        tool_call_id: request.toolCall.id,
      });
    }
  },
});

dataState.dataset = null; // 重置状态：从"未加载"开始，观察完整修正循环
const agentErr2 = createAgent({ model, tools: [loadDataset, analyze], middleware: [handleToolErrors] });
const res5b2: any = await agentErr2.invoke({
  messages: [{ role: "user", content: "帮我看看数据集的整体情况" }],
});
console.log("完整消息链（出错 → 修正 → 成功）:");
dumpChain(res5b2, 130);
console.log("最终答复:", lastAi(res5b2).slice(0, 150));

// ================= 6. ToolRuntime =================
section("6. ToolRuntime：上下文注入 / 状态读取 / 长期记忆");

const UserContext = z.object({ user_id: z.string(), user_name: z.string() });

const whoAmI = tool(
  async (_input, config: ToolRuntime<unknown, z.infer<typeof UserContext>>) => {
    const n = (config.state as any)?.messages?.length ?? "?";
    return `用户: ${config.context.user_name}（id=${config.context.user_id}）｜对话 ${n} 条消息｜tool_call_id=${config.toolCallId}`;
  },
  { name: "who_am_i", description: "获取当前用户的信息。", schema: z.object({}) }
);

const saveColor = tool(
  async ({ color }, config: ToolRuntime<unknown, z.infer<typeof UserContext>>) => {
    await (config.store as any).put(["prefs"], config.context.user_id, { favorite_color: color });
    return `已保存：${color}`;
  },
  {
    name: "save_color",
    description: "保存用户喜欢的颜色到长期记忆。",
    schema: z.object({ color: z.string() }),
  }
);

const readColor = tool(
  async (_input, config: ToolRuntime<unknown, z.infer<typeof UserContext>>) => {
    const item: any = await (config.store as any).get(["prefs"], config.context.user_id);
    if (item == null) return "长期记忆中没有记录";
    return `你喜欢的颜色是：${item.value.favorite_color}`;
  },
  {
    name: "read_color",
    description: "读取用户喜欢的颜色（从长期记忆）。",
    schema: z.object({}),
  }
);

const store = new InMemoryStore();
const agentRt = createAgent({
  model,
  tools: [whoAmI, saveColor, readColor],
  contextSchema: UserContext,
  store,
});

const ctx = { user_id: "user123", user_name: "小明" };

const res1: any = await agentRt.invoke({ messages: [{ role: "user", content: "我是谁？" }] }, { context: ctx });
console.log("6a. 问『我是谁』→", lastAi(res1).slice(0, 160));

const res2: any = await agentRt.invoke(
  { messages: [{ role: "user", content: "请记住：我喜欢的颜色是蓝色" }] },
  { context: ctx }
);
console.log("6b. 保存颜色 →", lastAi(res2).slice(0, 120));

const res3: any = await agentRt.invoke(
  { messages: [{ role: "user", content: "我喜欢的颜色是什么？" }] },
  { context: ctx }
);
console.log("6c. 新会话读取 →", lastAi(res3).slice(0, 120));

console.log("6d. 从外部直查存储桶:");
const items = await store.search(["prefs"]);
for (const item of items) {
  console.log("   ", JSON.stringify(item));
}

// ================= 7. 动态工具选择 =================
section("7. 动态工具选择：按角色给不同的工具集");

const dataTableState = { deleted: false };

const readData = tool(
  ({ table }: { table: string }) =>
    dataTableState.deleted ? `（${table} 表数据：0 行，已清空）` : `（${table} 表数据：128 行）`,
  { name: "read_data", description: "读取数据表内容。", schema: z.object({ table: z.string() }) }
);

const writeData = tool(({ table }: { table: string; value: string }) => `（已写入 ${table}）`, {
  name: "write_data",
  description: "写入数据表。",
  schema: z.object({ table: z.string(), value: z.string() }),
});

const deleteData = tool(
  ({ table }: { table: string }) => {
    dataTableState.deleted = true;
    return { deleted: true, table, rows: 128 };
  },
  { name: "delete_data", description: "删除数据表的全部数据（高危操作）。", schema: z.object({ table: z.string() }) }
);

const viewerAgent = createAgent({ model, tools: [readData] });
const adminAgent = createAgent({ model, tools: [readData, writeData, deleteData] });

const q7 = "请删除 orders 数据表里的全部数据";

const resV: any = await viewerAgent.invoke({ messages: [{ role: "user", content: q7 }] });
console.log("7a. viewer（只给 read_data）→", lastAi(resV).slice(0, 160));

const resA: any = await adminAgent.invoke({ messages: [{ role: "user", content: q7 }] });
console.log("7b. admin（工具集含 delete_data）:");
dumpChain(resA, 110);

console.log("7c. 用户确认后（携带历史继续）：");
const resA2: any = await adminAgent.invoke({
  messages: [
    ...resA.messages,
    { role: "user", content: "我已确认，这是测试环境，允许执行删除，请直接调用工具执行。" },
  ],
});
dumpChain({ messages: resA2.messages.slice(resA.messages.length) }, 110);

// ================= 8. Command：写入 agent 状态 =================
section("8. 工具更新 agent 状态（Command 返回值）");

const CustomState = z.object({ user_name: z.string().default("") });

const setUserName = tool(
  async ({ new_name }, config: ToolRuntime<any, any>) => {
    return new Command({
      update: {
        user_name: new_name,
        messages: [
          new ToolMessage({
            content: `用户名已设置为 ${new_name}。`,
            tool_call_id: config.toolCallId,
          }),
        ],
      },
    });
  },
  {
    name: "set_user_name",
    description: "Set the user's name in the conversation state.",
    schema: z.object({ new_name: z.string() }),
  }
);

const agentState = createAgent({ model, tools: [setUserName], stateSchema: CustomState });

const res8: any = await agentState.invoke({
  messages: [{ role: "user", content: "请把我的用户名设置为小明" }],
});
console.log("最终状态里的 user_name:", res8.user_name);
dumpChain(res8, 100);