#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 12 事实守护脚本：把本课的硬事实固化为可重复执行的断言。

背景：本课出现过「先写了结论、后来被实测推翻」的情况，故建此脚本。
     任何一条失败都说明讲义里的对应表述需要更新。

守护的事实：
  G1  Direct Reply-To 完整往返可成功（同连接 + 同信道 + 先注册后发布）
  G2  跨信道（消费 A / 发布 B）→ 响应【静默丢失】（不报错，但收不到）
  G3  同信道但顺序颠倒（先发后注册）→ 异步 406 fast reply consumer does not exist
  G4  伪队列绑死连接：另一连接访问 amq.rabbitmq.reply-to → 404 NOT_FOUND
  G5  普通回调队列（exclusive）方案完整往返可成功
  G6  本环境 vm_memory_high_watermark = 0.6（4.x 默认，非 3.x 的 0.4）
  G7  Prometheus 端点 :15692 暴露的指标名（讲义引用必须真实存在）
"""
import re
import subprocess
import sys
import time
import uuid

import pika

PORT = 5681
CRED = pika.PlainCredentials('learn', 'learn123')
RPC_Q = 'l12.rpc.drt'
PSEUDO = 'amq.rabbitmq.reply-to'

PASS = []
FAIL = []


def check(name, ok, detail=''):
    (PASS if ok else FAIL).append(name)
    print("  [%s] %s%s" % ("✅" if ok else "❌", name,
                           ("  —— " + detail) if detail else ""))


def newconn():
    return pika.BlockingConnection(pika.ConnectionParameters(
        host='localhost', port=PORT, credentials=CRED, heartbeat=600,
        blocked_connection_timeout=120, socket_timeout=120))


def server_ready():
    r = subprocess.run(
        ['docker', 'exec', 'rmq1', 'rabbitmqctl', 'list_queues',
         'name', 'messages', 'consumers', '--quiet'],
        capture_output=True, text=True, timeout=90)
    for ln in (r.stdout or '').splitlines()[1:]:
        p = ln.split('\t')
        if len(p) >= 3 and p[0].strip() == RPC_Q:
            return p[2].strip()
    return None


def wait_reply(ch, cid, timeout=6.0):
    try:
        for m in ch.consume(PSEUDO, inactivity_timeout=timeout,
                            auto_ack=True):
            if m[0] is None:
                return False, None
            if m[1].correlation_id == cid:
                return True, m[2].decode()
    except Exception as e:
        return False, "%s: %s" % (type(e).__name__,
                                  str(e).split('\n')[0][:80])
    return False, None


def g1_g2_g3():
    print("\n[G1/G2/G3] Direct Reply-To 的三种用法")
    cc = server_ready()
    if not cc or cc == '0':
        print("  ⚠️ 服务端未就绪，跳过 G1/G2/G3（需先跑 l12-drt-server.py）")
        return
    print("  服务端 consumers=%s" % cc)

    # G1 正例
    conn = newconn()
    ch = conn.channel()
    try:
        next(ch.consume(PSEUDO, auto_ack=True, inactivity_timeout=0.1))
    except StopIteration:
        pass
    cid = str(uuid.uuid4())
    ch.basic_publish(exchange='', routing_key=RPC_Q, body=b'5',
                     properties=pika.BasicProperties(
                         reply_to=PSEUDO, correlation_id=cid))
    got, val = wait_reply(ch, cid)
    check("G1 同连接+同信道+先注册后发布 → 往返成功",
          got and val == '5', "响应=%s" % val)
    try:
        conn.close()
    except Exception:
        pass

    # G2 跨信道
    conn = newconn()
    chA = conn.channel()
    chB = conn.channel()
    try:
        next(chA.consume(PSEUDO, auto_ack=True, inactivity_timeout=0.1))
    except StopIteration:
        pass
    cid = str(uuid.uuid4())
    try:
        chB.basic_publish(exchange='', routing_key=RPC_Q, body=b'5',
                          properties=pika.BasicProperties(
                              reply_to=PSEUDO, correlation_id=cid))
    except Exception:
        pass
    got, val = wait_reply(chA, cid, timeout=5.0)
    check("G2 跨信道 → 响应静默丢失（不报错但收不到）",
          (not got) and val is None,
          "收不到响应且无异常 = 静默丢失" if not got else "竟然收到了=%s" % val)
    try:
        conn.close()
    except Exception:
        pass

    # G3 顺序颠倒
    conn = newconn()
    ch = conn.channel()
    cid = str(uuid.uuid4())
    err = None
    try:
        ch.basic_publish(exchange='', routing_key=RPC_Q, body=b'5',
                         properties=pika.BasicProperties(
                             reply_to=PSEUDO, correlation_id=cid))
    except Exception as e:
        err = str(e)
    if err is None:
        _, val = wait_reply(ch, cid, timeout=5.0)
        err = val  # wait_reply 捕获的异常会以字符串返回
    check("G3 先发后注册 → 异步 406 fast reply consumer does not exist",
          err is not None and 'fast reply consumer does not exist' in str(err),
          str(err)[:70] if err else "未复现")
    try:
        conn.close()
    except Exception:
        pass


def g4():
    print("\n[G4] 伪队列绑死连接")
    conn = newconn()
    ch = conn.channel()
    try:
        next(ch.consume(PSEUDO, auto_ack=True, inactivity_timeout=0.1))
    except StopIteration:
        pass
    # 在【另一个连接】上访问
    conn2 = newconn()
    ch2 = conn2.channel()
    err = None
    try:
        ch2.basic_get(PSEUDO, auto_ack=True)
    except Exception as e:
        err = str(e)
    check("G4 另一连接访问伪队列 → 404 NOT_FOUND",
          err is not None and 'NOT_FOUND' in err.upper(),
          str(err).split('\n')[0][:70] if err else "未复现")
    for c in (conn2, conn):
        try:
            c.close()
        except Exception:
            pass


def g5():
    print("\n[G5] 普通回调队列（exclusive）方案")
    cc = server_ready()
    if not cc or cc == '0':
        print("  ⚠️ 服务端未就绪，跳过 G5")
        return
    conn = newconn()
    ch = conn.channel()
    cb_ch = conn.channel()
    qd = cb_ch.queue_declare(queue='', exclusive=True)
    cbq = qd.method.queue
    corr = {}
    for n in (5, 10, 15, 20):
        cid = str(uuid.uuid4())
        corr[cid] = n
        ch.basic_publish(exchange='', routing_key=RPC_Q, body=str(n).encode(),
                         properties=pika.BasicProperties(
                             reply_to=cbq, correlation_id=cid,
                             delivery_mode=2))
    expected = {5: '5', 10: '55', 15: '610', 20: '6765'}
    collected = {}
    t0 = time.time()
    for m in cb_ch.consume(cbq, inactivity_timeout=20, auto_ack=True):
        if m[0] is None:
            break
        collected[m[1].correlation_id] = m[2].decode()
        if len(collected) >= 4 or time.time() - t0 > 20:
            break
    ok = sum(1 for cid, n in corr.items()
             if collected.get(cid) == expected[n])
    check("G5 普通回调队列 4/4 往返成功", ok == 4, "正确 %d/4" % ok)
    try:
        conn.close()
    except Exception:
        pass


def g6():
    print("\n[G6] 本环境内存水位（4.x 默认 0.6，不是 3.x 的 0.4）")
    r = subprocess.run(
        ['docker', 'exec', 'rmq1', 'rabbitmqctl', 'environment'],
        capture_output=True, text=True, timeout=90)
    out = r.stdout or ''
    val = None
    # 真实输出形如：      {vm_memory_high_watermark,0.6},
    m = re.search(r'\{vm_memory_high_watermark\s*,\s*([0-9.]+)\s*\}', out)
    if m:
        try:
            val = float(m.group(1))
        except ValueError:
            val = None
    check("G6 内存高水位 = 0.6", val == 0.6, "实测值=%s" % val)


def g7():
    print("\n[G7] Prometheus 端点 :15692 的指标名")
    subprocess.run(
        ['docker', 'cp',
         '/mnt/d/projects/learning/rabbitmq/playground/l12-fetch-metrics.sh',
         'rmq1:/tmp/fetch.sh'], capture_output=True, timeout=60)
    r = subprocess.run(['docker', 'exec', 'rmq1', 'bash', '/tmp/fetch.sh'],
                       capture_output=True, text=True, timeout=90)
    out = r.stdout or ''
    names = set()
    for ln in out.splitlines():
        if ln.startswith('# TYPE '):
            names.add(ln.split()[2])

    # 讲义引用的正确指标
    for m in ['rabbitmq_queue_messages_ready',
              'rabbitmq_queue_messages_unacked',
              'rabbitmq_queue_consumers',
              'rabbitmq_queue_messages',
              'rabbitmq_process_resident_memory_bytes',
              'rabbitmq_resident_memory_limit_bytes',
              'rabbitmq_disk_space_available_bytes',
              'rabbitmq_disk_space_available_limit_bytes',
              'rabbitmq_channel_messages_published_total',
              'rabbitmq_queue_messages_delivered_total',
              'rabbitmq_queue_messages_acked_total',
              'rabbitmq_alarms_memory_used_watermark',
              'rabbitmq_alarms_free_disk_space_watermark']:
        check("G7 指标存在：%s" % m, m in names)

    # 讲义中【错误】引用的指标名（这些应当不存在，若存在说明版本变了）
    for m in ['rabbitmq_node_mem_used', 'rabbitmq_node_mem_limit',
              'rabbitmq_node_disk_free', 'rabbitmq_node_disk_free_limit']:
        check("G7 旧名已不可用：%s" % m, m not in names,
              "该名在新版端点中不存在，讲义不可引用")


def main():
    print("=" * 72)
    print("课 12 事实守护脚本")
    print("=" * 72)
    g1_g2_g3()
    g4()
    g5()
    g6()
    g7()

    print("\n" + "=" * 72)
    print("结果：通过 %d / 失败 %d" % (len(PASS), len(FAIL)))
    if FAIL:
        print("失败项：")
        for f in FAIL:
            print("  ❌ %s" % f)
    else:
        print("✅ 全部通过")
    print("=" * 72)
    return 1 if FAIL else 0


if __name__ == '__main__':
    sys.exit(main())
