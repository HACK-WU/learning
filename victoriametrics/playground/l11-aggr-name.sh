#!/bin/bash
echo "=== 1. tenant 79 中所有含 'up' 的指标名 ==="
curl -s "http://localhost:8487/select/79/prometheus/api/v1/label/__name__/values" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
names=[n for n in d['data'] if 'up' in n.lower()]
print('  匹配数 =', len(names))
for n in names: print('   ', n)
" 2>/dev/null

echo
echo "=== 2. up 的时间序列（看 10 是怎么来的）==="
NOW=$(date +%s)
curl -s "http://localhost:8487/select/79/prometheus/api/v1/query_range?query=up&start=$((NOW-300))&end=$NOW&step=30" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
for r in d['data']['result']:
    vals=[p[1] for p in r['values']]
    print('  job=%-14s 最近值序列=%s' % (r['metric'].get('job'), vals[-8:]))
" 2>/dev/null

echo
echo "=== 3. tenant 0 中 up 的对照（同一时刻）==="
curl -s "http://localhost:8487/select/0/prometheus/api/v1/query_range?query=up&start=$((NOW-300))&end=$NOW&step=30" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
for r in d['data']['result']:
    vals=[p[1] for p in r['values']]
    print('  job=%-14s 最近值序列=%s' % (r['metric'].get('job'), vals[-8:]))
" 2>/dev/null

echo
echo "=== 4. 结论判定 ==="
echo "  若 tenant 79 的 up 值 > tenant 0，说明聚合结果写回了同名指标 up"
