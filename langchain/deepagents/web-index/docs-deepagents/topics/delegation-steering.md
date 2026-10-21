# delegation-steering · 委派与人工干预（4 条）

> 范围：/oss/python/deepagents 下的委派与 steering 类页面
> 一句话定位：agent "怎么把活分出去、人怎么在关键处插手"

| # | 页面 | URL | 一句话 | 课程落点 |
|---|------|-----|--------|----------|
| 1 | Subagents | https://docs.langchain.com/oss/python/deepagents/subagents.md | 内建 `task` 工具 / isolated vs fork / 默认 general-purpose | 课 10、课 12 |
| 2 | Dynamic subagents | https://docs.langchain.com/oss/python/deepagents/dynamic-subagents.md | 用解释器在代码里派发与编排子代理 | 课 12 |
| 3 | Async subagents | https://docs.langchain.com/oss/python/deepagents/async-subagents.md | 后台并行跑，支持中途 steering | 课 12 |
| 4 | Human-in-the-loop | https://docs.langchain.com/oss/python/deepagents/human-in-the-loop.md | `interrupt_on` 声明哪些工具执行前要审批 | 课 11 |

## 关键结论备忘

- 子代理三类执行特征：**上下文隔离/继承可选**（默认 `mode: "isolated"`，`fork` 继承父对话）、**自主执行到完成**、**只返回一份最终报告**、**无状态**（不能多次回话）
- **任务规划（`write_todos`）自 v0.7 起为 opt-in**：需显式传 `TodoListMiddleware`；早期版本默认包含
- 默认带一个 `general-purpose` 子代理；也可自定义子代理
- 想彻底去掉 `task` 工具：官方文档有「Running without subagents」小节
- HITL 用 `interrupt_on={"edit_file": True}` 这种"工具名 → 配置"映射；底层接的是 LangGraph interrupt
