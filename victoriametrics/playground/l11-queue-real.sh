#!/bin/bash
echo "=== 0. 把 vmagent 接入默认 bridge（让它能抓 vm-learn）==="
docker network connect bridge vmagent-learn 2>&1 | head -2
sleep 8
curl -s http://localhost:8429/api/v1/targets 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
for t in d['data']['activeTargets']:
    print('  %-14s %-22s health=%-4s samples=%s' % (
        t['labels'].get('job'), t['labels'].get('instance'),
        t['health'], t.get('lastSamplesScraped')))
" 2>/dev/null

echo
echo "=== 1. 故障前基线 ==="
base() {
  curl -s http://localhost:8429/metrics 2>/dev/null | grep -E "^$1" | grep -v "^#" | awk '{s+=$NF} END {print s+0}'
}
echo "  blocks_sent_total   = $(base vmagent_remotewrite_blocks_sent_total)"
echo "  pending_data_bytes  = $(base vmagent_remotewrite_pending_data_bytes)"
echo "  samples_dropped     = $(base vmagent_remotewrite_samples_dropped_total)"
echo "  retries_count       = $(base vmagent_remotewrite_retries_count_total)"

echo
echo "=== 2. 真正断开后端：docker stop vminsert-learn ==="
docker stop vminsert-learn >/dev/null 2>&1
echo "  $(date +%H:%M:%S) STOPPED"

for i in 1 2 3; do
  sleep 15
  echo "  --- 故障第 $((i*15)) 秒 ---"
  echo "      pending_data_bytes = $(base vmagent_remotewrite_pending_data_bytes)"
  echo "      retries_count      = $(base vmagent_remotewrite_retries_count_total)"
  echo "      samples_dropped    = $(base vmagent_remotewrite_samples_dropped_total)"
  docker exec vmagent-learn sh -c "du -sb /vmagent-remotewrite-data/persistent-queue/* 2>/dev/null | head -2" | sed 's/^/      队列目录: /'
done

echo
echo "=== 3. 恢复后端 ==="
docker start vminsert-learn >/dev/null 2>&1
echo "  $(date +%H:%M:%S) STARTED"
sleep 12

for i in 1 2 3 4 5; do
  sleep 6
  echo "    +$((i*6))s  pending = $(base vmagent_remotewrite_pending_data_bytes)  blocks_sent = $(base vmagent_remotewrite_blocks_sent_total)"
done

echo
echo "=== 4. 最终核对：故障期间的数据有没有丢 ==="
sleep 5
curl -s "http://localhost:8481/select/0/prometheus/api/v1/query?query=count(up)" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('  后端 up 序列数 =', d['data']['result'][0]['value'][1] if d['data']['result'] else 'NO DATA')
"
echo "  samples_dropped 总计 = $(base vmagent_remotewrite_samples_dropped_total)"
echo "  packets_dropped 总计 = $(base vmagent_remotewrite_packets_dropped_total)"
