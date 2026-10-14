#!/usr/bin/env bash
# 课 6 取证脚本：对象总表（下）——网络 · 安全 · 策略 · 扩展
# 用途：验证课 6 讲义里每一份 YAML 都能真实 apply 成功。
# 写操作隔离在一次性命名空间 obj6-lab；集群级对象单独建并在结尾删除。
set -u
NS=obj6-lab
PASS=0; FAIL=0
kubectl create namespace "$NS" 2>&1 | tail -1

apply() {
  OUT=$(echo "$2" | kubectl apply -f - 2>&1 | tail -1)
  if echo "$OUT" | grep -qiE 'created|configured|unchanged'; then
    echo "  ✅ $1"; PASS=$((PASS+1))
  else
    echo "  ❌ $1 —— 实际：$OUT"; FAIL=$((FAIL+1))
  fi
}

echo "===== A. 网络与入口 ====="
apply "Service(ClusterIP)" "apiVersion: v1
kind: Service
metadata: {name: t-svc, namespace: $NS}
spec:
  selector: {app: t-app}
  ports: [{port: 80, targetPort: 80}]"

apply "Ingress" "apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: {name: t-ing, namespace: $NS}
spec:
  ingressClassName: nginx
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service: {name: t-svc, port: {number: 80}}"

apply "NetworkPolicy" "apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: t-netpol, namespace: $NS}
spec:
  podSelector: {matchLabels: {app: t-app}}
  policyTypes: [Ingress]
  ingress:
  - from: [{podSelector: {matchLabels: {app: t-client}}}]"

echo "===== B. 安全 ====="
apply "ServiceAccount" "apiVersion: v1
kind: ServiceAccount
metadata: {name: t-sa, namespace: $NS}"

apply "Role" "apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: {name: t-role, namespace: $NS}
rules:
- apiGroups: ['']
  resources: ['pods']
  verbs: ['get', 'list']"

apply "RoleBinding" "apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: {name: t-rb, namespace: $NS}
subjects:
- {kind: ServiceAccount, name: t-sa, namespace: $NS}
roleRef: {kind: Role, name: t-role, apiGroup: rbac.authorization.k8s.io}"

apply "ClusterRole(集群级)" "apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata: {name: t-crole}
rules:
- apiGroups: ['']
  resources: ['nodes']
  verbs: ['get', 'list']"

apply "ClusterRoleBinding(集群级)" "apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata: {name: t-crb}
subjects:
- {kind: ServiceAccount, name: t-sa, namespace: $NS}
roleRef: {kind: ClusterRole, name: t-crole, apiGroup: rbac.authorization.k8s.io}"

echo "===== C. 策略与限制 ====="
apply "ResourceQuota" "apiVersion: v1
kind: ResourceQuota
metadata: {name: t-quota, namespace: $NS}
spec:
  hard: {pods: '10', requests.cpu: '2'}"

apply "LimitRange" "apiVersion: v1
kind: LimitRange
metadata: {name: t-limits, namespace: $NS}
spec:
  limits:
  - type: Container
    default: {cpu: 200m, memory: 256Mi}
    defaultRequest: {cpu: 100m, memory: 128Mi}"

apply "HPA" "apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata: {name: t-hpa, namespace: $NS}
spec:
  scaleTargetRef: {apiVersion: apps/v1, kind: Deployment, name: t-app}
  minReplicas: 1
  maxReplicas: 5
  metrics:
  - type: Resource
    resource: {name: cpu, target: {type: Utilization, averageUtilization: 80}}"

apply "PDB" "apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: {name: t-pdb, namespace: $NS}
spec:
  minAvailable: 1
  selector: {matchLabels: {app: t-app}}"

echo "===== D. 集群与扩展 ====="
apply "CRD(集群级)" "apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata: {name: widgets.example.com}
spec:
  group: example.com
  names: {kind: Widget, plural: widgets, singular: widget}
  scope: Namespaced
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              size: {type: integer}"

apply "IngressClass(集群级)" "apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata: {name: t-ingclass}
spec:
  controller: example.com/ingress-controller"

echo
echo "===== 取证：Service 自动生成的 EndpointSlice ====="
sleep 3
kubectl get endpointslice -n "$NS" --no-headers 2>&1 | head -3
echo "--- EndpointSlice 的 owner ---"
kubectl get endpointslice -n "$NS" -o jsonpath='{range .items[0]}{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}{"\n"}{end}' 2>/dev/null

echo
echo "===== 取证：CRD 建好后，新对象种类真的出现了吗 ====="
kubectl api-resources --no-headers 2>/dev/null | grep -i widget
echo "--- 用新种类建一个对象 ---"
OUT=$(echo "apiVersion: example.com/v1
kind: Widget
metadata: {name: t-widget, namespace: $NS}
spec: {size: 3}" | kubectl apply -f - 2>&1 | tail -1)
echo "$OUT"
echo "$OUT" | grep -qi created && echo "  ✅ 自定义对象创建成功（对象种类本身也是对象 → 闭环）"

echo
echo "===== 取证：两级归属核对 ====="
kubectl api-resources --no-headers 2>/dev/null | grep -wE 'ingressclasses|customresourcedefinitions|clusterroles|services|roles|horizontalpodautoscalers|poddisruptionbudgets'

echo
echo "===== 统计 ====="
echo "PASS=$PASS  FAIL=$FAIL"

echo
echo "===== 清理 ====="
kubectl delete namespace "$NS" 2>&1 | tail -1
kubectl delete crd widgets.example.com 2>&1 | tail -1
kubectl delete clusterrole t-crole 2>&1 | tail -1
kubectl delete clusterrolebinding t-crb 2>&1 | tail -1
kubectl delete ingressclass t-ingclass 2>&1 | tail -1
kubectl get ns "$NS" 2>&1 | tail -1
