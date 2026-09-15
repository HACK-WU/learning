#!/usr/bin/env bash
echo "===== 按顺序清理：先删注册表类对象，再删 ns ====="
kubectl delete apiservice v1.hello.example.com --ignore-not-found 2>&1 | tail -1
kubectl delete ns aggregator --ignore-not-found 2>&1 | tail -1
kubectl delete clusterrole hello-apiserver-auth-delegator --ignore-not-found 2>&1 | tail -1
kubectl delete clusterrolebinding hello-apiserver-auth-delegator --ignore-not-found 2>&1 | tail -1
kubectl delete clusterrolebinding hello-apiserver-system-auth-delegator --ignore-not-found 2>&1 | tail -1

echo
echo "===== 等待 ns 消失 ====="
for i in $(seq 1 20); do
  kubectl get ns aggregator >/dev/null 2>&1 || { echo "  ✓ 已删除"; break; }
  sleep 2
done

echo
echo "===== 最终状态核对 ====="
echo "  节点:"; kubectl get nodes --no-headers 2>/dev/null | awk '{print "    "$1,$2}'
echo "  非内置 APIService:"
kubectl get apiservice --no-headers 2>/dev/null | grep -vE "^\s*$" | awk '$2 !~ /^Local$/ {print "    "$1,$2,$3}'
echo "  外部 webhook:"
kubectl get validatingwebhookconfigurations --no-headers 2>/dev/null | awk '{print "    "$1}'
kubectl get mutatingwebhookconfigurations --no-headers 2>/dev/null | awk '{print "    "$1}'
echo "  残留 PV/PVC:"
echo -n "    PV="; kubectl get pv --no-headers 2>/dev/null | wc -l
echo -n "    PVC="; kubectl get pvc -A --no-headers 2>/dev/null | wc -l
echo "  命名空间:"
kubectl get ns --no-headers 2>/dev/null | awk '{print "    "$1}'
