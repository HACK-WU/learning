#!/bin/bash
set -u
W=/mnt/d/projects/learning/grafana/projects/从告警到定位

echo "=== 0. 拿到文件夹 UID（上一步失败疑似 folderUID 为空）==="
FUID=$(curl -s --noproxy '*' -u admin:admin http://localhost:3130/api/folders 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
for f in d:
    print(f['uid'], f['title'])
" 2>&1 | grep 'Shop' | awk '{print $1}')
echo "  folderUID=$FUID"
echo

echo "=== 1. 建临时规则（带正确 folderUID）==="
curl -s --noproxy '*' -u admin:admin -X POST http://localhost:3130/api/v1/provisioning/alert-rules \
  -H 'Content-Type: application/json' \
  -d "{\"uid\":\"tmp-tpl-test\",\"title\":\"[TMP] 模板渲染验证\",\"folderUID\":\"$FUID\",\"ruleGroup\":\"tpl-verify\",\"orgId\":1,\"condition\":\"C\",\"noDataState\":\"OK\",\"execErrState\":\"Error\",\"for\":\"0s\",\"isPaused\":false,\"annotations\":{\"summary\":\"渲染验证：route={{ .Labels.route }} 当前值={{ humanize .Value }}\",\"description\":\"临时规则\"},\"labels\":{\"severity\":\"warning\",\"team\":\"shop\",\"signal\":\"tmp\"},\"data\":[{\"refId\":\"A\",\"relativeTimeRange\":{\"from\":300,\"to\":0},\"datasourceUid\":\"shop-prom\",\"model\":{\"editorMode\":\"code\",\"expr\":\"up{job=\\\"shop\\\"}\",\"instant\":false,\"intervalMs\":1000,\"maxDataPoints\":43200}},{\"refId\":\"B\",\"relativeTimeRange\":{\"from\":300,\"to\":0},\"datasourceUid\":\"-100\",\"model\":{\"type\":\"reduce\",\"reducer\":\"last\",\"expression\":\"A\"}},{\"refId\":\"C\",\"relativeTimeRange\":{\"from\":0,\"to\":0},\"datasourceUid\":\"-100\",\"model\":{\"type\":\"threshold\",\"expression\":\"B\",\"conditions\":[{\"type\":\"query\",\"evaluator\":{\"type\":\"gt\",\"params\":[0]}}]}}]}" \
  -o /tmp/tpl.json -w '  create=%{http_code}\n'
head -c 300 /tmp/tpl.json
echo
echo

echo "=== 2. 等 50 秒 ==="
sleep 50
echo

echo "=== 3. webhook 收到 TMP 告警了吗 ==="
docker logs p3-webhook 2>&1 | grep -B2 -A8 'TMP' | tail -25
echo

echo "=== 4. 落盘文件 ==="
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
