#!/usr/bin/env bash
# CSV 最后定位：返回 204 但落库 0 条
set -u
VM=http://localhost:8428
NOW=$(date +%s)

echo "########## 1. 用 export 确认 CSV 到底写进去没有 ##########"
curl -s -m 20 -G "$VM/api/v1/export" \
  --data-urlencode 'match[]={__name__=~"l04_csv.*"}' \
  --data-urlencode "start=$((NOW-3600))" --data-urlencode "end=$((NOW+60))" \
| head -5
echo "  (无输出 = 确实没写进去)"

echo
echo "########## 2. 检查 CSV 字段名：VM 要求 format 里的列序号从 1 开始 ##########"
echo "  尝试 format 不用 metric 名而用 __name__ 作为 metric 列："
curl -s -m 15 -G "$VM/api/v1/import/csv" \
  --data-urlencode 'format=1:metric:__name__,2:label:host,3:metric:value,4:time:unix_s' \
  --data-urlencode "data=l04_csv_final,hostA,3.14,${NOW}" \
  -w "    http=%{http_code}\n"
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
echo "########## 3. 不带任何 metric 名，纯 label + value ##########"
curl -s -m 15 -G "$VM/api/v1/import/csv" \
  --data-urlencode 'format=1:label:host,2:metric:l04_csv_pure,3:metric:value,4:time:unix_s' \
  --data-urlencode "data=hostA,l04_csv_pure,3.14,${NOW}" \
  -w "    http=%{http_code}\n"
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
echo "########## 4. 查询 VM 自身统计，看 CSV 请求到底被怎么处理了 ##########"
echo "  --- vm_http_request_errors_total（按 path 看）---"
curl -s -m 15 -G "$VM/api/v1/query" \
  --data-urlencode 'query={__name__=~"vm_http_request_errors_total"}' \
  --data-urlencode "nocache=1" \
| python3 -c '
import sys,json
r=json.load(sys.stdin)["data"]["result"]
for it in r[:10]:
    if "csv" in str(it["metric"]).lower() or "import" in str(it["metric"]).lower():
        print("      ", it["metric"], "=", it["value"][1])
' 2>/dev/null | head -10

echo
echo "  --- vm_rows_inserted_total 按 type 分组 ---"
curl -s -m 15 -G "$VM/api/v1/query" \
  --data-urlencode 'query=sum(vm_rows_inserted_total) by (type)' \
  --data-urlencode "nocache=1" \
| python3 -c '
import sys,json
r=json.load(sys.stdin)["data"]["result"]
print("    命中 {} 条".format(len(r)))
for it in r[:15]:
    print("      ", {k:v for k,v in it["metric"].items() if k!="__name__"}, "=", it["value"][1])
'

echo
echo "########## 5. 结论性验证：CSV 是否只是需要特殊 Content-Type ##########"
CSV="l04_csv_ct,hostA,3.14,${NOW}"
echo "  --- 带 Content-Type: text/plain ---"
curl -s -m 15 -X POST "$VM/api/v1/import/csv?format=1:metric:l04_csv_ct,2:label:host,3:metric:value,4:time:unix_s" \
  -H 'Content-Type: text/plain' --data-binary "$CSV" -w "    http=%{http_code}\n"
curl -s -m 15 -X POST "$VM/api/v1/import/csv?format=1:metric:l04_csv_ct,2:label:host,3:metric:value,4:time:unix_s" \
  --data-urlencode "data=$CSV" -w "    http=%{http_code}\n"
curl -s -m 30 -o /dev/null "$VM/internal/force_flush"
sleep 2
curl -s -m 15 -G "$VM/api/v1/series" \
  --data-urlencode 'match[]={__name__=~"l04_csv.*"}' \
| python3 -c '
import sys,json
d=json.load(sys.stdin)["data"]
print("    最终落库 {} 条".format(len(d)))
for m in d: print("      ", m)
'
