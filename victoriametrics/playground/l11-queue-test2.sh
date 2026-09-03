#!/bin/bash
VMAGENT=8429
SEL=http://localhost:8481/select/0/prometheus

echo "=== 0. 排查 vmsingle up=0 ==="
echo "  直连 vm-learn /metrics 前几行："
curl -s http://localhost:8428/metrics 2>/dev/null | head -3
echo "  HTTP 码: $(curl -s -o /dev/null -w '%{http_code}' http://localhost:8428/metrics)"

echo
echo "  从 vmagent 容器内访问 vm-learn："
docker exec vmagent-learn sh -c "wget -qO- http://vm-learn:8428/metrics 2>&1 | head -2; echo 'exit='\$?"

echo
echo "=== 1. 队列基线（故障前）==="
q() {
  curl -s "http://localhost:$VMAGENT/metrics" 2>/dev/null \
    | grep -E "$1" | grep -v "^#" | head -3
}
echo "  pending_data_bytes:"; q "vmagent_remotewrite_pending_data_bytes"
echo "  blocks_sent_total:";  q "vmagent_remotewrite_blocks_sent_total"
echo "  bytes_sent_total:";   q "vmagent_remotewrite_bytes_sent_total"

echo
echo "=== 2. 暂停 vminsert（后端故障）==="
docker pause vminsert-learn >/dev/null
echo "  $(date +%H:%M:%S) vminsert-learn PAUSED"

for i in 1 2 3; do
  sleep 15
  echo "  --- 故障第 ${i}5 秒 ---"
  q "vmagent_remotewrite_pending_data_bytes"
  docker exec vmagent-learn sh -c "du -sb /vmagent-remotewrite-data/persistent-queue/* 2>/dev/null | head -3"
done

echo
echo "=== 3. 恢复后端 ==="
docker unpause vminsert-learn >/dev/null
echo "  $(date +%H:%M:%S) vminsert-learn RESUMED"

for i in 1 2 3 4; do
  sleep 8
  v=$(curl -s "http://localhost:$VMAGENT/metrics" 2>/dev/null \
     | grep "vmagent_remotewrite_pending_data_bytes" | grep -v "^#" \
     | awk '{print $2}')
  echo "    +${i}×8s  pending_data_bytes = ${v:-?}"
done
