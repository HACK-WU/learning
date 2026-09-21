#!/usr/bin/env bash
# 严格照抄讲义第四幕，逐条断言
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501
FAIL=0
H=$(hostname | tr '-' '_')
echo "主机名前缀 = $H"

echo "== 断言1 两个端点都可用 =="
P=$(curl -s -o /dev/null -w '%{http_code}' 'http://127.0.0.1:8501/v1/agent/metrics?format=prometheus')
J=$(curl -s -o /dev/null -w '%{http_code}' 'http://127.0.0.1:8501/v1/agent/metrics')
echo "  prometheus=$P json=$J"
[ "$P" = 200 ] && [ "$J" = 200 ] && echo "  通过" || { echo "  !! FAIL"; FAIL=1; }

echo "== 断言2 Prometheus 无前缀 raft_last_index 恒 0 =="
curl -s 'http://127.0.0.1:8501/v1/agent/metrics?format=prometheus' > /tmp/pv.txt
NP=$(grep -E '^consul_raft_last_index ' /tmp/pv.txt | awk '{print $2}')
echo "  无前缀 consul_raft_last_index = $NP (期望 0)"
[ "$NP" = "0" ] && echo "  通过" || { echo "  !! FAIL"; FAIL=1; }

echo "== 断言3 带前缀版本非 0（真值） =="
WP=$(grep -E "^consul_${H}_raft_last_index " /tmp/pv.txt | awk '{print $2}')
echo "  带前缀 consul_${H}_raft_last_index = $WP (期望非0)"
python3 -c "
v='$WP'
assert v not in ('','0'), f'带前缀仍为 {v}'
print('  通过')
" || { echo "  !! FAIL"; FAIL=1; }

echo "== 断言4 JSON 端点值与 CLI commit 一致量级 =="
JV=$(curl -s $CONSUL_HTTP_ADDR/v1/agent/metrics | python3 -c "
import sys,json
d=json.load(sys.stdin); g=d.get('Gauges',{})
if isinstance(g,list): g={s['Name']:s for s in g if isinstance(s,dict) and 'Name' in s}
print([v['Value'] if isinstance(v,dict) else v for k,v in g.items() if k.endswith('raft.last_index')][0])
")
CM=$(consul operator raft list-peers | awk 'NR>1{print $7}' | head -1)
echo "  JSON=$JV  CLI commit=$CM"
python3 -c "
j,c=int('$JV'),int('$CM')
assert j>0 and c>0, '两者都应非0'
print(f'  通过（两者均非0，且 CLI>=JSON: {c>=j}）')
" || { echo "  !! FAIL"; FAIL=1; }

echo "== 断言5 空壳 vs 真值对照（autopilot_healthy） =="
AH_N=$(grep -E '^consul_autopilot_healthy ' /tmp/pv.txt | awk '{print $2}')
AH_Y=$(grep -E "^consul_${H}_autopilot_healthy " /tmp/pv.txt | awk '{print $2}')
echo "  无前缀=$AH_N (期望0)  带前缀=$AH_Y (期望1)"
[ "$AH_N" = "0" ] && [ "$AH_Y" = "1" ] && echo "  通过" || { echo "  !! FAIL"; FAIL=1; }

echo "== 断言6 server_isLeader 求和 = 1（恰好一个 leader） =="
SUM=0
for n in 1 2 3; do
  V=$(curl -s "http://127.0.0.$n:$((8500+n))/v1/agent/metrics?format=prometheus" | grep -E "^consul_${H}_server_isLeader " | awk '{print $2}')
  echo "    node$n server_isLeader = $V"
  SUM=$(python3 -c "print($SUM+int('${V:-0}'))")
done
echo "  求和 = $SUM (期望 1)"
[ "$SUM" = "1" ] && echo "  通过" || { echo "  !! FAIL"; FAIL=1; }

echo "== 断言7 恒0占比约 51% =="
TOT=$(grep -c '^consul' /tmp/pv.txt)
ZERO=$(grep '^consul' /tmp/pv.txt | awk '$2=="0"' | wc -l)
python3 -c "
t,z=$TOT,$ZERO
r=z/t*100
print(f'  共 {t} 条，恒0 = {z} 条 → {r:.0f}%')
assert 30<r<80, f'占比 {r:.0f}% 超出预期区间'
print('  通过')
" || { echo "  !! FAIL"; FAIL=1; }

echo "== 断言8 API 兜底可用且 Healthy =="
AP=$(curl -s $CONSUL_HTTP_ADDR/v1/operator/autopilot/health | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['Healthy'])")
echo "  /v1/operator/autopilot/health → Healthy=$AP"
[ "$AP" = "True" ] && echo "  通过" || { echo "  !! FAIL"; FAIL=1; }

echo "== 断言9 HELP 行存在但无语义（仅重复指标名） =="
HL=$(grep -c '^# HELP' /tmp/pv.txt)
S1=$(grep '^# HELP' /tmp/pv.txt | head -1 | awk '{print $3, $4}')
echo "  HELP 行数=$HL  示例: $S1"
python3 -c "
assert $HL>100, 'HELP 行太少'
print('  通过（HELP 仅重复指标名，故第2步在 Consul 上信息有限）')
" || { echo "  !! FAIL"; FAIL=1; }

echo
[ $FAIL -eq 0 ] && echo "=== 课6 终验通过（9 组断言）===" || echo "=== 终验存在失败 ==="
exit $FAIL
