set +x
PROM=http://localhost:9094

echo "########## Firing -> Inactive 恢复路径 ##########"

echo "=== 1) 先注入 50% 错误率，让告警到 firing ==="
docker exec l4-app python3 -c "
import urllib.request
print(urllib.request.urlopen('http://localhost:8080/fault/on?rate=0.5').read().decode())
"
echo "等待 45 秒（跨过 for=20s 并稳定）"
sleep 45
curl -s "$PROM/api/v1/alerts" | python3 -c "
import json,sys
d = json.load(sys.stdin)['data']['alerts']
print('  当前告警:')
for a in d:
    print('    %-22s %s' % (a['labels'].get('alertname'), a['state']))
"

echo
echo "=== 2) 恢复故障（错误率归零），观察状态变化 ==="
docker exec l4-app python3 -c "
import urllib.request
print(urllib.request.urlopen('http://localhost:8080/fault/off').read().decode())
"

echo "每 3 秒采样一次，共 40 秒"
for i in $(seq 1 14); do
  out=$(curl -s "$PROM/api/v1/alerts" | python3 -c "
import json,sys
d = json.load(sys.stdin)['data']['alerts']
m = {a['labels'].get('alertname'): a['state'] for a in d}
print('Wobble=%-8s Critical=%-8s' % (m.get('L4ErrorRateWobble','-'), m.get('L4HighErrorRate','-')))
")
  val=$(curl -s -G "$PROM/api/v1/query" \
    --data-urlencode 'query=job:app_requests_error:ratio1m' \
    | python3 -c "
import json,sys
r = json.load(sys.stdin)['data']['result']
print('%.4f' % float(r[0]['value'][1]) if r else 'n/a')
")
  echo "  t=$((i*3))s  ratio1m=$val  $out"
  sleep 3
done

echo
echo "=== 3) 关键观察 ==="
echo "  - for=0s 的告警：条件一不满足就立刻消失（无恢复保护）"
echo "  - for=20s 的告警：同样立刻消失——for 只在 Pending->Firing 生效"
echo "  - 若要做'恢复保护'，需要 keep_firing_for（本课后续说明）"
