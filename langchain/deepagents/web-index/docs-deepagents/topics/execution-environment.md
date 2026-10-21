# execution-environment · 执行环境（6 条）

> 范围：/oss/python/deepagents 下的执行环境类页面
> 一句话定位：agent "在哪动手、能动手到什么程度"

| # | 页面 | URL | 一句话 | 课程落点 |
|---|------|-----|--------|----------|
| 1 | Tools | https://docs.langchain.com/oss/python/deepagents/tools.md | 自定义函数 / LangChain 工具 / 任意 MCP 服务都走 `tools=` | 课 3、课 4 |
| 2 | Backends | https://docs.langchain.com/oss/python/deepagents/backends.md | 内存 state / 本地磁盘 / Store / 组合路由 / 自定义后端 | 课 4 |
| 3 | Permissions | https://docs.langchain.com/oss/python/deepagents/permissions.md | 声明式规则，按声明顺序 first-match-wins | 课 5 |
| 4 | Multimodal inputs and outputs | https://docs.langchain.com/oss/python/deepagents/multimodal.md | 图片 / 音频 / 视频 / 文档进工具结果 | 课 4 |
| 5 | Sandboxes | https://docs.langchain.com/oss/python/deepagents/sandboxes.md | 隔离环境执行 shell，暴露 `execute` 工具 | 课 6 |
| 6 | Interpreters | https://docs.langchain.com/oss/python/deepagents/interpreters.md | QuickJS 作用域内跑 JS，暴露 `eval` 工具 | 课 6 |

## 关键结论备忘

- **内置文件工具清单**（7 个）：`ls` / `read_file` / `write_file` / `edit_file` / `delete` / `glob` / `grep`；沙箱后端再额外提供 `execute`
- `delete` 需 `deepagents>=0.7`；后端不支持删除时该工具**自动从模型可见工具中隐藏**（不是报错）
- `read_file` 带行号、支持 offset/limit，非文本文件可返回多模态内容块
- 权限只作用于**内置文件工具**，**对沙箱后端的 `execute` 无效** —— 这是最容易误判安全边界的地方
- 沙箱后端实现 `SandboxBackendProtocolV2`，被检测到时 harness 才加 `execute` 工具
- 解释器**不提供** shell、装包、文件与网络访问 —— 它只管"轻量可编程"
