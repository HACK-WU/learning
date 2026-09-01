#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 12 环境清理：
  1. 停止本课后台实验进程（l12-drt-server.py 等）
  2. 删除课 12 在集群上留下的实验队列（l12.*）
  3. 确认既有 rabbitmq-learn 容器与集群节点不受影响

只清理 l12.* 前缀的队列，绝不动其他队列。
"""
import os
import signal
import subprocess
import sys

BASE = '/mnt/d/projects/learning/rabbitmq'

PASS = []
FAIL = []


def check(name, ok, detail=''):
    (PASS if ok else FAIL).append(name)
    print("  [%s] %s%s" % ("✅" if ok else "❌", name,
                           ("  —— " + detail) if detail else ""))


def list_queues():
    r = subprocess.run(
        ['docker', 'exec', 'rmq1', 'rabbitmqctl', 'list_queues',
         'name', '--quiet'], capture_output=True, text=True, timeout=90)
    return [ln.split('\t')[0].strip()
            for ln in (r.stdout or '').splitlines()[1:] if ln.strip()]


def main():
    print("=" * 72)
    print("课 12 环境清理")
    print("=" * 72)

    # ---------- 1. 停后台进程 ----------
    print("\n[1] 停止本课后台实验进程")
    r = subprocess.run(['ps', '-eo', 'pid,args'],
                       capture_output=True, text=True, timeout=30)
    killed = []
    for ln in (r.stdout or '').splitlines():
        if 'l12-drt-server.py' in ln and 'ps -eo' not in ln:
            pid = int(ln.split()[0])
            if pid == os.getpid():
                continue
            try:
                os.kill(pid, signal.SIGTERM)
                killed.append(str(pid))
            except Exception as e:
                print("      kill %s 失败：%s" % (pid, e))
    check("1 已停止后台进程", True,
          "已发 SIGTERM 给 PID %s" % ", ".join(killed) if killed else "无运行中的进程")

    # ---------- 2. 删除实验队列 ----------
    print("\n[2] 清理课 12 实验队列（仅限 l12.* 前缀）")
    qs = list_queues()
    targets = [q for q in qs if q.startswith('l12.')]
    if not targets:
        check("2 无 l12.* 队列需清理", True, "已干净")
    else:
        for q in targets:
            subprocess.run(
                ['docker', 'exec', 'rmq1', 'rabbitmqctl', 'delete_queue', q],
                capture_output=True, text=True, timeout=60)
        left = [q for q in list_queues() if q.startswith('l12.')]
        check("2 已删除 %d 个 l12.* 队列" % len(targets), not left,
              "已删：%s" % ", ".join(targets) if not left
              else "仍有残留：%s" % ", ".join(left))

    # ---------- 3. 确认环境完好 ----------
    print("\n[3] 环境完好性")
    r = subprocess.run(['docker', 'ps', '--format', '{{.Names}}\t{{.Status}}'],
                       capture_output=True, text=True, timeout=60)
    running = dict(ln.split('\t', 1) for ln in (r.stdout or '').strip().splitlines()
                   if '\t' in ln)
    for ct in ['rmq1', 'rmq2', 'rmq3', 'rabbitmq-learn']:
        check("3 容器 %s 仍在运行" % ct,
              ct in running and running[ct].startswith('Up'),
              running.get(ct, '未找到'))

    r = subprocess.run(
        ['docker', 'exec', 'rmq1', 'rabbitmqctl', 'list_queues',
         'name', '--quiet'], capture_output=True, text=True, timeout=90)
    remain = [ln.split('\t')[0] for ln in (r.stdout or '').splitlines()[1:]
              if ln.strip()]
    print("     集群剩余队列：%s" % (", ".join(remain) if remain else "无"))

    print("\n" + "=" * 72)
    print("通过 %d / 失败 %d" % (len(PASS), len(FAIL)))
    for f in FAIL:
        print("  ❌ %s" % f)
    print("=" * 72)
    return 1 if FAIL else 0


if __name__ == '__main__':
    sys.exit(main())
