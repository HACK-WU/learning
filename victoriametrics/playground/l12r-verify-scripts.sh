#!/bin/bash
echo "=== 讲义引用的 l12r-* 补充脚本存在性校验 ==="
cd /mnt/d/projects/learning/victoriametrics/playground
miss=0
for f in l12r-probe.sh l12r-nativemig2.sh l12r-xmig-data.sh l12r-xmig-run.sh \
         l12r-snapretain.sh l12r-snap-ab.sh l12r-delmerge5.sh l12r-delmerge6.sh; do
  if [ -f "$f" ]; then
    printf "  [OK]   %-24s %s 行\n" "$f" "$(wc -l < $f)"
  else
    printf "  [MISS] %-24s 不存在\n" "$f"
    miss=$((miss+1))
  fi
done
echo ""
echo "缺失数: $miss"

echo ""
echo "=== 讲义中引用的全部脚本名（去重） ==="
grep -o 'l12[a-z]*-[a-z0-9]*\.sh' /mnt/d/projects/learning/victoriametrics/stages/5-生产落地/12-备份恢复迁移与选型决策.md | sort -u | while read -r s; do
  if [ -f "$s" ]; then
    printf "  [OK]   %s\n" "$s"
  else
    printf "  [MISS] %s\n" "$s"
  fi
done
