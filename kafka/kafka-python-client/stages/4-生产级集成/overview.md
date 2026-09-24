# 阶段 4 · 生产级集成

> 一句话：**代码写对了还不够，它得能被观测、被测试、被部署**。

## 本阶段要解决的冲突

你的客户端逻辑全对，但上线后出问题你不知道——没有指标、没有健康检查、没有测试兜底，只能靠看日志猜。

本阶段解决三件"最后一公里"的事：异步框架怎么集成、客户端怎么被观测、以及怎么测与怎么部署。

## 课程

| 课 | 标题 | 核心问题 | 状态 |
|---|---|---|---|
| 课 11 | asyncio 三方对照 | FastAPI 这类异步服务该用哪个库 | ✅ 已完成 |
| 课 12 | 可观测与测试部署 | 客户端侧怎么暴露指标、怎么测 | ✅ 已完成 |
| 课 13 | 结课综合实战 | 把全线的东西用起来 | ✅ 已完成 |

## 本阶段产出

- 异步集成的选型判据（含 confluent 2.13+ AIOConsumer GA 带来的变化）
- 客户端侧可观测方案（stats 回调、lag 监控、健康检查）
- 一套可运行的测试与部署检查清单

## 一个已被推翻的前提

> **"要 async 就得用 aiokafka"——这个说法在 confluent-kafka 2.13.0 之后不再成立**。

confluent 从 2.13.0 起 asyncio 支持正式 GA（`AIOProducer` / `AIOConsumer`）。这意味着 aiokafka 的独占优势消失了，课 11 值得为此单开一课做三方对照，而不是直接推荐 aiokafka。

### ✅ 课 11 实测裁定（2026-09-23）

该结论**成立但需精确化**，两条修正：

1. **存在性**：`AIOConsumer`/`AIOProducer` 确实存在（本机 confluent-kafka 2.15.1），但**不在顶层命名空间**——须 `from confluent_kafka.aio import AIOConsumer`。顶层 `hasattr(confluent_kafka, 'AIOConsumer')` 返回 `False`，直接探测会误判为"不存在"（与课 3 aiokafka AdminClient 同构，同坑第 2 次）。

2. **性能定位**：它是**同步 Consumer + `ThreadPoolExecutor(max_workers=2)` 包装**（源码 `_call` → `_common.async_call(self.executor, ...)`），不是真 async IO。三方公平对照实测（5 次采样取中位）：

| 方案 | 纯 CPU | 含 0.5ms IO |
|---|---|---|
| `aiokafka` | 0.258s（1.79x） | **0.059s（7.26x）** |
| `AIOConsumer` | 0.435s（1.06x，与线程池打平） | 0.235s（1.83x） |
| 同步 Consumer + 线程池 | 0.462s（1.00x 基线） | 0.430s（1.00x 基线） |

**故推荐结论未变**：IO 密集场景仍选 `aiokafka`；`AIOConsumer` 的正确定位是"**confluent 生态用户的平滑升级路径**"（保住 SR / 事务 / librdkafka 调优参数，同时不冻结事件循环），而非 aiokafka 的替代品。

补充实测：`max_workers` 从 2 调到 16 性能零变化（1.01x），瓶颈是每批次一次线程切换的固定开销，与 worker 数无关。

## 导航

- ⬆️ 返回：[Kafka Python 客户端子教程目录](../../02-课程目录.md)
- ⬅️ 上一阶段：[阶段 3 · 生产层](../3-生产层-吞吐与可靠性/overview.md)
- 📖 进度：[00-学习档案](../../00-学习档案.md)
