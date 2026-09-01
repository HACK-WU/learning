"""Phase 3 探测 3（修正版）：4.3 原生延迟重试的正确姿势 + 死信闭环。
上一版错误：用 requeue=False → 直接死信，压根没走重试。
正确姿势（课 10 已证）：requeue=True 留在队列内触发延迟退避。

本探测要钉死三件事：
  A. requeue=True 时，延迟是否真的按 min * delivery_count 递增
  B. delivery-limit 达到后，是否自动转死信（不是靠客户端 requeue=False）
  C. 转死信时 x-death 里能看到什么
判据 = 实测间隔 + 死信队列实际收到。
"""
import json
import time

import pika

HOST, PORT = 'localhost', 5681
CRED = pika.PlainCredentials('learn', 'learn123')

MIN_MS, MAX_MS = 1000, 4000
DELIVERY_LIMIT = 3


def conn():
    return pika.BlockingConnection(pika.ConnectionParameters(
        host=HOST, port=PORT, credentials=CRED, heartbeat=600,
        blocked_connection_timeout=300))


def main():
    c = conn()
    ch = c.channel()
    ch.confirm_delivery()

    q = 'p3.probe3.work'
    dlx = 'p3.probe3.dlx'
    dlq = 'p3.probe3.work.dlq'

    for name in (q, dlq):
        try:
            ch.queue_delete(queue=name)
        except Exception:
            pass
    try:
        ch.exchange_delete(exchange=dlx)
    except Exception:
        pass

    ch.exchange_declare(exchange=dlx, exchange_type='fanout', durable=True)
    ch.queue_declare(queue=dlq, durable=True,
                     arguments={'x-queue-type': 'quorum'})
    ch.queue_bind(queue=dlq, exchange=dlx, routing_key='')

    ch.queue_declare(queue=q, durable=True, arguments={
        'x-queue-type': 'quorum',
        'x-dead-letter-exchange': dlx,
        'x-delivery-limit': DELIVERY_LIMIT,
        'x-delayed-retry-type': 'all',
        'x-delayed-retry-min': MIN_MS,
        'x-delayed-retry-max': MAX_MS,
    })
    print(f'配置：quorum + DLX + delivery-limit={DELIVERY_LIMIT} '
          f'+ retry all({MIN_MS}~{MAX_MS}ms)')
    print()

    body = json.dumps({'order_id': 'P3-PROBE3-001'})
    ch.basic_publish('', q, body, pika.BasicProperties(delivery_mode=2))
    print('已发布 1 条，开始消费并 requeue=True 打回')
    print()

    rows = []
    for rnd in range(1, DELIVERY_LIMIT + 3):
        t0 = time.time()
        got = None
        while time.time() - t0 < 20:
            m, p, b = ch.basic_get(queue=q, auto_ack=False)
            if m:
                got = (m, p, b)
                break
            time.sleep(0.1)
        if not got:
            rows.append((rnd, None, None, None, '20s 未取到（推测已死信）'))
            break
        m, p, b = got
        wait = time.time() - t0
        hdr = p.headers or {}
        rows.append((rnd, wait, hdr.get('x-delivery-count'),
                     hdr.get('x-acquired-count'), ''))
        # 关键：requeue=True 打回，触发延迟退避
        ch.basic_nack(delivery_tag=m.delivery_tag, requeue=True)

    print('| 轮次 | 实测间隔 | 理论延迟 | delivery-count | acquired-count | 备注 |')
    print('|------|----------|----------|----------------|----------------|------|')
    for rnd, wait, dc, acq, note in rows:
        theory = min(MIN_MS * (rnd - 1), MAX_MS) / 1000
        if wait is None:
            print(f'| {rnd} | - | {theory:.1f}s | {dc} | {acq} | {note} |')
        else:
            print(f'| {rnd} | {wait:.2f}s | {theory:.1f}s | {dc} | {acq} | {note} |')

    time.sleep(2)
    print()
    print('=== 死信队列 ===')
    dm, dp, db = ch.basic_get(queue=dlq, auto_ack=True)
    if dm:
        hdr = dp.headers or {}
        print(f'  收到：{db.decode()}')
        print(f'  x-death：{hdr.get("x-death")}')
        print(f'  x-delivery-count：{hdr.get("x-delivery-count")}')
    else:
        print('  死信队列为空')

    print()
    print('=== 主队列剩余 ===')
    rm, _, _ = ch.basic_get(queue=q, auto_ack=True)
    print(f'  {"有消息" if rm else "空"}')

    try:
        c.close()
    except Exception:
        pass


if __name__ == '__main__':
    main()
