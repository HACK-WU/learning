"""Phase 3 探测：quorum 队列 + DLX + 4.3 原生延迟重试 三者能否共存。
判据是实测，不是文档推断。
"""
import json
import sys
import time

import pika

HOST, PORT = 'localhost', 5681
CRED = pika.PlainCredentials('learn', 'learn123')


def conn():
    return pika.BlockingConnection(pika.ConnectionParameters(
        host=HOST, port=PORT, credentials=CRED, heartbeat=600))


def main():
    c = conn()
    ch = c.channel()
    ch.confirm_delivery()

    ex = 'p3.probe.topic'
    q = 'p3.probe.work'
    dlx = 'p3.probe.dlx'
    dlq = 'p3.probe.work.dlq'

    # 清理历史
    for name in (q, dlq):
        try:
            ch.queue_delete(queue=name)
        except Exception:
            pass
    for name in (ex, dlx):
        try:
            ch.exchange_delete(exchange=name)
        except Exception:
            pass

    ch.exchange_declare(exchange=ex, exchange_type='topic', durable=True)
    ch.exchange_declare(exchange=dlx, exchange_type='topic', durable=True)

    # 死信队列：普通 quorum
    ch.queue_declare(queue=dlq, durable=True, arguments={'x-queue-type': 'quorum'})
    ch.queue_bind(queue=dlq, exchange=dlx, routing_key='#')

    # 主队列：quorum + DLX + delivery-limit + 延迟退避 三者同时挂
    args = {
        'x-queue-type': 'quorum',
        'x-dead-letter-exchange': dlx,
        'x-dead-letter-routing-key': 'to.dlq',
        'x-delivery-limit': 3,
        'x-delayed-retry-type': 'rejected',
        'x-delayed-retry-min': 1000,
        'x-delayed-retry-max': 4000,
    }
    print('=== 探测 1：quorum + DLX + delivery-limit + x-delayed-retry 能否声明 ===')
    try:
        ch.queue_declare(queue=q, durable=True, arguments=args)
        print('  声明成功，参数组合被接受')
    except Exception as e:
        print(f'  声明失败：{type(e).__name__}: {e}')
        sys.exit(1)

    ch.queue_bind(queue=q, exchange=ex, routing_key='order.#')

    # 探测 2：属性是否真的生效（读回 arguments）
    print()
    print('=== 探测 2：声明后读回 effective policy / arguments ===')
    ch2 = conn().channel()
    ch2.queue_declare(queue=q, durable=True, arguments=args)  # 等价声明不应报错
    print('  等价重复声明通过（参数一致）')

    # 探测 3：发一条，观察 rejects 后的去向
    print()
    print('=== 探测 3：连续 reject 3 次后是否进入死信队列 ===')
    body = json.dumps({'order_id': 'P3-PROBE-001'})
    ch.basic_publish(ex, 'order.created', body,
                     pika.BasicProperties(delivery_mode=2,
                                          message_id='P3-PROBE-001'))
    print('  已发布 1 条')

    for i in range(1, 5):
        t0 = time.time()
        method, props, payload = None, None, None
        # 轮询直到取到（延迟退避期间 basic_get 返回 None）
        while time.time() - t0 < 15:
            m, p, b = ch2.basic_get(queue=q, auto_ack=False)
            if m:
                method, props, payload = m, p, b
                break
            time.sleep(0.2)
        if not method:
            print(f'  第 {i} 次：15 秒内未取到（可能已进死信或仍在延迟中）')
            break
        wait = time.time() - t0
        xd = (props.headers or {}).get('x-death')
        print(f'  第 {i} 次取到：等待 {wait:.2f}s, redelivered={method.redelivered}, '
              f'acquired-count={(props.headers or {}).get("x-acquired-count")}, '
              f'delivery-count={(props.headers or {}).get("x-delivery-count")}')
        ch2.basic_nack(delivery_tag=method.delivery_tag, requeue=False)  # reject 语义
        time.sleep(0.5)

    time.sleep(2)
    print()
    print('=== 探测 4：死信队列内容 ===')
    m, p, b = ch2.basic_get(queue=dlq, auto_ack=True)
    if m:
        hdr = p.headers or {}
        xd = hdr.get('x-death')
        print(f'  死信收到：{b.decode()}')
        print(f'  x-death: {xd}')
        print(f'  x-delivery-count: {hdr.get("x-delivery-count")}')
    else:
        print('  死信队列为空（延迟重试未生效或未超 delivery-limit）')

    print()
    print('=== 探测 5：主队列剩余 ===')
    m2, _, _ = ch2.basic_get(queue=q, auto_ack=True)
    print(f'  主队列：{"还有消息" if m2 else "空"}')

    for chx in (ch, ch2):
        try:
            chx.connection.close()
        except Exception:
            pass


if __name__ == '__main__':
    main()
