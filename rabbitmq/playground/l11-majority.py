#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 11 实验 3：多数派可用（4.3 新语义）
========================================
知识点 3「故障与网络分区」的核心。

Raft 的多数派规则：3 节点集群需要 ⌊3/2⌋+1 = 2 个节点才能达成多数派。

本实验实测：
  A. 停 1 个节点（剩 2 个）→ 应【仍可用】（多数派达成）
  B. 再停 1 个（剩 1 个）→ 应【不可用】（失去多数派）
  C. 恢复 1 个（剩 2 个）→ 应【恢复可用】

这解释了为什么官方强烈建议 quorum 队列用【奇数个节点】：
  3 节点：容忍 1 个故障
  4 节点：也只容忍 1 个故障（需要 3 个达成多数派），但成本高 33%
  5 节点：容忍 2 个故障

⚠️ 本实验会 stop/start 集群节点，不触碰 rabbitmq-learn
"""
import json
import subprocess
import sys
import time

import pika

NODES = {'rmq1': (5681, 15681), 'rmq2': (5682, 15682), 'rmq3': (5683, 15683)}
CRED = pika.PlainCredentials('learn', 'learn123')
Q = 'l11.majority.q'


def docker(*args, timeout=120):
    r = subprocess.run(['docker'] + list(args), capture_output=True,
                       text=True, timeout=timeout)
    return r.stdout or ''


def api(node, path):
    _, ui = NODES[node]
    r = subprocess.run(
        ['curl', '-s', '-u', 'learn:learn123',
         'http://localhost:%d/api/%s' % (ui, path)],
        capture_output=True, text=True, timeout=15)
    try:
        return json.loads(r.stdout)
    except Exception:
        return None


def conn_of(port, timeout=15):
    return pika.BlockingConnection(pika.ConnectionParameters(
        host='localhost', port=port, credentials=CRED, heartbeat=600,
        blocked_connection_timeout=timeout,
        connection_attempts=2, retry_delay=1, socket_timeout=20))


def try_publish(node, body):
    """尝试通过某节点发布，返回 (成功?, 说明)"""
    port = NODES[node][0]
    try:
        c = conn_of(port, timeout=10)
        ch = c.channel()
        ch.confirm_delivery()
        ch.basic_publish(exchange='', routing_key=Q, body=body,
                         properties=pika.BasicProperties(delivery_mode=2))
        c.close()
        return True, "publish 成功"
    except Exception as e:
        return False, "%s: %s" % (type(e).__name__, str(e)[:90])


def probe_alive(label):
    """探测每个节点的可用性与队列 leader"""
    print("\n  --- %s ---" % label)
    rows = []
    for node in NODES:
        # 节点是否运行
        ps = docker('ps', '--format', '{{.Names}}')
        running = node in ps.split()
        if not running:
            rows.append((node, "(已停止)", "—"))
            continue
        ok, msg = try_publish(node, ('probe-%s' % node).encode())
        rows.append((node, "运行中", "✅ 可写" if ok else "❌ %s" % msg[:60]))
    print("")
    print("  | 节点 | 容器状态 | 写入结果 |")
    print("  |------|----------|----------|")
    for n, st, res in rows:
        print("  | %s | %s | %s |" % (n, st, res))
    return rows


def setup():
    c = conn_of(NODES['rmq1'][0])
    ch = c.channel()
    try:
        ch.queue_delete(queue=Q)
    except Exception:
        pass
    time.sleep(1)
    ch.queue_declare(queue=Q, durable=True, arguments={'x-queue-type': 'quorum'})
    time.sleep(2)
    c.close()
    d = api('rmq1', 'queues/%%2F/%s' % Q)
    print("\n  队列就绪：Leader=%s, Members=%s" % (
        (d or {}).get('leader'), (d or {}).get('members')))


def main():
    print("=" * 74)
    print("课 11 实验 3：多数派可用（Raft quorum）")
    print("=" * 74)
    print("三节点集群，多数派阈值 = ⌊3/2⌋+1 = 2")

    setup()

    print("\n" + "=" * 74)
    print("【A】停 1 个节点（剩 2 个 = 达到多数派）")
    print("=" * 74)
    docker('stop', 'rmq3')
    time.sleep(8)
    probe_alive("停掉 rmq3 后（存活 rmq1、rmq2）")

    print("\n" + "=" * 74)
    print("【B】再停 1 个（剩 1 个 = 失去多数派）")
    print("=" * 74)
    docker('stop', 'rmq2')
    time.sleep(8)
    probe_alive("再停掉 rmq2 后（仅剩 rmq1）")

    print("\n" + "=" * 74)
    print("【C】恢复 1 个（剩 2 个 = 重新达成多数派）")
    print("=" * 74)
    docker('start', 'rmq2')
    time.sleep(15)
    probe_alive("恢复 rmq2 后（存活 rmq1、rmq2）")

    # 全量恢复
    print("\n" + "=" * 74)
    print("【D】恢复全部节点")
    print("=" * 74)
    docker('start', 'rmq3')
    time.sleep(15)
    probe_alive("三节点全部恢复")

    d = api('rmq1', 'queues/%%2F/%s' % Q)
    if isinstance(d, dict):
        print("\n  最终 Leader  = %s" % d.get('leader'))
        print("  最终 Members = %s" % d.get('members'))
        print("  最终 Online  = %s" % d.get('online'))
        print("  队列深度     = %s" % d.get('messages'))

    # 清理
    try:
        c = conn_of(NODES['rmq1'][0])
        ch = c.channel()
        ch.queue_delete(queue=Q)
        c.close()
    except Exception:
        pass

    print("\n" + "=" * 74)
    print("结论")
    print("=" * 74)
    print("三节点集群：停 1 个仍可用，停 2 个不可用，恢复后自动重新可用。")
    print("")
    print("这就是 4.3 起【多数派可用】的语义：")
    print("  旧版本（Mnesia 时代）有 pause_minority / autoheal / ignore 等")
    print("  分区处理策略，管理员需要配置；4.3 起元数据存储统一为 Khepri，")
    print("  分区恢复按 Raft 语义【统一处理】，旧策略已全部移除。")
    return 0


if __name__ == '__main__':
    sys.exit(main())
