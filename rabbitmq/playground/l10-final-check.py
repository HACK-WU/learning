#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""课 10 交付终检：环境恢复确认 + 残留扫描 + 课 8 守护脚本回归。"""
import subprocess
import sys

BASE = '/mnt/d/projects/learning/rabbitmq'


def sh(cmd, timeout=90):
    r = subprocess.run(cmd, shell=True, capture_output=True,
                       text=True, timeout=timeout)
    return r.stdout


def main():
    print("=" * 70)
    print("课 10 交付终检")
    print("=" * 70)

    # 1. broker 告警状态
    print("\n【1】broker 告警状态（应为空）")
    out = sh('docker exec rabbitmq-learn rabbitmqctl status 2>&1')
    alarms = []
    started = False
    for ln in out.splitlines():
        if 'Alarms' in ln:
            started = True
            continue
        if started:
            s = ln.strip()
            if not s:
                continue
            alarms.append(s)
            if 'none' in s.lower() or s.startswith('Total'):
                break
    print("  %s" % (alarms[:3] if alarms else "（未读到）"))

    # 2. 水位恢复
    print("\n【2】内存水位（应为 0.6）")
    for ln in out.splitlines():
        if 'watermark setting' in ln.lower():
            print("  %s" % ln.strip())

    # 3. 队列残留
    print("\n【3】broker 队列（应只剩 hello 与 l8.guard.*）")
    out = sh('docker exec rabbitmq-learn rabbitmqctl list_queues name messages 2>&1')
    lines = [l for l in out.splitlines()[2:] if l.strip()]
    stray = [l for l in lines if 'l10' in l]
    print("  队列总数：%d" % len(lines))
    print("  l10 残留：%s" % (stray if stray else "无 ✅"))

    # 4. 运行时残留
    print("\n【4】文件系统残留")
    out = sh('find %s -name "__pycache__" -o -name "*.pyc" 2>/dev/null' % BASE)
    pyc = [l for l in out.splitlines() if l.strip()]
    print("  __pycache__/*.pyc：%s" % ("无 ✅" if not pyc else "%d 项" % len(pyc)))

    # 5. 课 8 守护脚本回归
    print("\n【5】课 8 守护脚本回归（确认本课实验未破坏既有结论）")
    out = sh('cd %s/playground && python3 l8-guard-facts.py 2>&1' % BASE)
    tail = [l for l in out.splitlines() if l.strip()][-3:]
    for l in tail:
        print("  %s" % l)

    print("\n" + "=" * 70)
    print("终检完成")
    print("=" * 70)
    return 0


if __name__ == '__main__':
    sys.exit(main())
