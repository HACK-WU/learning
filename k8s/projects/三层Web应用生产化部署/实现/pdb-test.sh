#!/usr/bin/env bash
# PDB 验证：drain 节点时观察 PDB 是否阻止驱逐
# ⚠️ 单节点 kind 集群：drain 会驱逐全部 Pod，本脚本只演示 PDB 的
#    "允许/拒绝" 判定，不真正破坏集群。
set -uo pipefail
NS=shop3t
NODE=$(kubectl get node -o jsonpath='{.items[0].metadata.name}')

echo "=== PDB 状态（drain 前）==="
kubectl get pdb -n $NS --no-headers
echo ""
kubectl get pdb -n $NS web-pdb -o jsonpath='minAvailable={.spec.minAvailable} currentHealthy={.status.currentHealthy} desiredHealthy={.status.desiredHealthy} disruptionsAllowed={.status.disruptionsAllowed}{"\n"}'

echo ""
echo "=== 尝试 dry-run drain（不真正执行）==="
echo "  命令：kubectl drain $NODE --dry-run=server --ignore-daemonsets --delete-emptydir-data"
kubectl drain "$NODE" --dry-run=server --ignore-daemonsets --delete-emptydir-data 2>&1 | head -20

echo ""
echo "=== PDB 语义验证：手动尝试驱逐一个 web Pod ==="
WEBPOD=$(kubectl get pod -n $NS -l app=web --no-headers | awk 'NR==1{print $1}')
echo "  目标 Pod: $WEBPOD"
echo "  disruptionsAllowed 表示还能容忍几次自愿中断："
kubectl get pdb -n $NS web-pdb -o jsonpath='    web-pdb: allowed={.status.disruptionsAllowed} healthy={.status.currentHealthy}{"\n"}'
kubectl get pdb -n $NS api-pdb -o jsonpath='    api-pdb: allowed={.status.disruptionsAllowed} healthy={.status.currentHealthy}{"\n"}'

echo ""
echo "=== 结论说明 ==="
cat <<'TXT'
  PDB 的 minAvailable=1 含义：
    - 自愿驱逐（drain / 节点维护）时，至少保留 1 个 Pod
    - disruptionsAllowed = currentHealthy - desiredHealthy
      本例 6 个 web Pod、minAvailable=1 → allowed=5，可同时驱逐 5 个
    - ⚠️ PDB 只挡"自愿驱逐"，挡不住 kubectl delete pod（课 19 已实测）

  ⚠️ 单节点局限：本集群只有 1 个节点，drain 会驱逐所有 Pod 且无处可调度，
     故本脚本只做 dry-run 与状态读取，不真正执行 drain。
TXT
