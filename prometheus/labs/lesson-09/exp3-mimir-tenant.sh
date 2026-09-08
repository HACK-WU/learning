#!/usr/bin/env bash
# Mimir 多租户隔离决定性实验
# 用一个 remote write 端点、靠 X-Scope-OrgID 头区分租户
set -uo pipefail
NET=l9net
M=http://l9-mimir:8080

echo "############ 1. 无租户头写入（应被拒绝 401）############"
docker run --rm --network $NET curlimages/curl:latest -s -o /dev/null -w '   HTTP %{http_code}\n' \
  -X POST "$M/api/v1/push" \
  -H 'Content-Type: application/x-protobuf' \
  --data-binary '' 2>/dev/null

echo
echo "############ 2. 两个租户分别写入不同值 ############"
# 用 Prometheus remote write 更真实：起两个 Prometheus 分别 remote write 到 Mimir
# 这里先用原生 Prometheus 文本 -> remote write 走不通，改用 Mimir 自带的 prometheus 远端写
# 简化：直接起两个 Prometheus，配置 remote_write + headers
echo "   (使用 Prometheus remote_write，见 setup-mimir-tenants.sh)"

echo
echo "############ 3. 租户隔离验证：各自只能查到自己的数据 ############"
for t in tenantA tenantB; do
  echo "  -- 租户 $t 查 app_requests_total --"
  docker run --rm --network $NET curlimages/curl:latest -s -G \
    -H "X-Scope-OrgID: $t" \
    --data-urlencode 'query=count(app_requests_total)' \
    "$M/prometheus/api/v1/query" 2>/dev/null \
  | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    rs=d.get('data',{}).get('result',[])
    if rs: print('     count = %s' % rs[0]['value'][1])
    else:  print('     无数据 (status=%s)' % d.get('status'))
except Exception as e: print('     ERR %s' % e)
"
done

echo
echo "############ 4. 无租户头查询（应 401）############"
docker run --rm --network $NET curlimages/curl:latest -s -o /dev/null -w '   HTTP %{http_code}\n' \
  -G --data-urlencode 'query=up' "$M/prometheus/api/v1/query" 2>/dev/null

echo
echo "############ 5. Mimir 版本与模块 ############"
docker run --rm --network $NET curlimages/curl:latest -s \
  "$M/api/v1/status/buildinfo" 2>/dev/null | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)['data']
    print('   version=%s  revision=%s' % (d.get('version'), str(d.get('revision'))[:12]))
except Exception as e: print('   ERR', e)
"
