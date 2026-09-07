#!/bin/bash
set -u
W=/mnt/d/projects/learning/grafana/projects/从告警到定位
echo "########## 验证模板渲染：用一条新告警（不影响现有告警状态）##########"
echo
echo "思路：repeat_interval=5~10m，现有告警不会立刻重发。"
echo "     所以新建一条【必定触发】的临时规则，看它的 summary 是否渲染。"
echo

echo "=== 1. 建临时规则（up==1 恒真，阈值 gt 0 → 必然触发）==="
curl -s --noproxy '*' -u admin:admin -X POST http://localhost:3130/api/v1/provisioning/alert-rules \
  -H 'Content-Type: application/json' \
  -d '{"uid":"tmp-tpl-test","title":"[TMP] 模板渲染验证","folderUID":"","ruleGroup":"tpl-verify","orgId":1,"condition":"C","noDataState":"OK","execErrState":"Error","for":"0s","isPaused":false,"annotations":{"summary":"渲染验证：route={{ .Labels.route }} 当前值={{ humanize .Value }}","description":"临时规则，验证完即删"},"labels":{"severity":"warning","team":"shop","signal":"tmp"},"data":[{"refId":"A","relativeTimeRange":{"from":300,"to":0},"datasourceUid":"shop-prom","model":{"editorMode":"code","expr":"up{job=\"shop\"}","instant":false,"intervalMs":1000,"maxDataPoints":43200}},{"refId":"B","relativeTimeRange":{"from":300,"to":0},"datasourceUid":"-100","model":{"type":"reduce","reducer":"last","expression":"A"}},{"refId":"C","relativeTimeRange":{"from":0,"to":0},"datasourceUid":"-100","model":{"type":"threshold","expression":"B","conditions":[{"type":"query","evaluator":{"type":"gt","params":[0]}}]}}]}' \
  -o /dev/null -w '  create=%{http_code}\n'
echo

echo "=== 2. 等 45 秒（for=0s + group_wait 10s + 求值周期）==="
sleep 45
echo "  done"
echo

echo "=== 3. 看新告警的 summary 是否渲染 ==="
docker logs p3-webhook 2>&1 | grep -A6 'TMP' | tail -20
echo

echo "=== 4. 直接看落盘文件 ==="
python3 -c "
import json,glob
fs=sorted(glob.glob('$W/实现/webhook/out/*.json'))
print('  文件数 =', len(fs))
for f in fs[-2:]:
    d=json.load(open(f))
    for a in d.get('alerts',[]):
        n=a.get('labels',{}).get('alertname','')
        s=a.get('annotations',{}).get('summary','')
        print('  ', n)
        print('     summary:', s)
" 2>&1
echo

echo "=== 5. 清理临时规则 ==="
curl -s --noproxy '*' -u admin:admin -X DELETE http://localhost:3130/api/v1/provisioning/alert-rules/tmp-tpl-test -o /dev/null -w '  delete=%{http_code}\n'
