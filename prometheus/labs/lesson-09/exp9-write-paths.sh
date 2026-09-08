#!/usr/bin/env bash
# 写入路径对比：同一个 Prometheus 双写到 Mimir 与 VM，看两端行为差异
set -uo pipefail
NET=l9net

echo "############ 1. 各方案的远端写入端点 ############"
echo "   Thanos  : 无（sidecar 上传 block，不收 remote write；Receive 组件才收）"
echo "   Mimir   : /api/v1/push       （需 X-Scope-OrgID）"
echo "   VM      : /api/v1/write      （单节点 / vminsert:8480/insert/0/prometheus）"
echo

echo "-- 实测各端点对空 payload 的响应码 --"
printf '   %-40s ' "Mimir /api/v1/push (无租户头)"
docker run --rm --network $NET curlimages/curl:latest -s -o /dev/null -w '%{http_code}\n' \
  -X POST http://l9-mimir:8080/api/v1/push 2>/dev/null
printf '   %-40s ' "Mimir /api/v1/push (有租户头)"
docker run --rm --network $NET curlimages/curl:latest -s -o /dev/null -w '%{http_code}\n' \
  -X POST -H 'X-Scope-OrgID: t' http://l9-mimir:8080/api/v1/push 2>/dev/null
printf '   %-40s ' "VM /api/v1/write"
docker run --rm --network $NET curlimages/curl:latest -s -o /dev/null -w '%{http_code}\n' \
  -X POST http://l9-vm-single:8428/api/v1/write 2>/dev/null

echo
echo "############ 2. 查询代价对比（同一 range 查询，各方案耗时）############"
now=$(date +%s)
st=$((now-300))
QQ='app_requests_total'
for pair in "Thanos-Q1|http://l9-thanos-query:19191/api/v1/query_range" \
            "Mimir-A|http://l9-mimir:8080/prometheus/api/v1/query_range" \
            "VM-single|http://l9-vm-single:8428/prometheus/api/v1/query_range"; do
  n=${pair%%|*}; u=${pair#*|}
  printf '   %-12s ' "$n"
  if [ "$n" = "Mimir-A" ]; then
    hdr='-H X-Scope-OrgID:\ tenantA'
  else
    hdr=''
  fi
  docker run --rm --network $NET curlimages/curl:latest -s -G \
    $hdr \
    --data-urlencode "query=$QQ" \
    --data-urlencode "start=$st" \
    --data-urlencode "end=$now" \
    --data-urlencode 'step=15s' \
    "$u" 2>/dev/null | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    rs=d.get('data',{}).get('result',[])
    npts=sum(len(r.get('values',[])) for r in rs)
    warn=d.get('warnings',[])
    print('序列=%d 数据点=%d warnings=%d' % (len(rs), npts, len(warn)))
except Exception as e:
    print('ERR %s' % e)
"
done

echo
echo "############ 3. Thanos 的降采样能力（VM/Mimir 也有对应机制）############"
echo "   Thanos: compactor 做 5m/1h 降采样 -- 本次实验未部署 compactor（需单例）"
echo "   注：compactor 每 bucket 必须单例，多实例会损坏 block"

echo
echo "############ 4. 组件数量对比（实测本环境）############"
echo "   Thanos : Prometheus×2 + sidecar×2 + store×1 + query×2(含对照) = 7 容器"
echo "   Mimir  : 1 容器（单体模式 -target=all，内含全部微服务）"
echo "   VM     : 单节点 1 容器 / 集群 3 容器（vmstorage+vminsert+vmselect）"
docker ps --format '{{.Names}}' | grep -c '^l9-' | sed 's/^/   本环境 l9-* 容器总数: /'
