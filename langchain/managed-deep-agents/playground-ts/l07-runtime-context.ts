/**
 * 课 7 · 运行时上下文（TypeScript 侧）
 *
 * 对应课文：stages/3-运行与交付/lessons/07-运行时上下文.md
 *
 * 三个知识点：
 *   ① runtime 对象上有哪几个入口（channel / executionRuntime / serverInfo）
 *   ② context 与 principal 的分工：一个能变、一个不能改
 *   ③ 工厂入口：查表必须在工厂外，工厂内只有赋值与 return
 *
 * ⚠️ 本课最值得记的一条：ManagedToolRuntime 的泛型是 <TState, TContext>，
 *    只写一个泛型会把 context 塞进 state 槽，runtime.context 变成 {}。
 */

import { defineDeepAgent, defineSandbox } from "managed-deepagents";
import type { ManagedServerRuntime, ManagedToolRuntime } from "managed-deepagents";
import { tool } from "langchain";
import { z } from "zod";
import { section, step, show, showConfigKeys, attempt } from "./_shared.ts";

type AppContext = { region?: string; verbose?: boolean; tier?: string };

// ── 实验 1：runtime 的三个入口 ─────────────────────────────────
section("实验 1", "ManagedServerRuntime 上有哪几样东西");

console.log(`
  runtime
  ├── channel            通道上下文：name / provider / target / rawEvent
  ├── executionRuntime   本次执行：context（业务上下文）
  ├── serverInfo         身份：principal（平台签发）
  └── ...                其余见类型定义

  三个入口对应三个问题：
    channel      "这条消息从哪来"（分流用）
    context      "这次按什么参数跑"（选模型、选技能用）
    principal    "这个人是谁"（判权限用）
`);

// ── 实验 2：泛型顺序（本课最重要的一条）──────────────────────
section("实验 2", "泛型顺序：<TState, TContext>，写反了类型就塌");

export const checkOrder = tool(
  async ({ orderId }, runtime: ManagedToolRuntime<unknown, AppContext>) => {
    const principal = runtime.serverInfo?.principal;
    if (!principal) return "Sign in to check orders.";
    const region = runtime.context?.region ?? "us";
    return `Order ${orderId} for ${principal.id} ships from ${region}.`;
  },
  {
    name: "check_order",
    description: "Check the status of an order.",
    schema: z.object({ orderId: z.string() }),
  },
);

show("checkOrder.name", checkOrder.name);

console.log(`
  正确：ManagedToolRuntime<unknown, AppContext>
                            ↑TState  ↑TContext

  常见错误：ManagedToolRuntime<AppContext>
    → AppContext 进了 TState 槽，TContext 保持默认 {},
    → runtime.context 被推断成 {}，
    → 访问 runtime.context?.region 报 TS2339: Property 'region' does not exist

  这个错误 tsc 会抓（本工程实测报的就是这条），
  但若你把 runtime 标成 any 或关掉 strict，就会一路滑到运行时才炸。
`);

step("两条读法对照（哪条合法、哪条错误）");
console.log(`
  ✅ const region = runtime.context?.region;          // TContext 对了才行
  ❌ const region = (runtime as any).context?.region;  // 类型全丢，改字段不会报错
`);

// ── 实验 3：context vs principal 的分工 ──────────────────────
section("实验 3", "context 可变、principal 不可改");

console.log(`
  context 的来源：调用方传进来的 run context（工厂按它挑配置）
  principal 的来源：平台校验身份后签发

  所以：
    挑模型 / 挑技能 / 挑提示       → 读 context（它本来就该可变）
    判断"能不能做这件事"           → 读 principal（它改不了）

  反例（本课程反复强调的错法）：
    const region = runtime.context?.region;
    if (region !== "cn") return "无权限";   ← region 是数据，不是身份
  调用方把 region 传成 "cn" 就绕过去了。
`);

// ── 实验 4：工厂入口的形状 ───────────────────────────────────
section("实验 4", "工厂入口：查表在工厂外，工厂内只有赋值与 return");

const CONFIGS: Record<string, Record<string, unknown>> = {
  "payments-service": {
    model: "openai:gpt-5.5",
    instructions: "Python service. Run pytest before opening a PR.",
  },
  storefront: {
    model: "openai:gpt-5.5-mini",
    instructions: "Next.js app. Run web tests and an a11y check.",
  },
};
const DEFAULT_CONFIG = CONFIGS.storefront;

export function agent(runtime: ManagedServerRuntime<any>) {
  const context = runtime.executionRuntime?.context;
  const repo = context?.repository as string | undefined;
  const config = CONFIGS[repo ?? ""] ?? DEFAULT_CONFIG;
  return defineDeepAgent({ name: "open-swe", ...config } as never);
}

show("CONFIGS 的键", Object.keys(CONFIGS));
show("默认配置的 model", DEFAULT_CONFIG.model);

console.log(`
  为什么查表要放工厂外？
    工厂体里出现 if / try / for / while / with 之类的控制流，
    mda build 的静态扫描就读不出 name 了（Python 侧直接报
    "agent name ... must be a static string literal"）。
    TS 侧的实测结论：工厂函数体里 return defineDeepAgent(...)，
    build 报"缺 name"——因为 CLI 不去执行工厂，读不到里面的字面量。

  所以正确形状是：
    const CONFIGS = {...}                  ← 模块级，build 能读
    export function agent(runtime) {
      const config = CONFIGS[...] ?? 默认   ← 查表
      return defineDeepAgent({ name: "...", ...config })   ← 赋值 + return
    }
`);

// ── 实验 5：context 只有声明了 schema 才有类型 ────────────────
section("实验 5", "context 的类型来自 contextSchema / context_schema");

const withSchema = defineDeepAgent({
  name: "typed-context",
  model: "openai:gpt-5.5",
  instructions: "按上下文调整。",
} as never);
showConfigKeys(withSchema.config, "不声明 schema 的 keys");

console.log(`
  不声明 schema 时：runtime.context 是宽松对象，取什么字段都不报错（也不校验）。
  声明 contextSchema 后：运行时会按 schema 校验传入的 context，
  字段名写错、类型不符会在运行前被拦下。

  ⚠️ 但要注意：schema 是"校验形状"，不是"可信来源"。
     它可以保证 region 是字符串，不能保证 region 就该是这个值。
     判权限仍然只认 principal。
`);

// ── 实验 6：sandbox 与 permissions 的关系（呼应课 6）─────────
section("实验 6", "sandbox 存在时 permissions 归平台");

const sb = defineSandbox({ idleTtlSeconds: 300 });
show("sandbox options", (sb as unknown as { options: unknown }).options);

console.log(`
  托管版里 permissions 不是作者可设字段（类型层就是 never）。
  想让"某些文件不能写"，靠的是 沙箱边界 + 工具收窄，
  不是靠写一条 deny 规则——这一点与直连 deepagents 完全不同。
`);

section("完成", "课 7 实测结束");
