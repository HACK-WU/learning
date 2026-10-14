#!/usr/bin/env bash
# 课 3 取证脚本：ownerReference 与级联删除
# 用途：讲义「4.1 机制验证」的实测留痕。写操作隔离在一次性命名空间 obj3-lab。
set -u
NS=obj3-lab
kubectl create namespace "$NS" 2>&1 | tail -1

echo "===== 1. 建一个 Deployment，看它生的 Pod 上 ownerReference 长什么样 ====="
cat <<'EOF' | kubectl apply -f - 2>&1 | tail -1
apiVersion: apps/v1
kind: Deployment
metadata:
  name: obj3-web
  namespace: obj3-lab
spec:
  replicas: 2
  selector:
    matchLabels:
      app: obj3-web
  template:
    metadata:
      labels:
        app: obj3-web
    spec:
      containers:
      - name: app
        image: nginx:alpine
        imagePullPolicy: IfNotPresent
EOF
sleep 8
POD=$(kubectl get pod -n "$NS" -l app=obj3-web --no-headers 2>/dev/null | head -1 | awk '{print $1}')
echo "取到 Pod=$POD"
echo "--- Pod 上的 ownerReference（真值）---"
kubectl get pod "$POD" -n "$NS" -o jsonpath='{.metadata.ownerReferences}' ; echo

echo
echo "===== 2. 中间层：ReplicaSet 也有 ownerReference（链是两跳）====="
RS=$(kubectl get rs -n "$NS" --no-headers 2>/dev/null | head -1 | awk '{print $1}')
echo "RS=$RS"
kubectl get rs "$RS" -n "$NS" -o jsonpath='{.metadata.ownerReferences}'; echo
echo "--- RS 的 uid（用来确认 Pod 认的是不是它）---"
kubectl get rs "$RS" -n "$NS" -o jsonpath='{.metadata.uid}'; echo

echo
echo "===== 3. 三种级联删除策略 ====="
echo "--- 3a. 默认（Background）：删 Deployment，Pod 应被回收 ---"
kubectl delete deployment obj3-web -n "$NS" 2>&1 | tail -1
sleep 6
echo "剩余 Pod 数："
kubectl get pod -n "$NS" -l app=obj3-web --no-headers 2>/dev/null | wc -l

echo
echo "--- 3b. Orphan：显式留下孤儿 ---"
cat <<'EOF' | kubectl apply -f - 2>&1 | tail -1
apiVersion: apps/v1
kind: Deployment
metadata:
  name: obj3-orphan
  namespace: obj3-lab
spec:
  replicas: 2
  selector:
    matchLabels:
      app: obj3-orphan
  template:
    metadata:
      labels:
        app: obj3-orphan
    spec:
      containers:
      - name: app
        image: nginx:alpine
        imagePullPolicy: IfNotPresent
EOF
sleep 8
echo "删除前 Pod 数："
kubectl get pod -n "$NS" -l app=obj3-orphan --no-headers 2>/dev/null | wc -l
kubectl delete deployment obj3-orphan -n "$NS" --cascade=orphan 2>&1 | tail -1
sleep 4
echo "删除后 Pod 数（预期 2，说明成了孤儿）："
kubectl get pod -n "$NS" -l app=obj3-orphan --no-headers 2>/dev/null | wc -l
echo "--- 孤儿 Pod 的 ownerReference 还在吗（预期还在，只是爹没了）---"
OPOD=$(kubectl get pod -n "$NS" -l app=obj3-orphan --no-headers 2>/dev/null | head -1 | awk '{print $1}')
kubectl get pod "$OPOD" -n "$NS" -o jsonpath='{.metadata.ownerReferences[0].name}|{.metadata.ownerReferences[0].uid}'; echo
echo "--- 那个爹（RS）真的没了吗 ---"
kubectl get rs -n "$NS" --no-headers 2>/dev/null | wc -l

echo
echo "===== 4. 孤儿怎么收拾：手动删 ====="
kubectl delete pod -n "$NS" -l app=obj3-orphan 2>&1 | tail -1
sleep 3
echo "剩余 Pod 数（预期 0）："
kubectl get pod -n "$NS" --no-headers 2>/dev/null | wc -l

echo
echo "===== 5. finalizer 让删除卡住 ====="
cat <<'EOF' | kubectl apply -f - 2>&1 | tail -1
apiVersion: v1
kind: ConfigMap
metadata:
  name: obj3-stuck
  namespace: obj3-lab
  finalizers:
  - example.com/never-done
data:
  key: value
EOF
echo "--- 尝试删除（预期卡住）---"
timeout 8 kubectl delete cm obj3-stuck -n "$NS" 2>&1 | tail -2 || echo "(超时未返回 = 卡住了)"
echo "--- 查状态（预期 Terminating，对象还在）---"
kubectl get cm obj3-stuck -n "$NS" -o jsonpath='{.metadata.deletionTimestamp}|{.metadata.finalizers}'; echo

echo
echo "===== 6. 清理：先摘 finalizer，再删命名空间 ====="
kubectl patch cm obj3-stuck -n "$NS" --type=merge -p '{"metadata":{"finalizers":[]}}' 2>&1 | tail -1
kubectl delete namespace "$NS" 2>&1 | tail -1
kubectl get ns "$NS" 2>&1 | tail -1
