#!/usr/bin/env bash
# 诊断 l02-panel.sh 的失败：A 组无输出 + dashboard 创建 bad request data
set -u
GF="http://localhost:3014"
CK=/tmp/l02diag_ck.txt
curl -s -c $CK -X POST "$GF/login" -H 'Content-Type: application/json' \
  -d '{"user":"admin","password":"lab-pass-2026"}' >/dev/null

echo "=== 1. PROXY_UID 是否干净（有无隐藏换行）==="
UID_RAW=$(curl -s -b $CK "$GF/api/datasources/name/PROM_PROXY" | python3 -c "import sys,json;print(json.load(sys.stdin)['uid'])")
printf '  [%s]  长度=%s\n' "$UID_RAW" "${#UID_RAW}"

echo
echo "=== 2. 最简查询是否通（不含复杂表达式）==="
curl -s -b $CK -X POST "$GF/api/ds/query" -H 'Content-Type: application/json' \
  -d "{\"queries\":[{\"refId\":\"A\",\"datasource\":{\"type\":\"prometheus\",\"uid\":\"$UID_RAW\"},\"expr\":\"up\",\"instant\":true,\"range\":false}],\"from\":\"now-5m\",\"to\":\"now\"}" \
  | head -c 200
echo

echo
echo "=== 3. 带 by/instance 的表达式，不经 shell 变量，直接看看 ==="
EXP='100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[2m])) * 100)'
echo "  表达式原文: $EXP"
echo -n "  直接问 Prometheus（9201）: "
curl -s -G --data-urlencode "query=$EXP" "http://localhost:9201/api/v1/query" | head -c 300
echo

echo
echo "=== 4. 用文件构造 JSON，绕开 shell 引号（python 生成 + curl -d @file）==="
python3 - <<'PY'
import json
uid="cfx7z63ogo54wd"
expr='100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[2m])) * 100)'
q={"queries":[{"refId":"A","datasource":{"type":"prometheus","uid":uid},
    "expr":expr,"instant":True,"range":False}],"from":"now-5m","to":"now"}
open('/tmp/l02_q.json','w').write(json.dumps(q))
print("  已写 /tmp/l02_q.json")
PY
echo "  查询结果（前 400 字符）:"
curl -s -b $CK -X POST "$GF/api/ds/query" -H 'Content-Type: application/json' \
  -d @/tmp/l02_q.json | head -c 400
echo

echo
echo "=== 5. 最小 dashboard 能否创建（逐步加字段定位 bad request 原因）==="
python3 - <<'PY'
import json
uid="cfx7z63ogo54wd"
d={"dashboard":{"title":"L02 最小","uid":"l02-min","schemaVersion":41,"panels":[],"time":{"from":"now-15m","to":"now"}},"overwrite":True}
open('/tmp/l02_min.json','w').write(json.dumps(d))
print("  已写 /tmp/l02_min.json")
PY
echo -n "  5a 空面板: "
curl -s -b $CK -X POST "$GF/api/dashboards/db" -H 'Content-Type: application/json' -d @/tmp/l02_min.json -w ' [HTTP %{http_code}]\n' | head -c 200

python3 - <<'PY'
import json
uid="cfx7z63ogo54wd"
p={"id":1,"type":"timeseries","title":"CPU","gridPos":{"h":8,"w":12,"x":0,"y":0},
   "datasource":{"type":"prometheus","uid":uid},
   "targets":[{"refId":"A","expr":"up"}]}
d={"dashboard":{"title":"L02 带面板","uid":"l02-p1","schemaVersion":41,"panels":[p],"time":{"from":"now-15m","to":"now"}},"overwrite":True}
open('/tmp/l02_p1.json','w').write(json.dumps(d))
print("  已写 /tmp/l02_p1.json")
PY
echo -n "  5b 带一个 timeseries 面板: "
curl -s -b $CK -X POST "$GF/api/dashboards/db" -H 'Content-Type: application/json' -d @/tmp/l02_p1.json -w ' [HTTP %{http_code}]\n' | head -c 250

python3 - <<'PY'
import json
uid="cfx7z63ogo54wd"
p={"id":1,"type":"timeseries","title":"CPU","gridPos":{"h":8,"w":12,"x":0,"y":0},
   "datasource":{"type":"prometheus","uid":uid},
   "targets":[{"refId":"A","expr":"up"}],
   "fieldConfig":{"defaults":{"unit":"percent","thresholds":{"mode":"absolute","steps":[
      {"color":"green","value":None},{"color":"orange","value":60},{"color":"red","value":85}]}},
      "overrides":[]}}
d={"dashboard":{"title":"L02 带阈值","uid":"l02-p2","schemaVersion":41,"panels":[p],"time":{"from":"now-15m","to":"now"}},"overwrite":True}
open('/tmp/l02_p2.json','w').write(json.dumps(d))
print("  已写 /tmp/l02_p2.json")
PY
echo -n "  5c 再加 fieldConfig+thresholds: "
curl -s -b $CK -X POST "$GF/api/dashboards/db" -H 'Content-Type: application/json' -d @/tmp/l02_p2.json -w ' [HTTP %{http_code}]\n' | head -c 250
