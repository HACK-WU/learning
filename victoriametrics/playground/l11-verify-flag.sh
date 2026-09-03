#!/bin/bash
echo "=== 1. maxDiskUsagePerURL 的官方语义 ==="
docker run --rm victoriametrics/vmagent:v1.151.0 --help 2>/dev/null \
  | grep -A4 "maxDiskUsagePerURL" | head -12

echo
echo "=== 2. seriesLimitPerTarget 的官方语义 ==="
docker run --rm victoriametrics/vmagent:v1.151.0 --help 2>/dev/null \
  | grep -A3 "seriesLimitPerTarget" | head -8

echo
echo "=== 3. maxScrapeSize 的官方语义 ==="
docker run --rm victoriametrics/vmagent:v1.151.0 --help 2>/dev/null \
  | grep -A3 "maxScrapeSize" | head -8

echo
echo "=== 4. 流式聚合相关 flag 语义 ==="
docker run --rm victoriametrics/vmagent:v1.151.0 --help 2>/dev/null \
  | grep -A3 "streamAggr.keepInput\|streamAggr.dropInput\b" | head -14
