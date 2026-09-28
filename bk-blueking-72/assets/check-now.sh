#!/usr/bin/env bash
echo "=== 1. 节点 ==="
kubectl get nodes --no-headers 2>&1 | sed 's/^/  /'
echo ""
echo "=== 2. Pod ==="
echo "  总数:        $(kubectl get pods -n blueking --no-headers 2>/dev/null | wc -l)"
echo "  Terminating: $(kubectl get pods -n blueking --no-headers 2>/dev/null | awk '$3=="Terminating"' | wc -l)"
echo "  CrashLoop:   $(kubectl get pods -n blueking --no-headers 2>/dev/null | awk '$3=="CrashLoopBackOff"' | wc -l)"
echo ""
echo "=== 3. 内存 / PSI ==="
free -g | sed -n '1,2p' | sed 's/^/  /'
cat /proc/pressure/memory 2>/dev/null | sed 's/^/  /'
echo ""
echo "=== 4. kind 容器 ==="
docker stats --no-stream --format '{{.Name}} {{.MemUsage}}' 2>/dev/null | grep calico | sed 's/^/  /'
echo ""
echo "=== 5. 页面可达性（流程走通的核心证据） ==="
for d in paas.example.com bkpaas.paas.example.com bkmonitor.paas.example.com bkrepo.paas.example.com bknodeman.paas.example.com bkiam.paas.example.com apigw.paas.example.com; do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "http://$d/" 2>/dev/null)
  printf "  %-32s %s\n" "$d" "$code"
done
