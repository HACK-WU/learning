#!/usr/bin/env bash
# 课 1 取证脚本：status 子资源语义 + resourceVersion 乐观锁 + managedFields 形态
# 用途：讲义「4.1 机制验证」的实测留痕。全部对象隔离在 obj-lab 命名空间。
set -u
NS=obj-lab
POD=obj-pod

echo "===== 1. status 是不是子资源：带 --subresource=status 改 ====="
kubectl patch pod "$POD" -n "$NS" --subresource=status --type=merge \
  -p '{"status":{"phase":"Bogus"}}' 2>&1 | tail -2
echo "--- 改完实际 phase ---"
kubectl get pod "$POD" -n "$NS" -o jsonpath='{.status.phase}'; echo

echo
echo "===== 2. 不带 --subresource，直接改 status ====="
kubectl patch pod "$POD" -n "$NS" --type=merge \
  -p '{"status":{"phase":"Bogus2"}}' 2>&1 | tail -2
echo "--- 改完实际 phase（预期仍是 Running，说明被丢弃）---"
kubectl get pod "$POD" -n "$NS" -o jsonpath='{.status.phase}'; echo

echo
echo "===== 3. resourceVersion 乐观锁：用过期 RV 更新 ====="
RV=$(kubectl get pod "$POD" -n "$NS" -o jsonpath='{.metadata.resourceVersion}')
echo "当前 RV=$RV"
echo "--- 用 RV-1 的过期值尝试更新容器镜像 ---"
OLD=$((RV - 1))
kubectl patch pod "$POD" -n "$NS" --type=merge \
  -p "{\"metadata\":{\"resourceVersion\":\"$OLD\"},\"spec\":{\"containers\":[{\"name\":\"app\",\"image\":\"nginx:alpine\"}]}}" \
  2>&1 | tail -2

echo
echo "===== 4. managedFields：谁改过哪些字段 ====="
kubectl get pod "$POD" -n "$NS" -o jsonpath='{range .metadata.managedFields[*]}manager={.manager} operation={.operation}{"\n"}{end}'

echo
echo "===== 5. uid / generation / creationTimestamp ====="
kubectl get pod "$POD" -n "$NS" -o jsonpath='uid={.metadata.uid}{"\n"}generation={.metadata.generation}{"\n"}created={.metadata.creationTimestamp}{"\n"}'

echo
echo "===== 6. 四段式里 apiVersion 的两种写法（core 组省略组名）====="
kubectl get pod "$POD" -n "$NS" -o jsonpath='pod.apiVersion={.apiVersion}{"\n"}'
kubectl get deployment -n kube-system coredns -o jsonpath='deploy.apiVersion={.apiVersion}{"\n"}' 2>/dev/null || \
  echo "(kube-system 无 coredns 可读，跳过)"

echo
echo "===== 7. 清单：本集群有哪些 API 组 ====="
kubectl api-versions 2>/dev/null | sed 's#/# / #' | head -30
