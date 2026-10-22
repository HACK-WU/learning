# get-started · 入门（TS 版）

> 覆盖：overview / quickstart / customization / comparison
> 对应课程：课 1-3

| 页面 | URL | 解决什么 | 本课程在哪用 |
|---|---|---|---|
| Overview | https://docs.langchain.com/oss/javascript/deepagents/overview.md | 定位、与 createAgent 和 LangGraph 的分工 | 课 2 |
| Quickstart | https://docs.langchain.com/oss/javascript/deepagents/quickstart.md | 最小可运行示例 | 课 1、课 3 |
| Customization | https://docs.langchain.com/oss/javascript/deepagents/customization.md | 换模型、改 prompt、加工具、配子代理 | 课 3、课 10 |
| Comparison | https://docs.langchain.com/oss/javascript/deepagents/comparison.md | 与 Claude Agent SDK 的异同 | 课 2 延伸阅读 |

## 与 Python 版的差异提醒

- `comparison` 页 Python 版无同名 slug，属 TS 版独有
- `quickstart` 两侧示例代码形态不同（`create_deep_agent(...)` vs `createDeepAgent({...})`），概念一一对应
- `customization` 中 TS 版列出的 `streamTransformers` 是 TS 独有参数，Python 版无对应项
