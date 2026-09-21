#!/usr/bin/env bash
# 受控实验 2：坏 2 台的失败态 + 多轮采样看报错是否稳定
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

echo "########## 坏 1 台：不同等待时长的可写性 ##########"
restart_all
pkill -f 'conf/node3.hcl'
for t in 3 6 10 15; do
  sleep $((t==3?3:3))
  w=$(curl -s --max-time 8 -X PUT -d "t$t" $CONSUL_HTTP_ADDR/v1/kv/ops/probe 2>&1)
  printf "  停后约 %2ss: 写=%s\n" "$t" "${w:0:50}"
done

echo
echo "########## 坏 2 台：连续 4 次采样报错形态 ##########"
pkill -f 'conf/node2.hcl'; sleep 8
for i in 1 2 3 4; do
  w=$(curl -s --max-time 8 -X PUT -d "x$i" $CONSUL_HTTP_ADDR/v1/kv/ops/probe 2>&1)
  r=$(curl -s --max-time 8 $CONSUL_HTTP_ADDR/v1/kv/ops/probe?raw 2>&1)
  printf "  第%d次 写=%-55s 读=%s\n" "$i" "${w:0:55}" "${r:0:35}"
  sleep 2
done

echo
echo "剩余进程: $(pgrep -cf 'consul agent')"
pkill -f 'consul agent' 2>/dev/null; sleep 2
echo done
