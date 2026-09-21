#!/usr/bin/env bash
R=/mnt/d/projects/learning/consul
P="$R/00-评审清单.md"
echo "===== 评审清单结构探测 ====="
wc -l "$P" | sed 's/^/  行数: /'
grep -n '^## \|^### ' "$P" | sed 's/^/  /' | head -20
echo
echo "===== 是否已有课3/课6的评审记录（作为格式参照）====="
grep -n '课 3\|课 6\|运维专项' "$P" | sed 's/^/  /' | head -10
