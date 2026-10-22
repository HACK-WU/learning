/**
 * 课 5 Yin· Backends 后端与 Permissions 权限（TypeScript 版）
 *
 * 对应课文知识点 1-3。全程离线构造，不发请求、不需要 key：
 *   1) 六种后端的能力矩阵（静态 8 vs 请求期摘除）+ 三轴选型
 *   2) CompositeBackend 最长前缀路由：剥前缀 / 贴前缀语义
 *   3) permissions 声明式规则：first-match-wins + 三条边界
 *
 * 运行：npm run l05
 */

import {
  createDeepAgent,
  createFilesystemMiddleware,
  CompositeBackend,
  FilesystemBackend,
  LocalShellBackend,
  StateBackend,
} from "deepagents";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createRequire } from "node:module";
import { section } from "./_shared.js";

const require = createRequire(import.meta.url);

interface MiddlewareLike {
  name?: string;
  tools?: unknown;
  wrapModelCall?: unknown;
}

const mwToolNames = (mw: MiddlewareLike): string[] =>
  ((mw.tools as Array<{ name: string }>) ?? []).map((t) => t.name).sort();

/** 请求期真实可见的工具（拦 wrapModelCall，不发网络请求；必须传真实工具对象）。 */
const requestTimeTools = async (mw: MiddlewareLike): Promise<string[]> => {
  const tools = (mw.tools as Array<{ name: string }>) ?? [];
  const box: { seen?: Array<{ name: string }> } = {};
  const handler = async (r: unknown) => {
    box.seen = (r as { tools?: Array<{ name: string }> }).tools;
    return { content: "ok" };
  };
  const call = mw.wrapModelCall as (a: unknown, b: unknown) => Promise<unknown>;
  await call({ tools }, handler);
  return (box.seen ?? []).map((t) => t.name).sort();
};

/** 一个"无 delete、无 execute"的鸭子后端（TS：实例级判定 delete）。 */
class BareBackend {
  async ls() {
    return { files: [] };
  }
  async read() {
    return { content: "" };
  }
  async write(p: string) {
    return { path: p };
  }
  async edit(p: string) {
    return { path: p, occurrences: 1 };
  }
  async glob() {
    return { files: [] };
  }
  async grep() {
    return { matches: [] };
  }
  async uploadFiles() {
    return [];
  }
  async downloadFiles() {
    return [];
  }
}

async function main() {
  section("0. 版本");
  console.log("deepagents:", require("deepagents/package.json").version);

  // ---------------------------------------------------------------- 1
  section("1) 六种后端能力矩阵（静态 8 vs 请求期摘除）");
  const bareNoDelete = new BareBackend();
  const bareWithDelete = new BareBackend() as BareBackend & {
    delete: (p: string) => Promise<{ path: string }>;
  };
  bareWithDelete.delete = async (p: string) => ({ path: p });

  const cases: Array<[string, unknown]> = [
    ["StateBackend     ", new StateBackend()],
    ["FilesystemBackend", new FilesystemBackend({ rootDir: mkdtempSync(join(tmpdir(), "da-l05-")), virtualMode: true })],
    ["LocalShellBackend", new LocalShellBackend({ rootDir: "/tmp" })],
    [
      "Composite(default=磁盘)",
      new CompositeBackend(new FilesystemBackend({ rootDir: mkdtempSync(join(tmpdir(), "da-l05-")), virtualMode: true }), {
        "/memories/": new StateBackend(),
      }),
    ],
    ["自定义(无 delete)  ", bareNoDelete],
    ["自定义(挂 delete)  ", bareWithDelete],
  ];
  for (const [tag, backend] of cases) {
    const mw = createFilesystemMiddleware({ backend: backend as never });
    const statics = mwToolNames(mw);
    const visible = await requestTimeTools(mw);
    const hidden = statics.filter((n) => !visible.includes(n));
    const hasDelete = visible.includes("delete");
    const hasExec = visible.includes("execute");
    console.log(
      `${tag} delete=${String(hasDelete).padEnd(5)} exec=${String(hasExec).padEnd(5)} 可见 ${visible.length} 摘掉=[${hidden.join(",")}]`,
    );
  }

  // ---------------------------------------------------------------- 2
  section("2) CompositeBackend 最长前缀路由：剥 / 贴");
  const root = mkdtempSync(join(tmpdir(), "da-l05-"));
  mkdirSync(join(root, "memories"), { recursive: true });
  writeFileSync(join(root, "memories/agent.md"), "记忆内容");
  mkdirSync(join(root, "memoriesX"), { recursive: true });
  const diskForMemories = new FilesystemBackend({ rootDir: join(root, "memories"), virtualMode: true });
  // default 用另一块磁盘目录，避免 StateBackend 在独立构造时缺少执行上下文
  const diskDefault = new FilesystemBackend({ rootDir: join(root, "default"), virtualMode: true });
  const composite = new CompositeBackend(diskDefault, {
    "/memories/": diskForMemories,
  });

  // read：剥掉前缀变成 /agent.md 转发，返回时贴回前缀
  const read = await composite.read("/memories/agent.md");
  console.log("read /memories/agent.md ->", JSON.stringify(read.content));

  // write /memories/new.md：应当落在 memories 磁盘下
  await composite.write("/memories/new.md", "新记忆");
  const back = await composite.read("/memories/new.md");
  console.log("write+read /memories/new.md ->", JSON.stringify(back.content));

  // 前缀边界：/memoriesX 不应被 /memories/ 命中（段边界匹配）
  await composite.write("/memoriesX/outside.md", "外部");

  // 资源解构：read 的时候传入 offset/limit 是否透传
  const paged = await composite.read("/memories/agent.md", 0, 1);
  console.log("read offset=0 limit=1 ->", JSON.stringify(paged.content));

  // ---------------------------------------------------------------- 3
  section("3) permissions：first-match-wins + 三条边界");
  const fsRoot = mkdtempSync(join(tmpdir(), "da-l05-"));
  const be = new FilesystemBackend({ rootDir: fsRoot, virtualMode: true });
  await be.write("/notes.md", "普通笔记");
  await be.write("/.env", "SECRET=1");
  await be.write("/.aws/credentials", "AKIA...");

  // 3a. 宽 deny：/** 挡不住点开头文件
  // TS 约定：deny 用结果对象里的 error 字段表达，**不抛异常**——这正是罪魁
  const denyAll = createFilesystemMiddleware({
    backend: be,
    permissions: [{ operations: ["read"], paths: ["/**"], mode: "deny" }],
  });
  const readText = async (mw: MiddlewareLike, p: string): Promise<string> => {
    const t = ((mw.tools as Array<{ name: string; invoke: (a: unknown) => Promise<unknown> }>) ?? []).find(
      (x) => x.name === "read_file",
    );
    const content = ((await t!.invoke({ file_path: p })) as { content?: string }).content ?? "";
    return content.startsWith("Error: permission denied")
      ? `BLOCKED:${content.slice(0, 30)}`
      : `OK:${content.slice(0, 30)}`;
  };
  console.log("deny-all /notes.md  ->", await readText(denyAll, "/notes.md"));
  console.log("deny-all /.env      ->", (await readText(denyAll, "/.env")).slice(0, 30));

  // 3b. 补点号后能拦住
  const denyDots = createFilesystemMiddleware({
    backend: be,
    permissions: [{ operations: ["read"], paths: ["/**", "/**/.*", "/**/.*/**"], mode: "deny" }],
  });
  console.log("deny+点号 /.env     ->", (await readText(denyDots, "/.env")).slice(0, 40));

  // 3c. first-match-wins：窄 allow 在前，宽 deny 在后 -> 命中 allow 放行
  const narrowAllow = createFilesystemMiddleware({
    backend: be,
    permissions: [
      { operations: ["read"], paths: ["/notes.md"], mode: "allow" },
      { operations: ["read"], paths: ["/**"], mode: "deny" },
    ],
  });
  console.log("窄allow在前 /notes.md ->", (await readText(narrowAllow, "/notes.md")).slice(0, 40));
  console.log("窄allow在前 /other.md ->", (await readText(narrowAllow, "/other.md")).slice(0, 30));

  // 3d. 沙箱 + 宽 deny 权限 -> 构造期 NotImplementedError / ConfigurationError
  try {
    createFilesystemMiddleware({
      backend: new LocalShellBackend({ rootDir: "/tmp" }) as never,
      permissions: [{ operations: ["read"], paths: ["/**"], mode: "deny" }],
    });
    console.log("沙箱+/** deny      -> 未抛错(不应)");
  } catch (e) {
    const err = e as { constructor: { name: string }; code?: string; message: string };
    console.log("沙箱+/** deny      -> 抛错:", err.constructor.name, "|", err.message.split("\n")[0].slice(0, 80));
  }

  // 前缀边界：/memoriesX 不应被 /memories/ 命中（段边界匹配）——应走 default 磁盘
  await composite.write("/memoriesX/outside.md", "外部");
  const outside = await composite.read("/memoriesX/outside.md");
  console.log("write+read /memoriesX/outside.md ->", JSON.stringify(outside.content));

  section("结论");
  console.log("能力判定：delete Python 看类 / TS 看实例；execute 看 isSandboxBackend");
  console.log("Composite 最长前缀剥/贴；/memoriesX 是段边界，不会被 /memories/ 命中");
  console.log("deny /** 盖不住点开头（无 DOTMATCH）；补 /**/.* 才拦得住");
  console.log("first-match-wins；窄 allow 在前会让宽 deny 失效");
  console.log("沙箱 execute 不适用工具级权限，构造期抛错");
}

main().catch((e) => {
  console.error("验证失败:", e);
  process.exit(1);
});
