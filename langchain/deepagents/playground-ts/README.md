# Deep Agents 课程 · TypeScript 实操工程

> 本目录是《Deep Agents》教材 TypeScript 侧的**可运行配套工程**：课文里每个 `::: code-group` 的 `[TypeScript]` 标签页，对应这里一个 `lNN-*.ts`。
> Python 侧是主线，这里是平行线——两侧内容一一对应，挑自己用得上的一侧读即可。

## 为什么单独建一个工程

课文的 TS 代码块是**教学片段**（去掉 import、省掉无关分支），照抄进编辑器跑不起来。本工程负责把片段拼回**完整可执行文件**，并保证两件事：

- `npm run check` 能过（`tsc --noEmit`，`strict: true`）
- `npm run lNN` 能跑（真实执行，输出存成 `lNN-ts-output.txt`）

课文里凡是标 `🇹🇸` 的实测结论，都是这些脚本真实跑出来的。

## 环境准备

| 项 | 版本 | 说明 |
|----|------|------|
| Node.js | `>=20`（实测 `22.22.2`） | LangGraph JS 的运行时要求 |
| `deepagents` | `^1.15.1` | TS 版入口是 `createDeepAgent`（注意：与 Python 的 `0.7.28` **版本号独立演进**，不要对着 0.7 去 npm 找） |
| `@langchain/core` | `^1.2.20` | 与 `deepagents` 的 peer 要求一致 |
| `@langchain/langgraph` | `^1.5.1` | 运行时 |
| `@langchain/openai` | `^1.6.2` | 走 OpenAI 兼容端点必需 |
| `@langchain/quickjs` | `^0.6.5` | 课 6 / 课 12 的解释器与动态子代理 |
| `zod` | `^4.6.7` | 自定义工具的参数 schema |

版本已固定在 `package.json`，直接装即可：

```bash
cd langchain/deepagents/playground-ts
npm install
```

> ⚠️ 与 Python 侧最大的不同：TS 的 `deepagents` 把 Anthropic 也列为 **peer** 而不是核心依赖，所以**开箱不会自动获得任何模型集成**。必须显式装 `@langchain/openai` 或 `@langchain/anthropic`。

## 配凭据

```bash
cp .env.example .env
```

`.env` 已被 `.gitignore` 排除。查找顺序是「本目录 `.env` → 兄弟教程 `../playground/.env`」，所以本机已有 `langchain/playground/.env` 的话可以跳过这步。

课程默认走百炼的 OpenAI 兼容端点（对齐 LangChain 教程口径，成本低）；要验证官方默认行为，把 `DEEPAGENTS_MODEL` 改成 `anthropic:claude-sonnet-4-6`。

## 怎么跑

```bash
npm run check        # tsc --noEmit，全工程类型检查
npm run l01          # 课 1 环境自检（不调模型、不联网）
npm run l08          # 课 8 Memory
```

13 个脚本与课文的对应关系：

| 命令 | 文件 | 对应课文 | 输出存档 |
|------|------|---------|---------|
| `npm run l01` | `l01-setup.ts` | 课 1 环境准备 | `l01-ts-output.txt` |
| `npm run l02` | `l02-what.ts` | 课 2 Deep Agents 是什么 | `l02-ts-output.txt` |
| `npm run l03` | `l03-first-agent.ts` | 课 3 第一个 deep agent 与默认装配 | `l03-ts-output.txt` |
| `npm run l04` | `l04-tools-vfs.ts` | 课 4 工具与虚拟文件系统 | `l04-ts-output.txt` |
| `npm run l05` | `l05-backends-permissions.ts` | 课 5 Backends 与 Permissions | `l05-ts-output.txt` |
| `npm run l06` | `l06-sandbox-interpreter.ts` | 课 6 沙箱与解释器 | `l06-ts-output.txt` |
| `npm run l07` | `l07-skills.ts` | 课 7 Skills 技能 | `l07-ts-output.txt` |
| `npm run l08` | `l08-memory.ts` | 课 8 Memory 记忆 | `l08-ts-output.txt` |
| `npm run l09` | `l09-context-engineering.ts` | 课 9 上下文工程 | `l09-ts-output.txt` |
| `npm run l10` | `l10-subagents.ts` | 课 10 任务规划与子代理 | `l10-ts-output.txt` |
| `npm run l11` | `l11-hitl.ts` | 课 11 人在环中 | `l11-ts-output.txt` |
| `npm run l12` | `l12-async-subagents.ts` | 课 12 异步与动态子代理 | `l12-ts-output.txt` |
| `npm run l13` | `l13-production.ts` | 课 13 生产化：容错、流式与上线 | `l13-ts-output.txt` |

大部分脚本用**桩模型**（自定义 `BaseChatModel` 子类）代替真实模型，所以不花钱、不联网也能跑出可复现的结论。真正调用模型的段落会明确标注。

## 两侧差异看哪里

跨语言差异共 58 条，全部沉淀在 [`API-MAPPING.md`](./API-MAPPING.md)：

- 第一节是 `create_deep_agent` / `createDeepAgent` 的**参数映射表**（哪些是驼峰、哪几个是单侧独有）
- 第二节起是逐条差异，每条都带「表现 → 原因 → 怎么写才不踩」
- 最容易静默失效的几条：`FileData` 结构两侧必填字段互换、`permissions` 无 `interrupt` 档、`batched` 混合决策丢调用、`graphId` 才是异步分流开关

## 几条硬约束（写新脚本时会撞上）

- 自定义模型必须 `constructor() { super({}); }`、`_llmType()` 是**方法**不是 getter、要显式实现 `bindTools()`、`_generate` 返回 `{ generations: [{ text, message }] }`
- `createDeepAgent` 同步返回 `ReactAgent`（官方示例常带 `await`，加了也无害）
- 没有 `agent.nodes`，中间件栈从 `agent.options.middleware` 读
- `tsconfig` 是 `NodeNext`，相对导入要写 `.js` 后缀（如 `import { section } from "./_shared.js"`）

## 说明

- 本工程只覆盖**课文 13 课 + 应用实战 10 篇**的代码；`源码解析/` 6 篇不纳入（TS 包被 bundle 成哈希文件名，逐行对照无意义）
- `lNN-ts-output.txt` 是某次真实运行的存档，不是承诺值——Node / 包版本变化后数字可能微调，但结论方向稳定
