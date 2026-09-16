# 阶段 1：入门与模型层

> 所属课程：LangChain 系统学习 ｜ 故事章节："认识主角：模型与它的语言" ｜ 上一阶段：无（起点）

## 🎯 本阶段目标

- 说清 LangChain 的定位、演化逻辑与生态关系（LangChain / LangGraph / Deep Agents / LangSmith 各管什么）
- 建立 "Agent = Model + Harness" 的全局心智模型，理解 agent loop 是什么
- 能在本机接入自定义 LLM API（URL + Key）并跑通第一个 create_agent

## 📍 学习重点

- **起源与 1.0 大重构**：理解"为什么 chains 被砍掉、只留 create_agent"——这是新版 LangChain 一切设计的前提
- **Agent = Model + Harness**：全课程最重要的思维框架，后续每个组件都是 harness 的一部分
- **模型接入（含自定义 endpoint）**：实操的入场券，用户自备 API 的接入方式与排查方法
- **标准消息体系**：消息是后续所有组件（工具、记忆、流式）的数据基元，必须先立住

## ✅ 必须掌握的知识点

| 知识点 | 所属课 | 学完应能 |
|--------|--------|----------|
| LangChain 的起源与演进史 | 课 1 | 能说清 chains → LangGraph → create_agent 的演化逻辑与原因 |
| Agent = Model + Harness | 课 1 | 能用自己的话解释 agent loop 与 harness 各是什么 |
| 安装与第一个 Agent | 课 1 | 能本机跑通第一个 create_agent 并看到回复 |
| 模型初始化的两种方式 | 课 2 | 能用 init_chat_model 与 Model Class 两种方式初始化模型 |
| 自定义 endpoint 接入 | 课 2 | 能接入自定义 API（base_url + api_key）并排查常见错误 |
| 模型参数与调用方式 | 课 2 | 会用 invoke / stream / batch 与常用参数 |
| 模型能力探测与多模态 | 课 2 | 能查模型 profile、理解多模态与 reasoning 内容 |
| 为什么需要标准消息格式 | 课 3 | 能解释厂商差异与标准化的价值 |
| 四类消息与角色 | 课 3 | 能说出 System / Human / AI / Tool 的分工与流转 |
| 消息内容与多模态 | 课 3 | 能构造含文本/图片的 content blocks |
| 构造、字典与序列化 | 课 3 | 能用对象与字典两种格式构造消息 |

## 🗺️ 本阶段路径图

![阶段 1 路径](./assets/stage-01-path.svg)

> SVG 展示本阶段三课的学习顺序与依赖。

## 本阶段产出

- [x] `lessons/lesson-01-LangChain是什么.md`
- [x] `lessons/lesson-02-Models模型层.md`
- [x] `lessons/lesson-03-Messages消息体系.md`
