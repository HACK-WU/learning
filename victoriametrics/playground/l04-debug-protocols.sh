#!/usr/bin/env bash
# 课 4 疑点排查：Influx 写入返回 204 但查不到；CSV 返回 400
set -u
VM=http://localhost:8428
FMT=/mnt/d/projects/learning/victoriametrics/playground/l04-fmt.py
NOW=$(date +%s)

echo "########## 疑点 1：Influx 写入 http=204 但查不到 ##########"
echo "  204 = 服务端已接受。查不到通常是【查询时间窗】问题："
echo "  VM 默认只返回 lookbehind 窗口内的数据，而我写的是当前时间戳。"
echo
echo "  当前时间: $(date '+%H:%M:%S') (ts=$NOW)"

echo
echo "--- 1a. 用 export 接口直接读回（绕过查询窗口逻辑）---"
curl -s -m 20 -G "$VM/api/v1/export" \
  --data-urlencode 'match[]=cpu_load_short' \
  --data-urlencode "start=$((NOW-600))" --data-urlencode "end=$((NOW+60))" \
| head -3
echo "  (上面若输出 JSON 行则说明数据确实写进去了)"

echo
echo "--- 1b. 检查时间戳单位：纳秒 vs 秒 ---"
echo "  我写的时间戳: ${NOW}000000000  (纳秒)"
echo "  正确的纳秒   : $((NOW * 1000000000))"
echo "  两者是否相等: $([ "${NOW}000000000" = "$((NOW * 1000000000))" ] && echo 是 || echo 否)"

echo
echo "--- 1c. 用秒级时间戳重试 ---"
curl -s -m 15 -o /dev/null -w "    秒级写入 http=%{http_code}\n" \
  -X POST "$VM/write" \
  --data-binary "l04_influx_s,host=s1 value=1.5 ${NOW}"
curl -s -m 15 -o /dev/null -w "    毫秒级写入 http=%{http_code}\n" \
  -X POST "$VM/write" \
  --data-binary "l04_influx_ms,host=s1 value=2.5 $((NOW * 1000))"
curl -s -m 15 -o /dev/null -w "    纳秒级写入 http=%{http_code}\n" \
  -X POST "$VM/write" \
  --data-binary "l04_influx_ns,host=s1 value=3.5 $((NOW * 1000000000))"
curl -s -m 15 -o /dev/null "$VM/internal/force_flush"
sleep 2
for m in l04_influx_s l04_influx_ms l04_influx_ns; do
  echo "--- 查 $m ---"
  curl -s -m 15 -G "$VM/api/v1/query" --data-urlencode "query=$m" \
    --data-urlencode "nocache=1" | python3 "$FMT" | sed -n '2,3p'
done

echo
echo "########## 疑点 2：CSV import 返回 400 ##########"
echo "  /api/v1/import/csv 必须通过 URL query arg 指定 format，"
echo "  我用的 --data-urlencode 把 format 放进了 body，应该用 -G 拼到 URL。"
echo
echo "--- 2a. 用正确方式重试（-G 拼 URL）---"
CSV="l04_csv_ok,host,h1,dc,dc1,3.14,${NOW}
l04_csv_ok,host,h2,dc,dc1,2.71,${NOW}"
curl -s -m 15 -o /dev/null -w "    http=%{http_code}\n" -G \
  "$VM/api/v1/import/csv" \
  --data-urlencode 'format=1:metric:host,2:metric:dc,3:metric:value,4:time:unix_s' \
  --data-urlencode "data=$CSV"
curl -s -m 15 -o /dev/null "$VM/internal/force_flush"
sleep 2
echo "--- 查 l04_csv_ok ---"
curl -s -m 15 -G "$VM/api/v1/query" --data-urlencode 'query=l04_csv_ok' \
  --data-urlencode "nocache=1" | python3 "$FMT"

echo
echo "--- 2b. 完整错误响应（看服务端到底说什么）---"
curl -s -m 15 -G "$VM/api/v1/import/csv" \
  --data-urlencode 'format=1:metric:host,2:metric:dc,3:metric:value,4:time:unix_s' \
  --data-urlencode "data=$CSV" -w "\n    http=%{http_code}\n" -o /dev/null
echo "    再试一次不带 format:"
curl -s -m 15 -X POST "$VM/api/v1/import/csv" --data-binary "$CSV" \
  -w "\n    http=%{http_code}\n" | tail -3

echo
echo "########## 疑点 3：原生 import 也是 204 但查不到 ##########"
echo "--- 3a. export 读回验证 ---"
curl -s -m 20 -G "$VM/api/v1/export" \
  --data-urlencode 'match[]=l04_native_test' \
  --data-urlencode "start=$((NOW-600))" --data-urlencode "end=$((NOW+60))" | head -3
echo
echo "--- 3b. 带 nocache 且指定 time 精确查询 ---"
curl -s -m 15 -G "$VM/api/v1/query" \
  --data-urlencode 'query=l04_native_test' \
  --data-urlencode "time=$NOW" --data-urlencode "nocache=1" | python3 "$FMT"
