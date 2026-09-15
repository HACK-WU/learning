#!/usr/bin/env bash
# 三层 Web 应用生产化部署 —— 一键清理
# 用法：bash 实现/cleanup.sh
set -uo pipefail
NS=shop3t

echo "=== 1. 删除命名空间（连带其中全部资源）==="
kubectl delete ns "$NS" --ignore-not-found --wait=false 2>&1

echo "=== 2. 等待命名空间消失 ==="
GONE=0
for i in $(seq 1 60); do
  if ! kubectl get ns "$NS" >/dev/null 2>&1; then
    echo "  命名空间已删除（等待 ${i}s）"
    GONE=1
    break
  fi
  sleep 1
done

if [ "$GONE" -eq 0 ]; then
  echo "  ⚠️ 命名空间超过 60s 未消失，尝试清理 finalizer ..."
  # ⚠️ 课 20 补充讲义实测：真卡死时 kubectl patch ns 无效（返回 patched (no change)），
  #    必须用 /finalize 子资源 + 手写最简请求体才有效。本脚本不依赖 jq。
  python3 - <<'PY'
import json
out = {
    "apiVersion": "v1",
    "kind": "Namespace",
    "metadata": {"name": "shop3t"},
    "spec": {"finalizers": []},
}
with open("/tmp/ns-finalize.json", "w") as f:
    json.dump(out, f)
print("  wrote /tmp/ns-finalize.json")
PY
  kubectl replace --raw "/api/v1/namespaces/$NS/finalize" -f /tmp/ns-finalize.json 2>&1 | head -3
  sleep 3
  kubectl get ns "$NS" 2>&1 | head -2
fi

echo "=== 3. 清理遗留 PV ==="
PVS=$(kubectl get pv --no-headers 2>/dev/null | grep -i "$NS" | awk '{print $1}')
if [ -n "$PVS" ]; then
  for PV in $PVS; do
    echo "  清理 PV: $PV"
    kubectl patch pv "$PV" -p '{"metadata":{"finalizers":null}}' >/dev/null 2>&1
    kubectl delete pv "$PV" --ignore-not-found >/dev/null 2>&1
  done
else
  echo "  无遗留 PV"
fi

echo "=== 4. 最终核查（应全部为空）==="
kubectl get ns "$NS" 2>&1 | head -2
kubectl get pv --no-headers 2>/dev/null | grep -i "$NS" || echo "  PV: 0"
kubectl get pod -n "$NS" --no-headers 2>/dev/null | wc -l | sed 's/^/  残留 Pod: /'

echo ""
echo "=== 清理完成 ==="
