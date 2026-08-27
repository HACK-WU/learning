# 课 5：Raft 与 Gossip 一致性成色

> ⏳ 本课为骨架，正文将在 Phase 2 展开填充。

## 本课目标

掌握 Consul 一致性架构的两根支柱：Raft（强一致写路径）与 Gossip（成员管理与故障检测），理解三种读模式的取舍——这是横向对比中"CP 成色"的评判语言。

## 情节定位

引擎第二站：小林直面最硬核的部分。他要知道"脑裂时会怎样""读到的是不是最新数据"这两个分布式系统经典问题在 Consul 里的答案。

## 知识点清单

### 知识点 1：Raft 写路径与 quorum

- 关键点：写路径：leader 统一处理 → quorum 确认 → 提交
- 关键点：leader 选举与故障转移的时间量级
- 关键点：为什么是 3 或 5 节点（奇数与容错公式）

### 知识点 2：Gossip 两层池（LAN / WAN）

- 关键点：LAN gossip（8301）：成员管理、故障检测、事件广播
- 关键点：WAN gossip（8302）：跨 DC 的 server 互联
- 关键点：gossip 检测故障 vs Raft 提交状态的分工（谁说了算）

### 知识点 3：三种读模式（default / consistent / stale）

- 关键点：default：leader 许可的最终一致读
- 关键点：consistent：强制走 Raft quorum 的线性一致读
- 关键点：stale：任意 server 可答的可用性优先读；三模式的延迟/一致性/可用性权衡表
