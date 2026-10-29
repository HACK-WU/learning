/**
 * 课 4 · 指令、技能与工具（TypeScript 侧）
 *
 * 对应课文：stages/2-能力声明/lessons/04-指令技能与工具.md
 *
 * 三个知识点各自的"静默失败"形态：
 *   ① 指令：省略 instructions 不会报错，但系统提示只剩平台的模板
 *   ② 技能：必须放进 skills/ 才会被发现（不是写在 config 里）
 *   ③ 工具：必须 import 进入口并传 tools=[...]，漏了 config 里连键都没有
 */

import { defineDeepAgent } from "managed-deepagents";
import type { ManagedToolRuntime } from "managed-deepagents";
import { tool } from "langchain";
import { z } from "zod";
import { section, step, show, showConfigKeys, hasKey, attempt } from "./_shared.ts";

type AppContext = { region?: string; verbose?: boolean };

// ── 实验 1：工具的声明式写法 ───────────────────────────────────
section("实验 1", "一个最小工具的完整形状");

export const lookupCustomer = tool(
  async ({ customerId }) => `Customer ${customerId} is on the enterprise plan.`,
  {
    name: "lookup_customer",
    description: "Look up a customer record by ID.",
    schema: z.object({
      customerId: z.string().describe("Customer ID from the CRM."),
    }),
  },
);

show("tool 对象类型", typeof lookupCustomer);
show("tool.name", lookupCustomer.name);
show("tool.description", lookupCustomer.description);
show("has .invoke", typeof lookupCustomer.invoke);

console.log(`
  三个必填项：name（模型看到的工具名）、description（模型据此判断何时用）、
  schema（参数结构，用 zod 描述一次、两侧共用）。

  注意 name 与变量名无关：变量叫 lookupCustomer，模型看到的是 lookup_customer。
  这个不一致是排查时最常见的困惑来源之一。
`);

// ── 实验 2：漏点名 → config 里没有 tools 键 ─────────────────────
section("实验 2", "漏点名：build 绿灯但工具不存在");

const withTools = defineDeepAgent({
  name: "support-agent",
  model: "openai:gpt-5.5",
  tools: [lookupCustomer],
});

const withoutTools = defineDeepAgent({
  name: "support-agent",
  model: "openai:gpt-5.5",
});

showConfigKeys(withTools.config, "传了 tools 的 keys");
showConfigKeys(withoutTools.config, "漏了 tools 的 keys");
show('漏了 tools: "tools" in config', hasKey(withoutTools.config, "tools"));
show("漏了 tools: config.tools", (withoutTools.config as Record<string, unknown>).tools);

console.log(`
  关键：漏点名时 config 里连 "tools" 这个键都不存在，不是空数组。
  JS 侧硬取得到 undefined，Python 侧硬取抛 KeyError——两边都不会主动提醒。

  所以"模型说我没有这个工具"时，第一个要查的不是工具实现，
  而是入口有没有把工具 import 进来并写进 tools=[...]。
`);

// ── 实验 3：runtime 注入与泛型顺序 ─────────────────────────────
section("实验 3", "工具里拿运行上下文：泛型顺序是 <TState, TContext>");

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

console.log(`
  正确：ManagedToolRuntime<unknown, AppContext>
                ↑TState（大多数时候不关心）  ↑TContext（你的业务上下文）

  ⚠️ 只写一个泛型 = 把 AppContext 塞进了 TState 槽，于是：
       runtime.context 被推断成 {}，访问 .region 报 TS2339
     这个错误 tsc 会抓到，但如果你没开 strict 或用了 any 就会漏过去。
     实测见 README 的「跨语言差异」表。

  runtime 上可用的三样东西：
    runtime.context        本次运行的业务上下文（作者声明什么就有什么）
    runtime.serverInfo     身份：principal.id / principal.claims
    runtime.state          图状态（需要 TState 泛型才拿得到类型）
`);

step("权限判断只认 principal，不看 context");
console.log(`
  对照组（错法）：
    const region = runtime.context?.region;
    if (region !== "cn") return "无权限";     ← 错：region 是数据不是身份

  context 可以由调用方传，等于"申请人自己填表"；
  principal 是平台签发的，改不了。判权限只能用后者。
`);

// ── 实验 4：技能的落点是目录，不是 config ──────────────────────
section("实验 4", "技能：落点是 skills/ 目录，config 里没有这个键");

console.log(`
  skills/ 与 tools/ 的根本差别：
    tools/     普通模块，必须 import + 点名
    skills/    自动发现，目录下每个 SKILL.md 都算一个技能

  技能是"渐进披露"的：模型先只看到技能的名字与描述，
  需要时才读正文——所以技能写长了不会立刻烧 token，
  但描述写糊了模型就不会去读。

  ⚠️ 静态入口不能设 skills——但拦的地方是 mda build，不是运行时。
     实测 defineDeepAgent({ skills }) 运行时完全不报错、config 里也有这个键；
     真跑 build 才拦：
       error: agent.ts: Remove 「skills」 from defineDeepAgent(...).
              Use a factory entrypoint to select skills per run;
              static agents use skills/.
     这个"晚一步才拦"的时机差异，是本地自测容易漏掉的一类坑。
`);

attempt("静态入口传 skills（运行时不拦，build 才拦）", () =>
  defineDeepAgent({
    name: "probe",
    model: "openai:gpt-5.5",
    skills: ["./skills/demo"],
  } as never),
);

// ── 实验 5：instructions 的两种给法 ───────────────────────────
section("实验 5", "指令：静态用 instructions.md，工厂用 instructions");

const staticPrompt = defineDeepAgent({
  name: "with-inline",
  model: "openai:gpt-5.5",
  instructions: "你是值班助手，回答要给出依据。",
});
showConfigKeys(staticPrompt.config, "内联 instructions 的 keys");
show("instructions 值", (staticPrompt.config as Record<string, unknown>).instructions);

console.log(`
  两条路：
    静态入口：写在 agent.ts 旁边的 instructions.md，build 时嵌进去
              （实测缺这个文件时 build 成功但给出警告）
    工厂入口：在 defineDeepAgent({ instructions }) 里给，可按 runtime 变

  两条路都不走 config 之外的"隐藏通道"——所以排查时看 config 就知道
  这次到底喂了什么提示。
`);

section("完成", "课 4 实测结束");
