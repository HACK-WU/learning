#!/usr/bin/env bash
# 集群级故障注入演练（三选一或全部）
# 用法：wsl -- bash -c "tr -d '\r' < /mnt/d/projects/learning/k8s/子教程/运维专项/assets/五查-故障注入.sh | bash"
#
# ⚠️ 安全边界（重要）：
#   - 全部操作在专用命名空间 ops-drill 内进行，演练结束即整体删除
#   - 场景 2 用 VAP 且设为 Warn（放行不拦截），不会阻断任何真实业务
#   - 场景 3 修改的副本数为 0 的对象是演练专用 Deployment
#   - 不触碰 kube-system / monitoring / 任何业务命名空间
#   - 提供 reset 子命令一键清理
#
# 子命令：inject（注入三个场景）| check（走五查定位）| reset（清理）
set -uo pipefail

NS=ops-drill
hr() { printf '\n========== %s ==========\n' "$*"; }

inject() {
  hr '注入场景 1：全部 Pod Pending（requests 超出节点可分配）'
  kubectl create ns "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  # 故意申请超量 CPU（每节点 20 核，申请 999 核必然 Pending）
  kubectl -n "$NS" apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: drill-pending
spec:
  replicas: 1
  selector:
    matchLabels: { app: drill-pending }
  template:
    metadata:
      labels: { app: drill-pending }
    spec:
      containers:
      - name: c
        image: registry.k8s.io/pause:3.10
        resources:
          requests: { cpu: "999", memory: "999Gi" }
EOF
  echo '>>> 已创建 drill-pending（requests 999 核，必然 Pending）'

  hr '注入场景 2：写操作被准入拦截报"奇怪"的错（VAP Warn 模式，只告警不阻断）'
  kubectl apply -f - <<'EOF'
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: drill-deny-drillns
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
    - apiGroups:   ["apps"]
      apiVersions: ["v1"]
      operations:  ["CREATE", "UPDATE"]
      resources:   ["deployments"]
  validations:
  - expression: "!object.metadata.name.startsWith('drill-bad')"
    message: "演练策略：Deployment 名字不能以 drill-bad 开头"
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: drill-deny-drillns-b
spec:
  policyName: drill-deny-drillns
  validationActions: ["Warn"]
  matchResources:
    namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: ops-drill
EOF
  echo '>>> 已创建 VAP（Warn 模式，只告警不阻断，安全）'

  hr '注入场景 3：HPA/replicas=0 导致的"服务消失"'
  kubectl -n "$NS" apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: drill-zero
  labels: { app: drill-zero }
spec:
  replicas: 0
  selector:
    matchLabels: { app: drill-zero }
  template:
    metadata:
      labels: { app: drill-zero }
    spec:
      containers:
      - name: c
        image: registry.k8s.io/pause:3.10
---
apiVersion: v1
kind: Service
metadata:
  name: drill-zero
spec:
  selector: { app: drill-zero }
  ports:
  - port: 80
    targetPort: 80
EOF
  echo '>>> 已创建 drill-zero（replicas=0，Service 存在但无后端）'

  hr '注入完成。跑 check 子命令走五查定位'
}

check() {
  hr '① 查节点账本：是不是没余量了'
  kubectl get nodes -o custom-columns='NAME:.metadata.name,CPU_CAP:.status.capacity.cpu,CPU_ALLOC:.status.allocatable.cpu'
  for n in $(kubectl get nodes -o name | sed 's|^node/||'); do
    printf -- '--- %s ---\n' "$n"
    kubectl describe node "$n" | sed -n '/Allocated resources/,/Events/p' | head -8
    kubectl get node "$n" -o jsonpath='压力: {range .status.conditions[*]}{.type}={.status} {end}{"\n"}'
  done

  hr '② 查 etcd：是不是数据层的问题'
  ETCD_POD=$(kubectl -n kube-system get pod -l component=etcd -o name | head -1 | sed 's|^pod/||')
  kubectl -n kube-system exec "$ETCD_POD" -- etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    endpoint health --write-out=table 2>&1 | head
  echo '--- alarm（空=正常）---'
  kubectl -n kube-system exec "$ETCD_POD" -- etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    alarm list 2>&1 | head

  hr '③ 查证书'
  CP=$(docker ps --format '{{.Names}}' 2>/dev/null | grep control-plane | head -1)
  docker exec "$CP" kubeadm certs check-expiration 2>&1 | grep -E 'RESIDUAL|apiserver |ca ' | head -5

  hr '④ 查准入：被拦了要知道被谁拦'
  echo '--- VAP ---'
  kubectl get validatingadmissionpolicy -A 2>&1 | head
  echo '--- 触发一次 Warn（应看到 warning，但对象仍能创建）---'
  kubectl -n "$NS" create deployment drill-bad-test --image=registry.k8s.io/pause:3.10 2>&1 | head -5
  kubectl -n "$NS" delete deployment drill-bad-test --ignore-not-found >/dev/null 2>&1

  hr '⑤ 查备份'
  kubectl get cronjob -A 2>&1 | head

  hr '现象确认'
  echo '--- 场景 1：Pending 的 Pod 与 Events ---'
  kubectl -n "$NS" get pods --no-headers 2>&1 | head
  kubectl -n "$NS" describe pod -l app=drill-pending 2>/dev/null | grep -A5 Events | head -10
  echo '--- 场景 3：Service 有，但 EndpointSlice 空 ---'
  kubectl -n "$NS" get svc,endpointslices --no-headers 2>&1 | head
  echo '--- 三个场景的 kubectl top（实际用量口径）---'
  kubectl top nodes 2>&1 | head
}

reset() {
  hr '清理演练资源'
  kubectl delete validatingadmissionpolicybinding drill-deny-drillns-b --ignore-not-found >/dev/null 2>&1
  kubectl delete validatingadmissionpolicy drill-deny-drillns --ignore-not-found >/dev/null 2>&1
  kubectl delete ns "$NS" --ignore-not-found >/dev/null 2>&1
  echo '>>> 已删除 VAP / VAPB / 命名空间 ops-drill'
  kubectl get ns "$NS" 2>&1 | head -2
  kubectl get validatingadmissionpolicy -A 2>&1 | head -2
}

case "${1:-inject}" in
  inject) inject ;;
  check)  check  ;;
  reset)  reset  ;;
  *) echo "用法: $0 {inject|check|reset}" ;;
esac
