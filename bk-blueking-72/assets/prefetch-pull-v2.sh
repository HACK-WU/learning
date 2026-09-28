#!/usr/bin/env bash
# 并行预拉 + 充分重试（吸取 bkssm 4次不够的教训）
set -uo pipefail
SEQ=${1:-third}
NODES="k8s-c1-calico-control-plane k8s-c1-calico-worker k8s-c1-calico-worker2"
LIST=/tmp/imgs-$SEQ.txt
LOG=/tmp/pull-$SEQ.log
[ -f "$LIST" ] || { echo "缺少 $LIST"; exit 1; }
: > $LOG

echo "镜像总数: $(wc -l < $LIST)  节点: 3"
echo "开始: $(date +%H:%M:%S)"

# 节点间并行，节点内串行（registry 单连接有限速，串行反而稳）
for n in $NODES; do
  (
    ok=0; skip=0; fail=0
    while read -r img; do
      img=$(echo "$img" | tr -d '\r'); [ -z "$img" ] && continue
      if docker exec "$n" ctr -n k8s.io images list 2>/dev/null | awk '{print $1}' | grep -qx "$img"; then
        skip=$((skip+1)); continue
      fi
      got=0
      for i in 1 2 3 4 5 6 7 8; do
        if docker exec "$n" ctr -n k8s.io images pull "$img" >/dev/null 2>&1; then got=1; break; fi
        sleep 3
      done
      # 用 ctr 列表复验，不靠退出码猜
      if docker exec "$n" ctr -n k8s.io images list 2>/dev/null | awk '{print $1}' | grep -qx "$img"; then
        ok=$((ok+1)); echo "  ✅ [$n] $img" >> $LOG
      else
        fail=$((fail+1)); echo "  ❌ [$n] $img" >> $LOG
      fi
    done < "$LIST"
    echo "  === $n 完成: 新拉$ok 已有$skip 失败$fail ===" >> $LOG
  ) &
done
wait

echo "结束: $(date +%H:%M:%S)"
echo ""
echo "===== 各节点结果 ====="
grep '===' $LOG | sed 's/^/  /'

echo ""
echo "===== 失败的（如有）====="
grep '❌' $LOG | sed 's/^/  /' || echo "  无"

echo ""
echo "===== 最终校验：仍缺失的镜像 ====="
allok=1
for n in $NODES; do
  docker exec $n ctr -n k8s.io images list 2>/dev/null | awk '{print $1}' | grep -vE '@sha256' | sort -u > /tmp/f-$n.txt
  miss=$(comm -23 "$LIST" /tmp/f-$n.txt 2>/dev/null)
  if [ -n "$miss" ]; then
    allok=0
    echo "  --- $n 缺 ---"
    echo "$miss" | sed 's/^/    /'
  fi
done
[ $allok -eq 1 ] && echo "  ✅ 三节点全齐"
