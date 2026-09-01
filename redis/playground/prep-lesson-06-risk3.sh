#!/usr/bin/env bash
# 课 6 知识点 3：异步复制风险的机制性证据（稳定版）
# 修正：启动后必须轮询等待 Redis 就绪（固定 sleep 不够，机器上 Redis 启动较慢）
BASE=/tmp/redis-course-l06-risk3
rm -rf "$BASE"; mkdir -p "$BASE"/{6401,6402,6403}

wait_ready() {
  local p=$1
  for i in $(seq 1 40); do
    if [ "$(redis-cli -p $p ping 2>/dev/null)" = "PONG" ]; then return 0; fi
    sleep 0.5
  done
  return 1
}

for p in 6401 6402 6403; do
  redis-server --port $p --daemonize yes --save '' --appendonly no \
    --dir "$BASE/$p" --logfile "$BASE/$p/redis.log" > /dev/null 2>&1
done
wait_ready 6401 || { echo "6401 启动失败"; exit 1; }
wait_ready 6402 || { echo "6402 启动失败"; exit 1; }
wait_ready 6403 || { echo "6403 启动失败"; exit 1; }
echo "  三个实例已就绪"

redis-cli -p 6401 config set repl-diskless-sync-delay 0 > /dev/null
redis-cli -p 6402 replicaof 127.0.0.1 6401 > /dev/null 2>&1
redis-cli -p 6403 replicaof 127.0.0.1 6401 > /dev/null 2>&1
sleep 4
echo "  主从就绪: connected_slaves=$(redis-cli -p 6401 info replication | grep -oP '(?<=^connected_slaves:)\d+')"
echo ""

echo "########## 1. 复制滞后直接度量 ##########"
echo "  指标: master_repl_offset - slave_repl_offset = 从库尚未收到的字节数"
echo ""
printf "%-10s %-18s %-18s %-16s\n" "采样" "master_offset" "slave_offset" "滞后(字节)"
printf "%-10s %-18s %-18s %-16s\n" "----------" "------------------" "------------------" "----------------"

python3 -c "
with open('/tmp/l06_gen.txt','w') as f:
    for i in range(1, 3001):
        val = 'v' * 500
        key = 'k:%d' % i
        f.write('*3\r\n\$3\r\nSET\r\n\$%d\r\n%s\r\n\$%d\r\n%s\r\n' % (len(key), key, len(val), val))
" 2>/dev/null

for i in $(seq 1 8); do
  redis-cli -p 6401 --pipe < /tmp/l06_gen.txt > /dev/null 2>&1
  MO=$(redis-cli -p 6401 info replication 2>/dev/null | grep -oP '(?<=^master_repl_offset:)\d+')
  SO=$(redis-cli -p 6402 info replication 2>/dev/null | grep -oP '(?<=^slave_repl_offset:)\d+')
  [ -z "$MO" ] && MO=0; [ -z "$SO" ] && SO=0
  printf "%-10s %-18s %-18s %-16s\n" "第${i}批" "$MO" "$SO" "$((MO-SO))"
  sleep 0.1
done
sleep 1
MO=$(redis-cli -p 6401 info replication | grep -oP '(?<=^master_repl_offset:)\d+')
SO=$(redis-cli -p 6402 info replication | grep -oP '(?<=^slave_repl_offset:)\d+')
echo "  停止写入后: 滞后 $((MO-SO)) 字节  <-- 最终归零，过程中始终有滞后窗口"

echo ""
echo "########## 2. min-replicas：主动拒绝不安全写入 ##########"
echo ""
echo "  默认值（默认关闭保护）:"
echo "    min-replicas-to-write = $(redis-cli -p 6401 config get min-replicas-to-write | tail -1)"
echo "    min-replicas-max-lag  = $(redis-cli -p 6401 config get min-replicas-max-lag | tail -1)"
echo ""
echo "  开启保护：至少 1 个从库且 lag <= 3 秒"
redis-cli -p 6401 config set min-replicas-to-write 1 > /dev/null
redis-cli -p 6401 config set min-replicas-max-lag 3 > /dev/null
echo "    -> to-write=$(redis-cli -p 6401 config get min-replicas-to-write | tail -1), max-lag=$(redis-cli -p 6401 config get min-replicas-max-lag | tail -1)"
echo ""
echo "  从库在线时写入: $(redis-cli -p 6401 set safe:test 1 2>&1)"
echo ""
echo "  停掉所有从库..."
redis-cli -p 6402 shutdown nosave 2>/dev/null
redis-cli -p 6403 shutdown nosave 2>/dev/null
sleep 2
echo "    connected_slaves=$(redis-cli -p 6401 info replication | grep -oP '(?<=^connected_slaves:)\d+')"
echo "  再次写入: $(redis-cli -p 6401 set unsafe:test 1 2>&1)"
echo "    ^ NOREPLICAS = Redis 主动拒绝，宁可不可用也不让数据冒险"
echo ""
echo "  代价：从库全挂时主库完全不可写（可用性换一致性）"

echo ""
echo "########## 3. WAIT 命令：让客户端等复制完成 ##########"
echo ""
redis-server --port 6402 --daemonize yes --save '' --appendonly no --dir "$BASE/6402" --logfile "$BASE/6402/redis.log" > /dev/null 2>&1
wait_ready 6402
redis-cli -p 6402 replicaof 127.0.0.1 6401 > /dev/null 2>&1
sleep 4
redis-cli -p 6401 config set min-replicas-to-write 0 > /dev/null
sleep 0.5
echo "  从库恢复: connected_slaves=$(redis-cli -p 6401 info replication | grep -oP '(?<=^connected_slaves:)\d+')"
echo ""
echo "  普通 SET:        $(redis-cli -p 6401 set w:1 v1 2>&1)  (立即返回，不等复制)"
redis-cli -p 6401 set w:2 v2 > /dev/null
echo "  SET + WAIT 1 0:  $(redis-cli -p 6401 wait 1 0) 个从库确认"
redis-cli -p 6401 set w:3 v3 > /dev/null
echo "  SET + WAIT 2 0:  $(redis-cli -p 6401 wait 2 0) 个从库确认（只有1个从库）"
echo ""
echo "  WAIT 的延迟代价（各 50 次）："
S=$(date +%s%N)
for i in $(seq 1 50); do redis-cli -p 6401 set "perf:$i" v > /dev/null; done
E=$(date +%s%N)
T1=$(awk "BEGIN{printf \"%.1f\", ($E-$S)/1000000}")
S=$(date +%s%N)
for i in $(seq 1 50); do redis-cli -p 6401 set "perf2:$i" v > /dev/null; redis-cli -p 6401 wait 1 1000 > /dev/null; done
E=$(date +%s%N)
T2=$(awk "BEGIN{printf \"%.1f\", ($E-$S)/1000000}")
echo "    50 次普通 SET:   ${T1} ms"
echo "    50 次 SET+WAIT:  ${T2} ms"
echo "    代价: $(awk -v a=$T2 -v b=$T1 'BEGIN{printf "%.1fx", a/b}')"

echo ""
echo "=== 清理 ==="
rm -f /tmp/l06_gen.txt
for p in 6403 6402 6401; do redis-cli -p $p shutdown nosave 2>/dev/null; done
sleep 1.5
rm -rf "$BASE"
echo "done"
