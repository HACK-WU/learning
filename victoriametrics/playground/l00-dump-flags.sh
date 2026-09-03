#!/usr/bin/env bash
# 抓取 VictoriaMetrics 单节点关键启动参数的默认值与说明
set -u
OUT="/mnt/d/projects/learning/victoriametrics/playground/l00-flags-dump.txt"
DOCKER_NAME="${DOCKER_NAME:-vm-learn}"

docker exec "$DOCKER_NAME" /victoria-metrics-prod --help >"$OUT" 2>&1
echo "已导出到 $OUT，共 $(wc -l <"$OUT") 行"
echo
echo "=== 关键参数摘录 ==="
grep -A3 -E '^  -(retentionPeriod|memory\.allowedPercent|search\.maxUniqueTimeseries|search\.maxConcurrentRequests|search\.maxSeries|maxLabelsPerTimeseries|dedup\.minScrapeInterval|search\.maxStalenessInterval|search\.setLookbackToStep|search\.cacheTimestampOffset|search\.disableAutoCacheReset|search\.maxQueryLen|maxInsertRequestSize|influx\.maxLineSize)\b' "$OUT"
