#!/usr/bin/env bash
BASE=/tmp/consul-ops/dualdc
D1=http://127.0.1.1:8500
D2=http://127.0.2.1:8500

echo "########## 重启 dc2 ##########"
nohup consul agent -config-file $BASE/conf/dc2-s1.hcl > $BASE/log/dc2-s1.log 2>&1 &
sleep 10
echo "  dc2 状态 = $(CONSUL_HTTP_ADDR=$D1 consul members -wan 2>/dev/null | awk '$1=="dc2-s1.dc2"{print $3}')"

echo
echo "########## 实验 A：consul leave（优雅下线）##########"
echo "  执行 leave..."
CONSUL_HTTP_ADDR=$D2 consul leave 2>&1 | sed 's/^/    /'
sleep 6
echo "  WAN 成员表:"; CONSUL_HTTP_ADDR=$D1 consul members -wan 2>&1 | sed 's/^/    /'
echo "  >>> 判定：dc2-s1 是否从表中【完全消失】（left 状态）"
echo "  dc2 进程数 = $(pgrep -fc 'conf/dc2-s1.hcl' 2>/dev/null || echo 0)"

echo
echo "########## 重启 dc2，再做硬杀对比 ##########"
nohup consul agent -config-file $BASE/conf/dc2-s1.hcl > $BASE/log/dc2-s1.log 2>&1 &
sleep 10
echo "  dc2 状态 = $(CONSUL_HTTP_ADDR=$D1 consul members -wan 2>/dev/null | awk '$1=="dc2-s1.dc2"{print $3}')"

echo
echo "########## 实验 B：kill -9（硬杀，非优雅）##########"
PID=$(pgrep -f 'conf/dc2-s1.hcl' | head -1)
kill -9 $PID 2>/dev/null
echo "  已 kill -9 (pid=$PID)"
sleep 6
echo "  WAN 成员表（6秒后）:"; CONSUL_HTTP_ADDR=$D1 consul members -wan 2>&1 | sed 's/^/    /'
echo "  >>> 判定：dc2-s1 是否【仍在表中】且状态 alive/failed（未被摘除）"

echo
echo "########## 实验 C：leave 后数据是否还在（退出的可逆性）##########"
echo "  dc1 数据 app/only-dc1 = '$(curl -s $D1/v1/kv/app/only-dc1?raw 2>/dev/null)'"
echo "  >>> 一个 DC 退出，不影响另一个 DC 的数据"

echo
echo "########## 实验 D：单 DC 内 server 下线的 quorum 影响（退出顺序）##########"
echo "  当前 dc1 raft peers:"; CONSUL_HTTP_ADDR=$D1 consul operator raft list-peers 2>&1 | sed 's/^/    /'
echo "  --- 停 dc1-s3（follower），quorum 2/3 保住 ---"
P3=$(pgrep -f 'conf/dc1-s3.hcl' | head -1)
kill -TERM $P3 2>/dev/null
sleep 8
echo "    dc1 写 = HTTP $(curl -s -o /dev/null -w '%{http_code}' -X PUT -d 'after-s3-leave' $D1/v1/kv/test/afterleave)"
echo "    raft peers:"; CONSUL_HTTP_ADDR=$D1 consul operator raft list-peers 2>&1 | sed 's/^/      /'
