/**
 * 课 2 · 三层分工验证（TypeScript 版）
 *
 * 对应课文：stages/1-定位与起跑/lessons/02-DeepAgents是什么.md
 * 目的：证明三件事——运行时是 LangGraph、工具是 harness 预装的、write_todos 来自 framework 的中间件。
 * 不调用模型，不需要 key。
 *
 * 运行（在 playground-ts 目录内）：
 *
 *     npm run l02
 */

import { createDeepAgent } from "deepagents";
import { todoListMiddleware } from "langchain";
import { createRequire } from "node:module";
import { section } from "./_shared.js";

const require = createRequire(import.meta.url);

/** 从各中间件的 tools 字段汇总工具名（TS 侧没有 agent.nodes["tools"] 这种入口）。 */
function toolsOf(agent: { options: { middleware?: readonly unknown[] } }): string[] {
  const collected: string[] = [];
  for (const mw of (agent.options.middleware ?? []) as Array<{ tools?: unknown }>) {
    const t = mw.tools;
    if (!t) continue;
    const arr = typeof t === "function" ? (t as () => unknown[])() : (t as unknown[]);
    for (const x of arr ?? []) {
      const n = (x as { name?: string }).name;
      if (n) collected.push(n);
    }
  }
  return [...new Set(collected)].sort();
}

async function main() {
  section("1. 包版本");
  console.log("deepagents", require("deepagents/package.json").version);

  section("2. 返回对象类型（第 1 层证据：运行时）");
  const agent = await createDeepAgent({ model: "openai:gpt-4o-mini", tools: [] });
  console.log("返回对象类型:", agent.constructor.name);

  section("3. 默认工具（第 2 层证据：harness 预装）");
  console.log("默认工具:", toolsOf(agent));

  section("4. 加 todoListMiddleware 后（第 3 层证据：framework 构件）");
  // Python 写 TodoListMiddleware()（大写开头、构造调用）
  // TS 写 todoListMiddleware()（小写开头、工厂函数）
  const agent2 = await createDeepAgent({
    model: "openai:gpt-4o-mini",
    tools: [],
    middleware: [todoListMiddleware()],
  });
  console.log("加 todoListMiddleware 后:", toolsOf(agent2));

  section("5. 结论");
  console.log("返回 ReactAgent → 运行时是 @langchain/langgraph 的图");
  console.log("9 个工具开箱即有 → harness 预装");
  console.log("middleware 可插入 → framework 构件");
}

main().catch((e) => {
  console.error("验证失败:", e);
  process.exit(1);
});
