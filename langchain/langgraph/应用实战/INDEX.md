# 应用实战总索引

> 一键跳转全部应用实战。过「应用实战判定」的课才配：场景可得 + 有演进空间（基础 → 问题 → 综合两跳）+ 不需大量引入超纲知识。
> 未编写 = 纯文本；已编写 = 可点击链接。

## 阶段 1：从 create_agent 到 StateGraph

| 课 | 场景 | 覆盖知识点 | 链接 |
|----|------|-----------|------|
| 课 3 Graph API 第一个图 | 把"一次通过"的客服流程改成带质检回退的循环 | State 与 reducer / 节点与边 / 条件边与循环 | [03-Graph API 第一个图.md](03-Graph%20API%20%E7%AC%AC%E4%B8%80%E4%B8%AA%E5%9B%BE.md) |
## 阶段 2：执行模型与状态持久化

| 课 | 场景 | 覆盖知识点 | 链接 |
|----|------|-----------|------|
| 课 4 Pregel 执行模型 | 三份文档并行摘要后合并 | 超级步 / Send 扇出 / Command | [04-Pregel 执行模型.md](04-Pregel%20%E6%89%A7%E8%A1%8C%E6%A8%A1%E5%9E%8B.md) |
| 课 5 Checkpointer 短期记忆 | 会话中断后接着上次继续 | checkpoint 与 thread_id / 后端选型 / 断点续跑 | [05-Checkpointer 短期记忆.md](05-Checkpointer%20%E7%9F%AD%E6%9C%9F%E8%AE%B0%E5%BF%86.md) |
| 课 6 Store 长期记忆 | 跨会话记住用户偏好 | Store 与命名空间 / 长期记忆落地 | [06-Store 长期记忆.md](06-Store%20%E9%95%BF%E6%9C%9F%E8%AE%B0%E5%BF%86.md) |
| 课 7 Streaming 流式输出 | 让前端看到"第几步在做什么" | 流模式 / 事件流与子图事件 | [07-Streaming 流式输出.md](07-Streaming%20%E6%B5%81%E5%BC%8F%E8%BE%93%E5%87%BA.md) |
## 阶段 3：可控性与人在环中

| 课 | 场景 | 覆盖知识点 | 链接 |
|----|------|-----------|------|
| 课 8 Interrupts 人在环中 | 高危操作先让人签字 | interrupt 机制 / 审批流落地 | [08-Interrupts 人在环中.md](08-Interrupts%20%E4%BA%BA%E5%9C%A8%E7%8E%AF%E4%B8%AD.md) |
| 课 9 Time-travel 回放与分叉 | 客户投诉后回溯与改判重跑 | 历史回放 / 分叉重跑 | [09-Time-travel 回放与分叉.md](09-Time-travel%20%E5%9B%9E%E6%94%BE%E4%B8%8E%E5%88%86%E5%8F%89.md) |
| 课 10 Fault-tolerance 与 Subgraphs | 外部接口抖了就整单失败，还不能拖垮别的环节 | 节点级超时 / 重试 / 错误处理 / 子图与状态隔离 | [10-Fault-tolerance 与 Subgraphs.md](10-Fault-tolerance%20%E4%B8%8E%20Subgraphs.md) |
| 课 11 Functional API 与选型 | 已有脚本想加暂停和断点续跑，要不要重写成图 | @entrypoint / @task 模型 / 两套 API 选型 | [11-Functional API 与选型.md](11-Functional%20API%20%E4%B8%8E%E9%80%89%E5%9E%8B.md) |

## 阶段 4：工程化与上线

> 本阶段不单配实战——课 12 / 13 的实操由**结课综合实战项目**统一承接（跨阶段整合 + 设计决策 + 反例对照 + 验收清单），见 [../projects/会审批的退款工单系统/README.md](../projects/%E4%BC%9A%E5%AE%A1%E6%89%B9%E7%9A%84%E9%80%80%E6%AC%BE%E5%B7%A5%E5%8D%95%E7%B3%BB%E7%BB%9F/README.md)。
