#!/usr/bin/env bash
NS=blueking
echo "=== 1. 全集群 Pod 状态分桶 ==="
kubectl get pods -n $NS --no-headers 2>/dev/null | awk '{print $3}' | sort | uniq -c | sort -rn

echo ""
echo "=== 2. CrashLoop 残留 ==="
kubectl get pods -n $NS --no-headers 2>/dev/null | awk '$3=="CrashLoopBackOff"||$3=="Error"||$3=="Init:0/1"{print "  "$0}'
echo "  (以上为空则全部自愈)"

echo ""
echo "=== 3. 页面实测 ==="
for d in bkmonitor.paas.example.com paas.example.com bkpaas.paas.example.com bkcmdb.paas.example.com bkiam.paas.example.com bkuser.paas.example.com bknodeman.paas.example.com apigw.paas.example.com; do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://$d/" 2>/dev/null)
  printf "  %-32s %s\n" "$d" "$code"
done

echo ""
echo "=== 4. 监控 API 真实调用（不是只看 Pod） ==="
# healthz
echo "  --- healthz ---"
kubectl exec -n $NS deploy/bk-monitor-healthz -- curl -s --max-time 8 http://127.0.0.1:10205/healthz 2>&1 | head -3

echo ""
echo "  --- unify-query 存活 ---"
kubectl exec -n $NS deploy/bk-monitor-unify-query -- curl -s -o /dev/null -w '    HTTP %{http_code}\n' --max-time 8 http://127.0.0.1:8080/healthz 2>&1 | head -2

echo ""
echo "=== 5. kafka 消费组（证明监控数据真在流转） ==="
kubectl exec -n $NS bk-kafka-0 -- kafka-consumer-groups.sh --list --bootstrap-server localhost:9092 2>&1 | grep -c bkmonitorv3 | sed 's/^/  bkmonitorv3 消费组数: /'

echo ""
echo "=== 6. 内存 ==="
free -g | sed -n '1,2p'
