/**
 * 第 4 课 · 补充实验：MCP 协议实测（裸链 / 适配器）与 headless 工具现状（TypeScript 版，对应 playground/04-mcp-lab.py）
 *
 * 运行（在 playground-ts 目录内）：
 *
 *     npx tsx 04-mcp-lab.ts
 *
 * 说明：
 * - A 部分只用 Node 内置 fetch 直连公共 MCP 服务器（docs.langchain.com/mcp），展示协议裸链，无需额外依赖。
 * - B 部分需要 @langchain/mcp-adapters（新版 MCPAdapter）。
 * - C 部分验证 TS 侧 headless 工具 API 现状。
 */
import dotenv from "dotenv";
import { MCPAdapter } from "@langchain/mcp-adapters";
import { createAgent, initChatModel, tool } from "langchain";

dotenv.config({ path: [".env", "../playground/.env"] });

const MCP_URL = "https://docs.langchain.com/mcp";
const HEADERS_BASE: Record<string, string> = {
  "Content-Type": "application/json",
  Accept: "application/json, text/event-stream",
};

function section(title: string) {
  console.log(`\n${"=".repeat(16)} ${title} ${"=".repeat(16)}`);
}

/** 兼容 JSON 与 SSE 两种响应体，抽出 JSON-RPC 对象。 */
async function parseBody(resp: Response): Promise<any> {
  const ct = resp.headers.get("content-type") ?? "";
  const text = (await resp.text()).trim();
  if (ct.includes("text/event-stream")) {
    const dataLines = text
      .split("\n")
      .filter((ln) => ln.startsWith("data:"))
      .map((ln) => ln.slice(5).trim());
    if (dataLines.length === 0) return null;
    return JSON.parse(dataLines[dataLines.length - 1]);
  }
  return text ? JSON.parse(text) : null;
}

async function mainRaw() {
  section("A. 裸链实测：手写 JSON-RPC 直连 MCP 服务器");

  let sid: string | null = null;

  const r1 = await fetch(MCP_URL, {
    method: "POST",
    headers: HEADERS_BASE,
    body: JSON.stringify({
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: {
        protocolVersion: "2025-06-18",
        capabilities: {},
        clientInfo: { name: "lesson04-raw", version: "0.1" },
      },
    }),
  });
  sid = r1.headers.get("mcp-session-id");
  console.log("1) initialize ->", r1.status, "| session:", (sid ?? "（无）").slice(0, 24));
  const b1 = await parseBody(r1);
  if (b1?.result) {
    console.log("   服务器:", JSON.stringify(b1.result.serverInfo ?? {}));
    console.log("   协议版本:", b1.result.protocolVersion);
  } else {
    console.log("   响应:", JSON.stringify(b1).slice(0, 300));
  }

  const headers = { ...HEADERS_BASE };
  if (sid) headers["Mcp-Session-Id"] = sid;

  await fetch(MCP_URL, {
    method: "POST",
    headers,
    body: JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }),
  });

  const r2 = await fetch(MCP_URL, {
    method: "POST",
    headers,
    body: JSON.stringify({ jsonrpc: "2.0", id: 2, method: "tools/list" }),
  });
  const b2 = await parseBody(r2);
  const tools = b2?.result?.tools ?? [];
  console.log(`\n2) tools/list -> ${tools.length} 个工具:`);
  for (const t of tools) {
    console.log(`   - ${t.name}: ${String(t.description ?? "").slice(0, 70)}`);
  }

  const r3 = await fetch(MCP_URL, {
    method: "POST",
    headers,
    body: JSON.stringify({
      jsonrpc: "2.0",
      id: 3,
      method: "tools/call",
      params: { name: "search_docs_by_lang_chain", arguments: { query: "how to create a tool" } },
    }),
  });
  const b3 = await parseBody(r3);
  if (b3?.result) {
    const content = b3.result.content ?? [];
    const text = content[0]?.text ?? "";
    console.log(`\n3) tools/call(search_docs_by_lang_chain) -> 返回 ${text.length} 字符，节选:`);
    console.log("   " + text.slice(0, 300).replace(/\n/g, " / "));
  } else {
    console.log("\n3) tools/call ->", JSON.stringify(b3).slice(0, 300));
  }
}

async function mainAdapter() {
  section("B. LangChain MCPAdapter 实测（@langchain/mcp-adapters 2.x）");

  const model = await initChatModel("qwen3.8-flash", {
    modelProvider: "openai",
    apiKey: process.env.BAILIAN_API_KEY,
    baseUrl: process.env.BAILIAN_BASE_URL,
    maxRetries: 2,
    timeout: 60_000,
  });

  const adapter = new MCPAdapter({ servers: { docs: { url: MCP_URL } } });
  try {
    const tools = await adapter.listTools();
    console.log(`适配器把服务器工具转成了 ${tools.length} 个 LangChain 工具:`);
    for (const t of tools) {
      console.log(`   - ${t.name}`);
    }

    // 注：MCP 工具名带服务器前缀（docs_...）；用其中一个工具走通"经 MCP 工具回答"的真实链路
    const agent = createAgent({ model, tools });
    const res: any = await agent.invoke({
      messages: [
        { role: "user", content: "用一句话说明：在 LangChain 里给工具写描述的最佳实践是什么？" },
      ],
    });
    for (const m of [...res.messages].reverse()) {
      if (m.type === "ai" && m.content) {
        console.log("agent（经 MCP 工具）回答:", String(m.content).slice(0, 200));
        break;
      }
    }
  } finally {
    await adapter.close();
  }
}

async function mainHeadless() {
  section("C. headless 工具：TS 侧当前版本支持现状");

  try {
    // 官方写法：schema-only 定义（无 fn），再 .implement() 绑定客户端实现
    const def: any = tool({
      name: "browser_zoom",
      description: "调整浏览器缩放比例；仅在客户端执行。",
      schema: undefined,
    } as any);
    console.log("tool({name, description}) 返回类型:", def?.constructor?.name);
    console.log("有 .implement 方法:", typeof def?.implement);
    const impl = def.implement(async (args: any) => `缩放已设置为 ${args?.level ?? "?"}`);
    console.log("implement() 返回类型:", impl?.constructor?.name, "| 有 execute:", typeof impl?.execute);
    const execOut = await impl.execute({ level: 150 });
    console.log("实现体执行结果:", JSON.stringify(execOut));
  } catch (e: any) {
    console.log("headless 定义报错:", e.constructor.name, "|", String(e.message).slice(0, 200));
  }
}

await mainRaw();
await mainAdapter();
await mainHeadless();