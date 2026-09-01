#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""清理 RPC 实验残留队列与后台进程。"""
import subprocess
import time


def sh(cmd, timeout=90):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    return r.stdout or ''


def main():
    print("=" * 66)
    print("清理课 12 RPC 实验残留")
    print("=" * 66)

    # 1. 停掉后台服务端进程
    print("\n[1] 停止 RPC 服务端进程")
    r = subprocess.run(['pkill', '-f', 'l12-rpc-server.py'],
                       capture_output=True, text=True)
    print("  pkill 返回码：%s" % r.returncode)
    time.sleep(2)

    # 2. 列出所有队列
    out = sh(['docker', 'exec', 'rmq1', 'rabbitmqctl',
              'list_queues', 'name', '--quiet'])
    qs = [l.strip() for l in out.splitlines()[1:] if l.strip()]
    print("\n[2] 当前队列（%d 个）" % len(qs))
    for q in qs:
        print("  - %s" % q)

    # 3. 删除 l12 残留
    print("\n[3] 删除 l12.* 残留队列")
    for q in qs:
        if q.startswith('l12'):
            sh(['docker', 'exec', 'rmq1', 'rabbitmqctl', 'delete_queue', q])
            print("  已删除 %s" % q)

    time.sleep(2)
    out = sh(['docker', 'exec', 'rmq1', 'rabbitmqctl',
              'list_queues', 'name', '--quiet'])
    left = [l.strip() for l in out.splitlines()[1:] if l.strip()]
    print("\n[4] 清理后剩余队列：%d 个 %s" % (len(left), left if left else "✅"))

    # 4. 确认既有环境完好
    print("\n[5] 既有环境")
    print("  %s" % sh(['docker', 'ps', '--filter', 'name=rabbitmq-learn',
                       '--format', '{{.Names}} {{.Status}}']).strip())
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
