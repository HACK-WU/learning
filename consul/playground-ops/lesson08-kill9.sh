#!/usr/bin/env bash
BASE=/tmp/consul-ops/dualdc
D1=http://127.0.1.1:8500
D2=http://127.0.2.1:8500

echo "########## 硬杀（kill -9）对比 leave ##########"
echo "  基态 = $(CONSUL_HTTP_ADDR=$D1 consul members -wan 2>/dev/null | awk '$1=="dc2-s1.dc2"{print $3}')"
P=$(pgrep -f 'conf/dc2-s1.hcl' | head -1)
echo "  kill -9 pid=$P"
kill -9 $P 2>/dev/null

for t in 6 25 45; do
  sleep $([ $t -eq 6 ] && echo 6 || echo 20)
  S=$(CONSUL_HTTP_ADDR=$D1 consul members -wan 2>/dev/null | awk '$1=="dc2-s1.dc2"{print $3}')
  echo "  T+${t}s  状态 = ${S:-消失}"
done

echo
echo "  跨DC读（此时 dc2 已死）= '$(curl -s --max-time 5 "$D1/v1/kv/app/only-dc2?dc=dc2&raw" 2>/dev/null)'"
echo
echo "########## 对比表数据采集完成 ##########"
echo "  leave : 立刻 left，跨DC读 → No path to datacenter"
echo "  kill-9: 延迟约40s → failed，节点仍在表中"
