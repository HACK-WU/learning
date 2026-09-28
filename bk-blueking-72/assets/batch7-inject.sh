#!/usr/bin/env bash
NS=blueking
MARK="BATCH7-$(date +%s)"

echo "标记: $MARK"
echo ""
echo "=== 1. transfer 是否在收数据（http 10202） ==="
kubectl run ct7 --rm -i --restart=Never --image=curlimages/curl:8.5.0 -n $NS -- \
  curl -s --max-time 10 'http://bk-monitor-transfer-default:10202/v2/ping' -w ' HTTP=%{http_code}\n' 2>&1 | tail -2

echo ""
echo "=== 2. 往 transfer 推一条真实指标（模拟 agent 上报） ==="
kubectl run cs7 --rm -i --restart=Never --image=curlimages/curl:8.5.0 -n $NS -- \
  curl -s --max-time 15 -X POST 'http://bk-monitor-transfer-default:10202/v2/push/' \
  -H 'Content-Type: application/json' \
  -d "{\"data_id\":1001,\"data\":[{\"metrics\":{\"usage\":99.5,\"mark\":\"$MARK\"},\"target\":\"127.0.0.1\",\"dimension\":{\"bk_target_ip\":\"127.0.0.1\"},\"timestamp\":$(date +%s)000}]}" \
  -w '\n  HTTP=%{http_code}\n' 2>&1 | tail -3

echo ""
echo "=== 3. 看 transfer 有没有接住 ==="
kubectl logs -n $NS -l app.kubernetes.io/name=bk-monitor-transfer-default --tail=20 2>&1 | tail -4 | cut -c1-180

echo ""
echo "=== 4. 等 30s 看 detect 有没有反应 ==="
sleep 30
pod=$(kubectl get pod -n $NS --no-headers 2>/dev/null | grep '^bk-monitor-alarm-detect-' | head -1 | awk '{print $1}')
kubectl logs -n $NS $pod --tail=30 2>&1 | grep -iE 'detect|strategy' | tail -4 | cut -c1-180

echo ""
echo "=== 5. 清理 ==="
kubectl delete pod -n $NS ct7 cs7 >/dev/null 2>&1
echo "  done"
