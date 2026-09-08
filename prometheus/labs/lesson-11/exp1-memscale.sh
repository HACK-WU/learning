#!/usr/bin/env bash
# 实验 1：序列数 → 内存 的规模曲线（补上课 10 欠的系数）
D=/mnt/d/projects/learning/prometheus/labs/lesson-11
OUT=$D/results-memscale.txt
: > $OUT
echo "# N_SERIES|numSeries|numLabelPairs|mem_MiB_median|min|max" | tee -a $OUT

for N in 0 10000 50000 100000 200000; do
  echo "--- 测量 N=$N ---" >&2
  R=$(bash $D/measure.sh $N 12 19451 5)
  echo "$N|$R" | tee -a $OUT
done

echo ""
echo "===== 规模曲线 ====="
python3 - "$OUT" <<'PY'
import sys
rows=[l.strip().split('|') for l in open(sys.argv[1]) if l.strip() and not l.startswith('#')]
print(f"{'N_SERIES':>10} {'numSeries':>10} {'mem_MiB':>10} {'Δ序列':>10} {'ΔMiB':>8} {'KiB/千序列':>12}")
base=None
prev=None
for r in rows:
    n=int(r[0]); ns=int(r[1]); m=float(r[3])
    if base is None: base=(ns,m)
    ds=ns-base[0]; dm=m-base[1]
    per = (dm*1024/ds*1000) if ds>0 else 0
    print(f"{n:>10} {ns:>10} {m:>10.2f} {ds:>10} {dm:>8.2f} {per:>12.1f}")
PY
