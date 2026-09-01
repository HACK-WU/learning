# -*- coding: utf-8 -*-
"""一键跑通主流程：下单 → 扣库存（同步 RPC）→ 发货/短信（异步）

运行：
    python3 run_demo.py

知识点串联（这份脚本本身就是一张"知识点关系图"）：
    课 1  为什么异步（发货/短信不该拖死下单）
    课 12 同步 RPC（库存） vs 异步消息（发货/短信）
    课 5  队列类型（主链路 quorum / 短信 classic）
    课 6  confirm + 手动 ack + prefetch
    课 7  三层持久化
    课 10 延迟重试 + 死信
    课 8  幂等
    课 11 三节点集群（任一节点都可用）
"""
import logging
import sys
import threading
import time

from config import (
    Q_STOCK, Q_FULFILL_VIP, Q_FULFILL_NORMAL, Q_SMS, Q_DLQ,
    PREFETCH_MAIN, PREFETCH_SMS,
)
from connection import ConnectionManager, setup_logging
from topology import declare_topology
from idempotency import IdempotencyStore
from producer import OrderProducer, StockRpcClient
from services import StockService, FulfillConsumer, SmsConsumer

logger = logging.getLogger(__name__)

# 演示参数
ORDERS = [
    ('ORD-1001', 'SKU-001', 2, False),
    ('ORD-1002', 'SKU-002', 1, True),   # VIP
    ('ORD-1003', 'SKU-003', 1, False),  # 库存为 0，会失败
    ('ORD-1004', 'SKU-001', 3, True),   # VIP
    ('ORD-1005', 'SKU-001', 1, False),
]


def run_consumer(consumer, duration):
    """在线程里跑消费者 duration 秒后停止。

    ⚠️ 课 9 实测教训：一条连接/信道**不要跨线程共用**。
    所以每个消费者用**独立的 ConnectionManager**（独立连接）。
    """
    def _run():
        try:
            mgr = consumer.mgr
            ch = mgr.get_channel()
            ch.basic_qos(prefetch_count=consumer.prefetch)
            ch.basic_consume(queue=consumer.queue,
                             on_message_callback=consumer._on_message,
                             auto_ack=False)
            end = time.time() + duration
            while time.time() < end and not consumer._stopped:
                mgr.get_connection().process_data_events(time_limit=0.5)
        except Exception as e:  # noqa: BLE001
            logger.error('消费者线程异常：%s', e)

    t = threading.Thread(target=_run, daemon=True)
    t.start()
    return t


def main():
    setup_logging()
    print('=' * 74)
    print('订单履约消息系统 · 主流程演示')
    print('=' * 74)
    print()

    # ---------- 1. 建拓扑 ----------
    mgr_main = ConnectionManager()
    ch = mgr_main.get_channel()
    declare_topology(ch)
    print()

    store = IdempotencyStore(persist_path='/tmp/p3_idempotency.json')

    # ---------- 2. 启动服务 ----------
    print('--- 启动服务 ---')

    # 库存服务（RPC 服务端）：独立连接 + 独立线程
    stock_mgr = ConnectionManager()
    stock_svc = StockService(stock_mgr)
    stock_thread = threading.Thread(
        target=stock_svc.serve, kwargs={'duration': 25}, daemon=True)
    stock_thread.start()
    time.sleep(1.5)  # 等服务就绪

    # 发货消费者：决策 5 —— VIP 启 2 个、Normal 启 1 个（2:1 加权）
    fulfill_vip_1 = FulfillConsumer(ConnectionManager(), store,
                                    Q_FULFILL_VIP, 'VIP-1', fail_rate=0.3)
    fulfill_vip_2 = FulfillConsumer(ConnectionManager(), store,
                                    Q_FULFILL_VIP, 'VIP-2', fail_rate=0.3)
    fulfill_normal = FulfillConsumer(ConnectionManager(), store,
                                     Q_FULFILL_NORMAL, 'Normal', fail_rate=0.3)
    # 短信消费者
    sms_consumer = SmsConsumer(ConnectionManager(), store, fail_rate=0.2)

    threads = [
        run_consumer(fulfill_vip_1, 25),
        run_consumer(fulfill_vip_2, 25),
        run_consumer(fulfill_normal, 25),
        run_consumer(sms_consumer, 25),
    ]
    time.sleep(1.5)
    print()
    logger.info('发货：VIP × 2 消费者 + Normal × 1 消费者（决策 5 的加权优先级）')
    logger.info('短信：1 个消费者，prefetch=%d', PREFETCH_SMS)
    print()

    # ---------- 3. 下单 ----------
    print('--- 开始下单 ---')
    print()
    rpc = StockRpcClient(mgr_main)
    producer = OrderProducer(mgr_main)

    results = []
    for order_id, sku, qty, vip in ORDERS:
        print(f'{"=" * 60}')
        print(f'订单 {order_id}（sku={sku} qty={qty} {"VIP" if vip else "普通"}）')

        # 第 1 步：同步扣库存（决策 1）
        try:
            r = rpc.call(order_id, sku, qty, timeout=8)
        except TimeoutError as e:
            print(f'  ✗ 库存服务超时：{e}')
            results.append((order_id, '超时'))
            continue

        if not r.get('ok'):
            print(f'  ✗ 下单失败：{r.get("reason")}（可用 {r.get("available")}）')
            print('  → 流程终止，不会发出发货/短信事件')
            results.append((order_id, '库存不足'))
            continue

        # 第 2 步：异步发出发货事件（决策 1）
        print(f'  ✓ 库存扣减成功，剩余 {r.get("remain")}')
        ok = producer.publish_order_event(
            order_id, 'fulfill',
            {'sku': sku, 'qty': qty},
            vip=vip,
            headers={'trace_id': order_id},
        )
        print(f'  → 发货事件已发布（broker 确认={ok}）')

        # 第 3 步：异步发下单事件（触发短信）
        producer.publish_order_event(order_id, 'created', {'sku': sku})
        results.append((order_id, '已受理'))
        time.sleep(0.3)

    # ---------- 4. 等消费完成 ----------
    print()
    print('=' * 60)
    print('等待异步环节处理（含失败重试）...')
    time.sleep(12)

    # ---------- 5. 汇总 ----------
    print()
    print('=' * 74)
    print('结果汇总')
    print('=' * 74)
    print()
    print('| 订单 | 结果 |')
    print('|------|------|')
    for order_id, status in results:
        print(f'| {order_id} | {status} |')

    print()
    print('--- 消费者统计 ---')
    all_stats = [
        ('发货-VIP-1', fulfill_vip_1),
        ('发货-VIP-2', fulfill_vip_2),
        ('发货-Normal', fulfill_normal),
        ('短信', sms_consumer),
    ]
    print('| 服务 | 成功 | 跳过(幂等) | 失败(已重试) |')
    print('|------|------|-----------|-------------|')
    for name, c in all_stats:
        s = c.stats
        print(f'| {name} | {s["processed"]} | {s["skipped"]} | {s["failed"]} |')

    # ---------- 6. 队列状态 ----------
    print()
    print('--- 队列最终状态 ---')
    qch = mgr_main.get_channel()
    for q in (Q_STOCK, Q_FULFILL_VIP, Q_FULFILL_NORMAL, Q_SMS, Q_DLQ):
        try:
            resp = qch.queue_declare(queue=q, durable=True, passive=True)
            print(f'  {q:26s} 剩余 {resp.method.message_count} 条')
        except Exception as e:  # noqa: BLE001
            print(f'  {q:26s} 查询失败：{e}')

    print()
    print('说明：')
    print('  - 失败的消息会按 1s→2s→4s 退避重试（课 10 的 x-delayed-retry-*）')
    print('  - 重试 3 次仍失败 → 超过 delivery-limit → 自动转死信队列 order.dlq')
    print('  - 死信队列里有消息是**正常现象**：它证明失败有兜底、没有静默丢失')

    mgr_main.close()


if __name__ == '__main__':
    main()
