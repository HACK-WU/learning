#!/bin/bash
# 摸清 vminsert 支持哪些写入路径 + 查询路径
set -u
echo "=============================================="
echo " A. vminsert (8480) 支持的写入路径"
echo "=============================================="
for P in "/insert/100/influx/write" \
         "/insert/100/prometheus/write" \
         "/insert/100/prometheus/api/v1/write" \
         "/insert/100/prometheus/api/v1/import" \
         "/insert/100/influx/api/v2/write" \
         "/insert/100/opentsdb/api/put" \
         "/insert/100/csv/import" \
         "/insert/100/graphite/write" \
         "/insert/100/native/write"; do
  printf "    %-44s " "$P"
  curl -s -o /dev/null -w 'HTTP %{http_code}\n' -X POST --max-time 15 \
    --data-binary 'l10_probe,idx=1 value=1' \
    "http://localhost:8480$P"
done

echo
echo "  ⚠️ 上面的 body 是 Influx 行协议，非 Influx 端点会因格式不对报错"
echo "     重点看哪些是 400 unsupported path（路径本身不支持）"
echo "     哪些是 204/其它（路径存在，只是 body 格式问题）"

echo
echo "=============================================="
echo " B. 看 vminsert 启动日志里的路径清单"
echo "=============================================="
docker logs vminsert-learn 2>&1 | grep -iE 'supported|path|endpoint' | head -15

echo
echo "=============================================="
echo " C. 用正确的协议 body 再测关键路径"
echo "=============================================="
echo "  -- Influx 行协议 + 时间戳 --"
printf "    /insert/100/influx/write:          "
curl -s -o /dev/null -w 'HTTP %{http_code}\n' -X POST --max-time 15 \
  --data-binary "l10_probe,idx=1 value=1 $(($(date +%s)*1000000000))" \
  'http://localhost:8480/insert/100/influx/write'

echo "  -- Prometheus remote write (需要 snappy protobuf) --"
printf "    /insert/100/prometheus/api/v1/write: "
curl -s -o /dev/null -w 'HTTP %{http_code}\n' -X POST --max-time 15 \
  -H 'Content-Type: application/x-protobuf' \
  -H 'Content-Encoding: snappy' \
  --data-binary $'\x00' \
  'http://localhost:8480/insert/100/prometheus/api/v1/write'

echo
echo "=============================================="
echo " D. vmselect (8481) 支持的查询路径"
echo "=============================================="
for P in "/select/100/prometheus/api/v1/query" \
         "/select/100/prometheus/api/v1/query_range" \
         "/select/100/prometheus/api/v1/labels" \
         "/select/100/prometheus/api/v1/series" \
         "/select/100/prometheus/api/v1/export" \
         "/select/100/prometheus/api/v1/status/tsdb"; do
  printf "    %-48s " "$P"
  curl -s -o /dev/null -w 'HTTP %{http_code}\n' --max-time 15 \
    --data-urlencode 'query=up' "http://localhost:8481$P"
done

echo
echo "=============================================="
echo " E. 结论：给 vmauth 用的正确路径映射"
echo "=============================================="
echo "  查询: /api/v1/query"
echo "        → url_prefix: http://vmselect:8481/select/<T>/prometheus"
echo "        → 拼接: /select/<T>/prometheus/api/v1/query  ✓"
echo
echo "  写入(Influx 行协议):"
echo "        src_paths:  ['/write']"
echo "        url_prefix: ['http://vminsert:8480/insert/<T>/influx']"
echo "        → 拼接: /insert/<T>/influx/write  ✓"
echo
echo "  写入(Prometheus remote write):"
echo "        src_paths:  ['/api/v1/write']"
echo "        url_prefix: ['http://vminsert:8480/insert/<T>/prometheus']"
echo "        → 拼接: /insert/<T>/prometheus/api/v1/write"
echo "          需确认该路径是否存在（见上面 A 段）"
