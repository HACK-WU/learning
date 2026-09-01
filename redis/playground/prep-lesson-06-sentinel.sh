#!/usr/bin/env bash
# 课 6 知识点 2：哨兵故障转移
# 拓扑：1 主(6401) + 2 从(6402,6403) + 3 哨兵(26401,26402,26403)
BASE=/tmp/redis-course-l06-sentinel
rm -rf "$BASE"; mkdir -p "$BASE"/{6401,6402,6403,s1,s2,s3}

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
echo "  主库 6401 connected_slaves: $(redis-cli -p 6401 info replication | grep -oP '(?<=^connected_slaves:)\d+')"
echo ""

echo "=== 2. 写哨兵配置文件 ==="
cat > "$BASE/sentinel.conf" <<EOF
port 26401
daemonize yes
dir "$BASE/s1"
logfile "$BASE/s1/sentinel.log"
sentinel monitor mymaster 127.0.0.1 6401 2
sentinel down-after-milliseconds mymaster 5000
sentinel failover-timeout mymaster 10000
sentinel parallel-syncs mymaster 1
EOF
for i in 2 3; do
  sed -e "s/^port 26401/port 2640$i/" \
      -e "s|$BASE/s1|$BASE/s$i|g" "$BASE/sentinel.conf" > "$BASE/sentinel$i.conf"
done

echo "  quorum=2（3 个哨兵中至少 2 个认为主库下线才判定客观下线）"
echo "  down-after-milliseconds=5000（5 秒无响应判为主观下线）"
echo ""

echo "=== 3. 启动 3 个哨兵 ==="
for i in 1 2 3; do
  redis-sentinel "$BASE/sentinel$([ $i -eq 1 ] && echo '' || echo $i).conf" > /dev/null 2>&1
done
sleep 4
for p in 26401 26402 26403; do
  echo "  哨兵 $p: $(redis-cli -p $p ping 2>/dev/null)"
done
echo ""

echo "=== 4. 哨兵视角的集群状态 ==="
redis-cli -p 26401 sentinel master mymaster | paste - - | grep -E "name|ip|port|flags|num-slaves|num-other-sentinels|quorum|down-after|failover-timeout"
echo ""
echo "  发现的从库："
redis-cli -p 26401 sentinel replicas mymaster | paste - - | grep -E "^name|^port|^flags" | head -6
echo ""
echo "  发现的其他哨兵数: $(redis-cli -p 26401 sentinel master mymaster | paste - - | grep -A1 'num-other-sentinels' | tail -1)"
echo ""

echo "=== 5. 哨兵之间如何发现彼此？看 pub/sub ==="
echo "  哨兵通过主库的 __sentinel__:hello 频道互相发现"
redis-cli -p 6401 pubsub channels 2>/dev/null | head -3

echo ""
echo "########## 6. 故障转移实测：杀掉主库 ##########"
echo "  当前主库: $(redis-cli -p 26401 sentinel get-master-addr-by-name mymaster | tr '\n' ':')"
echo "  记录故障转移开始时间..."
T0=$(date +%s)

MPID=$(redis-cli -p 6401 info server | grep -oP '(?<=^process_id:)\d+')
echo "  kill -9 主库 (pid=$MPID)"
kill -9 "$MPID"
sleep 2

echo ""
echo "  --- 故障转移过程中每 2 秒采样一次 ---"
NEW=""
for i in $(seq 1 12); do
  ADDR=$(redis-cli -p 26401 sentinel get-master-addr-by-name mymaster 2>/dev/null | tr '\n' ':' | sed 's/:$//')
  echo "    t=$(awk "BEGIN{printf \"%.0f\", $i*2}")s  当前主库=$ADDR"
  if [ -n "$ADDR" ] && [ "$ADDR" != "127.0.0.1:6401" ]; then NEW=$ADDR; break; fi
  sleep 2
done
T1=$(date +%s)
echo ""
if [ -n "$NEW" ]; then
  echo "  ✅ 故障转移完成，新主库: $NEW"
  echo "  ⏱️  总耗时: $((T1-T0)) 秒"
else
  echo "  ❌ 未在预期时间内完成故障转移"
fi

echo ""
echo "=== 7. 故障转移后验证 ==="
echo "  新主库角色: $(redis-cli -p ${NEW#*:} info replication | grep -oP '(?<=^role:)\w+')"
echo "  哨兵记录的主库: $(redis-cli -p 26401 sentinel get-master-addr-by-name mymaster | tr '\n' ':')"
echo ""
echo "  各节点角色："
for p in 6402 6403; do
  echo "    $p: role=$(redis-cli -p $p info replication | grep -oP '(?<=^role:)\w+')  dbsize=$(redis-cli -p $p dbsize)"
done
echo ""

echo "=== 8. 哨兵日志关键事件 ==="
grep -E "sdown|odown|vote|elected|switch-master|failover" "$BASE/s1/sentinel.log" 2>/dev/null | tail -10 | cut -c1-150

echo ""
echo "=== 清理 ==="
for p in 26403 26402 26401; do redis-cli -p $p shutdown nosave 2>/dev/null; done
for p in 6403 6402 6401; do redis-cli -p $p shutdown nosave 2>/dev/null; done
sleep 1
rm -rf "$BASE"
echo "done"
