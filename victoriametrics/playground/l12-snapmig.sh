#!/bin/bash
# 课 12 实验 26：Prometheus snapshot 迁移 + vm-native 集群间迁移
set -u
cd /mnt/d/projects/learning/victoriametrics/playground
VM=http://localhost:8428
PROM=http://localhost:9090

echo "===== [1] Prometheus snapshot 迁移模式 ====="
echo "-- 生成 Prometheus 快照 --"
SNAPJSON=$(curl -s -X POST "$PROM/api/v1/admin/tsdb/snapshot")
echo "  返回 = $SNAPJSON"
SNAPNAME=$(echo "$SNAPJSON" | python3 -c "import sys,json;print(json.load(sys.stdin)['data']['name'])" 2>/dev/null | tr -d '\r')
echo "  快照名 = $SNAPNAME"
docker exec prom-learn sh -c "ls -la /prometheus/snapshots/ 2>&1 | head -8"
docker exec prom-learn sh -c "du -sh /prometheus/snapshots/$SNAPNAME 2>/dev/null"

echo ""
echo "===== [2] 用 vmctl prometheus 模式从快照迁移 ====="
echo "-- vmctl prometheus 子命令帮助 --"
docker run --rm victoriametrics/vmctl:v1.151.0 prometheus --help 2>&1 | grep -E '^\s+--prom-(snapshot|concurrency|filter)' | head -8

echo ""
echo "-- 挂载 Prometheus 快照目录做迁移（迁到单节点） --"
docker run --rm --network host \
  -v prom_data:/prometheus:ro \
  victoriametrics/vmctl:v1.151.0 \
  prometheus -s --disable-progress-bar \
  --prom-snapshot="/prometheus/snapshots/$SNAPNAME" \
  --vm-addr=http://localhost:8428 \
  --vm-concurrency=4 2>&1 | tail -12

echo ""
echo "===== [3] vm-native：VM 集群间迁移（本课重点） ====="
docker run --rm victoriametrics/vmctl:v1.151.0 vm-native --help 2>&1 | grep -E '^\s+--vm-native-(src|dst|filter)|^\s+--vm-(src|dst)' | head -14

echo ""
echo "===== [4] 实测 vm-native：从单节点迁移到集群 tenant 777 ====="
echo "-- 迁移前 tenant 777 序列数 --"
curl -s "http://localhost:8481/select/777/prometheus/api/v1/series/count"; echo

docker run --rm --network host \
  victoriametrics/vmctl:v1.151.0 \
  vm-native -s --disable-progress-bar \
  --vm-native-src-addr=http://localhost:8428 \
  --vm-native-dst-addr=http://localhost:8480 \
  --vm-native-filter-match='{__name__=~"l12_disaster_marker.*"}' \
  --vm-native-filter-time-start=2026-09-02T00:00:00Z \
  --vm-native-src-headers='' \
  --vm-native-dst-account-id=777 \
  --vm-concurrency=4 2>&1 | tail -15

echo ""
echo "-- 迁移后 tenant 777 序列数 --"
sleep 3
curl -s "http://localhost:8481/select/777/prometheus/api/v1/series/count"; echo
echo "-- 抽查 tenant 777 里的 marker 数据 --"
curl -s --data-urlencode 'query=count(l12_disaster_marker)' "http://localhost:8481/select/777/prometheus/api/v1/query" \
  | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print('   tenant 777 marker 序列数 =', r[0]['value'][1] if r else 'NONE')"

echo ""
echo "===== [5] 迁移完整性对照：源端 vs 目标端 ====="
echo "-- 源端（单节点）marker 序列数 --"
curl -s --data-urlencode 'query=count(l12_disaster_marker)' "$VM/api/v1/query" \
  | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print('   =', r[0]['value'][1] if r else 'NONE')"
echo "-- 源端 marker 采样值 i=7 --"
curl -s --data-urlencode 'query=l12_disaster_marker{i="7"}' "$VM/api/v1/query" \
  | python3 -c "
import sys,json
for r in json.load(sys.stdin)['data']['result']: print('   ', r['metric'].get('batch'), '=', r['value'][1])
"
echo "-- 目标端 tenant 777 采样值 i=7 --"
curl -s --data-urlencode 'query=l12_disaster_marker{i="7"}' "http://localhost:8481/select/777/prometheus/api/v1/query" \
  | python3 -c "
import sys,json
for r in json.load(sys.stdin)['data']['result']: print('   ', r['metric'].get('batch'), '=', r['value'][1])
" 2>&1 | head -4
