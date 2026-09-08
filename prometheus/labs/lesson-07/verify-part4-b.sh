#!/usr/bin/env bash
# 复验讲义第四幕 步骤5-9 的所有命令（逐字执行）
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  PASS  $1"; }
no(){ FAIL=$((FAIL+1)); echo "  FAIL  $1"; }
chk(){ if [ "$2" = "$3" ]; then ok "$1 (=$2)"; else no "$1 (期望=$3 实际=$2)"; fi; }

echo "=== S5: remote read 静默失败 (l7-prom-ro:19103 -> VM) ==="
W=$(curl -s -G "http://localhost:19103/api/v1/query" --data-urlencode 'query=count(l7_card_balance)')
echo "$W" | python -c "import sys,json;d=json.load(sys.stdin);print('  status  =',d['status']);print('  results =',len(d['data']['result']));print('  warnings=',d.get('warnings'))"
echo "$W" | grep -q '"status":"success"' && ok "S5 status=success" || no "S5 status"
echo "$W" | grep -q 'unsupported path requested' && ok "S5 warnings 含 unsupported path" || no "S5 warnings"

echo "=== S5b: reader(19106) 本地无 l7-app，但能查到 500 条 ==="
UPS=$(curl -s -G "http://localhost:19106/api/v1/query" --data-urlencode 'query=up' | python -c "
import sys,json
d=json.load(sys.stdin)
for s in d['data']['result']:
    m=s['metric']
    print('   up', {k:v for k,v in m.items() if k!='__name__'})
")
echo "$UPS"
echo "$UPS" | grep -q 'reader-self' && ok "S5b reader 只抓自己" || no "S5b reader-self"
echo "$UPS" | grep -qv 'job.: .l7-app' && ok "S5b reader 不抓 l7-app" || no "S5b reader 抓了 l7-app"
CNT=$(curl -s -G "http://localhost:19106/api/v1/query" --data-urlencode 'query=count(l7_card_balance)' | python -c "import sys,json;d=json.load(sys.stdin);r=d['data']['result'];print(r[0]['value'][1] if r else 0)")
chk "S5b remote read 命中序列数" "$CNT" "500"

echo "=== S6: external_labels 三段式 ==="
VMT=$(curl -s -G "http://localhost:19101/api/v1/query" --data-urlencode 'query=l7_card_balance{idx="0001"}' | python -c "
import sys,json
d=json.load(sys.stdin)
r=d['data']['result']
print(sorted(r[0]['metric'].keys()) if r else 'NONE')")
echo "  VM 标签 = $VMT"
echo "$VMT" | grep -q "'cluster'" && ok "S6 VM 上有 cluster" || no "S6 VM cluster"
RRT=$(curl -s -G "http://localhost:19102/api/v1/query" --data-urlencode 'query=l7_card_balance{idx="0001"}' | python -c "
import sys,json
d=json.load(sys.stdin)
r=d['data']['result']
print(sorted(r[0]['metric'].keys()) if r else 'NONE')")
echo "  rr 标签 = $RRT"
echo "$RRT" | grep -q "'cluster'" && no "S6 rr 不应有 cluster" || ok "S6 rr 已剥离 cluster"
for q in 'l7_card_balance' 'l7_card_balance{cluster="l7-lab"}'; do
  n=$(curl -s -G "http://localhost:19102/api/v1/query" --data-urlencode "query=count($q)" | python -c "import sys,json;d=json.load(sys.stdin);r=d['data']['result'];print(r[0]['value'][1] if r else 0)")
  echo "  $q -> $n"
done
N1=$(curl -s -G "http://localhost:19102/api/v1/query" --data-urlencode 'query=count(l7_card_balance)' | python -c "import sys,json;d=json.load(sys.stdin);r=d['data']['result'];print(r[0]['value'][1] if r else 0)")
N2=$(curl -s -G "http://localhost:19102/api/v1/query" --data-urlencode 'query=count(l7_card_balance{cluster="l7-lab"})' | python -c "import sys,json;d=json.load(sys.stdin);r=d['data']['result'];print(r[0]['value'][1] if r else 0)")
chk "S6 裸查询条数" "$N1" "500"
chk "S6 显式 cluster 条数" "$N2" "0"

echo "=== S7: Agent 拒绝 rule_files ==="
cd /mnt/d/projects/learning/prometheus
ERR=$(docker run --rm \
  -v "/mnt/d/projects/learning/prometheus/labs/lesson-07/agent-record-only.yml:/etc/prometheus/prometheus.yml:ro" \
  -v "/mnt/d/projects/learning/prometheus/labs/lesson-07/rules-record-only.yml:/etc/prometheus/rules-record-only.yml:ro" \
  prom/prometheus:v3.14.0 \
  --agent --config.file=/etc/prometheus/prometheus.yml 2>&1 | grep -o 'field rule_files is not allowed in agent mode')
chk "S7 Agent 拒绝 rule_files" "$ERR" "field rule_files is not allowed in agent mode"

echo "=== S7b: --agent 是独立 flag ==="
H=$(docker run --rm prom/prometheus:v3.14.0 --help 2>&1 | grep "Run Prometheus in 'Agent mode'")
echo "  help: $H"
echo "$H" | grep -q -- '--\[no-\]agent' && ok "S7b --agent 独立 flag" || no "S7b --agent flag"

echo "=== S8: Agent 能力边界 ==="
for p in "/api/v1/query?query=up" "/api/v1/targets" "/api/v1/rules" "/api/v1/alertmanagers" "/api/v1/labels"; do
  c=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:19107${p}")
  printf "   agent  %-30s -> %s\n" "$p" "$c"
done
A_Q=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:19107/api/v1/query?query=up")
A_T=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:19107/api/v1/targets")
A_R=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:19107/api/v1/rules")
A_A=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:19107/api/v1/alertmanagers")
A_L=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:19107/api/v1/labels")
chk "S8 agent /api/v1/query"  "$A_Q" "422"
chk "S8 agent /api/v1/targets" "$A_T" "200"
chk "S8 agent /api/v1/rules"  "$A_R" "422"
chk "S8 agent /api/v1/alertmanagers" "$A_A" "422"
chk "S8 agent /api/v1/labels" "$A_L" "422"

echo "=== S8b: Server 对照 ==="
for p in "/api/v1/query?query=up" "/api/v1/targets" "/api/v1/rules" "/api/v1/alertmanagers" "/api/v1/labels"; do
  c=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:19100${p}")
  printf "   server %-30s -> %s\n" "$p" "$c"
done
S_Q=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:19100/api/v1/query?query=up")
chk "S8b server /api/v1/query" "$S_Q" "200"

echo "=== S8c: 资源占用 ==="
docker stats --no-stream --format "{{.Name}}|{{.MemUsage}}" l7-prom l7-agent
echo "  --- 磁盘 ---"
docker exec l7-prom  sh -c 'du -sh /prometheus 2>/dev/null'
docker exec l7-agent sh -c 'du -sh /data-agent 2>/dev/null'

echo "=== S8d: 自监控悖论 ==="
M=$(docker exec l7-agent wget -qO- http://localhost:9090/metrics | grep -cE "^prometheus_remote_storage_samples_")
echo "  agent /metrics 中 remote_storage_samples_ 指标行数 = $M"
[ "$M" -gt 0 ] && ok "S8d agent /metrics 可用" || no "S8d agent /metrics"
HS=$(docker exec l7-agent wget -qO- http://localhost:9090/metrics | grep -c "^prometheus_tsdb_head_series")
chk "S8d agent 无 head_series" "$HS" "0"

echo
echo "=== 汇总: PASS=$PASS FAIL=$FAIL ==="
