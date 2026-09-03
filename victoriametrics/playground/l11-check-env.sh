#!/bin/bash
echo "=== 1. 运行中的 VM 相关容器 ==="
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}' | grep -Ei "vm|prom|alert|grafana" || echo "(none)"

echo
echo "=== 2. 镜像是否已有 vmagent / vmalert / alertmanager ==="
docker images --format '{{.Repository}}:{{.Tag}}' | grep -Ei "vmagent|vmalert|alertmanager|victoria" || echo "(none)"

echo
echo "=== 3. 关键端口占用 (8429 vmagent, 8880 vmalert, 9093 alertmanager) ==="
for p in 8428 8429 8880 9093 9090 8480 8481 8427; do
  r=$(docker ps --format '{{.Ports}}' | grep -c ":$p->")
  echo "  port $p : $r"
done

echo
echo "=== 4. 数据目录 ==="
ls -d /mnt/d/projects/learning/victoriametrics/playground/cluster-data/* 2>/dev/null

echo
echo "=== 5. 磁盘剩余 ==="
df -h /mnt/d | tail -1
