# execution · 执行环境（TS 版）

> 覆盖：backends / permissions / sandboxes / interpreters / tools / models
> 对应课程：课 4-6

| 页面 | URL | 解决什么 | 本课程在哪用 |
|---|---|---|---|
| Backends | https://docs.langchain.com/oss/javascript/deepagents/backends.md | 文件存哪：内存 / 磁盘 / Store / 路由 | 课 5 |
| Permissions | https://docs.langchain.com/oss/javascript/deepagents/permissions.md | 限制可读写路径 | 课 5 |
| Sandboxes | https://docs.langchain.com/oss/javascript/deepagents/sandboxes.md | 隔离执行 shell | 课 6 |
| Interpreters | https://docs.langchain.com/oss/javascript/deepagents/interpreters.md | 轻量可编程层（跑 JS，不碰 shell） | 课 6 |
| Tools | https://docs.langchain.com/oss/javascript/deepagents/tools.md | 自定义工具与 MCP 接入 | 课 4 |
| Models | https://docs.langchain.com/oss/javascript/deepagents/models.md | 换模型、provider 前缀写法 | 课 3、课 4 |

## 与 Python 版的差异提醒

- `models` 页 TS 版独有；Python 侧模型说明散在 `customization` 与 LangChain 主教程中
- 解释器两侧跑的都是 JavaScript，但依赖包不同：TS 是 `@langchain/quickjs`，Python 是 `langchain-quickjs`
- 工具名 8 个（`ls/read_file/write_file/edit_file/delete/glob/grep/execute`）两侧完全一致，可直接对照阅读
