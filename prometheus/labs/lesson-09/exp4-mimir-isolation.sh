#!/usr/bin/env bash
# 决定性对照：Mimir 的租户隔离是"真的隔离"还是"看起来隔离"
# 手法：两个租户写入的数据带不同的 external label（tenant=tenantA / tenantB）
#       若隔离生效，各租户只能看到自己的 label 值，且总序列数应为"自己那份"
set -uo pipefail
NET=l9net
M=http://l9-mimir:8080

q() { # $1=tenant $2=query
  docker run --rm --network $NET curlimages/curl:latest -s -G \
    -H "X-Scope-OrgID: $1" \
    --data-urlencode "query=$2" \
    "$M/prometheus/api/v1/query" 2>/dev/null
}

dump() { # $1=title $2=tenant $3=query
  echo "  $1"
  q "$2" "$3" | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    rs=d.get('data',{}).get('result',[])
    print('     返回 %d 条' % len(rs))
    for r in rs[:5]:
        m=dict(r['metric']); m.pop('__name__',None)
        print('       tenant=%-9s route=%-12s value=%s' % (
            m.get('tenant','?'), m.get('route'), r['value'][1]))
except Exception as e:
    print('     ERR %s' % e)
"
}

echo "############ 1. 各租户能看到哪些 tenant 标签值 ############"
dump "[tenantA] app_requests_total{route=\"/\"}" tenantA 'app_requests_total{route="/"}'
dump "[tenantB] app_requests_total{route=\"/\"}" tenantB 'app_requests_total{route="/"}'

echo
echo "############ 2. 决定性：用 tenant 标签过滤，看能否跨租户查到 ############"
dump "[tenantA 查询] tenant=\"tenantB\"" tenantA 'app_requests_total{tenant="tenantB"}'
dump "[tenantB 查询] tenant=\"tenantA\"" tenantB 'app_requests_total{tenant="tenantA"}'

echo
echo "############ 3. 总序列数对照（若隔离，各租户都是自己那份）############"
for t in tenantA tenantB; do
  n=$(q "$t" 'count(app_requests_total)' | python3 -c "
import sys,json
d=json.load(sys.stdin)
rs=d.get('data',{}).get('result',[])
print(rs[0]['value'][1] if rs else 'N/A')")
  echo "   $t: count(app_requests_total) = $n"
done

echo
echo "############ 4. 不存在的租户（应为空，不报错）############"
dump "[tenantZZZ] 不存在的租户" tenantZZZ 'app_requests_total'

echo
echo "############ 5. 与 Thanos 对比：Thanos 无租户概念（同一查询返回全部）############"
docker run --rm --network $NET curlimages/curl:latest -s -G \
  --data-urlencode 'query=count(app_requests_total)' \
  "http://l9-thanos-query:19191/api/v1/query" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
rs=d.get('data',{}).get('result',[])
print('   Thanos(无租户头): count = %s  <- 单视图，不区分租户' % (rs[0]['value'][1] if rs else 'N/A'))
"
