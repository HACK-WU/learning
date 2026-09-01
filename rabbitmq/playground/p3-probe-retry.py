"""Phase 3 探测 2：延迟重试的触发条件。
课 10 已知：nack 与 reject 在 4.3 不等价（延迟退避只看 delivery-count）。
本探测回答：x-delayed-retry-type 的取值（rejected / all / failed）与
客户端用 nack 还是 reject，到底哪个组合会触发延迟重试。
判据 = 两次投递之间的实际间隔（延迟期间 basic_get 返回 None）。
"""
import json
import time

import pika

HOST, PORT = 'localhost', 5681
CRED = pika.PlainCredentials('learn', 'learn123')

# 四组对照：(retry_type, 客户端动作)
GROUPS = [
    ('rejected', 'reject', 'rt-rejected + client-reject'),
    ('rejected', 'nack', 'rt-rejected + client-nack'),
    ('all', 'nack', 'rt-all + client-nack'),
    ('all', 'reject', 'rt-all + client-reject'),
]

MIN_MS, MAX_MS = 1000, 4000
ROUNDS = 3


def conn():
    return pika.BlockingConnection(pika.ConnectionParameters(
        host=HOST, port=PORT, credentials=CRED, heartbeat=600))


def run(retry_type, action, label):
    c = conn()
    ch = c.channel()
    ch.confirm_delivery()

    q = f'p3.probe2.{retry_type}.{action}'
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
        'x-delivery-limit': 5,
        'x-delayed-retry-type': retry_type,
        'x-delayed-retry-min': MIN_MS,
        'x-delayed-retry-max': MAX_MS,
    })

    ch.basic_publish('', q, json.dumps({'t': label}),
                     pika.BasicProperties(delivery_mode=2))

    intervals = []
    for i in range(ROUNDS):
        # 轮询等到能取到（延迟期间取不到）
        t0 = time.time()
        m = None
        while time.time() - t0 < 12:
            mm, pp, bb = ch.basic_get(queue=q, auto_ack=False)
            if mm:
                m, p = mm, pp
                break
            time.sleep(0.1)
        if not m:
            intervals.append(None)
            print(f'  [{label}] 第 {i+1} 轮：12s 内未取到（可能已死信）')
            break
        wait = time.time() - t0
        intervals.append(wait)
        hdr = p.headers or {}
        print(f'  [{label}] 第 {i+1} 轮：间隔 {wait:.2f}s, '
              f'redelivered={m.redelivered}, '
              f'delivery-count={hdr.get("x-delivery-count")}, '
              f'acquired-count={hdr.get("x-acquired-count")}')
        if action == 'reject':
            ch.basic_reject(delivery_tag=m.delivery_tag, requeue=False)
        else:
            ch.basic_nack(delivery_tag=m.delivery_tag, requeue=False)

    time.sleep(1.5)
    dm, dp, db = ch.basic_get(queue=dlq, auto_ack=True)
    dead = '是' if dm else '否'
    reached_dlq_early = any(x is None for x in intervals) or len([x for x in intervals if x is not None]) < ROUNDS

    print(f'  [{label}] 结论：间隔序列={[None if x is None else round(x,2) for x in intervals]}, '
          f'最终进死信={dead}')
    print()
    try:
        c.close()
    except Exception:
        pass
    return intervals, dead


def main():
    print('=== 延迟重试触发条件对照（min=1000ms max=4000ms）===')
    print('判定：若第 2 轮起间隔 ≈ 1s/2s/3s 递增 → 延迟重试生效；')
    print('      若第 2 轮立刻取到（≈0.0s）或进死信 → 未生效')
    print()
    results = {}
    for rt, act, label in GROUPS:
        results[label] = run(rt, act, label)

    print('=== 汇总 ===')
    for label, (iv, dead) in results.items():
        seq = [None if x is None else round(x, 2) for x in iv]
        delayed = any(x is not None and x >= 0.8 for x in iv[1:])
        print(f'  {label:32s} 间隔={str(seq):28s} 延迟生效={"是" if delayed else "否":2s} 死信={dead}')


if __name__ == '__main__':
    main()
