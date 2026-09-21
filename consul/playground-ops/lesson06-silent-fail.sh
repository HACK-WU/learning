#!/usr/bin/env bash
# 核心陷阱实证：用恒 0 指标写告警，故障发生时会不会触发？
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501

q() { curl -s "http://127.0.0.$1:$((8500+$1))/v1/agent/metrics?format=prometheus"; }

echo "########## 1. 故障前：两套指标的读数 ##########"
echo "  无前缀（常见教程写法）:"
q 1 | grep -E '^consul_(autopilot_healthy|server_isLeader) ' | sed 's/^/    /'
echo "  带前缀（真实值）:"
q 1 | grep -E '^consul_VWYPGWU_PC5_(autopilot_healthy|server_isLeader) ' | sed 's/^/    /'

echo
echo "########## 2. 注入故障：停掉 leader（node1）##########"
LN=$(consul operator raft list-peers | awk 'NR>1 && $4=="leader"{print $1}' | grep -oE '[0-9]+$')
echo "  当前 leader = node$LN，停掉它"
LP=$(pgrep -f "conf/node$LN.hcl" | head -1)
[ -z "$LP" ] && LP=$(pgrep -x consul | head -1)
kill -9 "$LP" 2>/dev/null
sleep 12

echo
echo "########## 3. 故障后：观察两套指标 ##########"
NL=$(consul operator raft list-peers 2>/dev/null | awk 'NR>1 && $4=="leader"{print $1}' | grep -oE '[0-9]+$')
echo "  新 leader = node$NL（原 node$LN 已停）"
ALIVE=${NL:-2}
echo "  存活节点(2) 无前缀指标:"
q 2 | grep -E '^consul_(autopilot_healthy|server_isLeader) ' | sed 's/^/    /'
echo "  存活节点(2) 带前缀指标:"
q 2 | grep -E '^consul_VWYPGWU_PC5_(autopilot_healthy|server_isLeader|members_servers) ' | sed 's/^/    /'

echo
echo "########## 4. 关键推演：如果告警这么写会怎样 ##########"
AH_NO=$(q 2 | grep -E '^consul_autopilot_healthy ' | awk '{print $2}')
AH_YES=$(q 2 | grep -E '^consul_VWYPGWU_PC5_autopilot_healthy ' | awk '{print $2}')
SL_NO=$(q 2 | grep -E '^consul_server_isLeader ' | awk '{print $2}')
SL_YES=$(q 2 | grep -E '^consul_VWYPGWU_PC5_server_isLeader ' | awk '{print $2}')
python3 -c "
print(f'  规则A: consul_autopilot_healthy == 0  → 实测值 {$AH_NO} → {\"告警\" if $AH_NO==0 else \"不告警\"}')
print(f'  规则B: consul_server_isLeader == 0   → 实测值 {$SL_NO} → {\"告警\" if $SL_NO==0 else \"不告警\"}')
print(f'  规则C: 带前缀 autopilot_healthy == 0 → 实测值 {$AH_YES} → {\"告警\" if $AH_YES==0 else \"不告警\"}')
print(f'  规则D: 带前缀 server_isLeader == 0   → 实测值 {$SL_YES} → {\"告警\" if $SL_YES==0 else \"不告警\"}')
"

echo
echo "########## 5. 再看 members_servers（数节点数更可靠）##########"
for n in 2 3; do
  MS=$(q $n | grep -E '^consul_VWYPGWU_PC5_members_servers' | awk '{print $2}')
  echo "  node$n: 带前缀 members_servers = $MS（期望 2，因为挂了 1 台）"
done

echo
echo "########## 6. 恢复：重启 node$LN ##########"
nohup consul agent -config-file /tmp/consul-ops/conf/node$LN.hcl > /tmp/consul-ops/log/node$LN.log 2>&1 &
sleep 14
consul operator raft list-peers | awk 'NR>1{print "    "$1" "$4}'