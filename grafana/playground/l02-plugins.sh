#!/usr/bin/env bash
# 核实「首次启动联网装五个插件」这个说法是否属实
set -u

echo "=== 1. gf-l02b（已跑了一会）的插件目录 ==="
docker exec gf-l02b ls -1 /var/lib/grafana/plugins 2>&1 | head -20
echo "  --- 目录项数: $(docker exec gf-l02b ls -1 /var/lib/grafana/plugins 2>/dev/null | wc -l)"

echo
echo "=== 2. 内置插件目录（不联网也有） ==="
docker exec gf-l02b ls -1 /usr/share/grafana/data/plugins-bundled 2>&1 | head -30

echo
echo "=== 3. 通过 API 查已注册插件数量 ==="
curl -s -c /tmp/l02p.txt -X POST "http://localhost:3012/login" \
  -H 'Content-Type: application/json' -d '{"user":"admin","password":"admin"}' >/dev/null
curl -s -b /tmp/l02p.txt "http://localhost:3012/api/plugins?embedded=0" \
  | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    print('  插件响应条目数:', len(d) if isinstance(d,list) else '非列表')
    for p in (d if isinstance(d,list) else [])[:12]:
        print(f\"    - {p.get('id')}  v{p.get('info',{}).get('version')}  type={p.get('type')}\")
except Exception as e:
    print('  解析失败:', e)
"

echo
echo "=== 4. 课 1 用的 grafana-lab 容器启动日志里，装插件相关行 ==="
docker logs grafana-lab 2>&1 | grep -iE 'Installing|Downloading|plugin.*install|app.*install' | head -20
echo "  （以上为空则说明课 1 的『装五个插件』观察来自别处）"

echo
echo "=== 5. grafana-lab 的插件目录 ==="
docker logs grafana-lab 2>&1 | head -3
echo "  --- 插件目录项数: $(docker exec grafana-lab ls -1 /var/lib/grafana/plugins 2>/dev/null | wc -l)"
docker exec grafana-lab ls -1 /var/lib/grafana/plugins 2>/dev/null | head -20
