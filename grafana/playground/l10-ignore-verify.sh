#!/bin/bash
cd /mnt/d/projects/learning

echo "=== A. 课 10 应忽略项（须全部命中）==="
miss=0
for f in l10-envcheck.sh l10-check.sh l10-probe2.sh l10-probe3.sh l10-probe4.sh l10-restart.sh l10-uiedit.sh l10-diag-allow.sh l10-wait.sh l10-wait2.sh l10-verify.sh l10-archive.py l10-archive2.py l10-final.sh l10_uiconflict.py; do
  r=$(git check-ignore -q "grafana/playground/$f" && echo HIT || echo MISS)
  printf "  %-24s %s\n" "$f" "$r"
  [ "$r" = "MISS" ] && miss=$((miss+1))
done
echo "  应忽略未命中数: $miss"

echo
echo "=== B. 课 10 教学产物（须全部不命中）==="
bad=0
keep="grafana/playground/l10-env-up.sh grafana/playground/l10-probe1.sh grafana/playground/l10-probe5.sh grafana/playground/l10-fresh.sh grafana/playground/l10-uiedit2.sh grafana/playground/l10-delete.sh grafana/playground/l10-delete2.sh grafana/playground/l10_jsonmodel.py grafana/playground/l10_roundtrip.py grafana/playground/l10_diff.py"
for f in $keep; do
  r=$(git check-ignore -q "$f" && echo IGNORED-BAD || echo OK)
  printf "  %-46s %s\n" "$(basename $f)" "$r"
  [ "$r" = "IGNORED-BAD" ] && bad=$((bad+1))
done
echo "  教学产物被误忽略数: $bad"

echo
echo "=== C. provisioning 目录（教学主体，须全部不命中）==="
pbad=0
for f in $(find grafana/playground/provisioning -type f | sort); do
  r=$(git check-ignore -q "$f" && echo IGNORED-BAD || echo OK)
  printf "  %-58s %s\n" "$f" "$r"
  [ "$r" = "IGNORED-BAD" ] && pbad=$((pbad+1))
done
echo "  provisioning 被误忽略数: $pbad"

echo
echo "=== D. 跨课回归（其他课程既有规则未被波及）==="
echo -n "  ES l10-*.ps1 仍忽略: "; git check-ignore -q elasticsearch/playground/l10-demo.ps1 && echo OK || echo "N/A(文件可能不存在)"
echo -n "  surrealdb l09-run.py 仍保留: "; git check-ignore -q surrealdb/playground/l09-run.py && echo BAD || echo OK
echo -n "  课 9 exporter 仍保留: "; git check-ignore -q grafana/playground/l09_exemplar_exporter.py && echo BAD || echo OK
echo -n "  课 9 l09-env-up.sh 仍保留: "; git check-ignore -q grafana/playground/l09-env-up.sh && echo BAD || echo OK
echo -n "  课 7 mkfolder 仍保留: "; git check-ignore -q grafana/playground/l07-mkfolder.sh && echo BAD || echo OK

echo
echo "=== E. git status 概览 ==="
git status --porcelain | grep -c '^??' | sed 's/^/  未跟踪条目数: /'
echo "  总判定: 应忽略未命中=$miss 教学产物误伤=$bad provisioning误伤=$pbad"
