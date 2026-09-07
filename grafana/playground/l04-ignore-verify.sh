#!/usr/bin/env bash
# 课 4 .gitignore 规则验证：0 误伤
set -u
cd /mnt/d/projects/learning

echo "=========================================================="
echo " 课 4 .gitignore 规则验证"
echo "=========================================================="

echo ""
echo "--- [A] 应忽略的课 4 一次性脚本（8 个，须全部命中）---"
A_OK=0; A_BAD=0
for f in l04-env-probe.sh l04-find-plugin.sh l04-frontend-probe.sh \
         l04-diag-cmdfmt.sh l04-diag-psline.sh l04-fix-cmdline.py \
         l04-archive.py l04-archive2.py; do
  p="grafana/playground/$f"
  if git check-ignore -q "$p" 2>/dev/null; then
    echo "  ✓ $f"; A_OK=$((A_OK+1))
  else
    echo "  ✗ 未忽略：$f"; A_BAD=$((A_BAD+1))
  fi
done
echo "  命中 $A_OK / 漏 $A_BAD"

echo ""
echo "--- [B] 教学产物（须全部未被忽略，防误伤）---"
B_BAD=0
for f in l04_probe_editor.py l04_probe_errcode.py l04_probe_journey.py \
         l04_probe_layers.py l04_probe_roundtrip.py l04-sniff.sh \
         l04-frontend-probe2.sh l04-verify.sh l04-final.sh ; do
  p="grafana/playground/$f"
  if git check-ignore -q "$p" 2>/dev/null; then
    echo "  ✗ 误伤：$f"; B_BAD=$((B_BAD+1))
  else
    echo "  ✓ $f"
  fi
done

echo ""
echo "--- [C] 讲义正文（须未被忽略）---"
for f in "grafana/stages/2-查得到/lessons/lesson-04-查询编辑器与数据源协议：一次查询的完整旅程.md" \
         "grafana/00-学习档案.md" "grafana/00-评审清单.md" \
         "grafana/02-课程目录.md" "grafana/01-学习路径总览.md" \
         "grafana/stages/2-查得到/overview.md"; do
  if git check-ignore -q "$f" 2>/dev/null; then
    echo "  ✗ 误伤：$f"; B_BAD=$((B_BAD+1))
  else
    echo "  ✓ $(basename "$f")"
  fi
done

echo ""
echo "--- [D] 既有规则未被波及（抽查他课程）---"
for f in "elasticsearch/playground/l15-demo.py" "promql/README.md" \
         "grafana/playground/l00-env-up.sh" "grafana/playground/prometheus.yml"; do
  [ -e "$f" ] || { echo "  - 跳过（不存在）：$f"; continue; }
  if git check-ignore -q "$f" 2>/dev/null; then
    echo "  ! 被忽略（需确认是否有意）：$f"
  else
    echo "  ✓ $f"
  fi
done

echo ""
echo "=========================================================="
if [ "$A_BAD" -eq 0 ] && [ "$B_BAD" -eq 0 ]; then
  echo " ✅ 忽略规则正确：应忽略 $A_OK 个全命中，教学产物 0 误伤"
else
  echo " ❌ 有问题：漏忽略 $A_BAD 个，误伤 $B_BAD 个"
fi
echo "=========================================================="
