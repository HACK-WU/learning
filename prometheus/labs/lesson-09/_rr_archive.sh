#!/usr/bin/env bash
set -e
D=/mnt/d/projects/learning/prometheus
F=$D/00-学习档案.md

python3 - <<'PY'
import io,re
p=r"/mnt/d/projects/learning/prometheus/00-学习档案.md"
s=io.open(p,encoding="utf-8").read()

# 1) 更新课 9 环境状态说明：补充 remote read 补做
old_env="课 9 环境：Thanos v0.42.4 / Mimir 3.2.0 / VM v1.151.0（三方案均实测）"
if old_env in s:
    s=s.replace(old_env, old_env+"；remote read 分模式补做：自写 protobuf 客户端 + rr_bench 1500 序列")

# 2) 追加事实核查行（remote read 模式数量更正）
row = """| 2026-09-07 | 课 9 补做 | remote read 有「三种模式」（含 `STREAMED_CHUNKS`） | **不成立**。v3.14.0 二进制中 `STREAMED_CHUNKS` 出现 0 次；官方 `remote.proto` 的 `ResponseType` 只有 `SAMPLES=0` / `STREAMED_XOR_CHUNKS=1` 两个值；`read-max-bytes-in-frame` 是分帧参数非模式 | 已更正课 7 讲义并加更正说明块 |
"""
# 找事实核查表末尾插入
lines=s.split("\n")
idx=None
for i,l in enumerate(lines):
    if l.strip().startswith("| 2026-09-07") and "课 9" in l:
        idx=i
if idx is None:
    # 找到最后一条 2026-09-07 行
    for i,l in enumerate(lines):
        if l.strip().startswith("| 2026-09-07"):
            idx=i
if idx is not None:
    lines.insert(idx+1, row.rstrip("\n"))
    s="\n".join(lines)
    print("factcheck row inserted after line", idx+1)
else:
    print("WARN: no 2026-09-07 factcheck row found")

io.open(p,"w",encoding="utf-8").write(s)
print("done")
PY
