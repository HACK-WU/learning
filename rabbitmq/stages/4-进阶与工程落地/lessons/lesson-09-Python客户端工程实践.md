# 第 9 课：Python 客户端工程实践

> 所属阶段：阶段 4《进阶与工程落地》｜ 水平：零基础 ｜ 本课知识点：连接与信道管理、生产者模板、消费者模板
> 故事情节：主角要上岗了——从"能跑通的 demo"到"能在线上扛事的代码"，差的是这些工程细节

## 🎯 本课目标

- 说清 Connection 与 Channel 的关系，配置心跳并实现断线重连
- 写出 confirm + mandatory + persistent 三件套齐备的生产者模板
- 写出手动 ack + prefetch + 失败重试 + 优雅关闭的消费者模板

## 知识点清单（含关键点）

1. **连接与信道管理**（关键点：为什么信道是轻量虚拟连接 / 心跳 heartbeat 与 blocked 超时 / 断线重连 / BlockingConnection 与 SelectConnection 的取舍）
2. **生产者模板**（关键点：confirm + mandatory + persistent 三件套 / basic_return 处理不可路由 / 异常与重发策略 / 连接复用）
3. **消费者模板**（关键点：manual ack + prefetch / 处理失败与有限次重试 / 优雅关闭与信号捕获 / 并发消费模型）

## 正文

> ⏳ 待 Phase 2 分批生成。
