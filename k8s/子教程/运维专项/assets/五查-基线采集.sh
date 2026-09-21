#!/usr/bin/env bash
# 运维层五查 · 只读基线采集
# 用途：集群级故障定位演练的第一步——先建立"健康长什么样"的基线
# 用法：wsl -- bash -c "tr -d '\r' < /mnt/d/projects/learning/k8s/子教程/运维专项/assets/五查-基线采集.sh | bash"
# 安全声明：本脚本全部为只读操作（get / describe / exec version / check-expiration），不创建、不修改、不删除任何资源
set -uo pipefail

hr() { printf '\n========== %s ==========\n' "$*"; }

hr '① 节点账本：Capacity / Allocatable 与四相压力'
kubectl get nodes -o custom-columns='NAME:.metadata.name,CPU_CAP:.status.capacity.cpu,CPU_ALLOC:.status.allocatable.cpu,MEM_ALLOC:.status.allocatable.memory'
for n in $(kubectl get nodes -o name | sed 's|^node/||'); do
  printf -- '--- %s 健康条件（Ready + 三相压力）---\n' "$n"
  kubectl get node "$n" -o jsonpath='{range .status.conditions[*]}{.type}={.status}  {end}{"\n"}'
  printf -- '--- %s Allocated（requests 口径）---\n' "$n"
  kubectl describe node "$n" | sed -n '/Allocated resources/,/Events/p'
done

hr '② etcd：leader / DB SIZE / 工具在哪'
echo '--- 关键指标 ---'
kubectl get --raw /metrics 2>/dev/null | grep -E '^(etcd_server_has_leader|etcd_db_total_size_in_bytes)' || echo '(未取到 etcd 指标)'
ETCD_POD=$(kubectl -n kube-system get pod -l component=etcd -o name | head -1 | sed 's|^pod/||')
echo "etcd pod: ${ETCD_POD:-未找到}"
if [ -n "$ETCD_POD" ]; then
  echo '--- etcdctl 版本（应能取到）---'
  kubectl -n kube-system exec "$ETCD_POD" -- etcdctl version 2>&1 | head -3
fi
CP=$(docker ps --format '{{.Names}}' 2>/dev/null | grep control-plane | head -1)
echo "control-plane 容器: ${CP:-未找到}"
if [ -n "$CP" ]; then
  echo '--- 控制面容器内 etcdctl（应 not found，证明工具不在那儿）---'
  docker exec "$CP" etcdctl version 2>&1 | head -2
fi

hr '③ 证书：三层级有效期'
if [ -n "$CP" ]; then
  docker exec "$CP" kubeadm certs check-expiration 2>&1 | head -30
else
  echo '(未找到控制面容器，跳过)'
fi

hr '④ 准入：插件 / VAP / PSA / 配额'
echo '--- 启用的准入插件 ---'
kubectl -n kube-system get pod -l component=kube-apiserver -o jsonpath='{.items[0].spec.containers[0].command}' | tr ',' '\n' | grep -i admission
echo '--- VAP（ValidatingAdmissionPolicy）---'
kubectl get validatingadmissionpolicy -A 2>&1 | head
echo '--- default 命名空间 PSA 标签 ---'
kubectl get ns default -o jsonpath='{.metadata.labels}{"\n"}' 2>&1
echo '--- ResourceQuota / LimitRange ---'
kubectl get resourcequota,limitrange -A 2>&1 | head

hr '⑤ 备份：有无定时备份'
kubectl get cronjob -A 2>&1 | head

hr '参考：装箱率的"实际用量"口径（与 requests 口径对照）'
kubectl top nodes 2>&1 | head

hr '基线采集结束'
