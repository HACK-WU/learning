#!/usr/bin/env bash
# 课 6 .gitignore 规则验证：应忽略全命中、0 误伤
set -u
cd /mnt/d/projects/learning

echo "=========================================================="
echo " 课 6 .gitignore 规则验证"
echo "=========================================================="

echo ""
echo "--- [A] 应忽略的课 6 一次性脚本（4 个）---"
A_OK=0; A_BAD=0
for f in l06-check.sh l06-run-archive.sh l06-archive.py l06-archive2.py; do
  p="grafana/playground/$f"
  if git check-ignore -q "$p" 2>/dev/null; then
    echo "  OK   $f"; A_OK=$((A_OK+1))
  else
    echo "  MISS $f"; A_BAD=$((A_BAD+1))
  fi
done
echo "  命中 $A_OK / 漏 $A_BAD"

echo ""
echo "--- [B] 教学产物（须全部未被忽略）---"
B_BAD=0
for f in l06_probe_vartypes.py l06_probe_all.py l06_probe_multival.py \
         l06_probe_failmodes.py l06_probe_repeat.py \
         l06-verify.sh l06-final.sh l06-review-probe.sh; do
  p="grafana/playground/$f"
  if git check-ignore -q "$p" 2>/dev/null; then
    echo "  误伤 $f"; B_BAD=$((B_BAD+1))
  else
    echo "  OK   $f"
  fi
done

echo ""
echo "--- [C] 讲义与档案（须未被忽略）---"
DOC="grafana/stages/2-查得到/lessons/lesson-06-变量进阶与动态仪表盘.md"
for f in "$DOC" "grafana/00-学习档案.md" "grafana/00-评审清单.md" \
         "grafana/02-课程目录.md" "grafana/01-学习路径总览.md" \
         "grafana/stages/2-查得到/overview.md"; do
  if git check-ignore -q "$f" 2>/dev/null; then
    echo "  误伤 $(basename "$f")"; B_BAD=$((B_BAD+1))
  else
    echo "  OK   $(basename "$f")"
  fi
done

echo ""
echo "--- [D] 既有规则未被波及（抽查他课程）---"
for f in "grafana/playground/l05-verify.sh" "grafana/playground/l04-verify.sh" \
         "grafana/playground/l00-env-up.sh" "grafana/playground/prometheus.yml"; do
  [ -e "$f" ] || { echo "  - 跳过（不存在）：$f"; continue; }
  if git check-ignore -q "$f" 2>/dev/null; then
    echo "  ! 被忽略（需确认是否有意）：$f"
  else
    echo "  OK   $f"
  fi
done

echo ""
echo "=========================================================="
if [ "$A_BAD" -eq 0 ] && [ "$B_BAD" -eq 0 ]; then
  echo " 通过：应忽略 $A_OK 个全命中，教学产物 0 误伤"
else
  echo " 有问题：漏忽略 $A_BAD 个，误伤 $B_BAD 个"
fi
echo "=========================================================="
