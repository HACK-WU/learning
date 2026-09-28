#!/usr/bin/env bash
echo "=== 1. WSL 实际资源 ==="
free -h | head -2
echo "CPU: $(nproc) 核"
echo "磁盘: $(df -h / | tail -1 | awk '{print $4}') 可用"

echo ""
echo "=== 2. 7.2 镜像源 hub.bktencent.com 连通性 ==="
getent hosts hub.bktencent.com || echo "(解析失败)"
timeout 20 curl -sS -o /dev/null -w "hub.bktencent.com HTTP=%{http_code}\n" https://hub.bktencent.com 2>&1

echo ""
echo "=== 3. 中控机需要的文件站 bkopen-1252002024.file.myqcloud.com ==="
timeout 20 curl -sS -o /dev/null -w "bkopen file.myqcloud HTTP=%{http_code}\n" https://bkopen-1252002024.file.myqcloud.com 2>&1

echo ""
echo "=== 4. 尝试拉取 7.2 一个镜像 (探测是否被掐) ==="
timeout 180 docker pull hub.bktencent.com/blueking/centos7:latest >/tmp/bk72probe.log 2>&1 \
  && echo "PULL OK" || { echo "PULL FAILED:"; tail -4 /tmp/bk72probe.log; }

echo ""
echo "=== 5. 已有 k8s 集群 (kind/k3s/kubeasz) ==="
kubectl get nodes 2>/dev/null | head -5 || echo "(无 kubectl 或集群)"
docker ps --format '{{.Names}}' | grep -iE 'kind|k3s|k8s' | head -5
