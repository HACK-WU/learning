#!/usr/bin/env bash
# VM 课 0 定论验证：写入 → 未刷盘查不到 → force_flush → 查得到（重复两轮，排除偶然）
set -u
BASE="http://localhost:8428"

probe() {
  # $1 = 轮次标签, $2 = 指标名
  local round="$1" metric="$2"
  local now
  now=$(date +%s)

  echo "----- 轮次 ${round}：${metric} -----"
  curl -s -m 10 -w "  write_http=%{http_code}\n" -X POST "$BASE/api/v1/import/prometheus" \
    --data-binary "${metric}{job=\"flush${round}\"} ${round} ${now}" >/dev/null

  sleep 2
  echo -n "  刷盘前 query : "
  curl -s -m 10 --data-urlencode "query=${metric}{job=\"flush${round}\"}" "$BASE/api/v1/query" \
    | python3 -c 'import sys,json; d=json.load(sys.stdin)["data"]["result"]; print(f"命中 {len(d)} 条")'

  echo -n "  刷盘前 export: "
  curl -s -m 10 --data-urlencode "match[]=${metric}{job=\"flush${round}\"}" "$BASE/api/v1/export" \
    | python3 -c 'import sys; print(f"命中 {len([l for l in sys.stdin if l.strip()])} 条")'

  curl -s -m 10 -o /dev/null -w "  force_flush_http=%{http_code}\n" "$BASE/internal/force_flush"
  sleep 2

  echo -n "  刷盘后 query : "
  curl -s -m 10 --data-urlencode "query=${metric}{job=\"flush${round}\"}" "$BASE/api/v1/query" \
    | python3 -c 'import sys,json; d=json.load(sys.stdin)["data"]["result"]; print(f"命中 {len(d)} 条")'

  echo -n "  刷盘后 export: "
  curl -s -m 10 --data-urlencode "match[]=${metric}{job=\"flush${round}\"}" "$BASE/api/v1/export" \
    | python3 -c 'import sys; print(f"命中 {len([l for l in sys.stdin if l.strip()])} 条")'
  echo
}

echo "=== 验证一：两轮重复，确认「刷盘前后」差异稳定复现 ==="
probe 1 flush_probe_a
probe 2 flush_probe_b

echo "=== 验证二：刷盘后普通查询仍可见（不是瞬时状态）==="
sleep 5
curl -s -m 10 --data-urlencode 'query=flush_probe_a' "$BASE/api/v1/query" | head -c 300
echo
curl -s -m 10 --data-urlencode 'query=flush_probe_b' "$BASE/api/v1/query" | head -c 300
echo

echo
echo "=== 验证三：时间戳精度对照（秒 vs 毫秒，同样落库后看真实值）==="
NOW=$(date +%s)
curl -s -m 10 -o /dev/null -X POST "$BASE/api/v1/import/prometheus" --data-binary "ts_cmp{mode=\"sec\"} 1 ${NOW}"
curl -s -m 10 -o /dev/null -X POST "$BASE/api/v1/import/prometheus" --data-binary "ts_cmp{mode=\"ms\"}  2 ${NOW}123"
curl -s -m 10 -o /dev/null "$BASE/internal/force_flush"
sleep 2
echo "写入值：sec 模式传 ${NOW}（10 位秒），ms 模式传 ${NOW}123（13 位毫秒）"
echo -n "export 实际存储："
curl -s -m 10 --data-urlencode 'match[]=ts_cmp' "$BASE/api/v1/export"

echo
echo "=== 验证四：Prometheus remote write 需要 snappy+protobuf（裸文本必然失败）==="
curl -s -m 10 -w "http=%{http_code}\n" -X POST "$BASE/prometheus/api/v1/write" \
  --data-binary 'raw_text_metric{job="x"} 1'
