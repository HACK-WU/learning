/**
 * 课 2 · 托管的是什么（TypeScript 侧）
 *
 * 对应课文：stages/1-定位与起跑/lessons/02-托管的是什么.md
 *
 * 本课要回答：defineDeepAgent 到底托管了什么？答案是三样
 *   ① 编译（你不用自己 createDeepAgent 再挂中间件）
 *   ② 运行时资源（backend / store / checkpointer 平台给）
 *   ③ 交付形态（部署后是一个 LangGraph app）
 * 并实测：托管自有键在 JS 侧是"运行时直接抛错"，不是"静默忽略"。
 */

import {
  defineDeepAgent,
  defineSandbox,
} from "managed-deepagents";
import { section, step, show, showConfigKeys, hasKey, attempt } from "./_shared.ts";

// ── 实验 1：定义 vs 已编译 agent ─────────────────────────────────
section("实验 1", "返回值是定义，不是 agent");

const definition = defineDeepAgent({
  name: "my-agent",
  model: "openai:gpt-5.5",
});

show("constructor", definition.constructor.name);
show("kind", definition.kind);
show("Object.keys", Object.keys(definition));
step("三个存在性检查");
show("typeof invoke", typeof (definition as Record<string, unknown>).invoke);
show("typeof stream", typeof (definition as Record<string, unknown>).stream);
show("typeof config", typeof definition.config);

console.log(`
  结论：kind 是 "deep-agent"，但 invoke / stream 都不存在。
  它是"配方"而不是"做好的菜"——编译器在托管平台侧，不在你本地。
`);

// ── 实验 2：config 里到底是什么 ──────────────────────────────────
section("实验 2", "config 只存你亲口说过的东西");

showConfigKeys(definition.config);
show("config 全量", definition.config);

step("省略 vs 空数组：两种「没有」");
const withEmpty = defineDeepAgent({
  name: "empty-tools",
  model: "openai:gpt-5.5",
  tools: [],
});
show('省略 tools: "tools" in config', hasKey(definition.config, "tools"));
show('省略 tools: config.tools', (definition.config as Record<string, unknown>).tools);
show('tools=[]: "tools" in config', hasKey(withEmpty.config, "tools"));
show('tools=[]: config.tools', (withEmpty.config as Record<string, unknown>).tools);

console.log(`
  两者模型侧看到的效果一样（都是零个自有工具），但排查时要分清：
    "键不存在" = 你压根没提这个字段
    "键存在且为空" = 你提了，但配成空的
  JS 侧硬取缺键得到 undefined 而非抛错，所以判断存在性要用 'in'。
`);

// ── 实验 3：托管自有键会被运行时拒绝 ─────────────────────────────
section("实验 3", "托管自有键：类型禁止 + 运行时抛错");

console.log(`
  下面五组在 TS 类型层面本就是 never（写进编辑器就标红），
  这里用 as any 绕过类型，看运行时会不会兜底：
`);

const managedKeys: Array<[string, Record<string, unknown>]> = [
  ["backend", { backend: {} }],
  ["store", { store: {} }],
  ["checkpointer", { checkpointer: {} }],
  ["systemPrompt", { systemPrompt: "你是助手" }],
  ["disableMemory", { disableMemory: true }],
];

for (const [label, extra] of managedKeys) {
  attempt(
    `传入 ${label}`,
    () => defineDeepAgent({ name: "probe", model: "openai:gpt-5.5", ...extra } as never),
  );
}

console.log(`
  五组全部抛错，且报错信息直接告诉你"该挪去哪里"——
  这不是静默忽略，而是双保险：类型层禁止 + 运行时兜底。
  与 Python 侧最大的差别就在这里：Python 是类型标注 + 文档，
  JS 侧把这条限制做成了硬失败。
`);

// ── 实验 4：sandbox 是"托管资源"的正确落点 ──────────────────────
section("实验 4", "托管资源的正确落点：sandbox/ 目录");

const sandbox = defineSandbox({
  idleTtlSeconds: 600,
  defaultTimeout: 600,
});

show("sandbox constructor", sandbox.constructor.name);
show("sandbox keys", Object.keys(sandbox));
show("sandbox 全量", sandbox);

console.log(`
  注意形状：{ kind: "sandbox", options: {...} }——
  它不是配置片段，而是一个带 kind 的声明对象。
  同期还有 memory.ts / identity.ts / channels/ / schedules/，
  共同点是"作者声明意图，平台负责执行"。
`);

step("对照：createDeepAgent 的入参里全是「谁拥有」的答案");

console.log(`
  直连 deepagents 时你写：
    createDeepAgent({
      model, tools,
      systemPrompt: SYSTEM_PROMPT,      → 搬进 instructions.md
      skills: ["/skills/research/"],    → 搬进 skills/research/SKILL.md
      checkpointer,                     → 删掉，运行时给
    })

  托管版你写：
    defineDeepAgent({
      name: "research-assistant",       → 新增，必填
      model, tools,
    })

  差别不是"少写几个字段"，而是"这些字段的所有权换了人"。
  少写 systemPrompt 不是忘写，是它压根不该由你在这里给。
`);

// ── 实验 5：instructions 不进 config ───────────────────────────
section("实验 5", "instructions 是个例外：它是作者该管的");

const withInstructions = defineDeepAgent({
  name: "with-instructions",
  model: "openai:gpt-5.5",
  instructions: "你是一个值班助手。",
});
showConfigKeys(withInstructions.config, "带 instructions 的 keys");

console.log(`
  instructions 留在 config 里，而 systemPrompt 被拒——
  区别在于"谁能改"：instructions.md 是你仓库里的文件，
  部署时由 mda 嵌进系统提示；systemPrompt 是运行时拼装的一部分。
`);

section("完成", "课 2 实测结束");
