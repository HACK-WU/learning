#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 11 实验 5：Federation（与 Shovel 的关键差异）
====================================================
知识点 1「集群基础」：集群 vs Federation vs Shovel 的分工。

Federation 与 Shovel 最容易混淆。核心差异（本实验要验证）：

  Shovel     ：【move】语义——从源队列消费掉，转发到目标
  Federation ：【copy】语义——从上游【拉取副本】，上游消息仍保留

本实验实测：
  1. 建上游队列（rmq1）与下游队列（rmq2）
  2. 配置 federation upstream + policy
  3. 发布消息到上游，观察下游是否【自动拉取到副本】
  4. 关键验证：上游的消息【是否还在】（这是与 Shovel 的分水岭）
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

# 关键：Federation 的下游队列会去上游找【同名队列】拉取。
# 初版用了 l11.fed.up（上游）与 l11.fed.down（下游）两个不同的名字，
# 导致 federation 状态显示 running 但拉不到消息，因为
#   upstream_queue => <<"l11.fed.down">>
# 即：它去上游找名为 l11.fed.down 的队列（没有），而不是我发消息的 l11.fed.up。
# 修正：两端使用【同名】队列，这也正是 Federation 的真实语义。
Q = 'l11.fed.queue'


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
    print("课 11 实验 5：Federation（copy 语义）")
    print("=" * 74)
    print("上游：rmq1 的 %s" % Q)
    print("下游：rmq2 的 %s（通过 federation 拉取，【必须同名】）" % Q)

    # 1. 准备队列（两端同名）
    print("\n[1] 准备两端【同名】队列")
    c1 = conn_of(NODES['rmq1'][0])
    ch1 = c1.channel()
    try:
        ch1.queue_delete(queue=Q)
    except Exception:
        pass
    ch1.queue_declare(queue=Q, durable=True)
    c1.close()

    c2 = conn_of(NODES['rmq2'][0])
    ch2 = c2.channel()
    try:
        ch2.queue_delete(queue=Q)
    except Exception:
        pass
    ch2.queue_declare(queue=Q, durable=True)
    c2.close()
    print("    已就绪（两端队列名均为 %s）" % Q)

    # 2. 配置 federation upstream
    print("\n[2] 在下游（rmq2）配置 federation upstream 指向 rmq1")
    upstream_def = {"uri": "amqp://learn:learn123@rmq1:5672"}
    out = ctl('rmq2', 'set_parameter', 'federation-upstream', 'rmq1-up',
              json.dumps(upstream_def))
    print("    %s" % out.strip()[:100])

    # 3. 配置 policy：让下游队列通过 federation 拉取
    print("\n[3] 配置 policy（federate 下游队列）")
    policy = {
        "federation-upstream-set": "all",
    }
    out = ctl('rmq2', 'set_policy', 'l11-fed-policy',
              '^%s$' % Q, json.dumps(policy), '--apply-to', 'queues')
    print("    %s" % out.strip()[:100])

    time.sleep(5)

    # 4. 发布到上游
    N = 5
    print("\n[4] 向上游（rmq1）的同名队列发布 %d 条消息" % N)
    c1 = conn_of(NODES['rmq1'][0])
    ch1 = c1.channel()
    ch1.confirm_delivery()
    for i in range(N):
        ch1.basic_publish(exchange='', routing_key=Q,
                          body=b'fed-msg-%03d' % i,
                          properties=pika.BasicProperties(delivery_mode=2))
    c1.close()
    time.sleep(2)
    print("    上游队列深度 = %s" % depth('rmq1', Q))

    # 5. 等待下游拉取
    print("\n[5] 等待下游通过 federation 拉取（最多 60 秒）")
    t0 = time.time()
    d_down = 0
    while time.time() - t0 < 60:
        d_down = depth('rmq2', Q) or 0
        if d_down >= N:
            break
        time.sleep(2)

    d_up = depth('rmq1', Q) or 0
    d_down = depth('rmq2', Q) or 0

    print("")
    print("    | 队列 | 节点 | 深度 |")
    print("    |------|------|------|")
    print("    | %s（上游）| rmq1 | %s |" % (Q, d_up))
    print("    | %s（下游）| rmq2 | %s |" % (Q, d_down))
    print("")

    if d_down > 0:
        print("    ✅ 下游拉取到 %d 条副本" % d_down)
        if d_up > 0:
            print("    ✅ 上游仍保留 %d 条 → 【copy 语义】确认" % d_up)
            print("       这正是 Federation 与 Shovel 的分水岭：")
            print("       Shovel 会消费掉源端（move），Federation 只拉副本（copy）")
        else:
            print("    ⚠️ 上游已被清空 → 表现更像 Shovel 的 move 语义")
    else:
        print("    ⚠️ 下游未收到消息，federation 可能未生效")

    # 6. 状态
    print("\n[6] Federation 状态")
    out = ctl('rmq2', 'federation_status')
    for ln in out.splitlines()[:8]:
        if ln.strip():
            print("    %s" % ln.strip()[:110])

    # 7. 清理
    print("\n[7] 清理")
    ctl('rmq2', 'clear_policy', 'l11-fed-policy')
    ctl('rmq2', 'clear_parameter', 'federation-upstream', 'rmq1-up')
    c1 = conn_of(NODES['rmq1'][0])
    ch1 = c1.channel()
    try:
        ch1.queue_delete(queue=Q)
    except Exception:
        pass
    c1.close()
    c2 = conn_of(NODES['rmq2'][0])
    ch2 = c2.channel()
    try:
        ch2.queue_delete(queue=Q)
    except Exception:
        pass
    c2.close()
    print("    已清理 policy、upstream 与两端队列")

    print("\n" + "=" * 74)
    print("三种扩展方式的分工")
    print("=" * 74)
    print("集群      ：紧耦合，同 cookie/版本，低延迟网络，共享队列")
    print("Federation：松耦合，【copy】语义，跨地域/跨组织，订阅式拉取")
    print("Shovel    ：松耦合，【move】语义，单向搬运，更像是'搬电线'")
    return 0


if __name__ == '__main__':
    sys.exit(main())
