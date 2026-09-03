#!/bin/bash
# 遗留项攻关 - 环境探测
echo "=== [1] vm-learn 实际版本 ==="
curl -s http://localhost:8428/api/v1/status/fields 2>/dev/null | head -c 100
echo ""
docker exec vm-learn /victoria-metrics-prod --version 2>&1 | head -5

echo ""
echo "=== [2] vm-learn 启动参数（找 forceMergeAuthKey / retentionPeriod） ==="
docker inspect vm-learn --format '{{range .Args}}{{.}}
{{end}}'

echo ""
echo "=== [3] 集群版 vmstorage 版本 ==="
docker exec vmstorage-learn /vmstorage-prod --version 2>&1 | head -3

echo ""
echo "=== [4] force_merge 端点是否存在（未设 authKey 时的返回） ==="
curl -s -o /dev/null -w "no-key: %{http_code}\n" http://localhost:8428/internal/force_merge
echo "--- 带错误 key ---"
curl -s -X POST "http://localhost:8428/internal/force_merge?authKey=wrong" | head -c 300
echo ""

echo ""
echo "=== [5] 快照列表 API ==="
curl -s http://localhost:8428/snapshot/list | head -c 500
echo ""

echo ""
echo "=== [6] vmctl vm-native 全部参数 ==="
docker run --rm victoriametrics/vmctl:v1.151.0 vm-native --help 2>&1 | grep -E "vm-native|account|user|addr|step|filter" | head -60

echo ""
echo "=== [7] 磁盘剩余空间 ==="
df -h /var/lib/docker 2>/dev/null | tail -2
df -h / | tail -2
