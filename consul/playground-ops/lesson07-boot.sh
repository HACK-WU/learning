#!/usr/bin/env bash
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501
D=/tmp/consul-ops
mkdir -p $D/logs $D/data/node1 $D/data/node2 $D/data/node3

echo "########## 启动集群 ##########"
bash $D/gen-conf.sh > /dev/null 2>&1
nohup consul agent -config-file=$D/conf/node1.hcl > $D/logs/node1.log 2>&1 &
sleep 2
nohup consul agent -config-file=$D/conf/node2.hcl > $D/logs/node2.log 2>&1 &
nohup consul agent -config-file=$D/conf/node3.hcl > $D/logs/node3.log 2>&1 &
sleep 18
echo "  进程数 = $(pgrep -fc 'consul agent')"
consul operator raft list-peers 2>&1 | sed 's/^/  /'
