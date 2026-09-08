#!/usr/bin/env bash
set -uo pipefail
NET=l9net

run() { # $1=提示 $2=url $3=query
  echo "  $1"
  docker run --rm --network $NET curlimages/curl:latest -s -G \
    --data-urlencode "query=$3" "$2/api/v1/query" 2>/dev/null \
  | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    rs=d.get('data',{}).get('result',[])
    print('     返回 %d 条' % len(rs))
    for r in rs[:4]:
        m=dict(r['metric']); m.pop('__name__',None)
        rep=m.get('replica','<已剥离>')
        print('       replica=%-10s route=%-12s value=%s' % (rep, m.get('route'), r['value'][1]))
except Exception as e:
    print('     ERR: %s' % e)
"
}

Q1=http://l9-thanos-query:19191
Q2=http://l9-thanos-query-nodedup:19191

echo "############ 明细对照：app_requests_total{route=\"/\"} ############"
run "[Q1] --query.replica-label=replica 已设" "$Q1" 'app_requests_total{route="/"}'
run "[Q2] 未设 replica-label"                 "$Q2" 'app_requests_total{route="/"}'

echo
echo "############ 聚合对照：sum by (route) ############"
run "[Q1] 去重开启" "$Q1" 'sum by (route) (app_requests_total)'
run "[Q2] 去重关闭" "$Q2" 'sum by (route) (app_requests_total)'

echo
echo "############ 结论数据：count / sum ############"
for pair in "Q1|$Q1" "Q2|$Q2"; do
  name=${pair%%|*}; url=${pair#*|}
  c=$(docker run --rm --network $NET curlimages/curl:latest -s -G \
      --data-urlencode 'query=count(app_requests_total{route="/"})' \
      "$url/api/v1/query" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin); print(d['data']['result'][0]['value'][1] if d['data']['result'] else 'N/A')")
  s=$(docker run --rm --network $NET curlimages/curl:latest -s -G \
      --data-urlencode 'query=sum(app_requests_total)' \
      "$url/api/v1/query" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin); print(d['data']['result'][0]['value'][1] if d['data']['result'] else 'N/A')")
  echo "  $name: count=$c  sum=$s"
done
