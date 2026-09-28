#!/usr/bin/env bash
# 用途：确认渲染出的 PVC 用什么 storageClass（决定能否直接用集群 default standard）
set -uo pipefail
OUT=/root/bk72/render_test/base-storage-render.yaml

echo "===== 1. PVC 的 storageClassName ====="
grep -B3 -A6 '^kind: PersistentVolumeClaim' "$OUT" | grep -E 'kind:|name:|storageClassName|storage:' | head -40

echo ""
echo "===== 2. storageClassName 出现次数（空=用 default）====="
grep -c 'storageClassName:' "$OUT"
