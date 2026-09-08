#!/usr/bin/env bash
# 读取 webhook 收到的通知数（用 docker logs，不依赖容器内 wget）
set -u
echo "=== 1. webhook 容器的日志（每条 [NOTIFY] 就是一条通知）==="
docker logs l8-webhook 2>&1 | grep -c '\[NOTIFY\]' | sed 's/^/   通知条数 = /'

echo
echo "=== 2. 通知内容 ==="
docker logs l8-webhook 2>&1 | grep '\[NOTIFY\]'

echo
echo "=== 3. 判读 ==="
N=$(docker logs l8-webhook 2>&1 | grep -c '\[NOTIFY\]')
echo "   收到 $N 条通知"
if [ "$N" -le 1 ]; then
  echo "   --> gossip 生效：两个 AM 副本只发出 1 条通知"
else
  echo "   --> 收到 $N 条：需要进一步区分是重复通知还是 group_interval 的重复提醒"
fi

echo
echo "=== 4. 决定性对照：拆散 gossip 集群，看会不会发两遍 ==="
echo "   （这个对照能证明 gossip 确实是去重的机制）"
