#!/usr/bin/env bash
# honor_labels 决定性对照：同一批数据，只改这一个开关
set -u
L8=/mnt/d/projects/learning/prometheus/labs/lesson-08

echo "=== 阶段 1：先记录 honor_labels: true 的结果 ==="
docker exec l8-global wget -qO- \
  'http://localhost:9090/api/v1/query?query=l8_card_balance{idx="0001"}' \
  | python -c "
import sys,json
d=json.load(sys.stdin)
for s in d['data']['result']:
    m=s['metric']
    print(f\"   [true ] cluster={m.get('cluster'):8s} job={m.get('job'):12s} instance={m.get('instance'):18s} source_cluster={m.get('source_cluster')}\")
"

echo
echo "=== 阶段 2：切换为 honor_labels 默认（false） ==="
docker rm -f l8-global-nh >/dev/null 2>&1 || true
docker run -d --name l8-global-nh --network l8net -p 19116:9090 \
  -v "$L8/global-nohonor.yml:/etc/prometheus/prometheus.yml:ro" \
  prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus --storage.tsdb.retention.time=2h \
  --web.enable-lifecycle >/dev/null

echo "   等待 25 秒（抓取间隔 5s，等 4 轮以上）..."
sleep 25

echo
echo "=== 阶段 3：honor_labels=false 的结果 ==="
docker exec l8-global-nh wget -qO- \
  'http://localhost:9090/api/v1/query?query=l8_card_balance{idx="0001"}' \
  | python -c "
import sys,json
d=json.load(sys.stdin)
r=d['data']['result']
print(f'   命中 {len(r)} 条')
for s in r:
    m=s['metric']
    print(f\"   [false] cluster={m.get('cluster'):8s} job={m.get('job'):12s} instance={m.get('instance'):18s} source_cluster={m.get('source_cluster')}\")
"

echo
echo "=== 阶段 4：差异对照表 ==="
python3 - <<'PY'
import json, subprocess

def q(container, port, expr):
    url = f'http://localhost:{port}/api/v1/query?query=' + expr.replace('{','%7B').replace('}','%7D').replace('"','%22')
    out = subprocess.run(['curl','-s',url], capture_output=True, text=True)
    try:
        return json.loads(out.stdout)['data']['result']
    except Exception:
        return []

a = q('l8-global', 19114, 'l8_card_balance{idx="0001"}')
b = q('l8-global-nh', 19116, 'l8_card_balance{idx="0001"}')

def sig(rs):
    out=[]
    for s in rs:
        m=s['metric']
        out.append((m.get('cluster'), m.get('job'), m.get('instance'), m.get('source_cluster')))
    return sorted(out)

print(f"   honor_labels=true   命中 {len(a)} 条")
for t in sig(a):
    print(f"      cluster={str(t[0]):8s} job={str(t[1]):14s} instance={str(t[2]):20s} src={t[3]}")
print(f"   honor_labels=false  命中 {len(b)} 条")
for t in sig(b):
    print(f"      cluster={str(t[0]):8s} job={str(t[1]):14s} instance={str(t[2]):20s} src={t[3]}")

sa, sb = set(sig(a)), set(sig(b))
print()
print("   === 决定性结论 ===")
if len(a) != len(b):
    print(f"   序列条数不同：true={len(a)}  false={len(b)}")
    if len(b) < len(a):
        print("   --> honor_labels=false 时，两个叶子的数据因 job/instance 被改写而发生标签冲突、互相覆盖")
for t in sorted(sa ^ sb):
    print(f"   仅在其中一侧出现: {t}")
PY
