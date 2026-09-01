#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""课 11 交付终检：环境回归 + 档案完整性 + 既有结论守护。"""
import os
import re
import subprocess

BASE = '/mnt/d/projects/learning/rabbitmq'
ARCHIVE = os.path.join(BASE, '00-学习档案.md')
LESSON = os.path.join(
    BASE, 'stages', '4-进阶与工程落地', 'lessons',
    'lesson-11-集群与高可用.md')


def sh(cmd, timeout=180):
    r = subprocess.run(cmd, shell=True, capture_output=True,
                       text=True, timeout=timeout)
    return r.stdout or ''


def main():
    print("=" * 70)
    print("课 11 交付终检")
    print("=" * 70)

    # 1. 集群健康
    print("\n【1】集群健康")
    out = sh('docker exec rmq1 rabbitmqctl cluster_status 2>&1')
    if 'rabbit@rmq2' in out and 'rabbit@rmq3' in out:
        print("  三节点集群正常 ✅")
    else:
        print("  ⚠️ 集群状态异常")

    # 2. 既有环境
    print("\n【2】既有环境 rabbitmq-learn")
    print("  %s" % sh(
        "docker ps --filter name=rabbitmq-learn "
        "--format '{{.Names}} {{.Status}}'").strip())

    # 3. 残留
    print("\n【3】集群内残留")
    q = sh('docker exec rmq1 rabbitmqctl list_queues name 2>&1')
    ql = [l.strip() for l in q.splitlines()[2:] if l.strip()]
    print("  队列数：%d %s" % (len(ql), ql if ql else "✅"))
    pol = sh('docker exec rmq1 rabbitmqctl list_policies 2>&1')
    print("  policy：%s" % ("无 ✅" if 'l11' not in pol else "⚠️ 有残留"))
    par = sh('docker exec rmq1 rabbitmqctl list_parameters 2>&1')
    print("  parameter：%s" % ("无 ✅" if 'l11' not in par else "⚠️ 有残留"))

    # 4. 既有环境结论守护（课 8）
    print("\n【4】课 8 守护脚本回归（确认本课未破坏既有结论）")
    out = sh('cd %s/playground && python3 l8-guard-facts.py 2>&1' % BASE)
    tail = [l for l in out.splitlines() if l.strip()][-3:]
    for l in tail:
        print("  %s" % l)

    # 5. 档案完整性
    print("\n【5】学习档案完整性")
    with open(ARCHIVE, encoding='utf-8') as f:
        text = f.read()
    checks = [
        ('课 10 评审记录', '| 2026-09-01 | 阶段 4·课 10《高级特性》 | 主 agent 内联'),
        ('课 11 评审记录', '| 2026-09-01 | 阶段 4·课 11《集群与高可用》 | 主 agent 内联'),
        ('课 11 进度-集群基础', '| 4 | 课 11 | 集群基础 | ✅ 已完成'),
        ('课 11 进度-复制型队列', '| 4 | 课 11 | 复制型队列 | ✅ 已完成'),
        ('课 11 进度-故障与分区', '| 4 | 课 11 | 故障与网络分区 | ✅ 已完成'),
        ('课 11 大纲记录', '课 11《集群与高可用》三个知识点全部完成'),
        ('课 11 事实核查', 'leader 故障切换：0.07s 完成选举'),
    ]
    for name, pat in checks:
        print("  %-22s %s" % (name, "✅" if pat in text else "❌ 缺失"))

    # 6. 事实核查条数
    n = len(re.findall(r'\| 2026-09-01 \| \*\*', text))
    print("  2026-09-01 事实核查条目：%d" % n)

    # 7. 讲义
    print("\n【6】讲义")
    with open(LESSON, encoding='utf-8') as f:
        lt = f.read()
    print("  行数：%d" % (lt.count('\n') + 1))
    print("  小测：%d 题" % len(re.findall(r'### Q\d+', lt)))
    print("  占位符：%s" % ("无 ✅" if '待 Phase' not in lt and '⏳' not in lt else "⚠️"))

    # 8. 课程目录
    print("\n【7】课程目录")
    with open(os.path.join(BASE, '02-课程目录.md'), encoding='utf-8') as f:
        ct = f.read()
    print("  课 11 链接：%s" % ("✅ 已链接" if
                              'lesson-11-集群与高可用.md)' in ct else "❌ 未链接"))

    print("\n" + "=" * 70)
    print("终检完成")
    print("=" * 70)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
