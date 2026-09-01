# -*- coding: utf-8 -*-
"""生产者：confirm + 持久化 + 流控处理

知识点对照：
- 课 6：发布者确认（confirm）—— 不开 confirm 时，broker 收没收到你根本不知道
- 课 7：三层持久化的第三层 —— 消息 delivery_mode=2
- 课 10：流控 —— 内存告警时 broker 会发 BLOCKED，生产者应当感知
- 课 9：pika 的 confirm 是"逐条同步等 RTT"的假异步（BlockingChannel 实现特征）

⚠️ 关于 confirm 的性能（课 6/课 9 实测）：
    100 条持久化消息：不开 confirm 2.3ms，开了 55.5ms，约 24 倍耗时。
    慢的是 **pika 同步适配器的用法**，不是协议本身。
    追求吞吐应换异步客户端或批量确认，本项目为了代码可读性保留同步写法。
"""
import json
import logging
import time
import uuid

import pika
from pika.exceptions import AMQPConnectionError, UnroutableError, NackError

from config import (
    EX_ORDER, EX_NOTIFY, Q_STOCK,
    RK_ORDER_CREATED, RK_FULFILL_VIP, RK_FULFILL_NORMAL,
    RETRY_MIN_MS,
)
from connection import ConnectionManager

logger = logging.getLogger(__name__)


class OrderProducer:
    """订单事件生产者。"""

    def __init__(self, mgr: ConnectionManager):
        self.mgr = mgr
        self.ch = mgr.get_channel()
        # 课 6：开启发布者确认 —— 这是"不丢消息"的发布侧前提
        self.ch.confirm_delivery()
        self._register_flow_control()

    def _register_flow_control(self):
        """注册流控回调（课 10）。

        内存/磁盘告警时 broker 会发 connection.blocked，
        生产者应该感知并降速，而不是继续猛发。
        注意：blocked 回调属于 **Connection** 而非 Channel
        （课 10 实测：BlockingChannel 无 add_on_connection_blocked_callback 属性）。
        """
        conn = self.mgr.get_connection()
        conn.add_on_connection_blocked_callback(
            lambda _conn, _frame: logger.warning('⚠️ 连接被阻塞：broker 资源告警，应降速')
        )
        conn.add_on_connection_unblocked_callback(
            lambda _conn, _frame: logger.info('连接解除阻塞')
        )

    def publish_order_event(self, order_id, event_type, payload,
                            vip=False, headers=None):
        """发布一个订单事件。

        参数：
            order_id：业务单号（幂等键的组成部分）
            event_type：事件类型
            payload：业务数据
            vip：是否 VIP 订单（决策 5：决定进哪个队列）
            headers：自定义头（用于链路追踪）

        返回：True = broker 已确认接收
        """
        routing_key = {
            'created': RK_ORDER_CREATED,
            'fulfill': RK_FULFILL_VIP if vip else RK_FULFILL_NORMAL,
        }.get(event_type, event_type)

        body = json.dumps({
            'order_id': order_id,
            'event_type': event_type,
            'payload': payload,
            'vip': vip,
            'ts': time.time(),
        }, ensure_ascii=False)

        # 课 5：消息属性
        props = pika.BasicProperties(
            # 课 7：delivery_mode=2 = 持久化消息（三层持久化的第三层）
            delivery_mode=2,
            # 内容类型，便于消费者正确解码
            content_type='application/json',
            # 课 8：message_id 用业务单号 + UUID，便于追踪与去重
            message_id=f'{order_id}-{uuid.uuid4().hex[:8]}',
            # 消息过期时间（可选兜底，防止永久积压）
            # ⚠️ 课 7：per-message TTL 是**惰性过期** —— 只有到达队首才被移除，
            # 被前面的长 TTL 消息堵住时完全失效。本项目不设，改由 delivery-limit 控重试。
            headers=headers or {},
        )

        try:
            self.ch.basic_publish(
                exchange=EX_ORDER,
                routing_key=routing_key,
                body=body,
                properties=props,
                # 课 9：mandatory=True 让不可路由的消息退回，而不是静默丢弃
                mandatory=True,
            )
            logger.info('✓ 已发布 %s → %s（broker 已确认）', order_id, routing_key)
            return True
        except UnroutableError:
            # 课 9：confirm + mandatory 是"异常 + 回调"**双路通知**
            logger.error('✗ 消息不可路由：%s → %s', order_id, routing_key)
            return False
        except NackError:
            # 课 6/课 11：quorum 队列失去多数派时会 NACK
            # 关键：失败形态是 NACK **而非异常**，不开 confirm 则完全感知不到
            logger.error('✗ broker 拒绝（NACK）：%s，可能失去多数派', order_id)
            return False
        except AMQPConnectionError as e:
            logger.error('✗ 连接断开：%s', e)
            return False

    def publish_notification(self, text):
        """发广播通知（课 12：发布订阅模式）。

        fanout 交换机忽略 routing key，绑定到它的所有队列都会收到一份完整副本。
        """
        props = pika.BasicProperties(delivery_mode=2,
                                     content_type='application/json')
        self.ch.basic_publish(
            exchange=EX_NOTIFY,
            routing_key='',  # fanout 忽略 routing key（课 4 实测）
            body=json.dumps({'text': text, 'ts': time.time()},
                            ensure_ascii=False),
            properties=props,
        )
        logger.info('✓ 已广播通知：%s', text)


class StockRpcClient:
    """库存服务 RPC 客户端（决策 1 + 课 12）。

    决策 1：扣库存要同步拿结果（用户必须立刻知道成功还是失败）。
    用 Direct Reply-To 避免为每个客户端声明一个专属回调队列。

    ⚠️ 课 12 的硬约束（本项目最容易踩的坑）：
    RPC 客户端必须用**同一个连接和同一个信道**，
    既从 amq.rabbitmq.reply-to 消费、又发布请求消息。
    跨信道时**不报错、但响应静默丢失** —— 比抛异常更危险。
    """

    def __init__(self, mgr: ConnectionManager):
        self.mgr = mgr
        self.conn = mgr.get_connection()
        self.ch = self.conn.channel()
        self.ch.confirm_delivery()
        # 预注册响应消费者（必须在 publish **之前**）
        # 课 12：pika 生成器式 consume() 是**惰性**的，
        # 必须 next() 预热让 basic.consume 帧真正发出
        self.replies = self.ch.consume(
            'amq.rabbitmq.reply-to',
            auto_ack=True,
            exclusive=True,
            inactivity_timeout=10,
        )
        next(self.replies)  # 预热：真正发出 basic.consume

    def call(self, order_id, sku, qty, timeout=10):
        """同步调用库存服务，返回结果 dict。"""
        corr_id = f'{order_id}-{uuid.uuid4().hex[:8]}'
        body = json.dumps({
            'order_id': order_id, 'sku': sku, 'qty': qty,
        }, ensure_ascii=False)

        self.ch.basic_publish(
            exchange='',
            routing_key=Q_STOCK,  # 默认交换机：routing_key 即队列名（课 4）
            body=body,
            properties=pika.BasicProperties(
                delivery_mode=2,
                # Direct Reply-To：reply_to 固定为伪队列名
                reply_to='amq.rabbitmq.reply-to',
                correlation_id=corr_id,
                content_type='application/json',
            ),
        )
        logger.info('→ RPC 请求已发：%s（sku=%s qty=%s）', order_id, sku, qty)

        deadline = time.time() + timeout
        while time.time() < deadline:
            method, props, payload = next(self.replies)
            if payload is None:
                continue  # 超时帧，继续等
            if props.correlation_id != corr_id:
                continue  # 不是本次请求的响应
            result = json.loads(payload)
            logger.info('← RPC 响应：%s', result)
            return result

        raise TimeoutError(f'RPC 超时：{order_id}（{timeout}s 内未收到响应）')
