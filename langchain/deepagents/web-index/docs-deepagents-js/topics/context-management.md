# context · 上下文管理（TS 版）

> 覆盖：skills / memory / context-engineering / multimodal / rag
> 对应课程：课 7-9

| 页面 | URL | 解决什么 | 本课程在哪用 |
|---|---|---|---|
| Skills | https://docs.langchain.com/oss/javascript/deepagents/skills.md | 按需加载的技能包 | 课 7 |
| Memory | https://docs.langchain.com/oss/javascript/deepagents/memory.md | 跨会话记住项目规范 | 课 8 |
| Context engineering | https://docs.langchain.com/oss/javascript/deepagents/context-engineering.md | 长任务不爆上下文 | 课 9 |
| Multimodal | https://docs.langchain.com/oss/javascript/deepagents/multimodal.md | 多模态输入输出 | 课 9 延伸 |
| RAG | https://docs.langchain.com/oss/javascript/deepagents/rag.md | 接检索增强 | 课 9 延伸 |

## 与 Python 版的差异提醒

- `multimodal` 与 `rag` 两页 TS 版独有；Python 侧对应能力分散在 LangChain 主教程
- `skills` / `memory` / `context-engineering` 三页两侧概念一一对应，路径约定一致
- TS 侧有 `MULTIMODAL_BLOCK_TYPES` 常量（Python 无同名导出），处理多模态块时以 TS 文档为准
