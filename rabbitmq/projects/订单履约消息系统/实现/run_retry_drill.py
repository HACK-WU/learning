# -*- coding: utf-8 -*-
"""演练：把失败率拉满，逼出重试退避与死信兜底。

run_demo.py 里失败是随机的，可能一条死信都不产生 —— 那就等于没验证兜底。
本脚本**故意让所有消息都失败**，确保观察到：
  1. quorum 队列：reject → 延迟退避（1s/2s/4s）→ 超 delivery-limit → 自动转死信
  2. classic 队列：应用层计数重投 → 超限 → requeue=False 送死信
  3. 死信里能查到 x-death 记录（可观测性）

运行：
    python3 run_retry_drill.py
"""
import json
import logging
import threading
import time

from config import (
    Q_FULFILL_NORMAL, Q_SMS, Q_DLQ, Q_SMS_DLQ,
    PREFETCH_MAIN, PREFETCH_SMS, DELIVERY_LIMIT,
)
from connection import ConnectionManager, setup_logging
from topology import declare_topology, teardown_topology
from idempotency import IdempotencyStore
from services import FulfillConsumer, SmsConsumer

logger = logging.getLogger(__name__)

# 故意 100% 失败
FAIL_RATE = 1.0
DRILL_SECONDS = 30


def run_consumer(consumer, duration):
    def _run():
        try:
            ch = consumer.mgr.get_channel()
            ch.basic_qos(prefetch_count=consumer.prefetch)
            ch.basic_consume(queue=consumer.queue,
                             on_message_callback=consumer._on_message,
                             auto_ack=False)
            end = time.time() + duration
            while time.time() < end and not consumer._stopped:
                consumer.mgr.get_connection().process_data_events(
                    time_limit=0.3)
        except Exception as e:  # noqa: BLE001
            logger.error('消费者异常：%s', e)
    t = threading.Thread(target=_run, daemon=True)
    t.start()
    return t


def peek_dead_letter(mgr, queue, limit=5):
    """查看死信队列内容（不消费掉，取完再放回不合适，这里直接取出展示）。"""
    ch = mgr.get_channel()
    items = []
    for _ in range(limit):
        m, p, b = ch.basic_get(queue=queue, auto_ack=False)
        if not m:
            break
        hdr = p.headers or {}
        xd = hdr.get('x-death')
        reason = xd[0].get('reason') if xd else None
        count = xd[0].get('count') if xd else None
        try:
            order_id = json.loads(b).get('order_id')
        except Exception:  # noqa: BLE001
            order_id = b.decode()[:30]
        items.append({
            'order_id': order_id,
            'reason': reason,
            'death_count': count,
            'app_retry': hdr.get('x-app-retry-count'),
        })
        ch.basic_ack(delivery_tag=m.delivery_tag)
    return items


def main():
    setup_logging()
    print('=' * 74)
    print('重试与死信演练（故意 100% 失败）')
    print('=' * 74)
    print()
    print(f'配置：主链路 quorum delivery-limit={DELIVERY_LIMIT}、'
          f'退避 1s→30s；短信 classic 应用层上限 3 次')
    print()

    mgr = ConnectionManager()
    ch = mgr.get_channel()
    # 先清场，保证死信数据是本次产生的
    teardown_topology(ch, confirm=True)
    ch = mgr.get_channel()
    declare_topology(ch)

    store = IdempotencyStore()

    # 两个消费者：一个 quorum（broker 托管重试）、一个 classic（应用层重试）
    fulfill = FulfillConsumer(ConnectionManager(), store, Q_FULFILL_NORMAL,
                              '演练-发货', fail_rate=FAIL_RATE)
    sms = SmsConsumer(ConnectionManager(), store, fail_rate=FAIL_RATE)

    t1 = run_consumer(fulfill, DRILL_SECONDS)
    t2 = run_consumer(sms, DRILL_SECONDS)
    time.sleep(1.5)

    # 发布失败消息
    pch = mgr.get_channel()
    pch.confirm_delivery()
    print(f'--- 发布 {3} 条注定失败的消息 ---')
    for i in range(1, 4):
        for q, label in ((Q_FULFILL_NORMAL, '发货'), (Q_SMS, '短信')):
            body = json.dumps({'order_id': f'DRILL-{i:03d}',
                               'event_type': 'fulfill',
                               'payload': {'sku': 'SKU-001'}},
                              ensure_ascii=False)
            pch.basic_publish(
                exchange='', routing_key=q, body=body,
                properties=pika.BasicProperties(delivery_mode=2),
            )
        print(f'  已发 DRILL-{i:03d} → 发货队列 + 短信队列')
    print()

    print(f'--- 观察 {DRILL_SECONDS} 秒（含退避等待）---')
    for remaining in range(DRILL_SECONDS, 0, -5):
        print(f'  剩余 {remaining:3d}s ...')
        time.sleep(5)

    print()
    print('=' * 74)
    print('演练结果')
    print('=' * 74)
    print()
    print('| 消费者 | 模式 | 成功 | 失败次数 | 送死信 |')
    print('|--------|------|------|----------|--------|')
    for name, c, mode in (('发货(quorum)', fulfill, 'broker 托管'),
                          ('短信(classic)', sms, '应用层计数')):
        s = c.stats
        print(f'| {name} | {mode} | {s["processed"]} | {s["failed"]} | {s["dead"]} |')

    print()
    print('--- 死信队列内容 ---')
    main_dl = peek_dead_letter(mgr, Q_DLQ)
    sms_dl = peek_dead_letter(mgr, Q_SMS_DLQ)

    if main_dl:
        print(f'  {Q_DLQ}：{len(main_dl)} 条')
        for it in main_dl:
            print(f"    - {it['order_id']}  reason={it['reason']} "
                  f"count={it['death_count']}")
    else:
        print(f'  {Q_DLQ}：空')

    if sms_dl:
        print(f'  {Q_SMS_DLQ}：{len(sms_dl)} 条')
        for it in sms_dl:
            print(f"    - {it['order_id']}  "
                  f"app_retry_count={it['app_retry']}")
    else:
        print(f'  {Q_SMS_DLQ}：空')

    print()
    print('判定：')
    ok1 = len(main_dl) > 0
    ok2 = len(sms_dl) > 0
    print(f'  quorum  broker 托管重试 → 死信：{"✓ 生效" if ok1 else "✗ 未触发"}')
    print(f'  classic 应用层重试     → 死信：{"✓ 生效" if ok2 else "✗ 未触发"}')
    if not (ok1 and ok2):
        print()
        print('  ⚠️ 若未触发，可能原因：退避时间未走完（quorum 退避 1s→2s→4s，')
        print('     三次重试共约 7s + 消费耗时），可增大 DRILL_SECONDS 重跑。')

    mgr.close()


if __name__ == '__main__':
    import pika  # noqa: E402  (延迟导入，避免与上方 import 冲突提示)
    main()
