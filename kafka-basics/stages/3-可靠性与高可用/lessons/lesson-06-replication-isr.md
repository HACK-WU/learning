# 第 6 课：副本机制与故障转移

> 所属阶段：阶段 3《可靠性与高可用》｜ 水平：零基础 ｜ 本课知识点：副本与 leader/follower / ISR 机制 / 控制器选举与故障转移
> 故事情节：仓库着火了——主角怎么保证货不丢、换仓库时无缝衔接

## 🎯 本课目标

- 解释副本 replica 与 leader/follower 的读写分工
- 讲清 ISR（In-Sync Replicas）是什么、缩容/扩容的边界与丢消息风险
- 说清控制器 Controller 如何选举、leader 故障后如何转移

---

> 正文（五幕叙事）将在 Phase 2 分批生成。
