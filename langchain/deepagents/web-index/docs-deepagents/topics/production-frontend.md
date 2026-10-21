# production-frontend · 生产化、流式、前端与协议（14 条）

> 范围：/oss/python/deepagents 下的上线、流式、前端与协议类页面
> 一句话定位：agent "怎么接出去、怎么让人看见它在干什么"

## 生产化

| # | 页面 | URL | 一句话 | 课程落点 |
|---|------|-----|--------|----------|
| 1 | Going to production | https://docs.langchain.com/oss/python/deepagents/going-to-production.md | 持久记忆 / 沙箱 / 韧性中间件 / 部署选项 | 课 13 |
| 2 | Fault tolerance | https://docs.langchain.com/oss/python/deepagents/fault-tolerance.md | 重试 / 次数上限 / 降级 / 错误处理 | 课 13 |

## 流式

| # | 页面 | URL | 一句话 | 课程落点 |
|---|------|-----|--------|----------|
| 3 | Streaming | https://docs.langchain.com/oss/python/deepagents/streaming.md | deep agent 与子代理执行的实时更新 | 课 13 |
| 4 | Event streaming | https://docs.langchain.com/oss/python/deepagents/event-streaming.md | 类型化投影；`stream.subagents` 每个委派任务一个句柄 | 课 13 |

## 前端

| # | 页面 | URL | 一句话 | 课程落点 |
|---|------|-----|--------|----------|
| 5 | Frontend overview | https://docs.langchain.com/oss/python/deepagents/frontend/overview.md | 展示子代理流 / 任务进度 / 沙箱的 UI | 延伸 |
| 6 | Subagent streaming | https://docs.langchain.com/oss/python/deepagents/frontend/subagent-streaming.md | 可折叠卡片展示专家子代理 | 延伸 |
| 7 | Todo list | https://docs.langchain.com/oss/python/deepagents/frontend/todo-list.md | 从 agent state 同步的实时待办 | 延伸 |
| 8 | Sandbox (frontend) | https://docs.langchain.com/oss/python/deepagents/frontend/sandbox.md | 类 IDE 的编码 agent 界面 | 延伸 |

## 协议

| # | 页面 | URL | 一句话 | 课程落点 |
|---|------|-----|--------|----------|
| 9 | Agent Client Protocol (ACP) | https://docs.langchain.com/oss/python/deepagents/acp.md | 暴露给编辑器 / IDE | 延伸 |
| 10 | Agent User Interaction Protocol (AG-UI) | https://docs.langchain.com/oss/python/deepagents/ag-ui.md | 把事件流给任意 AG-UI 客户端 | 延伸 |

## 官方教程

| # | 页面 | URL | 一句话 | 课程落点 |
|---|------|-----|--------|----------|
| 11 | Build a deep research agent | https://docs.langchain.com/oss/python/deepagents/deep-research.md | 子代理委派做多步网络研究 | 结课项目素材 |
| 12 | Build a content builder agent | https://docs.langchain.com/oss/python/deepagents/content-builder.md | 品牌记忆 + 技能 + 子代理 + 图像生成 | 结课项目素材 |
| 13 | RAG with Deep Agents | https://docs.langchain.com/oss/python/deepagents/rag.md | skills 引导检索 / rubric 评分 | 结课项目素材 |
| 14 | （回链）LangChain middleware | https://docs.langchain.com/oss/python/langchain/middleware/overview.md | `deepagents/middleware` 已 307 迁到此处 | 课 9、课 13 |

## 关键结论备忘

- 前端四页与协议两页**不属主线**（对应 `01-学习路径总览.md` 的延伸方向），只做定位级介绍，不展开实现
- 三篇官方教程是 Phase 3 结课项目的参考素材，不逐课讲
- 流式侧的关键增量是 `stream.subagents`：每个被委派的任务拿到独立句柄，含独立的消息 / 工具调用 / 嵌套子代理流
