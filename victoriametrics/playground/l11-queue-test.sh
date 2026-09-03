#!/bin/bash
set -u
echo "=== 阶段 A：基线 —— 确认数据在正常写入 ==="
# 用当前时间写入一条可辨识的序列
NOW=$(date +%s)
curl -s -o /dev/null "http://localhost:8480/insert/0/prometheus/api/v1/write" --data-binary "" 2>/dev/null

docker exec vmagent-learn sh -c \
  "wget -qO- --post-data='l11_base_metric{phase=\"before\"} 1' \
   http://localhost:8429/api/v1/import/prometheus 2>/dev/null" || true

echo "查看 vmagent 抓取到的样本数："
curl -s "http://localhost:8429/api/v1/query?query=sum(vmagent_remotewrite_samples_total)" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print('  samples_total =', d['data']['result'][0]['value'][1] if d['data']['result'] else 'NO DATA')" 2>/dev/null

echo
echo "=== 阶段 B：记录 vmagent 自身指标（队列相关）==="
echo "--- 队列大小 ---"
curl -s "http://localhost:8429/api/v1/query?query=vmagent_remotewrite_pending_data_bytes" \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)
for r in d['data']['result']:
    print('   %-40s = %s' % (r['metric'].get('url','')[-18:], r['value'][1]))
" 2>/dev/null

echo "--- 已发送/丢弃/重试 ---"
for m in vmagent_remotewrite_samples_total vmagent_remotewrite_packets_dropped_total vmagent_remotewrite_retries_count_total; do
  v=$(curl -s "http://localhost:8429/api/v1/query?query=$m" \
    | python3 -c "
import sys,json
d=json.load(sys.stdin)
rs=d['data']['result']
print(sum(float(r['value'][1]) for r in rs) if rs else 'NO_DATA')
" 2>/dev/null)
  printf "   %-45s = %s\n" "$m" "$v"
done

echo
echo "=== 阶段 C：停掉 vminsert（模拟后端故障 60 秒）==="
docker pause vminsert-learn
echo "  vminsert-learn 已暂停，时间: $(date +%H:%M:%S)"
sleep 20

echo "  后端故障 20 秒后，队列大小："
curl -s "http://localhost:8429/api/v1/query?query=vmagent_remotewrite_pending_data_bytes" \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)
for r in d['data']['result']:
    print('      pending_bytes =', r['value'][1])
" 2>/dev/null

echo "  队列目录内容："
docker exec vmagent-learn sh -c "du -sh /vmagent-remotewrite-data/persistent-queue/* 2>/dev/null | head -5"

sleep 20
echo "  后端故障 40 秒后队列大小："
curl -s "http://localhost:8429/api/v1/query?query=vmagent_remotewrite_pending_data_bytes" \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)
for r in d['data']['result']:
    print('      pending_bytes =', r['value'][1])
" 2>/dev/null

echo
echo "=== 阶段 D：恢复后端，观察队列排空 ==="
docker unpause vminsert-learn
echo "  vminsert-learn 已恢复，时间: $(date +%H:%M:%S)"
for i in 1 2 3 4 5 6; do
  sleep 10
  v=$(curl -s "http://localhost:8429/api/v1/query?query=vmagent_remotewrite_pending_data_bytes" \
    | python3 -c "
import sys,json
d=json.load(sys.stdin)
rs=d['data']['result']
print(sum(float(r['value'][1]) for r in rs) if rs else 0)
" 2>/dev/null)
  echo "    +${i}0s  pending_bytes = $v"
done
