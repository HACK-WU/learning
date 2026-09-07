#!/bin/bash
echo "=== 1. 数据库里有没有 api_key 表 ==="
docker exec grafana-prov sh -c "which sqlite3 || echo NO_SQLITE3" 2>&1
echo
echo "--- 尝试用 sqlite3 查 ---"
docker exec grafana-prov sh -c "sqlite3 /var/lib/grafana/grafana.db '.tables' 2>&1 | tr ' ' '\n' | grep -Ei 'api_key|apikey|service' || echo 'no match / no sqlite3'" 2>&1
echo
echo "=== 2. 从宿主机拷贝 db 出来查 ==="
docker cp grafana-prov:/var/lib/grafana/grafana.db /tmp/l11-grafana.db 2>&1 && echo "  copied ok"
ls -la /tmp/l11-grafana.db 2>/dev/null
echo
echo "--- 用 python 查 sqlite ---"
python3 - <<'PY'
import sqlite3
try:
    c=sqlite3.connect('/tmp/l11-grafana.db')
    rows=c.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name").fetchall()
    names=[r[0] for r in rows]
    print('  表总数:',len(names))
    hits=[n for n in names if 'api_key' in n.lower() or 'apikey' in n.lower() or 'service' in n.lower()]
    print('  相关表:',hits)
    print()
    print('  --- 关键表是否存在 ---')
    for t in ['api_key','service_account','service_account_token','team','org_user','user','dashboard','folder','permission']:
        print('   %-24s %s' % (t, 'YES' if t in names else 'no'))
except Exception as e:
    print('  ERR',e)
PY
