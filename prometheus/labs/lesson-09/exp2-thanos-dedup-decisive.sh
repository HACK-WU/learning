#!/usr/bin/env bash
# 决定性对照：Thanos 去重到底是不是 --query.replica-label 干的
# 起一个【不设】replica-label 的 querier（Q2），与已设的 Q1 对比
set -uo pipefail
NET=l9net
LAB=/mnt/d/projects/learning/prometheus/labs/lesson-09
IMG=quay.io/thanos/thanos:v0.42.4

echo "=== 启动对照 querier（不设 --query.replica-label）==="
docker rm -f l9-thanos-query-nodedup 2>/dev/null || true
docker run -d --name l9-thanos-query-nodedup --network $NET \
  -p 19401:19191 \
  -v $LAB/sd-files:/etc/thanos/sd:ro \
  $IMG query \
  --http-address=0.0.0.0:19191 \
  --grpc-address=0.0.0.0:19091 \
  --store.sd-files=/etc/thanos/sd/stores.yaml \
  --store.sd-interval=10s >/dev/null
echo "l9-thanos-query-nodedup started (host :19401)"

echo "等待 store 发现（约 35s）..."
sleep 40

q1() { docker run --rm --network $NET curlimages/curl:latest -s -G \
  --data-urlencode "query=$1" "http://l9-thanos-query:19191/api/v1/query" 2>/dev/null; }
q2() { docker run --rm --network $NET curlimages/curl:latest -s -G \
  --data-urlencode "query=$1" "http://l9-thanos-query-nodedup:19191/api/v1/query" 2>/dev/null; }

show() { # $1=标签 $2=json
  echo "$2" | python3 -c "
import sys,json
tag='''$1'''
try:
    d=json.load(sys.stdin)
    rs=d.get('data',{}).get('result',[])
    print('  %-28s 返回 %d 条' % (tag, len(rs)))
    for r in rs[:6]:
        m=dict(r['metric']); m.pop('__name__',None)
        print('      replica=%-6s value=%s' % (m.get('replica','<已剥离>'), r['value'][1]))
except Exception as e:
    print('  %s ERR %s' % (tag,e))
"
}

echo
echo "############ 对照：同一个查询，两个 querier ############"
echo "-- 查询：app_requests_total{route=\"/\"} --"
echo "  [Q1 有 --query.replica-label=replica]"
q1 'app_requests_total{route="/"}' | show "Q1 去重开启"
echo "  [Q2 无 replica-label]"
q2 'app_requests_total{route="/"}' | show "Q2 去重关闭"

echo
echo "-- 查询：count(app_requests_total{route=\"/\"}) --"
echo -n "  Q1 count = "
q1 'count(app_requests_total{route="/"})' | python3 -c "
import sys,json
d=json.load(sys.stdin); print(d['data']['result'][0]['value'][1] if d['data']['result'] else 'N/A')"
echo -n "  Q2 count = "
q2 'count(app_requests_total{route="/"})' | python3 -c "
import sys,json
d=json.load(sys.stdin); print(d['data']['result'][0]['value'][1] if d['data']['result'] else 'N/A')"

echo
echo "-- 查询：sum(app_requests_total)（聚合后两者应一致）--"
echo -n "  Q1 sum = "
q1 'sum(app_requests_total)' | python3 -c "
import sys,json
d=json.load(sys.stdin); print(d['data']['result'][0]['value'][1] if d['data']['result'] else 'N/A')"
echo -n "  Q2 sum = "
q2 'sum(app_requests_total)' | python3 -c "
import sys,json
d=json.load(sys.stdin); print(d['data']['result'][0]['value'][1] if d['data']['result'] else 'N/A')"
