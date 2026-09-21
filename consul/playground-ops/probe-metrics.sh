#!/usr/bin/env bash
echo "===== 直接看返回体 ====="
curl -si 'http://127.0.0.1:8501/v1/agent/metrics?format=prometheus' | head -20

echo
echo "===== 默认 JSON 的前几个 gauge 名 ====="
curl -s 'http://127.0.0.1:8501/v1/agent/metrics' | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('Gauges:')
for k in list(d.get('Gauges',{}))[:25]: print('  ',k)
print('Counters:',list(d.get('Counters',{}))[:10])
print('Samples:',list(d.get('Samples',{}))[:10])
"
