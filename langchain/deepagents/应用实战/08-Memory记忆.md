# 应用实战 · Memory 记忆

> 对应课程：[第 8 课：Memory 记忆](../stages/3-上下文管理/lessons/08-Memory记忆.md) ｜ 覆盖知识点：AGENTS.md 与 memory 参数、全量加载 vs 按需加载、后端落点与 agent 自更新
> 定位：**会用，不上生产**——课里学完，在这里动手。
> ✅ 本文全部代码在 `deepagents 0.7.28` / `langchain 1.4.6` 下实测（假模型驱动真实 agent 图，不发网络请求）
> ✅ TypeScript 侧实测于 2026-10-22 ｜ `deepagents 1.15.1` ｜ 对照 `playground-ts/l08-memory.ts`

> 🧭 **双语说明**：标 🇹🇸 的段落是 TS 侧实测补充。`AGENTS.md` 的格式与注入结构（`<agent_memory>` / `<memory_guidelines>`）两语言完全通用——那是提示词层的东西。差异在 `StoreBackend` 的构造签名：TS 收 `{ store, namespace }` 一个对象，Python 是关键字参数。

## 场景：给项目配一份"会自己长大"的记忆

**场景**：团队规范写在 `AGENTS.md` 里（用 ruff、行宽 100、禁止裸 except）。你想让 agent：

1. 一开工就知道这些规矩，不用每轮提醒
2. 换对话也记得（跨线程），别每次都从零开始
3. 你纠正它一次，它就记下来，下次自动照做
4. 但它别乱记、别记错，记错了你能看出来

**全貌一句话**：完整方案还包括按用户隔离（user-scoped）、后台整理（consolidation）、组织策略只读（权限）、记忆写进代码评审流程（都不是本课内容）。本课解决"让它记住、记对、能管"这一段。

---

### ① 基础实现（能跑但存不住）

![基础版：AGENTS.md 挂上去 + 固定税](./assets/app-step1-memory-basic.svg)

> 看图：左边是 `AGENTS.md` 的内容形态（正文 + 给人看的 HTML 注释）；中间是注入后的提示词结构（`<agent_memory>` 包内容、`<memory_guidelines>` 是固定底噪）；右边是"这笔税有多贵"的实测数字。注意：**注释不进模型眼，但正文字字都付钱**。

::: code-group

```python [Python]
import tempfile
from pathlib import Path

from langchain_core.language_models.chat_models import BaseChatModel
from langchain_core.messages import AIMessage
from langchain_core.outputs import ChatGeneration, ChatResult

from deepagents import create_deep_agent
from deepagents.backends import FilesystemBackend


# 1. 写一份 AGENTS.md -----------------------------
root = Path(tempfile.mkdtemp())
(root / "AGENTS.md").write_text(
    "<!-- 维护说明：本文件由 @platform-team 维护，改动走 PR -->\n"
    "# 项目规范\n\n"
    "## 代码风格\n"
    "- 用 ruff，行宽 100\n"
    "- 禁止裸 except，必须写明异常类型\n\n"
    "## 测试\n"
    "- pytest；新增分支必须有测试\n",
    encoding="utf-8",
)

# 2. 挂上去 ---------------------------------------
fsb = FilesystemBackend(root_dir=str(root), virtual_mode=True)
agent = create_deep_agent(
    model="openai:gpt-5.4",
    backend=fsb,
    memory=["/AGENTS.md"],
)


# 3. 验证它真的进了提示词
from langgraph.checkpoint.memory import InMemorySaver

agent = create_deep_agent(
    model="openai:gpt-5.4", backend=fsb, memory=["/AGENTS.md"],
    checkpointer=InMemorySaver(),
)
out = agent.invoke(
    {"messages": [{"role": "user", "content": "帮我写个函数"}]},
    config={"configurable": {"thread_id": "T1"}},
)
# 系统提示里出现 <agent_memory> ... 用 ruff，行宽 100 ... </agent_memory>
```

```typescript [TypeScript]
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createDeepAgent, FilesystemBackend } from "deepagents";
import { MemorySaver } from "@langchain/langgraph";

// 1. 写一份 AGENTS.md（格式两语言一致）
const root = mkdtempSync(join(tmpdir(), "mem-"));
writeFileSync(
  join(root, "AGENTS.md"),
  "<!-- 维护说明：本文件由 @platform-team 维护，改动走 PR -->\n"
    + "# 项目规范\n\n"
    + "## 代码风格\n"
    + "- 用 ruff，行宽 100\n"
    + "- 禁止裸 except，必须写明异常类型\n\n"
    + "## 测试\n"
    + "- pytest；新增分支必须有测试\n",
);

// 2. 挂上去
const fsb = new FilesystemBackend({ rootDir: root, virtualMode: true });
const agent = await createDeepAgent({
  model: "openai:gpt-4o-mini",
  backend: fsb,
  memory: ["/AGENTS.md"],
  checkpointer: new MemorySaver(),
});

// 3. 验证它真的进了提示词
await agent.invoke(
  { messages: [{ role: "user", content: "帮我写个函数" }] },
  { configurable: { thread_id: "T1" } },
);
// 系统提示里同样出现 <agent_memory> ... 用 ruff，行宽 100 ... </agent_memory>
```

:::

> ⚠️ **它的三个问题**：
> 1. **存不住**。默认 `StateBackend` 下，换 thread 记忆就没了（实测 T2 读不到 T1 写的）。这里用了 `FilesystemBackend` 才活过 thread，但换机器仍然没了。
> 2. **不知道多贵**。你无法回答"这篇 AGENTS.md 值不值"，因为没量过固定税。
> 3. **管不住它**。它默认就有 `edit_file` 写记忆的能力，可能乱记或记错，而你没有任何约束。

---

### ② 综合实现（被问题逼出来的下一步）

![综合版：迁到 Store + 打开自更新 + 管住笔](./assets/app-step2-memory-store.svg)

> 看图：橙框是相对基础版的三处变化——① 迁到 Store 后端让记忆真持久；② 量出固定税并据此瘦身；③ 打开自更新但用权限与 diff 管住。右侧标出 Store 那三个咬人的细节。

**变化一：迁到 StoreBackend，让记忆真持久**

::: code-group

```python [Python]
from langgraph.store.memory import InMemoryStore
from deepagents.backends import CompositeBackend, StateBackend, StoreBackend

store = InMemoryStore()

# seed 初始记忆：key 是剥掉路由前缀后的路径！
store.put(
    ("my-agent",),
    "/AGENTS.md",                    # 不是 "/memories/AGENTS.md"
    {
        "content": "# 项目规范\n- 用 ruff，行宽 100\n- 禁止裸 except\n",
        "encoding": "utf-8",
    },
)

backend = CompositeBackend(
    default=StateBackend(),
    routes={
        "/memories/": StoreBackend(
            store=store,
            namespace=lambda _rt: ("my-agent",),   # 必须是可调用
        )
    },
)

agent = create_deep_agent(
    model="openai:gpt-5.4",
    backend=backend,          # 必须是实例，不能是工厂
    memory=["/memories/AGENTS.md"],
    store=store,
    checkpointer=InMemorySaver(),
)
```

```typescript [TypeScript]
import { CompositeBackend, StateBackend, StoreBackend } from "deepagents";

const store = new InMemoryStore();

// seed 初始记忆：key 同样要剥掉路由前缀
// 注意 value 必须是 FileData：TS 没有 encoding 字段，必须有 created_at/modified_at
const now = new Date().toISOString();
await store.put(["my-agent"], "/AGENTS.md", {
  content: "# 项目规范\n- 用 ruff，行宽 100\n- 禁止裸 except\n",
  mimeType: "text/markdown",
  created_at: now,
  modified_at: now,
});

const backend = new CompositeBackend(new StateBackend(), {
  "/memories/": new StoreBackend({
    store,
    namespace: () => ["my-agent"],          // 必须是函数，返回值是数组不是元组
  }),
});

const agent = await createDeepAgent({
  model: "openai:gpt-4o-mini",
  backend,                                   // 实例，不能是工厂
  memory: ["/memories/AGENTS.md"],
  checkpointer: new MemorySaver(),
});
```

:::

🇹🇸 TS 侧三个坑与 Python 同源但形态不同：① `backend` 也必须是实例（TS 是强类型，传函数在编译期就报错，比 Python 的运行期 `TypeError` 更早）；② `namespace` 同样是**必须可调用**，但返回值是 `string[]` 不是元组；③ seed 的 key 一样要剥前缀，写 `"/memories/AGENTS.md"` 读不到。

🇹🇸 此外 TS 还有**第 4 个坑，方向相反**：store 里的 value 结构不同。Python 是 `{ content, encoding }`（`encoding` 必填，时间戳可选），TS 是 `FileData`——**没有 `encoding`，必须有 `created_at` / `modified_at`**。照抄 Python 写法不会抛错，而是静默读到 `(No memory loaded)`：

```text [TypeScript]
{ content, encoding }               → 含正文 false ｜ 含 "(No memory loaded)" true
{ content, created_at, modified_at } → 含正文 true  ｜ 含 "(No memory loaded)" false
```

Python 侧三个坑的实际报错：

```python
# ❌ 工厂函数（0.7 已移除）
backend=lambda rt: CompositeBackend(StateBackend(rt), {...})
# TypeError: backend must be an initialized backend instance.
#             Backend factories were removed in deepagents 0.7

# ❌ namespace 传元组
StoreBackend(store=store, namespace=("my-agent",))
# TypeError: 'tuple' object is not callable

# ❌ seed 到带前缀的 key
store.put(("my-agent",), "/memories/AGENTS.md", {...})
# 读不到——CompositeBackend 会剥掉 "/memories/" 再交给 StoreBackend
```

**变化二：量出固定税，据此决定写多少**

用一个假模型量系统提示长度：

::: code-group

```python [Python]
class Spy(BaseChatModel):
    @property
    def _llm_type(self):
        return "spy"

    def bind_tools(self, tools, **kwargs):
        return self

    def _generate(self, messages, stop=None, run_manager=None, **kwargs):
        SEEN.append(list(messages))
        return ChatResult(generations=[ChatGeneration(message=AIMessage(content="ok"))])


def measure_memory(agents_md_len: int):
    """量出固定税与正文的真实比例。"""
    root = Path(tempfile.mkdtemp())
    fsb = FilesystemBackend(root_dir=str(root), virtual_mode=True)
    body = "# 规范\n" + ("- 规则条目占位内容。\n" * (agents_md_len // 10 + 1))
    body = body[:agents_md_len]
    (root / "AGENTS.md").write_text(body, encoding="utf-8")

    SEEN.clear()
    create_deep_agent(model=Spy()).invoke(
        {"messages": [{"role": "user", "content": "go"}]})
    base = len(sys_of(SEEN[0]))

    SEEN.clear()
    create_deep_agent(model=Spy(), backend=fsb, memory=["/AGENTS.md"]).invoke(
        {"messages": [{"role": "user", "content": "go"}]})
    total = len(sys_of(SEEN[0]))
    return total - base, len(body)
```

```typescript [TypeScript]
class Spy extends BaseChatModel {
  constructor() { super({}); }            // 必须调，否则基类字段没初始化
  _llmType() { return "spy"; }            // 是方法不是 getter
  bindTools() { return this; }
  async _generate(messages: BaseMessage[]): Promise<ChatResult> {
    SEEN.push([...messages]);
    return { generations: [{ text: "ok", message: new AIMessage("ok") }] } as ChatResult;
  }
}

const measureMemory = async (agentsMdLen: number): Promise<[number, number]> => {
  const root = mkdtempSync(join(tmpdir(), "measure-"));
  const fsb = new FilesystemBackend({ rootDir: root, virtualMode: true });
  const body = ("# 规范\n" + "- 规则条目占位内容。\n".repeat(agentsMdLen / 10 + 1)).slice(0, agentsMdLen);
  writeFileSync(join(root, "AGENTS.md"), body, "utf-8");

  SEEN.length = 0;
  await (await createDeepAgent({ model: new Spy() as never }))
    .invoke({ messages: [{ role: "user", content: "go" }] });
  const base = sysOf(SEEN[0]).length;

  SEEN.length = 0;
  await (await createDeepAgent({ model: new Spy() as never, backend: fsb, memory: ["/AGENTS.md"] }))
    .invoke({ messages: [{ role: "user", content: "go" }] });
  const total = sysOf(SEEN[0]).length;
  return [total - base, body.length];
};
```

:::

实测结果：

```
AGENTS.md 正文   提示增量    固定税    固定税占比
            0      5,124     5,124     100.0%
          500      5,618     5,118      91.1%
        2,000      7,118     5,118      71.9%
       20,000     25,118     5,118      20.4%
```

> 🇹🇸 TS 侧曲线形状一样，但基数小一截（固定税 4,470 vs 5,124 字符，少约 13%）：正文 0 → 4,470、500 → 4,963、2,000 → 6,463。**结论不变**——正文从 500 涨到 2,000（多 1,500 字符），提示只涨 1,500，固定税一分没省。所以"精简正文"永远省不出那 4.5k。

> 🔍 **这组数字改变了一个常见决策**：很多人以为"AGENTS.md 要写得精简以省 token"。实测告诉你：**精简正文省下的钱，远小于固定税本身**。真正的省钱方式是"不该常驻的内容别放这里"（交给课 7 的 skills）。所以判断顺序是：先问"每轮都要用吗"，再问"写多长"。

> 🎯 **会用标志**：当有人说"把这堆规范都塞进 AGENTS.md 吧"，你能回一句："先看这些是不是每轮都要用；不是的话做成 skill，能省 5.1k 的固定税。"

**变化三：打开自更新，但管住它的笔**

`memory_guidelines` 已经鼓励它自己写，你不需要额外配置。要做的反而是"约束"：

::: code-group

```python [Python]
from deepagents import FilesystemPermission

# 方案 A：完全放开（适合个人助手）
agent_free = create_deep_agent(
    model="openai:gpt-5.4", backend=backend,
    memory=["/memories/AGENTS.md"], store=store,
    checkpointer=InMemorySaver(),
)

# 方案 B：组织策略只读，agent 只能改工作区（适合团队/生产）
agent_guarded = create_deep_agent(
    model="openai:gpt-5.4", backend=backend,
    memory=["/memories/AGENTS.md"], store=store,
    checkpointer=InMemorySaver(),
    permissions=[
        FilesystemPermission(operations=["write"], paths=["/memories/**"], mode="deny"),
        FilesystemPermission(operations=["read", "write"], paths=["/workspace/**"]),
    ],
)
```

```typescript [TypeScript]
// 方案 A：完全放开（适合个人助手）
const agentFree = await createDeepAgent({
  model: "openai:gpt-4o-mini", backend,
  memory: ["/memories/AGENTS.md"],
  checkpointer: new MemorySaver(),
});

// 方案 B：组织策略只读，agent 只能改工作区（适合团队/生产）
// TS 的 permission 是普通对象，mode 只有 "allow" / "deny"——没有 "interrupt"
const agentGuarded = await createDeepAgent({
  model: "openai:gpt-4o-mini", backend,
  memory: ["/memories/AGENTS.md"],
  checkpointer: new MemorySaver(),
  permissions: [
    { operations: ["write"], paths: ["/memories/**"], mode: "deny" },
    { operations: ["read", "write"], paths: ["/workspace/**"] },
  ],
});
```

:::

实测两者差异（两侧文案几乎逐字相同）：

```
方案 A：Successfully replaced 1 instance(s) of the string in '/memories/AGENTS.md'
方案 B：Error: permission denied for write on /memories/AGENTS.md
```

> 🇹🇸 TS 侧实测文案是 `Successfully replaced 1 occurrence(s)`（Python 是 `1 instance(s)`），拦截文案完全一致。TS 的 `mode` 只有 `allow` / `deny` 两档，**没有 `interrupt`**；需要"改动前先问人"的场景只能走 `interruptOn` 那一层。

> ⚠️ **权限拦的是中间件层，不是后端层**。实测：走中间件的 `write_file` / `edit_file` 会被 deny 拦住，但直接调 `backend.write("/memories/x.md", ...)` 一样能写进去。所以权限是"给 agent 用的护栏"，不是"数据层加密"——别指望它能防住你自己写的代码。

**加一道人工审查**：记忆是纯 Markdown，把它纳入 `git diff` 流程最有效。如果你用 `FilesystemBackend` 指向仓库，agent 的每次写入都会成为一次可见的 diff。

---

## 🔍 落盘前自检

| # | 检查项 | 结果 |
|---|--------|------|
| 1 | 形态：基础实现 → 问题 → 综合实现，两版可对比 | ✅ 基础版（挂上就走）→ 综合版（Store + 量化 + 权限） |
| 2 | 图 N 张：每步一张分步设计图 | ✅ 2 张（`app-step1-memory-basic.svg` / `app-step2-memory-store.svg`） |
| 3 | 图片语法：全部用相对路径指向真实文件 | ✅ 2/2 |
| 4 | assets：文件存在且 XML 合法 | ✅ `xmllint` 通过 |
| 5 | 读图指引与变化标注 | ✅ 每张图下有一句"看图：…"；第 2 步标出"橙框=3 处变化" |
| 6 | 索引与双入口 | ✅ 应用实战 INDEX / 课 8 正文 4.2 双入口 |
| 7 | 代码 review：所有代码与输出一致 | ✅ 固定税曲线 / 三坑报错文案 / 权限拦截均实测 |

---

## 🧭 导航

- ⬅️ 回到课程：[第 8 课：Memory 记忆](../stages/3-上下文管理/lessons/08-Memory记忆.md)
- 📚 全部实战：[应用实战索引](INDEX.md)
- ➡️ 下一课实战：09 · 上下文工程（待编写）
