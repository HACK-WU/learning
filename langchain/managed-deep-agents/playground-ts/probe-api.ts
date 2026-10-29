/**
 * 探针：实测 managed-deepagents 0.9.5 的 JS 侧真实 API 面。
 *
 * 目的：课文 TS 侧的每个写法都要在这里真跑一遍，不许照文档臆造。
 * 跑法：npm run probe
 */

import {
  defineDeepAgent,
  defineSandbox,
  defineMemory,
  defineIdentity,
  defineSchedule,
  defineMcp,
  channels,
  schedules,
  memoryLayer,
} from "managed-deepagents";

const line = (label: string) => console.log(`\n===== ${label} =====`);

line("1. defineDeepAgent 最小调用");
const a1 = defineDeepAgent({ name: "my-agent", model: "openai:gpt-5.5" });
console.log("constructor :", a1?.constructor?.name);
console.log("kind        :", a1.kind);
console.log("config keys :", Object.keys(a1.config).sort());
console.log("config JSON :", JSON.stringify(a1.config));
console.log("has invoke  :", typeof (a1 as any).invoke);
console.log("has stream  :", typeof (a1 as any).stream);
console.log("all keys    :", Object.keys(a1));

line("2. tools 三态：省略 / 空数组 / 有线");
const a2 = defineDeepAgent({ name: "x", model: "openai:gpt-5.5", tools: [] });
console.log('tools=[] -> "tools" in config:', "tools" in a2.config, "| value:", JSON.stringify((a2.config as any).tools));
console.log("省略 ->", 'sorted:', Object.keys(a1.config).sort().join(","), '| "tools" in:', "tools" in a1.config);
console.log('get 安全读:', (a1.config as any).tools);
try {
  console.log((a1.config as any).tools);
} catch (e) {
  console.log("硬取 KeyError 验证：以上不会抛，因为 JS 对象缺键返回 undefined 而非抛错");
}

line("3. instructions 键");
const a3 = defineDeepAgent({ name: "x", model: "openai:gpt-5.5", instructions: "你是助手" });
console.log("keys:", Object.keys(a3.config).sort());

line("4. 托管自有键应被类型拒绝（backend/store/checkpointer/systemPrompt/disableMemory）");
for (const [label, cfg] of Object.entries({
  backend: { name: "x", model: "openai:gpt-5.5", backend: {} },
  store: { name: "x", model: "openai:gpt-5.5", store: {} },
  checkpointer: { name: "x", model: "openai:gpt-5.5", checkpointer: {} },
  systemPrompt: { name: "x", model: "openai:gpt-5.5", systemPrompt: "s" },
  disableMemory: { name: "x", model: "openai:gpt-5.5", disableMemory: true },
})) {
  try {
    const r = defineDeepAgent(cfg as any);
    console.log(`${label}: 运行时不拦，config keys =`, Object.keys(r.config).sort().join(","));
  } catch (e) {
    console.log(`${label}: 运行时抛 ->`, (e as Error).message.slice(0, 100));
  }
}

line("5. name 缺失 / 非静态字符串");
try {
  defineDeepAgent({ model: "openai:gpt-5.5" } as any);
} catch (e) {
  console.log("缺 name ->", (e as Error).constructor.name, ":", (e as Error).message.slice(0, 160));
}

line("5b. name 形态三层：字面量 / const 变量 / 模板字符串 / 工厂内");
const NAME = "ts-var-name";
const tpl = `tpl-${1}`;
for (const [label, v] of Object.entries({
  字面量: "ts-literal",
  const变量: NAME,
  模板字符串: tpl,
})) {
  try {
    const r = defineDeepAgent({ name: v, model: "openai:gpt-5.5" } as any);
    console.log(`  ${label.padEnd(8)} -> 运行时放行，config.name =`, r.config.name);
  } catch (e) {
    console.log(`  ${label.padEnd(8)} -> 运行时抛:`, (e as Error).message.slice(0, 90));
  }
}
function nameFactory() {
  return defineDeepAgent({ name: "ts-factory", model: "openai:gpt-5.5" });
}
console.log("  工厂函数内 ->", nameFactory().config.name, "（运行时放行；mda build 是否求值另测）");

line("6. defineSandbox");
const sb = defineSandbox({ idleTtlSeconds: 600, defaultTimeout: 600 });
console.log("constructor:", sb?.constructor?.name);
console.log("keys       :", Object.keys(sb as any));
console.log("JSON       :", JSON.stringify(sb));

line("7. defineMemory / memoryLayer");
console.log("defineMemory 类型:", typeof defineMemory, "| arity:", defineMemory.length);
console.log("memoryLayer 类型:", typeof memoryLayer, "| arity:", memoryLayer.length);

line("8. defineIdentity");
console.log("defineIdentity 类型:", typeof defineIdentity, "| arity:", defineIdentity.length);

line("9. defineSchedule / schedules");
console.log("defineSchedule 类型:", typeof defineSchedule, "| arity:", defineSchedule.length);
console.log("schedules 导出:", typeof schedules, schedules && Object.keys(schedules as any).join(","));

line("10. defineMcp");
console.log("defineMcp 类型:", typeof defineMcp, "| arity:", defineMcp.length);

line("11. channels");
console.log("channels 键:", Object.keys(channels as any).join(","));
for (const k of Object.keys(channels as any)) {
  const fn = (channels as any)[k];
  console.log(`  channels.${k}: typeof=${typeof fn}, arity=${fn?.length}`);
}
