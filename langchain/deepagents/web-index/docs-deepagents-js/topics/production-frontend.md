# production · 生产化与前端（TS 版）

> 覆盖：event-streaming / streaming / fault-tolerance / going-to-production / acp / ag-ui / frontend / profiles / content-builder
> 对应课程：课 13

| 页面 | URL | 解决什么 | 本课程在哪用 |
|---|---|---|---|
| Event streaming | https://docs.langchain.com/oss/javascript/deepagents/event-streaming.md | 流式吐出子代理过程 | 课 13 |
| Streaming | https://docs.langchain.com/oss/javascript/deepagents/streaming.md | 通用流式接口 | 课 13 |
| Fault tolerance | https://docs.langchain.com/oss/javascript/deepagents/fault-tolerance.md | 重试 / 次数上限 / 降级 | 课 13 |
| Going to production | https://docs.langchain.com/oss/javascript/deepagents/going-to-production.md | 上线检查清单 | 课 13 |
| ACP | https://docs.langchain.com/oss/javascript/deepagents/acp.md | 接 IDE 协议 | 课 13 延伸 |
| AG-UI | https://docs.langchain.com/oss/javascript/deepagents/ag-ui.md | 接前端协议 | 课 13 延伸 |
| Frontend | https://docs.langchain.com/oss/javascript/deepagents/frontend.md | 前端集成总览 | 课 13 延伸 |
| Profiles | https://docs.langchain.com/oss/javascript/deepagents/profiles.md | 可复用配置档 | 课 13 延伸 |
| Content builder | https://docs.langchain.com/oss/javascript/deepagents/content-builder.md | 官方实战案例 | 课 13 延伸 |

## 与 Python 版的差异提醒

- `streaming`、`frontend`、`profiles`、`content-builder`、`going-to-production` 五页 TS 版独有
- 流式 v3 入口语义两侧一致：Python `stream_events(..., version="v3")`，TS `streamEvents(input, { version: "v3" })`
- `profiles` / `harnessProfile` 系列是 TS 包内部脚手架（`createHarnessProfile` 等），Python 侧无对应导出，本课程不展开
