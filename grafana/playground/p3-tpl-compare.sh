#!/bin/bash
set -u
W=/mnt/d/projects/learning/grafana/projects/从告警到定位

echo "=== 等 110 秒让三条规则触发 ==="
sleep 110
echo "  done"
echo

echo "=== 对比三条规则的 summary 渲染结果 ==="
docker logs p3-webhook 2>&1 | grep -E 'TMP-[ABC]' -A6 | grep -E 'TMP-|summary' | tail -20
echo

echo "=== 结构化输出 ==="
python3 -c "
import json,glob
seen={}
for f in sorted(glob.glob('$W/实现/webhook/out/*.json')):
    d=json.load(open(f))
    for a in d.get('alerts',[]):
        n=a.get('labels',{}).get('alertname','')
        if 'TMP-' in n:
            seen[n]=a.get('annotations',{}).get('summary','')
for k in sorted(seen):
    print('  ', k)
    print('      →', seen[k])
" 2>&1
echo

echo "=== 清理 ==="
for U in tmp-a tmp-b tmp-c; do
  curl -s --noproxy '*' -u admin:admin -X DELETE "http://localhost:3130/api/v1/provisioning/alert-rules/$U" -o /dev/null -w "  $U delete=%{http_code}\n"
done
