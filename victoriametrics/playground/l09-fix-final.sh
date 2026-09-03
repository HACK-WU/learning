#!/bin/bash
# 课 9 收尾：修正「✅ 未开始」措辞矛盾 + 闭环阶段概览伏笔
cd /mnt/d/projects/learning/victoriametrics || exit 1

echo "=== 1. 修正 00-学习档案.md 的「✅ 未开始」==="
python3 - <<'PY'
import io
f = "00-学习档案.md"
lines = io.open(f, encoding="utf-8").read().split("\n")
n = 0
for i, ln in enumerate(lines):
    if "课 9" in ln and "✅ 未开始" in ln:
        # 替换状态列为已完成 + 填日期
        parts = ln.split("|")
        for j, p in enumerate(parts):
            if p.strip() == "✅ 未开始":
                parts[j] = " ✅ 已完成"
            elif p.strip() == "-" and j == len(parts) - 3:
                parts[j] = " 2026-09-02"
            elif p.strip() == "-" and j == len(parts) - 2:
                parts[j] = " 见讲义"
        lines[i] = "|".join(parts)
        n += 1
io.open(f, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
print("  修正 %d 处" % n)
PY
echo "-- 结果 --"
grep '课 9' 00-学习档案.md | head -3

echo
echo "=== 2. 闭环阶段 4 概览中的课 9 伏笔 ==="
F="stages/4-怎么横向扩展/README.md"
python3 - "$F" <<'PY'
import io, sys
f = sys.argv[1]
t = io.open(f, encoding="utf-8").read()
old = "- **节点故障丢 509 条数据怎么办？** → 课 9 复制因子"
new = "- ~~**节点故障丢 509 条数据怎么办？**~~ ✅ **课 9 已解答**：RF=2 + dedup 后停节点结果保持 300 不变"
if old in t:
    t = t.replace(old, new)
    io.open(f, "w", encoding="utf-8", newline="\n").write(t)
    print("  已闭环：节点故障丢数据")
else:
    print("  未匹配，可能已处理")

old2 = "- **扩容后一年负载不均衡怎么缓解？** → 课 9 副本策略"
new2 = "- **扩容后一年负载不均衡怎么缓解？** → 课 12（迁移与重平衡）；课 9 已说明副本会放大此问题（数据需存 N 份）"
if old2 in t:
    t = io.open(f, encoding="utf-8").read().replace(old2, new2)
    io.open(f, "w", encoding="utf-8", newline="\n").write(t)
    print("  已更新：负载不均衡伏笔指向课 12")
PY
echo "-- 结果 --"
sed -n '/## 待解伏笔/,/^## /p' "$F" | head -8
