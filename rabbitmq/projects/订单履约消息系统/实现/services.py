# -*- coding: utf-8 -*-
"""三个业务服务：库存（RPC 服务端）、发货、短信

知识点对照：
- 课 12：RPC 模式（Direct Reply-To 服务端）
- 课 6：手动 ack 与 prefetch
- 课 10：失败重试与死信兜底

设计：这些是"假装的下游系统"，用随机失败模拟真实世界的不确定性，
目的是让重试、幂等、死信这些机制真的被触发，而不是写在文档里供着。
"""
import json
import logging
import random
import time

import pika

from config import (
    Q_STOCK, Q_FULFILL_VIP, Q_FULFILL_NORMAL, Q_SMS,
    PREFETCH_MAIN, PREFETCH_SMS, RETRY_MIN_MS,
)
from consumer import BaseConsumer

logger = logging.getLogger(__name__)


class StockService:
    """库存服务：RPC 服务端（决策 1 + 课 12）。

    为什么扣库存用同步 RPC 而不是异步消息：
    用户点完"提交订单"必须立刻知道成功还是失败。
    做成异步，前端要轮询或上 WebSocket，复杂度反而更高。
    """

    def __init__(self, mgr, fail_rate=0.0):
        self.mgr = mgr
        self.ch = mgr.get_channel()
        self.ch.basic_qos(prefetch_count=PREFETCH_MAIN)
        self.fail_rate = fail_rate
        # 用 dict 模拟库存表
        self.stock = {'SKU-001': 100, 'SKU-002': 5, 'SKU-003': 0}

    def serve(self, duration=15):
        """启动 RPC 服务端，持续 duration 秒。"""
        logger.info('[库存服务] 启动 RPC 服务端（%s），库存：%s',
                    Q_STOCK, self.stock)

        def on_request(ch, method, props, body):
            data = json.loads(body)
            order_id = data['order_id']
            sku, qty = data['sku'], data['qty']

            available = self.stock.get(sku, 0)
            logger.info('[库存服务] 收到扣减请求：%s sku=%s qty=%s（当前库存 %s）',
                        order_id, sku, qty, available)

            if available >= qty:
                self.stock[sku] = available - qty
                result = {'ok': True, 'order_id': order_id,
                          'remain': self.stock[sku]}
            else:
                result = {'ok': False, 'order_id': order_id,
                          'reason': '库存不足', 'available': available}

            # 课 12：RPC 响应 —— 发到 reply_to 指定的队列，带上 correlation_id
            # 这里 reply_to 是伪队列 amq.rabbitmq.reply-to
            ch.basic_publish(
                exchange='',
                routing_key=props.reply_to,
                properties=pika.BasicProperties(
                    correlation_id=props.correlation_id,
                    delivery_mode=2,
                ),
                body=json.dumps(result, ensure_ascii=False),
            )
            ch.basic_ack(delivery_tag=method.delivery_tag)

        self.ch.basic_consume(queue=Q_STOCK, on_message_callback=on_request,
                              auto_ack=False)
        # 用带超时的消费循环，duration 秒后自动退出
        end = time.time() + duration
        while time.time() < end:
            self.mgr.get_connection().process_data_events(time_limit=0.5)
        logger.info('[库存服务] 服务结束')


class FulfillConsumer(BaseConsumer):
    """发货服务：消费 VIP / Normal 两个队列（决策 5）。

    决策 5：quorum 不支持 x-max-priority，所以拆成两个队列，
    用**消费者实例数量**做加权优先级（VIP 启 3 个、Normal 启 1 个）。
    """

    def __init__(self, mgr, store, queue, tier, fail_rate=0.3):
        super().__init__(mgr, queue, f'发货-{tier}', store,
                         prefetch=PREFETCH_MAIN)
        self.tier = tier
        self.fail_rate = fail_rate

    def handle(self, data, props):
        order_id = data.get('order_id')
        # 模拟：30% 概率下游超时（真实世界里仓库系统调用经常超时）
        if random.random() < self.fail_rate:
            logger.warning('[发货] 下游仓库系统超时：%s', order_id)
            return False
        # 模拟处理耗时
        time.sleep(0.05)
        logger.debug('[发货] 已通知仓库发货：%s（%s）', order_id, self.tier)
        return True


class SmsConsumer(BaseConsumer):
    """短信服务：旁路通知（决策 2：用 classic 队列）。

    决策 2 的理由：短信丢了用户顶多收不到通知，
    不值得为它付 quorum 的 3.7 倍写代价与 2.8-3.4 倍内存。
    代价：宿主节点宕机时不可用（课 11 实测 NOT_FOUND）。
    """

    def __init__(self, mgr, store, fail_rate=0.2):
        # ⚠️ broker_managed_retry=False：classic 队列不接受
        # x-delivery-limit / x-delayed-retry-*（本项目实测），
        # 重试计数必须在应用层自己维护。
        super().__init__(mgr, Q_SMS, '短信', store, prefetch=PREFETCH_SMS,
                         broker_managed_retry=False)
        self.fail_rate = fail_rate

    def handle(self, data, props):
        # 短信队列同时收到两种消息：订单事件 + 广播通知
        if 'text' in data:
            logger.info('[短信] 发送广播：%s', data['text'])
        else:
            order_id = data.get('order_id')
            if random.random() < self.fail_rate:
                logger.warning('[短信] 短信网关超时：%s', order_id)
                return False
            logger.debug('[短信] 已发送：%s', order_id)
        return True
