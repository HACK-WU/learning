#!/usr/bin/env bash
# 预拉 v3：修复复验逻辑（用 ctr images list -q，不用 awk '{print $1}'）
set -uo pipefail
SEQ=${1:-third}
NODES="k8s-c1-calico-control-plane k8s-c1-calico-worker k8s-c1-calico-worker2"
LIST=/tmp/imgs-$SEQ.txt
LOG=/tmp/pull-$SEQ.log
: > $LOG

# 可靠的存在性判断（实测：awk '{print $1}' 会因行尾填充空格导致 grep -qx 失败）
has_img() {
  docker exec "$1" ctr -n k8s.io images list -q 2>/dev/null | grep -qxF "$2"
}

echo "镜像总数: $(wc -l < $LIST)  节点: 3"
echo "开始: $(date +%H:%M:%S)"

for n in $NODES; do
  (
    ok=0; skip=0; fail=0
    while read -r img; do
      img=$(echo "$img" | tr -d '\r'); [ -z "$img" ] && continue
      if has_img "$n" "$img"; then skip=$((skip+1)); continue; fi
      for i in 1 2 3 4 5 6 7 8; do
        docker exec "$n" ctr -n k8s.io images pull "$img" >/dev/null 2>&1 && break
        sleep 3
      done
      if has_img "$n" "$img"; then
        ok=$((ok+1)); echo "  OK [$n] $img" >> $LOG
      else
        fail=$((fail+1)); echo "  NG [$n] $img" >> $LOG
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
echo "===== 仍缺失（用 list -q 复验）====="
allok=1
for n in $NODES; do
  docker exec $n ctr -n k8s.io images list -q 2>/dev/null | sort -u > /tmp/q-$n.txt
  while read -r img; do
    img=$(echo "$img" | tr -d '\r'); [ -z "$img" ] && continue
    grep -qxF "$img" /tmp/q-$n.txt || { echo "  $n 缺: $img"; allok=0; }
  done < "$LIST"
done
[ $allok -eq 1 ] && echo "  ✅ 三节点全齐"
