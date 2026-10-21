# get-started · 入门与定位（6 条）

> 范围：/oss/python/deepagents 下的定位与起跑类页面
> 用法：先看本表定位页面，再打开 URL 取正文

| # | 页面 | URL | 一句话 | 课程落点 |
|---|------|-----|--------|----------|
| 1 | Deep Agents overview | https://docs.langchain.com/oss/python/deepagents/overview.md | 六大能力 + 三大组件（执行环境 / 上下文管理 / 委派与steering）全景 | 课 2、课 3 |
| 2 | Quickstart | https://docs.langchain.com/oss/python/deepagents/quickstart.md | 装包 → 配 key → `create_deep_agent` → 跑研究代理 | 课 1、课 3 |
| 3 | Customize Deep Agents | https://docs.langchain.com/oss/python/deepagents/customization.md | system prompt / tools / subagents / middleware / memory 五类定制入口 | 课 3、课 11 |
| 4 | Models | https://docs.langchain.com/oss/python/deepagents/models.md | `provider:model` 字符串与已初始化模型两种写法 | 课 2、课 3 |
| 5 | Comparison with Claude Agent SDK | https://docs.langchain.com/oss/python/deepagents/comparison.md | 与 Anthropic harness 的取舍对照 | 课 2（选型决策） |
| 6 | Profiles | https://docs.langchain.com/oss/python/deepagents/profiles.md | 按 provider / 模型打包默认参数 | 课 2 |

## 关键结论备忘

- Deep Agents **不是新框架**：官方明确它是"agent harness"，核心仍是 tool calling loop，只是把常用能力预先组装好
- 依赖关系：`deepagents` 建在 **LangChain** 的核心构件之上，用 **LangGraph** 运行时做 durable execution / streaming / HITL
- 不用它时的替代：`create_agent`（要自控）或自定义 LangGraph workflow（要完全掌控）
- 模型硬要求：必须支持 tool calling
