# 阶段 3：可控性与人在环中

> 章节定位：「敢让它上生产」——能跑能看还不够：出错怎么办、要不要人批、失败了能不能重跑。

## 阶段目标

1. 用 interrupt 在关键节点卡住执行等人工确认，并能把人工输入接回状态
2. 用 time-travel 回放历史执行、从某一步分叉重跑
3. 给节点配超时 / 重试 / 错误处理，让单个节点失败不炸掉整张图
4. 用子图拆分复杂流程，理解子图的状态隔离与事件冒泡
5. 掌握 Functional API（@entrypoint / @task），能在两套 API 之间选型

## 学习重点

- **interrupt 与 time-travel 都长在 checkpoint 上**：没有 checkpointer，这两个能力都不存在——这是阶段 2 为什么必须先学
- **interrupts 的恢复语义**：`Command(resume=...)` 到底把值送到哪里，是本阶段最容易讲错的点
- **子图不是"函数抽取"**：状态隔离带来复用，也带来"父图看不到子图内部"的调试代价

## 必须掌握的知识点

| 课 | 知识点 | 关键点 |
|----|--------|--------|
| 课 8 Interrupts 人在环中 | interrupt 的中断机制 | interrupt() 如何暂停 / 状态快照 / 与 checkpointer 的依赖 |
| 课 8 | 审批流落地 | 人工输入回写 / Command(resume=) / 多节点中断 |
| 课 9 Time-travel 回放与分叉 | 历史回放 | get_state_history / 逐步回看 / 与 checkpoint 的关系 |
| 课 9 | 分叉重跑 | 从历史某点 fork / update_state / 新 thread 还是复用 |
| 课 10 容错与子图 | 节点级超时 / 重试 / 错误处理 | per-node 配置 / RetryPolicy / 错误处理器 |
| 课 10 | 子图与状态隔离 | 子图编译与挂载 / 状态传递 / 事件冒泡 |
| 课 11 Functional API 与选型 | @entrypoint / @task 模型 | 函数式心智模型 / task 的持久化语义 / 与 Graph API 的对照 |
| 课 11 | 两套 API 选型 | 官方选型页 / 判据 / 混用边界 |
