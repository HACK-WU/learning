#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 10 实验 11：流控与资源水位
==============================
知识点：
  - 内存高水位（vm_memory_high_watermark，当前环境 0.6 = 60% 内存）
  - 磁盘告警（disk_free_limit，当前环境 50000000 = 50 MB）
  - 触发后对【发布者】的影响：连接被阻塞（blocked），publish 挂起
  - 分页（paging）：内存中的消息被换出到磁盘

⚠️ 安全考量（重要）：
  真实触发内存告警需要把容器内存压到 60%，这对【用户的个人电脑】
  有风险（可能拖慢系统、触发宿主交换）。
  因此本实验采用【临时把水位调到极低值】的安全方式触发流控，
  测完【立即恢复原值】。

  原值：vm_memory_high_watermark = 0.6
       disk_free_limit          = 50000000

实验步骤：
  1. 记录当前水位配置
  2. 临时设为极低值（0.000001，约几十 KB）
  3. 观察 broker 日志/状态是否进入 memory alarm
  4. 尝试发布，验证是否被阻塞
  5. 【务必】恢复原值并验证

对应课程概念：
  - blocked_connection_timeout：pika 连接参数，阻塞后最多等多久
  - 客户端会收到 Connection.Blocked / Connection.Unblocked 通知
"""
import subprocess
import sys
import time

import pika

HOST, PORT = 'localhost', 5672
CRED = pika.PlainCredentials('learn', 'learn123')
ORIG_MEM = '0.6'
ORIG_DISK = '50000000'
Q = 'l10.flow.q'


def ctl(*args, timeout=60):
    r = subprocess.run(['docker', 'exec', 'rabbitmq-learn', 'rabbitmqctl'] + list(args),
                       capture_output=True, text=True, timeout=timeout)
    return (r.stdout or '') + (r.stderr or '')


def status():
    """读取内存/磁盘告警状态"""
    out = ctl('status')
    return out


def set_watermark(rel):
    return ctl('set_vm_memory_high_watermark', str(rel))


def conn_of(blocked_timeout=5):
    return pika.BlockingConnection(pika.ConnectionParameters(
        host=HOST, port=PORT, credentials=CRED, heartbeat=600,
        blocked_connection_timeout=blocked_timeout))


def main():
    print("=" * 74)
    print("课 10 实验 11：流控与资源水位（安全触发方式）")
    print("=" * 74)
    print("原始配置：vm_memory_high_watermark=%s, disk_free_limit=%s"
          % (ORIG_MEM, ORIG_DISK))

    print("\n【1】当前内存/磁盘状态")
    out = status()
    for line in out.splitlines():
        low = line.lower()
        if 'memory' in low or 'disk' in low or 'alarm' in low:
            print("  %s" % line.strip()[:100])

    print("\n【2】临时把内存高水位设为极低值 0.000001（触发告警）")
    print("  %s" % set_watermark('0.000001').strip()[:150])
    time.sleep(3)

    print("\n【3】告警状态")
    out = status()
    for line in out.splitlines():
        low = line.lower()
        if 'alarm' in low:
            print("  %s" % line.strip()[:120])

    print("\n【4】尝试发布消息，观察是否被阻塞")
    blocked_seen = {'blocked': False, 'unblocked': False}
    try:
        c = conn_of(blocked_timeout=8)
        # 注意：blocked/unblocked 回调属于 Connection，不是 Channel
        c.add_on_connection_blocked_callback(
            lambda conn, method: blocked_seen.update(blocked=True))
        c.add_on_connection_unblocked_callback(
            lambda conn, method: blocked_seen.update(unblocked=True))
        ch = c.channel()
        try:
            ch.queue_declare(queue=Q, durable=True)
        except Exception as e:
            print("  queue_declare 异常：%s" % str(e)[:100])

        t0 = time.time()
        try:
            ch.basic_publish(exchange='', routing_key=Q, body=b'flow-test',
                             properties=pika.BasicProperties(delivery_mode=2))
            print("  publish 成功（未被阻塞），耗时 %.2f s" % (time.time() - t0))
        except Exception as e:
            print("  publish 异常：%s（耗时 %.2f s）" % (
                type(e).__name__, time.time() - t0))
            print("  详情：%s" % str(e)[:200])
        try:
            c.close()
        except Exception:
            pass
    except Exception as e:
        print("  连接异常：%s" % str(e)[:150])

    print("\n  回调状态：blocked=%s, unblocked=%s"
          % (blocked_seen['blocked'], blocked_seen['unblocked']))

    print("\n【5】恢复原水位配置")
    print("  %s" % set_watermark(ORIG_MEM).strip()[:150])
    time.sleep(3)

    print("\n【6】恢复后验证")
    out = status()
    for line in out.splitlines():
        low = line.lower()
        if 'alarm' in low:
            print("  %s" % line.strip()[:120])

    # 清理
    try:
        c = conn_of()
        ch = c.channel()
        ch.queue_delete(queue=Q)
        c.close()
    except Exception:
        pass

    print("\n" + "=" * 74)
    print("要点")
    print("=" * 74)
    print("1. 内存高水位默认 0.4（本环境 0.6），达到后 broker 阻塞【发布者】连接")
    print("2. 磁盘告警默认 50MB，低于后同样阻塞发布者")
    print("3. 阻塞是【对发布者】的，消费者不受影响（消费能缓解积压）")
    print("4. 客户端需设置 blocked_connection_timeout，避免无限挂起")
    print("5. 生产上要监控这两个水位，并配置告警")
    return 0


if __name__ == '__main__':
    sys.exit(main())
