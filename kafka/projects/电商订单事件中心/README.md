# 综合实战项目：电商订单事件中心（Order Event Hub）

> 所属课程：[Kafka 系统学习](../00-学习档案.md)｜ 项目类型：技术域 · 多文件工程 ｜ 难度：结课级
> 事实核查：kafka-python 3.x 事务 API、DLQ 实践、share groups 状态均已联网核实（核查于 2026-08）

## 一句话需求

做一个**可运行**的订单事件中心：订单服务把 `OrderCreated` / `OrderPaid` / `OrderCancelled` 三类事件发进 Kafka，下游的**积分服务**、**风控服务**、**审计服务**各自独立消费同一份数据，且必须做到**不丢消息、不重复记账、坏消息不阻塞主链路**。

## 目标（完成即达成）

1. 一份事件流被 3 个下游服务独立消费（互不影响、各自有独立进度）
2. 积分服务**不重复加分**（幂等），坏消息进 DLQ 不阻塞主链路
3. 风控服务用**事务**保证「读-处理-写」原子性
4. 全链路可观测：能用一个命令看清各服务的消费进度与积压

---

## 覆盖知识点地图（跨阶段整合的证据）

| 知识点 | 所属阶段 / 课 | 本项目落点 |
|--------|---------------|-----------|
| 削峰·异步·解耦三大价值 | 阶段 1 / 课 1 | 订单服务不再同步调用积分/风控，改为发事件 |
| Kafka vs 其他 MQ 对比 | 阶段 1 / 课 2 | 为什么选 Kafka：一份数据 3 个下游 + 可回放 |
| 创建 Topic + CLI 观察 | 阶段 2 / 课 3 | 初始化 4 个 topic（含 DLQ、重试） |
| Topic 与 Partition | 阶段 2 / 课 4 | 分区数 = 并行度上限，决定消费者扩容天花板 |
| 分区策略（key 保序） | 阶段 2 / 课 5 | 用 `user_id` 作 key，保证同一用户订单有序 |
| acks 与发送可靠性 | 阶段 2 / 课 5 | `acks='all'` + 幂等，不丢消息 |
| 消费者组与再均衡 | 阶段 2 / 课 6 | 3 个服务 = 3 个 group，组间广播、组内分摊 |
| 位移提交与重复/丢失 | 阶段 2 / 课 6 | 手动提交 + 处理完再提交，避免丢失 |
| ISR 机制 | 阶段 3 / 课 7 | `acks='all'` 等待 ISR 全体确认的真正含义 |
| 三种交付语义 | 阶段 3 / 课 8 | 明确本项目取「至少一次 + 消费端幂等」 |
| 幂等 producer | 阶段 3 / 课 8 | 生产者开启幂等，消除内部重试导致的重复 |
| 事务简介 | 阶段 3 / 课 8 | 风控服务用事务实现「消费-处理-生产」原子 |
| 写生产者 / 写消费者 | 阶段 4 / 课 9 | 全部代码基于课 9 的生产者/消费者骨架 |
| 事件驱动架构 EDA | 阶段 4 / 课 10 | 事件命名用过去式事实，不用命令式 |
| 常见拓扑 | 阶段 4 / 课 10 | 本项目 = 事件主干 + 多个下游（日志管道雏形）|
| 决策清单（Topic 设计三原则） | 阶段 4 / 课 10 | 按业务事件建 topic，不按消费方建 |

> **跨阶段统计**：阶段 1（3 点）/ 阶段 2（5 点）/ 阶段 3（3 点）/ 阶段 4（5 点）——**4 个阶段全覆盖**，满足跨阶段整合门槛。

## 运行方式

> Windows 避坑同课 9：用 `python3.11.exe` 运行、PowerShell 用 `;` 分隔命令。

```powershell
docker ps
```

```powershell
python3.11.exe 实现\init_topics.py
```

```powershell
python3.11.exe 实现\order_producer.py
```

再开**三个**终端分别跑下游：

```powershell
python3.11.exe 实现\points_consumer.py
python3.11.exe 实现\risk_consumer.py
python3.11.exe 实现\audit_consumer.py
```

看全局进度：

```powershell
docker exec kafka /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group points-service
```

## 目录说明

```
实现/
├── init_topics.py       # 一次性初始化 topic（orders / orders.DLQ / orders.retry）
├── order_producer.py    # 订单服务：发三种事件，含故意制造的坏消息
├── points_consumer.py   # 积分服务：幂等记账 + 坏消息进 DLQ
├── risk_consumer.py     # 风控服务：事务消费-处理-生产
├── audit_consumer.py    # 审计服务：全量留痕（事件溯源雏形）
└── common.py            # 公共配置（topic 名、序列化、日志）
```

---

## 快速上手路径

1. 先读 [设计决策.md](设计决策.md)——理解为什么这么选（尤其"为什么不用事务做全部服务"）
2. 再读 [反例对照.md](反例对照.md)——看"能跑但很糟"的版本长什么样
3. 跑起来后逐项勾选 [验收清单.md](验收清单.md)
