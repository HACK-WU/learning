#!/usr/bin/env bash
# 课 2 取证脚本：命名空间级 vs 集群级
# 用途：讲义「4.1 机制验证」的实测留痕。写操作隔离在一次性命名空间 obj2-lab。
set -u
NS=obj2-lab

echo "===== 1. 本集群两级对象各有多少（随 CRD 而变，别当常数）====="
echo -n "集群级(namespaced=false)："
kubectl api-resources --namespaced=false --no-headers 2>/dev/null | wc -l
echo -n "命名空间级(namespaced=true)："
kubectl api-resources --namespaced=true --no-headers 2>/dev/null | wc -l

echo
echo "===== 2. 集群级对象完整清单（本集群实测 33 条）====="
kubectl api-resources --namespaced=false --no-headers 2>/dev/null \
  | awk '{print $1"  ("$NF")"}' | sort

echo
echo "===== 3. 坑：给集群级对象加 -n 不报错 ====="
NODE=$(kubectl get nodes --no-headers 2>/dev/null | head -1 | awk '{print $1}')
echo "节点名=$NODE"
echo "--- kubectl get node \$NODE -n \$NS（命名空间不存在也照样返回）---"
kubectl get node "$NODE" -n "$NS" --no-headers 2>&1 | head -2
echo "退出码=$?"

echo
echo "===== 4. 反例：命名空间级对象写错 namespace 会怎样 ====="
kubectl create namespace "$NS" 2>&1 | tail -1
cat <<'EOF' | kubectl apply -f - 2>&1 | tail -2
apiVersion: v1
kind: ConfigMap
metadata:
  name: obj2-cm
  namespace: obj2-lab
data:
  key: value
EOF
echo "--- 查存在的 ns ---"
kubectl get cm obj2-cm -n "$NS" --no-headers 2>&1 | head -1
echo "--- 查不存在的 ns（预期 NotFound）---"
kubectl get cm obj2-cm -n no-such-ns 2>&1 | tail -1

echo
echo "===== 5. 删命名空间会连带清空里面的对象 ====="
echo "--- 删之前：命名空间里有什么 ---"
kubectl get all -n "$NS" --no-headers 2>&1 | head -5
kubectl get cm -n "$NS" --no-headers 2>&1 | head -3
echo "--- 执行删除 ---"
kubectl delete namespace "$NS" 2>&1 | tail -1
echo "--- 删之后：命名空间还在吗 ---"
kubectl get ns "$NS" 2>&1 | tail -1
echo "--- 删之后：里面的 ConfigMap 还在吗 ---"
kubectl get cm obj2-cm -n "$NS" 2>&1 | tail -1

echo
echo "===== 6. kubectl get all 到底包含哪些（漏了什么）====="
kubectl create namespace "$NS" 2>&1 | tail -1
cat <<'EOF' | kubectl apply -f - 2>&1 | tail -1
apiVersion: v1
kind: ConfigMap
metadata:
  name: hidden-cm
  namespace: obj2-lab
data:
  key: value
EOF
cat <<'EOF' | kubectl apply -f - 2>&1 | tail -1
apiVersion: v1
kind: Secret
metadata:
  name: hidden-secret
  namespace: obj2-lab
type: Opaque
data:
  pw: ZXhhbXBsZQ==
EOF
echo "--- get all 的输出 ---"
kubectl get all -n "$NS" --no-headers 2>&1 | head -5
echo "--- 但 ConfigMap/Secret 其实在 ---"
kubectl get cm,secret -n "$NS" --no-headers 2>&1 | head -5

echo
echo "===== 7. 清理 ====="
kubectl delete namespace "$NS" 2>&1 | tail -1
kubectl get ns "$NS" 2>&1 | tail -1
