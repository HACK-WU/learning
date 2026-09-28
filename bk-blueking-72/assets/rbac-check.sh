#!/usr/bin/env bash
echo "=== RBAC DIAGNOSIS ==="
echo "--- current context/user ---"
kubectl config view --minify 2>&1 | grep -E 'user|cluster|server' | sed 's/^/  /'
echo ""
echo "--- whoami ---"
kubectl auth whoami 2>&1 | head -8 | sed 's/^/  /'
echo ""
echo "--- cluster-admin binding ---"
kubectl get clusterrolebinding --no-headers 2>&1 | grep -iE 'admin|kubernetes-admin' | head -10 | sed 's/^/  /'
echo ""
echo "--- can-i (as current user) ---"
kubectl auth can-i list nodes 2>&1 | sed 's/^/  /'
kubectl auth can-i list pods -n blueking 2>&1 | sed 's/^/  /'
kubectl auth can-i '*' '*' 2>&1 | sed 's/^/  superuser: /'
echo ""
echo "--- kubeconfig file ---"
echo "  KUBECONFIG=${KUBECONFIG:-unset}"
ls -la ~/.kube/config 2>&1 | sed 's/^/  /'
echo ""
echo "--- apiserver pod status ---"
kubectl get pods -n kube-system --no-headers 2>&1 | grep -E 'apiserver|etcd' | head -5 | sed 's/^/  /'
