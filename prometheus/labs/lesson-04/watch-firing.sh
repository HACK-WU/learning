set -x
PROM=http://localhost:9094

echo "=== 阶段 4：等待 L4HighErrorRate 跨过 for=20s ==="
sleep 20
curl -s "$PROM/api/v1/alerts" | python3 -c "
import json,sys
d = json.load(sys.stdin)['data']['alerts']
for a in d:
    print('  name=%-22s state=%-9s activeAt=%s'
          % (a['labels'].get('alertname'), a['state'], a.get('activeAt','-')))
"

echo
echo "=== 阶段 5：注入 wobble 振荡（演示抖动） ==="
docker exec l4-app python3 -c "
import urllib.request
print(urllib.request.urlopen('http://localhost:8080/fault/wobble?center=0.08&period=24&amp=0.04').read().decode())
"
echo "错误率将在 0.04 ~ 0.12 之间振荡，跨越 0.05(wobble阈值) 和 0.1(critical阈值)"
echo "观察 40 秒内 L4ErrorRateWobble（for=0s）的状态翻转次数"

STATE_PREV=""
for i in $(seq 1 20); do
  sleep 2
  cur=$(curl -s "$PROM/api/v1/alerts" | python3 -c "
import json,sys
d = json.load(sys.stdin)['data']['alerts']
parts = []
for a in d:
    parts.append('%s=%s' % (a['labels'].get('alertname'), a['state']))
print(' '.join(sorted(parts)))
")
  echo "  t=$((i*2))s  $cur"
done
