#!/bin/bash
echo "=== 1. 高频轮询：停止目标后每 5 秒看一次告警状态 ==="
docker stop vm-learn >/dev/null 2>&1
echo "  $(date +%H:%M:%S) vm-learn STOPPED"

for i in $(seq 1 14); do
  sleep 5
  st=$(curl -s http://localhost:8880/api/v1/alerts 2>/dev/null | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    al=d['data']['alerts']
    if not al: print('无')
    else:
        print('; '.join('%s=%s' % (a.get('name'), a.get('state')) for a in al))
except: print('ERR')
" 2>/dev/null)
  am=$(curl -s http://localhost:9093/api/v2/alerts 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null)
  up=$(curl -s "http://localhost:8481/select/0/prometheus/api/v1/query?query=up%7Bjob%3D%22vmsingle%22%7D" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
rs=d['data']['result']
print(','.join(r['value'][1] for r in rs) if rs else 'none')
" 2>/dev/null)
  echo "    T+${i}x5s  up(vmsingle)=${up:0:12}  vmalert=[$st]  AM=$am"
done

echo
echo "=== 2. 恢复并继续观察 ==="
docker start vm-learn >/dev/null 2>&1
echo "  $(date +%H:%M:%S) vm-learn STARTED"
for i in $(seq 1 8); do
  sleep 5
  st=$(curl -s http://localhost:8880/api/v1/alerts 2>/dev/null | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    al=d['data']['alerts']
    print('; '.join('%s=%s' % (a.get('name'), a.get('state')) for a in al) if al else '无')
except: print('ERR')
" 2>/dev/null)
  am=$(curl -s http://localhost:9093/api/v2/alerts 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null)
  echo "    R+${i}x5s  vmalert=[$st]  AM=$am"
done

echo
echo "=== 3. Alertmanager 收到的告警明细（含 resolved）==="
curl -s "http://localhost:9093/api/v2/alerts?active=true&silenced=false" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('  当前活跃:', len(d))
for a in d[:6]:
    lbl=a.get('labels',{})
    print('     %-22s job=%-12s state=%s' % (lbl.get('alertname'), lbl.get('job'), a.get('status',{}).get('state')))
" 2>/dev/null
