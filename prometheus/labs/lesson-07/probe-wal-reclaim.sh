#!/usr/bin/env bash
# 验证 Agent WAL "发出即删" 特性：停止写入压力后，磁盘是否回落
# 前提：receiver 已恢复 ok，两实例持续发送
set -u
snap(){
  P=$(docker exec l7-prom  sh -c 'du -sk /prometheus 2>/dev/null' | cut -f1)
  PW=$(docker exec l7-prom  sh -c 'du -sk /prometheus/wal 2>/dev/null' | cut -f1)
  PC=$(docker exec l7-prom  sh -c 'du -sk /prometheus/chunks_head 2>/dev/null' | cut -f1)
  A=$(docker exec l7-agent sh -c 'du -sk /data-agent 2>/dev/null' | cut -f1)
  AW=$(docker exec l7-agent sh -c 'du -sk /data-agent/wal 2>/dev/null' | cut -f1)
  echo "${P:-0} ${PW:-0} ${PC:-0} ${A:-0} ${AW:-0}"
}
echo "时刻                     server总   server_wal  chunks_head  agent总  agent_wal"
for i in 1 2 3 4 5 6; do
  read P PW PC A AW <<< "$(snap)"
  TS=$(date +%H:%M:%S)
  printf "%s  %8s  %10s  %11s  %7s  %9s\n" "$TS" "$P" "$PW" "$PC" "$A" "$AW"
  [ $i -lt 6 ] && sleep 90
done
echo
echo "=== Agent WAL 保留参数（确认 min-time/max-time） ==="
docker exec l7-agent wget -qO- http://localhost:9090/metrics 2>/dev/null \
  | grep -iE "^prometheus_agent_" | head -n 5
docker exec l7-agent sh -c '/bin/prometheus --help 2>&1 | grep -A1 "storage.agent.retention" | head -n 8'
