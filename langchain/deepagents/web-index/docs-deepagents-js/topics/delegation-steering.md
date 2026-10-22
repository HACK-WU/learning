# delegation · 委派与编排（TS 版）

> 覆盖：subagents / async-subagents / dynamic-subagents / human-in-the-loop / retrieval
> 对应课程：课 10-12

| 页面 | URL | 解决什么 | 本课程在哪用 |
|---|---|---|---|
| Subagents | https://docs.langchain.com/oss/javascript/deepagents/subagents.md | 主代理派活给子代理 | 课 10 |
| Async subagents | https://docs.langchain.com/oss/javascript/deepagents/async-subagents.md | 后台并行、可中断改主意 | 课 12 |
| Dynamic subagents | https://docs.langchain.com/oss/javascript/deepagents/dynamic-subagents.md | 运行时动态决定派谁 | 课 12 |
| Human-in-the-loop | https://docs.langchain.com/oss/javascript/deepagents/human-in-the-loop.md | 高危操作要人确认 | 课 11 |
| Retrieval | https://docs.langchain.com/oss/javascript/deepagents/retrieval.md | 子代理取回结果的机制 | 课 10 延伸 |

## 与 Python 版的差异提醒

- `dynamic-subagents` 与 `retrieval` 两页 TS 版独有
- `async-subagents` 两侧概念对应，但本课程实测结论「异步/动态子代理不提速」是通用结论，两版均适用
- `human-in-the-loop` 参数名两侧不同：Python `interrupt_on`，TS `interruptOn`
