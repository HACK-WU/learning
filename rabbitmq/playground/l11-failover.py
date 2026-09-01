#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 11 实验 2：leader 故障切换与数据安全（本课核心）
=====================================================
知识点 2「复制型队列」+ 知识点 3「故障」的核心实证。

实验设计：
  1. 建 quorum 队列，发 20 条【已确认】的消息（publisher confirms + 持久化）
  2. 记录当前 leader
  3. 【停掉 leader 节点】（docker stop，模拟宕机）
  4. 观察：剩余两节点能否选出新 leader？要多久？
  5. 连到新集群，检查消息是否还在、能否继续消费
  6. 恢复节点，观察副本是否重新同步

对照组：
  7. 同样场景下 classic 队列的表现（预期：不可用或数据丢失）

这是"高可用"这个词最直接的验证——不是听概念，是看数据还在不在。

⚠️ 注意：docker stop 只停集群容器 rmq1/rmq2/rmq3，
       绝不触碰 rabbitmq-learn（前 10 课环境）
"""
import json
import subprocess
import sys
import time

import pika

NODES = {'rmq1': (5681, 15681), 'rmq2': (5682, 15682), 'rmq3': (5683, 15683)}
CRED = pika.PlainCredentials('learn', 'learn123')


def docker(*args, timeout=90):
    r = subprocess.run(['docker'] + list(args),
                       capture_output=True, text=True, timeout=timeout)
    return r.stdout or ''


def api(node, path, tries=1):
    _, ui = NODES[node]
    for _ in range(tries):
        r = subprocess.run(
            ['curl', '-s', '-u', 'learn:learn123',
             'http://localhost:%d/api/%s' % (ui, path)],
            capture_output=True, text=True, timeout=15)
        try:
            return json.loads(r.stdout)
        except Exception:
            time.sleep(1)
    return None


def conn_of(port, timeout=30):
    return pika.BlockingConnection(pika.ConnectionParameters(
        host='localhost', port=port, credentials=CRED, heartbeat=600,
        blocked_connection_timeout=timeout,
        connection_attempts=3, retry_delay=2,
        socket_timeout=30))


def qinfo(node, q, tries=15):
    for _ in range(tries):
        d = api(node, 'queues/%%2F/%s' % q)
        if isinstance(d, dict) and d.get('leader'):
            return d
        time.sleep(1)
    return api(node, 'queues/%%2F/%s' % q)


def publish_batch(port, q, n, prefix=b'msg'):
    """用 publisher confirms 发布 n 条持久化消息，返回确认数"""
    c = conn_of(port)
    ch = c.channel()
    ch.confirm_delivery()
    ok = 0
    for i in range(n):
        try:
            ch.basic_publish(exchange='', routing_key=q,
                             body=b'%s-%03d' % (prefix, i),
                             properties=pika.BasicProperties(delivery_mode=2))
            ok += 1
        except Exception as e:
            print("    发布第 %d 条失败：%s" % (i, str(e)[:60]))
            break
    c.close()
    return ok


def drain(port, q, limit=100):
    """取走所有消息，返回内容列表"""
    got = []
    c = conn_of(port)
    ch = c.channel()
    for _ in range(limit):
        m = ch.basic_get(q, auto_ack=True)
        if m[0] is None:
            break
        got.append(m[2].decode())
    c.close()
    return got


def run_quorum_case():
    print("\n" + "=" * 74)
    print("【实验组】quorum 队列：停掉 leader 后的表现")
    print("=" * 74)

    Q = 'l11.failover.q'
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

    info = qinfo('rmq1', Q)
    leader = (info or {}).get('leader')
    leader_name = (leader or '').split('@')[-1]
    print("\n[1] 队列已建，Leader = %s" % leader)
    print("    Members = %s" % (info or {}).get('members'))

    # 发布 20 条
    n = publish_batch(NODES['rmq1'][0], Q, 20)
    time.sleep(1)
    d = qinfo('rmq1', Q)
    print("\n[2] 已发布 %d 条持久化消息（publisher confirms 已确认）" % n)
    print("    当前队列深度 = %s" % (d or {}).get('messages'))

    # 停掉 leader
    print("\n[3] 停掉 leader 节点 %s（docker stop，模拟宕机）..." % leader_name)
    t0 = time.time()
    docker('stop', leader_name)
    print("    已停止，耗时 %.2f s" % (time.time() - t0))

    # 找存活节点
    alive = [x for x in NODES if x != leader_name]
    print("\n[4] 存活节点：%s" % alive)
    print("    等待 Raft 重新选举新 leader（最多 60 秒）...")

    new_leader = None
    waited = None
    t1 = time.time()
    for node in alive:
        for _ in range(60):
            d = api(node, 'queues/%%2F/%s' % Q)
            if isinstance(d, dict) and d.get('leader'):
                nl = d.get('leader')
                nl_name = (nl or '').split('@')[-1]
                if nl_name != leader_name:
                    new_leader = nl
                    waited = time.time() - t1
                    break
            time.sleep(1)
        if new_leader:
            break

    if new_leader:
        print("    ✅ 新 Leader = %s（选举耗时 %.2f s）" % (new_leader, waited))
    else:
        print("    ❌ 60 秒内未选出新 leader")

    # 检查消息
    print("\n[5] 检查数据安全")
    alive_node = alive[0]
    d = api(alive_node, 'queues/%%2F/%s' % Q)
    depth = (d or {}).get('messages')
    print("    通过 %s 查询队列深度 = %s（原始 20 条）" % (alive_node, depth))

    # 消费
    try:
        msgs = drain(NODES[alive_node][0], Q, limit=50)
        print("    实际消费到 %d 条" % len(msgs))
        if msgs:
            print("    前 3 条：%s" % msgs[:3])
            print("    末 3 条：%s" % msgs[-3:])
        if len(msgs) >= n:
            print("    ✅ 数据零丢失——quorum 的 Raft 复制生效")
        else:
            print("    ⚠️ 丢失 %d 条" % (n - len(msgs)))
    except Exception as e:
        print("    消费异常：%s" % str(e)[:120])

    # 继续发布，验证新 leader 可写
    print("\n[6] 故障期间继续写入（验证新 leader 可服务）")
    try:
        n2 = publish_batch(NODES[alive_node][0], Q, 5, prefix=b'after')
        print("    ✅ 成功写入 %d 条新消息" % n2)
    except Exception as e:
        print("    ❌ 写入失败：%s" % str(e)[:120])

    # 恢复节点
    print("\n[7] 恢复节点 %s（docker start）" % leader_name)
    docker('start', leader_name)
    for node in NODES:
        for _ in range(40):
            r = docker('exec', node, 'rabbitmqctl', 'await_startup', '--timeout', '5')
            if 'error' not in r.lower() or r.strip() == '':
                break
            time.sleep(2)
    time.sleep(5)

    d = api('rmq1', 'queues/%%2F/%s' % Q)
    if isinstance(d, dict):
        print("    恢复后 Leader  = %s" % d.get('leader'))
        print("    恢复后 Members = %s" % d.get('members'))
        print("    恢复后 Online  = %s" % d.get('online'))
        print("    队列深度       = %s" % d.get('messages'))
        print("")
        print("    ⚠️ 注意：恢复后的 leader 【未必切回原节点】——")
        print("       Raft 不会为了'回到原状'再引发一次选举，这是正常的")

    return leader, new_leader


def run_classic_case():
    print("\n" + "=" * 74)
    print("【对照组】classic 队列：宿主节点宕机后的表现")
    print("=" * 74)

    Q = 'l11.failover.classic'
    c = conn_of(NODES['rmq1'][0])
    ch = c.channel()
    try:
        ch.queue_delete(queue=Q)
    except Exception:
        pass
    time.sleep(1)
    ch.queue_declare(queue=Q, durable=True)     # classic + durable
    time.sleep(1)
    c.close()

    d = api('rmq1', 'queues/%%2F/%s' % Q)
    host = (d or {}).get('node')
    host_name = (host or '').split('@')[-1]
    print("\n[1] classic 队列已建（durable=True），宿主节点 = %s" % host)

    n = publish_batch(NODES['rmq1'][0], Q, 20)
    time.sleep(1)
    print("[2] 已发布 %d 条持久化消息" % n)

    print("\n[3] 停掉宿主节点 %s ..." % host_name)
    docker('stop', host_name)
    time.sleep(5)

    alive = [x for x in NODES if x != host_name]
    print("[4] 存活节点：%s" % alive)

    print("\n[5] 尝试从存活节点访问该队列")
    for node in alive:
        port = NODES[node][0]
        try:
            c = conn_of(port, timeout=10)
            ch = c.channel()
            m = ch.basic_get(Q, auto_ack=True)
            print("    %s: 能访问，取到 %s" % (
                node, m[2].decode() if m[0] is not None else "（空队列）"))
            c.close()
        except Exception as e:
            print("    %s: ❌ %s" % (node, str(e)[:100]))

    print("\n    清理并恢复节点")
    docker('start', host_name)
    time.sleep(8)


def main():
    print("=" * 74)
    print("课 11 实验 2：leader 故障切换与数据安全")
    print("=" * 74)
    print("集群：rmq1 / rmq2 / rmq3（4.3.5）")
    print("⚠️ 本实验会 stop/start 集群节点，不触碰 rabbitmq-learn")

    run_quorum_case()
    run_classic_case()

    # 清理
    try:
        c = conn_of(NODES['rmq1'][0])
        ch = c.channel()
        for q in ('l11.failover.q', 'l11.failover.classic'):
            try:
                ch.queue_delete(queue=q)
            except Exception:
                pass
        c.close()
    except Exception:
        pass

    print("\n" + "=" * 74)
    print("结论")
    print("=" * 74)
    print("quorum 队列：leader 宕机后自动选出新 leader，已确认消息零丢失")
    print("classic 队列：宿主节点宕机后队列不可用（4.0 起无镜像队列兜底）")
    return 0


if __name__ == '__main__':
    sys.exit(main())
