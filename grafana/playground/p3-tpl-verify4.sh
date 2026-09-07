#!/bin/bash
set -u
W=/mnt/d/projects/learning/grafana/projects/从告警到定位
FUID=afxi23vi14lq8c

echo "=== 1. 重建临时规则 ==="
curl -s --noproxy '*' -u admin:admin -X POST http://localhost:3130/api/v1/provisioning/alert-rules \
  -H 'Content-Type: application/json' \
  -d "{\"uid\":\"tmp-tpl-test\",\"title\":\"[TMP] 模板渲染验证\",\"folderUID\":\"$FUID\",\"ruleGroup\":\"tpl-verify\",\"orgId\":1,\"condition\":\"C\",\"noDataState\":\"OK\",\"execErrState\":\"Error\",\"for\":\"0s\",\"isPaused\":false,\"annotations\":{\"summary\":\"渲染验证：route={{ .Labels.route }} 当前值={{ humanize .Value }}\",\"description\":\"临时规则\"},\"labels\":{\"severity\":\"critical\",\"team\":\"shop\",\"signal\":\"tmp\"},\"data\":[{\"refId\":\"A\",\"relativeTimeRange\":{\"from\":300,\"to\":0},\"datasourceUid\":\"shop-prom\",\"model\":{\"editorMode\":\"code\",\"expr\":\"up{job=\\\"shop\\\"}\",\"instant\":false,\"intervalMs\":1000,\"maxDataPoints\":43200}},{\"refId\":\"B\",\"relativeTimeRange\":{\"from\":300,\"to\":0},\"datasourceUid\":\"-100\",\"model\":{\"type\":\"reduce\",\"reducer\":\"last\",\"expression\":\"A\"}},{\"refId\":\"C\",\"relativeTimeRange\":{\"from\":0,\"to\":0},\"datasourceUid\":\"-100\",\"model\":{\"type\":\"threshold\",\"expression\":\"B\",\"conditions\":[{\"type\":\"query\",\"evaluator\":{\"type\":\"gt\",\"params\":[0]}}]}}]}" \
  -o /dev/null -w '  create=%{http_code}\n'
echo

echo "=== 2. 每 20 秒查一次规则状态，最多等 140 秒 ==="
for i in $(seq 1 7); do
  sleep 20
  ST=$(curl -s --noproxy '*' -u admin:admin 'http://localhost:3130/api/ruler/grafana/api/v1/rules' 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
for g in d.get('data',{}).get('groups',[]):
    for r in g.get('rules',[]):
        if 'TMP' in r.get('name',''):
            print(r.get('state'), r.get('health'), 'alerts=', len(r.get('alerts',[])))
" 2>/dev/null)
  echo "  ${i}x20s: ${ST:-（未找到）}"
  if echo "$ST" | grep -q 'alerts= [1-9]\|alerts=1\|Firing'; then echo "  ✅ 已触发"; break; fi
done
echo

echo "=== 3. webhook 日志（最后 30 行）==="
docker logs p3-webhook 2>&1 | tail -30
echo

echo "=== 4. 落盘 ==="
python3 -c "
import json,glob
fs=sorted(glob.glob('$W/实现/webhook/out/*.json'))
print('  文件数 =', len(fs))
for f in fs:
    d=json.load(open(f))
    for a in d.get('alerts',[]):
        print('  ', a.get('labels',{}).get('alertname'))
        print('     summary:', a.get('annotations',{}).get('summary'))
" 2>&1
echo

echo "=== 5. 清理 ==="
curl -s --noproxy '*' -u admin:admin -X DELETE http://localhost:3130/api/v1/provisioning/alert-rules/tmp-tpl-test -o /dev/null -w '  delete=%{http_code}\n'
