#!/bin/bash
echo "=== 1. healthz=400 排查 ==="
echo "  /healthz 响应体:"
curl -s http://localhost:8880/healthz 2>/dev/null | head -c 300
echo
echo "  相关日志:"
docker logs vmalert-learn 2>&1 | grep -iE "notifier|alertmanager|health" | tail -5 | sed 's/^/    /'
echo
echo "  --- 逐个检查依赖组件可达性 ---"
for u in "http://vmsel-dedup:8481/select/0/prometheus/health" "http://alertmanager-learn:9093/-/ready" "http://vminsert-learn:8480/health"; do
  code=$(docker exec vmalert-learn sh -c "wget -qO- --timeout=5 -S $u 2>&1 | grep -oE 'HTTP/[0-9.]+ [0-9]+' | tail -1" 2>/dev/null)
  echo "     $u -> $code"
done

echo
echo "=== 2. 告警完整链路复验：触发 TargetDown ==="
echo "  停止 vm-learn（vmsingle job 目标）"
docker stop vm-learn >/dev/null 2>&1
echo "     $(date +%H:%M:%S) STOPPED"

for i in $(seq 1 16); do
  sleep 5
  st=$(curl -s http://localhost:8880/api/v1/alerts 2>/dev/null | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin); al=d['data']['alerts']
    print('; '.join('%s=%s' % (a.get('name'), a.get('state')) for a in al) if al else '无')
except: print('ERR')
" 2>/dev/null)
  am=$(curl -s http://localhost:9093/api/v2/alerts 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null)
  upv=$(curl -s "http://localhost:8481/select/0/prometheus/api/v1/query?query=up%7Bjob%3D%22vmsingle%22%7D" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin); rs=d['data']['result']
print(','.join(r['value'][1] for r in rs) if rs else 'none')
" 2>/dev/null)
  echo "    T+${i}x5s up(vmsingle)=${upv:0:6} vmalert=[$st] AM=$am"
done

echo
echo "=== 3. 恢复 ==="
docker start vm-learn >/dev/null 2>&1
echo "     $(date +%H:%M:%S) STARTED"
for i in $(seq 1 10); do
  sleep 5
  st=$(curl -s http://localhost:8880/api/v1/alerts 2>/dev/null | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin); al=d['data']['alerts']
    print('; '.join('%s=%s' % (a.get('name'), a.get('state')) for a in al) if al else '无')
except: print('ERR')
" 2>/dev/null)
  am=$(curl -s http://localhost:9093/api/v2/alerts 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null)
  echo "    R+${i}x5s vmalert=[$st] AM=$am"
done

echo
echo "=== 4. 告警计数指标 ==="
curl -s http://localhost:8880/metrics 2>/dev/null | grep -E "^vmalert_alerts_(fired|sent|pending|error)_total|^vmalert_alertmanager" | grep -v "^#" | head -12
