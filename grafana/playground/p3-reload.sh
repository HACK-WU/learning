#!/bin/bash
set -u
echo "=== 1. 重载 Grafana（使修正后的模板语法生效）==="
docker restart p3-grafana >/dev/null 2>&1
for i in $(seq 1 40); do
  R=$(curl -s --noproxy '*' -m 3 http://localhost:3130/api/health | tr -d ' \n')
  if [ -n "$R" ]; then echo "  ready at ${i}x2s"; break; fi
  sleep 2
done
echo

echo "=== 2. 确认规则里的模板已更新 ==="
curl -s --noproxy '*' -u admin:admin http://localhost:3130/api/v1/provisioning/alert-rules 2>&1 \
 | python3 -c "
import sys,json
d=json.load(sys.stdin)
for r in d:
    print('  ', r['uid'])
    print('      summary:', r.get('annotations',{}).get('summary',''))
"
echo

echo "=== 3. 清空旧告警文件 ==="
rm -f /mnt/d/projects/learning/grafana/projects/从告警到定位/实现/webhook/out/*.json 2>/dev/null
echo "  cleared"
echo

echo "=== 4. 等 120 秒，让告警重新触发（新模板）==="
sleep 120
echo "  done"
echo

echo "=== 5. 看 webhook 收到的 summary 是否渲染 ==="
docker logs p3-webhook 2>&1 | grep 'summary' | tail -6
echo

echo "=== 6. 落盘文件 ==="
python3 - <<'PYEOF'
import json, glob
fs = sorted(glob.glob('/mnt/d/projects/learning/grafana/projects/从告警到定位/实现/webhook/out/*.json'))
print('  文件数 =', len(fs))
for f in fs:
    d = json.load(open(f))
    for a in d.get('alerts', []):
        print('  ', a.get('labels', {}).get('alertname'))
        print('      summary:', a.get('annotations', {}).get('summary', ''))
PYEOF
