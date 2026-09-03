#!/bin/bash
# 遗留项 2：vm-native 跨租户迁移 —— 用 URL 路径指定租户
echo "=== [1] 集群租户路径 health 探测 ==="
for p in "/select/0/prometheus/health" "/select/42/prometheus/health" "/insert/42/prometheus/health"; do
  code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8481${p}")
  echo "vmselect:8481${p} -> ${code}"
done
for p in "/insert/42/prometheus/health" "/insert/0/prometheus/health"; do
  code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8480${p}")
  echo "vminsert:8480${p} -> ${code}"
done

echo ""
echo "=== [2] 迁移前：源租户 0 与目标租户 42 的序列数 ==="
echo -n "tenant 0 : "; curl -s "http://localhost:8481/select/0/prometheus/api/v1/series/count" ; echo ""
echo -n "tenant 42: "; curl -s "http://localhost:8481/select/42/prometheus/api/v1/series/count" ; echo ""

echo ""
echo "=== [3] 源租户 0 的指标名列表（取前 10） ==="
curl -s "http://localhost:8481/select/0/prometheus/api/v1/label/__name__/values" | head -c 600
echo ""

echo ""
echo "=== [4] 源数据的时间范围 ==="
NOW=$(date +%s)
START=$((NOW - 86400))
echo "window: ${START} -> ${NOW} ($(date -d @${START} '+%Y-%m-%d %H:%M:%S') ~ $(date -d @${NOW} '+%Y-%m-%d %H:%M:%S'))"
curl -s -G "http://localhost:8481/select/0/prometheus/api/v1/query" \
  --data-urlencode 'query=l12r_marker_a' --data-urlencode "time=${NOW}" | head -c 300
echo ""

echo ""
echo "=== [5] 先用不存在的参数复现课 12 的失败 ==="
docker run --rm --network host victoriametrics/vmctl:v1.151.0 vm-native \
  --vm-native-src-addr=http://localhost:8481/select/0/prometheus \
  --vm-native-dst-addr=http://localhost:8480/insert/42/prometheus \
  --vm-native-dst-account-id=42 \
  --vm-native-filter-time-start="2026-09-02T00:00:00Z" \
  -s --disable-progress-bar 2>&1 | head -20
echo "exit=$?"
