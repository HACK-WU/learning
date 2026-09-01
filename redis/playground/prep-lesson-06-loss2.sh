#!/usr/bin/env bash
# 课 6 知识点 3：异步复制丢数据（人工制造复制滞后）
# 本机回环网络太快（从库反而比主库多一条），必须人为制造滞后
# 方法：DEBUG SLEEP 冻结从库 -> 主库写入堆积在 backlog/输出缓冲 -> 杀主库
BASE=/tmp/redis-course-l06-loss2
rm -rf "$BASE"; mkdir -p "$BASE"/{6401,6402,6403,s1,s2,s3}

echo "########## 制造复制滞后：DEBUG SLEEP 冻结从库 ##########"
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

# 灌基础数据
seq 1 5000 | awk '{print "set base:"$1" v"$1}' | redis-cli -p 6401 --pipe > /dev/null 2>&1
sleep 1
echo "  基础数据: 主库 dbsize=$(redis-cli -p 6401 dbsize), 从库 dbsize=$(redis-cli -p 6402 dbsize)"
echo ""

# 哨兵
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
echo "  哨兵就绪"
echo ""

echo "########## 实验：冻结从库 -> 主库写入 -> 杀主库 ##########"
echo ""

# 冻结两个从库（各自后台执行）
( redis-cli -p 6402 debug sleep 6 > /dev/null 2>&1 ) &
SP1=$!
( redis-cli -p 6403 debug sleep 6 > /dev/null 2>&1 ) &
SP2=$!
sleep 0.5

echo "  从库已冻结 6 秒，主库开始写入..."

# 主库持续写入，记录已确认的序号
rm -f "$BASE/written.txt"
(
  for i in $(seq 1 20000); do
    R=$(redis-cli -p 6401 set "lost:$i" "v$i" 2>/dev/null)
    if [ "$R" = "OK" ]; then
      echo "$i" > "$BASE/written.txt"
    else
      break
    fi
  done
) &
WPID=$!

# 写入约 1.5 秒后杀主库（此时从库仍冻结）
sleep 1.5
WRITTEN=$(cat "$BASE/written.txt" 2>/dev/null || echo 0)
echo "  主库已确认写入: $WRITTEN 条"

# 查看复制滞后
MO=$(redis-cli -p 6401 info replication 2>/dev/null | grep -oP '(?<=^master_repl_offset:)\d+')
echo "  主库 offset: $MO"

MPID=$(redis-cli -p 6401 info server 2>/dev/null | grep -oP '(?<=^process_id:)\d+')
echo "  >>> kill -9 主库 (pid=$MPID)"
kill -9 "$MPID" 2>/dev/null
kill $WPID 2>/dev/null
wait $WPID 2>/dev/null

# 等从库解冻
wait $SP1 2>/dev/null
wait $SP2 2>/dev/null
sleep 1

WRITTEN=$(cat "$BASE/written.txt" 2>/dev/null || echo 0)
echo ""
echo "  主库最终确认写入: $WRITTEN 条 (lost:1 ~ lost:$WRITTEN)"
echo ""

echo "=== 等待哨兵故障转移 ==="
NEW=""
for i in $(seq 1 25); do
  ADDR=$(redis-cli -p 26401 sentinel get-master-addr-by-name mymaster 2>/dev/null | tr '\n' ':' | sed 's/:$//')
  if [ -n "$ADDR" ] && [ "$ADDR" != "127.0.0.1:6401" ] && [ "$ADDR" != ":" ]; then
    NEW=$ADDR; break
  fi
  sleep 1
done
NEWP=${NEW#*:}
echo "  新主库: ${NEW:-未转移}"
sleep 1

echo ""
echo "########## 结果：异步复制到底丢了多少 ##########"
if [ -n "$NEWP" ]; then
  ACTUAL=$(redis-cli -p $NEWP --scan --pattern 'lost:*' 2>/dev/null | wc -l)
  MAXKEY=$(redis-cli -p $NEWP --scan --pattern 'lost:*' 2>/dev/null | sed 's/lost://' | sort -n | tail -1)
  echo "  主库确认写入:    $WRITTEN 条"
  echo "  新主库实际拥有:  $ACTUAL 条 (最大序号 lost:${MAXKEY:-0})"
  LOST=$((WRITTEN - ACTUAL))
  if [ "$LOST" -gt 0 ]; then
    echo ""
    echo "  ❌ 永久丢失 $LOST 条！"
    echo "     丢失范围: lost:$((MAXKEY+1)) ~ lost:$WRITTEN"
    echo "     这些写入主库已返回 OK 给客户端，但从未到达从库"
    echo "     主库进程已死，这部分数据无法找回"
  else
    echo "  未观测到丢失"
  fi
  echo ""
  for p in 6402 6403; do
    if [ "$p" != "$NEWP" ]; then
      C=$(redis-cli -p $p --scan --pattern 'lost:*' 2>/dev/null | wc -l)
      echo "  从库 $p: $C 条"
    fi
  done
else
  echo "  故障转移未完成"
fi

echo ""
echo "=== 清理 ==="
for p in 26403 26402 26401; do redis-cli -p $p shutdown nosave 2>/dev/null; done
for p in 6403 6402 6401; do redis-cli -p $p shutdown nosave 2>/dev/null; done
sleep 1.5
rm -rf "$BASE"
echo "done"
