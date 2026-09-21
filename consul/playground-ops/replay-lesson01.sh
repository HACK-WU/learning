#!/usr/bin/env bash
# 复验：4b 的两种失败形态都应被判定为"读写失败"
BASE=/tmp/consul-ops
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501
FAIL=0

# 干净重启
pkill -f 'consul agent' 2>/dev/null; sleep 2
rm -rf $BASE/data/node{1,2,3}; mkdir -p $BASE/data/node{1,2,3}
for i in 1 2 3; do
  nohup consul agent -config-file $BASE/conf/node$i.hcl > $BASE/log/node$i.log 2>&1 &
done
sleep 15
echo "启动: $(pgrep -cf 'consul agent') 个"
consul operator raft list-peers | head -4

echo
echo "########## 4a 停 1 台 ##########"
pkill -f 'conf/node3.hcl'; sleep 6
W2=$(curl -s -X PUT -d 'after-1-down' $CONSUL_HTTP_ADDR/v1/kv/ops/quorum)
echo "写=$W2"
[ "$W2" = "true" ] || { echo "!! FAIL 4a 应可写"; FAIL=1; }

echo
echo "########## 4b 再停 1 台 ##########"
pkill -f 'conf/node2.hcl'; sleep 6
W3=$(curl -s --max-time 8 -X PUT -d 'x' $CONSUL_HTTP_ADDR/v1/kv/ops/quorum)
R3=$(curl -s --max-time 8 $CONSUL_HTTP_ADDR/v1/kv/ops/quorum?raw)
echo "写返回: $W3"
echo "读返回: $R3"

# 判定：只要不是 true / 正常值，且非空，就算"读写失败"
ok_write=no; ok_read=no
echo "$W3" | grep -qE 'Raft leader not found|connection refused|rpc error' && ok_write=yes
echo "$R3" | grep -qE 'Raft leader not found|connection refused|rpc error' && ok_read=yes
echo "识别为失败: 写=$ok_write 读=$ok_read"
[ "$ok_write" = yes ] && [ "$ok_read" = yes ] || { echo "!! FAIL 4b 未识别为失败"; FAIL=1; }

# 同时确认：进程还活着（讲义核心论点）
STILL=$(pgrep -cf 'consul agent')
echo "剩余 consul 进程数 = $STILL  ← 进程仍活着，但已不可用"
[ "$STILL" -ge 1 ] || { echo "!! FAIL 应仍有存活进程"; FAIL=1; }

echo
echo "########## 恢复 ##########"
nohup consul agent -config-file $BASE/conf/node2.hcl > $BASE/log/node2.log 2>&1 &
nohup consul agent -config-file $BASE/conf/node3.hcl > $BASE/log/node3.log 2>&1 &
sleep 15
W4=$(curl -s -X PUT -d 'recovered' $CONSUL_HTTP_ADDR/v1/kv/ops/quorum)
echo "恢复后写=$W4"
[ "$W4" = "true" ] || { echo "!! FAIL 恢复"; FAIL=1; }

pkill -f 'consul agent'; sleep 2
echo
[ $FAIL -eq 0 ] && echo "=== 复验通过 ===" || echo "=== 复验失败 ==="
exit $FAIL
