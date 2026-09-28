#!/usr/bin/env bash
# 用途：算清资源账——从镜像清单看要跑多少组件，对照你的 20核47G
set -uo pipefail
F=/root/bk72/chart-images/blueking/chart-images.txt
E=/root/bk72/install/blueking/environments/default

echo "===== 1. 组件规模 ====="
echo "chart 数量: $(wc -l < "$F")"
echo "自研镜像数: $(grep -o 'blueking/' "$F" | wc -l)"
echo "涉及产品: $(cut -f1 "$F" | tr '\n' ' ')"

echo ""
echo "===== 2. 你的机器资源 ====="
echo "CPU 核数: $(nproc)"
free -h | head -2
echo "可用磁盘:"; df -h / 2>/dev/null | tail -1

echo ""
echo "===== 3. 基础存储层组件（内存大头）====="
for c in mysql redis mongodb elasticsearch kafka influxdb etcd consul zookeeper rabbitmq; do
  n=$(grep -c "^$c	" "$F" 2>/dev/null)
  [ "$n" -gt 0 ] && echo "  $c: 在清单中"
done

echo ""
echo "===== 4. K8s 集群现状 ====="
kubectl get nodes -o wide 2>/dev/null | head -5
echo "---"
kubectl top nodes 2>/dev/null | head -5 || echo "(metrics-server 未装，无实时用量)"
