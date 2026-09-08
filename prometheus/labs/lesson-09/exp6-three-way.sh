#!/usr/bin/env bash
# 三方对比：Thanos / Mimir / VictoriaMetrics 对同一份数据的查询行为
# 重点：HA 去重语义差异（这是选型时最容易踩坑的地方）
set -uo pipefail
NET=l9net

q() { # $1=name $2=url $3=query [$4=header]
  local name=$1 url=$2 query=$3 hdr=${4:-}
  local out
  if [ -n "$hdr" ]; then
    out=$(docker run --rm --network $NET curlimages/curl:latest -s -G \
      -H "$hdr" --data-urlencode "query=$query" "$url" 2>/dev/null)
  else
    out=$(docker run --rm --network $NET curlimages/curl:latest -s -G \
      --data-urlencode "query=$query" "$url" 2>/dev/null)
  fi
  echo "$out" | python3 -c "
import sys,json
tag='''$name'''
try:
    d=json.load(sys.stdin)
    rs=d.get('data',{}).get('result',[])
    print('   %-24s %d 条' % (tag, len(rs)))
    for r in rs[:3]:
        m=dict(r['metric']); m.pop('__name__',None)
        print('        %s = %s' % (
            {k:v for k,v in sorted(m.items()) if k in ('replica','tenant','cluster')},
            r['value'][1]))
except Exception as e:
    print('   %-24s ERR %s' % (tag,e))
"
}

echo "############ 1. HA 双写的去重语义：三方对比 ############"
echo "-- 查询：count(app_requests_total{route=\"/\"}) --"
echo
echo "  [Thanos] 查询层自动去重（--query.replica-label=replica）："
q "Thanos Q1(去重开)" "http://l9-thanos-query:19191/api/v1/query" \
  'count(app_requests_total{route="/"})'
q "Thanos Q2(去重关)" "http://l9-thanos-query-nodedup:19191/api/v1/query" \
  'count(app_requests_total{route="/"})'

echo
echo "  [Mimir] 靠 HA tracker + 外部标签，查询层不自动去重："
q "Mimir tenantA" "http://l9-mimir:8080/prometheus/api/v1/query" \
  'count(app_requests_total{route="/"})' "X-Scope-OrgID: tenantA"

echo
echo "  [VictoriaMetrics] 靠 dedup.minScrapeInterval，写入/查询时合并："
q "VM 单节点" "http://l9-vm-single:8428/prometheus/api/v1/query" \
  'count(app_requests_total{route="/"})'

echo
echo "############ 2. 各方案的自监控入口对比 ############"
echo "  Thanos   : /api/v1/stores          （看发现了哪些 store）"
echo "  Mimir    : /api/v1/status/buildinfo + 每租户 /prometheus/api/v1/*"
echo "  VM       : /metrics + /api/v1/status/tsdb（VM 无 /api/v1/status/flags）"

echo
echo "  -- 实测：各方案的组件发现/状态端点 --"
printf '   %-10s ' "Thanos"; docker run --rm --network $NET curlimages/curl:latest -s -o /dev/null -w '%{http_code}\n' \
  http://l9-thanos-query:19191/api/v1/stores 2>/dev/null
printf '   %-10s ' "Mimir"; docker run --rm --network $NET curlimages/curl:latest -s -o /dev/null -w '%{http_code}\n' \
  http://l9-mimir:8080/api/v1/status/buildinfo 2>/dev/null
printf '   %-10s ' "VM"; docker run --rm --network $NET curlimages/curl:latest -s -o /dev/null -w '%{http_code}\n' \
  http://l9-vm-single:8428/api/v1/status/tsdb 2>/dev/null

echo
echo "############ 3. 资源占用实测（docker stats 单次采样）############"
docker stats --no-stream --format '   {{.Name}}\tCPU={{.CPUPerc}}\tMEM={{.MemUsage}}' \
  l9-thanos-query l9-thanos-store l9-thanos-sc-1 l9-mimir l9-vm-single \
  l9-vmstorage l9-vmselect 2>/dev/null
