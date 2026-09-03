#!/bin/bash
# 定位：influx 写入计数涨到 2000，但为什么查不到？
Q() { curl -s --max-time 15 --data-urlencode "query=$1" http://localhost:8428/api/v1/query; }
Q1() { curl -s --max-time 15 --data-urlencode "query=$1" --data-urlencode "time=$2" http://localhost:8428/api/v1/query; }

echo "=============================================="
echo " T1 探针数据到底叫什么名字？"
echo "=============================================="
echo "  课 4 的教训：Influx line protocol 的【字段名一律拼进指标名】"
echo "  我写的是: l06_probe_a value=1"
echo "  → 实际指标名可能是 l06_probe_a_value ！"
echo
echo "-- 按前缀搜所有 l06 开头的指标 --"
curl -s --max-time 15 'http://localhost:8428/api/v1/label/__name__/values' \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)['data']
hit=[m for m in d if m.startswith('l06')]
print('  l06* 指标列表:')
for m in sorted(hit): print('   ', m)
if not hit: print('    (无)')
" 2>&1

echo
echo "=============================================="
echo " T2 直接查带 _value 后缀的名字"
echo "=============================================="
for m in l06_probe_a_value l06_probe_b_value l06_probe_c_value l06_probe_d_value l06_constant_value; do
  R=$(Q "count($m)" | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
print(int(float(d[0]["value"][1])) if d else 0)' 2>/dev/null)
  echo "  $m : $R 条"
done

echo
echo "=============================================="
echo " T3 用 tsdb status 看真实指标名（权威）"
echo "=============================================="
curl -s --max-time 15 'http://localhost:8428/api/v1/status/tsdb' \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)['data']
print('  totalSeries:', d.get('totalSeries'))
print('  序列数最多的前 15 个指标:')
for it in d.get('seriesCountByMetricName',[])[:15]:
    n=it.get('name','')
    print('    %-42s %8d' % (n, it.get('value',0)))
" 2>&1

echo
echo "=============================================="
echo " T4 确认 influx 计数涨了多少（说明确实写入了）"
echo "=============================================="
Q 'sum(vm_rows_inserted_total{type="influx"})' | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
print("  influx 累计:", int(float(d[0]["value"][1])) if d else "无")' 2>/dev/null
Q 'sum(vm_rows_ignored_total)' | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
print("  vm_rows_ignored_total:", int(float(d[0]["value"][1])) if d else "无")' 2>/dev/null
Q 'sum(vm_rows_invalid_total)' | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
print("  vm_rows_invalid_total:", int(float(d[0]["value"][1])) if d else "无")' 2>/dev/null
