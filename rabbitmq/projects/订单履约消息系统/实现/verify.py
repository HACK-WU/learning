# -*- coding: utf-8 -*-
"""验收自检：逐项检查本项目是否真的满足了各项约束。

运行：
    python3 verify.py

设计原则：
  **只检查能被客观验证的项**。像"代码是否优雅"这种主观判断不进清单。
  每项输出 PASS / FAIL / SKIP（SKIP = 需要人工操作的项）。

验收项对应 README 里的"项目要求"，也对应设计决策里的 5 个权衡点。
"""
import json
import logging
import os
import sys
import time

import pika

from config import (
    NODES, EX_ORDER, EX_NOTIFY, EX_DLX,
    Q_STOCK, Q_FULFILL_VIP, Q_FULFILL_NORMAL, Q_SMS, Q_DLQ, Q_SMS_DLQ,
    PREFETCH_MAIN, PREFETCH_SMS, DELIVERY_LIMIT,
)
from connection import ConnectionManager, setup_logging

logger = logging.getLogger(__name__)

results = []


def check(name, func):
    """执行一项检查并记录结果。"""
    try:
        ok, detail = func()
    except Exception as e:  # noqa: BLE001
        ok, detail = False, f'{type(e).__name__}: {e}'
    results.append((name, ok, detail))
    icon = '✓ PASS' if ok else '✗ FAIL'
    print(f'  [{icon}] {name}')
    print(f'         {detail}')
    return ok


def main():
    setup_logging(logging.WARNING)  # 静音 pika 的连接日志
    print('=' * 74)
    print('订单履约消息系统 · 验收自检')
    print('=' * 74)
    print()
    print(f'环境：RabbitMQ 4.3.5 三节点 / pika {pika.__version__}')
    print()

    mgr = ConnectionManager()

    # ================= 阶段 1：拓扑 =================
    print('【拓扑完整性】')

    def _queues_exist():
        ch = mgr.get_channel()
        missing = []
        for q in (Q_STOCK, Q_FULFILL_VIP, Q_FULFILL_NORMAL, Q_SMS,
                  Q_DLQ, Q_SMS_DLQ):
            try:
                ch.queue_declare(queue=q, durable=True, passive=True)
            except Exception:  # noqa: BLE001
                missing.append(q)
        return (not missing,
                f'6 个队列均存在' if not missing else f'缺失：{missing}')

    check('全部队列已声明', _queues_exist)

    def _exchanges_exist():
        ch = mgr.get_channel()
        missing = []
        for ex in (EX_ORDER, EX_NOTIFY, EX_DLX):
            try:
                ch.exchange_declare(exchange=ex, exchange_type='topic',
                                    durable=True, passive=True)
            except Exception:  # noqa: BLE001
                missing.append(ex)
        return (not missing,
                '3 个交换机均存在' if not missing else f'缺失：{missing}')

    check('全部交换机已声明', _exchanges_exist)

    # ================= 阶段 2：可靠性配置 =================
    print()
    print('【非功能约束 1：可靠性】')

    def _queue_types():
        """用 rabbitmqctl 读队列类型，确认主链路是 quorum。"""
        import subprocess
        r = subprocess.run(
            ['docker', 'exec', 'rmq1', 'rabbitmqctl', 'list_queues',
             'name', 'type'],
            capture_output=True, text=True)
        out = r.stdout
        want_quorum = [Q_STOCK, Q_FULFILL_VIP, Q_FULFILL_NORMAL]
        bad = []
        for q in want_quorum:
            for line in out.splitlines():
                if line.startswith(q + '\t'):
                    if 'quorum' not in line:
                        bad.append(f'{q} 不是 quorum')
        for q in (Q_SMS,):
            for line in out.splitlines():
                if line.startswith(q + '\t'):
                    if 'classic' not in line:
                        bad.append(f'{q} 不是 classic')
        return (not bad,
                '主链路 quorum / 短信 classic，符合决策 2'
                if not bad else '; '.join(bad))

    check('队列类型符合决策 2', _queue_types)

    def _durable():
        """三层持久化：队列必须 durable。"""
        import subprocess
        r = subprocess.run(
            ['docker', 'exec', 'rmq1', 'rabbitmqctl', 'list_queues',
             'name', 'durable'],
            capture_output=True, text=True)
        bad = []
        for q in (Q_STOCK, Q_FULFILL_VIP, Q_FULFILL_NORMAL, Q_SMS, Q_DLQ):
            found = False
            for line in r.stdout.splitlines():
                if line.startswith(q + '\t'):
                    found = True
                    if 'true' not in line.lower():
                        bad.append(f'{q} 非 durable')
            if not found:
                bad.append(f'{q} 未找到')
        return (not bad, '所有队列 durable=true（课 7 三层持久化第二层）'
                if not bad else '; '.join(bad))

    check('队列持久化已开启', _durable)

    def _dlx_configured():
        """主链路队列必须配了死信交换机。"""
        import subprocess
        r = subprocess.run(
            ['docker', 'exec', 'rmq1', 'rabbitmqctl', 'list_queues',
             'name', 'arguments'],
            capture_output=True, text=True)
        bad = []
        for q in (Q_STOCK, Q_FULFILL_VIP, Q_FULFILL_NORMAL):
            line_ok = False
            for line in r.stdout.splitlines():
                if line.startswith(q + '\t'):
                    if 'dead-letter-exchange' in line:
                        line_ok = True
            if not line_ok:
                bad.append(f'{q} 未配 DLX')
        return (not bad, '主链路 3 个队列均配 DLX（课 7 死信兜底）'
                if not bad else '; '.join(bad))

    check('死信交换机已配置', _dlx_configured)

    def _delivery_limit():
        """quorum 队列必须配了 delivery-limit，否则失败会无限重试。"""
        import subprocess
        r = subprocess.run(
            ['docker', 'exec', 'rmq1', 'rabbitmqctl', 'list_queues',
             'name', 'arguments'],
            capture_output=True, text=True)
        bad = []
        for q in (Q_STOCK, Q_FULFILL_VIP, Q_FULFILL_NORMAL):
            ok = False
            for line in r.stdout.splitlines():
                if line.startswith(q + '\t') and 'delivery-limit' in line:
                    ok = True
            if not ok:
                bad.append(f'{q} 未配 delivery-limit')
        return (not bad,
                f'均配 delivery-limit（={DELIVERY_LIMIT}），配合 reject 才有效'
                if not bad else '; '.join(bad))

    check('交付上限已配置', _delivery_limit)

    # ================= 阶段 3：正确性 =================
    print()
    print('【非功能约束 2：正确性（幂等）】')

    def _idempotency_module():
        """幂等模块行为正确：重复投递只执行一次。"""
        from idempotency import IdempotencyStore
        store = IdempotencyStore()
        key = 'VERIFY-001:test'
        executed = 0
        for _ in range(3):
            if store.acquire(key):
                executed += 1
                store.mark_done(key)
        return (executed == 1,
                f'投递 3 次，业务执行 {executed} 次（期望 1）')

    check('幂等去重表生效', _idempotency_module)

    def _idempotency_release():
        """失败后必须释放，否则消息再也重试不了（等于丢失）。"""
        from idempotency import IdempotencyStore
        store = IdempotencyStore()
        key = 'VERIFY-002:test'
        store.acquire(key)
        store.release(key)   # 模拟业务失败
        can_retry = store.acquire(key)
        return (can_retry,
                '失败后释放 → 可重新抢占（否则失败一次就永久丢失）'
                if can_retry else '失败后无法重试 ✗')

    check('失败后幂等锁可释放', _idempotency_release)

    # ================= 阶段 4：重试语义 =================
    print()
    print('【工程约束 1：错误处理无静默失败】')

    def _retry_uses_reject():
        """代码里失败路径必须用 reject（不能用 nack）。"""
        import inspect
        from consumer import BaseConsumer
        src = inspect.getsource(BaseConsumer._on_message)
        uses_reject = 'basic_reject' in src
        uses_nack_for_retry = 'basic_nack' in src
        # nack 只应出现在注释里
        nack_in_comment = all(
            '#' in line or 'nack' not in line
            for line in src.splitlines()
            if 'basic_nack' in line
        )
        ok = uses_reject and (not uses_nack_for_retry or nack_in_comment)
        return (ok,
                '失败路径使用 basic_reject（决策 3：nack 不推进 delivery-count）'
                if ok else '失败路径用了 basic_nack ✗ 会导致无限重试')

    check('失败用 reject 而非 nack', _retry_uses_reject)

    def _classic_app_retry():
        """classic 队列必须有应用层重试（它不支持 broker 级退避）。"""
        import inspect
        from services import SmsConsumer
        src = inspect.getsource(SmsConsumer)
        ok = 'broker_managed_retry=False' in src
        return (ok,
                '短信（classic）已启用应用层重试计数'
                if ok else 'classic 队列未启用应用层重试 ✗ 会无限重投')

    check('classic 应用层重试已启用', _classic_app_retry)

    def _dead_letter_reachable():
        """死信队列存在且可被消费（兜底路径通畅）。"""
        ch = mgr.get_channel()
        try:
            resp = ch.queue_declare(queue=Q_DLQ, durable=True, passive=True)
            return True, f'死信队列 {Q_DLQ} 可访问，当前 {resp.method.message_count} 条'
        except Exception as e:  # noqa: BLE001
            return False, str(e)

    check('死信队列可访问', _dead_letter_reachable)

    # ================= 阶段 5：工程规模 =================
    print()
    print('【工程约束 2：可维护性（多文件模块划分）】')

    def _module_split():
        here = os.path.dirname(os.path.abspath(__file__))
        files = ['config.py', 'connection.py', 'topology.py',
                 'idempotency.py', 'producer.py', 'consumer.py',
                 'services.py']
        missing = [f for f in files if not os.path.exists(os.path.join(here, f))]
        total = len([f for f in os.listdir(here) if f.endswith('.py')])
        return (not missing,
                f'{total} 个 Python 模块，7 个核心模块齐全'
                if not missing else f'缺失：{missing}')

    check('多文件模块划分', _module_split)

    def _topology_separated():
        """拓扑声明应独立于业务代码。"""
        import inspect
        from topology import declare_topology
        from services import FulfillConsumer
        topo_src = inspect.getsource(declare_topology)
        biz_src = inspect.getsource(FulfillConsumer)
        ok = 'queue_declare' in topo_src and 'queue_declare' not in biz_src
        return (ok,
                '拓扑声明集中在 topology.py，业务代码不含队列声明'
                if ok else '业务代码混入了拓扑声明')

    check('拓扑与业务分离', _topology_separated)

    # ================= 阶段 6：集群可用性 =================
    print()
    print('【非功能约束 3：可用性】')

    def _all_nodes_reachable():
        ok_nodes = []
        for host, port in NODES:
            try:
                c = pika.BlockingConnection(pika.ConnectionParameters(
                    host=host, port=port,
                    credentials=pika.PlainCredentials('learn', 'learn123'),
                    heartbeat=600))
                ok_nodes.append(port)
                c.close()
            except Exception:  # noqa: BLE001
                pass
        return (len(ok_nodes) == 3,
                f'{len(ok_nodes)}/3 个节点可达：{ok_nodes}')

    check('三节点全部可达', _all_nodes_reachable)

    def _quorum_has_members():
        """quorum 队列应有 3 个副本。"""
        import subprocess
        r = subprocess.run(
            ['docker', 'exec', 'rmq1', 'rabbitmqctl', 'list_queues',
             'name', 'type'],
            capture_output=True, text=True)
        # 通过 HTTP API 查 members 更可靠
        import urllib.request
        import base64
        try:
            req = urllib.request.Request(
                f'http://localhost:15681/api/queues/%2F/{Q_FULFILL_VIP}')
            cred = base64.b64encode(b'learn:learn123').decode()
            req.add_header('Authorization', f'Basic {cred}')
            with urllib.request.urlopen(req, timeout=5) as resp:
                data = json.loads(resp.read())
            members = data.get('members') or []
            return (len(members) >= 3,
                    f'{Q_FULFILL_VIP} 副本数 {len(members)}（leader={data.get("leader")}）')
        except Exception as e:  # noqa: BLE001
            return False, f'查询失败：{type(e).__name__}: {e}'

    check('quorum 队列有 3 副本', _quorum_has_members)

    # ================= 汇总 =================
    print()
    print('=' * 74)
    print('验收汇总')
    print('=' * 74)
    print()
    passed = sum(1 for _, ok, _ in results if ok)
    total = len(results)
    print(f'  通过 {passed}/{total} 项')
    print()
    if passed < total:
        print('  未通过项：')
        for name, ok, detail in results:
            if not ok:
                print(f'    ✗ {name}：{detail}')
        print()
        print('  提示：多数未通过项可通过先跑 run_demo.py 建立拓扑来解决。')

    print()
    print('  需要人工验证的项（脚本无法自动判定）：')
    print('    □ 故障演练：docker stop rmq1 后消息仍不丢（跑 run_chaos.py）')
    print('    □ 重试退避：失败消息按 1s→2s→4s 递增（跑 run_retry_drill_b.py）')
    print('    □ 死信兜底：重试耗尽后进入 order.dlq（同上，看死信输出）')
    print()

    mgr.close()
    return 0 if passed == total else 1


if __name__ == '__main__':
    sys.exit(main())
