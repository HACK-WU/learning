#!/usr/bin/env bash
# 知识点 3：找可靠指标——leader 变动、quorum、提交延迟
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501
P=/tmp/consul-ops/prom.txt

snap() { curl -s "http://127.0.0.$1:$((8500+$1))/v1/agent/metrics?format=prometheus"; }

echo "########## 1. leader 变动怎么检测（无可靠指标时的替代）##########"
echo "  带前缀 server_isLeader 在 leader 上应为 1:"
for n in 1 2 3; do
  V=$(snap $n | grep -E '^consul_VWYPGWU_PC5_server_isLeader ' | awk '{print $2}')
  echo "    node$n: server_isLeader = $V"
done
echo "  → 这个指标可信（leader=1, follower=0），可用"
echo "  告警思路：sum(consul_*_server_isLeader) != 1 → 没有 leader 或多个 leader"

echo
echo "########## 2. raft 提交延迟相关指标（哪些有真实值）##########"
snap 1 > $P
grep -E '^consul_VWYPGWU_PC5_raft_' $P | sed 's/^/    /'

echo
echo "########## 3. 关键：last_index 与 applied_index 差值（FSM 落后）##########"
for n in 1 2 3; do
  L=$(snap $n | grep -E '^consul_VWYPGWU_PC5_raft_last_index ' | awk '{print $2}')
  A=$(snap $n | grep -E '^consul_VWYPGWU_PC5_raft_applied_index ' | awk '{print $2}')
  echo "    node$n: last=$L applied=$A 差值=$((L-A))"
done

echo
echo "########## 4. 制造 FSM 落后：批量写入后立刻采样 ##########"
python3 - <<'PYEOF'
import json,urllib.request
ops=[{"KV":{"Verb":"set","Key":f"burst/{i}","Value":"dg=="}} for i in range(2000)]
try:
    urllib.request.urlopen(urllib.request.Request("http://127.0.0.1:8501/v1/txn",json.dumps(ops).encode(),method="PUT"),timeout=60)
    print("  已批量写入 2000 条")
except Exception as e:
    print("  写入失败:",getattr(e,'code',e))
PYEOF
for t in 1 2 3; do
  L=$(snap 1 | grep -E '^consul_VWYPGWU_PC5_raft_last_index ' | awk '{print $2}')
  A=$(snap 1 | grep -E '^consul_VWYPGWU_PC5_raft_applied_index ' | awk '{print $2}')
  echo "    采样$t: last=$L applied=$A 差值=$((L-A))"
  sleep 0.5
done

echo
echo "########## 5. 可用告警指标清单（实测有真实值的）##########"
snap 1 | grep -E '^consul_VWYPGWU_PC5_(members|state|autopilot|server|runtime)_' | awk '{print "    "$0}' | head -20

echo
echo "########## 6. 健康 API 作为兜底（指标不可信时的权威源）##########"
curl -s $CONSUL_HTTP_ADDR/v1/operator/autopilot/health | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(f'    Healthy={d[\"Healthy\"]} FailureTolerance={d[\"FailureTolerance\"]} Servers={len(d.get(\"Servers\",[]))}')
for s in d.get('Servers',[])[:3]:
    print(f'      {s[\"Name\"]}: Healthy={s[\"Healthy\"]} LastContact={s.get(\"LastContact\")}')
"