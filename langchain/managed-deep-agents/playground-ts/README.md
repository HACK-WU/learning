# Managed Deep Agents 课程 · TypeScript 实操工程

> 本目录是《Managed Deep Agents》教材 TypeScript 侧的**可运行配套工程**：课文里每个 `::: code-group` 的 `[TypeScript]` 标签页，对应这里一个 `lNN-*.ts`。
> Python 侧是主线，这里是平行线——两侧内容一一对应，挑自己用得上的一侧读即可。

## 为什么单独建一个工程

课文的 TS 代码块是**教学片段**（去掉 import、省掉无关分支），照抄进编辑器跑不起来。本工程负责把片段拼回**完整可执行文件**，并保证两件事：

- `npm run check` 能过（`tsc --noEmit`，`strict: true`）
- `npm run lNN` 能跑（真实执行，输出存成 `lNN-ts-output.txt`）

课文里凡是标 `🇹🇸` 的实测结论，都是这些脚本真实跑出来的。**没跑过的不写。**

## 环境准备

| 项 | 版本 | 说明 |
|----|------|------|
| Node.js | `>=20`（实测 `22.22.2`） | `tsx` 与 ESM 解析需要 |
| `managed-deepagents` | `^0.9.5` | **与 Python 侧同为 0.9.5**（这一点与 deepagents 教程不同，那边的两侧版本号独立演进） |
| `typescript` | `^7.0.2` | 严格模式 |
| `tsx` | `^4.23.15` | 直接跑 `.ts`，不用先编译 |

```bash
cd langchain/managed-deep-agents/playground-ts
npm install
```

> 与 deepagents 教程最大的不同：`managed-deepagents` 把 `deepagents`、`@langchain/core`、`@langchain/langgraph`、`@langchain/mcp-adapters` **全部列为直接依赖**，所以装一个包就够了，不用再手动补 peer。它也自带 `mda` CLI（`bin/mda.mjs`）。

### 不需要凭据

本工程**九课全部不需要 API key、不需要 LangSmith 账号、不联网**。原因是 MDA 的核心验证面在「定义期」——`defineDeepAgent` 返回的是配置声明，不是已编译的图，所以键集合、校验强度、报错文本这些都能在本地实测。

需要真资源的只有两处，课文与脚本里都标了 `⚠️ 未实测`：

- `mda deploy`（需 LangSmith 账号 + 模型额度）
- `mda evals init`（需 Harbor 工作区）

## 怎么跑

```bash
npm run check    # tsc --noEmit，全工程类型检查
npm run l01      # 课 1 环境自检
npm run l07      # 课 7 运行时上下文
```

九个脚本与课文的对应关系：

| 命令 | 文件 | 对应课文 | 输出存档 |
|------|------|---------|---------|
| `npm run l01` | `l01-setup.ts` | 课 1 环境准备 | `l01-ts-output.txt` |
| `npm run l02` | `l02-what.ts` | 课 2 托管的是什么 | `l02-ts-output.txt` |
| `npm run l03` | `l03-first-agent.ts` | 课 3 第一个可部署项目 | `l03-ts-output.txt` |
| `npm run l04` | `l04-tools-skills.ts` | 课 4 指令、技能与工具 | `l04-ts-output.txt` |
| `npm run l05` | `l05-middleware-mcp.ts` | 课 5 中间件、MCP 与检索 | `l05-ts-output.txt` |
| `npm run l06` | `l06-memory-sandbox.ts` | 课 6 记忆、沙箱与身份 | `l06-ts-output.txt` |
| `npm run l07` | `l07-runtime-context.ts` | 课 7 运行时上下文 | `l07-ts-output.txt` |
| `npm run l08` | `l08-channels-schedules.ts` | 课 8 通道与调度 | `l08-ts-output.txt` |
| `npm run l09` | `l09-deploy-evals.ts` | 课 9 部署、评估与收口 | `l09-ts-output.txt` |

另有 `npm run probe`（`probe-api.ts`）：枚举包的全部导出、实测 `defineDeepAgent` 的入参校验面。改课文前先跑它，避免凭记忆写。

## 跨语言差异：八条会静默失效的地方

这是本工程最该先读的一节。八条**全部有实测依据**，其余细节见 [API-MAPPING.md](./API-MAPPING.md)。

### 1. 缺键的读法不同：Python 抛 `KeyError`，JS 得 `undefined`

```python
d = define_deep_agent(name="x", model="openai:gpt-5.5")
"tools" in d.config      # False
d.config["tools"]        # KeyError: 'tools'
d.config.get("tools")    # None
```

```typescript
const d = defineDeepAgent({ name: "x", model: "openai:gpt-5.5" });
"tools" in d.config      // false
(d.config as any).tools  // undefined —— 不抛
```

**推论**：JS 侧判断「有没有配」必须用 `'key' in obj`。用 `=== undefined` 判断会把「显式传了 `undefined`」也算成「没配」。Python 侧的排查代码直接搬到 JS 会静默变成「永远是 undefined」，看起来像「配了但为空」。

### 2. 托管自有键：Python 靠类型与文档，JS 是运行时硬失败

`backend` / `store` / `checkpointer` / `systemPrompt` / `disableMemory` 在 TS 类型层是 `never`，但**绕过类型（`as any`）后运行时仍会抛错**，且报错直接告诉你该挪去哪：

```text
Remove `backend` from defineDeepAgent(...). Configure the sandbox in sandbox/.
Remove `checkpointer` from defineDeepAgent(...). MDA provides the checkpointer automatically.
Remove `systemPrompt` from defineDeepAgent(...). Use `instructions` in a factory entrypoint
  or put the static prompt in instructions.md.
```

实测五组全部抛错。所以 JS 侧「我绕过了类型为什么还炸」不是 bug，是双保险。

### 3. `skills` / `mcp` 的拒绝发生在 `mda build`，不在运行时

这条最容易骗过本地自测：

```typescript
// 运行时不报错，config 里也有 skills 这个键
defineDeepAgent({ name: "x", model: "openai:gpt-5.5", skills: ["./skills/demo"] });
```

真跑 `mda build` 才拦：

```text
error: agent.ts: Remove `skills` from defineDeepAgent(...).
       Use a factory entrypoint to select skills per run; static agents use skills/.
```

类型注释写着「静态入口不能设这些字段」，但类型系统并没有强制。**自测只跑 `tsx` 会漏掉这一类。**

### 4. `ManagedToolRuntime` 的泛型是 `<TState, TContext>`，只写一个就塌

```typescript
// ✅ 正确
tool(async ({ orderId }, runtime: ManagedToolRuntime<unknown, AppContext>) => {
  return runtime.context?.region;   // AppContext 的字段拿得到
}, {...});

// ❌ 错误：AppContext 落进 TState 槽，TContext 保持默认 {}
tool(async ({ orderId }, runtime: ManagedToolRuntime<AppContext>) => {
  return runtime.context?.region;   // TS2339: Property 'region' does not exist on type '{}'
}, {...});
```

`tsc` 会抓到，但标 `any` 或关 `strict` 就会滑到运行时。**注意这与 Python 侧 `[Context, State]` 的顺序相反**——两侧泛型顺序正好颠倒，是本课程最易错的一条。

### 5. `name` 的宽容度不对称

| 写法 | Python | TypeScript |
|------|--------|------------|
| 字面量 | ✅ | ✅ |
| const 变量 | ❌（工厂体有控制流即报错） | ✅（`mda build` 会求值） |
| 模板字符串 | ❌ | ✅ |
| 工厂函数体内 | 需内联字面量 | ❌（CLI 不执行工厂，读不到） |

实测 `mda build` 对变量写法能正确解析出 name（产物 `langgraph.json` 里就是解析后的值）。

### 6. 导出名不叫 `agent` 时，报错是「缺 name」

```text
error: agent `name` is required in agent.ts. ...
```

但你明明写了 name。真正原因是 CLI 只认 `agent` 这个导出名，找不到就当「没声明」，于是顺着「没声明」报成「缺 name」。

**排查口诀**：`mda build` 报缺 name，先看导出名是不是 `agent`，再看 name 有没有写在函数体里——两个原因共用同一句报错。

### 7. TS 的 `memoryLayer({ allow })` 已废弃、且参数是联合类型（Python 侧两者都不成立）

```text
@deprecated Select memory from a dynamic agent definition instead.
            This callback will be removed in a future release.
```

回调参数不是 `AppContext` 本身，是 `ManagedRunContext<AppContext> = AppContext | ManagedChannelContext` 的**联合类型**，直接取字段会被 `tsc` 拒。正确写法是先判 `in`：

```typescript
allow: (context) => "remember" in context && context.remember === true
```

**Python 侧对照**（同一版本 0.9.5）：`MemoryLayer.allow` 的标注是 `Callable[[ContextT], bool | Awaitable[bool]]`，**既没有联合类型、也没有 `@deprecated`**。所以 Python 里 `context.get("remember") is True` 是合法的正式写法。

这就是「两侧版本号相同 ≠ API 面相同」的典型例子：同一个 0.9.5，TS 的这条已进入废弃通道，Python 的没有。

未来的统一写法是在工厂入口挑 memory 定义（`memory: null` 关掉 / `memory: def` 挂上），这条路两侧都支持。

### 8. 校验强度在同一个包里并不一致

| 能力 | 类型层 | 运行时 | `mda build` |
|------|--------|--------|-------------|
| 托管自有键（backend 等） | 拒绝（`never`） | **抛错** | — |
| sandbox 的 `snapshotName` + `dockerImage` 互斥 | 拒绝 | **抛错** | — |
| `skills` / `mcp` 在静态入口 | 放过 | 放过 | **抛错** |
| 通道缺 `parse`、`verify` 返回非布尔 | 放过 | 放过 | 放过（静默） |
| `provider: ""` | 放过 | **抛错** | — |
| 缺 `instructions.md` | — | — | **只警告**（exit 0） |

所以「本地跑通了」这句话，在这个包里必须追问一句「在哪一层跑通的」。

## 目录约定

```text
playground-ts/
├── _shared.ts                   公共打印工具（section / show / attempt）
├── probe-api.ts                 包导出与校验面枚举（改课文前先跑）
├── l01-setup.ts ... l09-*.ts    九课脚本
├── l01-ts-output.txt ...        对应输出存档
├── API-MAPPING.md               Python ↔ TS 逐项对照表
├── tsconfig.json                strict + allowImportingTsExtensions
└── package.json                 每课一个 npm run
```

`allowImportingTsExtensions` 是必须的：脚本按真实运行方式 `import "./_shared.ts"`，不开这个选项 `tsc` 会报 TS5097。

## 一句提醒

MDA 处于 public beta（0.9.5，2026-10-23 构建）。本工程所有结论都锚定这个版本，升级后请先跑 `npm run probe` 复核，再改课文——尤其是第 7 条那个已废弃的 `allow`，它明说了「will be removed in a future release」。
