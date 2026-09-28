#!/usr/bin/env bash
# 把 /tmp/imgs-$SEQ.txt 里的镜像并行拉到所有节点
# 修正：用退出码判断成功（上轮管道grep误判的教训）
set -uo pipefail
SEQ=${1:-second}
NODES="k8s-c1-calico-control-plane k8s-c1-calico-worker k8s-c1-calico-worker2"
LIST=/tmp/imgs-$SEQ.txt
[ -f "$LIST" ] || { echo "缺少 $LIST，先跑 prefetch-images.sh $SEQ"; exit 1; }

echo "镜像总数: $(wc -l < $LIST)，节点: 3"
echo "开始: $(date +%H:%M:%S)"
echo ""

# 每个节点内串行、节点间并行；单镜像最多重试 4 次
for n in $NODES; do
  (
    ok=0; fail=0
    while read -r img; do
      [ -z "$img" ] && continue
      # 已有则跳过
      if docker exec "$n" ctr -n k8s.io images list 2>/dev/null | awk '{print $1}' | grep -qx "$img"; then
        continue
      fi
      got=0
      for i in 1 2 3 4; do
        if docker exec "$n" ctr -n k8s.io images pull "$img" >/dev/null 2>&1; then
          got=1; break
        fi
        sleep 5
      done
      # 用退出码复验（不靠日志）
      if docker exec "$n" ctr -n k8s.io images list 2>/dev/null | awk '{print $1}' | grep -qx "$img"; then
        echo "  ✅ [$n] $img"
        ok=$((ok+1))
      else
        echo "  ❌ [$n] $img"
        fail=$((fail+1))
      fi
    done < "$LIST"
    echo "  --- $n 完成: 成功$ok 失败$fail ---"
  ) &
done
wait

echo ""
echo "结束: $(date +%H:%M:%S)"
echo ""
echo "===== 最终校验：各节点仍缺失的镜像 ====="
for n in $NODES; do
  docker exec $n ctr -n k8s.io images list 2>/dev/null | awk '{print $1}' | sort -u > /tmp/has-$n.txt
  echo "  --- $n ---"
  comm -23 "$LIST" /tmp/has-$n.txt 2>/dev/null | sed 's/^/    缺: /' || true
done
