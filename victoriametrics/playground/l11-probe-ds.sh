#!/bin/bash
echo "=== 1. 各 vmselect 上到底有没有 up 数据 ==="
for port in 8481 8487 8489; do
  n=$(curl -s "http://localhost:$port/select/0/prometheus/api/v1/query?query=up" 2>/dev/null | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin); print(len(d['data']['result']))
except: print('ERR')
" 2>/dev/null)
  echo "  vmselect :$port  -> up 序列数 = $n"
done

echo
echo "=== 2. 时间窗口检查：当前时间 vs 数据最后时间 ==="
NOW=$(date +%s)
echo "  当前 epoch = $NOW ($(date '+%F %T'))"
curl -s "http://localhost:8481/select/0/prometheus/api/v1/query?query=up" 2>/dev/null | python3 -c "
import sys,json,datetime
d=json.load(sys.stdin)
rs=d['data']['result']
if rs:
    ts=max(float(r['value'][0]) for r in rs)
    print('  最后样本时间 = %s' % datetime.datetime.fromtimestamp(ts).strftime('%F %T'))
    print('  距现在 = %.1f 秒' % (datetime.datetime.now().timestamp()-ts))
else:
    print('  无数据')
" 2>/dev/null

echo
echo "=== 3. 用 range query 看 up 的实际时间分布 ==="
curl -s "http://localhost:8481/select/0/prometheus/api/v1/query_range?query=up&start=$((NOW-3600))&end=$NOW&step=60" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
rs=d['data']['result']
print('  range 查询返回序列数:', len(rs))
for r in rs[:3]:
    pts=r['values']
    nonzero=[p for p in pts if float(p[1])!=0]
    print('     job=%-12s 点数=%d  非零点数=%d' % (r['metric'].get('job'), len(pts), len(nonzero)))
" 2>/dev/null

echo
echo "=== 4. 检查 WSL 与容器的时间是否一致 ==="
echo "  WSL 时间: $(date '+%F %T %Z')"
echo "  容器时间: $(docker exec vmagent-learn date '+%F %T %Z' 2>/dev/null)"
echo "  vmalert : $(docker exec vmalert-learn date '+%F %T %Z' 2>/dev/null)"

echo
echo "=== 5. vmalert 日志中的求值错误 ==="
docker logs vmalert-learn 2>&1 | tail -15
