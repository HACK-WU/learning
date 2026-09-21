#!/usr/bin/env bash
# 汇总三次独立实验，确认报错形态全集
BASE=/tmp/consul-ops
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501

restart_all() {
  pkill -f 'consul agent' 2>/dev/null; sleep 2
  rm -rf $BASE/data/node{1,2,3}; mkdir -p $BASE/data/node{1,2,3}
  for i in 1 2 3; do
    nohup consul agent -config-file $BASE/conf/node$i.hcl > $BASE/log/node$i.log 2>&1 &
  done
  sleep 15
}

for round in 1 2 3; do
  echo "########## 第 $round 轮 ##########"
  restart_all
  pkill -f 'conf/node3.hcl'; sleep 8
  pkill -f 'conf/node2.hcl'; sleep 8
  for i in 1 2 3; do
    w=$(curl -s --max-time 8 -X PUT -d "r$i" $CONSUL_HTTP_ADDR/v1/kv/ops/probe 2>&1)
    r=$(curl -s --max-time 8 $CONSUL_HTTP_ADDR/v1/kv/ops/probe?raw 2>&1)
    printf "  采样%d\n    写: %s\n    读: %s\n" "$i" "${w:0:90}" "${r:0:90}"
    sleep 2
  done
done

pkill -f 'consul agent' 2>/dev/null; sleep 2
echo
echo "done"
