#!/bin/bash
echo "=== [1] vminsert-learn (8480) 的 storageNode ==="
docker inspect vminsert-learn --format '{{range .Args}}{{.}}
{{end}}' | grep -iE "storageNode|replication|addr"

echo ""
echo "=== [2] vmselect-learn (8481) 的 storageNode ==="
docker inspect vmselect-learn --format '{{range .Args}}{{.}}
{{end}}' | grep -iE "storageNode|replication|addr"

echo ""
echo "=== [3] 第二个 vminsert (8488) 的 storageNode ==="
docker inspect vminsert-learn2 --format '{{range .Args}}{{.}}
{{end}}' | grep -iE "storageNode|replication|addr"

echo ""
echo "=== [4] 两个 vmstorage 的启动参数 ==="
echo "--- vmstorage-learn ---"
docker inspect vmstorage-learn --format '{{range .Args}}{{.}}
{{end}}' | grep -iE "retention|storageDataPath|addr"
echo "--- vmstorage-learn2 ---"
docker inspect vmstorage-learn2 --format '{{range .Args}}{{.}}
{{end}}' | grep -iE "retention|storageDataPath|addr"

echo ""
echo "=== [5] 通过 8481 查出的数据，观察其来源节点 ==="
curl -s -G "http://localhost:8481/select/0/prometheus/api/v1/query" \
  --data-urlencode 'query=up' | head -c 500
echo ""

echo ""
echo "=== [6] 检查 vmstorage 数据目录中的租户分区 ==="
docker exec vmstorage-learn sh -c "ls /vmstorage-data/data/ 2>/dev/null | head -20"
echo "--- big 分区 ---"
docker exec vmstorage-learn sh -c "ls /vmstorage-data/data/big/ 2>/dev/null | head -10"
echo "--- small 分区 ---"
docker exec vmstorage-learn sh -c "ls /vmstorage-data/data/small/ 2>/dev/null | head -10"

echo ""
echo "=== [7] vmstorage-learn2 的租户分区 ==="
docker exec vmstorage-learn2 sh -c "ls /vmstorage-data/data/small/ 2>/dev/null | head -10"

echo ""
echo "=== [8] vmstorage 的 retained/pending 写入统计 ==="
curl -s "http://localhost:8482/metrics" 2>/dev/null | grep -E "vm_rows_inserted_total|vm_active_merges|vm_pending_rows" | head -10
echo "--- 8492 (vmstorage-learn2 的 http) ---"
curl -s "http://localhost:8492/metrics" 2>/dev/null | grep -E "vm_rows_inserted_total" | head -5
