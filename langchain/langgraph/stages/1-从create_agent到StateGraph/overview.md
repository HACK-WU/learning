# 阶段 1：从 create_agent 到 StateGraph

> 章节定位：「把方向盘拿回来」——你已经会跑 agent，但循环不在你手里。本阶段把控制流显式写出来。

## 阶段目标

1. 装好 LangGraph 环境，能本地起服务并用 Studio 看一个图的执行
2. 说清 LangGraph 与 LangChain `create_agent` 的分工——什么时候该下沉
3. 用 StateGraph 定义 state / node / edge，跑通第一个带条件分支与循环的图

## 学习重点

- **心智模型优先**：`thinking-in-langgraph` 是本阶段的地基，state / node / edge / superstep 四个词要能在不看文档的情况下讲给别人听
- **workflow vs agent 的分界**决定了后面所有设计选择：固定流程用 workflow，需要模型决策才用 agent
- **reducer 是 LangGraph 最容易踩坑的地方**——默认覆盖 vs 追加，状态"消失"多半栽在这

## 必须掌握的知识点

| 课 | 知识点 | 关键点 |
|----|--------|--------|
| 课 1 环境准备 | 环境准备 | 最小环境集 / 主路径与备选 / 验证命令 / 常见安装坑 / 可跳过声明 |
| 课 2 LangGraph 是什么 | LangGraph 在生态中的位置 | LangChain 与 LangGraph 的分层 / create_agent 建立在 LangGraph 之上 / 什么时候下沉 |
| 课 2 | 用图思考 | state / node / edge / superstep 四件套 / 与"线性脚本"的对照 |
| 课 2 | workflow 与 agent | 固定流程 vs 模型决策 / 选型判据 |
| 课 3 Graph API 第一个图 | State 的定义与 reducer | TypedDict 与 dataclass / reducer 是什么 / 默认覆盖的坑 |
| 课 3 | 节点与边 | 节点是函数 / START 与 END / add_node / add_edge |
| 课 3 | 条件边与循环 | add_conditional_edges / 回到自己的边 / recursion_limit 兜底（机制层见课 4） |
