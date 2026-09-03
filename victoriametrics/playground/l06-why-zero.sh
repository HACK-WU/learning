#!/bin/bash
# 排查：三组数据 ZSTD 增量证明写进去了，但 count() 查不到
Q() { curl -s --max-time 20 --data-urlencode "query=$1" http://localhost:8428/api/v1/query; }
QT() { curl -s --max-time 20 --data-urlencode "query=$1" --data-urlencode "time=$2" http://localhost:8428/api/v1/query; }

echo "=============================================="
echo " W1 数据在 tsdb status 里吗（权威：不看查询，看索引）"
echo "=============================================="
curl -s --max-time 20 'http://localhost:8428/api/v1/status/tsdb' \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)['data']
print('  totalSeries:', d.get('totalSeries'))
hit=[it for it in d.get('seriesCountByMetricName',[]) if 'l06' in it.get('name','')]
print('  l06* 指标:')
for it in hit: print('    %-30s %8d' % (it['name'], it['value']))
" 2>&1

echo
echo "=============================================="
echo " W2 时间窗口假设：写入时间戳在未来？"
echo "=============================================="
NOW=$(date +%s)
echo "  当前 epoch: $NOW  ($(date -u '+%Y-%m-%d %H:%M:%S'))"
echo "  实验写入的时间戳: NOW ~ NOW+90 秒"
echo "  查询默认 time = 服务器当前时间"
echo
echo "  关键：如果查询时刻 < 数据时间戳，count() 就查不到！"

echo
echo "-- 用未来时间点查（write time + 120s）--"
FUT=$((NOW + 120))
for m in l06_a_const_value l06_b_slow_value l06_c_random_value; do
  R=$(QT "count($m)" "$FUT" | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
print(int(float(d[0]["value"][1])) if d else 0)' 2>/dev/null)
  echo "  count($m) @ +120s : $R"
done

echo
echo "-- 用 range query 跨窗口查（更可靠）--"
for m in l06_a_const_value l06_b_slow_value l06_c_random_value; do
  R=$(curl -s --max-time 20 --data-urlencode "query=count_over_time($m[10m])" \
     --data-urlencode "time=$FUT" http://localhost:8428/api/v1/query \
     | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
t=sum(float(r["value"][1]) for r in d)
print(int(t))' 2>/dev/null)
  echo "  count_over_time($m[10m]) @ +120s : $R 个样本"
done

echo
echo "=============================================="
echo " W3 时间精度问题：我传的是纳秒，VM 怎么存？"
echo "=============================================="
echo "  influx 行样本:"
head -1 /tmp/l06_a_const.influx 2>/dev/null
echo "  长度: $(head -1 /tmp/l06_a_const.influx 2>/dev/null | awk -F' ' '{print $3}' | wc -c) 位（含换行）"
TS_RAW=$(head -1 /tmp/l06_a_const.influx 2>/dev/null | awk -F' ' '{print $3}')
echo "  原始时间戳: $TS_RAW (${#TS_RAW} 位)"
echo "  若为纳秒: $(echo "$TS_RAW / 1000000000" | bc) 秒"
echo "  当前秒  : $NOW"

echo
echo "=============================================="
echo " W4 确认：数据到底落在哪个时间范围"
echo "=============================================="
echo "-- 用 /api/v1/series 查（不受时间窗口限制）--"
curl -s --max-time 20 --data-urlencode 'match[]=l06_a_const_value' \
  'http://localhost:8428/api/v1/series' 2>&1 | head -c 300
echo
echo
echo "-- 用 export 直接导原始样本（最权威，绕过查询引擎）--"
curl -s --max-time 30 --data-urlencode 'match[]=l06_a_const_value{idx="0"}' \
  'http://localhost:8428/api/v1/export' 2>&1 | head -c 500
echo
