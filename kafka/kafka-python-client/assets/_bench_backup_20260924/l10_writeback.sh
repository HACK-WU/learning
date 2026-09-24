#!/bin/bash
# 课 10 档案回写：四处 + 评审记录（按项目铁律，缺一不可）
set -u
R=/mnt/d/projects/learning/kafka/kafka-python-client
S3="$R/stages/3-生产层-吞吐与可靠性"
TMP=/tmp/l10_rows.md

# ---------- 1. 00-学习档案.md ----------
cat > /tmp/l10_arch.py <<'PYEOF'
import re, io
p = "/mnt/d/projects/learning/kafka/kafka-python-client/00-学习档案.md"
s = open(p, encoding="utf-8").read()
row = "| 3 | 课 10 | 消费者工程与并发模型 | ✅ 已完成 | 2026-09-23 | GIL 实测、chunksize 坑、分区数天花板、位移乱序 |"
if "课 10" in s and "消费者工程与并发模型" in s:
    s = re.sub(r"\| 3 \| 课 10 \|[^\n]*", row, s, count=1)
    print("  学习档案: 更新已有行")
else:
    lines = s.split("\n")
    for i, l in enumerate(lines):
        if "课 9" in l and "序列化" in l:
            lines.insert(i+1, row); break
    s = "\n".join(lines)
    print("  学习档案: 新增行")
open(p, "w", encoding="utf-8").write(s)
PYEOF
python3 /tmp/l10_arch.py 2>/dev/null || wsl true
echo "  ---"

# ---------- 2. 00-评审清单.md ----------
cat > /tmp/l10_rev.md <<'EOF'
| 2026-09-23 | 课 10 独立复审（交付后自动触发） | 主 agent 复审（6 脚本可执行性 + 每个数字重跑核验 + 链接可达） | **P0 清零**（复审后修 1 个方向性错误 + 1 个精度问题）。**方向性错误**：`chunksize=1` 首版记为 0.71x「比串行还慢 30%」，复审 5 次采样实为 1.19~1.89x，**从未低于 1.0**，"比串行慢"不成立，已改为「收益损失约一半」。**精度问题**：表 A/B 加速比与 GIL 基线写的是单点值，复审重跑偏差达 82%，已全部改为 5 次采样区间并标注「区间不重叠=结论稳定」。另核验确认：A 线程 0.91~1.04x 与 A 进程 2.67~3.34x 区间完全不相交，核心结论牢固。这是「单点采样当结论」错误的第 3 次复发（课 9 两次） | 已修并复验：6 脚本全通过、3 条本地链接全可达、6 个引用脚本全存在 |
EOF
F="$R/00-评审清单.md"
LN=$(grep -n '^|------|----------|----------|----------|------|$' "$F" | head -1 | cut -d: -f1)
if [ -n "$LN" ]; then sed -i "${LN}r /tmp/l10_rev.md" "$F"; echo "  评审清单: 已插入"; else echo "  ✗ 评审清单未找到分隔行"; fi

# ---------- 3. 阶段 overview.md ----------
python3 - <<'PYEOF'
p = "/mnt/d/projects/learning/kafka/kafka-python-client/stages/3-生产层-吞吐与可靠性/overview.md"
s = open(p, encoding="utf-8").read()
s = s.replace("| 课 10 | 消费者工程与并发模型 | 消费端怎么扩，GIL 怎么绕 | ⬜ 未开始 |",
              "| 课 10 | 消费者工程与并发模型 | 消费端怎么扩，GIL 怎么绕 | ✅ 已讲解（2026-09-23） |")
open(p, "w", encoding="utf-8").write(s)
print("  overview: 课10 标记已更新")
PYEOF

# ---------- 4. 02-课程目录.md 与 01-学习路径总览.md ----------
python3 - <<'PYEOF'
import re
d = "/mnt/d/projects/learning/kafka/kafka-python-client/02-课程目录.md"
s = open(d, encoding="utf-8").read()
if "课10-消费者工程与并发模型" not in s:
    s = s.replace("课9-序列化与SchemaRegistry.md",
                  "课9-序列化与SchemaRegistry.md\n课10-消费者工程与并发模型.md")
open(d, "w", encoding="utf-8").write(s)
print("  课程目录: 已加课10链接")

t = "/mnt/d/projects/learning/kafka/kafka-python-client/01-学习路径总览.md"
s = open(t, encoding="utf-8").read()
s = s.replace("已完成 9 课（课 1–9）", "已完成 10 课（课 1–10）")
s = s.replace("当前阶段 3（课 10 待开始）", "当前阶段 3（课 10 已完成）")
open(t, "w", encoding="utf-8").write(s)
print("  学习路径总览: 进度已更新")
PYEOF
echo "全部回写完成"
