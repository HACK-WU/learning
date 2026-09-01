# -*- coding: utf-8 -*-
"""故障演练：真停一个节点，验证"高可用"不是写在文档里的空话。

⚠️ 这是可用性这个非功能约束的**唯一真实验证方式**。
代码里写一百遍"高可用"，不如真停一个节点看看消息还在不在。

课 11 已实测的结论（本脚本复现之）：
  - quorum 队列：leader 宕机 → 0.07s 选出新 leader → 已确认消息零丢失
  - classic 队列：宿主宕机 → NOT_FOUND，完全不可用
  - 失败形态是 **NACK 而非异常** → 不开 publisher confirm 则完全感知不到

运行（需要你能执行 docker）：
    python3 run_chaos.py

脚本会：
  1. 建 quorum 队列并写入 N 条 confirm 确认的消息
  2. 提示你手动执行 docker stop rmq1
  3. 验证：仍能连上（换节点）→ 仍能写入 → 消息一条不少
  4. 提示你 docker start rmq1 恢复
"""
import json
import logging
import time

import pika
from pika.exceptions import AMQPConnectionError, NackError

from config import Q_FULFILL_VIP, NODES
from connection import ConnectionManager, setup_logging

logger = logging.getLogger(__name__)

CHAOS_QUEUE = 'chaos.quorum.test'
N_MSGS = 20


import subprocess
import sys

AUTO = '--auto' in sys.argv  # 自动模式：自己执行 docker，不等用户输入


def do(cmd):
    """执行 shell 命令（自动模式用）。"""
    print(f'  $ {cmd}')
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if r.stdout.strip():
        print(f'    {r.stdout.strip()[:200]}')
    return r


def wait_for_user(prompt, auto_cmd=None):
    """等待用户操作；自动模式下直接执行 auto_cmd。"""
    print()
    print('─' * 74)
    if AUTO and auto_cmd:
        print(f'▶ [自动模式] {prompt.splitlines()[0]}')
        do(auto_cmd)
        if 'start' in auto_cmd:
            print('  等待副本同步...')
            time.sleep(12)
    else:
        input(f'▶ {prompt}\n  （完成后按回车继续）')
    print('─' * 74)
    print()


def check_queue_depth(mgr, queue):
    """用 passive 声明读队列深度（不消费、不修改）。"""
    try:
        ch = mgr.get_channel()
        resp = ch.queue_declare(queue=queue, durable=True, passive=True)
        return resp.method.message_count
    except Exception as e:  # noqa: BLE001
        return f'查询失败：{type(e).__name__}'


def main():
    setup_logging()
    print('=' * 74)
    print('故障演练：停掉一个节点，验证高可用')
    print('=' * 74)
    print()
    print('本演练验证三件事：')
    print('  1. 已确认（confirm）的消息，在节点宕机后是否还在')
    print('  2. 宕机期间系统是否仍可写入')
    print('  3. 失败形态是"报错"还是"静默"')
    print()

    mgr = ConnectionManager()
    ch = mgr.get_channel()
    ch.confirm_delivery()

    # ---- 准备 ----
    try:
        ch.queue_delete(queue=CHAOS_QUEUE)
    except Exception:
        pass
    ch = mgr.get_channel()
    ch.confirm_delivery()
    ch.queue_declare(queue=CHAOS_QUEUE, durable=True,
                     arguments={'x-queue-type': 'quorum'})

    print(f'--- 发布 {N_MSGS} 条持久化消息（开启 confirm）---')
    confirmed = 0
    for i in range(N_MSGS):
        try:
            ch.basic_publish(
                exchange='', routing_key=CHAOS_QUEUE,
                body=json.dumps({'seq': i, 'msg': f'chaos-{i:03d}'},
                                ensure_ascii=False),
                properties=pika.BasicProperties(delivery_mode=2),
            )
            confirmed += 1
        except NackError:
            logger.error('第 %d 条被 NACK', i)
    print(f'  broker 已确认：{confirmed}/{N_MSGS} 条')
    print()

    depth_before = check_queue_depth(mgr, CHAOS_QUEUE)
    print(f'  宕机前队列深度：{depth_before}')
    print()

    # ---- 让用户停节点 ----
    wait_for_user(
        '请在另一个终端执行：docker stop rmq1\n'
        '  （这会停掉当前 leader 节点，模拟真实宕机）',
        auto_cmd='docker stop rmq1',
    )
    if AUTO:
        time.sleep(3)  # 给选举留时间

    # ---- 验证 1：还能连上吗 ----
    print('--- 验证 1：连接是否可用 ---')
    new_mgr = ConnectionManager()
    try:
        nch = new_mgr.get_channel()
        nch.confirm_delivery()
        print('  ✓ 仍能连上（自动切换到存活节点）')
    except AMQPConnectionError as e:
        print(f'  ✗ 连不上：{e}')
        print('  演练中止')
        return

    # ---- 验证 2：消息还在吗 ----
    print()
    print('--- 验证 2：已确认消息是否还在 ---')
    time.sleep(1)
    depth_after = check_queue_depth(new_mgr, CHAOS_QUEUE)
    print(f'  宕机后队列深度：{depth_after}')
    if depth_after == depth_before:
        print(f'  ✓ {depth_before} 条消息一条不少（已确认 = 已落盘到多数派）')
    else:
        print(f'  ✗ 深度变化：{depth_before} → {depth_after}')

    # ---- 验证 3：还能写入吗 ----
    print()
    print('--- 验证 3：宕机期间是否仍可写入 ---')
    written = 0
    try:
        for i in range(5):
            nch.basic_publish(
                exchange='', routing_key=CHAOS_QUEUE,
                body=json.dumps({'seq': f'after-{i}'}, ensure_ascii=False),
                properties=pika.BasicProperties(delivery_mode=2),
            )
            written += 1
        print(f'  ✓ 仍可写入，成功 confirm {written}/5 条')
        print('    （多数派 = 2，剩 2 个节点仍构成多数派，故可写）')
    except NackError as e:
        print(f'  ✗ 写入被 NACK：{e}')
        print('    这说明已失去多数派 —— 停 1 个不该出现这种情况，请检查')
    except Exception as e:  # noqa: BLE001
        print(f'  ✗ 写入失败：{type(e).__name__}: {e}')

    # ---- 消费验证 ----
    print()
    print('--- 验证 4：能否完整消费 ---')
    received = []
    cch = new_mgr.get_channel()
    while True:
        m, p, b = cch.basic_get(queue=CHAOS_QUEUE, auto_ack=True)
        if not m:
            break
        received.append(json.loads(b).get('seq'))
    expected = list(range(N_MSGS)) + [f'after-{i}' for i in range(written)]
    missing = [x for x in expected if x not in received]
    if not missing:
        print(f'  ✓ 消费到 {len(received)} 条，与预期完全一致，零丢失')
    else:
        print(f'  ✗ 缺失：{missing}')

    # ---- 恢复 ----
    wait_for_user('请恢复节点：docker start rmq1\n  （等待约 10 秒让副本同步）',
                  auto_cmd='docker start rmq1')

    print('--- 恢复后状态 ---')
    if not AUTO:
        time.sleep(10)
    final_mgr = ConnectionManager()
    for host, port in NODES:
        try:
            c = pika.BlockingConnection(pika.ConnectionParameters(
                host=host, port=port,
                credentials=pika.PlainCredentials('learn', 'learn123'),
                heartbeat=600))
            cch2 = c.channel()
            resp = cch2.queue_declare(queue=CHAOS_QUEUE, durable=True,
                                      passive=True)
            print(f'  {host}:{port} → 可见，深度 {resp.method.message_count}')
            c.close()
        except Exception as e:  # noqa: BLE001
            print(f'  {host}:{port} → 不可用：{type(e).__name__}')

    print()
    print('=' * 74)
    print('演练结论')
    print('=' * 74)
    print()
    print('  quorum 队列通过 Raft 复制，只要存活节点构成多数派：')
    print('    - 已 confirm 的消息不丢（确认前已 fsync 到多数派）')
    print('    - 仍可继续写入')
    print('    - 整个过程客户端只需换一个节点地址，无需业务代码配合')
    print()
    print('  对照（课 11 实测）：classic 队列宿主宕机后报')
    print('  NOT_FOUND - process is stopped by supervisor，完全不可用。')
    print('  这就是决策 2 选 quorum 的原因。')

    mgr.close()
    new_mgr.close()
    final_mgr.close()


if __name__ == '__main__':
    main()
