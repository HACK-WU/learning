"""课 13 结课实战 —— 订单事件处理服务。

把阶段 1-4 的能力串成一个能真跑起来的服务：
  阶段1  AdminClient 幂等建 topic        -> kafka_client.ensure_topics
  阶段2  确认语义/手动提交               -> worker.OrderWorker._commit
  阶段3  吞吐调优/Schema/并发模型        -> config.producer_conf / schema / worker
  阶段4  asyncio 集成 / 可观测 / 测试    -> main.py / metrics / tests
"""

__version__ = "1.0.0"
