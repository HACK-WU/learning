#!/usr/bin/env bash
echo "=== FULL HEALTHZ (failed hooks only) ==="
docker exec k8s-c1-calico-control-plane bash -c 'curl -sk https://127.0.0.1:6443/healthz --max-time 8' 2>&1 | grep -E '^\[-\]' | sed 's/^/  /'
echo ""
echo "=== ETCD HEALTH ==="
docker exec k8s-c1-calico-control-plane bash -c 'curl -sk https://127.0.0.1:2379/health --max-time 5' 2>&1 | sed 's/^/  /'
echo ""
echo "=== ETCD MEMBER LIST ==="
docker exec k8s-c1-calico-control-plane bash -c 'ETCDCTL_API=3 etcdctl --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key endpoint health --cluster 2>&1 | head -5' 2>&1 | sed 's/^/  /'
echo ""
echo "=== APISERVER LOG (rbac errors) ==="
docker exec k8s-c1-calico-control-plane bash -c 'crictl logs $(crictl ps -a --name kube-apiserver -q 2>/dev/null | head -1) 2>&1 | tail -25' 2>&1 | grep -iE 'rbac|forbidden|bootstrap|error|timeout|etcd' | tail -12 | cut -c1-160 | sed 's/^/  /'
echo ""
echo "=== DISK on CP ==="
docker exec k8s-c1-calico-control-plane bash -c 'df -h /var/lib/etcd 2>/dev/null | tail -2' 2>&1 | sed 's/^/  /'
