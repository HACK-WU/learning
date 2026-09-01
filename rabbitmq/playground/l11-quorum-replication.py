#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 11 实验 1（修正版）：quorum 队列的副本分布与 leader 选举
==============================================================
修正 l11-quorum-replication.py 的三个问题：

  1. `rabbitmqctl quorum_status` 在 4.3.5 中【已被移除】
     → 改用 Management API 的 leader / members / online 字段
  2. 场景 C 用 list_queues 判断"哪个节点有队列"是错的
     → 集群中【所有节点都能看到队列元数据】，必须用 `node` 字段判断真实宿主
  3. 顺带记录一个 4.x 的重要限制（来自 rabbitmqctl help 原文）：
       rename_cluster_node : DEPRECATED. ... Node renaming is incompatible
       with Raft-based features such as quorum queues, streams, Khepri.

环境：三节点集群 rmq1/rmq2/rmq3（4.3.5）
  AMQP 5681/5682/5683，UI 15681/15682/15683
"""
import json
import subprocess
import sys
import time

import pika

NODES = {'rmq1': (5681, 15681), 'rmq2': (5682, 15682), 'rmq3': (5683, 15683)}
CRED = pika.PlainCredentials('learn', 'learn123')
Q = 'l11.quorum.demo'


def api(node, path):
    _, ui = NODES[node]
    r = subprocess.run(
        ['curl', '-s', '-u', 'learn:learn123',
         'http://localhost:%d/api/%s' % (ui, path)],
        capture_output=True, text=True, timeout=30)
    try:
        return json.loads(r.stdout)
    except Exception:
        return None


def queue_info(node, q):
    d = api(node, 'queues/%%2F/%s' % q)
    if not isinstance(d, dict):
        return None
    return {
        'leader': d.get('leader'),
        'members': d.get('members') or [],
        'online': d.get('online') or [],
        'node': d.get('node'),
        'type': d.get('type'),
    }


def conn_of(port):
    return pika.BlockingConnection(pika.ConnectionParameters(
        host='localhost', port=port, credentials=CRED, heartbeat=600,
        blocked_connection_timeout=60))


def wait_info(node, q, tries=20):
    for _ in range(tries):
        info = queue_info(node, q)
        if info and info.get('leader'):
            return info
        time.sleep(1)
    return queue_info(node, q)


def scenario_a():
    print("\n【A】quorum 队列的副本分布（默认 3 副本）")
    c = conn_of(NODES['rmq1'][0])
    ch = c.channel()
    try:
        ch.queue_delete(queue=Q)
    except Exception:
        pass
    time.sleep(1)
    ch.queue_declare(queue=Q, durable=True,
                     arguments={'x-queue-type': 'quorum'})
    time.sleep(2)
    info = wait_info('rmq1', Q)
    print("  队列类型：%s" % info.get('type'))
    print("  Leader   : %s" % info.get('leader'))
    print("  Members  : %s" % info.get('members'))
    print("  Online   : %s" % info.get('online'))
    print("")
    print("  → 三个节点各持一份副本（members=3），这是 Raft 复制的物理体现")
    c.close()
    return info


def scenario_b(info):
    print("\n【B】连接【非 leader】节点发布与消费（验证请求转发）")
    leader = info.get('leader') or ''
    leader_name = leader.split('@')[-1]
    others = [n for n in NODES if n != leader_name]
    if not others:
        print("  无法确定非 leader 节点，跳过")
        return
    target = others[0]
    port = NODES[target][0]
    print("  Leader 在 %s，本次连接【%s】（AMQP %d）" % (leader_name, target, port))

    c = conn_of(port)
    ch = c.channel()
    ch.basic_publish(exchange='', routing_key=Q,
                     body=('via-%s' % target).encode(),
                     properties=pika.BasicProperties(delivery_mode=2))
    print("  已通过 %s 发布" % target)
    time.sleep(1)
    m = ch.basic_get(Q, auto_ack=True)
    if m[0] is not None:
        print("  通过 %s 取回：%s" % (target, m[2].decode()))
        print("  ✅ 连非 leader 节点也能正常读写（请求被内部转发到 leader）")
    else:
        print("  ⚠️ 未取到消息")
    c.close()


def scenario_c():
    print("\n【C】对比：classic 队列在集群中【不复制】")
    qc = 'l11.classic.demo'
    c = conn_of(NODES['rmq1'][0])
    ch = c.channel()
    try:
        ch.queue_delete(queue=qc)
    except Exception:
        pass
    time.sleep(1)
    ch.queue_declare(queue=qc, durable=True)      # classic 默认
    time.sleep(1)
    info = queue_info('rmq1', qc)
    print("")
    print("  队列类型：%s" % info.get('type'))
    print("  宿主节点（node）：%s" % info.get('node'))
    print("  members：%s" % (info.get('members') or '（无——classic 不复制）'))
    print("")
    print("  ⚠️ 关键认知：在集群中，【所有节点都能看到队列元数据】，")
    print("     用 list_queues 在每个节点上查都能查到——但【数据只在一个节点上】。")
    print("     判断真实宿主要看 node 字段，而不是'能不能查到'。")
    print("")
    print("  → classic 队列所在节点宕机，该队列就不可用。")
    print("     这正是 4.0 移除镜像队列后，生产必须用 quorum 的原因。")
    ch.queue_delete(queue=qc)
    c.close()


def scenario_d():
    print("\n【D】x-quorum-initial-group-size 对副本数的影响")
    print("")
    print("| 声明参数 | Leader | Members 数 |")
    print("|----------|--------|------------|")
    for size in (1, 3):
        qn = 'l11.size.%d' % size
        c = conn_of(NODES['rmq1'][0])
        ch = c.channel()
        try:
            ch.queue_delete(queue=qn)
        except Exception:
            pass
        time.sleep(1)
        try:
            ch.queue_declare(queue=qn, durable=True, arguments={
                'x-queue-type': 'quorum',
                'x-quorum-initial-group-size': size,
            })
            time.sleep(2)
            info = wait_info('rmq1', qn)
            print("| size=%d | %s | %d |" % (
                size, info.get('leader'), len(info.get('members') or [])))
        except Exception as e:
            print("| size=%d | ❌ %s | - |" % (size, str(e)[:60]))
        try:
            ch.queue_delete(queue=qn)
        except Exception:
            pass
        c.close()
    print("")
    print("  → size=1 是【单副本 quorum】，无高可用，仅特殊场景使用")


def main():
    print("=" * 74)
    print("课 11 实验 1（修正版）：quorum 副本分布与 leader 选举")
    print("=" * 74)
    print("集群：rmq1 / rmq2 / rmq3（4.3.5）｜ pika %s" % pika.__version__)

    info = scenario_a()
    scenario_b(info)
    scenario_c()
    scenario_d()

    c = conn_of(NODES['rmq1'][0])
    ch = c.channel()
    try:
        ch.queue_delete(queue=Q)
    except Exception:
        pass
    c.close()

    print("\n" + "=" * 74)
    print("要点")
    print("=" * 74)
    print("1. quorum 队列默认在【所有节点】放副本（本例 3 个）")
    print("2. 只有一个 leader 处理读写，follower 通过 Raft 同步")
    print("3. 客户端可连任意节点——非 leader 节点会把请求转发给 leader")
    print("4. classic 队列【不复制】，数据只在 node 字段标识的那个节点上")
    print("5. 4.3.5 已移除 rabbitmqctl quorum_status，改用 Management API")
    return 0


if __name__ == '__main__':
    sys.exit(main())
