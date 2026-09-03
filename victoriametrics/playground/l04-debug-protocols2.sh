#!/usr/bin/env bash
# 课 4 疑点排查 v2：用 nocache + 指定 time 复验各协议；修正 CSV 格式
set -u
VM=http://localhost:8428
FMT=/mnt/d/projects/learning/victoriametrics/playground/l04-fmt.py

echo "########## 验证 1：用 nocache + time 复验 Influx 写入 ##########"
echo "  课 2 结论：新写入的数据默认查不到，因为 -search.cacheTimestampOffset=5m"
echo "  默认查询会跳过最近 5 分钟的数据（认为它们还不完整）"
echo
NOW_SEC=$(date +%s)
NOW_MS=$((NOW_SEC * 1000))
NOW_NS=$((NOW_SEC * 1000000000))

for pair in "l04_influx_s:${NOW_SEC}" "l04_influx_ms:${NOW_MS}" "l04_influx_ns:${NOW_NS}"; do
  m="${pair%%:*}"; ts="${pair##*:}"
  echo "--- $m (写入时间戳=$ts) ---"
  curl -s -m 15 -G "$VM/api/v1/query" \
    --data-urlencode "query=$m" \
    --data-urlencode "time=$NOW_SEC" \
    --data-urlencode "nocache=1" | python3 "$FMT" | sed -n '2,3p'
done

echo
echo "########## 验证 2：三种时间戳单位 export 读回，看实际落库值 ##########"
for m in l04_influx_s l04_influx_ms l04_influx_ns; do
  echo "--- $m ---"
  curl -s -m 20 -G "$VM/api/v1/export" \
    --data-urlencode "match[]=$m" \
    --data-urlencode "start=$((NOW_SEC-3600))" --data-urlencode "end=$((NOW_SEC+60))" \
  | python3 -c '
import sys, json, datetime
found=False
for line in sys.stdin:
    line=line.strip()
    if not line: continue
    d=json.loads(line); found=True
    for t in d["timestamps"][:3]:
        print("    落库时间戳(ms):", t, "→", datetime.datetime.fromtimestamp(t/1000).strftime("%H:%M:%S"))
if not found: print("    (无数据)")
'
done

echo
echo "########## 验证 3：CSV 格式修正 ##########"
echo "  错误信息: entry #1 must have the following form: <column_pos>:<column_type>:<extension>"
echo "  原因：format 的每一段需要 3 段式（pos:type:ext），metric 段的 ext 是标签名"
echo
echo "  正确格式示例: 1:metric:host,2:metric:dc,3:metric:value,4:time:unix_s"
echo "  - 1:metric:host   → 第1列是 metric 的 host 标签"
echo "  - 3:metric:value  → 第3列是 metric 的值（ext 用 value 表示值列）"
echo
CSV="l04_csv_v2,hostA,dcX,3.14,${NOW_SEC}
l04_csv_v2,hostB,dcX,2.71,${NOW_SEC}"
echo "  数据行:"; echo "$CSV" | sed 's/^/    /'
curl -s -m 15 -o /dev/null -w "    http=%{http_code}\n" -G \
  "$VM/api/v1/import/csv" \
  --data-urlencode 'format=1:metric:host,2:metric:dc,3:metric:value,4:time:unix_s' \
  --data-urlencode "data=$CSV"
curl -s -m 30 -o /dev/null "$VM/internal/force_flush"
sleep 2
echo "--- 查 l04_csv_v2 ---"
curl -s -m 15 -G "$VM/api/v1/query" \
  --data-urlencode 'query=l04_csv_v2' \
  --data-urlencode "time=$NOW_SEC" --data-urlencode "nocache=1" | python3 "$FMT"

echo
echo "########## 验证 4：Influx 多字段展开 ##########"
curl -s -m 15 -o /dev/null -X POST "$VM/write" --data-binary \
  "l04_multi,machine=m1 external=25,internal=37 ${NOW_NS}"
curl -s -m 30 -o /dev/null "$VM/internal/force_flush"
sleep 2
echo "--- 查 l04_multi（多字段应展开为 l04_multi_external / _internal）---"
for m in l04_multi l04_multi_external l04_multi_internal; do
  echo "  -- $m --"
  curl -s -m 15 -G "$VM/api/v1/query" --data-urlencode "query=$m" \
    --data-urlencode "time=$NOW_SEC" --data-urlencode "nocache=1" \
  | python3 "$FMT" | sed -n '2,3p'
done

echo
echo "########## 验证 5：Graphite / OpenTSDB 需重启容器开启 ##########"
echo "  这两个协议默认关闭，必须重启 VM 并加参数："
echo "    -graphiteListenAddr=:2003"
echo "    -opentsdbListenAddr=:4242  -opentsdbHTTPListenAddr=:4242"
echo "  当前容器未加这些参数 → 端口未监听 → 协议不可用"
