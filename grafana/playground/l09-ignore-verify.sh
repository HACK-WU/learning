#!/usr/bin/env bash
# 课 9 .gitignore 回归校验：26 条应忽略 + 12 条应保护 + 0 误伤
set -u
cd /mnt/d/projects/learning

echo "=== A. 课 9 应忽略项（必须全部命中）==="
IGNORE=(
  grafana/playground/l09-envcheck.sh
  grafana/playground/l09-diag-read.sh
  grafana/playground/l09-jaeger-probe.sh
  grafana/playground/l09-diag-counts.py
  grafana/playground/l09-diag-autolabel.py
  grafana/playground/l09-diag-otlp.sh
  grafana/playground/l09-fix-otlp.sh
  grafana/playground/l09-fix-otlp2.sh
  grafana/playground/l09-findport.sh
  grafana/playground/l09-diag-exporter.sh
  grafana/playground/l09-diag-net.sh
  grafana/playground/l09-diag-prom.sh
  grafana/playground/l09-diag-parse.sh
  grafana/playground/l09-test-om.sh
  grafana/playground/l09-diag-2issues.sh
  grafana/playground/l09-diag-frame.py
  grafana/playground/l09-diag-ds.sh
  grafana/playground/l09_probe_ds.py
  grafana/playground/l09_probe_exemplar.py
  grafana/playground/l09_probe_exemplar2.py
  grafana/playground/l09_probe_exemplar3.py
  grafana/playground/l09-r1.txt
  grafana/playground/l09-rfinal.txt
)
miss=0
for f in "${IGNORE[@]}"; do
  if git check-ignore -q "$f" 2>/dev/null; then :; else echo "  ❌ 未忽略: $f"; miss=$((miss+1)); fi
done
echo "  应忽略 ${#IGNORE[@]} 条，漏忽略 $miss 条"

echo ""
echo "=== B. 必须保护的教学产物（不能被忽略）==="
KEEP=(
  grafana/playground/l09_exemplar_exporter.py
  grafana/playground/l09-env-up.sh
  grafana/playground/l09-jaeger-up.sh
  grafana/playground/l09-exemplar-up.sh
  grafana/playground/l09-restart-exporter.sh
  grafana/playground/l09-verify.sh
  grafana/playground/l09-final.sh
  grafana/playground/l09-archive.py
  grafana/playground/l09_probe_loki.py
  grafana/playground/l09_probe_drilldown.py
  grafana/playground/l09_probe_ds2.py
  grafana/playground/l09_probe_final.py
  grafana/playground/prometheus-ex.yml
  grafana/playground/prometheus-ex2.yml
)
bad=0
for f in "${KEEP[@]}"; do
  if git check-ignore -q "$f" 2>/dev/null; then echo "  ❌ 被误忽略: $f"; bad=$((bad+1)); fi
done
echo "  应保护 ${#KEEP[@]} 条，被误忽略 $bad 条"

echo ""
echo "=== C. 跨课回归：既有教学产物仍受保护 ==="
OLD=(
  grafana/playground/l00-env-up.sh
  grafana/playground/prometheus.yml
  grafana/playground/l07-mkfolder.sh
  grafana/playground/l08_webhook_receiver.py
  grafana/playground/l08-verify.sh
  grafana/playground/l08_probe_group.py
)
oldbad=0
for f in "${OLD[@]}"; do
  if git check-ignore -q "$f" 2>/dev/null; then echo "  ❌ 既有产物被误忽略: $f"; oldbad=$((oldbad+1)); fi
done
echo "  抽查 ${#OLD[@]} 条，误伤 $oldbad 条"

echo ""
echo "=== D. 总结 ==="
if [ $miss -eq 0 ] && [ $bad -eq 0 ] && [ $oldbad -eq 0 ]; then
  echo "  ✅ 全部通过（应忽略全命中 / 教学产物零误伤 / 跨课回归干净）"
else
  echo "  ❌ 有问题：漏忽略=$miss 误忽略=$bad 跨课误伤=$oldbad"
fi
