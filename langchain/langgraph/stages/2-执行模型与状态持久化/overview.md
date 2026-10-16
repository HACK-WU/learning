# 阶段 2：执行模型与状态持久化

> 章节定位：「让它记住和说出来」——图能跑了，但一停就忘、跑起来是黑盒。本阶段搞清它到底怎么执行，再挂上记忆与流式输出。

## 阶段目标

1. 解释一次 `invoke` 底层如何被切成超级步执行，能对着 trace 说出每一步
2. 用 `Send` 做动态扇出、用 `Command` 同时更新状态并跳转
3. 挂 checkpointer 实现断点续跑与多会话隔离，知道 checkpoint 里到底存了什么
4. 用 store 做跨会话长期记忆
5. 区分四种流模式，能按场景选，并订阅子图事件

## 学习重点

- **超级步（superstep）是理解后面一切的钥匙**：interrupt 为什么卡在节点前、time-travel 为什么能回到某一步、streaming 为什么按节点粒度吐——都是同一套执行模型的表现
- **checkpointer 与 store 的分工**：前者管"这次会话跑到哪"，后者管"这个用户是谁"，混用是高频错误
- **流模式不是越多越好**：`values` 全量重发 vs `updates` 增量，选错直接影响前端渲染与带宽

## 必须掌握的知识点

| 课 | 知识点 | 关键点 |
|----|--------|--------|
| 课 4 Pregel 执行模型 | 超级步执行模型 | Pregel 渊源 / 一个 superstep 做什么 / 节点并行与状态合并 / 终止条件（承接课 3 的循环） |
| 课 4 | Send 动态扇出 | 为什么条件边不够用 / Send 的语义 / map-reduce 形态 |
| 课 4 | Command 与状态更新 / 跳转 | 返回值即更新 / Command 的 goto / 与条件边的分工 |
| 课 5 Checkpointer 短期记忆 | checkpoint 与 thread_id | checkpoint 存了什么 / thread_id 即会话 / 配置传入方式 |
| 课 5 | checkpointer 后端选型 | InMemory / SqliteSaver / PostgresSaver / 官方集成页 |
| 课 5 | 断点续跑与状态恢复 | 中断后 resume / 同一 thread 继续 / 状态不预期的排查 |
| 课 6 Store 长期记忆 | Store 与命名空间 | namespace 与 key / 与 checkpointer 的边界 / put / search |
| 课 6 | 长期记忆落地 | 语义记忆 / 情景记忆 / 与课 5 短期记忆的协作 |
| 课 7 Streaming 流式输出 | 流模式 | values / updates / messages / custom 四模式 / 选型对照 |
| 课 7 | 事件流与子图事件 | 事件流 API / 子图事件如何冒泡 / 与流模式的取舍 |
