# 源码解析总索引

> 一键跳转全部源码解析。适用：**限库 / SDK / 框架类主题**（LangGraph 是 Python 库，符合）。过三问才配：有源码可讲 + 讲源码带来认知增量 + 规模可控（单类 / 单函数级别）。
> 未编写 = 纯文本；已编写 = 可点击链接。

## 阶段 2：执行模型与状态持久化

| 课 | 场景 | 覆盖知识点 | 链接 |
|----|------|-----------|------|
| 课 4 Pregel 执行模型 | 一个 superstep 是怎么被调度出来的 | 超级步执行模型 / Send / Command | [04-Pregel 执行模型.md](04-Pregel%20%E6%89%A7%E8%A1%8C%E6%A8%A1%E5%9E%8B.md) |
| 课 5 Checkpointer 短期记忆 | checkpoint 里到底存了什么、怎么被读写 | checkpoint 与 thread_id / 断点续跑 | [05-Checkpointer 短期记忆.md](05-Checkpointer%20%E7%9F%AD%E6%9C%9F%E8%AE%B0%E5%BF%86.md) |
## 阶段 3：可控性与人在环中

| 课 | 场景 | 覆盖知识点 | 链接 |
|----|------|-----------|------|
| 课 8 Interrupts 人在环中 | `interrupt()` 抛出后执行流怎么被接住与恢复 | interrupt 机制 / 审批流落地 | [08-Interrupts 人在环中.md](08-Interrupts%20%E4%BA%BA%E5%9C%A8%E7%8E%AF%E4%B8%AD.md) |

> **版本锚点**：源码一律引用本机实测基线 `langgraph 1.2.11`（见 `../00-学习档案.md`），并标注 `源码锚点 @ 1.2.11（{仓库 / 文件}）`。升级后须重跑校验，不凭记忆写旧版本行为。
