#!/bin/bash
set -u
W=/mnt/d/projects/learning/grafana/projects/从告警到定位

echo "########## 最终验收：完整跑一遍「从告警到定位」##########"
echo

echo "=== 步骤 0：重建应用（带 exemplar 修复）==="
cd "$W/实现/app" && docker build -t p3-shop:1.1 . 2>&1 | tail -2
docker rm -f p3-shop >/dev/null 2>&1
docker run -d --name p3-shop --network grafana-net \
  -p 9400:9400 -p 9401:9401 \
  -e SERVICE_NAME=shop-api \
  -e OTLP_ENDPOINT=http://grafana-jaeger:4318/v1/traces \
  -e LOKI_URL=http://grafana-loki:3100/loki/api/v1/push \
  -e FAULT_MODE=1 \
  -v "$W/实现/app/logs:/var/log/shop" \
  p3-shop:1.1 2>&1 | tail -1
sleep 10
docker logs p3-shop 2>&1 | grep '故障注入' | head -1
echo

echo "=== 步骤 1：等 90 秒让 exemplar 与告警数据积累 ==="
sleep 90
echo "  done"
echo

echo "=== 步骤 2：exemplar 有了吗（指标→链路的第一跳）==="
curl -s --noproxy '*' -m 10 -G 'http://localhost:3110/api/v1/query_exemplars' --data-urlencode 'query=shop_request_duration_seconds_bucket' 2>&1 | python3 -c "
import sys,json
d=json.load(sys.stdin).get('data',[])
print('  exemplar 组数 =', len(d))
for g in d[:2]:
    print('   标签:', g.get('seriesLabels'))
    for e in g.get('exemplars',[])[:3]:
        print('    → trace_id =', dict(e.get('labels',{})).get('trace_id','?'), 'value=', round(e.get('value',0),3))
" 2>&1
echo

echo "=== 步骤 3：告警触发了吗 ==="
curl -s --noproxy '*' -u admin:admin 'http://localhost:3130/api/alertmanager/grafana/api/v2/alerts' 2>&1 | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('  活跃告警 =', len(d) if isinstance(d,list) else '?')
for a in (d if isinstance(d,list) else [])[:3]:
    L=a.get('labels',{})
    print('   ', L.get('alertname'), '| route=', L.get('route'), '| sev=', L.get('severity'))
    print('      summary:', a.get('annotations',{}).get('summary','')[:90])
" 2>&1
echo

echo "=== 步骤 4：webhook 收到的最新告警（模板渲染了吗）==="
docker logs p3-webhook 2>&1 | grep 'summary' | tail -4
echo

echo "=== 步骤 5：三级下钻完整走一遍 ==="
python3 - "$W" <<'PYEOF'
import json, re, subprocess, sys, time

def sh(cmd):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True).stdout

# ① 指标：找出最慢的接口
out = sh("curl -s --noproxy '*' -m 10 -G http://localhost:3110/api/v1/query --data-urlencode 'query=histogram_quantile(0.9, sum by (le, route) (rate(shop_request_duration_seconds_bucket[2m])))'")
try:
    res = json.loads(out)['data']['result']
    res.sort(key=lambda x: -float(x['value'][1]))
    worst = res[0]
    print(f"  ① 指标：最慢接口 = {worst['metric'].get('route')}  P90 = {float(worst['value'][1]):.3f}s")
except Exception as e:
    print("  ① 指标查询失败:", e); sys.exit()

# ② exemplar：从指标拿 trace_id
out = sh("curl -s --noproxy '*' -m 10 -G http://localhost:3110/api/v1/query_exemplars --data-urlencode 'query=shop_request_duration_seconds_bucket'")
tid = None
try:
    for g in json.loads(out).get('data', []):
        for e in g.get('exemplars', []):
            t = dict(e.get('labels', {})).get('trace_id')
            if t: tid = t; break
        if tid: break
except Exception: pass
print(f"  ② 指标→链路：exemplar trace_id = {tid or '（无）'}")

# ③ 日志：用 trace_id 搜日志
if tid:
    now = int(time.time())
    out = sh(f"curl -s --noproxy '*' -m 10 -G http://localhost:3101/loki/api/v1/query_range --data-urlencode 'query={{job=\"shop\"}} |= \"{tid}\"' --data-urlencode 'limit=5' --data-urlencode 'start={(now-600)*10**9}' --data-urlencode 'end={now*10**9}'")
    n = 0
    try:
        for s in json.loads(out).get('data', {}).get('result', []):
            n += len(s.get('values', []))
    except Exception: pass
    print(f"  ③ 日志：该 trace 命中日志 {n} 条")

    # ④ 链路：Jaeger 打开这个 trace
    out = sh(f"curl -s --noproxy '*' -m 10 http://localhost:16687/api/traces/{tid}")
    try:
        d = json.loads(out).get('data', [])
        if d:
            spans = d[0]['spans']
            print(f"  ④ 链路：Jaeger 打开成功，spans = {len(spans)}")
            for s in spans:
                dur = s.get('duration', 0)/1000
                err = any(x.get('key')=='error' for x in s.get('tags', []))
                print(f"       - {s['operationName']}  {dur:.1f}ms {'(ERROR)' if err else ''}")
        else:
            print("  ④ 链路：Jaeger 暂无此 trace（可能尚未索引）")
    except Exception as e:
        print("  ④ 链路查询失败:", e)
PYEOF
echo

echo "=== 步骤 6：dashboard 面板能查到数据吗 ==="
for Q in 'sum(rate(shop_requests_total[2m])) by (route)' 'sum(shop_inflight_requests)' 'min(up{job="shop"})'; do
  R=$(curl -s --noproxy '*' -m 8 -G http://localhost:3110/api/v1/query --data-urlencode "query=$Q" 2>&1 | python3 -c "import sys,json;d=json.load(sys.stdin)['data']['result'];print(len(d))" 2>/dev/null)
  echo "  $Q → 结果数=$R"
done
