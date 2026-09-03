#!/bin/bash
echo "=== [1] vmstorage-learn 日志中的错误/警告（查 fallocate / IO / 9p） ==="
docker logs vmstorage-learn --tail 100 2>&1 | grep -iE "error|warn|fallocate|not supported|failed|cannot" | tail -20
echo "--- 计数 ---"
docker logs vmstorage-learn --tail 200 2>&1 | grep -icE "error|warn"

echo ""
echo "=== [2] vmstorage-learn2 日志中的错误 ==="
docker logs vmstorage-learn2 --tail 100 2>&1 | grep -iE "error|warn|fallocate|not supported|failed|cannot" | tail -20

echo ""
echo "=== [3] vminsert-learn 日志（写入侧） ==="
docker logs vminsert-learn --tail 30 2>&1 | tail -20

echo ""
echo "=== [4] 决定性测试：写入后强制 flush，再看 ==="
TS=$(date +%s)
echo "写入 l12r_force_test 时间戳: ${TS}"
echo "{\"metric\":{\"__name__\":\"l12r_force_test\",\"idx\":\"0\"},\"values\":[42],\"timestamps\":[${TS}000]}" \
  | curl -s -X POST --data-binary @- "http://localhost:8480/insert/0/prometheus/api/v1/import/prometheus" -w " -> HTTP %{http_code}\n"

echo "--- 触发快照（强制把内存数据落盘） ---"
curl -s http://localhost:8428/snapshot/create | head -c 200
echo ""

echo "--- 等 5 秒后再 export ---"
sleep 5
curl -s -G "http://localhost:8481/select/0/prometheus/api/v1/export" \
  --data-urlencode 'match[]={__name__="l12r_force_test"}' | head -c 300
echo ""

echo ""
echo "=== [5] 检查 indexdb 中是否有新序列 ==="
echo -n "租户 0 的 series count: "
curl -s "http://localhost:8481/select/0/prometheus/api/v1/series/count"; echo ""
echo -n "查 l12r 开头的指标名: "
curl -s "http://localhost:8481/select/0/prometheus/api/v1/label/__name__/values" | grep -o 'l12r[^"]*' | head -10
echo ""

echo ""
echo "=== [6] 直接查 vmstorage（8482）的内部指标看写入计数变化 ==="
echo "--- 写入前 ---"
curl -s "http://localhost:8482/metrics" | grep -E "vm_rows_inserted_total" | head -3
echo "--- 写入一条后 ---"
echo "{\"metric\":{\"__name__\":\"l12r_cnt_test\",\"idx\":\"0\"},\"values\":[1],\"timestamps\":[$(date +%s)000]}" \
  | curl -s -X POST --data-binary @- "http://localhost:8480/insert/0/prometheus/api/v1/import/prometheus" -w " -> HTTP %{http_code}\n"
sleep 2
curl -s "http://localhost:8482/metrics" | grep -E "vm_rows_inserted_total" | head -3

echo ""
echo "=== [7] 9p 挂载验证：能否在 vmstorage data 目录写文件 ==="
docker exec vmstorage-learn sh -c "touch /storage/data/small/2026_09/_wtest 2>&1 && echo 'WRITE OK' && rm -f /storage/data/small/2026_09/_wtest"
docker exec vmstorage-learn sh -c "cd /storage/data/small/2026_09 && ls | head -10"
