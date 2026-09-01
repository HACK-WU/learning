#!/usr/bin/env bash
# 课 6 知识点 3：哨兵解决不了的丢数据 —— 异步复制的固有缺陷
BASE=/tmp/redis-course-l06-loss
rm -rf "$BASE"; mkdir -p "$BASE"/{6401,6402,6403,s1,s2,s3}

echo "########## 实验设计 ##########"
echo "  1. 主库持续写入，从库异步复制"
echo "  2. 在主库写入的瞬间 kill -9 主库"
echo "  3. 哨兵把从库提升为新主库"
echo "  4. 对比「主库已确认的写入」vs「新主库实际拥有的数据」"
echo ""

for p in 6401 6402 6403; do
  redis-server --port $p --daemonize yes --save '' --appendonly no \
    --dir "$BASE/$p" --logfile "$BASE/$p/redis.log" > /dev/null 2>&1
done
sleep 1
redis-cli -p 6401 config set repl-diskless-sync-delay 0 > /dev/null
redis-cli -p 6402 replicaof 127.0.0.1 6401 > /dev/null
redis-cli -p 6403 replicaof 127.0.0.1 6401 > /dev/null
sleep 3
echo "  主从就绪: 主=$(redis-cli -p 6401 info replication | grep -oP '(?<=^connected_slaves:)\d+') 个从库"
echo ""

echo "=== 哨兵配置（down-after 设为 3000ms 加快）==="
for i in 1 2 3; do
cat > "$BASE/sen$i.conf" <<EOF
port 2640$i
daemonize yes
dir "$BASE/s$i"
logfile "$BASE/s$i/sentinel.log"
sentinel monitor mymaster 127.0.0.1 6401 2
sentinel down-after-milliseconds mymaster 3000
sentinel failover-timeout mymaster 10000
sentinel parallel-syncs mymaster 1
EOF
done
for i in 1 2 3; do redis-server "$BASE/sen$i.conf" --sentinel > /dev/null 2>&1; done
sleep 4
echo "  哨兵就绪: $(redis-cli -p 26401 sentinel master mymaster 2>/dev/null | paste - - | grep -A1 '^num-other-sentinels' | tail -1) 个伙伴哨兵"
echo ""

echo "########## 开始丢数据实验 ##########"
echo ""

# 记录已确认写入的 key（主线程持续写入，每次记录最后成功写入的序号）
rm -f "$BASE/written.txt"

# 后台持续写入
(
  for i in $(seq 1 100000); do
    R=$(redis-cli -p 6401 set "lost:$i" "v$i" 2>/dev/null)
    if [ "$R" = "OK" ]; then
      echo "$i" > "$BASE/written.txt"
    else
      break
    fi
  done
) &
WPID=$!

# 写入 2 秒后立刻杀主库
sleep 2
MPID=$(redis-cli -p 6401 info server | grep -oP '(?<=^process_id:)\d+')
echo "  主库已确认写入进度: $(cat "$BASE/written.txt" 2>/dev/null)"
echo "  >>> kill -9 主库 (pid=$MPID)"
kill -9 "$MPID" 2>/dev/null

# 停掉写入
kill $WPID 2>/dev/null
wait $WPID 2>/dev/null

WRITTEN=$(cat "$BASE/written.txt" 2>/dev/null || echo 0)
echo "  主库最后确认写入序号: $WRITTEN"
echo ""

echo "=== 等待哨兵完成故障转移 ==="
NEW=""
for i in $(seq 1 20); do
  ADDR=$(redis-cli -p 26401 sentinel get-master-addr-by-name mymaster 2>/dev/null | tr '\n' ':' | sed 's/:$//')
  if [ -n "$ADDR" ] && [ "$ADDR" != "127.0.0.1:6401" ] && [ "$ADDR" != ":" ]; then
    NEW=$ADDR; echo "  新主库: $ADDR"; break
  fi
  sleep 1
done

if [ -z "$NEW" ]; then echo "  转移失败"; exit 1; fi
NEWP=${NEW#*:}
sleep 1

echo ""
echo "########## 结果统计 ##########"
# 新主库上实际有多少个 lost: key
ACTUAL=$(redis-cli -p $NEWP --scan --pattern 'lost:*' 2>/dev/null | wc -l)
# 找最大序号
MAXKEY=$(redis-cli -p $NEWP --scan --pattern 'lost:*' 2>/dev/null | sed 's/lost://' | sort -n | tail -1)

echo "  主库确认写入:  $WRITTEN 条 (lost:1 ~ lost:$WRITTEN)"
echo "  新主库实际有:  $ACTUAL 条"
echo "  新主库最大序号: lost:$MAXKEY"
echo ""
LOST=$((WRITTEN - ACTUAL))
if [ "$LOST" -gt 0 ]; then
  echo "  ❌ 永久丢失: $LOST 条 (序号 $MAXKEY ~ $WRITTEN)"
  echo "     这些数据主库已经返回 OK，但从未传到从库"
else
  echo "  本次未观测到丢失（网络太快，复制已完成）"
fi
echo ""

echo "=== 其他从库的数据一致性 ==="
for p in 6402 6403; do
  if [ "$p" != "$NEWP" ]; then
    C=$(redis-cli -p $p --scan --pattern 'lost:*' 2>/dev/null | wc -l)
    echo "  $p (从库): $C 条"
  fi
done
echo ""

echo "=== 另一个关键场景：脑裂（split-brain）==="
echo "  场景：主库因网络分区与哨兵失联，但仍在接受客户端写入"
echo "        哨兵判定其下线，提升从库为新主"
echo "        网络恢复后，旧主被降级为从库，其分区期间的写入被清空"
echo ""
echo "  模拟方式：用 DEBUG SLEEP 冻结主库，使其无法响应哨兵心跳"
echo "  （本机难以模拟真实网络分区，这里说明机制）"
echo ""

echo "=== 清理 ==="
for p in 26403 26402 26401; do redis-cli -p $p shutdown nosave 2>/dev/null; done
for p in 6403 6402 6401; do redis-cli -p $p shutdown nosave 2>/dev/null; done
sleep 1.5
rm -rf "$BASE"
echo "done"
