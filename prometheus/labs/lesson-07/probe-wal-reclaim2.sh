#!/usr/bin/env bash
# 长周期观察：等待 WAL 轮转，看谁会真正回收磁盘
# 每 5 分钟采样一次，共 40 分钟
set -u
snap(){
  P=$(docker exec l7-prom  sh -c 'du -sk /prometheus 2>/dev/null' | cut -f1)
  PW=$(docker exec l7-prom  sh -c 'du -sk /prometheus/wal 2>/dev/null' | cut -f1)
  PC=$(docker exec l7-prom  sh -c 'du -sk /prometheus/chunks_head 2>/dev/null' | cut -f1)
  A=$(docker exec l7-agent sh -c 'du -sk /data-agent 2>/dev/null' | cut -f1)
  echo "${P:-0} ${PW:-0} ${PC:-0} ${A:-0}"
}
echo "时刻        server总  server_wal  chunks_head  agent总   差(server/agent)"
for i in $(seq 1 9); do
  read P PW PC A <<< "$(snap)"
  R=$(python -c "print(f'{$P/$A:.2f}x')" 2>/dev/null || echo '?')
  printf "%s  %8s  %10s  %11s  %7s  %8s\n" "$(date +%H:%M)" "$P" "$PW" "$PC" "$A" "$R"
  [ $i -lt 9 ] && sleep 300
done
echo
echo "=== WAL 段文件数量 ==="
echo -n "  server /prometheus/wal 段数 = "
docker exec l7-prom sh -c 'ls /prometheus/wal 2>/dev/null | grep -c "^0"'
echo -n "  agent  /data-agent/wal 段数 = "
docker exec l7-agent sh -c 'ls /data-agent/wal 2>/dev/null | grep -c "^0"'
