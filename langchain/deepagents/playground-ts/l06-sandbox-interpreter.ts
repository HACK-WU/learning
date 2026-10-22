/**
 * 课 6 Yin· 代码执行 Sandboxes 与 Interpreters（TypeScript 版，可实测部分）
 *
 * 对应课文知识点 1 的两个可双向验证点：
 *   1) execute 可见性由后端类型判定（State / Filesystem 无，LocalShell 有）
 *   2) LocalShellBackend 的 virtual_mode 只管文件工具，execute 能穿出去
 *
 * 注意：TS npm 包没有 interpreter 中间件，知识点 2 无法在 TS 侧实测。
 *
 * 运行：npm run l06
 */

import {
  createDeepAgent,
  createFilesystemMiddleware,
  LocalShellBackend,
  StateBackend,
  FilesystemBackend,
} from "deepagents";
import { mkdtempSync, writeFileSync, existsSync } from "node:fs";
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

async function main() {
  section("0. 版本");
  console.log("deepagents:", require("deepagents/package.json").version);

  // ---------------------------------------------------------------- 1
  section("1) execute 可见性由后端类型判定");
  const backendCases: Array<[string, unknown]> = [
    ["StateBackend", new StateBackend()],
    ["FilesystemBackend", new FilesystemBackend({ rootDir: mkdtempSync(join(tmpdir(), "da-l06-")), virtualMode: true })],
    ["LocalShellBackend", new LocalShellBackend({ rootDir: "/tmp", virtualMode: true })],
  ];
  for (const [tag, be] of backendCases) {
    const mw = createFilesystemMiddleware({ backend: be as never });
    const statics = ((mw.tools as Array<{ name: string }>) ?? []).map((t) => t.name).sort();
    const visible = await requestTimeTools(mw);
    const hasExec = visible.includes("execute");
    console.log(
      `${tag.padEnd(18)} n=${visible.length}  execute=${hasExec ? "YES" : "no "} 摘掉=[${statics.filter((n) => !visible.includes(n)).join(",")}]`,
    );
  }

  // ---------------------------------------------------------------- 2
  section("2) LocalShellBackend 隔离边界：文件工具守住 / execute 穿出去");
  const root = join(tmpdir(), "da-l06-sh");
  const ls = new LocalShellBackend({ rootDir: root, virtualMode: true });
  await ls.write("/inside.txt", "in");
  // 文件工具穿越被拒（TS：返回 {error} 而非抛异常）
  const rr = await ls.read("/../../etc/hostname", 0, 5) as { error?: string };
  if (rr.error) {
    console.log("read 穿越  -> 拒绝:", rr.error.slice(0, 45));
  } else {
    console.log("read 穿越  -> 竟然成功（不应）");
  }
  // execute 读宿主文件
  const r = await ls.execute("cat /etc/hostname");
  console.log("execute 读 /etc -> exit=", r.exitCode, "output=", JSON.stringify((r.output ?? "").slice(0, 20)));
  // execute 写 root_dir 外
  const outside = join(tmpdir(), "da-l06-OUTSIDE.txt");
  await ls.execute(`touch ${outside} && echo done`);
  console.log("execute 写 root 外 -> 文件存在=", existsSync(outside));
  // execute cwd
  const r2 = await ls.execute("pwd");
  console.log("execute 的 cwd ->", r2.output?.trim());

  section("结论");
  console.log("execute 可见性：State/Filesystem 无、LocalShell 有（类型判定）");
  console.log("virtual_mode 只管文件工具路径；execute 是任意 shell（无隔离）");
  console.log("interpreter：TS 1.15.1 无导出，无法实测（Python 侧才可用）");
}

main().catch((e) => {
  console.error("验证失败:", e);
  process.exit(1);
});
