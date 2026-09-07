#!/bin/bash
echo "=== 1. grafana-lab(3001) 的数据源 ==="
curl -s --noproxy '*' -u admin:admin http://localhost:3001/api/datasources 2>&1 | python3 -c "import sys,json;d=json.load(sys.stdin);[print('  ',x['uid'],x['type'],x.get('url','')) for x in d]" 2>&1 | head -10
echo

echo "=== 2. grafana-lab 现有 dashboard 数 ==="
curl -s --noproxy '*' -u admin:admin 'http://localhost:3001/api/search?limit=500' 2>&1 | python3 -c "import sys,json;d=json.load(sys.stdin);print('  dashboards =',len(d));[print('   ',x['uid'],x['title']) for x in d[:8]]" 2>&1
echo

echo "=== 3. 渲染能力：image renderer 是否可用 ==="
curl -s --noproxy '*' -u admin:admin -o /dev/null -w '  render_http=%{http_code}\n' 'http://localhost:3001/render/dashboard-solo/db/x?panelId=1' -m 20
echo "  --- 渲染插件 ---"
docker exec grafana-lab ls /var/lib/grafana/plugins/ 2>&1 | head -10
echo "  --- rendering 配置 ---"
docker exec grafana-lab sh -c 'grep -Ei "^;?\[rendering\]|^;?renderer_|^;?server_url|^;?callback_url" /etc/grafana/grafana.ini 2>/dev/null | head -10' 2>&1
echo

echo "=== 4. Prometheus 数据源可达性（用 lab 的第一个 prom）==="
PROM=$(curl -s --noproxy '*' -u admin:admin http://localhost:3001/api/datasources 2>/dev/null | python3 -c "import sys,json;d=json.load(sys.stdin);print([x['uid'] for x in d if x['type']=='prometheus'][0] if any(x['type']=='prometheus' for x in d) else '')" 2>/dev/null)
echo "  prom_uid=$PROM"
echo

echo "=== 5. 单次查询基线耗时（3 次取范围）==="
for i in 1 2 3; do
  curl -s --noproxy '*' -u admin:admin -o /dev/null -w "  第${i}次: total=%{time_total}s\n" -X POST http://localhost:3001/api/ds/query -H 'Content-Type: application/json' -d "{\"queries\":[{\"refId\":\"A\",\"datasource\":{\"uid\":\"$PROM\"},\"expr\":\"up\",\"instant\":true}],\"from\":\"now-1h\",\"to\":\"now\"}"
done
echo

echo "=== 6. 并发能力：服务端是否有限流 ==="
echo "  (后续脚本测)"
