# Python ↔ TypeScript API 对照表

> 本文件是全教程双语改造的**唯一口径来源**。任何课文里出现两侧差异的描述，都必须与这里一致。
> 依据：`deepagents 0.7.28`（PyPI）+ `deepagents 1.15.1`（npm）在本机实测，采集日期 2026-10-21。

## 一、先记住三件事

1. **两套版本号独立演进**，不能按版本号对齐功能。Python 是 `0.7.x`，TypeScript 是 `1.15.x`。
2. **入口形态不同**：Python 是 `create_deep_agent(...)`（关键字参数），TypeScript 是 `createDeepAgent({...})`（配置对象）。
3. **TypeScript 版同步返回**（实测 `typeof r.then === "undefined"`，`constructor.name` 为 `ReactAgent`），但官方示例普遍写 `await`。本教程统一写 `await`，与官方示例保持一致，并在课 3 括注说明。

## 二、`create_deep_agent` / `createDeepAgent` 参数对照

| Python | TypeScript | 备注 |
|---|---|---|
| `model` | `model` | 两侧都接受 `"provider:model"` 字符串 |
| `tools` | `tools` | 一致 |
| `system_prompt` | `systemPrompt` | 驼峰差异 |
| `middleware` | `middleware` | 一致 |
| `subagents` | `subagents` | 一致 |
| `skills` | `skills` | 一致 |
| `memory` | `memory` | 一致 |
| `permissions` | `permissions` | 一致；`mode` 语义同为 first-match-wins |
| `backend` | `backend` | 一致 |
| `interrupt_on` | `interruptOn` | 驼峰差异 |
| `response_format` | `responseFormat` | 驼峰差异 |
| `state_schema` | `stateSchema` | 驼峰差异 |
| `context_schema` | `contextSchema` | 驼峰差异 |
| `checkpointer` | `checkpointer` | 一致 |
| `store` | `store` | 一致 |
| `name` | `name` | 一致 |
| `cache` | 无对应 | **Python 独有** |
| `debug` | 无对应 | **Python 独有** |
| 无对应 | `streamTransformers` | **TS 独有**：注册自定义流转换器 |

## 三、完全一致的项（可放心直译）

- 内置文件工具 **8 个**，同名：`ls`、`read_file`、`write_file`、`edit_file`、`delete`、`glob`、`grep`、`execute`
- 后端类 **7 类**：`StateBackend`、`FilesystemBackend`、`StoreBackend`、`CompositeBackend`、`ContextHubBackend`、`LocalShellBackend`、`BaseSandbox` 系
- 默认模型：`claude-sonnet-4-6`（Python 写裸名，TypeScript 写 `anthropic:claude-sonnet-4-6`）
- 流式 v3：Python `stream_events(..., version="v3")` / TS `streamEvents(input, { version: "v3" })`
- 虚拟文件系统路径语义：以 `/` 为根，`/memories/`、`/skills/`、`/large_tool_results/` 等约定目录一致
- 权限 `mode` 取值与 first-match-wins 判定顺序一致

## 四、必须标注的差异（58 条，均有实测依据）

### 差异 1：默认装配栈成员不同（最容易讲错的一处）

**Python 最小栈 = 7 条中间件**。拦 `create_agent` 捕获到的真实列表：

```
1. FilesystemMiddleware          (name=FilesystemMiddleware)
2. SubAgentMiddleware            (name=SubAgentMiddleware)
3. _ParentNotifierMiddleware     (name=_ParentNotifierMiddleware)
4. _DeepAgentsSummarizationMiddleware (name=SummarizationMiddleware)
5. PatchToolCallsMiddleware      (name=PatchToolCallsMiddleware)
6. AnthropicPromptCachingMiddleware (name=AnthropicPromptCachingMiddleware)
7. UnsupportedContentMiddleware  (name=UnsupportedContentMiddleware)
```

注意 3 和 6 在**图节点上看不见**：`_ParentNotifierMiddleware` 只挂 `after_agent`，`AnthropicPromptCachingMiddleware` 在 model 节点内部包裹。所以「图节点 5 个」≠「中间件 5 条」。图节点实测为：

```
__start__, model, tools,
_ParentNotifierMiddleware.after_agent,
PatchToolCallsMiddleware.before_agent
```

**TypeScript 最小栈 = 5 条中间件**。实测 `createDeepAgent({ model })` 后 `options.middleware` 长度为 5，`name` 字段依次是：

```
1. FilesystemMiddleware
2. subAgentMiddleware
3. SummarizationMiddleware
4. patchToolCallsMiddleware
5. UnsupportedContentMiddleware
```

**两侧差 2 条**：Python 有 `_ParentNotifierMiddleware`（异步子代理跑完唤醒父代理）与 `AnthropicPromptCachingMiddleware`（提示缓存，非 Anthropic 模型上 no-op），TS 的默认栈里没有这两条。

**结论**：TS 版默认不带提示缓存中间件；需要缓存要在 TS 侧自己挂 `anthropicPromptCachingMiddleware`（`langchain` 导出）。这是行为差异，不是命名差异。

另外 `REQUIRED_MIDDLEWARE_NAMES` 实测是 `Set<string>`、只有 2 项（`FilesystemMiddleware`、`SubAgentMiddleware`），它表示「必须存在、不可排除」而非「全部成员」，不要当成完整清单引用。

### 差异 2：解释器两侧跑的都是 JavaScript

| | Python 侧 | TypeScript 侧 |
|---|---|---|
| 依赖包 | `langchain-quickjs` | `@langchain/quickjs` |
| 执行语言 | **JavaScript** | **JavaScript** |

**关键结论**：Python 版 Deep Agents 的解释器**不能执行 Python 代码**，它跑的是 JS。这一点在课 6 必须写清楚。

### 差异 3：`createDeepAgent` 的同步/异步语义

同步返回 `ReactAgent`，`await` 合法但非必需。课文统一写 `await`，课 3 括注说明，避免读者以为漏写 `await` 会报错。

### 差异 4：`cache` / `debug` 仅 Python 有

Python 的 `create_deep_agent` 接受 `cache=` 与 `debug=`，TypeScript 的 `CreateDeepAgentParams` 无这两项。TS 侧要缓存需走 LangGraph 自身的 cache 机制。

### 差异 5：自定义工具撞内置 —— Python 静默覆盖 / TS 构造期抛错

| 场景 | Python 0.7.28 | TypeScript 1.15.1 |
|---|---|---|
| 自定义工具名撞内置（如 `read_file`） | 静默顶掉，工具总数不变 | `createDeepAgent` 抛 `ConfigurationError`，`code: TOOL_NAME_COLLISION` |
| 两个自定义工具同名 | 后者胜，表里只剩一条 | 两条并存，不去重 |
| `write_todos` 能否撞 | 能 | 能（它不在 TS 的 `BUILTIN_TOOL_NAMES` 里） |

TS 源码调用链：`tools.map(t => t.name).filter(n => BUILTIN_TOOL_NAMES.has(n))`，命中即抛。错误文案：`Tool name(s) [read_file] conflict with built-in tools. Rename your custom tools to avoid this.`

实践后果：Python 的「覆盖内置实现」写法在 TS 完全不可用，改内置行为只能换后端或换中间件。

### 差异 6：`delete` 能力判定层级不同

| | Python | TypeScript |
|---|---|---|
| 判定表达式 | `type(backend).delete is not BackendProtocol.delete` | `typeof backend.delete === "function"` |
| 层级 | 类级 | 实例级 |
| 鸭子类型对象运行时挂 `delete` | 无效 | 立即生效 |

TS 侧请求期过滤是按**对象身份**比较：`tools.filter(t => backendSupportsDelete || t !== builtInDeleteTool)`。所以写探针时必须传真实工具对象，一旦重建为普通 `{name, description}` 对象，身份判定失效、`delete` 会被误判为可见。

### 差异 7：`glob` 语义相反

同一批文件（`.github/workflows/ci.yml`、`.env`、`src/a.yml`、`top.yml`）：

| pattern | Python | TypeScript |
|---|---|---|
| `*.yml` | `['/.github/workflows/ci.yml', '/src/a.yml']` | `["/top.yml"]` |
| `**/*.yml` | `['/src/a.yml']` | 三个全中（含 `.github/`） |

Python 的 `*.yml` 比 `**/*.yml` 更宽（`**` 不进点目录，源码注释写 "the bare form `*.yml` is *broader*"）；TS 走标准 glob（`*` 不跨 `/`，`**` 递归含点目录）。同一句「找所有 yml」两侧要写不同 pattern。

### 差异 8：`grep` 的 `regex_literal_hint` 只有 Python 有

Python 在「无命中 + pattern 像正则」时追加一段 `Note: grep matches literal text, not regex...` 提示；TS 侧无此实现，只回 `No matches found for pattern 'a.*a'`。信号判定只认 `|`、`.*`、`.+`、转义元字符四种形态，所以 `a.b`、`C++` 都不触发。

另一层：工具描述里「该用 `execute` 跑 `rg`」那句随 `execute` 能力增减（两侧都有），而这条无命中提示与 `execute` 无关（仅 Python）。

### 差异 9：多模态内容块键名不同

| 层次 | Python | TypeScript |
|---|---|---|
| 后端层 | `{'content': '<base64>', 'encoding': 'base64'}` | `{content: Uint8Array, mimeType: "image/png"}` |
| 工具层 image 块 | `{"type": "image", "base64": ..., "mime_type": ...}` | `{"type": "image", "data": ..., "mimeType": ...}` |

TS 后端给 `Uint8Array`、转 base64 发生在工具层；Python 后端直接给 base64。三个键名（`file_data.content` → `content`、`base64` → `data`、`mime_type` → `mimeType`）搞错时类型检查不报错，只在运行时拿到 `undefined`。

### 差异 10：后端类构造签名不同

| 后端 | Python | TypeScript |
|---|---|---|
| `CompositeBackend` | `CompositeBackend(default=..., routes={...})` 关键字 | `new CompositeBackend(defaultBackend, routes)` **位置参数** |
| `StoreBackend` | `StoreBackend(namespace=lambda rt: ...)` 位置/关键字都有 | `new StoreBackend({ namespace })` **配置对象** |
| `FilesystemBackend` | `FilesystemBackend(root_dir=..., virtual_mode=True)` | `new FilesystemBackend({ rootDir, virtualMode })` |
| `StateBackend` | `StateBackend()` | `new StateBackend()` |

**结论**：TS 侧 `CompositeBackend` 是 `(default, routes)` 二元组，不是配置对象；`StoreBackend` 反而用配置对象。跨语言迁移时这两个最容易写反。

### 差异 11：`permissions.mode` 取值不同（interrupt 仅 Python）

| 取值 | Python | TypeScript |
|---|---|---|
| `"allow"` | ✅（默认） | ✅（默认） |
| `"deny"` | ✅ | ✅ |
| `"interrupt"` | ✅（`>=0.6.8`，暂停等人审批） | ❌（`type PermissionMode = "allow" | "deny"`） |

**结论**：TS 的 `FilesystemPermission` 类型里只有两个 mode。照抄 Python 的 `"interrupt"` 到 TS 会直接类型报错。

### 差异 12：权限对点开头文件的两侧行为相反

| `paths=["/**"]` 遇 `/\.env` | Python | TypeScript |
|---|---|---|
| 是否匹配 | ❌ 放行 | ✅ 拦截 |
| 原因 | `_FS_WCMATCH_FLAGS` 无 DOTMATCH | `micromatch` + `{ dot: true }` |

**结论**：同一条 `deny ["/**"]`，Python 拦不住 `.env`（需补 `"/**/.*"` 等点号规则），TS 默认就能拦住。这是本教程里"同代码行为相反"最典型的一处，课 5 知识点 3 与探针 3 都实测收录。

### 差异 13：错误传播约定 — 抛异常 vs 返回 error 字段

| 场景 | Python | TypeScript |
|---|---|---|
| 文件工具路径穿越（如 `read("/../../etc/hostname")`） | 抛 `ValueError: Path traversal not allowed` | 返回 `{error: "Error reading file '...': Path traversal not allowed"}` |
| 权限 deny | 返回带 `error` 的 `ReadResult(error=...)` / `ToolMessage(status="error")` | 同左（返回对象 error，不抛） |

**结论**：Python 在"配置/约束违规"（路径穿越、构造参数错误）上倾向**抛异常**，TS 倾向于**返回 error 结果对象**。跨语言写处理逻辑时不要想当然——Python 用 `try/except` 接穿越错误，TS 要检查返回值 `.error` 字段。

### 差异 14：interpreter 仅 Python 侧有（TS 1.15.1 无导出）

| | Python | TypeScript |
|---|---|---|
| 中间件 | `langchain_quickjs.CodeInterpreterMiddleware` | 无对应导出 |
| 运行时 | QuickJS 跑 **JavaScript** | N/A（无实现） |
| 依赖 | `pip install deepagents[quickjs]` | 无 |

**结论**：即便在 Python 侧，解释器执行 `eval` 的代码也是 **JavaScript**（QuickJS 是 JS 运行时，不是 Python 运行时）——"解释器两侧跑的都是 JS"这句话成立。TS 侧 npm 包 `deepagents@1.15.1` 当前没有 `CodeInterpreterMiddleware` 或类似导出，本课知识点 2（Interpreters）以 Python 为主线索，TS 侧标注能力缺失即可，不要在 TS 教程里假设它存在。

### 差异 15：Middleware 原位替换 vs 二选一覆盖（skills 尤其危险）

| 写法 | Python | TypeScript |
|---|---|---|
| 只传 `skills=A` | 装配默认 `SkillsMiddleware(A)` | 同 |
| 只传 `middleware=[B]` | 装配 `B`（无 A） | 同 |
| `skills=A` + `middleware=[B]`（同名） | **槽位替换**：A 被 B 顶掉，栈里只有 1 个 | **完全忽略 `skills=`**：只有 B |
| 两个同名中间件 `[B, A]` | 按列表顺序，后者进栈 | `findLast` 取**最后一个** |

TS 源码 `resolveSkillsMiddleware` 用 `custom.findLast((e) => e.name === "SkillsMiddleware")`，是**二选一**语义（有自定义就完全不看 `skills=`），不是"槽位替换"。实测 A/B/C/D 四组：只传 skills → alpha；只传 middleware → beta；两个都传 → beta；两个同名 → 取最后一个。

**结论**：TS 里不要"先用 skills= 再补一个同名中间件微调"，那样 `skills=` 会被彻底丢弃。

### 差异 16：`systemMessage` 形态三种、各不相同

| 中间件 | Python | TypeScript |
|---|---|---|
| `SkillsMiddleware` | 统一 `SystemMessage` 对象 | `string[]`（元素是**裸字符串**） |
| `MemoryMiddleware` | 统一 `SystemMessage` 对象 | `SystemMessage` 对象（`content` 是 block 数组） |
| `FilesystemMiddleware.wrapModelCall` | — | 需要 `tools` / `model` / `state` / `runtime` 齐全 |

写探针拦 `request.systemMessage` 时，按 `.content` 取值会得到空串（因为元素是字符串）；给 Memory 传数组会报 `arr.map is not a function`。这是本教程编写过程中踩坑最密集的一处。

### 差异 17：文件工具输出 HTML 注释的处理相反

| `AGENTS.md` / SKILL.md 里的 `<!-- ... -->` | Python | TypeScript |
|---|---|---|
| 是否进系统提示 | **剥离** | **原样保留** |
| 有无开关 | 无（内置行为） | 无 |

**结论**：想让维护说明不占上下文，TS 侧必须把它挪出记忆文件。这会导致同一份 `AGENTS.md` 在两侧的系统提示长度不同（课 8 实测固定税 Python 5,118 / TS 4,470 字符）。

### 差异 18：工具结果卸载只认消息对象

| 工具返回值 | Python | TypeScript |
|---|---|---|
| `ToolMessage` | 卸载 | 卸载 |
| `Command`（含 messages） | 卸载内部消息 | 卸载内部消息 |
| 裸字符串 | 契约不允许（`ToolMessage \| Command`） | **原样放行，不卸载** |

实测 400,000 字符：TS 侧裸字符串进模型 400,000 字符，`ToolMessage` 进模型 1,610 字符。Python 侧没有这个坑，因为它的 `wrap_tool_call` 签名就要求返回消息对象。

### 差异 19：悬空调用修补 — 补 + 删 vs 只补

| 行为 | Python | TypeScript |
|---|---|---|
| 补悬空调用结果 | ✅ `status="error"` | ✅ `status="error"` |
| 区分"未完成"与"参数畸形" | ✅ 两种文案 | ❌ 只有一种 |
| 删除孤立 `ToolMessage`（无对应 tool_calls） | ❌ 不做 | ✅ 会删 |
| 文案 | "did not complete - no result was recorded..." | "was cancelled - another message came in..." |
| 返回结构 | `[RemoveMessage(REMOVE_ALL_MESSAGES), ...patched]` | 同 |

**结论**：数修补结果要先减掉那个 `RemoveMessage`，否则会多算 1。按文案 grep 日志也要分两套。

### 差异 20：缓存中间件 — 无条件装 vs 按模型装

| | Python | TypeScript |
|---|---|---|
| 装配策略 | 无条件 append，靠 `unsupported_model_behavior="ignore"` 静默 | `isAnthropicModel` / `isBedrockConverseModel` 判定后才装 |
| 支持范围 | Anthropic / Bedrock / Fireworks | Anthropic / Bedrock（**无 Fireworks 分支**） |
| 非支持模型的现象 | 中间件在栈里，no-op | 中间件**不在栈里** |
| 中间件名 | `AnthropicPromptCachingMiddleware` | `PromptCachingMiddleware` + `CacheBreakpointMiddleware` |
| Bedrock 中间件名 | `BedrockPromptCachingMiddleware` | 同名 |
| 运行时切模型的兜底 | `ignore` 覆盖 | `CacheBreakpointMiddleware` 每次调用重判 `isAnthropicModel(request.model)` |

**结论**：TS 侧"栈里找不到缓存中间件"是正常现象，不是版本 bug；但用 `modelFallbackMiddleware` 动态切模型时，装配期判定的结果会过时，靠 `CacheBreakpointMiddleware` 的逐次重判兜住（源码注释点名 OpenAI 会对 `cache_control` 返回 `400 Unknown parameter`）。

### 差异 21：摘要存档格式不同

| | Python | TypeScript |
|---|---|---|
| 存档文件 | `session_<uuid>.md` | `session_<8位hex>.md` |
| 消息格式 | XML：`<message type="human">...</message>` | 纯文本行：`Human: ...` / `AI: ...` |
| 时间戳 | `2026-10-21T02:17:53.667656+00:00` | `2026-10-22T04:01:23.773Z` |
| 送模型的条数 | system 占 1 条（在 messages 数组里） | system 不在数组里，少 1 条 |

**结论**：想用脚本解析这些存档做评测，两侧要写两套解析器。

### 差异 22：`truncateArgsSettings` 的无 profile 分支差异

| 模型无 profile 时 | Python | TypeScript |
|---|---|---|
| 摘要 `trigger` | `tokens 170000` | `tokens 17e4`（同） |
| 摘要 `keep` | `messages 6` | `messages 6`（同） |
| **裁剪 `trigger`** | `messages 20` | `messages 20`（同） |
| 模型有 profile 时裁剪 `trigger` | `fraction 0.85` | `fraction 0.85`（同） |

**结论**：两侧一致，但这一点容易漏——**无 profile 时参数裁剪的触发条件是"历史超过 20 条消息"，不是"上下文越 85%"**。自建模型网关往往不暴露 profile，此时小任务就会开始裁参。

### 差异 23：HumanMessage 卸载（两侧都有，文档没单独讲）

| | Python | TypeScript |
|---|---|---|
| 参数 | `human_message_token_limit_before_evict`（默认 50,000 token） | `humanMessageTokenLimitBeforeEvict`（默认 5e4） |
| 阈值 | 200,000 字符 | 200,000 字符（同） |
| 落盘目录 | `/conversation_history/` | 同 |
| 文件名 | `<uuid>.md` | `<12位hex>`（无扩展名） |
| 实测 | 150,000 不卸 / 210,000 → 1,376 字符 | 150,000 不卸 / 210,000 → 1,269 字符 |
| state 里原文 | 保留（非破坏性） | 保留 |

**结论**：这是"输入段"的第四道闸，比四段流图里的任何判断都早。只检查**最后一条** `HumanMessage`，且要求它还没被打过 `lc_evicted_to` 标记。

### 差异 24：默认工具数 — 8 vs 9（差一个 `execute`）

| | Python | TypeScript |
|---|---|---|
| 默认工具数 | 8 个 | **9 个** |
| 工具清单 | `ls` `read_file` `write_file` `edit_file` `delete` `glob` `grep` `task` | 上列 8 个 + **`execute`** |
| 加 `write_todos` 后 | 9 个 | 10 个 |
| 是否含 shell | ❌ 默认没有 | ✅ 默认有 |

**结论**：这是最容易踩的一条。读完 Python 文档去数 TS 的工具会一直差 1，且差的正是"能不能跑 shell"这个安全相关的差异。

### 差异 25：`write_todos` opt-in 的成因不同

| | Python | TypeScript |
|---|---|---|
| 默认是否带 | ❌ 不带 | ❌ 不带（结论同） |
| 原因 | v0.7 主动移除（changelog #4929）| **从来没默认带过** |
| 中间件类名 | `TodoListMiddleware` | `TodoListMiddleware`（同名）|
| 导入位置 | `from deepagents.middleware...` | **`import { todoListMiddleware } from "langchain"`** |
| 工厂形态 | 类，直接 `TodoListMiddleware()` | 小驼峰工厂 `todoListMiddleware()` |
| 写错导入的后果 | 通常 ImportError | **拿到 `undefined`，`middleware: [undefined]` 静默不生效** |

**结论**：结论一致但路径完全相反。TS 用户遇到"加了 todo 却不写计划"，第一嫌疑不是版本变化，而是导入源写错。

### 差异 26：`task` 参数校验 — forbid vs strip

| | Python | TypeScript |
|---|---|---|
| 校验方式 | Pydantic `forbid` | Zod `.strip()` |
| shape | `['description', 'subagent_type']` | 同 |
| 塞多余键（如 `prompt`）| **报错回模型**，模型下一轮可自我纠正 | **静默剥离**，模型永远不知道 |
| 错误文案 | `Unexpected argument 'prompt'; put all instructions for the subagent in \`descrip...` | 无（不报错）|
| 实际后果 | 一轮重试后恢复正常 | **持续产出空壳报告**，极难定位 |

**结论**：这是本课最危险的防呆不对称。TS 侧必须自己在封装层校验，否则"提示词塞错键"会表现为"子代理什么都没干"。

### 差异 27：fork 子代理的消息条数 — 5 vs 4

| | Python | TypeScript |
|---|---|---|
| fork 收到条数 | 5 条 | **4 条** |
| 差的这一条 | 一条 **system**（不写 `system_prompt` 时内容为空串）| 不写 `systemPrompt` 时**一条 system 都不带** |
| 前缀说明长度 | 约 600 字符 | 571 字符 |
| 前缀位置 | 最后一条 human | 同 |
| isolated 收到条数 | 2 条 | 2 条（同）|

**结论**：TS 的 fork 子代理如果不写 `systemPrompt`，它没有"你是子代理"的身份提示，只靠最后那条 571 字符前缀自我介绍。写代码时别指望有默认人格。

### 差异 28：关掉 `task` — 可关 vs 关不掉

| 写法 | Python 工具数 | TS 工具数 |
|---|:---:|:---:|
| 默认 | 8 | 9 |
| `subagents=[]` / `subagents: []` | 仍 8（GP 自动加）| 仍 9 |
| `generalPurposeAgent: false` | 参数不存在 | **参数不存在，静默忽略** |
| profile 关 GP + 空子代理 | **7，无 task** ✅ | 无对应能力 |
| `createSubAgentMiddleware({generalPurposeAgent:false, subagents:[]})` 顶掉默认 | 不适用 | 9，`task` 在但**可用类型为空**，调到抛异常 |
| 裸对象 `{name:"subAgentMiddleware"}` 顶掉 | 不适用 | **8，无 task**（拆掉整个机制）|

**结论**：Python 是"删掉工具"，TS 是"工具还在但无人可派"。TS 想彻底没有 `task` 只能拆中间件，等于放弃委派能力。

### 差异 29：未知 `subagent_type` 的错误形态

| | Python | TypeScript |
|---|---|---|
| 形态 | 返回 `ToolMessage` 错误字符串 | **直接 `throw`** |
| 模型能否看到错误 | ✅ 能看到并自我纠正 | ❌ 看不到，整轮中断 |
| 文案 | ``We cannot invoke subagent nobody because it does not exist, the only allowed types are `general-purpose`, `r` `` | ``invoked agent of type nobody, the only allowed types are `general-purpose`, `r` `` |
| 生产影响 | 自动降级重试 | **必须 `try/catch` 包住，否则一次幻觉就挂整轮** |

**结论**：文案几乎一样，但一个是"告诉模型重来"，一个是"抛出异常"。TS 侧任何允许模型自由填 `subagent_type` 的场景都要加保护。

### 差异 30：同名原位替换通道（TS 独有逃生口，也是坑）

| | Python | TypeScript |
|---|---|---|
| 能否移除默认 `SubAgentMiddleware` | ❌ `excluded_middleware` 明确拒绝 | ✅ 未知 |
| 同名覆盖机制 | 无 | `middleware: [{ name: "subAgentMiddleware", ... }]` **原位置顶掉** |
| 是否校验类型 | 不适用 | ❌ **只认 `name` 字符串，不校验类型** |
| 用途 | 无 | 换实现（`createSubAgentMiddleware` 生效就靠它）|
| 风险 | 无 | 写错名字/写个空对象都能"成功"顶掉，静默丢能力 |

**结论**：这是 TS 侧唯一的"逃生通道"，同时也是最容易静默破坏装配的地方。改中间件栈后一定要打印一次工具清单做回归。

### 差异 31：无 checkpointer 的失败时机

| | Python | TypeScript |
|---|---|---|
| 中断是否产生 | ✅ 产生，输出里带 `__interrupt__` | ❌ **不产生** |
| 报错时机 | `Command(resume=...)` 时才报 | **第一次 `invoke` 就抛** |
| 报错类型 | `RuntimeError` | `GraphValueError` |
| 报错文案 | `Cannot use Command(resume=...) without checkpointer` | `No checkpointer set` |

**结论**：同一个配置错误两种症状。Python 是"跑完了但接不回来"，TS 是"根本跑不起来"。TS 用户不能用"有没有 `__interrupt__`"验证闸门装对。

### 差异 32：`permissions` 的 mode 少一档

| | Python | TypeScript |
|---|---|---|
| 取值 | `allow` / `deny` / **`interrupt`** | `allow` / `deny` |
| 写 `interrupt` 的后果 | 合法，按路径触发审批 | **静默变 `allow`**（Zod strip），无报错 |
| 实测 | 写 `/secrets/key.txt` 中断 | 写 `/secrets/key.txt` **成功写入** `files={"/secrets/key.txt":"k"}` |
| 按路径触发审批的做法 | 直接配 `mode="interrupt"` | 必须用 `interruptOn` + `when` 谓词手写 |
| 权限转审批通道 | `_build_interrupt_on_from_permissions` + `_merge_fs_interrupt_on` | **不存在** |

**结论**：TS 少了整档"灰区"能力。从 Python 迁代码时这是最容易漏的一条——代码看起来完全正确，只是拦不住。

### 差异 33：`deny` 与审批的优先级相反

| | Python | TypeScript |
|---|---|---|
| 同一路径 `deny` + 审批 | **`deny` 赢，不中断** | **仍然中断** |
| 人批准后 | 不适用（没问） | 返回 `Error: permission denied for write on ...` |
| 实际体验 | 不问，直接拒 | **白点一次同意，然后失败** |
| `files` | `{}` | `{}` |

**结论**：TS 会让人为注定失败的调用点同意。需要在 `when` 谓词里排除 deny 路径才能对齐 Python 体验。

### 差异 34：`reject` 的 ToolMessage 文案

| | Python | TypeScript |
|---|---|---|
| 带 `message` | `User rejected the tool call for \`write_file\` with reason: 不许写这个文件` | **原样返回人的 message**：`不许写这个文件` |
| 不带 `message` | `... with id w1. The tool was not executed. Do not retry this tool call unless the user explicitly requests it.` | `User rejected the tool call for \`write_file\` with id w1` |
| 是否含"别重试"提示 | ✅ | ❌ |
| `status` | `error` | `error`（同）|

**结论**：TS 侧 `reject` 不传 `message` 时模型可能反复重试同一调用。要等价提示得自己在 `message` 里写全。审批审计的字段提取也不能共用。

### 差异 35：`batched` 模式混合决策会丢调用

| | Python | TypeScript |
|---|---|---|
| 一次中断 2 条待批，决策 `[approve, reject]` | 被批准的照常执行：`files={"/a.txt":"A"}` | **`files={}`，被批准的调用整条消失** |
| 消息条数 | 5 条（含 2 条 ToolMessage） | **4 条**（只有 reject 那条） |
| `tool_calls` | 保留两个 | **只剩被拒的那个** |
| 有无痕迹 | 正常 | 无 ToolMessage、无 tool_call，凭空消失 |
| 规避方式 | 不需要 | `interruptMode: "per_call"`（实测 `files={"/a.txt":"A"}` 正常）|
| 源码位置 | 无此分支 | `hitl.js:667` 的 `hasRejectedToolCalls` |

**结论**：这是本课最危险的差异。批量审批只要有一条 reject，同批 approve 的调用就没了。TS 侧批量审批建议直接用 `per_call`。

### 差异 36：`editNotice` 的生效范围

| | Python | TypeScript |
|---|---|---|
| 参数名 | `edit_notice` | `editNotice` |
| `batched` 模式 | ToolMessage 带 `Note: a human reviewer replaced this tool call...` 前缀 | **不加前缀**，原样返回工具结果 |
| `per_call` 模式 | 带前缀 | 带前缀（可自定义文案） |
| 实测 batched | `'Note: a human reviewer replaced ... Executed instead: write_file with arguments ...'` | `"Successfully wrote to '/safe.txt'"`（模型不知情）|

**结论**：TS 的 `batched` 模式下人改了参数，模型会以为自己写对了，后续推理全建立在错误前提上。要用 `edit` 决策就得开 `per_call`。

### 差异 37：悬空调用修补的文案与删除行为

| | Python | TypeScript |
|---|---|---|
| 补的文案 | `did not complete - no result was recorded. It may have been cancelled or interrupted.` | `was cancelled - another message came in before it could be completed.` |
| 补的 `status` | `error` | `error`（同） |
| 删孤立 `ToolMessage` | ❌ 不删 | ✅ **会删** |
| 区分"未完成"与"参数畸形" | ✅ 两种文案 | ❌ 只有一种 |

**结论**：运维告警按文案匹配要写两套正则；修补后消息条数两侧可能不同，断言不能共用。

### 差异 38：`when` 谓词的上下文能力

| | Python | TypeScript |
|---|---|---|
| 取参数路径 | `req.tool_call["args"]` | `req.toolCall.args` |
| 能否返回 Promise | ❌（同步） | ✅（`boolean \| Promise<boolean>`）|
| `batched` 下能拿到 `request.tool` | ❌ | ❌（`undefined`）|
| `per_call` 下能拿到 | 不适用 | ✅（在 `wrapToolCall` 里跑）|
| 恢复时是否重跑 | ✅ | ✅（JSDoc 明确警告，必须同结果）|

**结论**：TS 的 `when` 能异步，但"恢复时重跑谓词"这条约束两侧都成立——谓词结果不稳定会让人的决定被跳过。

### 差异 39：异步子代理的分流键名与判据强度

| | Python | TypeScript |
|---|---|---|
| 键名 | `graph_id` | `graphId` |
| 判据 | `if "graph_id" in spec` | `if ("graphId" in subAgent)` |
| 空串 | 未显式校验（键存在即异步） | **`{"graphId": ""}` 实测 `isAsyncSubAgent = true`** |
| 只写 `url` | `isAsyncSubAgent = False`（走同步，`url` 被忽略） | 同（`isAsyncSubAgent = False`）|
| 与 runnable 共存 | 按 `graph_id` 优先 | 同（`{name, runnable, graphId}` → 异步）|

**结论**：两侧判据都是"键存在即异步"，但 **TS 的空串也认**，会在真正 `start` 时才炸。配置校验要自己加非空断言，别指望 SDK。

### 差异 40：异步任务状态集 — TS 没有 `waiting`

| | Python | TypeScript |
|---|---|---|
| 状态总数 | 8 | **7** |
| 状态值 | `pending/running/success/error/cancelled/timeout/interrupted/waiting` | `pending/running/success/error/cancelled/timeout/interrupted` |
| thread 暂停的映射 | `_THREAD_TO_TASK_STATUS = {"interrupted": waiting, "busy": "running"}` | **无此映射** |
| 等人审批的远程任务 | `waiting`（主代理知道要等人） | **`success`**（主代理会去取半截结果）|

**结论**：这是本课最危险的差异。**异步子代理的远程图不要配 HITL**——需要人审批的活留在同步子代理或主代理上做。

### 差异 41：异步中间件没有自动轮询钩子

| | Python | TypeScript |
|---|---|---|
| 钩子 | `before_agent` / `abefore_agent` / `before_model` / `abefore_model` / `after_model` / `aafter_model` | **无** |
| 中间件返回 | 状态 schema + tools + 六个钩子 | `{name, stateSchema, tools, wrapModelCall}` |
| `after_model` 跳转 | `@hook_config(can_jump_to=["model"])` 能主动唤醒父代理 | **不存在这个能力** |
| 主体感知进展的方式 | 状态自动刷新，模型不用问 | **只能靠模型自己想起来调 `check_async_task`** |

**结论**：TS 侧"异步"只兑现了一半。Python 的异步是"派完不用管"，TS 的异步是"派完你得记得问"。

### 差异 42：异步中间件的 systemPrompt 自动装配时未传

| | Python | TypeScript |
|---|---|---|
| 自动装配写法 | `AsyncSubAgentMiddleware(async_subagents=...)` 内部拼 `_WAITING_NOTE` 等提示 | `createAsyncSubAgentMiddleware({ asyncSubAgents })`，**不传 `systemPrompt`** |
| 硬规则是否进上下文 | ✅ | ❌（`fullSystemPrompt` 为 null）|
| 硬规则内容 | "别自动 check""别照抄上一次的状态" | `ASYNC_TASK_SYSTEM_PROMPT` 存在但没被用上 |
| 补救 | 无需 | 显式传 `systemPrompt: ASYNC_TASK_SYSTEM_PROMPT` |

**结论**：源码里那段提示词写得很完整（`Never auto-check after launching`、`NEVER report a status from a previous tool result`），但自动装配路径根本不传它。TS 侧必须自己补，否则模型会把上一次 `check` 的旧状态当新状态汇报。

### 差异 43：动态子代理的包归属与构造形式

| | Python | TypeScript |
|---|---|---|
| 包 | `deepagents` 内置（`langchain_quickjs` 为运行依赖）| **独立包 `@langchain/quickjs`** |
| 构造 | 类 `CodeInterpreterMiddleware()` | **工厂函数 `createCodeInterpreterMiddleware()`** |
| peer 依赖 | 无显式要求 | `deepagents >= 1.13.4-rc.0` |
| 写错的后果 | ImportError（好排查） | **运行时炸**（模块不存在时通常也是 ImportError，但类型声明缺失易被忽略）|

**结论**：`import { createCodeInterpreterMiddleware } from "@langchain/quickjs"`。别写 `CodeInterpreterMiddleware`，别从 `deepagents` 里导。

### 差异 44：动态子代理失败传播 — 返回值 vs 抛异常（方向相反）

| | Python | TypeScript |
|---|---|---|
| 子代理抛异常 | 返回 `<error type="RuntimeError">...</error>` 字符串 | **`promise.reject`，直接抛到 JS 侧** |
| `eval` 是否继续 | ✅ 继续（可 catch 后返回其他值）| ❌ **整个 `eval` 崩掉**（不 try/catch 的话）|
| 未知 `subagentType` | 返回字符串（`subagents.py:847`）| **抛错** `invoked agent of type nobody, the only allowed types are ...` |
| 推荐写法 | `if (String(r).startsWith("<error"))` | `try { await task(...) } catch (e) {}` |

**结论**：两侧完全相反。**TS 侧批量派发必须用 `Promise.allSettled`**，否则一个子代理失败会带走全部结果。

### 差异 45：`task()` 在无子代理时的可用性

| | Python | TypeScript |
|---|---|---|
| 完全不配 `subagents` | `task` 工具不存在 | `typeof task` **仍是 `"function"`** |
| 原因 | 靠 `inline_subagents` 决定是否装中间件 | `subagents` 默认 `true` + 自动补 `general-purpose` |
| 关掉的方法 | `register_harness_profile(..., general_purpose_subagent=GeneralPurposeSubagentProfile(enabled=False))` | **`subagents: false`**（唯一有效写法）|
| `subagents: []` 是否关掉 | 是 | **否**，仍会自动补 `general-purpose` |

**结论**：TS 侧用 `typeof task` 判断动态派发是否可用**完全无效**，必须显式传 `subagents: false`。

### 差异 46：不写 `url` 的错误形态

| | Python | TypeScript |
|---|---|---|
| 报错文案 | `Async subagent 'r' has no url configured. ASGI transport (url=None) requires async invocation.` | `ConnectionError: Unable to connect to LangGraph server...` |
| 是否可诊断 | ✅ 文案直接指向配置问题 | ❌ 看起来像服务没起 |
| SDK 回落 | 无（必须显式给 url 才走 ASGI）| **回落 `http://localhost:8123`** |
| 错误是否吞掉 | ✅ catch 成 ToolMessage，流程继续 | ✅ 同（catch 成 ToolMessage）|

**结论**：TS 侧把 `url` 当必填项写。开发机恰好有服务占 8123 时，错误会变成"连上了但 assistant 不存在"，排查方向彻底跑偏。

### 差异 47：`check_async_task` 的返回形态

| | Python | TypeScript |
|---|---|---|
| 返回内容 | 人话 + 字段混排（`Status: running\nResult: ...`）| **纯 JSON 字符串**（`{"status":"success","threadId":"t-1","result":"..."}`）|
| 字段命名 | `task_id` / `agent_name` / `last_checked_at` | `taskId` / `agentName` / `checkedAt` |
| 模型读漏风险 | 较低（有自然语言标签）| **较高**（要自己解析 JSON 的 `status` 字段）|

**结论**：TS 侧模型更容易把 JSON 里的 `pending` 读成"没结果"而反复 `check`。系统提示里要明确"看到 status 字段就停手"。

### 差异 48：`list_async_tasks` 的过滤语义与终态宽松度

| | Python | TypeScript |
|---|---|---|
| `statusFilter` 筛的对象 | 缓存状态 | 缓存状态（同）|
| 终态任务再 `cancel` | 再发一次远程 cancel | 同（两侧都不做终态保护）|
| `waiting` 时是否发远程 cancel | **跳过**（`if tracked["status"] != _WAITING`）| 不适用（无 `waiting`）|
| `update` 已取消的任务 | 不校验终态，直接开新 run | 同 |

**结论**：`statusFilter` 筛的是缓存不是实时状态，这个坑两侧都有。TS 侧因为没 `waiting`，少了那条例外分支，行为反而更"一视同仁"。

### 差异 49：重试判定依据（异常家族 vs Symbol 标记）

| | Python | TypeScript |
|---|---|---|
| 判定入口 | `default_retry_on(exc)` | `retryOn(e) => getRetryable(e) ?? true` |
| 依据 | `isinstance(exc, ModelError)` → `exc.is_retryable` | `Symbol.for("langchain.errors.retryable")` 标记 |
| 是否看 `status` 字段 | 由 ModelError 子类间接体现 | **完全不看** |
| 无标记时的默认 | 普通异常 → `True` | `undefined` → `?? true` → `True` |

**结论**：结论巧合一致（"裸 Error 会被重试"），但机制完全不同。TS 侧连 `Error.status = 401` 都不影响判定，实测照样重试 3 次。

### 差异 50：`stampRetryable` 在 `createDeepAgent` 下被中间件链遮蔽

| | Python | TypeScript |
|---|---|---|
| 精细控制入口 | `ModelError.is_retryable`（在异常自身上）| `stampRetryable(err, false)` |
| `createAgent` 下是否生效 | 不适用 | **生效**（调用 1 次）|
| `createDeepAgent` 下是否生效 | 不适用 | **失效**（调用 3 次）|
| 失效原因 | — | `AgentNode` 把模型异常包成 `MiddlewareError`，标记留在 `.cause` |

实测包裹链：`MiddlewareError(marked=undefined) -> Error(marked=false)`。

**结论**：这是本课最隐蔽的一条。`getRetryable` 只读最外层对象的 Symbol，`MiddlewareError` 是新对象、没有标记。要在 `createDeepAgent` 下用打标，必须自己写 `retryOn` 沿 `cause` 链查（实测可把调用次数从 3 压回 1）。

### 差异 51：重试耗尽的默认去向

| | Python | TypeScript |
|---|---|---|
| 默认行为 | 异常往上抛 | `onFailure: "continue"`，**写成 AIMessage 继续跑** |
| 要它抛 | 默认就是 | 显式 `onFailure: "error"` |
| 参数名 | `on_failure` | `onFailure` |

实测文案：`Model call failed after 2 attempts with MiddlewareError: http 500`，且末条消息 `getType() === "ai"`。

**结论**：TS 默认把"模型全挂"变成一句假回答，静默产出错误结论，比直接崩溃更难排查。

### 差异 52：`exitBehavior` 的档位集合

| 层 | Python | TypeScript |
|---|---|---|
| Model | `"end"`(默认) / `"error"` | 同（一致）|
| Tool | `"continue"`(默认) / `"error"` | `"continue"`(默认) / `"error"` / **`"end"`（独有）** |

**结论**：默认值两侧一致，但 TS 的 Tool 层多一档 `"end"`，用于"工具撞上限就该整轮收工"。

### 差异 53：`modelFallbackMiddleware` 的签名

| | Python | TypeScript |
|---|---|---|
| 单模型 | `ModelFallbackMiddleware("gpt-5.5")` | `modelFallbackMiddleware("gpt-5.5")` |
| 多模型 | 位置参数序列 | **可变参数 `(...models)`**，不是数组 |

**结论**：`modelFallbackMiddleware(["a","b"])` 会把整个数组当成一个模型传进去，不报错但降级链是坏的。

### 差异 54：checkpointer 缺失的暴露时机（本课最大差异）

| 阶段 | Python | TypeScript |
|---|---|---|
| 第一次 `invoke` | 正常触发中断（`__interrupt__` 有值）| **抛 `GraphValueError: No checkpointer set`** |
| `Command(resume=...)` | 此时才抛 `RuntimeError` | 走不到这一步 |
| 排障链接 | 无 | `https://docs.langchain.com/oss/javascript/langgraph/MISSING_CHECKPOINTER/` |

**结论**：方向完全相反。Python 能"先演示、后配持久化"，TS 不给这个余地。从 Python 迁过来时"本地审批能跑通"不再是配置正确的证据。

### 差异 55：流式句柄的字段与形态

| | Python | TypeScript |
|---|---|---|
| 入口 | `stream_events(version="v3")` 同步返回 | **`streamEvents` 返回 Promise，要 `await`** |
| `output` | 同步版 dict / 异步版方法 | **Promise** |
| `messages` / `tool_calls` | 可迭代 | `StreamChannel` |
| `path` | 有 | **没有** |
| `status` | 有（4 值）| **没有** |

**结论**：TS 句柄自有属性为 `name / cause / output / messages / toolCalls / subagents`。`as never` 会绕过类型检查，缺字段静默 `undefined`，状态面板会永远空白。

### 差异 56：多消费者遍历（方向相反）

| | Python | TypeScript |
|---|---|---|
| 第二次遍历 | `RuntimeError: already has a subscriber` | **正常返回**（实测 `["worker"]`）|
| 分叉方法 | `atee(n)` | **无 `atee`**（`typeof === "undefined"`），有 `iterate(startAt?)` |

**结论**：Python 的"必须 atee"在 TS 侧用不上。源码注释：「Each call returns an independent cursor so multiple consumers can iterate the same channel concurrently.」两侧经验不可互搬。

### 差异 57：子代理失败的传播形态

| | Python | TypeScript |
|---|---|---|
| 主代理配了 retry | 子代理仍只调 1 次（不继承）| 同 |
| 异常去向 | 包成 ToolMessage 还给模型 | **`MiddlewareError` 抛穿整个 `invoke`** |
| 模型能否读到错误 | 能 | 不能（调用方 catch）|

**结论**："一个子代理炸掉不会带崩整体"在 TS 侧不成立，除非显式给子代理配容错。

### 差异 58：容错中间件的包归属与版本约束位置

| | Python | TypeScript |
|---|---|---|
| 中间件从哪导入 | `langchain.agents.middleware` | **`langchain`**（`deepagents` 56 个导出里没有）|
| 版本约束看哪里 | `dependencies`（`langchain>=1.4.6,<2.0.0`）| **`peerDependencies`（8 个）** |
| peer 不满足的后果 | — | npm 警告而非硬失败 |
| 静默工具变更 | v0.7 移除 `write_todos` | 无对应事件 |

TS 侧 8 个 peerDeps：`@langchain/anthropic ^1.5.12` / `@langchain/core ^1.2.14` / `@langchain/langgraph ^1.4.10` / `@langchain/langgraph-checkpoint ^1.1.5` / `@langchain/langgraph-sdk ^1.9.23` / `@langchain/openai ^1.6.2` / `langchain ^1.5.10` / `langsmith >=0.7.1 <0.10.0`。

**结论**：锁版本要锁 8 个 peer 而不是 1 个主包。好消息是 TS 没有 Python 那种静默移除工具的版本事件。


## 五、TypeScript 侧独有导出（本教程不展开）

`createHarnessProfile`、`parseHarnessProfileConfig`、`registerHarnessProfile`、`harnessProfileConfigSchema`、`EMPTY_HARNESS_PROFILE`、`findProjectRoot`、`adaptBackendProtocol`、`adaptSandboxProtocol`、`scrubUnsupportedMultimodalContent`、`createCompletionCallbackMiddleware` 等。

这些属于 TS 包的内部脚手架，与 Python 主线口径不对应，本教程不展开，避免读者误以为 Python 侧也有同名能力。

## 六、官方文档索引

- Python 版：`web-index/docs-deepagents/`（34 条）
- TypeScript 版：`web-index/docs-deepagents-js/`（30 条）
- 站点前缀：`https://docs.langchain.com/oss/python/deepagents/` 与 `https://docs.langchain.com/oss/javascript/deepagents/`
