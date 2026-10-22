/**
 * 课 4 · 工具与虚拟文件系统（TypeScript 版）
 *
 * 对应课文知识点 1-3。全程离线构造，不发请求、不需要 key：
 *   1) 三类工具来源混用（纯加法）
 *   2) 撞名行为（TS 与 Python 在这里相反）
 *   3) 构造期白名单与 read_file 强制
 *   4) 静态表 8 项 vs 请求期按后端能力过滤
 *   5) FilesystemBackend 的覆盖 / 原子编辑 / 字面 grep / glob 宽度
 *   6) read_file 分页与多模态
 *
 * 运行：npm run l04
 */

import {
  createDeepAgent,
  createFilesystemMiddleware,
  FilesystemBackend,
  LocalShellBackend,
  StateBackend,
} from "deepagents";
import { tool } from "langchain";
import { z } from "zod";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createRequire } from "node:module";
import { section } from "./_shared.js";

const require = createRequire(import.meta.url);

interface AgentLike {
  options: {
    middleware?: readonly unknown[];
    tools?: readonly unknown[];
  };
}

interface MiddlewareLike {
  name?: string;
  tools?: unknown;
  wrapModelCall?: unknown;
}

/** 从中间件里汇总内置工具名（TS 侧没有 nodes[...].bound 这种结构）。 */
const builtinTools = (mwList: readonly unknown[]): string[] => {
  const out: string[] = [];
  for (const mw of mwList as MiddlewareLike[]) {
    const t = mw.tools;
    if (!t) continue;
    const arr = typeof t === "function" ? (t as () => unknown[])() : (t as unknown[]);
    for (const x of arr ?? []) {
      const n = (x as { name?: string }).name;
      if (n) out.push(n);
    }
  }
  return [...new Set(out)].sort();
};

const toolNames = (a: AgentLike): string[] =>
  (a.options.tools ?? []).map((t) => (t as { name?: string }).name ?? "<anon>");

/** 请求期真实可见的工具（拦 wrapModelCall，不发网络请求）。 */
const requestTimeTools = async (mw: MiddlewareLike): Promise<string[]> => {
  const tools = (mw.tools as Array<{ name: string; description?: string }>) ?? [];
  // 必须传真实工具对象：TS 侧 delete 的过滤按对象身份比较（t !== builtInDeleteTool），
  // 一旦把工具重建成普通对象，身份判定就会失效、结果偏乐观。
  const req = { tools };
  const box: { seen?: Array<{ name: string }> } = {};
  const handler = async (r: unknown) => {
    box.seen = (r as { tools?: Array<{ name: string }> }).tools;
    return { content: "ok" };
  };
  const call = mw.wrapModelCall as (
    req: unknown,
    handler: (r: unknown) => Promise<unknown>,
  ) => Promise<unknown>;
  await call(req, handler);
  return (box.seen ?? []).map((t) => t.name).sort();
};

const mwToolNames = (mw: MiddlewareLike): string[] =>
  ((mw.tools as Array<{ name: string }>) ?? []).map((t) => t.name).sort();

async function main() {
  section("0. 版本");
  console.log("deepagents:", require("deepagents/package.json").version);

  // ---------------------------------------------------------------- 1
  section("1) 三类来源混用 → 纯加法");
  const plain = tool(async ({ city }: { city: string }) => city, {
    name: "plain_fn",
    description: "普通函数包成 tool()",
    schema: z.object({ city: z.string() }),
  });
  const decorated = tool(async ({ x }: { x: number }) => x * 2, {
    name: "decorated_tool",
    description: "官方 tool() 写法",
    schema: z.object({ x: z.number() }),
  });
  const objectTool = tool(async ({ q }: { q: string }) => q.toUpperCase(), {
    name: "object_tool",
    description: "以配置对象声明的工具",
    schema: z.object({ q: z.string() }),
  });

  const base = await createDeepAgent({ model: "openai:gpt-4o-mini", tools: [] });
  const mixed = await createDeepAgent({
    model: "openai:gpt-4o-mini",
    tools: [plain, decorated, objectTool],
  });

  const baseBuiltin = builtinTools(base.options.middleware ?? []);
  const mixedBuiltin = builtinTools(mixed.options.middleware ?? []);
  console.log("base  内置:", baseBuiltin.length, "| 用户:", toolNames(base).length);
  console.log("  ", baseBuiltin.join(", "));
  console.log("mixed 内置:", mixedBuiltin.length, "| 用户:", toolNames(mixed).sort().join(", "));
  console.log(
    "合计:",
    baseBuiltin.length + toolNames(base).length,
    "→",
    mixedBuiltin.length + toolNames(mixed).length,
  );
  console.log("内置一个没被顶掉:", JSON.stringify(baseBuiltin) === JSON.stringify(mixedBuiltin));

  // ---------------------------------------------------------------- 2
  section("2) 撞名 → TS 直接抛错（Python 是静默覆盖）");
  const hijack = tool(async ({ file_path }: { file_path: string }) => `HIJACK:${file_path}`, {
    name: "read_file",
    description: "我顶掉了内置的 read_file",
    schema: z.object({ file_path: z.string() }),
  });
  try {
    await createDeepAgent({ model: "openai:gpt-4o-mini", tools: [hijack] });
    console.log("未抛错（与预期不符）");
  } catch (e) {
    const err = e as { constructor: { name: string }; code?: string; message: string };
    console.log("抛错:", err.constructor.name, "| code:", err.code ?? "(无)");
    console.log("消息:", err.message);
  }
  for (const n of ["task", "ls", "execute", "write_todos"]) {
    try {
      await createDeepAgent({
        model: "openai:gpt-4o-mini",
        tools: [tool(async () => "x", { name: n, description: "d", schema: z.object({}) })],
      });
      console.log(`  撞 ${n.padEnd(12)} -> ok`);
    } catch (e) {
      console.log(`  撞 ${n.padEnd(12)} -> ${(e as { code?: string }).code}`);
    }
  }

  const mkDup = (d: string) =>
    tool(async ({ x }: { x: string }) => d, {
      name: "dup",
      description: d,
      schema: z.object({ x: z.string() }),
    });
  const dupCases: Array<[string, Array<ReturnType<typeof mkDup>>]> = [
    ["[A,B]", [mkDup("A 版"), mkDup("B 版")]],
    ["[B,A]", [mkDup("B 版"), mkDup("A 版")]],
  ];
  for (const [tag, arr] of dupCases) {
    try {
      const ag = await createDeepAgent({ model: "openai:gpt-4o-mini", tools: arr });
      const descriptors = (ag.options.tools ?? []).map((t) => t.description ?? "");
      console.log(
        `  两个自定义同名 ${tag} -> ok | 条数: ${descriptors.length} | 描述: ${descriptors.join(" / ")}`,
      );
    } catch (e) {
      console.log(`  两个自定义同名 ${tag} -> 抛错: ${(e as Error).message.slice(0, 60)}`);
    }
  }

  // ---------------------------------------------------------------- 3
  section("3) 构造期白名单 + read_file 强制");
  const narrowed = createFilesystemMiddleware({ tools: ["ls", "read_file", "glob", "grep"] });
  console.log("裁剪后:", mwToolNames(narrowed).join(", "), "| 条数:", mwToolNames(narrowed).length);
  try {
    createFilesystemMiddleware({ tools: ["ls", "grep"] });
    console.log("漏 read_file: 未抛错（与预期不符）");
  } catch (e) {
    console.log("漏 read_file ->", (e as Error).message);
  }

  // ---------------------------------------------------------------- 4
  section("4) 静态表 8 项 vs 请求期按后端能力过滤");
  class Bare {
    async ls(_p: string) {
      return { files: [] };
    }
    async read(_f: string, _o?: number, _l?: number) {
      return { content: "" };
    }
    async write(p: string, _c: string) {
      return { path: p };
    }
    async edit(p: string, _a: string, _b: string, _o?: boolean) {
      return { path: p, occurrences: 1 };
    }
    async glob(_pat: string, _p?: string) {
      return { files: [] };
    }
    async grep(_pat: string, _p?: string, _g?: string) {
      return { matches: [] };
    }
    async uploadFiles(_f: unknown) {
      return [];
    }
    async downloadFiles(_p: string[]) {
      return [];
    }
  }

  const bareNoDelete = new Bare();
  const bareWithDelete = new Bare() as Bare & { delete: (p: string) => Promise<{ path: string }> };
  bareWithDelete.delete = async (p: string) => ({ path: p });

  const cases: Array<[string, unknown]> = [
    ["StateBackend      ", new StateBackend()],
    ["Bare(无 delete)   ", bareNoDelete],
    ["Bare(挂 delete)   ", bareWithDelete],
    ["LocalShell(沙箱)  ", new LocalShellBackend({ rootDir: "/tmp" })],
  ];
  for (const [tag, backend] of cases) {
    const mw = createFilesystemMiddleware({ backend: backend as never });
    const statics = mwToolNames(mw);
    const visible = await requestTimeTools(mw);
    const hidden = statics.filter((n) => !visible.includes(n));
    console.log(
      `${tag} 静态 ${statics.length} | 请求期 ${visible.length} | 被摘: ${hidden.length ? hidden.join(",") : "(无)"}`,
    );
  }

  // ---------------------------------------------------------------- 5
  section("5) FilesystemBackend：覆盖 / 原子编辑 / 字面 grep / glob");
  const root = mkdtempSync(join(tmpdir(), "da-l04-"));
  const be = new FilesystemBackend({ rootDir: root, virtualMode: true });

  console.log("write OLD:", JSON.stringify(await be.write("/a/b/f.txt", "OLD")));
  console.log("write NEW:", JSON.stringify(await be.write("/a/b/f.txt", "NEW")));
  const back = await be.read("/a/b/f.txt");
  console.log("读回:", back.content, "| a/b 目录项:", (await be.ls("/a/b")).files?.length ?? 0);

  console.log("edit 命中:", JSON.stringify(await be.edit("/a/b/f.txt", "NEW", "NEWER")));
  console.log("edit 未命中:", JSON.stringify(await be.edit("/a/b/f.txt", "不存在的内容", "x")));
  await be.write("/m.txt", "aa aa aa");
  console.log("replaceAll:", JSON.stringify(await be.edit("/m.txt", "aa", "bb", true)));

  await be.write("/p.txt", "alpha\nbeta\ngamma\ndelta");
  console.log("grep 正则 a.*a:", JSON.stringify(await be.grep("a.*a")));
  console.log("grep 字面 alpha:", JSON.stringify(await be.grep("alpha")));
  console.log("glob 无匹配:", JSON.stringify(await be.glob("*.nothing")));
  console.log("ls 不存在目录:", JSON.stringify(await be.ls("/nope")));

  mkdirSync(join(root, ".github/workflows"), { recursive: true });
  mkdirSync(join(root, "src"), { recursive: true });
  writeFileSync(join(root, ".github/workflows/ci.yml"), "x");
  writeFileSync(join(root, "src/a.yml"), "x");
  writeFileSync(join(root, "top.yml"), "x");
  writeFileSync(join(root, ".env"), "x");
  for (const p of ["*.yml", "**/*.yml", ".env", ".github/**/*.yml"]) {
    const r = await be.glob(p);
    console.log(`  glob ${p.padEnd(18)} -> ${JSON.stringify((r.files ?? []).map((f) => f.path))}`);
  }

  // ---------------------------------------------------------------- 6
  section("6) read_file：分页与多模态");
  for (const [o, l] of [
    [0, 2],
    [1, 2],
    [3, 2],
  ]) {
    const r = await be.read("/p.txt", o, l);
    console.log(
      `offset=${o} limit=${l} -> content=${JSON.stringify(r.content)} | totalLines=${r.totalLines} | start=${r.startLine} | end=${r.endLine} | next=${r.nextOffset}`,
    );
  }

  const b64 =
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==";
  writeFileSync(join(root, "p.png"), Buffer.from(b64, "base64"));
  const raw = await be.read("/p.png");
  console.log("后端读 png: content=", raw.content?.constructor.name, "| mimeType:", raw.mimeType);

  const mw = createFilesystemMiddleware({ backend: be });
  const toolsOfMw = (mw.tools as Array<{ name: string; invoke: (a: unknown) => Promise<unknown> }>) ?? [];
  const readFile = toolsOfMw.find((t) => t.name === "read_file")!;

  const blocks = (await readFile.invoke({ file_path: "/p.png" })) as Array<Record<string, unknown>>;
  const first = Array.isArray(blocks) ? blocks[0] : (blocks as Record<string, unknown>);
  console.log(
    "工具层读 png:",
    JSON.stringify({ type: first?.type, mimeType: first?.mimeType, hasData: typeof first?.data === "string" }),
  );
  console.log(
    "工具层读文本:",
    JSON.stringify(await readFile.invoke({ file_path: "/p.txt", offset: 1, limit: 2 })),
  );

  section("结论");
  console.log("同名顶掉内置：Python 静默覆盖 → TS 抛 TOOL_NAME_COLLISION");
  console.log("两个自定义同名：Python 后者胜 → TS 两条并存（不去重）");
  console.log("delete 判定：Python 比 type().delete → TS 比 typeof backend.delete");
  console.log("glob 宽度：Python *.yml 更宽 → TS **/*.yml 更宽（语义相反）");
  console.log("多模态内容块键名：Python base64/mime_type → TS data/mimeType");
}

main().catch((e) => {
  console.error("验证失败:", e);
  process.exit(1);
});
