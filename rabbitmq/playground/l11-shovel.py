#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 11 实验 4（修订版）：Shovel 消息搬运
=========================================
修订说明（如实记录）：
  初版想用既有容器 rabbitmq-learn 当"上游站点"，但它在【不同的 docker 网络】，
  集群容器无法访问。随后尝试新建独立上游容器，却遇到宿主文件权限问题：
      "Error when reading /var/lib/rabbitmq/.erlang.cookie: eacces"
  两次尝试均未成功，故改为【在集群内部】演示 Shovel（rmq1 → rmq2）。

  这不削弱教学效果：Shovel 的核心机制是"一个 broker 持续把消息搬给另一个
  broker"，本实验完整展示了该机制；跨站点只是它的应用场景之一，
  原理部分仍按官方定义讲解。

本实验实测：
  1. 在 rmq1 上建源队列并发布消息
  2. 配置 Shovel：从 rmq1 的源队列搬到 rmq2 的目标队列
  3. 验证消息被搬运过去，且源队列被消费（Shovel 默认是 move 语义）
  4. 展示 Shovel 状态
  5. 清理

⚠️ 只操作集群内资源，不触碰 rabbitmq-learn
"""
import json
import subprocess
import sys
import time

import pika

NODES = {'rmq1': (5681, 15681), 'rmq2': (5682, 15682), 'rmq3': (5683, 15683)}
CRED = pika.PlainCredentials('learn', 'learn123')
SRC_Q = 'l11.shovel.src'
DST_Q = 'l11.shovel.dst'


def ctl(node, *args, timeout=60):
    r = subprocess.run(['docker', 'exec', node, 'rabbitmqctl'] + list(args),
                       capture_output=True, text=True, timeout=timeout)
    return (r.stdout or '') + (r.stderr or '')


def conn_of(port, timeout=30):
    return pika.BlockingConnection(pika.ConnectionParameters(
        host='localhost', port=port, credentials=CRED, heartbeat=600,
        blocked_connection_timeout=timeout,
        connection_attempts=3, retry_delay=2, socket_timeout=30))


def api(node, path):
    _, ui = NODES[node]
    r = subprocess.run(
        ['curl', '-s', '-u', 'learn:learn123',
         'http://localhost:%d/api/%s' % (ui, path)],
        capture_output=True, text=True, timeout=20)
    try:
        return json.loads(r.stdout)
    except Exception:
        return None


def depth(node, q):
    d = api(node, 'queues/%%2F/%s' % q)
    return (d or {}).get('messages')


def main():
    print("=" * 74)
    print("课 11 实验 4（修订版）：Shovel 消息搬运")
    print("=" * 74)
    print("源：rmq1 的 %s" % SRC_Q)
    print("目标：rmq2 的 %s" % DST_Q)

    # 1. 准备
    print("\n[1] 准备两端队列")
    c1 = conn_of(NODES['rmq1'][0])
    ch1 = c1.channel()
    for q in (SRC_Q,):
        try:
            ch1.queue_delete(queue=q)
        except Exception:
            pass
    ch1.queue_declare(queue=SRC_Q, durable=True)
    c1.close()

    c2 = conn_of(NODES['rmq2'][0])
    ch2 = c2.channel()
    try:
        ch2.queue_delete(queue=DST_Q)
    except Exception:
        pass
    ch2.queue_declare(queue=DST_Q, durable=True)
    c2.close()
    print("    已就绪")

    # 2. 发布
    N = 5
    print("\n[2] 向源队列（rmq1）发布 %d 条消息" % N)
    c1 = conn_of(NODES['rmq1'][0])
    ch1 = c1.channel()
    ch1.confirm_delivery()
    for i in range(N):
        ch1.basic_publish(exchange='', routing_key=SRC_Q,
                          body=b'payload-%03d' % i,
                          properties=pika.BasicProperties(delivery_mode=2))
    c1.close()
    time.sleep(1)
    print("    源队列深度 = %s" % depth('rmq1', SRC_Q))
    print("    目标队列深度 = %s" % depth('rmq2', DST_Q))

    # 3. 配置 Shovel
    print("\n[3] 配置 Shovel（rmq1 源 → rmq2 目标）")
    params = {
        "src-uri": "amqp://learn:learn123@rmq1:5672",
        "src-queue": SRC_Q,
        "dest-uri": "amqp://learn:learn123@rmq2:5672",
        "dest-queue": DST_Q,
    }
    out = ctl('rmq1', 'set_parameter', 'shovel', 'l11-demo', json.dumps(params))
    print("    %s" % out.strip()[:100])

    # 4. 等待搬运
    print("\n[4] 等待搬运完成（最多 40 秒）")
    moved = 0
    t0 = time.time()
    while time.time() - t0 < 40:
        d_src = depth('rmq1', SRC_Q) or 0
        d_dst = depth('rmq2', DST_Q) or 0
        if d_dst >= N:
            moved = d_dst
            break
        time.sleep(1)
    d_src = depth('rmq1', SRC_Q) or 0
    d_dst = depth('rmq2', DST_Q) or 0

    print("")
    print("    | 队列 | 所在节点 | 深度 |")
    print("    |------|----------|------|")
    print("    | %s | rmq1 | %s |" % (SRC_Q, d_src))
    print("    | %s | rmq2 | %s |" % (DST_Q, d_dst))
    print("")
    if d_dst >= N:
        print("    ✅ %d 条消息已搬运到目标队列" % d_dst)
        print("    源队列剩余 %s 条 → Shovel 默认消费并【转发】，源端不再保留" % d_src)
    else:
        print("    ⚠️ 目标队列只有 %d 条" % d_dst)

    # 5. 状态
    print("\n[5] Shovel 状态")
    out = ctl('rmq1', 'shovel_status')
    for ln in out.splitlines()[:8]:
        if ln.strip():
            print("    %s" % ln.strip()[:110])

    # 6. 取回消息验证内容
    print("\n[6] 从目标队列取回消息验证内容")
    c2 = conn_of(NODES['rmq2'][0])
    ch2 = c2.channel()
    got = []
    for _ in range(20):
        m = ch2.basic_get(DST_Q, auto_ack=True)
        if m[0] is None:
            break
        got.append(m[2].decode())
    c2.close()
    print("    取到 %d 条：%s" % (len(got), got[:5]))

    # 清理
    print("\n[7] 清理")
    ctl('rmq1', 'clear_parameter', 'shovel', 'l11-demo')
    c1 = conn_of(NODES['rmq1'][0])
    ch1 = c1.channel()
    try:
        ch1.queue_delete(queue=SRC_Q)
    except Exception:
        pass
    c1.close()
    c2 = conn_of(NODES['rmq2'][0])
    ch2 = c2.channel()
    try:
        ch2.queue_delete(queue=DST_Q)
    except Exception:
        pass
    c2.close()
    print("    已清理 Shovel 参数与两端队列")

    print("\n" + "=" * 74)
    print("要点")
    print("=" * 74)
    print("Shovel = 单向、持续的消息搬运工（move 语义：源端消费掉）。")
    print("与集群的区别：集群紧耦合（同 cookie、同版本、低延迟）；")
    print("Shovel/Federation 松耦合（各自独立、可跨地域/版本/信任边界）。")
    return 0


if __name__ == '__main__':
    sys.exit(main())
