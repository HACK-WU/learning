#!/usr/bin/env bash
# 课 4 取证脚本：Event 与 Lease（「自己冒出来的对象」）
# 用途：讲义「4.1 机制验证」的实测留痕。写操作隔离在一次性命名空间 obj4-lab。
set -u
NS=obj4-lab
kubectl create namespace "$NS" 2>&1 | tail -1

echo "===== 1. Event 是不是对象：它有没有 kind / apiVersion ====="
cat <<'EOF' | kubectl apply -f - 2>&1 | tail -1
apiVersion: v1
kind: Pod
metadata:
  name: obj4-pod
  namespace: obj4-lab
spec:
  containers:
  - name: app
    image: nginx:alpine
    imagePullPolicy: IfNotPresent
EOF
sleep 8
echo "--- 抓一条真实 Event 的完整 YAML ---"
kubectl get events -n "$NS" --sort-by=.lastTimestamp -o yaml 2>/dev/null | head -40

echo
echo "===== 2. Event 的 GVK 与它属于哪个组 ====="
kubectl get events -n "$NS" --no-headers 2>/dev/null | head -1
echo "--- apiVersion / kind ---"
kubectl get events -n "$NS" -o jsonpath='{range .items[0]}{.apiVersion}|{.kind}|{.type}|{.reason}|{.count}|{.source.component}{"\n"}{end}' 2>/dev/null

echo
echo "===== 3. Event 有没有 ownerReference？（它是 Pod 的子对象吗）====="
kubectl get events -n "$NS" -o jsonpath='{range .items[0]}involvedObject={.involvedObject.kind}/{.involvedObject.name}{"\n"}ownerRef={.metadata.ownerReferences}{"\n"}{end}' 2>/dev/null

echo
echo "===== 4. Event 涉及的对象 vs 它自己住哪（是不是同一命名空间）====="
kubectl get events -n "$NS" -o jsonpath='{range .items[*}ns={.metadata.namespace} involved={.involvedObject.namespace}/{.involvedObject.name}{"\n"}{end}' 2>/dev/null | head -5

echo
echo "===== 5. Event 数量：谁在写它 ====="
echo "总条数："
kubectl get events -n "$NS" --no-headers 2>/dev/null | wc -l
echo "按组件统计："
kubectl get events -n "$NS" -o jsonpath='{range .items[*]}{.source.component}{"\n"}{end}' 2>/dev/null | sort | uniq -c

echo
echo "===== 6. Lease：节点心跳 + 选主 ====="
echo "--- kube-node-lease 命名空间下的 Lease ---"
kubectl get lease -n kube-node-lease --no-headers 2>&1 | head -5
echo "--- 一条 Lease 的完整 YAML（节点心跳）---"
L=$(kubectl get lease -n kube-node-lease --no-headers 2>/dev/null | head -1 | awk '{print $1}')
kubectl get lease "$L" -n kube-node-lease -o yaml 2>/dev/null | head -30

echo
echo "===== 7. Lease 的 GVK 与命名空间级/集群级 ====="
kubectl api-resources --no-headers 2>/dev/null | grep -wE 'leases|events'

echo
echo "===== 8. 控制器生成对象全景：Service 生成 EndpointSlice ====="
cat <<'EOF' | kubectl apply -f - 2>&1 | tail -1
apiVersion: v1
kind: Service
metadata:
  name: obj4-svc
  namespace: obj4-lab
spec:
  selector:
    app: obj4-pod
  ports:
  - port: 80
    targetPort: 80
EOF
sleep 4
echo "--- Service 建了之后，自动出现的 EndpointSlice ---"
kubectl get endpointslice -n "$NS" --no-headers 2>&1 | head -3
echo "--- EndpointSlice 的 ownerReference（爹是谁）---"
kubectl get endpointslice -n "$NS" -o jsonpath='{range .items[0]}{.metadata.ownerReferences}{"\n"}{end}' 2>/dev/null

echo
echo "===== 9. 清理 ====="
kubectl delete namespace "$NS" 2>&1 | tail -1
kubectl get ns "$NS" 2>&1 | tail -1
