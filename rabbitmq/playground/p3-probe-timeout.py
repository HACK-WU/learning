# -*- coding: utf-8 -*-
"""探测：quorum 队列的消费者超时（x-consumer-timeout，4.3 新增）。
官方文档称 4.3 把超时处理下移到 quorum 队列内部，classic/stream 不再评估。
本探测验证：消费者取到消息后不 ack、卡住超过超时时间，broker 是否把消息收回。
"""
import json
import time

import pika

HOST, PORT = 'localhost', 5681
CRED = pika.PlainCredentials('learn', 'learn123')
Q = 'p3.probe6.timeout'
TIMEOUT_MS = 3000


def conn():
    return pika.BlockingConnection(pika.ConnectionParameters(
        host=HOST, port=PORT, credentials=CRED, heartbeat=600,
        blocked_connection_timeout=300))


def main():
    c = conn()
    ch = c.channel()
    ch.confirm_delivery()
    try:
        ch.queue_delete(queue=Q)
    except Exception:
        pass

    print('=== 探测：quorum + x-consumer-timeout=3000ms ===')
    try:
        ch.queue_declare(queue=Q, durable=True, arguments={
            'x-queue-type': 'quorum',
            'x-consumer-timeout': TIMEOUT_MS,
        })
        print('  声明成功（参数被接受）')
    except Exception as e:
        print(f'  声明失败：{type(e).__name__}: {e}')
        return

    ch.basic_publish('', Q, json.dumps({'t': 'timeout-test'}),
                     pika.BasicProperties(delivery_mode=2))
    print('  已发布 1 条')
    time.sleep(0.5)

    # 消费者取到消息后故意不 ack，卡住
    got = []
    cancelled = []

    def on_msg(_ch, method, props, body):
        got.append((time.time(), method.delivery_tag))
        print(f'  → 收到消息 tag={method.delivery_tag}，故意不 ack')

    def on_cancel(frame):
        cancelled.append(time.time())
        print(f'  ⚠️ 收到取消通知（消费者超时）：{type(frame).__name__}')

    ch.add_on_cancel_callback(on_cancel)
    ch.basic_consume(queue=Q, on_message_callback=on_msg, auto_ack=False)

    t0 = time.time()
    print(f'  开始等待（超时设 {TIMEOUT_MS}ms，观察 8 秒）')
    end = time.time() + 8
    while time.time() < end:
        c.process_data_events(time_limit=0.3)
        # 定期检查队列深度
    print()

    # 检查消息是否被收回（用另一个连接看 unacked/ready）
    c2 = conn()
    ch2 = c2.channel()
    resp = ch2.queue_declare(queue=Q, durable=True, passive=True)
    print(f'  队列深度：{resp.method.message_count}')

    m, p, b = ch2.basic_get(queue=Q, auto_ack=False)
    if m:
        print(f'  ✓ 消息已可被重新取到（broker 已收回）'
              f'，redelivered={m.redelivered}')
        ch2.basic_ack(delivery_tag=m.delivery_tag)
    else:
        print('  ✗ 消息仍被占用（超时未生效或仍在 unacked）')

    print()
    print('结论：')
    print(f'  收到消息次数：{len(got)}')
    print(f'  收到 cancel 次数：{len(cancelled)}')
    if got and cancelled:
        delay = cancelled[0] - got[0][0]
        print(f'  超时触发延迟：约 {delay:.2f}s（设 {TIMEOUT_MS/1000}s）')
        print('  → 消费者超时生效：卡住的消费者会被取消，消息回到队列')
    elif got and not cancelled:
        print('  → 消息收到但未触发取消（可能 pika 未声明 consumer_cancel_notify 能力）')

    for cx in (c, c2):
        try:
            cx.close()
        except Exception:
            pass


if __name__ == '__main__':
    main()
