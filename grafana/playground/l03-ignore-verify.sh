#!/usr/bin/env bash
# 校验 .gitignore 的课 3 规则：应忽略的是否命中、教学产物是否被误伤
set -u
cd /mnt/d/projects/learning

echo "=== A 组：应被忽略的（课 3 一次性脚本）==="
A_OK=0; A_BAD=0
for f in l03-diag-bisect.sh l03-diag-cleanup.sh l03-diag-control.sh l03-diag-db.sh \
         l03-diag-db2.sh l03-diag-deep.sh l03-diag-diff.sh l03-diag-dscmp.sh \
         l03-diag-dsnow.sh l03-diag-fwd2.sh l03-diag-gzipfix.sh l03-diag-kv.sh \
         l03-diag-l4.sh l03-diag-link.sh l03-diag-meta.sh l03-diag-meta2.sh \
         l03-diag-promlog.sh l03-diag-rawdump.sh l03-diag-res.sh l03-diag-sniff.sh \
         l03-diag-sniff3001.sh l03-diag-timefmt.sh l03-diag-twoinst.sh \
         l03-diag-zeropoint.sh l03-env-probe.sh l03-probe-execq.sh l03-proxy-path.sh \
         l03-var-interp.sh l03-var-probe2.sh l03-channel.sh l03-e2e.sh \
         l03-sniff.sh l03-sniff2.sh l03-var-fix.sh l03-review-probe.sh; do
  p="grafana/playground/$f"
  if git check-ignore -q "$p" 2>/dev/null; then A_OK=$((A_OK+1)); else echo "  ❌ 未命中: $f"; A_BAD=$((A_BAD+1)); fi
done
echo "  应忽略命中 $A_OK 个，未命中 $A_BAD 个"

echo
echo "=== B 组：教学产物（绝不能被忽略）==="
B_OK=0; B_BAD=0
for f in l03-nodes-up.sh l03-fix-gzip.sh l03-cal.sh l03-timefrom-tri.sh \
         l03-timequery.sh l03-exp32.sh l03-exp33.sh l03-exp34.sh l03-sniff3.sh \
         l03-diag-res2.sh l03-verify.sh l03-linkcheck-all.sh \
         l03-archive.py l03-checklist.py l03-fix-abspath.py; do
  p="grafana/playground/$f"
  if git check-ignore -q "$p" 2>/dev/null; then echo "  ❌ 被误伤: $f"; B_BAD=$((B_BAD+1)); else B_OK=$((B_OK+1)); fi
done
echo "  教学产物安全 $B_OK 个，被误伤 $B_BAD 个"

echo
echo "=== C 组：课 1 / 课 2 既有规则未被波及 ==="
C_BAD=0
for f in l00-env-up.sh l01-forms.py l02-panel.py l02-verify.sh l02-linkcheck.sh \
         l02-readyfix.sh prometheus.yml; do
  p="grafana/playground/$f"
  if git check-ignore -q "$p" 2>/dev/null; then echo "  ❌ 既有产物被误伤: $f"; C_BAD=$((C_BAD+1)); fi
done
[ $C_BAD -eq 0 ] && echo "  ✅ 课 1/课 2 教学产物全部安全"

echo
echo "=== D 组：其他主题既有规则未被波及（抽查）==="
D_BAD=0
for p in "surrealdb/playground/l02-install.sh" "doris/assets/lesson07-step3.sh" \
         "frontend/typescript-core/playground/scenario.js"; do
  if [ -e "$p" ] && git check-ignore -q "$p" 2>/dev/null; then echo "  ❌ 误伤: $p"; D_BAD=$((D_BAD+1)); fi
done
[ $D_BAD -eq 0 ] && echo "  ✅ 其他主题规则未被波及"

echo
echo "=========== 汇总 ==========="
T=$((A_BAD+B_BAD+C_BAD+D_BAD))
if [ "$T" -eq 0 ]; then echo "  🎉 0 项异常（应忽略 $A_OK 全部命中，教学产物 $B_OK 全部安全）"; else echo "  ⚠️ $T 项异常"; fi
exit $T
