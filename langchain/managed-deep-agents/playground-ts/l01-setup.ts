/**
 * 课 1 · 环境准备（TypeScript 侧）
 *
 * 对应课文：stages/1-定位与起跑/lessons/01-环境准备.md
 * 这一课不调模型、不联网，只确认三件事：
 *   ① managed-deepagents 装对了、版本是 0.9.5
 *   ② defineDeepAgent 能返回一个"定义"，而不是已编译的 agent
 *   ③ mda CLI 在 PATH 里（deploy 之外的动作都不需要账号）
 */

import { defineDeepAgent } from "managed-deepagents";
import { readFileSync } from "node:fs";
import { section, show, showConfigKeys, hasKey } from "./_shared.ts";

section("实验 1", "包与版本");

// 读包元信息里的版本——版本号是 public beta 期最易变的东西，不该硬编码。
// 注意：该包的 exports 没有开放 "./package.json"，所以只能走文件路径读。
const pkg = JSON.parse(
  readFileSync(
    new URL("./node_modules/managed-deepagents/package.json", import.meta.url),
    "utf8",
  ),
) as { version: string };
show("managed-deepagents", pkg.version);
show("Node.js", process.version);
show("平台", `${process.platform}/${process.arch}`);

section("实验 2", "defineDeepAgent 返回的是定义，不是 agent");

const agent = defineDeepAgent({
  name: "my-agent-ts",
  model: "openai:gpt-5.5",
});

show("constructor", agent.constructor.name);
show("kind", agent.kind);
show("Object.keys", Object.keys(agent));

console.log("\n  三个最关键的存在性检查：");
show("typeof agent.invoke", typeof (agent as Record<string, unknown>).invoke);
show("typeof agent.stream", typeof (agent as Record<string, unknown>).stream);
show("typeof agent.config", typeof agent.config);

console.log(`
  读法：kind === "deep-agent" 说明拿到了定义；
  invoke / stream 都是 undefined，说明它不能直接被调用——
  这正是托管版与直连 deepagents 的根本差别（课 2 展开）。
`);

section("实验 3", "config 的键集合：省略 = 键不存在");

showConfigKeys(agent.config);
show('"name" in config', hasKey(agent.config, "name"));
show('"tools" in config', hasKey(agent.config, "tools"));
show('"model" in config', hasKey(agent.config, "model"));

console.log(`
  这里没有传 tools，于是 config 里连 "tools" 这个键都没有。
  JS 侧硬取得到 undefined（不像 Python 抛 KeyError），
  所以判断"有没有配"要用 'key' in obj，不能用 === undefined。
`);

section("实验 4", "mda CLI 是否可用");

// 只检查 bin 是否解析得到，不真的执行（执行留给课 3 的 build）
const { execFileSync } = await import("node:child_process");
try {
  const out = execFileSync("mda", ["--version"], { encoding: "utf8" }).trim();
  show("mda --version", out);
} catch {
  show("mda --version", "未找到 mda，请先 npm install");
}

console.log(`
  能打出版本号就够了。deploy 需要 LangSmith 账号与模型额度，
  本课与后续本地实验都不碰它。
`);

section("完成", "课 1 自检通过");
