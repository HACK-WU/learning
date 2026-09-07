#!/bin/bash
echo "=== 1. 看落盘告警的完整 annotations ==="
python3 -c "
import json,glob
fs=sorted(glob.glob('/mnt/d/projects/learning/grafana/projects/从告警到定位/实现/webhook/out/*.json'))
for f in fs:
    d=json.load(open(f))
    print('---', f.split('/')[-1])
    for a in d.get('alerts',[]):
        print('  labels:', json.dumps(a.get('labels',{}), ensure_ascii=False))
        print('  annotations:', json.dumps(a.get('annotations',{}), ensure_ascii=False))
        print('  valueString:', json.dumps(a.get('valueString',''), ensure_ascii=False))
" 2>&1
echo

echo "=== 2. 规则里的模板原文（provisioning 读进去的是什么）==="
curl -s --noproxy '*' -u admin:admin http://localhost:3130/api/v1/provisioning/alert-rules/shop-p90-latency 2>&1 | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('  title:', d.get('title'))
print('  annotations:', json.dumps(d.get('annotations',{}), ensure_ascii=False, indent=2))
" 2>&1
echo

echo "=== 3. 测试：用 Grafana 的模板渲染 API 验证 ==="
echo "  说明：Grafana 13 的告警模板用的是 Go template，"
echo "        \$labels 只在【通知模板】里渲染，annotation 里要用 {{ with \$values }}...{{ end }}"
echo

echo "=== 4. 关键：annotation 里的 \$labels 到底能不能用 ==="
curl -s --noproxy '*' -u admin:admin http://localhost:3130/api/v1/provisioning/alert-rules/shop-error-rate 2>&1 | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('  annotations:', json.dumps(d.get('annotations',{}), ensure_ascii=False))
" 2>&1
