# Phase 3 综合实战项目评审：HTTP 请求诊断实验场

> 日期：2026-09-17  ｜评审方式：主 agent 内联（pedagogy + learner，独立性受限；`course-reviewer` 子 agent 尚未创建）

## 评审范围与证据

| 类别 | 文件 / 证据 |
|---|---|
| 需求与地图 | `projects/HTTP请求诊断实验场/README.md`、`证据卡示例.md` |
| 权衡与边界 | `projects/HTTP请求诊断实验场/设计决策.md` |
| 正反例 | `projects/HTTP请求诊断实验场/反例对照.md`、`实现/bad_server.py` |
| 可运行实现 | `实现/server.py`、`实现/client.py`、`实现/run_cases.py` |
| 自动化验证 | `实现/test_project.py`；系统 Python 3.9.6 编译通过；uv 运行病例与测试通过 |
| 视觉引导 | `assets/project-evidence-flow.svg`，XML 校验通过 |

## Phase 3 四项复杂度门槛

| 门槛 | 判定 | 证据 |
|---|---|---|
| 跨阶段整合 ≥3 阶段 | ✅ 通过，覆盖 5 个阶段 | README 知识点地图；病例同时使用报文/状态码、连接/安全、缓存/性能、协议、认证/CORS |
| 非功能约束 ≥2 项 | ✅ 通过，落实 4 项 | 安全、性能可观测性、错误语义、可维护性；README“工程约束” |
| 真权衡决策 ≥2 个 | ✅ 通过，落实 4 项 | 标准库 vs ASGI/网关、Bearer vs Cookie/Session、分层缓存 vs 全部 no-store、先保留 h1.1 vs 立即升级 |
| 多文件工程 | ✅ 通过 | 4 个实现模块 + 1 个反例 + 测试 + SVG + 4 个说明文档 |

## Pedagogy 评审

| 维度 | 结论 |
|---|---|
| 目标对齐 | 通过：同时覆盖理解、动手、决策三轨，不把项目扩张成业务系统开发 |
| 认知阶梯 | 通过：先看症状，再采集报文/时间证据，再写假设，最后做修复或暂不升级决策 |
| 跨课承接 | 通过：README 对每个实际覆盖知识点回指具体课时，且把代码证据与设计证据分开 |
| 反例教学 | 通过：`bad_server.py` 真能启动，但状态码、CORS、缓存、时间和并发模型均有可解释缺陷 |
| 实操闭环 | 通过：病例脚本、curl 命令、浏览器 DevTools 操作、回归测试和验收清单相互对应 |
| 边界诚实 | 通过：明确本地 HTTP/1.1，不把 HTTP/2/3、TLS 终止或 mitmproxy 说成已实测 |

## Learner 评审

| 检查项 | 结论 |
|---|---|
| L1 能否不依赖复杂环境启动 | 通过：Python 标准库即可，绑定 localhost |
| L2 能否看懂每个文件的职责 | 通过：README 文件说明 + 模块分工清晰 |
| L3 能否从输出回到原理 | 通过：每个输出都带状态码、头部或时间段，并在 README/设计决策中解释 |
| L4 能否区分 401、403、CORS 和网络失败 | 通过：病例分别给出 401/403/201、预检 204/403 和证据字段 |
| L5 能否练习真实取舍 | 通过：设计决策采用候选方案→选择→理由→代价→改选条件五段式 |
| L6 能否验证修复没有破坏其他行为 | 通过：3 个 unittest 覆盖重定向/慢响应、认证、CORS/缓存 |
| L7 是否有安全护栏 | 通过：不访问外部网络，不安装 CA，不写真实凭证，不默认打印认证正文 |
| L8 是否知道项目的能力边界 | 通过：README 和设计决策均说明不等于生产服务、压测和 HTTP/2/3 实验 |

## 可运行性与正确性核验

已执行：

```text
python3 -m py_compile 实现/*.py                         PASS（系统 Python 3.9.6）
uv run --no-project python 实现/run_cases.py             PASS
uv run --no-project python -m unittest discover ...      PASS（3 tests）
xmllint --noout assets/project-evidence-flow.svg         PASS
```

病例真实输出确认：

- 慢请求：302 → `/api/orders`、`/api/slow` 的 TTFB 约 82ms、正文读取约 45ms（具体数值随运行变化）。
- 认证：缺凭证 401 + `WWW-Authenticate`，错误凭证 403，字面量占位符 200。
- CORS：允许预检 204、带认证头的实际 POST 201、恶意来源预检 403。
- 缓存：首次 200 + ETag，条件请求 304 且正文为 0 字节，版本化静态资源带 immutable。
- 协议：明确记录为本地 HTTP/1.1 基线，未伪造 h2/h3 实测结果。

## 问题清单

- P0：0
- P1：0
- P2：0

结论：**通过**。项目满足 Phase 3 四项复杂度门槛，适合进入学习者逐项执行验收；不需要为“看起来更像生产”而增加数据库、前端框架、Docker 或未授权的代理/证书安装。
