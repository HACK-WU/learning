#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""等待上游容器就绪，并验证 cookie 差异与集群独立性。"""
import subprocess
import sys
import time


def docker_exec(name, *args, timeout=90):
    r = subprocess.run(['docker', 'exec', name] + list(args),
                       capture_output=True, text=True, timeout=timeout)
    return (r.stdout or '') + (r.stderr or '')


def main():
    print("=" * 70)
    print("等待上游站点 rmq-upstream 就绪")
    print("=" * 70)

    ready = False
    for i in range(30):
        r = docker_exec('rmq-upstream', 'rabbitmqctl', 'await_startup',
                        '--timeout', '5')
        if 'error' not in r.lower() or r.strip() == '':
            print("  就绪（第 %d 秒）" % (i * 3))
            ready = True
            break
        time.sleep(3)
    if not ready:
        print("  ⚠️ 超时未就绪，后续步骤可能失败")

    print("\n[cookie 对比]")
    c1 = docker_exec('rmq1', 'cat', '/var/lib/rabbitmq/.erlang.cookie').strip()
    c2 = docker_exec('rmq-upstream', 'cat',
                     '/var/lib/rabbitmq/.erlang.cookie').strip()
    print("  集群 rmq1      : %s..." % c1[:12])
    print("  上游 upstream  : %s..." % c2[:12])
    print("  是否相同      : %s" % ("相同" if c1 == c2 else "不同 ✅（无法组集群）"))

    print("\n[上游集群状态]（应只有自己）")
    out = docker_exec('rmq-upstream', 'rabbitmqctl', 'cluster_status')
    show = False
    for ln in out.splitlines():
        if 'Running Nodes' in ln:
            show = True
            continue
        if show:
            if ln.strip() == '':
                continue
            if 'Versions' in ln:
                break
            print("  %s" % ln.strip())

    print("\n[网络连通性] 从 rmq1 访问 rmq-upstream:5672")
    r = docker_exec('rmq1', 'bash', '-c',
                    'exec 3<>/dev/tcp/rmq-upstream/5672 && echo OK || echo FAIL')
    print("  %s" % ("✅ 可达" if 'OK' in r else "❌ 不可达 (%s)" % r.strip()[:60]))
    return 0


if __name__ == '__main__':
    sys.exit(main())
