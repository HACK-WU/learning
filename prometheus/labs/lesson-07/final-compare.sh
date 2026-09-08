#!/usr/bin/env bash
# 最终对照（配置已统一）：故障场景下 Server vs Agent 的 WAL 行为
set -u

snap(){
  P=$(docker exec l7-prom  sh -c 'du -sk /prometheus 2>/dev/null' | cut -f1)
  A=$(docker exec l7-agent sh -c 'du -sk /data-agent 2>/dev/null' | cut -f1)
  echo "${P:-0} ${A:-0}"
}

echo "=== 阶段 0：基线（receiver=ok，两实例已同起点运行 15 分钟） ==="
read P0 A0 <<< "$(snap)"
echo "  server=${P0}KB   agent=${A0}KB"

echo
echo "=== 阶段 1：注入 503（可重试），持续 420 秒 ==="
curl -s http://localhost:19099/mode/503 >/dev/null
sleep 420
read P1 A1 <<< "$(snap)"
echo "  server=${P1}KB (增量 $((P1-P0))KB)   agent=${A1}KB (增量 $((A1-A0))KB)"

echo "  -- 故障期间队列状态 --"
echo -n "  server pending = "
curl -s -G "http://localhost:19100/api/v1/query" \
  --data-urlencode 'query=prometheus_remote_storage_samples_pending' \
  | python -c "import sys,json;d=json.load(sys.stdin);r=d['data']['result'];print(r[0]['value'][1] if r else 'N/A')"
docker exec l7-agent wget -qO- http://localhost:9090/metrics 2>/dev/null \
  | grep -E "^prometheus_remote_storage_samples_(pending|failed_total)|^prometheus_remote_storage_enqueue_retries_total" \
  | sed 's/{.*}/ /' | awk '{print "  agent  "$1" = "$2}'

echo
echo "=== 阶段 2：恢复，持续 240 秒 ==="
curl -s http://localhost:19099/mode/ok >/dev/null
sleep 240
read P2 A2 <<< "$(snap)"
echo "  server=${P2}KB (较峰值 $((P2-P1))KB)   agent=${A2}KB (较峰值 $((A2-A1))KB)"

echo
echo "=== 阶段 3：receiver 侧真值（确认补发） ==="
curl -s http://localhost:19099/stats | python -c "
import sys,json
d=json.load(sys.stdin)
print('  requests =',d['requests'])
print('  accepted =',d['accepted'])
print('  rejected =',d['rejected'])
print('  mode     =',d['mode'])
"

echo
echo "=== 阶段 4：内存终值 ==="
docker stats --no-stream --format "{{.Name}}|{{.MemUsage}}" l7-prom l7-agent
