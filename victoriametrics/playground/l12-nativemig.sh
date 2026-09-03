#!/bin/bash
# 课 12 实验 27：vm-native 集群间迁移（修正参数）
set -u
cd /mnt/d/projects/learning/victoriametrics/playground
VM=http://localhost:8428

echo "===== [1] 重新制造 marker 数据（旧的可能已被 retention 清理） ====="
: > /tmp/l12_mk.txt
NOW=$(date +%s)
for i in $(seq 1 30); do
  printf 'l12_migrate_src{job="l12",i="%s"} %s %s000\n' "$i" "$((i*10))" "$NOW" >> /tmp/l12_mk.txt
done
curl -s -o /dev/null -w "  写入 30 条 l12_migrate_src HTTP=%{http_code}\n" -X POST --data-binary @/tmp/l12_mk.txt "$VM/api/v1/import/prometheus"
sleep 3
echo "-- 源端确认 --"
curl -s --data-urlencode 'query=count(l12_migrate_src)' "$VM/api/v1/query" \
  | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print('   源端 count =', r[0]['value'][1] if r else 'NONE')"

echo ""
echo "===== [2] vm-native 迁移：单节点 -> 集群 tenant 777 ====="
echo "-- 迁移前 tenant 777 --"
curl -s "http://localhost:8481/select/777/prometheus/api/v1/series/count"; echo

docker run --rm --network host \
  victoriametrics/vmctl:v1.151.0 \
  vm-native -s --disable-progress-bar \
  --vm-native-src-addr=http://localhost:8428 \
  --vm-native-dst-addr=http://localhost:8480 \
  --vm-native-filter-match='{__name__=~"l12_migrate_src.*"}' \
  --vm-native-filter-time-start=2026-09-02T00:00:00Z \
  --vm-native-dst-account-id=777 \
  --vm-concurrency=4 2>&1 | tail -14

echo ""
echo "===== [3] 迁移结果核对 ====="
sleep 3
echo "-- 迁移后 tenant 777 序列数 --"
curl -s "http://localhost:8481/select/777/prometheus/api/v1/series/count"; echo
echo "-- tenant 777 里 l12_migrate_src 序列数 --"
curl -s --data-urlencode 'query=count(l12_migrate_src)' "http://localhost:8481/select/777/prometheus/api/v1/query" \
  | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print('   =', r[0]['value'][1] if r else 'NONE')"
echo "-- 值对照：源端 i=5 --"
curl -s --data-urlencode 'query=l12_migrate_src{i="5"}' "$VM/api/v1/query" \
  | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print('   源端 =', r[0]['value'][1] if r else 'NONE')"
echo "-- 值对照：目标端 tenant 777 i=5 --"
curl -s --data-urlencode 'query=l12_migrate_src{i="5"}' "http://localhost:8481/select/777/prometheus/api/v1/query" \
  | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print('   目标端 =', r[0]['value'][1] if r else 'NONE')"

echo ""
echo "===== [4] vm-native 的 intercluster 模式（集群到集群，跨租户自动映射） ====="
echo "-- 帮助说明 --"
docker run --rm victoriametrics/vmctl:v1.151.0 vm-native --help 2>&1 | grep -A4 'vm-intercluster' | head -8

echo ""
echo "===== [5] 迁移带宽限制（生产迁移必备：避免打爆源端） ====="
echo "-- --vm-rate-limit 说明 --"
docker run --rm victoriametrics/vmctl:v1.151.0 vm-native --help 2>&1 | grep -A3 'vm-rate-limit' | head -6

echo ""
echo "===== [6] 实测限速迁移（限 1MB/s 观察耗时变化） ====="
echo "-- 不限速 --"
S=$(date +%s%N)
docker run --rm --network host victoriametrics/vmctl:v1.151.0 \
  vm-native -s --disable-progress-bar \
  --vm-native-src-addr=http://localhost:8428 \
  --vm-native-dst-addr=http://localhost:8480 \
  --vm-native-filter-match='{__name__=~"l12_migrate_src.*"}' \
  --vm-native-filter-time-start=2026-09-02T00:00:00Z \
  --vm-native-dst-account-id=778 \
  --vm-concurrency=1 2>&1 | grep -iE "total bytes|Total time" | head -3
E=$(date +%s%N)
echo "  不限速耗时 = $(( (E-S)/1000000 )) ms"
