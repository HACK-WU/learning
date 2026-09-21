#!/usr/bin/env bash
# 核验：autopilot_healthy 指标在 leader 与 follower 上是否一致？（告警误报陷阱）
BASE=/tmp/consul-ops

echo "########## 分别在三个节点上采集 autopilot 指标 ##########"
for i in 1 2 3; do
  echo "--- node$i ($(curl -s http://127.0.0.$i:$((8500+i))/v1/status/leader | tr -d '\"') 是 leader) ---"
  curl -s "http://127.0.0.$i:$((8500+i))/v1/agent/metrics?format=prometheus" \
    | grep -E '^consul_autopilot|^consul_raft_state|^consul_server_isLeader' || echo "  (无该指标)"
done

echo
echo "########## 各节点 /v1/operator/autopilot/health 的 Healthy ##########"
for i in 1 2 3; do
  echo -n "  node$i Healthy="
  curl -s "http://127.0.0.$i:$((8500+i))/v1/operator/autopilot/health" \
    | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['Healthy'],'FailureTolerance=',d['FailureTolerance'])"
done

echo
echo "########## 连续采样 3 次 node1 的 autopilot_healthy（看是否一直 0）##########"
for n in 1 2 3; do
  v=$(curl -s "http://127.0.0.1:8501/v1/agent/metrics?format=prometheus" | grep -E '^consul_autopilot_healthy' | awk '{print $2}')
  echo "  第${n}次: consul_autopilot_healthy = $v"
  sleep 2
done

echo
echo "########## raft 相关指标（修正后的正确解析）##########"
curl -s http://127.0.0.1:8501/v1/agent/metrics | python3 -c "
import sys,json
d=json.load(sys.stdin)
g=d.get('Gauges',{})
keys=[k for k in g if 'raft' in k or 'autopilot' in k]
for k in sorted(keys):
    print(f'  {k:50s} = {g[k][\"Value\"]}')
"
