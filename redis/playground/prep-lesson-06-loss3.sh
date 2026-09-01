#!/usr/bin/env bash
# 课 6 知识点 3：异步复制丢数据（SIGSTOP 暂停从库进程）
# DEBUG SLEEP 冻结的是命令处理，复制流仍在接收，所以测不出丢失
# 正确方法：SIGSTOP 暂停从库【进程】，内核不再调度它，无法接收任何数据
BASE=/tmp/redis-course-l06-loss3
rm -rf "$BASE"; mkdir -p "$BASE"/{6401,6402,6403,s1,s2,s3}

for p in 6401 6402 6403; do
  redis-server --port $p --daemonize yes --save '' --appendonly no \
    --dir "$BASE/$p" --logfile "$BASE/$p/redis.log" > /dev/null 2>&1
done
sleep 1
redis-cli -p 6401 config set repl-diskless-sync-delay 0 > /dev/null
redis-cli -p 6402 replicaof 127.0.0.1 6401 > /dev/null
redis-cli -p 6403 replicaof 127.0.0.1 6401 > /dev/null
sleep 3
seq 1 5000 | awk '{print "set base:"$1" v"$1}' | redis-cli -p 6401 --pipe > /dev/null 2>&1
sleep 1

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

echo "########## SIGSTOP 暂停从库进程 ##########"
S2PID=$(redis-cli -p 6402 info server | grep -oP '(?<=^process_id:)\d+')
S3PID=$(redis-cli -p 6403 info server | grep -oP '(?<=^process_id:)\d+')
echo "  从库 6402 pid=$S2PID, 6403 pid=$S3PID"
kill -STOP $S2PID $S3PID
echo "  已 SIGSTOP（进程被内核冻结，收不到任何数据）"
echo ""

# 主库写入
rm -f "$BASE/written.txt"
(
  for i in $(seq 1 50000); do
    R=$(redis-cli -p 6401 set "lost:$i" "v$i" 2>/dev/null)
    if [ "$R" = "OK" ]; then echo "$i" > "$BASE/written.txt"; else break; fi
  done
) &
WPID=$!

sleep 2
WRITTEN=$(cat "$BASE/written.txt" 2>/dev/null || echo 0)
MO=$(redis-cli -p 6401 info replication 2>/dev/null | grep -oP '(?<=^master_repl_offset:)\d+')
echo "  主库已确认写入: $WRITTEN 条, master_offset=$MO"
echo "  从库 offset (因 SIGSTOP 无法查询，必然落后)"
echo ""

MPID=$(redis-cli -p 6401 info server 2>/dev/null | grep -oP '(?<=^process_id:)\d+')
echo "  >>> kill -9 主库 (pid=$MPID)   [backlog 随之消失]"
kill -9 "$MPID" 2>/dev/null
kill $WPID 2>/dev/null
wait $WPID 2>/dev/null

WRITTEN=$(cat "$BASE/written.txt" 2>/dev/null || echo 0)
echo "  主库最终确认写入: $WRITTEN 条"

# 恢复从库
kill -CONT $S2PID $S3PID
echo "  已 SIGCONT 恢复从库"
sleep 1

echo ""
echo "=== 等待哨兵故障转移 ==="
NEW=""
for i in $(seq 1 25); do
  ADDR=$(redis-cli -p 26401 sentinel get-master-addr-by-name mymaster 2>/dev/null | tr '\n' ':' | sed 's/:$//')
  if [ -n "$ADDR" ] && [ "$ADDR" != "127.0.0.1:6401" ] && [ "$ADDR" != ":" ]; then NEW=$ADDR; break; fi
  sleep 1
done
NEWP=${NEW#*:}
echo "  新主库: ${NEW:-未转移}"
sleep 1.5

echo ""
echo "########## 结果 ##########"
if [ -n "$NEWP" ]; then
  ACTUAL=$(redis-cli -p $NEWP --scan --pattern 'lost:*' 2>/dev/null | wc -l)
  MAXKEY=$(redis-cli -p $NEWP --scan --pattern 'lost:*' 2>/dev/null | sed 's/lost://' | sort -n | tail -1)
  echo "  主库确认写入:    $WRITTEN 条 (lost:1 ~ lost:$WRITTEN)"
  echo "  新主库实际拥有:  $ACTUAL 条 (最大 lost:${MAXKEY:-0})"
  LOST=$((WRITTEN - ACTUAL))
  echo ""
  if [ "$LOST" -gt 0 ]; then
    echo "  ❌ 永久丢失 $LOST 条 (lost:$((MAXKEY+1)) ~ lost:$WRITTEN)"
    echo "     主库已对这些写入返回 OK，但数据从未到达从库"
    echo "     主库进程死亡后 backlog 消失，这部分数据再也找不回"
  else
    echo "  未观测到丢失"
  fi
  echo ""
  for p in 6402 6403; do
    [ "$p" != "$NEWP" ] && echo "  从库 $p: $(redis-cli -p $p --scan --pattern 'lost:*' 2>/dev/null | wc -l) 条"
  done
else
  echo "  未转移"
fi

echo ""
echo "=== 清理 ==="
for p in 26403 26402 26401; do redis-cli -p $p shutdown nosave 2>/dev/null; done
for p in 6403 6402 6401; do redis-cli -p $p shutdown nosave 2>/dev/null; done
sleep 1.5
rm -rf "$BASE"
echo "done"
