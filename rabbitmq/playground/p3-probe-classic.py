# -*- coding: utf-8 -*-
"""探测：classic 队列支持哪些重试相关参数。
刚才发现 x-delivery-limit 在 classic 上被拒（406 PRECONDITION_FAILED）。
逐个试，找出 classic 到底能用哪些。
"""
import pika

HOST, PORT = 'localhost', 5681
CRED = pika.PlainCredentials('learn', 'learn123')


def conn():
    return pika.BlockingConnection(pika.ConnectionParameters(
        host=HOST, port=PORT, credentials=CRED, heartbeat=600))


CASES = [
    ('x-delivery-limit', {'x-delivery-limit': 3}),
    ('x-delayed-retry-type only', {'x-delayed-retry-type': 'all'}),
    ('retry全套（无limit）', {
        'x-delayed-retry-type': 'all',
        'x-delayed-retry-min': 1000,
        'x-delayed-retry-max': 4000,
    }),
    ('retry全套 + limit', {
        'x-delivery-limit': 3,
        'x-delayed-retry-type': 'all',
        'x-delayed-retry-min': 1000,
        'x-delayed-retry-max': 4000,
    }),
    ('仅DLX', {'x-dead-letter-exchange': 'p3.probe5.dlx'}),
    ('仅maxlen', {'x-max-length': 1000}),
]


def main():
    c = conn()
    ch = c.channel()
    ch.exchange_declare(exchange='p3.probe5.dlx', exchange_type='fanout',
                        durable=True)

    print('=== classic 队列支持性探测 ===')
    print()
    for label, args in CASES:
        q = f'p3.probe5.{abs(hash(label)) % 10000}'
        try:
            ch.queue_declare(queue=q, durable=True,
                             arguments={'x-queue-type': 'classic', **args})
            print(f'  ✓ {label:26s} → 接受')
            ch.queue_delete(queue=q)
        except Exception as e:  # noqa: BLE001
            msg = str(e).split("PRECONDITION_FAILED - ")[-1] if 'PRECONDITION' in str(e) else str(e)[:90]
            print(f'  ✗ {label:26s} → {msg}')
            try:
                c.close()
            except Exception:
                pass
            c = conn()
            ch = c.channel()

    print()
    print('=== quorum 对照（应全部接受）===')
    for label, args in CASES:
        q = f'p3.probe5.q{abs(hash(label)) % 10000}'
        try:
            ch.queue_declare(queue=q, durable=True,
                             arguments={'x-queue-type': 'quorum', **args})
            print(f'  ✓ {label:26s} → 接受')
            ch.queue_delete(queue=q)
        except Exception as e:  # noqa: BLE001
            msg = str(e).split("PRECONDITION_FAILED - ")[-1] if 'PRECONDITION' in str(e) else str(e)[:90]
            print(f'  ✗ {label:26s} → {msg}')
            try:
                c.close()
            except Exception:
                pass
            c = conn()
            ch = c.channel()

    try:
        c.close()
    except Exception:
        pass


if __name__ == '__main__':
    main()
