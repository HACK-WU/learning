#!/usr/bin/env bash
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501
D=/tmp/consul-ops
echo "########## 1. 滚动升级的核心约束：quorum 必须保住 ##########"
python3 -c "
n=3
q=n//2+1
print(f'  3 节点集群: quorum = {q}')
print(f'  同时停机上限 = n - quorum = {n-q} 台')
print(f'  → 3 节点【一次只能停 1 台】，停 2 台就失去 quorum')
print()
for N in [3,5,7]:
    Q=N//2+1
    print(f'  {N} 节点: quorum={Q}, 可同时停 {N-Q} 台')
"

echo
echo "########## 2. 实测：quorum 被破坏时会发生什么 ##########"
echo "  当前 leader = $(curl -s $CONSUL_HTTP_ADDR/v1/status/leader)"
echo "  --- 停掉 node3（1台，quorum 仍保住 2/3）---"
PID3=$(pgrep -f 'conf/node3.hcl' | head -1)
kill -TERM $PID3 2>/dev/null
sleep 6
echo "  存活进程 = $(pgrep -fc 'consul agent')"
echo "  新 leader = $(curl -s $CONSUL_HTTP_ADDR/v1/status/leader 2>/dev/null || echo '(无)')"
echo "  写操作是否可用:"
R=$(curl -s -o /dev/null -w '%{http_code}' -X PUT -d 'write-during-1down' $CONSUL_HTTP_ADDR/v1/kv/test/one_down)
echo "    HTTP $R  ($([ "$R" = "200" ] && echo 写成功 || echo 写失败))"

echo
echo "  --- 再停掉 node2（共2台，quorum 只剩 1/3 → 失去）---"
PID2=$(pgrep -f 'conf/node2.hcl' | head -1)
kill -TERM $PID2 2>/dev/null
sleep 6
echo "  存活进程 = $(pgrep -fc 'consul agent')"
echo "  leader = $(curl -s $CONSUL_HTTP_ADDR/v1/status/leader 2>/dev/null || echo '(无 leader)')"
R2=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -X PUT -d 'write-during-2down' $CONSUL_HTTP_ADDR/v1/kv/test/two_down 2>/dev/null)
echo "    写操作 HTTP ${R2:-超时}  → $([ "$R2" = "200" ] && echo 写成功 || echo '写失败/超时')"

echo
echo "########## 3. 恢复集群 ##########"
nohup consul agent -config-file=$D/conf/node2.hcl > $D/logs/node2.log 2>&1 &
nohup consul agent -config-file=$D/conf/node3.hcl > $D/logs/node3.log 2>&1 &
sleep 15
echo "  进程数 = $(pgrep -fc 'consul agent')"
consul operator raft list-peers 2>&1 | sed 's/^/  /'
