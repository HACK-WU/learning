#!/usr/bin/env bash
# 排查 OpenTSDB 400 与 CSV 落库 0 条：读取服务端错误响应体
set -u
VM=http://localhost:8428
NOW=$(date +%s)

echo "########## 1. OpenTSDB /api/put 返回 400，看错误内容 ##########"
OTS='{"metric":"l04.opentsdb.test","timestamp":'"$NOW"',"value":18,"tags":{"host":"web01"}}'
echo "  请求体: $OTS"
echo "  响应:"
curl -s -m 10 -X POST "$VM/api/put" --data-binary "$OTS" 2>&1 | sed 's/^/    /'
echo

echo "  --- 用 HTTP 专用端口 4243 再试 ---"
curl -s -m 10 -X POST "http://localhost:4243/api/put" --data-binary "$OTS" \
  -w "\n    http=%{http_code}\n" 2>&1 | sed 's/^/    /'
echo

echo "  --- 用数组格式（OpenTSDB 支持批量）---"
OTSA='[{"metric":"l04.opentsdb.arr","timestamp":'"$NOW"',"value":18,"tags":{"host":"web01"}}]'
curl -s -m 10 -X POST "http://localhost:4243/api/put" --data-binary "$OTSA" \
  -w "\n    http=%{http_code}\n" 2>&1 | sed 's/^/    /'
echo

echo "  --- 用 telnet 协议（4242，put 命令）---"
printf 'put l04.opentsdb.telnet %d 18 host=web01\n' "$NOW" \
  | timeout 5 nc -q0 127.0.0.1 4242 2>&1 | sed 's/^/    /' \
  || echo "    (nc 不可用)"
echo "  --- 用 bash /dev/tcp 走 telnet 协议 ---"
exec 3<>/dev/tcp/127.0.0.1/4242
printf 'put l04.opentsdb.telnet %d 18 host=web01\n' "$NOW" >&3
sleep 1
exec 3<&-
curl -s -m 30 -o /dev/null "$VM/internal/force_flush"
sleep 2
echo "  落库检查："
curl -s -m 15 -G "$VM/api/v1/series" \
  --data-urlencode 'match[]={__name__=~"l04.opentsdb.*"}' \
| python3 -c '
import sys,json
d=json.load(sys.stdin)["data"]
print("    落库 {} 条".format(len(d)))
for m in d: print("      ", m)
'

echo
echo "########## 2. CSV 落库 0 条：用 export 确认 + 试最简格式 ##########"
echo "  --- 2a. 最简 CSV：只有指标名和值，无时间戳 ---"
curl -s -m 15 -G "$VM/api/v1/import/csv" \
  --data-urlencode 'format=1:metric:l04_csv_simple,2:metric:value' \
  --data-urlencode 'data=l04_csv_simple,3.14' \
  -w "    http=%{http_code}\n" | sed 's/^/    /'
curl -s -m 30 -o /dev/null "$VM/internal/force_flush"
sleep 2
curl -s -m 15 -G "$VM/api/v1/series" \
  --data-urlencode 'match[]={__name__=~"l04_csv.*"}' \
| python3 -c '
import sys,json
d=json.load(sys.stdin)["data"]
print("    落库 {} 条".format(len(d)))
for m in d: print("      ", m)
'

echo
echo "  --- 2b. 用 POST body 传 CSV（不用 data 参数）---"
CSV="l04_csv_body,hostA,3.14,${NOW}"
echo "    数据: $CSV"
curl -s -m 15 -X POST "$VM/api/v1/import/csv?format=1:metric:l04_csv_body,2:label:host,3:metric:value,4:time:unix_s" \
  --data-binary "$CSV" -w "    http=%{http_code}\n" | sed 's/^/    /'
curl -s -m 30 -o /dev/null "$VM/internal/force_flush"
sleep 2
curl -s -m 15 -G "$VM/api/v1/series" \
  --data-urlencode 'match[]={__name__=~"l04_csv.*"}' \
| python3 -c '
import sys,json
d=json.load(sys.stdin)["data"]
print("    落库 {} 条".format(len(d)))
for m in d: print("      ", m)
'

echo
echo "  --- 2c. 对照：/api/v1/import（Prometheus 文本）是否正常 ---"
curl -s -m 15 -X POST "$VM/api/v1/import/prometheus" \
  --data-binary "l04_import_ctrl{job=\"ctrl\"} 55 ${NOW}" \
  -w "    http=%{http_code}\n" | sed 's/^/    /'
curl -s -m 30 -o /dev/null "$VM/internal/force_flush"
sleep 2
curl -s -m 15 -G "$VM/api/v1/query" --data-urlencode 'query=l04_import_ctrl' \
  --data-urlencode "time=$NOW" --data-urlencode "nocache=1" \
| python3 -c '
import sys,json
r=json.load(sys.stdin)["data"]["result"]
print("    对照组落库 {} 条".format(len(r)))
for it in r: print("      ", it["metric"], "=", it["value"][1])
'
