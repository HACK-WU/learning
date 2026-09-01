#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 11 实验 6：4.3 的元数据存储与旧分区策略的消失
====================================================
知识点 3「故障与网络分区」的版本校验。

4.x 有两个影响深远的移除：
  1. 镜像队列（classic mirrored queues）——4.0 移除
  2. Mnesia 元数据存储与旧分区处理策略——4.3 起 Khepri 为默认/唯一

本实验实测（不轻信文档说法）：
  A. 元数据后端是否为 Khepri
  B. 旧的分区策略配置项（cluster_partition_handling）是否还存在
  C. ha-* 策略（镜像队列）是否还被接受
  D. 节点类型：ram 节点是否已移除
"""
import subprocess
import sys

NODES = ['rmq1', 'rmq2', 'rmq3']


def ctl(node, *args, timeout=60):
    r = subprocess.run(['docker', 'exec', node, 'rabbitmqctl'] + list(args),
                       capture_output=True, text=True, timeout=timeout)
    return (r.stdout or '') + (r.stderr or '')


def main():
    print("=" * 74)
    print("课 11 实验 6：4.3 元数据后端与旧特性的消失")
    print("=" * 74)
    print("集群：rmq1 / rmq2 / rmq3（4.3.5）")

    # A. 元数据后端
    print("\n【A】元数据存储后端")
    out = ctl('rmq1', 'status')
    for ln in out.splitlines():
        low = ln.lower()
        if 'khepri' in low or 'mnesia' in low or 'metadata' in low:
            print("  %s" % ln.strip()[:100])

    out = ctl('rmq1', 'environment')
    for ln in out.splitlines():
        if 'khepri' in ln.lower() or 'metadata_store' in ln.lower():
            print("  %s" % ln.strip()[:120])

    # B. 分区策略配置项
    print("\n【B】旧分区处理策略 cluster_partition_handling")
    out = ctl('rmq1', 'environment')
    hit = False
    for ln in out.splitlines():
        if 'partition' in ln.lower():
            print("  ⚠️ 仍存在：%s" % ln.strip()[:100])
            hit = True
    if not hit:
        print("  ✅ environment 中【不存在】cluster_partition_handling 配置")
        print("     （旧策略 pause_minority / autoheal / ignore 已随 Mnesia 移除）")

    # C. ha-* 策略（镜像队列）
    print("\n【C】镜像队列策略 ha-all 是否还被接受")
    out = ctl('rmq1', 'set_policy', 'l11-ha-test', '^test$',
              '{"ha-mode":"all"}', '--apply-to', 'queues')
    print("  命令返回：%s" % out.strip()[:160])
    if 'error' in out.lower() or 'invalid' in out.lower():
        print("  ✅ 被拒绝 → 镜像队列相关策略在 4.3 已不可用")
    else:
        print("  ⚠️ 被接受（需进一步验证是否真的生效）")
        ctl('rmq1', 'clear_policy', 'l11-ha-test')

    # D. 节点类型
    print("\n【D】节点类型：ram 节点是否仍可用")
    out = ctl('rmq1', 'help')
    ram_cmds = [ln.strip() for ln in out.splitlines()
                if 'ram' in ln.lower() and 'change_cluster_node_type' in ln.lower()]
    if ram_cmds:
        for c in ram_cmds[:3]:
            print("  ⚠️ %s" % c[:140])
    else:
        print("  ✅ rabbitmqctl help 中【无】change_cluster_node_type")
        print("     （4.3 起 ram 节点类型已移除，所有节点都是 disc 节点）")

    # 补充：cluster_status 中的节点分类
    print("\n【E】cluster_status 中的节点分类")
    out = ctl('rmq1', 'cluster_status')
    show = False
    for ln in out.splitlines():
        if 'Disk Nodes' in ln or 'RAM Nodes' in ln:
            show = True
            print("  %s" % ln.strip())
            continue
        if show:
            if ln.strip() == '':
                continue
            if ln.strip().startswith(('Running', 'Versions', 'CPU')):
                break
            print("  %s" % ln.strip())
            if 'rabbit@' not in ln:
                show = False

    print("\n" + "=" * 74)
    print("结论")
    print("=" * 74)
    print("4.3 的故障语义统一为 Raft：")
    print("  - 元数据存储 Khepri（Raft 协议）")
    print("  - 旧的 pause_minority / autoheal / ignore 策略已移除")
    print("  - 镜像队列（ha-* 策略）已在 4.0 移除")
    print("  - ram 节点类型已移除，节点一律为 disc")
    print("  → 分区恢复不再需要管理员选策略，按多数派语义统一处理")
    return 0


if __name__ == '__main__':
    sys.exit(main())
