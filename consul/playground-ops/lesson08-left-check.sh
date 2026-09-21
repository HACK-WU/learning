#!/usr/bin/env bash
BASE=/tmp/consul-ops/dualdc
D1=http://127.0.1.1:8500
D2=http://127.0.2.1:8500

echo "########## 关键判定：left 状态是"状态残留"还是"真实不可用"？##########"
echo
echo "  --- 1. dc2 进程在不在 ---"
P=$(pgrep -f 'conf/dc2-s1.hcl' | head -1)
echo "    dc2 pid = ${P:-无}"
echo "    dc2 HTTP 探活 = $(curl -s -o /dev/null -w '%{http_code}' --max-time 3 $D2/v1/status/leader 2>/dev/null || echo 失败)"

echo
echo "  --- 2. 从 dc1 视角：状态 vs 实际可达性 ---"
S=$(CONSUL_HTTP_ADDR=$D1 consul members -wan 2>/dev/null | awk '$1=="dc2-s1.dc2"{print $3}')
echo "    WAN 表状态 = $S"
echo "    跨DC读 dc2 的 KV = '$(curl -s "$D1/v1/kv/app/only-dc2?dc=dc2&raw" 2>/dev/null)'"

echo
echo "  --- 3. 让 dc2 主动重新 join WAN ---"
if [ -n "$P" ]; then
  CONSUL_HTTP_ADDR=$D2 consul join -wan 127.0.1.1:8302 2>&1 | sed 's/^/      /'
  sleep 8
  echo "    重新 join 后状态 = $(CONSUL_HTTP_ADDR=$D1 consul members -wan 2>/dev/null | awk '$1=="dc2-s1.dc2"{print $3}')"
fi

echo
echo "########## 结论采集 ##########"
echo "  如果 left 后进程仍在且 HTTP 可通，说明 left 是【集群侧的状态标记】，"
echo "  节点本身没死；重新 join 可恢复。"
