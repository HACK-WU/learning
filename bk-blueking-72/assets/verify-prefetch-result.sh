#!/usr/bin/env bash
set -uo pipefail
echo "===== 1. 核验：脚本文件是否 CRLF 行尾（误报嫌疑）====="
for f in prefetch-pull.sh prefetch-images.sh; do
  p=/mnt/d/projects/learning/bk-blueking-72/assets/$f
  if grep -qU $'\r' "$p" 2>/dev/null; then
    echo "  $f: 含 CR（CRLF 行尾）  <-- 高度可疑"
  else
    echo "  $f: 纯 LF，正常"
  fi
done

echo ""
echo "===== 2. 核验：imgs 列表文件是否带 CR ====="
grep -cU $'\r' /tmp/imgs-second.txt 2>/dev/null && echo "  列表含 CR" || echo "  列表正常"

echo ""
echo "===== 3. 真相：各节点 second 批镜像实际在位情况 ====="
for n in k8s-c1-calico-control-plane k8s-c1-calico-worker k8s-c1-calico-worker2; do
  echo "  --- $n ---"
  docker exec $n ctr -n k8s.io images list 2>/dev/null \
    | awk '{print $1}' | grep -vE '@sha256' | sort -u > /tmp/real-$n.txt
  while read -r img; do
    img=$(echo "$img" | tr -d '\r')
    if grep -qx "$img" /tmp/real-$n.txt; then echo "    ✅ $img"
    else echo "    ❌ $img"; fi
  done < /tmp/imgs-second.txt
done

echo ""
echo "===== 4. ctr 里 bkssm / bkiam 的实际情况（含任何痕迹）====="
for n in k8s-c1-calico-control-plane k8s-c1-calico-worker k8s-c1-calico-worker2; do
  echo "  --- $n ---"
  docker exec $n ctr -n k8s.io images list 2>/dev/null | grep -E 'bkssm|bkiam' | sed 's/^/    /' || echo "    (无)"
done
