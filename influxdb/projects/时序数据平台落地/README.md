# 实战项目：时序数据平台落地

> 所属课程：InfluxDB 3 系统学习 ｜ 学习目标：**动手实操 + 决策参考** ｜ 预计耗时：4–6 小时
> 对应阶段：topic-teach Phase 3（结课综合实战项目）

## 🎯 一句话需求

> 做一个**时序数据平台落地体检器**：输入一份负载描述（每秒点数、保留天数、tag 基数、约束条件），
> 输出一份**能直接向团队汇报的体检报告** —— 这份负载该选哪个 SKU、哪里会踩坑、成本多少、迁移要注意什么。

**为什么是这个需求**：本课程 19 课讲了 57 个知识点，但它们散在 19 份讲义里。
真实工作中，你面对的不是"第 11 课讲的什么"，而是"我们这个场景能不能上 InfluxDB"。
这个项目把散装知识点焊成一条**可执行的判断链**，也是全课程终点产物
**《时序数据库选型与落地方案》**的工程化版本。

## ✅ 目标与非功能约束

**功能目标**

1. 输入一份负载描述，自动跑完阶段 3–6 的体检并输出分级结论（P0 / P1 / P2 / INFO）
2. 每条结论都能回指到具体课时与官方依据（⭐ 一手 / ⚠️ 假设 / 📌 推导三档标注）
3. 内置三份真实场景（IoT 遥测 / K8s 监控 / 业务指标分析），可直接改成自己的负载

**非功能约束**（4 项）

- **正确性 · 约束归属**：每条规则必须标明它属于哪个 SKU。⭐ 432 文件上限是 **Core 的属性**，
  不能套到 Enterprise / Serverless 上（这是 L19 修过的 P0-1，本项目把它固化进架构）
- **可维护性 · 开闭原则**：新增一条检查规则 = 在某个模块加一个函数，**不改主程序**
- **可审计 · 来源可追溯**：每条结论带 `stage` 字段（形如 `阶段 4 · L11`），能回到讲义核对
- **诚实 · 不编造数字**：官方未公开的（如 Enterprise 授权费）一律标 ❓ 不估算；
  假设值（压缩比、人力成本）统一在 `config.py` 顶部，改一处即可替换

## 🗺️ 覆盖知识点地图

> **这是"跨阶段整合"的证据** —— 每一行都能回到讲义。

| 知识点 | 所属阶段 / 课 | 本项目用在何处 | 回指 |
|--------|--------------|---------------|------|
| 基数与点密度 | 阶段 3 · L7 | `schema_design.py` · `check_cardinality` | [lesson-07](../../stages/3-数据模型与查询/lessons/lesson-07-Schema设计与基数陷阱.md) |
| tag vs field 抉择 | 阶段 3 · L7 | `schema_design.py` · `check_tag_field_choice` | [lesson-07](../../stages/3-数据模型与查询/lessons/lesson-07-Schema设计与基数陷阱.md) |
| Core 硬限制（库 5 / 表 2000 / 列 500） | 阶段 3 · L6 | `schema_design.py` · `check_hard_limits` | [lesson-06](../../stages/3-数据模型与查询/lessons/lesson-06-数据模型-table-tag-field-timestamp.md) |
| 保留键三类后果 | 阶段 3 · L6 | `schema_design.py` · `check_naming` | [lesson-06](../../stages/3-数据模型与查询/lessons/lesson-06-数据模型-table-tag-field-timestamp.md) |
| 432 文件上限与可查窗口 | 阶段 4 · L11 | `engine.py` · `check_query_window` | [lesson-11](../../stages/4-存储引擎与性能/lessons/lesson-11-向量化执行-列存为什么快.md) |
| 批量写入双阈值 | 阶段 4 · L12 | `engine.py` · `check_write_path` | [lesson-12](../../stages/4-存储引擎与性能/lessons/lesson-12-写入与查询性能调优.md) |
| 内存三默认相加 90% | 阶段 5 · L13 | `engine.py` · `check_capacity` | [lesson-13](../../stages/5-生产落地/lessons/lesson-13-部署形态与容量规划.md) |
| 降采样调度周期决定可查性 | 阶段 5 · L14 | `ops.py` · `check_downsample` | [lesson-14](../../stages/5-生产落地/lessons/lesson-14-降采样保留策略与成本.md) |
| 保留期 `0d` 语义反转 / `mo` 非日历（命中检测） | 阶段 5 · L14 / 阶段 6 · L18 | `ops.py` · `check_retention` · `parse_retention` | [lesson-14](../../stages/5-生产落地/lessons/lesson-14-降采样保留策略与成本.md) |
| Telegraf 四条硬约束 | 阶段 5 · L16 | `ops.py` · `check_telegraf` | [lesson-16](../../stages/5-生产落地/lessons/lesson-16-生态集成与自监控.md) |
| Grafana 面板刷新决定账单 | 阶段 5 · L16 / 阶段 6 · L19 | `ops.py` · `check_grafana` | [lesson-16](../../stages/5-生产落地/lessons/lesson-16-生态集成与自监控.md) |
| 层次差（存储引擎 vs 完整方案） | 阶段 6 · L17 | `decision.py` · `check_layering` | [lesson-17](../../stages/6-对比与决策/lessons/lesson-17-横向对比-五款候选.md) |
| 迁移静默项 `reverse` / `drift` | 阶段 6 · L18 | `decision.py` · `check_migration` | [lesson-18](../../stages/6-对比与决策/lessons/lesson-18-迁移指南-从1x2x到3x.md) |
| 约束冲突检测 | 阶段 6 · L19 | `decision.py` · `find_conflicts` | [lesson-19](../../stages/6-对比与决策/lessons/lesson-19-场景演练与选型决策.md) |
| SKU 排雷与约束归属 | 阶段 6 · L19 | `decision.py` · `check_skus` / `surviving_skus` | [lesson-19](../../stages/6-对比与决策/lessons/lesson-19-场景演练与选型决策.md) |
| TCO 与授权费盲区 | 阶段 6 · L19 | `tco.py` | [lesson-19](../../stages/6-对比与决策/lessons/lesson-19-场景演练与选型决策.md) |

**跨阶段校验**：覆盖 **阶段 3 / 4 / 5 / 6 共 4 个阶段**（门槛 ≥3）✅

> 📌 阶段 1（为什么需要 TSDB）与阶段 2（环境搭建）属动机与手感层，不产生可编码的检查规则，
> 故未直接出现在代码里 —— 它们是判断"要不要上时序库"和"怎么跑起来"的前提，见 [验收清单](验收清单.md)。

## 🚀 运行方式

**环境**：Python 3.12.3（WSL2 / Ubuntu）。无需任何第三方依赖，**纯标准库**。

```bash
cd 实现/
python3 main.py            # 跑全部三份预设负载
python3 main.py iot        # 只跑指定场景（iot / k8s / biz）
python3 bad_example.py     # 跑反例，对照看它漏了什么
```

**预期结果**：三个场景全部输出体检报告，末尾给出汇总 `P0=21  P1=21  P2=7  INFO=40`
（数字随代码版本可能微调），并以**退出码**表达结论：

| 场景 | 幸存 SKU | 分级 |
|------|----------|------|
| IoT 设备遥测 | enterprise / serverless / dedicated | P0=5 P1=5 P2=3 |
| K8s 微服务监控 | enterprise / dedicated | P0=8 P1=7 P2=2 |
| 业务指标分析（需 JOIN） | enterprise / serverless / clustered | P0=8 P1=9 P2=2 |

> 💡 **三个场景没有一个跑出 0 个 P0** —— 这是**故意设计的**。
> 三份预设负载各自埋了真实世界里最常见的坑：IoT 埋了从 1.x 迁移过来的 `0d` 保留期（静默删库），
> K8s 埋了 `3mo` 保留期与"想托管 + 要 HA + 只要 2 人运维"的约束冲突，
> 业务指标埋了高基数 `order_id` 做 tag 与 SQL JOIN 短板。
> 跑出 P0 不是 bug，是这个工具在正常工作。

| 退出码 | 含义 |
|--------|------|
| `0` | 无 P0 无 P1 —— 可按当前设计推进 |
| `1` | 有 P0 —— 存在阻断项，不能上生产 |
| `2` | 只有 P1 —— 无阻断，但有需要决策的风险点 |
| `3` | 命令行参数错误 |

> 💡 **退出码是这个项目的点睛之笔**：它让体检器能挂进 CI。
> 每次改负载配置或升级 InfluxDB 版本，跑一次就知道有没有踩回旧的坑。

## 📁 目录说明

| 路径 | 内容 |
|------|------|
| [设计决策.md](设计决策.md) | 3 个权衡点的完整论证（为什么这么分层、为什么用退出码、为什么共享 config） |
| [反例对照.md](反例对照.md) | "能跑但很糟"的单文件版本 + 逐条对比 |
| `实现/config.py` | 单一数据源：全部官方常量 + 三份预设负载 |
| `实现/schema_design.py` | 阶段 3 体检：硬限制 / 基数 / tag-field / 保留键 |
| `实现/engine.py` | 阶段 4 体检：容量 / 可查窗口 / 写入阈值 |
| `实现/ops.py` | 阶段 5 体检：降采样 / 保留期 / Telegraf / Grafana |
| `实现/decision.py` | 阶段 6 体检：层次差 / 冲突检测 / SKU 排雷 / 迁移 |
| `实现/tco.py` | 成本估算（只比成本，不比可行性） |
| `实现/main.py` | 主入口：两阶段流水线 + 分级汇总 + 退出码 |
| `实现/bad_example.py` | 反例：单文件硬编码版（**不要照着写**） |
| [验收清单.md](验收清单.md) | 自测项，逐项勾选 |

## 🎬 项目在故事主线中的位置

全课程的**主角是时间**，冲突是"行式牢笼 vs 时间洪流"，收束是回答
"我们公司该不该用 InfluxDB？用哪个 SKU？怎么落地？成本多少？迁移代价多大？"。

这个项目就是那句收束的**可执行形态** —— 讲义告诉你答案，这个项目让你把它跑出来。
