#!/usr/bin/env bash
BASE=/tmp/consul-ops/dualdc
D1=http://127.0.1.1:8500
D2=http://127.0.2.1:8500

echo "########## 关键问题：leave 过的节点能否原样重启回来？##########"
echo "  （实验A 之后 dc2 重启，状态仍是 left — 说明 leave 有持久痕迹）"
echo
echo "  尝试 1：直接重启（同 node_name / 同 data_dir）"
nohup consul agent -config-file $BASE/conf/dc2-s1.hcl > $BASE/log/dc2-s1.log 2>&1 &
sleep 10
echo "    状态 = $(CONSUL_HTTP_ADDR=$D1 consul members -wan 2>/dev/null | awk '$1=="dc2-s1.dc2"{print $3}')"
P=$(pgrep -f 'conf/dc2-s1.hcl' | head -1)
[ -n "$P" ] && kill -9 $P 2>/dev/null
sleep 3

echo
echo "  尝试 2：清空 data_dir 后重启（模拟"干净重加入"）"
rm -rf $BASE/data/dc2/node1/* 2>/dev/null
nohup consul agent -config-file $BASE/conf/dc2-s1.hcl > $BASE/log/dc2-s1.log 2>&1 &
sleep 12
S=$(CONSUL_HTTP_ADDR=$D1 consul members -wan 2>/dev/null | awk '$1=="dc2-s1.dc2"{print $3}')
echo "    状态 = ${S:-（表中无此节点）}"
if [ "$S" = "alive" ]; then
  echo "    >>> 清 data_dir 才能恢复 alive。leave 状态持久化在 data_dir 的 serf snapshot 里"
fi

echo
echo "########## 现在做硬杀对比（确保基态是 alive）##########"
if [ "$S" = "alive" ]; then
  P=$(pgrep -f 'conf/dc2-s1.hcl' | head -1)
  echo "  kill -9 pid=$P"
  kill -9 $P 2>/dev/null
  sleep 6
  echo "  6 秒后 WAN 成员表:"; CONSUL_HTTP_ADDR=$D1 consul members -wan 2>&1 | sed 's/^/    /'
  echo "  >>> 判定：节点是否【仍在表中】（对比 leave 的"消失/left"）"
else
  echo "  ⚠️ 基态非 alive，跳过"
fi
