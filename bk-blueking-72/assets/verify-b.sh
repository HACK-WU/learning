#!/usr/bin/env bash
NS=blueking
echo "=== 等 90s 让 Pod 收缩 ==="
sleep 90

echo ""
echo "=== 1. 集群连通性 ==="
kubectl get nodes --no-headers 2>&1 | awk '{print "  "$1" "$2}'

echo ""
echo "=== 2. Pod 数量与异常 ==="
TOTAL=$(kubectl get pods -n $NS --no-headers 2>/dev/null | wc -l)
BAD=$(kubectl get pods -n $NS --no-headers 2>/dev/null | awk '$3!="Running"&&$3!="Completed"{c++}END{print c+0}')
echo "  Pod 总数: $TOTAL  (变更前 192)"
echo "  非Running: $BAD"

echo ""
echo "=== 3. 作废旧 Pod（Terminating 卡住） ==="
kubectl get pods -n $NS --no-headers 2>/dev/null | awk '$3=="Terminating"{print "  "$1}'

echo ""
echo "=== 4. WSL 内存与 PSI ==="
free -g | sed -n '1,2p' | sed 's/^/  /'
echo "  --- PSI (变更前 full avg10=73.47) ---"
cat /proc/pressure/memory 2>/dev/null | sed 's/^/  /'

echo ""
echo "=== 5. 页面可达性实测 ==="
for d in bkmonitor.paas.example.com bkpaas.paas.example.com bkrepo.paas.example.com bknodeman.paas.example.com paas.example.com bkiam.paas.example.com; do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "http://$d/" 2>/dev/null)
  echo "  $d -> $code"
done

echo ""
echo "=== 6. 确认保留的 4 个仍在跑 ==="
for d in bk-cmdb-monstache bk-monitor-web-beat bk-monitor-web-worker bk-monitor-healthz; do
  r=$(kubectl get deploy -n $NS $d -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  echo "  $d ready=$r"
done
