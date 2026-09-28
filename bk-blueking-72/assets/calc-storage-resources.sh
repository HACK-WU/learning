#!/usr/bin/env bash
# 用途：渲染 base-storage，算出真实资源 requests 总账——确认不撑爆 34G 才动手
set -uo pipefail
B=/root/bk72/install/blueking
E=$B/environments/default
BIN=/root/bk72/tools/bin
HF=$BIN/helmfile
export PATH="$BIN:$PATH"
OUT=/root/bk72/render_test/base-storage-render.yaml

cd "$B" || exit 1
echo "===== 渲染 base-storage（真实资源需求）====="
timeout 900 "$HF" -f base-storage.yaml.gotmpl template > "$OUT" 2>/tmp/bs_err.log
ec=$?
echo "退出码: $ec  输出大小: $(wc -c < "$OUT") 字节"
[ -s /tmp/bs_err.log ] && { echo "--- 错误 ---"; head -20 /tmp/bs_err.log; }

echo ""
echo "===== 1. 渲染出的 StatefulSet/Deployment ====="
grep -E '^kind:|^  name:' "$OUT" 2>/dev/null | paste - - 2>/dev/null | grep -E 'StatefulSet|Deployment' | head -20

echo ""
echo "===== 2. 资源 requests 汇总 ====="
grep -B1 -A3 -E 'requests:' "$OUT" 2>/dev/null | grep -E 'memory:|cpu:' | head -40

echo ""
echo "===== 3. PVC 存储需求 ====="
grep -E 'storage:' "$OUT" 2>/dev/null | sort | uniq -c | head -15
