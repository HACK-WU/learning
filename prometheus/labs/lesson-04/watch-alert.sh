set -x
BASE=/mnt/d/projects/learning/prometheus/labs/lesson-04
PROM=http://localhost:9094
APP=http://localhost:9094

# 应用端口未映射到宿主，需经容器网络访问
APP_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' l4-app)
echo "l4-app 容器 IP: $APP_IP"

echo "=== 阶段 0：当前状态（应无告警） ==="
curl -s -G "$PROM/api/v1/query" --data-urlencode 'query=ALERTS' | head -c 300
echo
curl -s -G "$PROM/api/v1/query" \
  --data-urlencode 'query=job:app_requests_error:ratio1m' | head -c 400
echo

echo
echo "=== 阶段 1：注入 50% 错误率 ==="
docker exec l4-app python3 -c "
import urllib.request
print(urllib.request.urlopen('http://localhost:8080/fault/on?rate=0.5').read().decode())
"

echo "等待 8 秒（< for=20s），应处于 Pending 而非 Firing"
sleep 8

echo "--- ALERTS_FOR_STATE（Pending 计时中） ---"
curl -s -G "$PROM/api/v1/query" --data-urlencode 'query=ALERTS_FOR_STATE'
echo
echo "--- ALERTS（应为空：还没到 Firing） ---"
curl -s -G "$PROM/api/v1/query" --data-urlencode 'query=ALERTS'
echo

echo
echo "=== 阶段 2：继续等待，跨过 for=20s ==="
sleep 25
echo "--- ALERTS（应出现 alertstate=firing） ---"
curl -s -G "$PROM/api/v1/query" --data-urlencode 'query=ALERTS'
echo
echo "--- ALERTS_FOR_STATE ---"
curl -s -G "$PROM/api/v1/query" --data-urlencode 'query=ALERTS_FOR_STATE'
echo

echo
echo "=== 阶段 3：/api/v1/alerts 查看完整状态机 ==="
curl -s "$PROM/api/v1/alerts" | python3 -c "
import json,sys
d = json.load(sys.stdin)['data']['alerts']
print('告警条数:', len(d))
for a in d:
    print('  name=%-22s state=%-9s activeAt=%s value=%s'
          % (a['labels'].get('alertname'), a['state'], a.get('activeAt','-'), a.get('value','-')))
"
