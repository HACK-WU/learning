"""Phase 3 探测 4：nack vs reject 谁会推进 delivery-count 并触发 delivery-limit 死信。
课 10 已证：延迟公式只看 delivery-count；nack=取过没失败，reject=真的失败。
本探测在【quorum + DLX + delivery-limit】组合下验证：
  A. reject(requeue=True) → delivery-count 递增 → 延迟按 min*count → 超限转死信
  B. nack(requeue=True)   → delivery-count 不涨 → 延迟恒为 min → 永不超限（死循环风险）
这是实战项目里"重试语义"选型的直接依据。
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


def run(mode, tag):
    c = conn()
    ch = c.channel()
    ch.confirm_delivery()

    q = f'p3.probe4.{tag}'
    dlx = f'{q}.dlx'
    dlq = f'{q}.dlq'

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

    ch.basic_publish('', q, json.dumps({'order_id': f'P3-{tag}'}),
                     pika.BasicProperties(delivery_mode=2))

    print(f'\n### 模式：{mode}(requeue=True)  delivery-limit={DELIVERY_LIMIT}')
    rows = []
    for rnd in range(1, 7):
        t0 = time.time()
        got = None
        while time.time() - t0 < 15:
            m, p, b = ch.basic_get(queue=q, auto_ack=False)
            if m:
                got = (m, p, b)
                break
            time.sleep(0.1)
        if not got:
            rows.append((rnd, None, None, None, '15s 未取到'))
            break
        m, p, b = got
        wait = time.time() - t0
        hdr = p.headers or {}
        rows.append((rnd, wait, hdr.get('x-delivery-count'),
                     hdr.get('x-acquired-count'), ''))
        if mode == 'reject':
            ch.basic_reject(delivery_tag=m.delivery_tag, requeue=True)
        else:
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
    dm, dp, db = ch.basic_get(queue=dlq, auto_ack=True)
    print(f'死信队列：{"收到 " + db.decode() if dm else "空"}')
    if dm:
        hdr = dp.headers or {}
        print(f'  x-death：{hdr.get("x-death")}')
    rm, _, _ = ch.basic_get(queue=q, auto_ack=True)
    print(f'主队列：{"仍有消息" if rm else "空"}')

    try:
        c.close()
    except Exception:
        pass
    return bool(dm)


def main():
    print('=' * 70)
    print('探测：谁会推进 delivery-count（延迟退避与 delivery-limit 的共同依据）')
    print('=' * 70)
    r1 = run('reject', 'reject')
    r2 = run('nack', 'nack')
    print()
    print('=' * 70)
    print('判定')
    print('=' * 70)
    print(f'  reject → 死信触发：{"是" if r1 else "否"}')
    print(f'  nack   → 死信触发：{"是" if r2 else "否"}')
    print()
    print('推论（供实战项目选型）：')
    print('  业务判定"这条真失败、要重试" → 用 reject，计数才涨、才会最终进死信')
    print('  用 nack 则延迟恒定、永不超限 → 无限重试死循环')


if __name__ == '__main__':
    main()
