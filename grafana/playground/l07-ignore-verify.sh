#!/usr/bin/env bash
# 课 7 .gitignore 规则验证：应忽略全命中、0 误伤
set -u
cd /mnt/d/projects/learning

echo "=========================================================="
echo " 课 7 .gitignore 规则验证"
echo "=========================================================="

echo ""
echo "--- [A] 应忽略的课 7 一次性脚本 ---"
A_OK=0; A_BAD=0
for f in l07-mkfolder.sh l07-envcheck.sh l07-diag-norules.sh l07-diag-state.sh \
         l07-diag-pgw.sh l07-run-archive.sh l07-archive.py l07-archive2.py \
         l07-check-env.sh \
         l07_probe_statemachine.py l07_probe_statemachine2.py \
         l07_probe_keeplast.py l07_probe_keeplast2.py; do
  p="grafana/playground/$f"
  if [ -f "$p" ]; then
    if git check-ignore -q "$p" 2>/dev/null; then
      echo "  OK   $f"; A_OK=$((A_OK+1))
    else
      echo "  MISS $f"; A_BAD=$((A_BAD+1))
    fi
  else
    echo "  -    不存在（跳过）：$f"
  fi
done
echo "  命中 $A_OK / 漏 $A_BAD"

echo ""
echo "--- [B] 教学产物（须全部未被忽略）---"
B_BAD=0
for f in l07_probe_arch.py l07_probe_statemachine3.py l07_probe_nodata.py \
         l07_probe_verify.py l07_probe_down.py \
         l07-verify.sh l07-final.sh l07-review-probe.sh; do
  p="grafana/playground/$f"
  if [ -f "$p" ]; then
    if git check-ignore -q "$p" 2>/dev/null; then
      echo "  误伤 $f"; B_BAD=$((B_BAD+1))
    else
      echo "  OK   $f"
    fi
  else
    echo "  -    不存在（跳过）：$f"
  fi
done

echo ""
echo "--- [C] 讲义与档案（须未被忽略）---"
DOC="grafana/stages/3-叫得醒/lessons/lesson-07-告警架构：规则在哪求值、状态怎么迁移.md"
for f in "$DOC" "grafana/00-学习档案.md" "grafana/00-评审清单.md" \
         "grafana/02-课程目录.md" "grafana/01-学习路径总览.md" \
         "grafana/stages/3-叫得醒/overview.md"; do
  if [ -f "$f" ]; then
    if git check-ignore -q "$f" 2>/dev/null; then
      echo "  误伤 $(basename "$f")"; B_BAD=$((B_BAD+1))
    else
      echo "  OK   $(basename "$f")"
    fi
  else
    echo "  -    不存在（跳过）：$(basename "$f")"
  fi
done

echo ""
echo "--- [D] 既有规则未被波及（抽查他课程）---"
for f in "grafana/playground/l06-verify.sh" "grafana/playground/l05-verify.sh" \
         "grafana/playground/l04-verify.sh" "grafana/playground/l00-env-up.sh" \
         "grafana/playground/prometheus.yml"; do
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
