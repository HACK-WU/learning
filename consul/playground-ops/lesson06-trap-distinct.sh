#!/usr/bin/env bash
# 关键区分：恒 0 指标对 ==0 与 >0 两种告警写法的影响完全不同
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501
echo "########## 恢复后状态 ##########"
consul operator raft list-peers | awk 'NR>1{print "  "$1" "$4}'
curl -s $CONSUL_HTTP_ADDR/v1/operator/autopilot/health | python3 -c "import sys,json;d=json.load(sys.stdin);print('  Healthy=',d['Healthy'],'FT=',d['FailureTolerance'],'Servers=',len(d.get('Servers',[])))"

echo
echo "########## 健康时：两套指标的值 ##########"
curl -s 'http://127.0.0.1:8501/v1/agent/metrics?format=prometheus' > /tmp/consul-ops/p3.txt
for m in autopilot_healthy server_isLeader; do
  A=$(grep -E "^consul_${m} " /tmp/consul-ops/p3.txt | awk '{print $2}')
  B=$(grep -E "^consul_VWYPGWU_PC5_${m} " /tmp/consul-ops/p3.txt | awk '{print $2}')
  echo "  consul_${m} = ${A:-无}    |    consul_VWYPGWU_PC5_${m} = ${B:-无}"
done

echo
echo "########## 两种写法的后果（健康 vs 故障）##########"
python3 - <<'PYEOF'
rows = [
 ("consul_autopilot_healthy == 0",  "恒0→0", "0", "健康时也触发", "永久误报（告警疲劳）"),
 ("consul_autopilot_healthy < 1",   "恒0→0", "0", "健康时也触发", "永久误报（告警疲劳）"),
 ("consul_autopilot_healthy > 0",   "恒0→0", "0", "故障时也不触发", "静默失效（最危险）"),
 ("consul_server_isLeader == 1",    "恒0→0", "0", "从不触发", "静默失效"),
 ("带前缀 autopilot_healthy == 0",  "真实1", "1", "仅故障时触发", "正确"),
]
print(f"  {'告警规则写法':42s} {'健康时':8s} {'故障时':8s} {'后果'}")
print("  "+"-"*92)
for r in rows:
    print(f"  {r[0]:42s} {r[1]:8s} {r[2]:8s} {r[4]}")
PYEOF

echo
echo "########## 结论：恒 0 指标不是\"不告警\"，而是\"告错了\"##########"
echo "  == 0 / < 1 写法 → 健康时一直告警 → 告警疲劳 → 真故障被忽略"
echo "  > 0 / == 1 写法 → 永远不触发   → 静默失效"
echo "  两种都是错的，错法不同"
