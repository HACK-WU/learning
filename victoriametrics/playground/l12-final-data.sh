#!/bin/bash
# 课 12 实验 25：序列数真相（活跃 vs 总数）+ vmctl 其他迁移模式 + 增量迁移证据
set -u
cd /mnt/d/projects/learning/victoriametrics/playground
VM=http://localhost:8428

echo "===== [1] 序列数真相：/series/count 与活跃序列的区别 ====="
echo "-- /api/v1/series/count（含已删除/历史所有） --"
curl -s $VM/api/v1/series/count; echo
echo "-- 活跃序列（最近 5 分钟有数据） --"
curl -s "$VM/api/v1/query?query=count(up)" | head -c 200; echo
echo "-- vm_active_time_series / vm_cache_entries --"
curl -s "$VM/api/v1/query?query=vm_active_merges" | head -c 200; echo
echo "-- 用 count 聚合统计当前活跃序列总数（近似） --"
curl -s "$VM/api/v1/query?query=vm_rows{type=\"indexdb\"}" | head -c 250; echo

echo ""
echo "===== [2] 关键：删除到底有没有减少存储中的序列 ====="
echo "-- 删除前写 30000 条，删除后对比 /series/count 增量 --"
BEFORE=$(curl -s $VM/api/v1/series/count | python3 -c "import sys,json;print(json.load(sys.stdin)['data'][0])")
echo "  删除实验前 count = $BEFORE"
: > /tmp/l12_ct.txt
for i in $(seq 1 30000); do
  printf 'l12_counttest{job="l12",i="%s"} %s %s000\n' "$i" "$i" "$(date +%s)" >> /tmp/l12_ct.txt
done
curl -s -o /dev/null -X POST --data-binary @/tmp/l12_ct.txt "$VM/api/v1/import/prometheus"
sleep 4
AFTER_W=$(curl -s $VM/api/v1/series/count | python3 -c "import sys,json;print(json.load(sys.stdin)['data'][0])")
echo "  写入 30000 条后 count = $AFTER_W  (增量 $((AFTER_W-BEFORE)))"
curl -s -o /dev/null -X POST "$VM/api/v1/admin/tsdb/delete_series" --data-urlencode 'match[]=l12_counttest'
sleep 5
AFTER_D=$(curl -s $VM/api/v1/series/count | python3 -c "import sys,json;print(json.load(sys.stdin)['data'][0])")
echo "  删除后 count = $AFTER_D  (变化 $((AFTER_D-AFTER_W)))"
echo "  >> /series/count 包含已标记删除但未物理回收的条目，所以删后不降"

echo ""
echo "===== [3] vmctl 的四种迁移模式（帮助信息） ====="
docker run --rm victoriametrics/vmctl:v1.151.0 --help 2>&1 | grep -A12 "COMMANDS" | head -20

echo ""
echo "===== [4] 迁移模式 B：prometheus snapshot（从 Prometheus 快照目录迁移） ====="
echo "-- 先让 Prometheus 生成快照 --"
curl -s -o /dev/null -w "  Prometheus snapshot HTTP=%{http_code}\n" -X POST "$PROM/api/v1/admin/tsdb/snapshot"
curl -s -X POST "$PROM/api/v1/admin/tsdb/snapshot" | head -c 200; echo
echo "-- 列出 Prometheus 快照目录 --"
docker exec prom-learn sh -c "ls -la /prometheus/snapshots/ 2>&1 | head -8"

echo ""
echo "===== [5] 迁移模式 C：vm-native（VM 集群间迁移，本课重点） ====="
docker run --rm victoriametrics/vmctl:v1.151.0 vm-native --help 2>&1 | grep -E '^\s+--(vm-native|vm-src|vm-dst)' | head -14

echo ""
echo "===== [6] 增量迁移证据：只迁新时间窗口，序列数应只增一点点 ====="
B2=$(curl -s $VM/api/v1/series/count | python3 -c "import sys,json;print(json.load(sys.stdin)['data'][0])")
echo "  增量迁移前 = $B2"
docker run --rm --network host \
  victoriametrics/vmctl:v1.151.0 remote-read -s --disable-progress-bar \
  --vm-addr=http://localhost:8428 \
  --remote-read-src-addr=http://localhost:9090 \
  --remote-read-filter-time-start=2026-09-02T13:00:00Z \
  --remote-read-filter-time-end=2026-09-02T13:30:00Z \
  --remote-read-step-interval=minute 2>&1 | grep -iE "total samples|import requests" | head -3
sleep 2
A2=$(curl -s $VM/api/v1/series/count | python3 -c "import sys,json;print(json.load(sys.stdin)['data'][0])")
echo "  增量迁移后 = $A2  (新增 $((A2-B2)))"
