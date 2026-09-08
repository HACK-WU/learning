set +x
PROM=http://localhost:9094

echo "########## keep_firing_for：恢复保护 ##########"
echo "对比 L4ErrorRateWobble(for=0s) 与 L4ErrorRateKeepFiring(keep_firing_for=30s)"
echo "两者阈值相同(>0.05)、for 相同(0s)，唯一差别是 keep_firing_for"
echo

echo "=== 1) 注入故障，让两条都 firing ==="
docker exec l4-app python3 -c "
import urllib.request
print(urllib.request.urlopen('http://localhost:8080/fault/on?rate=0.5').read().decode())
"
sleep 30
curl -s "$PROM/api/v1/alerts" | python3 -c "
import json,sys
d = json.load(sys.stdin)['data']['alerts']
for a in d:
    print('  %-24s %s' % (a['labels'].get('alertname'), a['state']))
"

echo
echo "=== 2) 关掉故障，观察两条告警的'存活'差异 ==="
docker exec l4-app python3 -c "
import urllib.request
print(urllib.request.urlopen('http://localhost:8080/fault/off').read().decode())
"

echo "每 5 秒采样，共 80 秒"
echo "预期：Wobble 条件不满足立刻消失；KeepFiring 会多撑约 30 秒"
echo

START=$(date +%s)
for i in $(seq 1 16); do
  out=$(curl -s "$PROM/api/v1/alerts" | python3 -c "
import json,sys
d = json.load(sys.stdin)['data']['alerts']
m = {a['labels'].get('alertname'): a['state'] for a in d}
print('%s|%s' % (m.get('L4ErrorRateWobble','-'), m.get('L4ErrorRateKeepFiring','-')))
")
  val=$(curl -s -G "$PROM/api/v1/query" \
    --data-urlencode 'query=job:app_requests_error:ratio1m' \
    | python3 -c "
import json,sys
r = json.load(sys.stdin)['data']['result']
print('%.4f' % float(r[0]['value'][1]) if r else 'n/a')
")
  w=$(echo "$out" | cut -d'|' -f1)
  k=$(echo "$out" | cut -d'|' -f2)
  now=$(date +%s)
  echo "  t=$((now-START))s  ratio1m=$val  Wobble=$w  KeepFiring=$k"
  sleep 5
done

echo
echo "=== 3) 结论 ==="
echo "  keep_firing_for 让告警在'条件已恢复'后仍保持 firing 指定时长"
echo "  用途：避免在阈值附近快速翻转（flapping），给下游系统一个稳定窗口"
