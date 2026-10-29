# 第 01 轮知识点对齐 · 选择题

> 日期：2026-10-28 ｜ 轮次：round-01（首轮）
> 范围：`langchain/managed-deep-agents/` 全部 9 课，基线 `managed-deepagents 0.9.5`
> 题量：6 题（单选 5 + 多选 1）｜ 分数口径：答对题数 / 总题数
> 出题依据：优先取本教程实测结论与源码证据（易混点来源逐题标注），干扰项一律来自真实存在的近似概念或近似行为，无编造项。

## 题目

### Q1 ｜知识点：自定义工具与运行上下文（课 4）｜ 题型：单选

你在 `tools/ticket.py` 里写好了 `@tool async def query_ticket(...)`，`mda build` 全程 `exit=0`，但运行起来模型说"我没有这个工具"。

最可能的直接原因是：

- A. `tools/ticket.py` 的文件名不符合命名约定，平台没扫描到
- B. 入口既没有 `from .tools.ticket import query_ticket`，也没有把它放进 `define_deep_agent(tools=[...])`
- C. `tools/` 下的模块必须在 `tools/mcp.py` 里登记一次才会被发现
- D. `@tool` 装饰器缺少 `parse_docstring=True`，导致工具没有被导出

**正确答案**：B
**易混点来源**：`stages/2-能力声明/lessons/04-指令技能与工具.md` 知识点 3——「`tools/` 下写完必须 import 进入口」「设备必须被人点名登记」；实测漏点名后 config 里连 `tools` 键都不存在（硬取 `KeyError`，`get` 才得 `None`）。
**干扰项迷惑来源**：A 取材于真实存在的同名机制混淆（`skills/` 只扫一层、`channels/` 只看直接子文件确实有扫描边界，但 `tools/` 的失败点不是文件名）；C 取材于 `tools/mcp.py` 是真·保留名且**只声明不 import**（课 5 知识点 2），容易推广错；D 取材于 `@tool(parse_docstring=True)` 真实存在（课 4 与课 8 示例里都用过），但它影响的是参数文档解析，与工具是否被注册无关。

---

### Q2 ｜知识点：技能目录与渐进披露（课 4）｜ 题型：多选

关于 `skills/`，下列说法正确的是（多选）：

- A. 目录只扫一层：`skills/parent/child/SKILL.md` 不会被发现
- B. `SKILL.md` 的 frontmatter 缺必需字段时，`mda build` 会失败退出
- C. 平时只加载 `name` 与 `description` 两个标签，正文被选中后才进上下文
- D. 单个 `SKILL.md` 有文件体积上限，超过会被跳过
- E. `name` 必须是小写连字符形式

**正确答案**：A, C, D, E
**易混点来源**：`stages/2-能力声明/lessons/04-指令技能与工具.md` 知识点 2——实测 `discovered: ['flat']` 漏掉 `parent/child`；frontmatter 七种写法逐一实测；渐进披露四阶段。
**干扰项迷惑来源**：B 是本题唯一错项，也是全课最要命的一条——`mda build` 全程 `exit=0`，只有**警告**，整张技能被**静默跳过**。它与"配置文件写错就构建失败"的普遍直觉相反，是 `08-实战经验.md` 故障模式 2 的根因。

---

### Q3 ｜知识点：沙箱与身份（课 6）｜ 题型：单选

项目里同时声明了 `sandbox/` 和 `define_deep_agent(permissions=[FilesystemPermission(... 禁止写 /workspace/**)])`。实测结果是：

- A. 两条规则叠加：沙箱生效，`permissions` 也生效
- B. 沙箱生效，`permissions` 被置为 `[]`（全清，不是过滤也不是部分保留）
- C. 沙箱被禁用，`permissions` 生效
- D. 构建期直接报错，两者互斥不允许同时声明

**正确答案**：B
**易混点来源**：`stages/2-能力声明/lessons/06-记忆沙箱与身份.md` 知识点 3——源码 `if sandbox_backend is not None: merged["permissions"] = []`（`runtime.py:1188`，另有 `1127` 行同构分支）。
**干扰项迷惑来源**：A 是"规则叠加"的正常直觉；C 是官方文档那句话的**半截读法**——原文说 "A filesystem permission rule disables the sandbox `execute` tool, so the runtime **drops the rules rather than the shell**"，即丢掉的是规则不是 shell；D 把"静默清空"误记成"显式报错"，而真实情况是 `mda build` 一句提示都没有。

---

### Q4 ｜知识点：调度与线程策略（课 8）｜ 题型：单选

你要让每个工作日早上 8 点的晨报**累积**进同一条话题，好在第二天注明"持续第 N 天"。声明式 `schedules/` 写法应该是：

- A. `define_schedule(cron="0 8 * * 1-5", new_thread=False, ...)`
- B. `define_schedule(cron="0 8 * * 1-5", thread={"mode": "persistent", "id": "<预先建好的话题 UUID>"}, ...)`
- C. `define_schedule(cron="0 8 * * 1-5", thread={"mode": "ephemeral"}, ...)`
- D. 不写任何线程字段即可，`cron` 的默认行为就是续接上一条话题

**正确答案**：B
**易混点来源**：声明层 `define_schedule` 签名核对（`inspect.signature` 只有 `cron / timezone / prompt / input / thread / deliver_to / context`）＋实测 `define_schedule(..., new_thread=False)` 抛 `TypeError: define_schedule() got an unexpected keyword argument 'new_thread'`；`thread={"mode":"persistent","id":...}` 实测通过。见 `stages/3-运行与交付/lessons/08-通道与调度.md` 知识点 2。
**干扰项迷惑来源**：A 是**运行时** `runtime.schedules.create` 的合法参数，真实存在且语义正确——错在层次；D 记反了默认值（`cron` 默认 `True` = 每次新话题，`at` 默认 `False`）；C 的 `ephemeral` 是真实枚举值，但方向相反。

---

### Q5 ｜知识点：定义与编译分离（课 2）｜ 题型：单选

`from agent import agent` 之后，`agent` 到底是什么？

- A. 一个已编译的 LangGraph 图（`CompiledStateGraph`），可以直接 `invoke`
- B. 一份 frozen 的声明对象 `DeepAgentDefinition`，`config` 是个 dict，真正的 agent 由运行时用 `create_deep_agent` 编译
- C. 一个普通的 dict，内容就是 `create_deep_agent` 的关键字参数
- D. 一个工厂函数，每次调用才产出一个新的 agent

**正确答案**：B
**易混点来源**：`define_deep_agent.py`（`0.9.5`，178 行）——`@dataclass(frozen=True) class DeepAgentDefinition`，字段只有 `config: dict[str, object]` 与 `kind: ClassVar[str] = "deep-agent"`；`runtime.py:981` `agent = create_deep_agent(**cast("Any", merged))` 才是编译发生处。
**干扰项迷惑来源**：A 是 `create_deep_agent` 的真实返回类型，也是"define 完就该能 invoke"这一直觉的来源；C 抓住了 `config` 是 dict 这个真实细节但丢了外层类型；D 混淆了**工厂入口**（`agent(runtime, config)` 这种写法确实存在，返回的仍是 definition，不是 agent）。

---

### Q6 ｜知识点：三源分离（课 7）｜ 题型：单选

一个只读报表的调用方，把 `configurable` 里的 `role` 写成 `admin`，然后调到了一个写工具。下列判断哪个正确？

- A. 这条路走不通：`role` 属于平台保留键，会被 `sanitize_configurable` 剥掉
- B. 这条路走不通：`context_schema` 会在入口校验 `role` 的取值
- C. 这条路能走通：平台只剥 13 个保留键，你自己起的业务字段原样送进工具；判权限必须读 `server_info.principal`
- D. 这条路能走通，但 `runtime.channel` 会拦下来

**正确答案**：C
**易混点来源**：`stages/3-运行与交付/lessons/07-运行时上下文.md` 知识点 1——13 个保留键（`user_id` / `mda_user_id` / `mda_groups` 等）全剥，与身份无关的键保留；`context` 只用来选行为，不判权限。
**干扰项迷惑来源**：A 把真实的剥键清单**扩大解释**成"什么都剥"，是最常见的误读；B 把 `context_schema` 的类型约束当成权限校验，而它只约束结构、不管取值可信度；D 把 `channel` 的"来源可信"错记成"权限可信"——`channel` 是撕不掉的快递单，只认来源。

---

## 用户作答

> 待作答。作答后逐题反馈 `✅ 正确` / `❌ 错误（正确答案 X）`，并把结果回填本节的 `作答` 与 `是否正确` 两列。

| 题号 | 作答 | 是否正确 |
|------|------|---------|
| Q1 | — | 待判 |
| Q2 | — | 待判 |
| Q3 | — | 待判 |
| Q4 | — | 待判 |
| Q5 | — | 待判 |
| Q6 | — | 待判 |

## 本轮成绩单

- 正确率：待作答后计算（口径：答对题数 / 6）
- 各知识点掌握情况：待作答后填写
- 与上一轮对比：**本轮为首轮，无历史基线**

## 事实核查留痕

- 声明层 `define_schedule` 无 `new_thread`、`thread={"mode":"persistent","id":...}` 可用：探针 venv `/tmp/mda-probe/k4/a/.venv`（`managed_deepagents 0.9.5`）实测 + `inspect.signature`。
- `DeepAgentDefinition` 为 frozen dataclass、`config` 为 dict、编译发生在 `runtime.py:981`：读 `define_deep_agent.py` 全文与 `runtime.py` 源码确认。
- `permissions` 被清空：`runtime.py:1127` 与 `1188` 两处 `merged["permissions"] = []`，条件为 `sandbox_backend is not None`。
- 技能只扫一层、frontmatter 静默跳过、10 MB 上限、`name` 小写连字符：课 4 知识点 2 的七态实测表。
- 13 个保留键全剥、业务字段保留：课 7 知识点 1 与实验一实测输出。
