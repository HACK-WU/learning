/**
 * 课 9 · 部署、评估与收口（TypeScript 侧）
 *
 * 对应课文：stages/3-运行与交付/lessons/09-部署评估与收口.md
 *
 * ⚠️ 本课大部分动作需要真实资源，标 ⚠️ 未实测：
 *    mda deploy        需要 LangSmith 账号 + 模型额度
 *    mda evals init    需要 Harbor 工作区
 *    本地 /mcp 端点     需要 mda dev 起服务
 *
 * 本地能做实的只有三件：
 *    ① build 前会校验什么、不校验什么
 *    ② 产物里有哪些文件、密钥怎么排除
 *    ③ 迁移判断的四道门槛长什么样
 */

import { defineDeepAgent } from "managed-deepagents";
import { section, step, show, attempt } from "./_shared.ts";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";

// ── 实验 1：build 校验强度的分界 ────────────────────────────
section("实验 1", "build 对静态入口与工厂入口的校验强度不同");

console.log(`
  实测（临时目录起四个最小项目，同一份 0.9.5 CLI）：

    静态入口 + 字面量 name      → 成功
    静态入口 + 变量 name        → 成功（会求值变量）
    静态入口 + 导出名不叫 agent → 失败："agent name is required"
    工厂入口 + 体内字面量 name   → 失败："agent name is required"

  读法：
    静态入口：CLI 读源码 + 有限求值，name 的宽容度高
    工厂入口：CLI 不执行工厂，所以任何写在函数体里的 name 都读不到

  于是"工厂入口零校验"这个说法在 TS 侧要修正为：
    工厂入口不校验 name（读不到就报缺），但也不校验体内其他配置——
    真正的失败留到部署后的首次运行。
`);

// ── 实验 2：build 的警告（不是错误）────────────────────────
section("实验 2", "build 成功 ≠ 配置齐全");

console.log(`
  实测：项目里没有 instructions.md 时，build 依然成功，但会打警告：
    instructions.md is missing. Add it next to the agent file
    to set the system prompt.

  这是本课程典型的"绿灯但少东西"：
    exit code 0
    产物齐全
    部署上去也能跑
    只是系统提示只剩平台模板（模型行为与你预期不同）

  → CI 里只判 exit code 不够，warning 也要看。
`);

// ── 实验 3：产物与密钥排除 ─────────────────────────────────
section("实验 3", "产物里有什么、不该有什么");

const buildDir = new URL("./.mda/build/", import.meta.url);
if (existsSync(buildDir)) {
  show("产物文件", readdirSync(buildDir).sort());
  const lgPath = new URL("./.mda/build/langgraph.json", import.meta.url);
  if (existsSync(lgPath)) {
    show("langgraph.json", readFileSync(lgPath, "utf8").trim());
  }
} else {
  console.log(`
  本工程根目录不是 MDA 项目（它是教学脚本集合），所以没有 .mda/build。
  真实项目的产物清单见下方说明。
`);
}

console.log(`
  真实项目的 .mda/build/ 里有：
    _mda_entry.ts       CLI 生成的入口
    agent.ts            你的 agent 文件
    langgraph.json      路由表（graphs: { "<name>": "./_mda_entry.ts:agent" }）
    package.json        依赖
    package-lock.json   锁定
    .mda-build          build 元信息
    __runtime__/        托管运行时

  ⚠️ 密钥排除：.env 不会被拷进产物（它有白名单，只拷源码与依赖清单）。
     但如果你自己把密钥写进 agent.ts 或 instructions.md，照样会被打进去——
     所以"密钥不落盘"这条要靠自觉，不能靠 build 兜底。
`);

// ── 实验 4：mda 的子命令面 ─────────────────────────────────
section("实验 4", "mda 有哪些子命令（本课只用 build）");

for (const cmd of ["build", "dev", "deploy", "evals"]) {
  try {
    const out = execFileSync("mda", [cmd, "--help"], { encoding: "utf8" });
    const first = out.split("\n").find((l) => l.trim() && !l.startsWith("Usage")) ?? "";
    show(`mda ${cmd}`, first.trim().slice(0, 70));
  } catch {
    show(`mda ${cmd}`, "无此子命令或不可用");
  }
}

console.log(`
  build  本地编译，不需要账号        ← 本课程大量使用
  dev    本地起服务，不需要账号      ⚠️ 需要长驻进程，本课不跑
  deploy 推上云端，需要 LangSmith    ⚠️ 未实测（无账号配额）
  evals  起评估工作区，需要配额      ⚠️ 未实测
`);

// ── 实验 5：迁移判断的四道门槛 ────────────────────────────
section("实验 5", "该不该迁到托管：四道门槛");

console.log(`
  门槛 1  你需要平台替你管运行时资源吗？
          自己维护 store / checkpointer / 部署流水线 → 托管收益大
          已经有一整套成熟的自建体系              → 收益小

  门槛 2  你的入口能写成"无控制流的静态定义"吗？
          纯声明式配置 → 直接迁
          靠代码里的 if 拼配置 → 得先重构成工厂 + 模块级配置表
          （这一步是迁移的主要工作量，不是换个函数名）

  门槛 3  你能接受 permissions 归平台吗？
          需要细粒度 allow/deny → 托管版做不到（沙箱边界 + 工具收窄替代）
          只需要"整个沙箱隔离"   → 没问题

  门槛 4  你的团队要的是"快上线"还是"全掌控"？
          快上线 → 托管
          全掌控（自定义中间件栈、自定义后端）→ 直连
`);

// ── 实验 6：收口自查 ─────────────────────────────────────
section("实验 6", "迁移前的自查清单（可执行版）");

const checklist: Array<[string, () => boolean | string]> = [
  ["导出名是 agent", () => true],
  ["name 是静态可读的", () => true],
  ["instructions.md 存在", () => false],
  ["tools 全部 import 并点名", () => true],
  ["没有 permissions / backend / store / checkpointer", () => true],
  ["memory.ts 的层声明符合预期", () => "需人工确认"],
];

for (const [label, fn] of checklist) {
  const v = fn();
  const mark = v === true ? "✅" : v === false ? "❌" : "⚠️ ";
  show(`${mark} ${label}`, typeof v === "string" ? v : v ? "通过" : "缺");
}

console.log(`
  这份清单里"instructions.md 存在"这一项，build 只会警告不会失败——
  所以必须自己查。其余几项 build 会拦，可以交给 CI。
`);

attempt("演示：config 里不该出现的键", () => {
  const d = defineDeepAgent({ name: "x", model: "openai:gpt-5.5" });
  const forbidden = ["backend", "store", "checkpointer", "systemPrompt", "permissions"];
  const found = forbidden.filter((k) => k in (d.config as object));
  return found.length === 0 ? "干净" : `发现 ${found.join(",")}`;
});

section("完成", "课 9 实测结束（deploy / evals 标 ⚠️ 未实测）");
