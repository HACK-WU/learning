# 值班研究助手

## 一句话需求

把"每天谁值班、现在有什么告警、该先处理哪个"这件事交给一个托管 agent：它在 Slack 里被 @ 时回答，每天早八点自动发一份晨报，需要升级时先验证是谁在操作。

## 目标

学完 9 课之后，把散装知识点焊成一个能真跑的东西。这个项目要证明的不是"我会调 API"，而是：

- 能把 agent 组织成**一个目录里的文件**（提示词、技能、工具、记忆、沙箱、身份、调度、通道各就各位）
- 能说清**哪些能力只能声明不能编码**（沙箱只有一种、记忆是空树、通道由平台代办）
- 能对"这个人有没有权限"给出**经得起追问的答案**（不看 context，只看 principal）
- 能在**同一份逻辑**里算清几个真实取舍的代价

## 覆盖知识点地图

| 知识点 | 阶段 / 课 | 落点文件 |
|---|---|---|
| 托管的边界：什么被接管、什么只能声明 | 阶段 1 · 课 2 | [README](#设计取舍速查)、`agent.py` 头注释 |
| 静态入口约束（`name` 必须是字面量） | 阶段 1 · 课 3 | [agent.py](实现/duty-assistant/agent.py) |
| 指令文件与技能目录 | 阶段 2 · 课 4 | [instructions.md](实现/duty-assistant/instructions.md)、[SKILL.md](实现/duty-assistant/skills/duty-runbook/SKILL.md) |
| 工具必须在入口点名 | 阶段 2 · 课 4 | [agent.py](实现/duty-assistant/agent.py)、[tools/duty.py](实现/duty-assistant/tools/duty.py) |
| 中间件的取舍（为什么这里不用） | 阶段 2 · 课 5 | [设计决策.md](设计决策.md) 决策 4 |
| 记忆两层：agent 共用 / user 私有 | 阶段 2 · 课 6 | [memory.py](实现/duty-assistant/memory.py) |
| 沙箱与权限互斥（静默清空） | 阶段 2 · 课 6 | [sandbox/\_\_init\_\_.py](实现/duty-assistant/sandbox/__init__.py) |
| 身份模式决定 principal 是否存在 | 阶段 2 · 课 6 | [identity.py](实现/duty-assistant/identity.py) |
| 运行时三源与信任级别（context 不判权限） | 阶段 3 · 课 7 | [tools/duty.py](实现/duty-assistant/tools/duty.py) |
| 通道：Slack 由平台代办、地址带 `/v1` | 阶段 3 · 课 8 | [channels/slack.py](实现/duty-assistant/channels/slack.py) |
| 调度：时区必须显式、线程策略要选 | 阶段 3 · 课 8 | [schedules/morning_digest.py](实现/duty-assistant/schedules/morning_digest.py) |
| 部署预检与 Context Hub 冲突 | 阶段 3 · 课 9 | [验收清单.md](验收清单.md) 第 4 组 |
| 评估与迁移判据 | 阶段 3 · 课 9 | [设计决策.md](设计决策.md) 决策 3 |

覆盖三个阶段全部 3 个阶段的 13 个知识点。

## 运行方式

```bash
cd 实现/duty-assistant

# 只验证声明结构（不需要任何 key，不联网）
uv run mda build

# 本地起服务（需要 LANGSMITH_API_KEY；见下方"本地启动的三个前置条件"）
uv run mda dev

# 部署（需要 LANGSMITH_API_KEY + .env 里的模型 key）
uv run mda deploy
```

### 本地启动的三个前置条件（实测，缺一不可）

本项目的声明组合有真实门槛，第一次 `mda dev` 大概率起不来。按顺序检查：

1. **必须有 `identity.py`** —— 因为有 Slack 通道（ingress trigger）。删掉它报：
   `channels/ or connectors/ with an ingress trigger ... require a root identity declaration; ingress triggers cannot fall back to a deployment service principal`
2. **开 user 层记忆就不能用默认 API key 模式** —— 报 `user-owned connections, managed tools, and user memory require LANGSMITH_API_KEY under mda dev`
3. **假 key 过不了身份校验** —— 报 `LangSmith could not identify the API key owner: Forbidden (HTTP 403)`

只跑 agent 逻辑、不验身份时，可以把 `identity.py` 临时改成 `auth="backend"`，此时不需要 LangSmith key 也能起来（实测可启动，Slack 路由正常注册）。

## 目录说明

```text
实现/duty-assistant/
├── agent.py                       入口：把五类声明拼起来（唯一要"写代码"的地方）
├── instructions.md                角色与三条硬约束
├── skills/duty-runbook/SKILL.md   事故初判手册（按需加载，不占常驻上下文）
├── tools/duty.py                  三个工具：两个只读、一个写且要验身份
├── memory.py                      agent 层（团队约定）+ user 层（个人偏好）
├── sandbox/__init__.py            沙箱声明（同时意味着 permissions 失效）
├── identity.py                    身份来源（决定 principal 与 user 记忆是否可用）
├── schedules/morning_digest.py    工作日早八点晨报
├── channels/slack.py              Slack 入口（地址带 /v1）
└── pyproject.toml                 依赖
```

## 设计取舍速查

四个真实取舍的详细推演见 [设计决策.md](设计决策.md)，这里只放结论：

| # | 取舍点 | 选了什么 | 代价 |
|---|---|---|---|
| 1 | 权限判断放工具里还是提示词里 | 工具里（读 `principal`） | 每个写工具都要自己写一遍判空 |
| 2 | 晨报用临时线程还是持久线程 | 临时（默认） | 昨天的晨报查不到，要翻 Slack 历史 |
| 3 | 该不该迁到托管 | 该（四门槛全否） | 失去自定义 backend 与自定义路由的自由 |
| 4 | 要不要加中间件做人工审批 | 不加，用工具内 interrupt 语义替代 | 审批状态要自己管，不能靠平台 |

## 相关文档

- [设计决策.md](设计决策.md)：四个取舍的五段式推演
- [反例对照.md](反例对照.md)：一版"看起来能跑"的糟糕实现
- [验收清单.md](验收清单.md)：怎么确认自己真的做成了
