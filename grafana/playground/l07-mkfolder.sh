#!/usr/bin/env bash
# 课 7 环境准备：创建告警专用文件夹
set -u
GF="http://localhost:3001"
AUTH="admin:admin"

echo "--- 现有文件夹 ---"
curl -s -u $AUTH -H 'Content-Type: application/json' "$GF/api/folders?limit=50" \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)
if isinstance(d,list):
    print('  文件夹数：%d'%len(d))
    for f in d: print('    uid=%-16s title=%s'%(f.get('uid'), f.get('title')))
else:
    print('  %s'%str(d)[:200])
"

echo ""
echo "--- 创建 l07-alerts 文件夹 ---"
curl -s -u $AUTH -X POST -H 'Content-Type: application/json' \
  -d '{"title":"L07 Alerts","uid":"l07alerts"}' \
  "$GF/api/folders" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('  uid=%s title=%s url=%s canSave=%s'%(d.get('uid'),d.get('title'),d.get('url'),d.get('canSave')))
" 2>&1

echo ""
echo "--- 验证（回读）---"
curl -s -u $AUTH "$GF/api/folders/l07alerts" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('  uid=%s title=%s'%(d.get('uid'),d.get('title')))
" 2>&1

echo ""
echo "--- 幂等性检查（再创建一次应报已存在）---"
curl -s -u $AUTH -X POST -H 'Content-Type: application/json' \
  -d '{"title":"L07 Alerts","uid":"l07alerts"}' \
  "$GF/api/folders" | head -c 300
echo ""
