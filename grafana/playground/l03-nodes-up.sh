#!/usr/bin/env bash
# 课 3：造出 N 台"机器"（node2 / node3），让变量有东西可选
# 注意：prometheus.yml 是 bind mount，改完必须重启 grafana-prom 才生效（未开 lifecycle）
set -u
GFDIR=/mnt/d/projects/learning/grafana/playground

echo "=== 1. 起 node2 / node3（用不同 hostname，让 nodename 也不同） ==="
docker rm -f grafana-node2 grafana-node3 >/dev/null 2>&1
docker run -d --name grafana-node2 --hostname node-alpha --network grafana-net \
  -p 9102:9100 prom/node-exporter:v1.10.2
docker run -d --name grafana-node3 --hostname node-beta  --network grafana-net \
  -p 9103:9100 prom/node-exporter:v1.10.2
sleep 2
docker ps --filter name=grafana-node --format '{{.Names}} | {{.Status}} | {{.Ports}}'
echo

echo "=== 2. 改写 prometheus.yml（幂等：已存在则不重复加） ==="
cat > /tmp/l03-patch-yml.py <<'PYEOF'
import re, pathlib
p = pathlib.Path('/mnt/d/projects/learning/grafana/playground/prometheus.yml')
t = p.read_text(encoding='utf-8')
old = "      - targets: ['grafana-node:9100']"
new = "      - targets: ['grafana-node:9100', 'grafana-node2:9100', 'grafana-node3:9100']"
if 'grafana-node2' in t:
    print("已含 node2/node3，跳过修改")
else:
    assert old in t, "未找到待替换的 targets 行，请人工检查 prometheus.yml"
    p.write_text(t.replace(old, new), encoding='utf-8')
    print("已改为 3 个 targets")
print("---- 当前 scrape_configs ----")
print(p.read_text(encoding='utf-8'))
PYEOF
python3 /tmp/l03-patch-yml.py
echo

echo "=== 3. 重启 Prometheus 使配置生效（bind mount 不会自动重载） ==="
docker restart grafana-prom >/dev/null
echo "已发出 restart，等待就绪..."
for i in $(seq 1 60); do
  r=$(curl -s --max-time 2 'http://localhost:9201/api/v1/query?query=up' | tr -d ' \n')
  if echo "$r" | grep -q '"status":"success"'; then
    echo "t+$((i*2))s Prometheus 就绪"; break
  fi
  sleep 2
done
echo

echo "=== 4. 等 20 秒让三台机器都有数据，再验证 up ==="
sleep 20
curl -s 'http://localhost:9201/api/v1/query?query=up' \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print(json.dumps([{'job':r['metric'].get('job'),'instance':r['metric'].get('instance'),'up':r['value'][1]} for r in d['data']['result']],ensure_ascii=False,indent=1))"
echo

echo "=== 5. 三台机器的 nodename（证明是三台不同的机器） ==="
curl -s 'http://localhost:9201/api/v1/query?query=node_uname_info' \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print(json.dumps([{'instance':r['metric'].get('instance'),'nodename':r['metric'].get('nodename')} for r in d['data']['result']],ensure_ascii=False,indent=1))"
echo

echo "=== 6. 变量将要用到的标签基数 ==="
for q in 'count(count by (instance) (node_cpu_seconds_total))' 'count(count by (job) (up))'; do
  echo "-- $q"
  curl -s --data-urlencode "query=$q" http://localhost:9201/api/v1/query \
    | python3 -c "import sys,json;d=json.load(sys.stdin);print(json.dumps(d['data']['result'],ensure_ascii=False))"
done
