#!/usr/bin/env bash
# 定位：为什么 autopilot_healthy / server_isLeader 恒为 0？
BASE=/tmp/consul-ops
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501

echo "########## 1. 谁才是 leader ##########"
consul operator raft list-peers

echo
echo "########## 2. leader 节点上的关键指标 ##########"
LEADER_IP=$(consul operator raft list-peers 2>/dev/null | awk '$4=="leader"{print $3}' | cut -d: -f1)
echo "leader IP = [$LEADER_IP]"
NUM=$(echo "$LEADER_IP" | grep -oE '[0-9]+$' || echo 1)
LEADER_HTTP=$((8500 + NUM))
echo "leader HTTP = $LEADER_IP:$LEADER_HTTP"
curl -s "http://$LEADER_IP:$LEADER_HTTP/v1/agent/metrics?format=prometheus" > "$BASE/all.txt"
echo "指标行数: $(wc -l < "$BASE/all.txt")"
grep -E '^consul_server_isLeader|^consul_raft_state|^consul_autopilot_healthy|^consul_raft_leader' "$BASE/all.txt" || echo "  (以上指标均未出现)"

echo
echo "########## 3. 指标前缀分布 ##########"
grep -oE '^consul_[a-z]+' "$BASE/all.txt" | sort | uniq -c | sort -rn | head -12

echo
echo "########## 4. raft 类指标 ##########"
grep '^consul_raft' "$BASE/all.txt" | head -10 || echo "  无"

echo
echo "########## 5. JSON 端点里的 raft/autopilot/leader ##########"
curl -s "http://$LEADER_IP:$LEADER_HTTP/v1/agent/metrics" | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
except Exception as e:
    print('  解析失败:',e); sys.exit()
g=d.get('Gauges',{})
hit=[k for k in g if any(s in k.lower() for s in ('raft','leader','autopilot'))]
if not hit: print('  Gauges 中无 raft/leader/autopilot 相关项')
for k in sorted(hit): print(f'  {k} = {g[k][\"Value\"]}')
"
