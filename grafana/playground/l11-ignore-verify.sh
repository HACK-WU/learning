#!/bin/bash
cd /mnt/d/projects/learning

echo "=== A. 课 11 应忽略项（须全部命中）==="
miss=0
for f in l11-team-probe.sh l11-folder-perm.sh l11-diag-perm.sh l11-hasacl.sh l11-whereami.sh l11-folder-fix.sh l11-team-role.sh l11-clean-user.sh l11-decisive.sh l11-sa.sh l11-perm-db.sh l11-write1.py l11-write2.py l11-write3.py l11-archive.py l11-archive2.py l11-archive3.py l11-verify.sh l11-final.sh l11-fix-continuation.py; do
  r=$(git check-ignore -q "grafana/playground/$f" && echo HIT || echo MISS)
  [ "$r" = "MISS" ] && { echo "  MISS $f"; miss=$((miss+1)); }
done
echo "  应忽略未命中数: $miss"

echo
echo "=== B. 课 11 教学产物（须全部不命中）==="
bad=0
for f in l11-envcheck.sh l11-org-setup.sh l11-org-switch.sh l11-crossorg.sh l11-folder-setup.sh l11-perm-retest.sh l11-viewer-test.sh l11-root-cause.sh l11-sa2.sh l11-token-test.sh l11-dbcheck.sh; do
  r=$(git check-ignore -q "grafana/playground/$f" && echo IGNORED-BAD || echo OK)
  printf "  %-26s %s\n" "$f" "$r"
  [ "$r" = "IGNORED-BAD" ] && bad=$((bad+1))
done
echo "  教学产物被误忽略数: $bad"

echo
echo "=== C. 跨课回归 ==="
echo -n "  provisioning 目录仍保留: "; git check-ignore -q grafana/playground/provisioning/datasources/ds.yaml && echo BAD || echo OK
echo -n "  课 10 l10-env-up.sh 仍保留: "; git check-ignore -q grafana/playground/l10-env-up.sh && echo BAD || echo OK
echo -n "  课 10 l10_diff.py 仍保留: "; git check-ignore -q grafana/playground/l10_diff.py && echo BAD || echo OK
echo -n "  课 9 l09-env-up.sh 仍保留: "; git check-ignore -q grafana/playground/l09-env-up.sh && echo BAD || echo OK
echo -n "  课 10 l10-envcheck.sh 仍忽略: "; git check-ignore -q grafana/playground/l10-envcheck.sh && echo OK || echo BAD
echo -n "  surrealdb l09-run.py 仍保留: "; git check-ignore -q surrealdb/playground/l09-run.py && echo BAD || echo OK

echo
echo "  总判定: 应忽略未命中=$miss 教学产物误伤=$bad"
