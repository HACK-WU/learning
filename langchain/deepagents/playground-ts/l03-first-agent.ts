/**
 * 课 3 · 默认装配全序验证（TypeScript 版）
 *
 * 对应课文 4.1 机制验证。一次跑完 five 个观察点：
 *   1) 只给 model 的默认栈与工具
 *   2) 不重名中间件插在 patch 之后
 *   3) 同名中间件原位替换
 *   4) todoListMiddleware 新增 write_todos
 *   5) interruptOn / memory 带来的尾栈
 * 全程离线构造，不发请求、不需要 key。
 *
 * 运行：npm run l03
 */

import { createDeepAgent } from "deepagents";
import { createMiddleware, todoListMiddleware } from "langchain";
import { createRequire } from "node:module";
import { section } from "./_shared.js";

const require = createRequire(import.meta.url);

interface AgentLike {
  options: { middleware?: readonly unknown[] };
}

const stackOf = (a: AgentLike): string[] =>
  ((a.options.middleware ?? []) as Array<{ name?: string }>).map(
    (m) => m.name ?? "<unnamed>",
  );

const toolsOf = (a: AgentLike): string[] => {
  const out: string[] = [];
  for (const mw of (a.options.middleware ?? []) as Array<{ tools?: unknown }>) {
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

async function main() {
  section("0. 版本");
  console.log("deepagents:", require("deepagents/package.json").version);

  section("1) 只给 model → 默认栈");
  const base = await createDeepAgent({ model: "openai:gpt-4o-mini", tools: [] });
  console.log("栈:", stackOf(base).join(" → "));
  console.log("工具:", toolsOf(base));

  section("2) 加不重名中间件 → 插在 patch 之后");
  const probe = createMiddleware({ name: "ProbeMiddleware", tools: [] });
  const added = await createDeepAgent({
    model: "openai:gpt-4o-mini",
    tools: [],
    middleware: [probe],
  });
  console.log("栈:", stackOf(added).join(" → "));

  section("3) 加同名中间件 → 原位替换");
  const myPatch = createMiddleware({ name: "patchToolCallsMiddleware", tools: [] });
  const replaced = await createDeepAgent({
    model: "openai:gpt-4o-mini",
    tools: [],
    middleware: [myPatch],
  });
  console.log("栈:", stackOf(replaced).join(" → "));

  section("4) todoListMiddleware → 新增 write_todos");
  const todo = await createDeepAgent({
    model: "openai:gpt-4o-mini",
    tools: [],
    middleware: [todoListMiddleware()],
  });
  const diff = toolsOf(todo).filter((t) => !toolsOf(base).includes(t));
  console.log("新增工具:", diff);

  section("5) 参数带来的尾栈");
  const hitl = await createDeepAgent({
    model: "openai:gpt-4o-mini",
    tools: [],
    interruptOn: { write_file: true },
  });
  console.log("interruptOn →", stackOf(hitl).join(" → "));

  const mem = await createDeepAgent({
    model: "openai:gpt-4o-mini",
    tools: [],
    memory: ["/AGENTS.md"],
  });
  console.log("memory      →", stackOf(mem).join(" → "));

  section("结论");
  console.log("TS 默认 5 条栈，Python 默认 7 条（多 _ParentNotifier 与 Anthropic 提示缓存）");
  console.log("同名原位替换、异名插在 patch 之后 —— 两侧一致");
  console.log("尾栈位置两侧不同，排障要分别实测");
}

main().catch((e) => {
  console.error("验证失败:", e);
  process.exit(1);
});
