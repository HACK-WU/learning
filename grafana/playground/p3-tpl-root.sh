#!/bin/bash
echo "########## 查清 annotation 模板为何不渲染 ##########"
echo

echo "=== 1. 查 Grafana 官方文档说法 ==="
echo "  （先本机验证，再决定要不要联网）"
echo

echo "=== 2. 试标准 Go template 语法 {{ \$labels.route }} 在【通知模板】里 ==="
echo "  先看默认通知模板长什么样"
curl -s --noproxy '*' -u admin:admin http://localhost:3130/api/v1/provisioning/templates 2>&1 | head -c 400
echo
echo

echo "=== 3. 建一个通知模板，用它渲染 ==="
curl -s --noproxy '*' -u admin:admin -X PUT http://localhost:3130/api/v1/provisioning/templates/tpl-test \
  -H 'Content-Type: application/json' \
  -d '{"name":"tpl-test","template":"{{ define \"my.summary\" }}route={{ $labels.route }} value={{ humanize $values.B.Value }}{{ end }}"}' \
  -o /dev/null -w '  put=%{http_code}\n'
echo

echo "=== 4. 用 API 测试模板渲染（Grafana 有专门的测试接口吗）==="
curl -s --noproxy '*' -u admin:admin -X POST http://localhost:3130/api/v1/provisioning/templates/test \
  -H 'Content-Type: application/json' \
  -d '{"template":"{{ define \"t\" }}route={{ $labels.route }}{{ end }}","alerts":[{"labels":{"route":"/checkout"},"annotations":{}}]}' 2>&1 | head -c 400
echo
echo

echo "=== 5. 关键：annotation 是否【根本不支持】模板 ==="
echo "  Grafana 13 有个 feature toggle: alertingUIDenseIntervals / ... 先查全部 toggle"
curl -s --noproxy '*' -u admin:admin http://localhost:3130/api/frontend/settings 2>&1 | python3 -c "
import sys,json
d=json.load(sys.stdin)
ft=d.get('featureToggles',{})
for k,v in sorted(ft.items()):
    if 'templ' in k.lower() or 'alert' in k.lower(): print('   ', k, '=', v)
" 2>&1 | head -20
echo

echo "=== 6. 验证：把 annotation 写成纯 Go template 的 {{ .Labels }} 之外的写法 ==="
echo "  试 {{ index .Labels \"route\" }}"
curl -s --noproxy '*' -u admin:admin -X POST http://localhost:3130/api/v1/provisioning/alert-rules \
  -H 'Content-Type: application/json' \
  -d '{"uid":"tmp-t2","title":"[TMP2] index 语法测试","folderUID":"afxi23vi14lq8c","ruleGroup":"tpl-verify","orgId":1,"condition":"C","noDataState":"OK","execErrState":"Error","for":"0s","isPaused":false,"annotations":{"summary":"A={{ index .Labels \"route\" }} B={{ .Labels.route }} C={{ $labels.route }} D={{ humanize .Value }} E={{ printf \"%.2f\" .Value }}","description":"test"},"labels":{"severity":"critical","team":"shop","signal":"tmp"},"data":[{"refId":"A","relativeTimeRange":{"from":300,"to":0},"datasourceUid":"shop-prom","model":{"editorMode":"code","expr":"up{job=\"shop\"}","instant":false,"intervalMs":1000,"maxDataPoints":43200}},{"refId":"B","relativeTimeRange":{"from":300,"to":0},"datasourceUid":"-100","model":{"type":"reduce","reducer":"last","expression":"A"}},{"refId":"C","relativeTimeRange":{"from":0,"to":0},"datasourceUid":"-100","model":{"type":"threshold","expression":"B","conditions":[{"type":"query","evaluator":{"type":"gt","params":[0]}}]}}]}' \
  -o /dev/null -w '  create=%{http_code}\n'
echo "  等 90 秒看渲染结果"
sleep 90
docker logs p3-webhook 2>&1 | grep -A6 'TMP2' | tail -12
echo

echo "=== 7. 清理 ==="
curl -s --noproxy '*' -u admin:admin -X DELETE http://localhost:3130/api/v1/provisioning/alert-rules/tmp-t2 -o /dev/null -w '  delete=%{http_code}\n'
curl -s --noproxy '*' -u admin:admin -X DELETE http://localhost:3130/api/v1/provisioning/templates/tpl-test -o /dev/null -w '  tpl_delete=%{http_code}\n'
