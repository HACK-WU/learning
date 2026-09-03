#!/usr/bin/env bash
# 课 4 疑点排查 v3：为什么 l04_multi 成功但 l04_influx_s/_ms/_ns 失败？
set -u
VM=http://localhost:8428
FMT=/mnt/d/projects/learning/victoriametrics/playground/l04-fmt.py
NOW_SEC=$(date +%s)
NOW_MS=$((NOW_SEC * 1000))
NOW_NS=$((NOW_SEC * 1000000000))

echo "########## 假设：VM 把 _s / _ms / _ns 后缀识别为【单位标识符】##########"
echo "  InfluxDB line protocol 在 VM 中有特殊处理："
echo "  指标名以 _s / _ms / _ns / _seconds 等结尾时，VM 可能将其视为时间单位后缀并改写指标名。"
echo

echo "--- 1. 写入一批带不同后缀的指标，用统一时间戳 ---"
for suffix in "" "_s" "_ms" "_ns" "_raw" "_test_s"; do
  name="l04_sfx${suffix}"
  curl -s -m 10 -o /dev/null -X POST "$VM/write" \
    --data-binary "${name},host=h1 value=7 ${NOW_NS}"
  echo "    写入 ${name}"
done
curl -s -m 30 -o /dev/null "$VM/internal/force_flush"
sleep 2

echo
echo "--- 2. 逐个查询（应只有不带单位后缀的成功）---"
for suffix in "" "_s" "_ms" "_ns" "_raw" "_test_s"; do
  name="l04_sfx${suffix}"
  printf '    %-16s → ' "$name"
  curl -s -m 15 -G "$VM/api/v1/query" --data-urlencode "query=$name" \
    --data-urlencode "time=$NOW_SEC" --data-urlencode "nocache=1" \
  | python3 -c '
import sys,json
r=json.load(sys.stdin)["data"]["result"]
print("命中 {} 条".format(len(r)) if r else "0 条")
'
done

echo
echo "--- 3. 用 series 接口列出所有 l04_sfx* 实际落库的指标名 ---"
curl -s -m 20 -G "$VM/api/v1/series" \
  --data-urlencode 'match[]={__name__=~"l04_sfx.*"}' \
| python3 -c '
import sys,json
d=json.load(sys.stdin)["data"]
print("    实际落库 {} 条：".format(len(d)))
for m in d:
    print("      ", m.get("__name__"), {k:v for k,v in m.items() if k!="__name__"})
'

echo
echo "########## 验证：CSV 三段式格式 ##########"
echo "--- 4. CSV 用 metric 名 + 标签名 + value 的完整三段式 ---"
echo "    数据: 指标名,host值,dc值,指标值,时间戳"
CSV="l04_csv_v3,hostA,dcX,3.14,${NOW_SEC}
l04_csv_v3,hostB,dcX,2.71,${NOW_SEC}"
echo "$CSV" | sed 's/^/      /'
echo
echo "  format 逐段解析："
echo "    1:metric:host  → 第1列(索引1)=metric 类型的 host 标签"
echo "    2:metric:dc    → 第2列=dc 标签"
echo "    3:metric:value → 第3列=值"
echo "    4:time:unix_s  → 第4列=秒级时间戳"
curl -s -m 15 -o /dev/null -w "    http=%{http_code}\n" -G \
  "$VM/api/v1/import/csv" \
  --data-urlencode 'format=1:metric:host,2:metric:dc,3:metric:value,4:time:unix_s' \
  --data-urlencode "data=$CSV"
curl -s -m 30 -o /dev/null "$VM/internal/force_flush"
sleep 2
echo "--- 查 l04_csv_v3 ---"
curl -s -m 15 -G "$VM/api/v1/query" \
  --data-urlencode 'query=l04_csv_v3' \
  --data-urlencode "time=$NOW_SEC" --data-urlencode "nocache=1" | python3 "$FMT"

echo
echo "--- 5. 用 series 接口看 CSV 到底落库成什么名字 ---"
curl -s -m 20 -G "$VM/api/v1/series" \
  --data-urlencode 'match[]={__name__=~"l04_csv.*"}' \
| python3 -c '
import sys,json
d=json.load(sys.stdin)["data"]
print("    落库 {} 条：".format(len(d)))
for m in d:
    print("      ", m.get("__name__"), {k:v for k,v in m.items() if k!="__name__"})
'
