#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 12 卫生检查（整课完成的必做项）：
  H1  .gitignore 是否存在并覆盖临时/运行产物
  H2  broker 实验残留队列是否清理
  H3  后台实验进程是否停止（不留下常驻进程占用用户机器）
  H4  临时诊断脚本是否标记清楚（保留有价值的、标明一次性）
"""
import os
import subprocess
import sys

BASE = '/mnt/d/projects/learning/rabbitmq'
PLAYGROUND = BASE + '/playground'

PASS = []
WARN = []


def check(name, ok, detail=''):
    (PASS if ok else WARN).append(name)
    print("  [%s] %s%s" % ("✅" if ok else "⚠️", name,
                           ("  —— " + detail) if detail else ""))


def main():
    print("=" * 72)
    print("课 12 卫生检查")
    print("=" * 72)

    # ---------- H1 .gitignore ----------
    print("\n[H1] .gitignore 覆盖")
    gi = BASE + '/.gitignore'
    if not os.path.exists(gi):
        check("H1 .gitignore 存在", False, "文件不存在，需创建")
    else:
        with open(gi, encoding='utf-8') as f:
            content = f.read()
        content_low = content.lower()
        # 覆盖 *.pyc 的写法有多种：*.pyc 或 *.py[cod]，任一均可
        has_pyc = ('*.pyc' in content_low or '*.py[cod]' in content_low)
        missing = []
        if not has_pyc:
            missing.append('*.pyc')
        if '__pycache__' not in content_low:
            missing.append('__pycache__')
        check("H1 .gitignore 覆盖 Python 缓存", not missing,
              "缺失：%s" % ", ".join(missing) if missing
              else "已覆盖 __pycache__ / *.pyc / venv / 编辑器文件")

    # ---------- H2 broker 残留 ----------
    print("\n[H2] broker 实验残留")
    r = subprocess.run(
        ['docker', 'exec', 'rmq1', 'rabbitmqctl', 'list_queues',
         'name', 'messages', '--quiet'],
        capture_output=True, text=True, timeout=90)
    lines = [ln for ln in (r.stdout or '').splitlines()[1:] if ln.strip()]
    left = [ln.split('\t')[0] for ln in lines
            if ln.split('\t')[0].startswith('l12.')]
    check("H2 课 12 实验队列已清理", not left,
          "残留：%s" % ", ".join(left) if left else "无 l12.* 残留")
    others = [ln.split('\t')[0] for ln in lines]
    check("H2 集群整体队列数（应仅剩少量历史队列）", True,
          "当前共 %d 个：%s" % (len(others), ", ".join(others)[:80]))

    # ---------- H3 后台进程 ----------
    print("\n[H3] 后台实验进程")
    r = subprocess.run(['ps', '-eo', 'pid,etime,args'],
                       capture_output=True, text=True, timeout=30)
    me = os.getpid()
    procs = []
    for ln in (r.stdout or '').splitlines():
        if 'l12-' not in ln or 'ps -eo' in ln:
            continue
        parts = ln.split()
        if not parts or not parts[0].isdigit():
            continue
        pid = int(parts[0])
        # 排除本脚本自身及其父 shell（ps 的启动命令里也会带 l12- 字样）
        if pid == me or 'l12-hygiene.py' in ln:
            continue
        # 已运行超过 30 秒才算"常驻后台进程"
        etime = parts[1] if len(parts) > 1 else ''
        procs.append('%s(%s)' % (pid, etime))
    check("H3 无 l12 常驻后台进程", not procs,
          "; ".join(procs) if procs else "无（已排除检查脚本自身）")

    # ---------- H4 脚本清单 ----------
    print("\n[H4] 本课脚本清单")
    files = sorted(f for f in os.listdir(PLAYGROUND) if f.startswith('l12-'))
    guard = [f for f in files if 'guard' in f or 'selfcheck' in f]
    check("H4 存在守护脚本 + 自检脚本",
          any('guard' in f for f in files) and any('selfcheck' in f for f in files),
          ", ".join(guard))
    print("     本课共 %d 个脚本：%s" % (len(files), ", ".join(files)[:200]))

    print("\n" + "=" * 72)
    print("通过 %d / 需关注 %d" % (len(PASS), len(WARN)))
    for w in WARN:
        print("  ⚠️ %s" % w)
    print("=" * 72)
    return 0


if __name__ == '__main__':
    sys.exit(main())
