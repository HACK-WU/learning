#!/bin/bash
set -u
echo "########## 按官方文档的正确写法验证 ##########"
echo "官方：range query 必须先 reduce（refId=B），然后用 index \$values \"B\""
echo "     {{ index \$labels \"route\" }} / {{ humanize (index \$values \"B\").Value }}"
echo

FUID=afxi23vi14lq8c

echo "=== 1. 建规则：用 index 语法 + reduce(B) ==="
curl -s --noproxy '*' -u admin:admin -X POST http://localhost:3130/api/v1/provisioning/alert-rules \
  -H 'Content-Type: application/json' \
  -d "{\"uid\":\"tmp-t3\",\"title\":\"[TMP3] 官方写法\",\"folderUID\":\"$FUID\",\"ruleGroup\":\"tpl-verify\",\"orgId\":1,\"condition\":\"C\",\"noDataState\":\"OK\",\"execErrState\":\"Error\",\"for\":\"0s\",\"isPaused\":false,\"annotations\":{\"summary\":\"route={{ index \$labels \"route\" }} value={{ humanize (index \$values \"B\").Value }}\",\"description\":\"按官方文档写法\"},\"labels\":{\"severity\":\"critical\",\"team\":\"shop\",\"signal\":\"tmp\"},\"data\":[{\"refId\":\"A\",\"relativeTimeRange\":{\"from\":300,\"to\":0},\"datasourceUid\":\"shop-prom\",\"model\":{\"editorMode\":\"code\",\"expr\":\"sum by (route) (rate(shop_requests_total[2m]))\",\"instant\":false,\"intervalMs\":1000,\"maxDataPoints\":43200}},{\"refId\":\"B\",\"relativeTimeRange\":{\"from\":300,\"to\":0},\"datasourceUid\":\"-100\",\"model\":{\"type\":\"reduce\",\"reducer\":\"last\",\"expression\":\"A\"}},{\"refId\":\"C\",\"relativeTimeRange\":{\"from\":0,\"to\":0},\"datasourceUid\":\"-100\",\"model\":{\"type\":\"threshold\",\"expression\":\"B\",\"conditions\":[{\"type\":\"query\",\"evaluator\":{\"type\":\"gt\",\"params\":[0]}}]}}]}" \
  -o /dev/null -w '  create=%{http_code}\n'
echo

echo "=== 2. 等 100 秒 ==="
sleep 100
echo "  done"
echo

echo "=== 3. 看渲染结果 ==="
docker logs p3-webhook 2>&1 | grep -A6 'TMP3' | tail -12
echo

echo "=== 4. 清理 ==="
curl -s --noproxy '*' -u admin:admin -X DELETE http://localhost:3130/api/v1/provisioning/alert-rules/tmp-t3 -o /dev/null -w '  delete=%{http_code}\n'
