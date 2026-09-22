# LangChain 生态学习（统一父目录）

> 本目录是 LangChain 生态各组件学习课程的统一父目录，按官方文档站的组件分区组织（官方导航：Overview / Deep Agents / Managed Deep Agents / LangChain / LangGraph / OpenWiki / Integrations / Learn / Reference）。
> 每个子目录 = 一个组件课程，课程之间相互独立、可各自开课。

## 基础前置课

> 不是官方组件，是**学组件前建议先补的底层认知**。

| 子目录 | 课程 | 状态 | 入口 |
|--------|------|------|------|
| [llm-fundamentals/](./llm-fundamentals/) | 大模型本质认知（token / 预训练 / 对齐 / 采样 / 上下文 / 缺陷 ↔ 组件） | 🚧 进行中（3 阶段 / 9 课 / 27 知识点） | [学习档案](./llm-fundamentals/00-学习档案.md) · [学习路径总览](./llm-fundamentals/01-学习路径总览.md) · [课程目录](./llm-fundamentals/02-课程目录.md) |

## 组件课程清单

| 子目录 | 组件 | 状态 | 入口 |
|--------|------|------|------|
| [langchain/](./langchain/) | LangChain（基础组件） | ✅ 已完成（4 阶段 / 13 课 / 44 知识点 + 结课实战项目 + 收尾四件套） | [学习档案](./langchain/00-学习档案.md) · [学习路径总览](./langchain/01-学习路径总览.md) · [课程手册](./langchain/final-课程手册.md) |
| langgraph/ | LangGraph（底层编排） | ⬜ 规划中 | - |
| 其他组件 | Deep Agents / Managed Deep Agents / OpenWiki 等 | ⬜ 待定 | - |

## 说明

- 组件课程统一体例：课程制（阶段 → 课 → 知识点）、双视角评审、学习档案回写、目录内 `web-index/` 官方文档索引
- 断点续学：进入对应组件子目录，读 `00-学习档案.md` 找第一个未完成的知识点

## 阅读顺序建议

- **`llm-fundamentals/` → `langchain/`**（推荐）：先懂"大模型缺什么"，学组件时看到的是机制而不是 API 列表
- **已学完 `langchain/` → 回头补 `llm-fundamentals/`**：同样成立，带着实操疑问回看原理反而更容易共鸣
- 两门课**双向回扣**：`llm-fundamentals` 每课的「体系收束」幕显式指向 `langchain/` 的对应课
