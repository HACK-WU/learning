/**
 * 课 3 · 第一个可部署项目（TypeScript 侧）
 *
 * 对应课文：stages/1-定位与起跑/lessons/03-第一个可部署项目.md
 *
 * 本课最值得实测的是「跨语言不对称」：
 *   Python 侧 name 必须是静态字符串字面量（工厂函数体里有 if/try 就报错）
 *   TS 侧 name 可以是 const 变量、甚至模板字符串，`mda build` 都能解析
 * 这个差异只靠读文档发现不了，必须真跑一遍 build。
 */

import { defineDeepAgent } from "managed-deepagents";
import { section, step, show, showConfigKeys, attempt } from "./_shared.ts";

// ── 实验 1：最小可部署项目的形状 ────────────────────────────────
section("实验 1", "一个最小项目由什么组成");

console.log(`
  my-agent/
  ├── agent.ts            ← 入口，导出定义
  ├── instructions.md     ← 系统提示（可选，缺了 build 会警告）
  ├── tools/              ← 普通模块，必须被 agent.ts import
  │   └── mcp.ts          ← 保留名，MCP 声明
  ├── skills/             ← 技能，自动发现
  ├── sandbox/            ← 沙箱声明
  ├── memory.ts           ← 记忆声明
  └── package.json
`);

// ── 实验 2：TS 侧 name 的宽松度 ─────────────────────────────────
section("实验 2", "TS 侧 name 可以为变量（与 Python 不对称）");

step("三种写法");

const AGENT_NAME = "ts-var-name";
const templateName = `ts-tpl-${1}`;

show("① 字面量", defineDeepAgent({ name: "ts-literal", model: "openai:gpt-5.5" }).config.name);
show("② const 变量", defineDeepAgent({ name: AGENT_NAME, model: "openai:gpt-5.5" }).config.name);
show("③ 模板字符串", defineDeepAgent({ name: templateName, model: "openai:gpt-5.5" }).config.name);

console.log(`
  三种在运行时全部通过。所以「必须是静态字符串」这条约束
  在 TS 侧是 mda build 静态扫描的事，不是 defineDeepAgent 的事。

  ⚠️ 但别高兴太早：本工程实测 mda build 对 ②③ 都能解析出正确 name
     （产物 langgraph.json 里就是解析后的值），对"工厂函数里返回"才报错。
     具体见下方实验 3。
`);

// ── 实验 3：工厂入口 mode 的限制 ────────────────────────────────
section("实验 3", "工厂入口 mode：什么时候会报静态扫描错");

console.log(`
  mda build 读 name 有两条路：
    路 A（静态入口）：直接 export const agent = defineDeepAgent({...})
                     → 从源码里扫 name 字面量，变量也能解析
    路 B（工厂入口）：export function agent(runtime) { return defineDeepAgent({...}) }
                     → 需要 name 是内联字符串字面量

  实测（临时目录起三个最小项目，同一份 0.9.5 CLI）：
    literal/   name: "scan-literal"   → build 成功
    varref/    name: NAME             → build 成功，产物 name = scan-var
    factory/   name: "scan-factory"   → build 失败：
               agent \`name\` is required in agent.ts. Add a static string ... to defineDeepAgent(...)

  反直觉的点：factory 里写的明明就是字符串字面量，照样报错。
  原因不是"字面量不够静态"，而是工厂 mode 下 CLI 不去执行工厂，
  所以任何在函数体里的 defineDeepAgent 调用都读不到 name。
`);

attempt("模拟工厂入口的写法（运行时是通的，build 才拦）", () => {
  function buildAgent() {
    return defineDeepAgent({ name: "ts-factory", model: "openai:gpt-5.5" });
  }
  return buildAgent().config.name;
});

// ── 实验 4：build 产物里有什么 ─────────────────────────────────
section("实验 4", "mda build 产物清单");

console.log(`
  实测 .mda/build/ 下有：
    _mda_entry.ts       生成的入口，把定义交给托管运行时
    agent.ts            你写的 agent 文件（被拷进来）
    langgraph.json      路由表：{"graphs": {"<name>": "./_mda_entry.ts:agent"}}
    package.json        依赖清单
    package-lock.json   锁定
    .mda-build          build 元信息
    __runtime__/        托管运行时（平台侧代码）
`);

step("langgraph.json 里 name 的落值（变量写法也能正确解析）");
console.log(`
  varref 项目（name 传 const 变量）的产物：
    "graphs": { "scan-var": "./_mda_entry.ts:agent" }
  说明 CLI 确实求值了那个变量，而不是拿不到就糊一个默认名。
`);

// ── 实验 5：export 名必须叫 agent ─────────────────────────────
section("实验 5", "入口导出的名字有约定（实测报错很坑）");

console.log(`
  约定：静态入口的导出名必须是 agent。
  实测把导出改成 const renamed = defineDeepAgent(...) 后：

    $ npx mda build .
    error: agent \`name\` is required in agent.ts. Add a static string
           (e.g. name: "research-assistant") to defineDeepAgent(...)

  ⚠️ 注意这个报错的误导性：它说"缺 name"，但你明明写了 name。
  真正的原因是 CLI 只认 \`agent\` 这个导出名，找不到就当"没声明"，
  于是顺着"没声明"报成"缺 name"。

  排查口诀：mda build 报缺 name，先确认导出名是不是 agent，
  再确认 name 有没有写在工厂函数体里——两个原因共用同一句报错。
`);

const good = defineDeepAgent({ name: "research-assistant", model: "openai:gpt-5.5" });
showConfigKeys(good.config, "正确写法 config keys");

section("完成", "课 3 实测结束");
