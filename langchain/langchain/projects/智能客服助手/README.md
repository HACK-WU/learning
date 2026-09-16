# 实战项目：智能客服助手

> 所属课程：[LangChain 系统学习](../../01-学习路径总览.md) ｜ 学习目标：动手实操（组装完整应用） ｜ 预计耗时：2-3 小时（含实测）

## 🎯 一句话需求

为电商业务交付一个**可运行的智能客服 agent 工程**：政策咨询走企业知识库检索（RAG）、订单物流走业务工具、退款走分级人工审批（小额直通 / 大额审核），全程有会话记忆、PII 脱敏、成本护栏与三层测试，支持流式对话与人工接管。

## ✅ 目标与非功能约束

- **功能目标**：
  1. 政策类问题基于知识库回答（4 份政策文档，回答注明来源、不编造）
  2. 订单 / 物流 / 售后动作通过工具完成（6 个工具；退款执行前校验金额）
  3. 高风险操作有人把关（退款分级审批：≥ 阈值中断等人工决策，可批准 / 拒绝）
- **非功能约束**（4 项）：
  - **安全**：手机号 / 邮箱进入模型前自动脱敏（PII 中间件 + 自定义 detector）
  - **成本**：单会话模型调用上限（15 次）+ 退款工具每会话最多 2 次（限额中间件）
  - **错误处理**：工具失败返回结构化说明不崩溃；退款金额与订单实付不符时拒绝执行
  - **可维护性**：包结构分层（config / kb / tools / middleware / agent）+ 三层测试套件

## 🗺️ 覆盖知识点地图

> **这是「跨阶段整合」的证据，逐个回指课时。**

| 知识点 | 所属阶段 / 课 | 本项目用在何处 | 回指 |
|--------|--------------|---------------|------|
| Agent = Model + Harness 心智模型 | 阶段 1 · 课 1 | 整个工程的组装观：`agent.py` 管 harness，`config.py` 管 model | [lesson-01](../../stages/1-入门与模型层/lessons/lesson-01-LangChain是什么.md) |
| 模型初始化 / 自定义 endpoint | 阶段 1 · 课 2 | `app/config.py` `build_chat_model()`（OpenAI 兼容端点接入） | [lesson-02](../../stages/1-入门与模型层/lessons/lesson-02-Models模型层.md) |
| 消息体系（Human/AI/Tool） | 阶段 1 · 课 3 | 审批流消息序列：AI 工具调用冻结 → Tool 执行结果回填（`demo.py` 场景 3） | [lesson-03](../../stages/1-入门与模型层/lessons/lesson-03-Messages消息体系.md) |
| @tool 工具与错误处理 | 阶段 2 · 课 4 | `app/tools/`（6 个工具；金额校验不通过时返回说明而非抛异常） | [lesson-04](../../stages/2-Agent核心/lessons/lesson-04-Tools工具.md) |
| create_agent 组装 | 阶段 2 · 课 5 | `app/agent.py`（模型 + 工具 + 中间件 + 检查点） | [lesson-05](../../stages/2-Agent核心/lessons/lesson-05-Agents智能体核心.md) |
| 流式输出 | 阶段 2 · 课 6 | `app/cli.py` 打字机输出（`stream_mode="messages"` 混合模式） | [lesson-06](../../stages/2-Agent核心/lessons/lesson-06-Streaming流式输出.md) |
| 短期记忆（checkpointer） | 阶段 2 · 课 7 | `InMemorySaver` + thread_id：多轮对话记住上文（`demo.py` 场景 6） | [lesson-07](../../stages/2-Agent核心/lessons/lesson-07-Memory记忆.md) |
| 内置与自定义中间件 | 阶段 3 · 课 8 | `app/middleware/safety.py`：PII 脱敏 + 限额 + 自定义审计中间件 | [lesson-08](../../stages/3-可控性与可靠性/lessons/lesson-08-Middleware中间件.md) |
| 上下文工程（动态提示词） | 阶段 3 · 课 9 | `customer_prompt`：按运行时用户档案注入系统消息（会员等级影响回答） | [lesson-09](../../stages/3-可控性与可靠性/lessons/lesson-09-ContextEngineering上下文工程.md) |
| HITL 中断 / 条件中断 / 护栏 | 阶段 3 · 课 10 | 退款分级审批（`when` 谓词）；金额一致性校验护栏 | [lesson-10](../../stages/3-可控性与可靠性/lessons/lesson-10-人机协同与护栏.md) |
| RAG 知识库构建与检索 | 阶段 3 · 课 11 | `app/kb/loader.py` + `search_policies` 工具（Agentic RAG，k=3） | [lesson-11](../../stages/3-可控性与可靠性/lessons/lesson-11-Retrieval检索与RAG.md) |
| 多智能体（架构决策 / handoff） | 阶段 4 · 课 12 | 设计决策 1（单 agent vs router 论证）；`escalate_to_human` 转人工 | [lesson-12](../../stages/4-组合与工程化/lessons/lesson-12-Multi-Agent多智能体.md) |
| 三层测试与可观测性 | 阶段 4 · 课 13 | `tests/`（单元 / 集成 / Evals）；审计中间件记录工具轨迹 | [lesson-13](../../stages/4-组合与工程化/lessons/lesson-13-Testing与Observability.md) |

**跨阶段校验**：覆盖 4 个阶段（门槛 ≥3）✅

## 🚀 运行方式

> 前置：Python 3.12+ 与 [uv](https://docs.astral.sh/uv/)；一个对话模型端点（OpenAI 兼容协议）+ 一个嵌入模型端点。

```bash
# 1. 进入实现目录并配置凭据（.env 不入库，模板见 .env.example）
cd 实现
cp .env.example .env    # 或手动创建 .env，填入自己的 Key 与端点

# 2. 安装依赖（uv 自动创建 .venv）
uv sync

# 3. 一键演示（7 个场景：RAG / 订单 / 审批 / 直通 / 脱敏 / 记忆 / 转人工）
uv run python demo.py

# 4. 交互式对话（流式输出；退款审批时进入人工决策）
uv run python -m app.cli

# 5. 测试：快速层默认跑（离线、秒级）；集成层显式跑（真调用）
uv run pytest tests/
uv run pytest tests/ -m integration
```

**预期结果**：
- `demo.py`：7 个场景依次输出（大额退款出现「审批请求 → 批准 → 执行」流程；小额退款无审批直接执行）；结尾打印 11+ 条审计轨迹
- `uv run pytest tests/`：7 passed（约 1 秒）；`-m integration`：2 passed（约 1 分钟，含知识库向量化）

## 📁 目录说明

| 路径 | 内容 |
|------|------|
| [README.md](README.md) | 本文档：需求 / 知识点地图 / 运行方式 |
| [设计决策.md](设计决策.md) | 3 个权衡点：架构选型 / 审批策略 / 记忆策略（五段式完整论证） |
| [反例对照.md](反例对照.md) | 「能跑但很糟」的单文件版本 + 4 条逐条对比 |
| [验收清单.md](验收清单.md) | 自测项：功能 / 非功能 / 理解三层验收，逐项勾选 |
| `实现/` | 可运行工程（`app/` 包 + `tests/` + `demo.py`；代码含中文注释与知识点标注） |
| `实现/data/kb/` | 政策知识库素材（4 份虚构文档：退换货 / 配送 / 会员积分 / 发票支付） |

## 📊 实测环境

- Python 3.12.13 + uv 管理（依赖锁 `uv.lock`）；langchain 1.4.0 / langchain-openai 1.6.2
- 对话模型：OpenAI 兼容端点（本项目实测使用 `qwen3.8-flash`）
- 嵌入模型：SiliconFlow `Qwen/Qwen3-Embedding-8B`（知识库向量化）
- 实测数据：单元 + Evals 7 项 0.73 秒；集成 2 项 70.57 秒；demo 全场景通过（详见 [验收清单.md](验收清单.md) 勾选记录）
