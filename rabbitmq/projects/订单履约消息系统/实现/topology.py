# -*- coding: utf-8 -*-
"""拓扑声明：交换机、队列、绑定

知识点对照：
- 课 4：交换机类型（topic 按事件路由 / fanout 广播通知 / 死信用 fanout）
- 课 5：队列类型三分与 arguments
- 课 7：死信交换机（DLX）与 delivery-limit
- 课 10：4.3 原生延迟重试参数

设计要点：
  拓扑声明与业务代码分离 —— 改拓扑不用动业务代码，
  且所有队列的 arguments 集中在一处，便于审计（这是"可维护性"约束的一部分）。
"""
import logging

import pika

from config import (
    EX_ORDER, EX_NOTIFY, EX_DLX,
    Q_STOCK, Q_FULFILL_VIP, Q_FULFILL_NORMAL, Q_SMS,
    Q_DLQ, Q_SMS_DLQ,
    RK_ORDER_CREATED, RK_FULFILL_VIP, RK_FULFILL_NORMAL,
    quorum_args, classic_args,
)

logger = logging.getLogger(__name__)


def declare_topology(ch):
    """声明全部交换机、队列与绑定。

    注意：所有声明都是**幂等**的 —— 重复声明参数一致时不会报错，
    参数不一致会报 PRECONDITION_FAILED（课 5：属性不可改）。
    这意味着改拓扑前要先删队列，或写迁移脚本。
    """
    # ---------- 交换机 ----------
    # 课 7：三层持久化的第一层 —— 交换机 durable=True
    ch.exchange_declare(exchange=EX_ORDER, exchange_type='topic', durable=True)
    ch.exchange_declare(exchange=EX_NOTIFY, exchange_type='fanout', durable=True)
    ch.exchange_declare(exchange=EX_DLX, exchange_type='fanout', durable=True)

    # ---------- 死信队列（兜底，课 7）----------
    # 死信队列自身用 quorum：死信是"最后的证据"，不能因为它自己挂了而再丢一次
    ch.queue_declare(queue=Q_DLQ, durable=True,
                     arguments=quorum_args(delivery_limit=None))
    ch.queue_bind(queue=Q_DLQ, exchange=EX_DLX, routing_key='')

    ch.queue_declare(queue=Q_SMS_DLQ, durable=True,
                     arguments=classic_args())
    ch.queue_bind(queue=Q_SMS_DLQ, exchange=EX_DLX, routing_key='')

    # ---------- 业务队列 ----------
    # 库存：quorum + 死信兜底
    # 走同步 RPC（Direct Reply-To），但仍然要持久化与重试能力
    ch.queue_declare(queue=Q_STOCK, durable=True,
                     arguments=quorum_args(dlx=EX_DLX, delivery_limit=3))

    # 决策 5：VIP / Normal 拆两个队列，用消费者数量做加权优先级
    # （quorum 不支持 x-max-priority，这是选 quorum 的连锁代价）
    ch.queue_declare(queue=Q_FULFILL_VIP, durable=True,
                     arguments=quorum_args(dlx=EX_DLX, delivery_limit=3))
    ch.queue_declare(queue=Q_FULFILL_NORMAL, durable=True,
                     arguments=quorum_args(dlx=EX_DLX, delivery_limit=3))

    # 短信用 classic：决策 2 —— 不值得为它付 quorum 的写代价与内存
    ch.queue_declare(queue=Q_SMS, durable=True,
                     arguments=classic_args(dlx=EX_DLX))

    # ---------- 绑定 ----------
    # 课 4：topic 按 routing key 模式匹配
    ch.queue_bind(queue=Q_FULFILL_VIP, exchange=EX_ORDER,
                  routing_key=RK_FULFILL_VIP)
    ch.queue_bind(queue=Q_FULFILL_NORMAL, exchange=EX_ORDER,
                  routing_key=RK_FULFILL_NORMAL)

    # 课 12：发布订阅 —— 短信队列同时订阅订单事件与通知广播
    ch.queue_bind(queue=Q_SMS, exchange=EX_ORDER, routing_key=RK_ORDER_CREATED)
    ch.queue_bind(queue=Q_SMS, exchange=EX_NOTIFY, routing_key='')

    logger.info('拓扑声明完成')


def teardown_topology(ch, confirm=False):
    """删除本项目创建的全部队列与交换机（清场用）。

    ⚠️ 危险操作：会连同消息一起删除。仅用于重跑演示前清场。
    """
    if not confirm:
        raise ValueError('清场需要显式传 confirm=True')

    for q in (Q_STOCK, Q_FULFILL_VIP, Q_FULFILL_NORMAL, Q_SMS,
              Q_DLQ, Q_SMS_DLQ):
        try:
            ch.queue_delete(queue=q)
            logger.info('已删除队列 %s', q)
        except Exception as e:  # noqa: BLE001
            logger.debug('删除队列 %s 失败（可能不存在）：%s', q, e)

    for ex in (EX_ORDER, EX_NOTIFY, EX_DLX):
        try:
            ch.exchange_delete(exchange=ex)
            logger.info('已删除交换机 %s', ex)
        except Exception as e:  # noqa: BLE001
            logger.debug('删除交换机 %s 失败：%s', ex, e)


def describe_topology(ch):
    """打印当前拓扑摘要（用 passive 声明探测，不修改任何东西）。

    课 5：passive=True 声明只探测不创建，是检查拓扑是否存在的标准方式。
    """
    lines = ['=== 当前拓扑 ===']
    for q in (Q_STOCK, Q_FULFILL_VIP, Q_FULFILL_NORMAL, Q_SMS, Q_DLQ, Q_SMS_DLQ):
        try:
            # passive 声明成功即队列存在
            ch.queue_declare(queue=q, durable=True, passive=True)
            lines.append(f'  ✓ {q}')
        except pika.exceptions.ChannelClosedByBroker:
            lines.append(f'  ✗ {q}（不存在）')
            # 信道被关闭，需要重开
            return '\n'.join(lines)
    return '\n'.join(lines)
