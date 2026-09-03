#!/bin/bash
echo "=== [1] 两个 vmstorage 的挂载点 ==="
echo "--- vmstorage-learn ---"
docker inspect vmstorage-learn --format '{{range .Mounts}}{{.Source}} -> {{.Destination}} ({{.Type}})
{{end}}'
echo "--- vmstorage-learn2 ---"
docker inspect vmstorage-learn2 --format '{{range .Mounts}}{{.Source}} -> {{.Destination}} ({{.Type}})
{{end}}'

echo ""
echo "=== [2] vmstorage-learn 的 /storage 内容 ==="
docker exec vmstorage-learn sh -c "ls -la /storage/ 2>&1 | head -20"
echo "--- data/small ---"
docker exec vmstorage-learn sh -c "ls /storage/data/small/ 2>&1 | head -20"
echo "--- data/big ---"
docker exec vmstorage-learn sh -c "ls /storage/data/big/ 2>&1 | head -20"

echo ""
echo "=== [3] vmstorage-learn2 的 /storage 内容 ==="
docker exec vmstorage-learn2 sh -c "ls /storage/data/small/ 2>&1 | head -20"

echo ""
echo "=== [4] 网络检查：vminsert 能否解析 vmstorage-learn ==="
docker exec vminsert-learn sh -c "getent hosts vmstorage-learn 2>&1; getent hosts vmstorage-learn2 2>&1"
echo "--- 所属网络 ---"
docker inspect vminsert-learn --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}'
echo ""
docker inspect vmstorage-learn --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}'
echo ""

echo ""
echo "=== [5] 检查两个 vmstorage 是否真的收到数据（比对其 data 目录大小） ==="
docker exec vmstorage-learn sh -c "du -sh /storage 2>/dev/null"
docker exec vmstorage-learn2 sh -c "du -sh /storage 2>/dev/null"

echo ""
echo "=== [6] 关键：检查 vmstorage 的 recent 数据（未落盘部分） ==="
docker exec vmstorage-learn sh -c "ls -la /storage/data/ 2>&1"
echo "--- snapshots ---"
docker exec vmstorage-learn sh -c "ls /storage/snapshots/ 2>&1 | head"

echo ""
echo "=== [7] 写入一条数据到 8480 后立刻在两个 storage 上查 ==="
TS=$(date +%s)
echo "{\"metric\":{\"__name__\":\"l12r_arch_test\",\"idx\":\"0\"},\"values\":[42],\"timestamps\":[${TS}000]}" \
  | curl -s -X POST --data-binary @- "http://localhost:8480/insert/0/prometheus/api/v1/import/prometheus" -w " -> HTTP %{http_code}\n"
sleep 3
echo -n "via 8481: "
curl -s -G "http://localhost:8481/select/0/prometheus/api/v1/export" --data-urlencode 'match[]={__name__="l12r_arch_test"}' | head -c 200
echo ""
echo -n "via 8485 (vmsel-n1): "
curl -s -G "http://localhost:8485/select/0/prometheus/api/v1/export" --data-urlencode 'match[]={__name__="l12r_arch_test"}' | head -c 200
echo ""
echo -n "via 8486 (vmsel-n2): "
curl -s -G "http://localhost:8486/select/0/prometheus/api/v1/export" --data-urlencode 'match[]={__name__="l12r_arch_test"}' | head -c 200
echo ""
