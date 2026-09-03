#!/bin/bash
echo "=== 1. 制造更大的写入负载（提高抓取频率）==="
P=/mnt/d/projects/learning/victoriametrics/playground
docker exec vmagent-learn sh -c "cat /etc/prometheus/prometheus.yml" >/dev/null 2>&1

echo "  当前抓取目标: $(curl -s http://localhost:8429/api/v1/targets 2>/dev/null | python3 -c 'import sys,json; print(len(json.load(sys.stdin)["data"]["activeTargets"]))')"
echo "  每秒样本量估算:"
curl -s http://localhost:8429/metrics 2>/dev/null | grep "vmagent_remotewrite_samples_total" | grep -v "^#" | head -2

echo
echo "=== 2. 用 -remoteWrite.forceVMProto + 更长故障窗口 ==="
echo "  停止后端，持续时间加长到 150 秒，每 30 秒采样一次"
docker stop vminsert-learn >/dev/null 2>&1
echo "  $(date +%H:%M:%S) STOPPED"

for i in 1 2 3 4 5; do
  sleep 30
  pend=$(curl -s http://localhost:8429/metrics 2>/dev/null | grep "^vmagent_remotewrite_pending_data_bytes" | grep -v "^#" | awk '{s+=$NF} END {print s+0}')
  inmem=$(curl -s http://localhost:8429/metrics 2>/dev/null | grep "^vmagent_remotewrite_pending_inmemory_blocks" | grep -v "^#" | awk '{s+=$NF} END {print s+0}')
  dropped=$(curl -s http://localhost:8429/metrics 2>/dev/null | grep "^vmagent_remotewrite_samples_dropped_total" | grep -v "^#" | awk '{s+=$NF} END {print s+0}')
  dirsz=$(docker exec vmagent-learn sh -c "du -sb /vmagent-remotewrite-data/persistent-queue/* 2>/dev/null | awk '{s+=\$1} END {print s+0}'")
  echo "    故障第 $((i*30))s: pending=${pend}B  inmemory_blocks=${inmem}  dropped=${dropped}  队列目录=${dirsz}B"
done

echo
echo "=== 3. 恢复 ==="
docker start vminsert-learn >/dev/null 2>&1
echo "  $(date +%H:%M:%S) STARTED"
for i in 1 2 3; do
  sleep 10
  pend=$(curl -s http://localhost:8429/metrics 2>/dev/null | grep "^vmagent_remotewrite_pending_data_bytes" | grep -v "^#" | awk '{s+=$NF} END {print s+0}')
  dirsz=$(docker exec vmagent-learn sh -c "du -sb /vmagent-remotewrite-data/persistent-queue/* 2>/dev/null | awk '{s+=\$1} END {print s+0}'")
  echo "    +${i}0s: pending=${pend}B  队列目录=${dirsz}B"
done

echo
echo "=== 4. 关键验证：vmagent 重启后队列是否保留 ==="
echo "  故障中再制造数据，然后重启 vmagent（不重启后端）"
docker stop vminsert-learn >/dev/null 2>&1
sleep 25
dirsz_before=$(docker exec vmagent-learn sh -c "du -sb /vmagent-remotewrite-data/persistent-queue/* 2>/dev/null | awk '{s+=\$1} END {print s+0}'")
echo "    重启前队列目录 = ${dirsz_before}B"
docker restart vmagent-learn >/dev/null 2>&1
sleep 15
dirsz_after=$(docker exec vmagent-learn sh -c "du -sb /vmagent-remotewrite-data/persistent-queue/* 2>/dev/null | awk '{s+=\$1} END {print s+0}'")
echo "    重启后队列目录 = ${dirsz_after}B  (保留=磁盘持久化生效)"
docker start vminsert-learn >/dev/null 2>&1
sleep 20
echo "    恢复后端后 dropped = $(curl -s http://localhost:8429/metrics 2>/dev/null | grep '^vmagent_remotewrite_samples_dropped_total' | grep -v '^#' | awk '{s+=$NF} END {print s+0}')"
