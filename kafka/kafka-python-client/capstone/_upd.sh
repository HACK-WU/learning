#!/bin/bash
# 课13 四处档案回写
set -e
B=/mnt/d/projects/learning/kafka/kafka-python-client
D=2026-09-23

# ---------- 1) 00-学习档案.md 进度表 ----------
F="$B/00-学习档案.md"
python3 - "$F" <<'PYEOF'
import sys, io
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = "| 4 | 课 13 | 结课综合实战 | ⬜ 未开始 | - | - |"
new = (
"| 4 | 课 13 | 工程搭建（零新增依赖 FastAPI 服务） | ✅ 已完成 | 2026-09-23 | 手写 Prometheus 文本格式 + 标准库 unittest，免装 prometheus_client/pytest |\n"
"| 4 | 课 13 | 6 个核心能力端到端实测 | ✅ 已完成 | 2026-09-23 | L1 16/16（0.004s）；L2 11/12；坏消息进 DLQ、手动提交、优雅退出全部跑通 |\n"
"| 4 | 课 13 | **三次误诊复盘（本课核心）** | ✅ 已完成 | 2026-09-23 | 同一份代码测出 67/s 与 897564/s，差 1.3 万倍——坏的是尺子不是代码 |"
)
assert old in s, "进度表锚点未找到"
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
print("  1) 00-学习档案.md 进度表 OK")
PYEOF

# ---------- 2) stages/4 overview ----------
F="$B/stages/4-生产级集成/overview.md"
python3 - "$F" <<'PYEOF'
import sys, io
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = "| 课 13 | 结课综合实战 | 把全线的东西用起来 | ⬜ 未开始 |"
new = "| 课 13 | 结课综合实战 | 把全线的东西用起来 | ✅ 已完成 |"
assert old in s, "overview 锚点未找到"
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
print("  2) stages/4 overview OK")
PYEOF

# ---------- 3) 02-课程目录.md ----------
F="$B/02-课程目录.md"
python3 - "$F" <<'PYEOF'
import sys, io
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = "- 课 13：结课综合实战（待讲解）"
new = "- 课 13：结课综合实战 ✅（工程 [capstone/](../capstone/)；核心产出＝三次误诊复盘）"
assert old in s, "课程目录锚点未找到"
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
print("  3) 02-课程目录.md OK")
PYEOF

# ---------- 4) 01-学习路径总览.md ----------
F="$B/01-学习路径总览.md"
python3 - "$F" <<'PYEOF'
import sys, io
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = 'D3["课 13 结课实战"]'
new = 'D3["课 13 结课实战 ✅"]'
assert old in s, "总览锚点未找到"
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
print("  4) 01-学习路径总览.md OK")
PYEOF

# ---------- 5) 评审记录表 ----------
F="$B/00-评审清单.md"
python3 - "$F" <<'PYEOF'
import sys, io
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
lines = s.split("\n")
idx = None
for i, l in enumerate(lines):
    if l.startswith("|------") and i > 0 and lines[i-1].startswith("|"):
        idx = i
        break
assert idx is not None, "评审表头未找到"
row = ("| 2026-09-23 | 课 13 结课实战 · 交付后自动独立复审 | 主 agent 复审脚本 "
       "[l13_review.py](../capstone/tests/l13_review.py)（10 项逐条核验） | **P0 清零，10/10 全过**。"
       "核验要点：①两种吞吐测法差异 **1.3 万倍**（测法A 67/s vs 测法B 897564/s），讲义结论 6 成立；"
       "②测法A 耗时 30.05s 紧贴超时上限，坐实「尾部等待」指纹；③分区倾斜复审复现，"
       "实测 `{0:0, 1:2000, 2:0, 3:0}`——裸 produce 不传 key 时按 batch 落同一分区（已补进讲义坑 #7）；"
       "④独立 group 拿到 4 分区；⑤服务端点 6 项（lag 为 gauge、指标齐全、DLQ 计数存在）全过。"
       "**本课最大产出是三次误诊复盘**：初版测出 0.7 条/秒后连续三次「修复」（lag 节流→异步 commit→"
       "lag 移出消费线程），数字每况愈下（16.6→11.1→3.8），真因是**测量方法错误**而非代码："
       "(a) 空 poll 时间算进每消息耗时，伪造出 5007ms/条；(b) 测试脚本与运行中服务共用 group.id 触发持续 rebalance；"
       "(c) 用「等 N 条完成」测法，遇分区倾斜导致最后几条永不到来，吃满超时。"
       "代码侧已保留**诚实注释**：worker._run 与 worker._commit 的 docstring 明确标注"
       "「曾误诊、710 倍数字来自被污染实验、请勿引用」，保留独立 lag 线程与异步提交的真实理由是**解耦**而非性能 |"
       "已修并复验：10/10 全过 |")
lines.insert(idx + 1, row)
io.open(p, "w", encoding="utf-8").write("\n".join(lines))
print("  5) 00-评审清单.md 评审记录 OK")
PYEOF

echo "=== 四处档案回写完成 ==="
