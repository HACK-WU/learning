#!/usr/bin/env bash
# 课 4 协议实测（正确版）：Influx 字段名映射规则 + CSV 正确用法
set -u
VM=http://localhost:8428
FMT=/mnt/d/projects/learning/victoriametrics/playground/l04-fmt.py
NOW_SEC=$(date +%s)
NOW_NS=$((NOW_SEC * 1000000000))

echo "########## A. InfluxDB line protocol：字段名的映射规则 ##########"
echo "  关键规则：measurement + field 名 → VM 指标名"
echo "    measurement 无 field（单值） → metric = measurement"
echo "    measurement 有 field 名     → metric = measurement_fieldname"
echo

echo "--- A1. 不带 field 名（measurement,标签 value=数）---"
curl -s -m 10 -o /dev/null -X POST "$VM/write" \
  --data-binary "l04_inf_a,host=h1 value=11 ${NOW_NS}"
echo "--- A2. 带 field 名 ---"
curl -s -m 10 -o /dev/null -X POST "$VM/write" \
  --data-binary "l04_inf_b,host=h1 load=22 ${NOW_NS}"
echo "--- A3. 多 field（自动展开）---"
curl -s -m 10 -o /dev/null -X POST "$VM/write" \
  --data-binary "l04_inf_c,host=h1 ext=25,int=37 ${NOW_NS}"
curl -s -m 30 -o /dev/null "$VM/internal/force_flush"
sleep 2

echo
echo "  实际落库的指标名："
curl -s -m 20 -G "$VM/api/v1/series" \
  --data-urlencode 'match[]={__name__=~"l04_inf_.*"}' \
| python3 -c '
import sys,json
d=json.load(sys.stdin)["data"]
for m in sorted(d, key=lambda x: x.get("__name__","")):
    print("      ", m.get("__name__"), {k:v for k,v in m.items() if k!="__name__"})
'

echo
echo "--- A1 查 l04_inf_a（单值，无 field 名）---"
curl -s -m 15 -G "$VM/api/v1/query" --data-urlencode 'query=l04_inf_a' \
  --data-urlencode "time=$NOW_SEC" --data-urlencode "nocache=1" | python3 "$FMT"
echo "--- A2 查 l04_inf_b_load（有 field 名 load）---"
curl -s -m 15 -G "$VM/api/v1/query" --data-urlencode 'query=l04_inf_b_load' \
  --data-urlencode "time=$NOW_SEC" --data-urlencode "nocache=1" | python3 "$FMT"
echo "--- A3 查 l04_inf_c_ext / _int（多 field 展开）---"
curl -s -m 15 -G "$VM/api/v1/query" \
  --data-urlencode 'query={__name__=~"l04_inf_c_.*"}' \
  --data-urlencode "time=$NOW_SEC" --data-urlencode "nocache=1" | python3 "$FMT"

echo
echo "########## B. CSV import 正确用法 ##########"
echo "  之前失败原因：CSV 第一列是【指标名+标签值混排】，VM 需要 format 明确每列含义。"
echo "  尝试用 -G + format + data 的组合，以及 POST body 两种写法对照。"
echo

echo "--- B1. 标准写法：format 中显式声明 metric 名列 ---"
CSV1="l04_csv_a,hostA,3.14,${NOW_SEC}
l04_csv_a,hostB,2.71,${NOW_SEC}"
echo "    数据:"; echo "$CSV1" | sed 's/^/      /'
echo "    format: 1:metric:l04_csv_a,2:label:host,3:metric:value,4:time:unix_s"
curl -s -m 15 -o /dev/null -w "    http=%{http_code}\n" -G \
  "$VM/api/v1/import/csv" \
  --data-urlencode 'format=1:metric:l04_csv_a,2:label:host,3:metric:value,4:time:unix_s' \
  --data-urlencode "data=$CSV1"

echo
echo "--- B2. 用 metric 列 + 标签列分离（第一列固定指标名）---"
CSV2="l04_csv_b,hostA,dcX,3.14,${NOW_SEC}
l04_csv_b,hostB,dcY,2.71,${NOW_SEC}"
echo "    数据:"; echo "$CSV2" | sed 's/^/      /'
echo "    format: 1:metric:__name__,2:label:host,3:label:dc,4:metric:value,5:time:unix_s"
curl -s -m 15 -o /dev/null -w "    http=%{http_code}\n" -G \
  "$VM/api/v1/import/csv" \
  --data-urlencode 'format=1:metric:__name__,2:label:host,3:label:dc,4:metric:value,5:time:unix_s' \
  --data-urlencode "data=$CSV2"

curl -s -m 30 -o /dev/null "$VM/internal/force_flush"
sleep 2

echo
echo "  实际落库："
curl -s -m 20 -G "$VM/api/v1/series" \
  --data-urlencode 'match[]={__name__=~"l04_csv.*"}' \
| python3 -c '
import sys,json
d=json.load(sys.stdin)["data"]
print("    落库 {} 条".format(len(d)))
for m in d:
    print("      ", m.get("__name__"), {k:v for k,v in m.items() if k!="__name__"})
'
