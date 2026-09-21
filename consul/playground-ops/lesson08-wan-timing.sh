#!/usr/bin/env bash
BASE=/tmp/consul-ops/dualdc
D1=http://127.0.1.1:8500

echo "########## 重启 dc2 ##########"
nohup consul agent -config-file $BASE/conf/dc2-s1.hcl > $BASE/log/dc2-s1.log 2>&1 &
sleep 10
echo "  dc2 状态 = $(CONSUL_HTTP_ADDR=$D1 consul members -wan 2>/dev/null | awk '$1=="dc2-s1.dc2"{print $3}')"

echo
echo "########## 精确计时：停 dc2 后多久被标记 failed ##########"
PID=$(pgrep -f 'conf/dc2-s1.hcl' | head -1)
kill -TERM $PID 2>/dev/null
START=$(date +%s)
echo "  停机时刻: $(date +%T)"
for i in $(seq 1 40); do
  sleep 3
  S=$(CONSUL_HTTP_ADDR=$D1 consul members -wan 2>/dev/null | awk '$1=="dc2-s1.dc2"{print $3}')
  NOW=$(date +%s); EL=$((NOW-START))
  printf "  T+%3ds  状态=%s\n" "$EL" "${S:-消失}"
  if [ "$S" = "failed" ] || [ -z "$S" ]; then
    echo "  >>> 检测耗时约 ${EL} 秒（$(echo "scale=1;$EL/60" | bc 2>/dev/null) 分钟）"
    break
  fi
done

echo
echo "########## 期间 dc1 是否受影响（故障域隔离验证）##########"
echo "  dc1 写 = HTTP $(curl -s -o /dev/null -w '%{http_code}' -X PUT -d 'during-dc2-fail' $D1/v1/kv/test/duringfail)"
echo "  dc1 raft peers:"; CONSUL_HTTP_ADDR=$D1 consul operator raft list-peers 2>&1 | sed 's/^/    /'
