#!/usr/bin/env bash
# 决定性对照：远端故障时，Server 与 Agent 的 WAL 行为差异
# 两侧实例已由 fair-compare.sh 同起点启动，抓取目标一致
set -u

snap(){
  P=$(docker exec l7-prom  sh -c 'du -sk /prometheus 2>/dev/null' | cut -f1)
  PW=$(docker exec l7-prom  sh -c 'du -sk /prometheus/wal 2>/dev/null' | cut -f1)
  A=$(docker exec l7-agent sh -c 'du -sk /data-agent 2>/dev/null' | cut -f1)
  echo "${P:-0} ${PW:-0} ${A:-0}"
}

echo "=== 阶段 0：故障前基线（receiver 正常） ==="
read P0 PW0 A0 <<< "$(snap)"
echo "  server 总=${P0}KB (wal=${PW0}KB)   agent 总=${A0}KB"

echo
echo "=== 阶段 1：注入 500 故障，持续 300 秒 ==="
curl -s http://localhost:19099/mode/500 >/dev/null
sleep 300
read P1 PW1 A1 <<< "$(snap)"
echo "  server 总=${P1}KB (wal=${PW1}KB)   agent 总=${A1}KB"
echo "  server 增量: 总 $((P1-P0))KB  wal $((PW1-PW0))KB"
echo "  agent  增量: 总 $((A1-A0))KB"

echo
echo "=== 阶段 2：故障期间的 pending / failed（Agent 侧） ==="
docker exec l7-agent wget -qO- http://localhost:9090/metrics 2>/dev/null \
  | grep -E "^prometheus_remote_storage_(samples_pending|samples_failed_total|enqueue_retries_total)" \
  | sed 's/{.*}/ /' | awk '{print "  agent  "$1" = "$2}'

echo "=== 阶段 2b：故障期间的 pending / failed（Server 侧） ==="
curl -s -G "http://localhost:19100/api/v1/query" \
  --data-urlencode 'query=prometheus_remote_storage_samples_pending' \
  | python -c "import sys,json;d=json.load(sys.stdin);r=d['data']['result'];print('  server pending =', r[0]['value'][1] if r else 'N/A')"

echo
echo "=== 阶段 3：恢复，持续 180 秒，观察回落 ==="
curl -s http://localhost:19099/mode/ok >/dev/null
sleep 180
read P2 PW2 A2 <<< "$(snap)"
echo "  server 总=${P2}KB (wal=${PW2}KB)   agent 总=${A2}KB"
echo "  server 较故障峰值: $((P2-P1))KB   agent 较故障峰值: $((A2-A1))KB"

echo
echo "=== 阶段 4：内存（故障时 vs 恢复后） ==="
docker stats --no-stream --format "{{.Name}}|{{.MemUsage}}" l7-prom l7-agent

echo
echo "=== 结论数据汇总 ==="
echo "  故障 300s  WAL/磁盘增量:  server +$((P1-P0))KB   agent +$((A1-A0))KB"
echo "  恢复 180s  变化:          server $((P2-P1))KB    agent $((A2-A1))KB"
echo "  稳态总量:                server ${P2}KB        agent ${A2}KB"
