#!/usr/bin/env bash
# 批量救 ImagePullBackOff（修正版）
# 修正：用 ctr 退出码判断成功，不用管道 grep（上轮误判根因）
set -uo pipefail
NS=blueking

# 1. 收集失败 Pod 的镜像与所在节点
echo "===== 1. 扫描 ImagePullBackOff Pod ====="
mapfile -t LINES < <(kubectl get pods -n "$NS" --no-headers 2>/dev/null | grep 'ImagePullBackOff' | awk '{print $1}')
if [ ${#LINES[@]} -eq 0 ]; then echo "  无失败 Pod"; exit 0; fi

declare -a JOBS
for p in "${LINES[@]}"; do
  img=$(kubectl get pod "$p" -n "$NS" -o jsonpath='{.spec.containers[0].image}')
  node=$(kubectl get pod "$p" -n "$NS" -o jsonpath='{.spec.nodeName}')
  JOBS+=("$node|$img|$p")
  printf "  %-50s\n    node=%s\n    img=%s\n" "$p" "$node" "$img"
done

# 2. 并行拉取（每个节点内串行，节点间并行）
echo ""
echo "===== 2. 开始并行拉取 ====="
for job in "${JOBS[@]}"; do
  IFS='|' read -r node img pod <<< "$job"
  (
    for i in 1 2 3 4 5 6; do
      if docker exec "$node" ctr -n k8s.io images pull "$img" >/dev/null 2>&1; then
        echo "  ✅ [$node] 第${i}次成功: $img"
        exit 0
      fi
      sleep 5
    done
    echo "  ❌ [$node] 6次均失败: $img"
  ) &
done
wait

echo ""
echo "===== 3. 拉取完成，等待 K8s 自动重建 Pod（60s）====="
sleep 60

echo ""
echo "===== 4. 复查 ====="
kubectl get pods -n "$NS" --no-headers 2>/dev/null | grep -iE 'ImagePull|ErrImage' | awk '{print "  仍失败: "$1}' || echo "  ✅ 无 ImagePullBackOff"
echo ""
kubectl get pods -n "$NS" --no-headers 2>/dev/null | awk '{print $3}' | sort | uniq -c | sort -rn
