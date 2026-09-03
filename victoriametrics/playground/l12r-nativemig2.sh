#!/bin/bash
echo "=== [1] vmselect 各 health 路径返回码 ==="
for p in "/health" "/select/0/prometheus/health" "/select/0/health" "/prometheus/health" "/select/42/prometheus/health" "/select/42/health"; do
  code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8481${p}")
  echo "8481${p} -> ${code}"
done

echo ""
echo "=== [2] vmselect /health 的响应体 ==="
curl -s "http://localhost:8481/health" | head -c 200
echo ""

echo ""
echo "=== [3] vminsert 各 health 路径返回码 ==="
for p in "/health" "/insert/0/prometheus/health" "/insert/42/prometheus/health"; do
  code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8480${p}")
  echo "8480${p} -> ${code}"
done

echo ""
echo "=== [4] 检查各租户当前序列数（找一个干净的目标租户） ==="
for t in 0 42 4242 8888 12345; do
  n=$(curl -s "http://localhost:8481/select/${t}/prometheus/api/v1/series/count" | grep -o '"data":\[[0-9]*\]' | grep -o '[0-9]*')
  echo "tenant ${t}: ${n}"
done

echo ""
echo "=== [5] verbose 模式跑 vm-native，看它实际请求什么 URL ==="
docker run --rm --network host victoriametrics/vmctl:v1.151.0 vm-native \
  --verbose \
  --vm-native-src-addr=http://localhost:8481/select/0/prometheus \
  --vm-native-dst-addr=http://localhost:8480/insert/4242/prometheus \
  --vm-native-filter-time-start="2026-09-02T00:00:00Z" \
  --vm-native-filter-match='{__name__=~"l12r_marker_a"}' \
  -s --disable-progress-bar 2>&1 | head -40
