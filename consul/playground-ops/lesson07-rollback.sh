#!/usr/bin/env bash
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501
D=/tmp/consul-ops
echo "########## A. 区分两种 protocol（避免混淆）##########"
echo "  consul version 里的 'understands 2 to 3' = gossip/serf LAN protocol"
echo "  members 里的 ProtocolCur→ProtocolMax = 同上（gossip）"
echo "  raft list-peers 里的 RaftProtocol = Raft 协议版本"
echo
echo "--- 实测三者 ---"
echo "  gossip(CLI version 行): $(consul version | grep -o 'understands [0-9]* to [0-9]*')"
echo "  gossip(members):        $(curl -s $CONSUL_HTTP_ADDR/v1/agent/members | python3 -c 'import sys,json;m=json.load(sys.stdin)[0];print(f\"{m[\"ProtocolCur\"]}→{m[\"ProtocolMax\"]}\")')"
echo "  raft:                   $(consul operator raft list-peers 2>/dev/null | awk 'NR==2{print $6}')"

echo
echo "########## B. 升级前的基线（回滚要回到的点）##########"
consul snapshot save $D/tls/pre-upgrade.snap 2>&1 | sed 's/^/  /'
echo "  快照 index/大小 = $(stat -c%s $D/tls/pre-upgrade.snap) 字节"
curl -s -X PUT -d 'v1-before-upgrade' $CONSUL_HTTP_ADDR/v1/kv/app/version > /dev/null
echo "  基线 KV app/version = $(curl -s $CONSUL_HTTP_ADDR/v1/kv/app/version?raw)"

echo
echo "########## C. 模拟升级：写入升级过程中产生的数据 ##########"
curl -s -X PUT -d 'v2-after-upgrade' $CONSUL_HTTP_ADDR/v1/kv/app/version > /dev/null
curl -s -X PUT -d 'new-service-registered-during-upgrade' $CONSUL_HTTP_ADDR/v1/kv/app/newsvc > /dev/null
curl -s -X PUT -d 'migration-artifact' $CONSUL_HTTP_ADDR/v1/kv/app/migration > /dev/null
echo "  升级后 app/version = $(curl -s $CONSUL_HTTP_ADDR/v1/kv/app/version?raw)"
echo "  升级中新增 newsvc      = $(curl -s $CONSUL_HTTP_ADDR/v1/kv/app/newsvc?raw)"
echo "  升级中新增 migration   = $(curl -s $CONSUL_HTTP_ADDR/v1/kv/app/migration?raw)"

echo
echo "########## D. 升级失败，执行回滚（恢复升级前快照）##########"
consul snapshot save $D/tls/emergency-before-rollback.snap 2>&1 | sed 's/^/  先存当前(救命): /'
consul snapshot restore $D/tls/pre-upgrade.snap 2>&1 | sed 's/^/  回滚: /'
sleep 4

echo
echo "########## E. 回滚代价清点 ##########"
echo "  app/version = '$(curl -s $CONSUL_HTTP_ADDR/v1/kv/app/version?raw 2>/dev/null)'  (基线值 v1-before-upgrade)"
echo "  app/newsvc  = '$(curl -s $CONSUL_HTTP_ADDR/v1/kv/app/newsvc?raw 2>/dev/null)'  ← 升级中新增"
echo "  app/migration = '$(curl -s $CONSUL_HTTP_ADDR/v1/kv/app/migration?raw 2>/dev/null)'  ← 升级中新增"
echo
echo "  >>> 判定：newsvc/migration 为空 = 回滚抹掉了升级期间的新数据"
