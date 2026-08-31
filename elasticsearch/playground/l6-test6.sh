#!/bin/bash
ES="https://localhost:9200"
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW"

echo "=== profile 原始输出（前 1500 字符）==="
$C -X POST "$ES/l6_shop/_search?size=0&profile=true" -H "Content-Type: application/json" -d '{
  "query":{"bool":{"filter":[{"term":{"brand":"Apple"}}]}}}' > /tmp/p.json
head -c 1500 /tmp/p.json
echo ""
echo ""
echo "=== 检查是否有 profile 字段 ==="
python -c "
import json
d=json.load(open('/tmp/p.json'))
print('  顶层字段:', list(d.keys()))
if 'profile' in d:
    print('  profile 存在')
else:
    print('  profile 不存在 → 该版本/请求方式不支持，不据此下结论')"
