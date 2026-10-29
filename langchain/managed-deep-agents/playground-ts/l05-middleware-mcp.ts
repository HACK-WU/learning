/**
 * 课 5 · 中间件、MCP 与检索（TypeScript 侧）
 *
 * 对应课文：stages/2-能力声明/lessons/05-中间件MCP与检索.md
 *
 * 三个知识点：
 *   ① 中间件：wrapToolCall 的洋葱序，与 Python 侧对称
 *   ② MCP：定义期只声明、连接发生在图构建时
 *   ③ 检索：托管内置，本地拿不到（本课只做"声明长什么样"的实测）
 *
 * 本课不联网：所有实测都在"定义对象形状"这一层，不真的连 MCP 服务端。
 */

import { defineDeepAgent, defineMcp, connections } from "managed-deepagents";
import { createMiddleware } from "langchain";
import { section, step, show, showConfigKeys, attempt } from "./_shared.ts";

// ── 实验 1：中间件的声明形状 ───────────────────────────────────
section("实验 1", "一个最小中间件");

export const logToolCalls = createMiddleware({
  name: "LogToolCalls",
  wrapToolCall: async (request, handler) => {
    console.log(`  [中间件] Calling tool: ${request.toolCall.name}`);
    const result = await handler(request);
    console.log(`  [中间件] Finished tool: ${request.toolCall.name}`);
    return result;
  },
});

show("middleware 类型", typeof logToolCalls);
show("middleware.name", logToolCalls.name);
show("keys", Object.keys(logToolCalls));

console.log(`
  中间件是"包在工具调用外面的一层"，所以叫洋葱模型：
    请求进来 → 你的前半段 → handler(request) → 你的后半段 → 返回模型

  关键在 handler(request)：调用它才是"往下传"。
  不调用直接 return，就是拦截（工具根本不会执行）。
  这个差别是审计和权限两件事的分界线。
`);

// ── 实验 2：挂上中间件后的 config ─────────────────────────────
section("实验 2", "中间件进了 config 的 middleware 键");

const withMw = defineDeepAgent({
  name: "support-agent",
  model: "openai:gpt-5.5",
  middleware: [logToolCalls],
});
showConfigKeys(withMw.config, "挂了中间件的 keys");
show("middleware 数组长度", ((withMw.config as Record<string, unknown>).middleware as unknown[]).length);

console.log(`
  注意：只有一个中间件，config.middleware 长度就是 1。
  内置的那一摞（todos / filesystem / summarization / subagents）不在 config 里——
  它们由 createDeepAgent 在前面自动 prepend，你在 config 里看到的只有自己写的。
  排查"中间件执行顺序"时这一点很关键：你的中间件永远在内置之后。
`);

// ── 实验 3：MCP 声明 ──────────────────────────────────────────
section("实验 3", "MCP：定义期只声明形状，不连接");

const mcpSimple = defineMcp({
  servers: {
    langchainDocs: {
      transport: "http",
      url: "https://docs.langchain.com/mcp",
    },
  },
});

show("mcp.kind", (mcpSimple as unknown as { kind: string }).kind);
show("servers 键", Object.keys((mcpSimple as unknown as { servers: object }).servers));
show("全量", mcpSimple);

console.log(`
  跑通这一行不需要网络：defineMcp 只是把声明装进一个带 kind 的对象。
  真正的连接发生在"图构建时"（managed runtime 构造 agent-graph 那一刻），
  所以「本地能 build 成功」和「部署后 MCP 能用」是两件事。
`);

step("字段名有个坑：type 已改名为 transport");
console.log(`
  @langchain/mcp-adapters 里这个字段历史上叫 type，
  MDA 的 RemoteMcpServerConfig 把它换成 transport，并把 type 标成 never。
  写 type: "http" 在 TS 类型层就报错，不会到运行时才炸。
`);

attempt("用旧字段名 type", () =>
  defineMcp({
    servers: {
      docs: { type: "http", url: "https://docs.langchain.com/mcp" },
    },
  } as never),
);

// ── 实验 4：includeTools / excludeTools / connection ──────────
section("实验 4", "工具筛选与凭据绑定");

const mcpFiltered = defineMcp({
  servers: {
    docs: {
      transport: "http",
      url: "https://docs.langchain.com/mcp",
      includeTools: ["search_docs_by_lang_chain"],
    },
    notion: {
      transport: "http",
      url: "https://mcp.notion.com/mcp",
      connection: connections.get("engineering-notion", { type: "user" }),
      excludeTools: ["delete_page"],
    },
  },
  throwOnLoadError: false,
});

show("servers", Object.keys((mcpFiltered as unknown as { servers: object }).servers));

// 只打形状，不打全量：connection 对象里带着 accessor（含整个 process.env），
// 原样打印会把环境变量和凭据刷到终端上。
const docsCfg = (mcpFiltered as any).servers.docs as Record<string, unknown>;
const notionCfg = (mcpFiltered as any).servers.notion as Record<string, unknown>;
show("docs.transport", docsCfg.transport);
show("docs.includeTools", docsCfg.includeTools);
show("notion.excludeTools", notionCfg.excludeTools);
show("notion.connection.slug", (notionCfg.connection as any)?.slug);
show("notion.connection.owner", (notionCfg.connection as any)?.owner);
show("throwOnLoadError", (mcpFiltered as unknown as { throwOnLoadError: boolean }).throwOnLoadError);

console.log(`
  三种筛选/绑定手段：
    includeTools   白名单：只暴露这几个
    excludeTools   黑名单：去掉这几个（适合"先接全套再收窄"）
    connection     凭据：type: "user" = 每个调用方各自授权，
                          type: "agent" = agent 所有者配一次、全员共用

  throwOnLoadError: false 的含义：某个 MCP 服务端连不上时，
  该服务端的工具静默缺席，agent 照常起来。
  这对可用性是好事，对排查是坏事——所以只在"非核心服务端"上开。
`);

// ── 实验 5：把 MCP 挂进 agent ────────────────────────────────
section("实验 5", "MCP 通过 mcp 键挂进 agent（只有工厂入口能用）");

console.log(`
  静态入口：tools/mcp.ts 里 export const mcp = defineMcp({...})，自动发现
  工厂入口：defineDeepAgent({ mcp: [mcpSimple] }) 显式选

  两条路的差别同 skills：静态入口靠目录约定，工厂入口靠显式传参。
`);

attempt("静态入口直接传 mcp 字段", () =>
  defineDeepAgent({
    name: "probe",
    model: "openai:gpt-5.5",
    mcp: [mcpSimple],
  } as never),
);

// ── 实验 6：内置检索 ─────────────────────────────────────────
section("实验 6", "内置检索：本课不做实测");

console.log(`
  托管版自带检索能力，但它要求 Plus / Startup 套餐，
  且索引进度与召回质量都要在真实部署上才看得出来——
  本地只有定义对象，没有索引可查。

  所以本课对检索只给"它在哪、什么时候生效"，不给"效果如何"。
  这是本课程里少数几处明确标注 ⚠️ 未实测 的地方。
`);

section("完成", "课 5 实测结束");
