#!/usr/bin/env bash
# 课 5 · 5.1 补充取证：数据库层 + 前端代码层
set -u

echo "=========================================="
echo " 5.1 补充：Transform 配置存在哪、谁来执行"
echo "=========================================="

echo ""
echo "--- [1] 数据库层：dashboard 存在哪张表，transformations 长什么样 ---"
docker exec grafana-lab bash -c "
  cp /var/lib/grafana/grafana.db /tmp/g.db 2>/dev/null && \
  python3 -c \"
import sqlite3
c = sqlite3.connect('/tmp/g.db')
c.row_factory = sqlite3.Row
tabs = [r[0] for r in c.execute(\\\"SELECT name FROM sqlite_master WHERE type='table' ORDER BY name\\\")]
print('  表总数：%d' % len(tabs))
for t in ('resource','dashboard','resource_history','dashboard_provisioning'):
    if t in tabs:
        n = c.execute('SELECT COUNT(*) FROM %s' % t).fetchone()[0]
        print('    %-24s %d 行' % (t, n))
\" 2>&1 | head -20
"

echo ""
echo "  注：Grafana 13.2.1 的 dashboard 存在 resource 表（课 3 已确认）"

echo ""
echo "--- [2] 前端代码层：transform 的实现在哪 ---"
MOD=/usr/share/grafana/data/plugins-bundled/prometheus/module.js
echo "  Prometheus 插件里搜 transformation（应为 0，因为 transform 不属于数据源插件）："
printf "    %s 次\n" "$(docker exec grafana-lab grep -o 'transformation' $MOD 2>/dev/null | wc -l)"

echo ""
echo "  在主程序 build 目录搜："
docker exec grafana-lab bash -c "
  for f in /usr/share/grafana/public/build/*.js; do
    n=\$(grep -o 'transformation' \"\$f\" 2>/dev/null | wc -l)
    if [ \"\$n\" -gt 0 ]; then echo \"    \$(basename \$f): \$n 次\"; fi
  done 2>/dev/null | head -8
"

echo ""
echo "--- [3] 搜 transform 相关的关键标识符 ---"
docker exec grafana-lab bash -c "
  for kw in 'transformDataFrame' 'runRequest' 'applyTransformations' 'transformations'; do
    tot=0
    for f in /usr/share/grafana/public/build/*.js; do
      n=\$(grep -o \"\$kw\" \"\$f\" 2>/dev/null | wc -l)
      tot=\$((tot+n))
    done
    printf '    %-24s 合计 %s 次\n' \"\$kw\" \"\$tot\"
  done
"

echo ""
echo "--- [4] 关键结论的佐证：transform 是否出现在 /api/ds/query 的响应里 ---"
cat > /tmp/l05c.json <<'JSON'
{"queries":[{"refId":"A","datasource":{"type":"prometheus","uid":"afx7x6dx803y8e"},"expr":"up","range":true,"instant":false,"intervalMs":15000,"maxDataPoints":10}],"from":"now-5m","to":"now"}
JSON
echo "  响应顶层字段（应只有 results，无 transformations）："
curl -s -u admin:admin -X POST http://localhost:3001/api/ds/query \
  -H 'Content-Type: application/json' --data @/tmp/l05c.json \
  | python3 -c "import sys,json; print('    %s' % ', '.join(sorted(json.load(sys.stdin).keys())))"

echo ""
echo "=========================================="
echo " 补充取证完成"
echo "=========================================="
