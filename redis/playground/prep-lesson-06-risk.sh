#!/usr/bin/env bash
# 课 6 知识点 3：丢数据窗口的机制性证据（不依赖难以捕捉的丢包瞬间）
# 前面 4 轮尝试的结论：本机回环网络下，数据一旦 write() 到 socket 内核缓冲就几乎不会丢
# 真正的丢失窗口 = 主库「已写内存」到「已 write 到 socket」之间的时间，本机是亚毫秒级
# 因此改用【机制性证据】+ 【配置验证】两条路径来证明异步复制的风险
BASE=/tmp/redis-course-l06-risk
rm -rf "$BASE"; mkdir -p "$BASE"/{6401,6402,6403}

echo "########## 1. 复制滞后（lag）的直接度量 ##########"
echo "  指标：master_repl_offset - slave_repl_offset = 尚未复制到从库的字节数"
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

gen() {
python3 -c "
n=$1
for i in range(1, n+1):
    val = 'v' * 500
    print('*3\r\n\$3\r\nSET\r\n\$%d\r\nk:%d\r\n\$%d\r\n%s\r\n' % (len('k:%d'%i), i, len(val), val))
"
}

echo "  持续写入并高频采样 offset 差值："
echo ""
printf "%-12s %-18s %-18s %-18s\n" "采样点" "master_offset" "slave_offset" "滞后字节"
printf "%-12s %-18s %-18s %-18s\n" "------------" "------------------" "------------------" "------------------"

# 后台持续写入
( for b in $(seq 1 30); do gen 2000 | redis-cli -p 6401 --pipe > /dev/null 2>&1; done ) &
WP=$!

for i in $(seq 1 12); do
  MO=$(redis-cli -p 6401 info replication 2>/dev/null | grep -oP '(?<=^master_repl_offset:)\d+')
  SO=$(redis-cli -p 6402 info replication 2>/dev/null | grep -oP '(?<=^slave_repl_offset:)\d+')
  [ -z "$MO" ] && MO=0; [ -z "$SO" ] && SO=0
  printf "%-12s %-18s %-18s %-18s\n" "第${i}次" "$MO" "$SO" "$((MO-SO))"
  sleep 0.3
done
wait $WP 2>/dev/null
sleep 1
MO=$(redis-cli -p 6401 info replication | grep -oP '(?<=^master_repl_offset:)\d+')
SO=$(redis-cli -p 6402 info replication | grep -oP '(?<=^slave_repl_offset:)\d+')
echo "  写入停止后: 滞后 $((MO-SO)) 字节  <-- 最终会归零，但过程中始终有滞后"

echo ""
echo "########## 2. min-replicas 配置：主动拒绝「不安全」的写入 ##########"
echo "  这是 Redis 官方提供的异步复制风险缓解手段"
echo ""
echo "  默认值: min-replicas-to-write=$(redis-cli -p 6401 config get min-replicas-to-write | tail -1), min-replicas-max-lag=$(redis-cli -p 6401 config get min-replicas-max-lag | tail -1)"
echo "  （默认 0 = 关闭，即主库不管从库死活，照常接受写入）"
echo ""

echo "  配置为：至少 1 个从库，且 lag <= 3 秒"
redis-cli -p 6401 config set min-replicas-to-write 1 > /dev/null
redis-cli -p 6401 config set min-replicas-max-lag 3 > /dev/null
echo "  设置后: to-write=$(redis-cli -p 6401 config get min-replicas-to-write | tail -1), max-lag=$(redis-cli -p 6401 config get min-replicas-max-lag | tail -1)"

echo ""
echo "  --- 从库都在线时，主库可写 ---"
echo "  写入测试: $(redis-cli -p 6401 set safe:test 1 2>&1)"

echo ""
echo "  --- 停掉所有从库，主库应拒绝写入 ---"
redis-cli -p 6402 shutdown nosave 2>/dev/null
redis-cli -p 6403 shutdown nosave 2>/dev/null
sleep 2
echo "  主库 connected_slaves: $(redis-cli -p 6401 info replication | grep -oP '(?<=^connected_slaves:)\d+')"
echo "  写入测试: $(redis-cli -p 6401 set unsafe:test 1 2>&1)"
echo "  ^ NOREPLICAS 错误 = Redis 主动拒绝，保护数据不丢"

echo ""
echo "  --- 代价：从库全挂时整个 Redis 不可写 ---"
echo "  这是「可用性」换「一致性」的取舍"

echo ""
echo "########## 3. WAIT 命令：让客户端同步等待复制完成 ##########"
echo "  WAIT <numreplicas> <timeout> 阻塞直到 N 个从库确认收到"
echo ""
# 重启一个从库
redis-server --port 6402 --daemonize yes --save '' --appendonly no --dir "$BASE/6402" --logfile "$BASE/6402/redis.log" > /dev/null 2>&1
sleep 1
redis-cli -p 6402 replicaof 127.0.0.1 6401 > /dev/null
sleep 3
redis-cli -p 6401 config set min-replicas-to-write 0 > /dev/null
sleep 0.5
echo "  从库已恢复，connected_slaves=$(redis-cli -p 6401 info replication | grep -oP '(?<=^connected_slaves:)\d+')"
echo ""
echo "  普通 SET:     $(redis-cli -p 6401 set w:1 v1 2>&1)  (立即返回，不等待复制)"
echo "  SET + WAIT 1 0: $(redis-cli -p 6401 set w:2 v2 > /dev/null; redis-cli -p 6401 wait 1 0) 个从库确认"
echo "  SET + WAIT 2 0: $(redis-cli -p 6401 set w:3 v3 > /dev/null; redis-cli -p 6401 wait 2 0) 个从库确认（只有1个从库，超时返回1）"
echo ""
echo "  测 WAIT 的延迟代价："
S=$(date +%s%N)
for i in $(seq 1 100); do redis-cli -p 6401 set "perf:$i" v > /dev/null; done
E=$(date +%s%N)
echo "    100 次普通 SET:    $(awk "BEGIN{printf \"%.1f ms\", ($E-$S)/1000000}")"
S=$(date +%s%N)
for i in $(seq 1 100); do redis-cli -p 6401 set "perf2:$i" v > /dev/null; redis-cli -p 6401 wait 1 1000 > /dev/null; done
E=$(date +%s%N)
echo "    100 次 SET+WAIT:   $(awk "BEGIN{printf \"%.1f ms\", ($E-$S)/1000000}")"

echo ""
echo "=== 清理 ==="
for p in 6403 6402 6401; do redis-cli -p $p shutdown nosave 2>/dev/null; done
sleep 1
rm -rf "$BASE"
echo "done"
