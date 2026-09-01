#!/usr/bin/env bash
# 课 6 知识点 2：哨兵故障转移（修正版）
# 关键修正：本机 redis 8.10.1 安装没有 redis-sentinel 命令
#           必须用 redis-server <conf> --sentinel
BASE=/tmp/redis-course-l06-sen2
rm -rf "$BASE"; mkdir -p "$BASE"/{6401,6402,6403,s1,s2,s3}

echo "=== 0. 环境说明 ==="
echo "  redis-sentinel 命令: $(which redis-sentinel 2>/dev/null || echo '不存在')"
echo "  替代方案: redis-server <conf> --sentinel"
echo ""

echo "=== 1. 启动主从 ==="
for p in 6401 6402 6403; do
  redis-server --port $p --daemonize yes --save '' --appendonly no \
    --dir "$BASE/$p" --logfile "$BASE/$p/redis.log" > /dev/null 2>&1
done
sleep 1
redis-cli -p 6402 replicaof 127.0.0.1 6401 > /dev/null
redis-cli -p 6403 replicaof 127.0.0.1 6401 > /dev/null
redis-cli -p 6401 config set repl-diskless-sync-delay 0 > /dev/null
sleep 3
# 灌点数据
seq 1 10000 | awk '{print "set k:"$1" v"$1}' | redis-cli -p 6401 --pipe > /dev/null 2>&1
echo "  主库 6401: connected_slaves=$(redis-cli -p 6401 info replication | grep -oP '(?<=^connected_slaves:)\d+'), dbsize=$(redis-cli -p 6401 dbsize)"
echo ""

echo "=== 2. 哨兵配置 ==="
for i in 1 2 3; do
cat > "$BASE/sen$i.conf" <<EOF
port 2640$i
daemonize yes
dir "$BASE/s$i"
logfile "$BASE/s$i/sentinel.log"
sentinel monitor mymaster 127.0.0.1 6401 2
sentinel down-after-milliseconds mymaster 5000
sentinel failover-timeout mymaster 10000
sentinel parallel-syncs mymaster 1
EOF
done
echo "  quorum=2, down-after=5000ms, failover-timeout=10000ms"
echo ""

echo "=== 3. 启动 3 个哨兵 ==="
for i in 1 2 3; do
  redis-server "$BASE/sen$i.conf" --sentinel > /dev/null 2>&1
done
sleep 5
for p in 26401 26402 26403; do
  echo "  哨兵 $p: $(redis-cli -p $p ping 2>/dev/null || echo '未响应')"
done
echo ""

echo "=== 4. 哨兵视角 ==="
MasterInfo=$(redis-cli -p 26401 sentinel master mymaster 2>/dev/null)
echo "$MasterInfo" | paste - - | grep -E "^name|^ip|^port|^flags|^num-slaves|^num-other-sentinels|^quorum|^down-after-milliseconds|^failover-timeout"
echo ""
echo "  从库列表："
redis-cli -p 26401 sentinel replicas mymaster 2>/dev/null | paste - - | grep -E "^name|^port|^flags|^master-link-status"
echo ""

echo "=== 5. 哨兵互相发现机制 ==="
echo "  主库上的哨兵 hello 频道订阅数: $(redis-cli -p 6401 pubsub channels '*sentinel*' 2>/dev/null | wc -l)"
redis-cli -p 6401 pubsub channels 2>/dev/null | grep -i sentinel | head -2
echo ""

echo "########## 6. 故障转移实测 ##########"
echo "  转移前主库: $(redis-cli -p 26401 sentinel get-master-addr-by-name mymaster 2>/dev/null | tr '\n' ':' | sed 's/:$//')"
T0=$(date +%s%N)
MPID=$(redis-cli -p 6401 info server | grep -oP '(?<=^process_id:)\d+')
echo "  kill -9 主库 (pid=$MPID)"
kill -9 "$MPID" 2>/dev/null

NEW=""
for i in $(seq 1 20); do
  ADDR=$(redis-cli -p 26401 sentinel get-master-addr-by-name mymaster 2>/dev/null | tr '\n' ':' | sed 's/:$//')
  EL=$(awk "BEGIN{printf \"%.1f\", ($(date +%s%N)-$T0)/1000000000}")
  if [ -n "$ADDR" ] && [ "$ADDR" != "127.0.0.1:6401" ] && [ "$ADDR" != ":" ]; then
    echo "    t=${EL}s  ✅ 新主库 = $ADDR"
    NEW=$ADDR
    break
  else
    echo "    t=${EL}s  主库仍为 ${ADDR:-未知}"
  fi
  sleep 1
done

echo ""
if [ -n "$NEW" ]; then
  T1=$(date +%s%N)
  echo "  ⏱️  故障转移总耗时: $(awk "BEGIN{printf \"%.2f 秒\", ($T1-$T0)/1000000000}")"
else
  echo "  ❌ 故障转移未在 20 秒内完成"
fi

echo ""
echo "=== 7. 转移后状态 ==="
NEWP=${NEW#*:}
echo "  新主库 $NEWP: role=$(redis-cli -p $NEWP info replication | grep -oP '(?<=^role:)\w+'), dbsize=$(redis-cli -p $NEWP dbsize), connected_slaves=$(redis-cli -p $NEWP info replication | grep -oP '(?<=^connected_slaves:)\d+')"
echo ""
for p in 6402 6403; do
  echo "  $p: role=$(redis-cli -p $p info replication | grep -oP '(?<=^role:)\w+'), master_port=$(redis-cli -p $p info replication | grep -oP '(?<=^master_port:)\d+'), dbsize=$(redis-cli -p $p dbsize)"
done
echo ""

echo "=== 8. 哨兵日志关键事件 ==="
grep -E "sdown|odown|vote|elected|switch-master|\+failover" "$BASE/s1/sentinel.log" 2>/dev/null | tail -12 | cut -c1-145

echo ""
echo "=== 清理 ==="
for p in 26403 26402 26401; do redis-cli -p $p shutdown nosave 2>/dev/null; done
for p in 6403 6402 6401; do redis-cli -p $p shutdown nosave 2>/dev/null; done
sleep 1.5
rm -rf "$BASE"
echo "done"
