# Python ↔ TypeScript API 对照表

> 锚定版本：`managed-deepagents 0.9.5`（Python 分发名 `managed-deepagents`，TS 包名 `managed-deepagents`，**两侧同版本号**）。
> Python 侧为课文主线，本表按"能力 → 两侧写法 → 差异"组织，每条差异都标了实测方式。
> 图例：`✅ 已验证` 本工程真实跑过 ／ `📖 文档` 仅文档说明未实测 ／ `⚠️ 未实测` 需云端资源

## 一、入口函数

| 能力 | Python | TypeScript | 差异 |
|------|--------|------------|------|
| 定义 agent | `define_deep_agent(name=..., model=...)` | `defineDeepAgent({ name, model })` | 参数形态：关键字参数 vs 单个对象 |
| 返回值类型 | `DeepAgentDefinition` | `DeepAgentDefinition<TConfig>` | TS 带泛型保留 config 形状 |
| 返回值形状 | `{ kind, config }` | `{ kind: "deep-agent", config, "~agentTypes", "~deepAgentTypes" }` | TS 多两个 phantom 类型品牌（运行时 `Object.keys` 只看到 `kind`/`config`）✅ |
| 是否可直接调用 | 否 | 否 | 两侧 `invoke`/`stream` 均为 `undefined` ✅ |
| 显式参数个数 | 18 + `**kwargs` | 见 `DefineDeepAgentConfig`（`createDeepAgent` 全量面去掉 MDA 自有键） | Python 是固定签名，TS 是类型交叉 |

## 二、config 的键语义

| 情形 | Python | TypeScript | 差异 |
|------|--------|------------|------|
| 省略 `tools` | `"tools" in config` → `False`；`config["tools"]` → `KeyError` | `"tools" in config` → `false`；`config.tools` → `undefined` | **读法必须改**：JS 不抛，只能用 `in` 判存在 ✅ |
| `tools=[]` | 键存在、值为 `[]` | 键存在、值为 `[]` | 一致 ✅ |
| 安全读法 | `config.get("tools")` → `None` | `config.tools` → `undefined`（但无法区分"没配"与"传了 undefined"） | Python 的 `get` 语义更精确 ✅ |
| `instructions` | 可传，进 config | 可传，进 config | 一致 ✅ |
| `context_schema` | 可传，进 config | `contextSchema`（驼峰） | 命名风格差异 📖 |
| `response_format` | 可传 | `responseFormat` | 命名风格差异 📖 |

## 三、托管自有键（作者不可设）

| 键 | Python 侧表现 | TypeScript 侧表现 |
|----|--------------|------------------|
| `backend` | 类型标注 + 文档提示 | 类型 `never`；绕过类型后运行时抛 `Remove \`backend\` ... Configure the sandbox in sandbox/.` ✅ |
| `store` | 同上 | 运行时抛 `MDA provides the store automatically.` ✅ |
| `checkpointer` | 同上 | 运行时抛 `MDA provides the checkpointer automatically.` ✅ |
| `systemPrompt` | 同上 | 运行时抛 `Use \`instructions\` in a factory entrypoint or put the static prompt in instructions.md.` ✅ |
| `disableMemory` | 已移除 | 运行时抛 `disableMemory is no longer supported ... Durable memory is opt-in and declared in memory.ts` ✅ |

> TS 侧这五条是**双保险**：类型层 `never` + 运行时抛错。Python 侧主要靠类型标注与文档，强度弱一档。

## 四、工厂入口与静态入口

| 能力 | 静态入口 | 工厂入口 | 差异 |
|------|---------|---------|------|
| 入口形态（Py） | `agent = define_deep_agent(...)` | `def agent(runtime): return define_deep_agent(...)` | — |
| 入口形态（TS） | `export const agent = defineDeepAgent(...)` | `export function agent(runtime) { return defineDeepAgent(...) }` | — |
| 导出名要求 | `agent` | `agent` | 两侧一致；TS 侧导出名错时报「缺 name」而非「找不到入口」✅ |
| `name` 静态要求 | 函数体含 `if`/`try`/`for`/`while`/`with`/`assert`/`del` 即报 `must be a static string literal` | CLI 不执行工厂，体内 `name` 一律读不到 → 报「缺 name」✅ | **报错理由不同** |
| `name` 可为变量 | 否 | 是（`mda build` 会求值，产物 `langgraph.json` 里是解析后的值）✅ | 最反直觉的一条 |
| `skills` | 静态入口不可设 | 静态入口运行时放过，`mda build` 抛 `Remove \`skills\` ... Use a factory entrypoint` ✅ | 拒绝层级不同 |
| `mcp` | 同上 | 同上（推测同 `skills`）📖 | — |
| `instructions` | 工厂入口可覆盖 `instructions.md` | 同 | — |
| `memory` | 工厂入口可传 `null` 关掉 | 同 | — |

## 五、工具（tools）

| 能力 | Python | TypeScript | 差异 |
|------|--------|------------|------|
| 装饰器/工厂 | `@tool` | `tool(fn, { name, description, schema })` | TS 是显式对象 |
| 参数 schema | 类型注解 + docstring | `z.object({...})`（zod） | — |
| 工具名来源 | 函数名（可覆盖） | `name` 字段（与变量名无关）✅ | 变量叫 `lookupCustomer`、模型看到 `lookup_customer` |
| runtime 注入 | 参数标注 `ManagedToolRuntime[Context]`（泛型 `[Context, State]`） | 第二参数标 `ManagedToolRuntime<TState, TContext>` | **泛型顺序相反** ✅ |
| 只写一个泛型的后果 | — | `AppContext` 进 TState 槽，`runtime.context` 推成 `{}`，`.region` 报 TS2339 ✅ | TS 特有坑 |
| 身份读取 | `runtime.server_info.principal` | `runtime.serverInfo.principal` | 命名风格 |
| 上下文读取 | `runtime.context` | `runtime.context` | 一致 |
| 漏点名（没写进 `tools=`） | config 无该键，硬取 `KeyError` | config 无该键，取到 `undefined` | 表现一致、读法不同 ✅ |

## 六、指令与技能

| 能力 | Python | TypeScript | 差异 |
|------|--------|------------|------|
| 静态系统提示 | `instructions.md`（agent 文件旁） | 同 | 一致 |
| 内联系统提示 | 工厂入口 `instructions=` | 工厂入口 `instructions:` | 一致 |
| 缺 `instructions.md` | build 警告 | `mda build` 警告且 exit 0：`instructions.md is missing. ...` ✅ | 一致：绿灯但少东西 |
| 技能落点 | `skills/{name}/SKILL.md` | 同 | 一致 |
| 技能发现 | 自动 | 自动 | 一致 |
| 静态入口设 `skills` | 不可 | 运行时放过、build 拒 ✅ | 拒绝层级 |
| `null` 语义 | 关掉 | 关掉（`skills: null` 禁用已发现的技能）📖 | 一致 |

## 七、中间件

| 能力 | Python | TypeScript | 差异 |
|------|--------|------------|------|
| 创建 | `@wrap_tool_call` 装饰器 / `AgentMiddleware` 子类 | `createMiddleware({ name, wrapToolCall })` | TS 是对象工厂 |
| 钩子签名 | `(request, handler)` | `(request, handler)` | 一致 |
| 洋葱序 | 嵌套调用 | 同 | 一致 |
| 内置栈位置 | `createDeepAgent` prepend | 同 | 作者中间件永远在内置之后 ✅ |
| `config.middleware` 内容 | 只有作者写的 | 只有作者写的（实测长度 = 作者数量）✅ | 一致 |

## 八、MCP

| 能力 | Python | TypeScript | 差异 |
|------|--------|------------|------|
| 声明函数 | `define_mcp(...)` | `defineMcp({ servers })` | — |
| 传输字段名 | `transport` | `transport`（历史名 `type` 已标 `never`）✅ | 旧写法在类型层就报错 |
| 白名单 | `include_tools` | `includeTools` | 命名风格 |
| 黑名单 | `exclude_tools` | `excludeTools` | 命名风格 |
| 凭据绑定 | `connections.get(slug, { type: "user" })` | 同 ✅ | 一致 |
| 加载失败策略 | `throw_on_load_error` | `throwOnLoadError` ✅ | 一致 |
| 连接时机 | 图构建时 | 图构建时（定义期不联网）✅ | 一致 |
| 返回值形状 | — | `{ kind: "mcp_servers", servers, ... }` ✅ | — |

## 九、记忆

| 能力 | Python | TypeScript | 差异 |
|------|--------|------------|------|
| 声明文件 | `memory.py` | `memory.ts` | 一致 |
| 层声明 | `define_memory(agent=..., user=...)` | `defineMemory({ agent: memoryLayer(), user: memoryLayer() })` | TS 要显式 `memoryLayer()` |
| 省略 = 关闭 | 是 | 是 ✅ | 一致（不是"默认开"） |
| 条件挂载 | `MemoryLayer(allow=...)`，正式 API | `memoryLayer({ allow })`，**已标 `@deprecated`** ✅ | 同版本号、不同废弃状态 |
| `allow` 参数类型 | `Callable[[ContextT], bool]`，**无联合类型** | `ManagedRunContext<AppContext> = AppContext \| ManagedChannelContext`（联合）✅ | TS 直接取字段会被 tsc 拒，要先判 `in`；Python 不需要 |
| 工厂入口开关 | `memory=null` 关闭 | `memory: null` 关闭 📖 | 一致 |
| 废弃后的替代 | 仍可用，也建议迁 | 在工厂入口挑 memory 定义（`memory: null` / `memory: def`）📖 | 两侧都支持，且不依赖 `allow` |

## 十、沙箱与权限

| 能力 | Python | TypeScript | 差异 |
|------|--------|------------|------|
| 声明文件 | `sandbox.py` | `sandbox/index.ts` | 一致 |
| 空闲回收 | `idle_ttl_seconds` | `idleTtlSeconds` ✅ | 命名风格 |
| 默认超时 | `default_timeout` | `defaultTimeout` ✅ | 命名风格 |
| 自定义镜像 | `docker_image` | `dockerImage` ✅ | 命名风格 |
| 镜像与快照互斥 | 需自查 | 类型层拒 + 运行时抛 `snapshotName, dockerImage are mutually exclusive. Pass only one bake base.` ✅ | TS 双保险 |
| `permissions` 归谁 | 平台（sandbox 存在时被清空，源码两处） | 平台（类型层 `never`）✅ | 一致 |
| 返回值形状 | — | `{ kind: "sandbox", options }` ✅ | — |

## 十一、通道

| 能力 | Python | TypeScript | 差异 |
|------|--------|------------|------|
| 命名空间 | `channels` | `channels` ✅ | 一致 |
| 可用通道 | `slack` / `http` | `slack` / `http` ✅ | 一致 |
| Slack 参数 | 全可选（name/description/icon/trigger_on_all_messages/allow_bot_triggers/reactions） | 同（驼峰）✅ | — |
| HTTP 三件套 | `verify` / `parse` / `post` | 同 ✅ | 一致 |
| `parse` 返回形态 | message / ignore | `{ type: "message" }` / `{ type: "ignore" }` ✅ | 一致 |
| `ParseResult.message` 必填 | userId / threadId / content / target | 同 ✅ | 一致 |
| `provider: ""` | 应报错 | 抛 `channels.http provider must be a non-empty string` ✅ | — |
| 缺 `parse` | 文档要求必填 | **静默放过**，返回 `{ kind }` ✅ | TS 侧校验弱 |
| `verify` 返回非布尔 | 应报错 | **静默放过** ✅ | TS 侧校验弱 |
| `post` 的 `newThread` | 有 | `newThread` ✅ | 一致（定时投递语义） |

## 十二、调度

| 能力 | Python | TypeScript | 差异 |
|------|--------|------------|------|
| 声明函数 | `define_schedule(...)` | `defineSchedule(config)` ✅ | — |
| 时间表达 | cron 或 `at` | 同 📖 | — |
| `at` 精度 | 整分钟（秒被取整） | 同 📖 | ⚠️ 未实测（需部署） |
| `at` 下界 | 距今不足 5 分钟被拒 | 同 📖 | ⚠️ 未实测 |
| 投递目标 | 不能用 `current_thread` | `ScheduleDeliveryTarget` 已排除 📖 | 一致 |
| 运行时管理 | `schedules.create/list/get/update/delete` | `schedules` 导出含同名方法 ✅ | 一致 |

## 十三、身份

| 能力 | Python | TypeScript | 差异 |
|------|--------|------------|------|
| 声明函数 | `define_identity(...)` | `defineIdentity(options)` ✅ | — |
| 认证方式 | LangSmith API key / Supabase 等 | `auth.langsmithApiKey()` / `auth.supabase(...)` 📖 | TS 走 `auth` 命名空间 |
| principal 来源 | 平台签发 | 平台签发 | 一致 |
| 校验时机 | authoring time | `validateIdentity(config)` 可在定义期调 📖 | TS 暴露了显式校验函数 |

## 十四、CLI

| 命令 | 用途 | 需要账号 | 实测状态 |
|------|------|---------|---------|
| `mda build [PATH]` | 编译成托管 LangGraph app | 否 | ✅ 大量使用 |
| `mda dev` | 本地起 dev server | 否 | ⚠️ 需长驻进程，未跑 |
| `mda deploy` | 推到 LangSmith | 是 | ⚠️ 未实测 |
| `mda evals init` | 起评估工作区 | 是 | ⚠️ 未实测 |

`mda --version` → `mda 0.9.5 (80a88fc 2026-10-23)` ✅

## 十五、build 校验强度总表

这张表是本工程最实用的排查参照。「本地跑通了」必须追问「在哪一层跑通的」。

| 检查项 | 类型层 | `defineDeepAgent` 运行时 | `mda build` | 首次运行 |
|--------|--------|------------------------|-------------|---------|
| 托管自有键（backend/store/checkpointer/systemPrompt/disableMemory） | 拒（`never`） | **抛错** ✅ | — | — |
| sandbox `snapshotName` + `dockerImage` 互斥 | 拒 | **抛错** ✅ | — | — |
| `skills` / `mcp` 在静态入口 | 放过 | 放过 | **抛错** ✅ | — |
| 通道缺 `parse` | 放过 | 放过 ✅ | 放过 | 可能全被忽略 |
| 通道 `verify` 返回非布尔 | 放过 | 放过 ✅ | 放过 | 验签失效 |
| 通道 `provider: ""` | 放过 | **抛错** ✅ | — | — |
| 缺 `instructions.md` | — | — | **只警告**（exit 0）✅ | 行为与预期不符 |
| 导出名不是 `agent` | — | — | **抛错**（但报"缺 name"）✅ | — |
| 工厂体内 `name` | — | 通过 ✅ | **抛错**（读不到）✅ | — |
| `ManagedToolRuntime` 少写泛型 | 拒（TS2339）✅ | — | — | 字段为 undefined |

## 十六、本工程实测记录索引

| 结论 | 验证方式 | 存档 |
|------|---------|------|
| 返回值形状、`invoke` 缺失 | `l01` / `l02` | `l01-ts-output.txt`、`l02-ts-output.txt` |
| config 缺键读法差异 | `l02` 实验 2 | `l02-ts-output.txt` |
| 五个托管键运行时抛错（含报错原文） | `l02` 实验 3 | `l02-ts-output.txt` |
| `mda build` 对变量 `name` 求值 | `l03` 实验 2/3 + 临时项目 build | `l03-ts-output.txt` |
| 导出名错时报"缺 name" | 临时项目 build | 本表第四节 |
| 工具漏点名后 config 无键 | `l04` 实验 2 | `l04-ts-output.txt` |
| `skills` 静态入口 build 才拒 | `l04` 实验 4 + 临时项目 build | `l04-ts-output.txt` |
| MCP 字段 `type` → `transport` | `l05` 实验 3 | `l05-ts-output.txt` |
| `allow` 联合类型 + 已废弃 | `l06` 实验 2 | `l06-ts-output.txt` |
| sandbox 镜像互斥双保险 | `l06` 实验 4 | `l06-ts-output.txt` |
| 泛型顺序错导致 TS2339 | `l07` 实验 2 | `l07-ts-output.txt` |
| 通道只校验 `provider` | `l08` 实验 4 | `l08-ts-output.txt` |
| 缺 `instructions.md` 只警告 | 临时项目 build | `l09-ts-output.txt` 实验 2 |
| 四个子命令的真实用途 | `l09` 实验 4 | `l09-ts-output.txt` |
