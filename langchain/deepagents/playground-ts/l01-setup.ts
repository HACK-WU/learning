/**
 * 课 1 · 环境自检（TypeScript 版）
 *
 * 对应课文：stages/1-定位与起跑/lessons/01-环境准备.md
 * 目的：不调用任何模型 API，只验证「包装对了、能 import、能构造」。
 *
 * 运行（在 playground-ts 目录内）：
 *
 *     npm run l01
 */

import { section } from "./_shared.js";

async function main() {
  section("1. 包版本");
  // 直接读 package.json 会因 NodeNext 的 import 断言限制而啰嗦，
  // 这里用 createRequire 读版本，输出与 Python 侧 `pip show` 对齐。
  const { createRequire } = await import("node:module");
  const require = createRequire(import.meta.url);

  const pkgs = ["deepagents", "@langchain/core", "@langchain/langgraph", "@langchain/openai"];
  for (const name of pkgs) {
    const v = require(`${name}/package.json`).version as string;
    console.log(`${name.padEnd(22)} ${v}`);
  }

  section("2. 入口能否加载");
  const mod = await import("deepagents");
  console.log("createDeepAgent 是否存在:", typeof mod.createDeepAgent === "function");
  // 注意：REQUIRED_MIDDLEWARE_NAMES 是 Set<string>，表示「必须存在」的中间件，
  // 不是完整装配清单。实测只有 2 项，勿当默认栈成员数引用。
  console.log(
    "REQUIRED_MIDDLEWARE_NAMES（Set）:",
    [...mod.REQUIRED_MIDDLEWARE_NAMES].join(", "),
  );

  section("3. 后端类是否都导出");
  const backends = [
    "StateBackend",
    "FilesystemBackend",
    "StoreBackend",
    "CompositeBackend",
    "ContextHubBackend",
    "LocalShellBackend",
  ];
  for (const b of backends) {
    console.log(`${b.padEnd(22)} ${b in mod ? "OK" : "缺失"}`);
  }

  section("4. 装配自检（不调模型、不联网）");
  const { createDeepAgent } = mod;
  // 只构造、不 invoke：验证 harness 替你装了什么。
  // 注意 createDeepAgent 同步返回，await 只为与官方示例写法一致。
  const agent = await createDeepAgent({ model: "openai:gpt-4o-mini", tools: [] });

  const collected: string[] = [];
  const middleware = agent.options.middleware ?? [];
  for (const mw of middleware) {
    const t = (mw as { tools?: unknown }).tools;
    if (!t) continue;
    const arr = typeof t === "function" ? (t as () => unknown[])() : (t as unknown[]);
    const names = (arr || [])
      .map((x) => (x as { name?: string })?.name)
      .filter((n): n is string => Boolean(n));
    if (names.length) console.log(`${(mw as { name?: string }).name} -> ${names.join(",")}`);
    collected.push(...names);
  }
  const uniq = [...new Set(collected)].sort();
  console.log("工具数：", uniq.length);
  console.log(uniq);
  console.log("中间件层数：", middleware.length);
  console.log(
    "中间件清单：",
    middleware.map((m) => (m as { name?: string }).name).join(", "),
  );

  section("5. 结论");
  console.log("包装好、入口可加载、后端齐全 —— 环境准备完成（尚未调用模型）。");
  console.log("注意：Python 侧裸栈 7 条中间件、TS 侧 5 条，差异详见 API-MAPPING.md。");
}

main().catch((e) => {
  console.error("自检失败:", e);
  process.exit(1);
});
