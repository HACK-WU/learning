#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""诊断集群容器访问宿主服务的网络路径，确定 Shovel 应使用的地址。"""
import subprocess


def sh(cmd, timeout=60):
    r = subprocess.run(['docker', 'exec', 'rmq1', 'bash', '-c', cmd],
                       capture_output=True, text=True, timeout=timeout)
    return (r.stdout or '') + (r.stderr or '')


def main():
    print("=" * 70)
    print("网络诊断：集群容器 rmq1 如何访问宿主上的 5672")
    print("=" * 70)

    print("\n[1] host.docker.internal 是否可解析")
    print("  %s" % sh('getent hosts host.docker.internal || echo "无法解析"').strip())

    print("\n[2] 默认网关")
    print("  %s" % sh("ip route | grep default || echo '无默认路由'").strip())

    print("\n[3] 候选地址连通性测试（TCP 5672）")
    cands = ['172.18.0.1', '172.17.0.1', 'host.docker.internal']
    for c in cands:
        r = sh("timeout 3 python3 -c \"import socket;"
               "s=socket.socket();s.settimeout(2);"
               "print(s.connect_ex(('%s',5672)))\" 2>&1 || echo err" % c)
        v = r.strip().splitlines()[-1] if r.strip() else 'err'
        print("  %-24s connect_ex=%s  %s" % (
            c, v, "✅ 可达" if v == '0' else "❌ 不可达"))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
