# -*- coding: utf-8 -*-
"""演练 B（干净隔离）：只验证 quorum 队列的 broker 托管重试 → 死信链路。

上一版 run_retry_drill.py 的死信里混入了 reason=rejected 的消息，
来源不明（疑似上一轮 run_demo.py 超时残留），无法确认是本次产生的。

本演练用**专属队列名**（drillb.*）与独立 DLX 完全隔离，
并在演练前删除之，确保死信里的每一条都能追溯到本次发布。

只跑 quorum 一条路径，观察：
    第 1 次投递 → reject → 退避 1s → 第 2 次 → 2s → 第 3 次 → 4s
    → 第 4 次失败时 delivery-count 达到 limit → broker 自动转死信
"""
import json
import logging
import threading
import time

import pika

from config import RETRY_MIN_MS, RETRY_MAX_MS
from connection import ConnectionManager, setup_logging

logger = logging.getLogger(__name__)

Q = 'drillb.work'
DLX = 'drillb.dlx'
DLQ = 'drillb.dlq'
DELIVERY_LIMIT = 3
RETRY_MIN, RETRY_MAX = 1000, 4000   # 用较短退避，30 秒内跑完
N_MSGS = 2
WATCH_SECONDS = 26


class AlwaysFailConsumer:
    """永远失败的消费者，记录每次投递的时间点与 delivery-count。"""

    def __init__(self, mgr, queue, step_name):
        self.mgr = mgr
        self.queue = queue
        self.step_name = step_name
        self.prefetch = 1
        self._stopped = False
        self.events = []      # (轮次, 相对时刻, delivery_count)
        self.t0 = None

    def _on_message(self, ch, method, props, body):
        if self.t0 is None:
            self.t0 = time.time()
        hdr = props.headers or {}
        dc = hdr.get('x-delivery-count')
        order_id = json.loads(body).get('order_id')
        elapsed = time.time() - self.t0
        self.events.append((order_id, round(elapsed, 2), dc))
        logger.info('[%s] 投递 %s：t=+%.2fs delivery-count=%s → reject',
                    self.step_name, order_id, elapsed, dc)
        # ⚠️ 决策 3：用 reject 推进 delivery-count
        ch.basic_reject(delivery_tag=method.delivery_tag, requeue=True)


def main():
    setup_logging()
    print('=' * 74)
    print('演练 B：quorum broker 托管重试 → 死信（干净隔离）')
    print('=' * 74)
    print()
    print(f'专属队列：{Q} / {DLQ}（演练前删除，确保死信可追溯）')
    print(f'配置：delivery-limit={DELIVERY_LIMIT}，退避 {RETRY_MIN}~{RETRY_MAX}ms')
    print()

    mgr = ConnectionManager()
    ch = mgr.get_channel()

    # ---- 彻底清场 ----
    for name in (Q, DLQ):
        try:
            ch.queue_delete(queue=name)
        except Exception:
            pass
    try:
        ch.exchange_delete(exchange=DLX)
    except Exception:
        pass
    ch = mgr.get_channel()

    # ---- 声明隔离拓扑 ----
    ch.exchange_declare(exchange=DLX, exchange_type='fanout', durable=True)
    ch.queue_declare(queue=DLQ, durable=True,
                     arguments={'x-queue-type': 'quorum'})
    ch.queue_bind(queue=DLQ, exchange=DLX, routing_key='')
    ch.queue_declare(queue=Q, durable=True, arguments={
        'x-queue-type': 'quorum',
        'x-dead-letter-exchange': DLX,
        'x-delivery-limit': DELIVERY_LIMIT,
        'x-delayed-retry-type': 'all',
        'x-delayed-retry-min': RETRY_MIN,
        'x-delayed-retry-max': RETRY_MAX,
    })
    print('拓扑已声明（队列为空）')
    print()

    # ---- 启动消费者 ----
    consumer = AlwaysFailConsumer(ConnectionManager(), Q, '演练B')
    cch = consumer.mgr.get_channel()
    cch.basic_qos(prefetch_count=1)
    cch.basic_consume(queue=Q, on_message_callback=consumer._on_message,
                      auto_ack=False)

    def _run():
        end = time.time() + WATCH_SECONDS
        while time.time() < end and not consumer._stopped:
            consumer.mgr.get_connection().process_data_events(time_limit=0.3)

    threading.Thread(target=_run, daemon=True).start()
    time.sleep(1)

    # ---- 发布 ----
    ch.confirm_delivery()
    print(f'--- 发布 {N_MSGS} 条必定失败的消息 ---')
    for i in range(1, N_MSGS + 1):
        ch.basic_publish(
            exchange='', routing_key=Q,
            body=json.dumps({'order_id': f'DRILLB-{i:02d}'}, ensure_ascii=False),
            properties=pika.BasicProperties(delivery_mode=2),
        )
        print(f'  已发 DRILLB-{i:02d}')
    print()
    print(f'--- 观察 {WATCH_SECONDS} 秒 ---')

    for remaining in range(WATCH_SECONDS, 0, -6):
        print(f'  剩余 {remaining:3d}s ...')
        time.sleep(6)

    # ---- 结果 ----
    print()
    print('=' * 74)
    print('投递时序（同一条消息的多次投递）')
    print('=' * 74)
    print()
    print('| 消息 | 相对时刻 | delivery-count | 本轮间隔 |')
    print('|------|----------|----------------|----------|')
    last_by_msg = {}
    for order_id, elapsed, dc in consumer.events:
        prev = last_by_msg.get(order_id)
        gap = f'{elapsed - prev:.2f}s' if prev is not None else '-'
        last_by_msg[order_id] = elapsed
        print(f'| {order_id} | +{elapsed:5.2f}s | {dc} | {gap} |')

    print()
    print('--- 死信队列 ---')
    dch = mgr.get_channel()
    items = []
    while True:
        m, p, b = dch.basic_get(queue=DLQ, auto_ack=False)
        if not m:
            break
        hdr = p.headers or {}
        xd = hdr.get('x-death') or []
        items.append({
            'order_id': json.loads(b).get('order_id'),
            'reason': xd[0].get('reason') if xd else None,
            'queue': xd[0].get('queue') if xd else None,
        })
        dch.basic_ack(delivery_tag=m.delivery_tag)

    if items:
        for it in items:
            print(f"  {it['order_id']}  reason={it['reason']}  from={it['queue']}")
    else:
        print('  空')

    print()
    print('--- 主队列剩余 ---')
    rm, _, _ = dch.basic_get(queue=Q, auto_ack=True)
    print(f'  {"仍有消息" if rm else "空"}')

    print()
    print('判定：')
    total_deaths = len(items)
    limit_deaths = [i for i in items if i['reason'] == 'delivery_limit']
    print(f'  投递总次数：{len(consumer.events)}')
    print(f'  死信条数：{total_deaths}（期望 {N_MSGS}）')
    print(f'  其中 reason=delivery_limit：{len(limit_deaths)}（期望 {N_MSGS}）')
    ok = len(limit_deaths) == N_MSGS
    print(f'  结论：broker 托管重试 → 超限死信 {"✓ 完全符合预期" if ok else "✗ 与预期不符"}')

    mgr.close()
    consumer.mgr.close()


if __name__ == '__main__':
    main()
