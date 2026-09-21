#!/usr/bin/env bash
# 知识点 1：健康读数全集——leader / quorum / 复制延迟 / autopilot / 目录
BASE=/tmp/consul-ops
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501

echo "########## 1. leader 是谁（三种问法对比）##########"
echo "-- A. /v1/status/leader（最轻量）--"
curl -s http://127.0.0.1:8501/v1/status/leader; echo
echo "-- B. raft list-peers --"
consul operator raft list-peers
echo "-- C. /v1/status/peers --"
curl -s http://127.0.0.1:8501/v1/status/peers; echo

echo
echo "########## 2. 各节点对 leader 的认知是否一致 ##########"
for i in 1 2 3; do
  echo -n "  node$i 认为 leader = "
  curl -s "http://127.0.0.$i:$((8500+i))/v1/status/leader"; echo
done

echo
echo "########## 3. autopilot 健康（综合判定 + 容错余量）##########"
curl -s http://127.0.0.1:8501/v1/operator/autopilot/health | python3 -m json.tool

echo
echo "########## 4. autopilot 配置 ##########"
consul operator autopilot get-config

echo
echo "########## 5. 复制延迟：last_contact / last_log_term 等 ##########"
curl -s http://127.0.0.1:8501/v1/agent/metrics?format=prometheus -o "$BASE/m.txt" 2>/dev/null
grep -E '^consul_raft_(lastContact|commitTime|leaderOldest|apply|state|candidate)|^consul_autopilot' "$BASE/m.txt" 2>/dev/null | head -20

echo
echo "########## 6. raft 状态的数值化读数（Gauges）##########"
curl -s http://127.0.0.1:8501/v1/agent/metrics | python3 -c "
import sys,json
d=json.load(sys.stdin)
g=d.get('Gauges',{})
for k in sorted(g):
    if 'raft' in k or 'autopilot' in k or 'serf' in k.lower():
        print(f'  {k:52s} = {g[k][\"Value\"]}')
" 2>&1 | head -25
