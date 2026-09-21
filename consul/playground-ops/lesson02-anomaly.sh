#!/usr/bin/env bash
# 知识点 3：典型异常处置——leader 震荡、节点失联、脑裂边界
BASE=/tmp/consul-ops
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501

# 先恢复 3 节点
pkill -f 'consul agent' 2>/dev/null || true
sleep 2
rm -rf "$BASE"/data/node{1,2,3}
mkdir -p "$BASE"/data/node{1,2,3}
for i in 1 2 3; do nohup consul agent -config-file "$BASE/conf/node$i.hcl" > "$BASE/log/node$i.log" 2>&1 & done
sleep 15
echo "基线 leader:"
consul operator raft list-peers | awk '$4=="leader"{print "  "$1,$4,"term="$6}'

echo
echo "########## A. leader 震荡：连续 3 次杀掉 leader，观察 term 递增与恢复时间 ##########"
for round in 1 2 3; do
  LNUM=$(consul operator raft list-peers | awk '$4=="leader"{print $1}' | grep -oE '[0-9]+$')
  echo "-- 第 $round 轮：当前 leader = ops-node-$LNUM --"
  pkill -f "conf/node$LNUM.hcl"
  # 测量多久恢复可写
  START=$(date +%s)
  for t in $(seq 1 20); do
    sleep 1
    R=$(curl -s --max-time 3 -X PUT -d "r$round" http://127.0.0.1:8501/v1/kv/ops/probe 2>/dev/null)
    if [ "$R" = "true" ]; then
      echo "   恢复可写耗时 ${t}s；新 leader=$(consul operator raft list-peers 2>/dev/null | awk '$4=="leader"{print $1}')"
      break
    fi
  done
  # 重启被杀节点
  nohup consul agent -config-file "$BASE/conf/node$LNUM.hcl" > "$BASE/log/node$LNUM.log" 2>&1 &
  sleep 10
done

echo
echo "########## B. 最终 raft 状态（term 应已递增）##########"
consul operator raft list-peers
curl -s http://127.0.0.1:8501/v1/operator/autopilot/health | python3 -c "import sys,json;d=json.load(sys.stdin);print('Healthy=',d['Healthy'],'FailureTolerance=',d['FailureTolerance'])"

echo
echo "########## C. 脑裂边界：3 节点分成 2|1，少数派能否写入 ##########"
echo "-- 用停掉节点的方式验证少数派行为（iptables 分区风险高，不采用）--"
LNUM=$(consul operator raft list-peers | awk '$4=="leader"{print $1}' | grep -oE '[0-9]+$')
OTHER1=$([ "$LNUM" != 2 ] && echo 2 || echo 1)
OTHER2=$([ "$LNUM" != 3 ] && echo 3 || echo 1)
echo "停掉 1 台（$OTHER1），留 2 台 → 多数派侧"
pkill -f "conf/node$OTHER1.hcl"; sleep 8
echo "  写入: $(curl -s --max-time 5 -X PUT -d m http://127.0.0.1:8501/v1/kv/ops/split 2>&1 | head -c 50)"
echo "停掉第 2 台（$OTHER2），留 1 台 → 少数派侧"
pkill -f "conf/node$OTHER2.hcl"; sleep 8
echo "  写入: $(curl -s --max-time 5 -X PUT -d s http://127.0.0.1:8501/v1/kv/ops/split 2>&1 | head -c 60)"
echo "  读取: $(curl -s --max-time 5 http://127.0.0.1:8501/v1/kv/ops/split?raw 2>&1 | head -c 60)"
echo "  → 少数派不可写（无 quorum），这正是脑裂不会发生的原因"
