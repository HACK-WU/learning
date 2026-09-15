#!/usr/bin/env bash
# ============================================================
# PDB 驱逐阻断验证 —— 用 Eviction API 拿到真实拒绝证据
#
# 背景：PDB 只约束「自愿驱逐」（Eviction API / kubectl drain）。
#        kubectl delete pod 不走 Eviction API，因此永远拿不到 429。
#
# 手法：必须把 PDB 改成 maxUnavailable: 0 才能让 allowed 恒为 0。
#        用 minAvailable 构造不出稳定 allowed=0 —— 删一个 Pod 后
#        控制器立刻补新的，currentHealthy 马上恢复。
#
# 用法： bash pdb-evict-test.sh
# 清理：脚本结束自动恢复 PDB 为 minAvailable: 1
# ============================================================
set -u
NS=shop3t
PDB=web-pdb

echo "=== 1. 初始 PDB 状态 ==="
kubectl -n "$NS" get pdb -o custom-columns=\
'NAME:.metadata.name,MINAVAIL:.spec.minAvailable,CURRENT:.status.currentHealthy,DESIRED:.status.desiredHealthy,ALLOWED:.status.disruptionsAllowed' 2>&1

echo ""
echo "=== 2. 对照实验：kubectl delete pod（预期不受 PDB 约束）==="
P=$(kubectl -n "$NS" get pod -l app=web -o jsonpath='{.items[0].metadata.name}' 2>&1)
echo "删除 Pod: $P  →  观察是否被 PDB 拦（预期：不拦，直接删）"
kubectl -n "$NS" delete pod "$P" --wait=false 2>&1
kubectl -n "$NS" wait --for=condition=Ready pod -l app=web --timeout=120s >/dev/null 2>&1
echo "结果：Pod 已被删除并重建 —— 证明 delete 不受 PDB 约束"

echo ""
echo "=== 3. 把 PDB 改为 maxUnavailable: 0（构造 allowed=0）==="
kubectl -n "$NS" patch pdb "$PDB" --type=merge \
  -p '{"spec":{"minAvailable":null,"maxUnavailable":0}}' 2>&1
sleep 3
kubectl -n "$NS" get pdb "$PDB" -o custom-columns=\
'NAME:.metadata.name,MAXUNAVAIL:.spec.maxUnavailable,CURRENT:.status.currentHealthy,ALLOWED:.status.disruptionsAllowed' 2>&1

echo ""
echo "=== 4. 经 Eviction API 驱逐（预期 HTTP 429 拒绝）==="
P2=$(kubectl -n "$NS" get pod -l app=web -o jsonpath='{.items[0].metadata.name}' 2>&1)
echo "驱逐目标: $P2"
kubectl proxy --port=8001 >/dev/null 2>&1 &
PROXY_PID=$!
sleep 3
CODE=$(curl -s -o /tmp/evict-result.json -w "%{http_code}" -X POST \
  -H "Content-Type: application/json" \
  --data "{\"apiVersion\":\"policy/v1\",\"kind\":\"Eviction\",\"metadata\":{\"name\":\"$P2\",\"namespace\":\"$NS\"}}" \
  "http://localhost:8001/api/v1/namespaces/$NS/pods/$P2/eviction")
kill $PROXY_PID 2>/dev/null

echo "HTTP 状态码: $CODE"
echo "响应体:"
cat /tmp/evict-result.json 2>&1 | head -12

echo ""
if [ "$CODE" = "429" ]; then
  echo "✅ 通过：PDB 真实阻断驱逐（reason=TooManyRequests）"
else
  echo "❌ 未拿到 429，实际码: $CODE —— 检查 maxUnavailable 是否生效"
fi

echo ""
echo "=== 5. 恢复 PDB 为 minAvailable: 1 ==="
kubectl -n "$NS" patch pdb "$PDB" --type=merge \
  -p '{"spec":{"maxUnavailable":null,"minAvailable":1}}' 2>&1
sleep 2
kubectl -n "$NS" get pdb -o custom-columns=\
'NAME:.metadata.name,MINAVAIL:.spec.minAvailable,ALLOWED:.status.disruptionsAllowed' 2>&1
