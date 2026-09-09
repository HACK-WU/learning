#!/usr/bin/env python3
# 检测循环体内的子进程调用（fork）次数
#
# 判定口径（此前误判的根因是口径不清）：
#   - $(( )) 算术展开：不产生子进程，不计入
#   - while read 循环体里的 $( )：真实 fork，计入
#   - 但"每次迭代 fork 一次"只对大 N 才是问题；本项目的 while read
#     处理的是 blob 清单，量级与文件数相当，属可接受用法
# 因此本脚本只统计"明确可避免"的高频 fork，并输出明细供人工判断。
import sys, re, os, io

base = sys.argv[1] if len(sys.argv) > 1 else "."
files = [os.path.join(base, "wf-lab")] + [
    os.path.join(base, "lib", f)
    for f in ("core.sh", "repo.sh", "hooks.sh", "audit.sh", "rescue.sh", "drill.sh")
]

hits = []
for p in files:
    if not os.path.exists(p):
        continue
    lines = io.open(p, encoding="utf-8").read().split("\n")
    depth = 0
    for i, ln in enumerate(lines, 1):
        st = ln.strip()
        if re.search(r"\b(?:while|for|until)\b.*(?:\bdo\s*$|;\s*do\b)", ln):
            depth += 1
            continue
        if depth > 0:
            if st == "done":
                depth -= 1
                continue
            body = re.sub(r"\$\(\(.*?\)\)", "", ln)
            if re.search(r"\$\(|`", body):
                hits.append((os.path.basename(p), i, st[:60]))

# 只把"可通过重写避免"的计入门槛：循环内调用自定义函数或 cat-file 之类
avoidable = 0
for fn, ln, txt in hits:
    if re.search(r"cat-file|\bwc -l\b|\bmktemp\b", txt):
        avoidable += 1

if os.environ.get("WF_GATE_VERBOSE"):
    for fn, ln, txt in hits:
        print(f"  {fn}:{ln}  {txt}", file=sys.stderr)

print(avoidable)
