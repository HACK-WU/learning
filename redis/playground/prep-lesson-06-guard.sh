#!/usr/bin/env bash
# 课 6 知识点 3（精简）：异步复制的两个官方缓解手段
# 去掉大批量 --pipe 写入（疑似导致实例不稳定），只测配置与命令行为
BASE=/tmp/redis-course-l06-guard
rm -rf "$BASE"; mkdir -p "$BASE"/{6401,6402}

wait_ready() {
  for i in $(seq 1 40); do
    [ "$(redis-cli -p $1 ping 2>/dev/null)" = "PONG" ] && return 0
    sleep 0.5
  done
  return 1
}

echo "########## 1. min-replicas-to-write：主库主动拒绝不安全写入 ##########"
echo ""

for p in 6401 6402; do
  redis-server --port $p --daemonize yes --save '' --appendonly no \
    --dir "$BASE/$p" --logfile "$BASE/$p/redis.log" > /dev/null 2>&1
done
wait_ready 6401 || { echo "主库启动失败"; exit 1; }
wait_ready 6402 || { echo "从库启动失败"; exit 1; }
echo "  实例就绪"

redis-cli -p 6401 config set repl-diskless-sync-delay 0 > /dev/null
redis-cli -p 6402 replicaof 127.0.0.1 6401 > /dev/null 2>&1
sleep 4
echo "  connected_slaves=$(redis-cli -p 6401 info replication | grep -oP '(?<=^connected_slaves:)\d+')"
echo ""

echo "  --- 默认配置（保护关闭）---"
echo "    min-replicas-to-write = $(redis-cli -p 6401 config get min-replicas-to-write | tail -1)"
echo "    min-replicas-max-lag  = $(redis-cli -p 6401 config get min-replicas-max-lag | tail -1)"
echo "    含义：0 = 不管从库死活，主库照常接受写入（丢数据风险最大）"
echo ""

echo "  --- 开启保护：至少 1 个从库、lag ≤ 3 秒 ---"
redis-cli -p 6401 config set min-replicas-to-write 1 > /dev/null
redis-cli -p 6401 config set min-replicas-max-lag 3 > /dev/null
echo "    to-write = $(redis-cli -p 6401 config get min-replicas-to-write | tail -1)"
echo "    max-lag  = $(redis-cli -p 6401 config get min-replicas-max-lag | tail -1)"
echo ""

echo "  从库在线 -> 写入: $(redis-cli -p 6401 set safe:test 1 2>&1)"
echo ""

echo "  停掉从库..."
redis-cli -p 6402 shutdown nosave 2>/dev/null
sleep 2
echo "    connected_slaves = $(redis-cli -p 6401 info replication | grep -oP '(?<=^connected_slaves:)\d+')"
echo "  再次写入 -> $(redis-cli -p 6401 set unsafe:test 1 2>&1)"
echo ""
echo "  ↑ NOREPLICAS = Redis 主动拒绝写入"
echo "    宁可让服务不可写，也不让写入冒险丢失"
echo "    代价：从库全挂时整个 Redis 不可写（可用性换一致性）"
echo ""

echo "########## 2. WAIT 命令：客户端显式等待复制完成 ##########"
echo ""

redis-server --port 6402 --daemonize yes --save '' --appendonly no \
  --dir "$BASE/6402" --logfile "$BASE/6402/redis.log" > /dev/null 2>&1
wait_ready 6402
redis-cli -p 6402 replicaof 127.0.0.1 6401 > /dev/null 2>&1
sleep 4
redis-cli -p 6401 config set min-replicas-to-write 0 > /dev/null
sleep 0.5
echo "  从库恢复: connected_slaves=$(redis-cli -p 6401 info replication | grep -oP '(?<=^connected_slaves:)\d+')"
echo ""

echo "  WAIT <numreplicas> <timeout>：阻塞直到 N 个从库确认收到"
echo ""
echo "  普通 SET:       $(redis-cli -p 6401 set w:1 v1 2>&1)   <- 命令返回即视为完成"
redis-cli -p 6401 set w:2 v2 > /dev/null
echo "  SET 后 WAIT 1 0: $(redis-cli -p 6401 wait 1 0) 个从库确认"
redis-cli -p 6401 set w:3 v3 > /dev/null
echo "  SET 后 WAIT 2 0: $(redis-cli -p 6401 wait 2 0) 个从库确认（只有 1 个从库，超时返回实际数）"
echo ""

echo "  --- WAIT 的延迟代价（各 50 次）---"
S=$(date +%s%N)
for i in $(seq 1 50); do redis-cli -p 6401 set "perf:$i" v > /dev/null; done
E=$(date +%s%N)
T1=$(awk "BEGIN{printf \"%.1f\", ($E-$S)/1000000}")
S=$(date +%s%N)
for i in $(seq 1 50); do redis-cli -p 6401 set "perf2:$i" v > /dev/null; redis-cli -p 6401 wait 1 1000 > /dev/null; done
E=$(date +%s%N)
T2=$(awk "BEGIN{printf \"%.1f\", ($E-$S)/1000000}")
echo "    50 次普通 SET:  ${T1} ms"
echo "    50 次 SET+WAIT: ${T2} ms"
echo "    代价: $(awk -v a=$T2 -v b=$T1 'BEGIN{printf "%.1fx", a/b}')"
echo ""

echo "########## 3. 两个手段的对比 ##########"
echo ""
printf "%-24s %-30s %-30s\n" "维度" "min-replicas-to-write" "WAIT 命令"
printf "%-24s %-30s %-30s\n" "------------------------" "------------------------------" "------------------------------"
printf "%-24s %-30s %-30s\n" "作用层" "服务端（主库配置）" "客户端（每次调用）"
printf "%-24s %-30s %-30s\n" "触发方式" "从库不足时拒绝写入" "阻塞等待 N 个从库确认"
printf "%-24s %-30s %-30s\n" "粒度" "全局，一刀切" "可精确控制每条命令"
printf "%-24s %-30s %-30s\n" "失败表现" "返回 NOREPLICAS 错误" "超时返回已确认数量"
printf "%-24s %-30s %-30s\n" "代价" "从库全挂时完全不可写" "每条命令增加一次往返延迟"

echo ""
echo "=== 清理 ==="
for p in 6402 6401; do redis-cli -p $p shutdown nosave 2>/dev/null; done
sleep 1.5
rm -rf "$BASE"
echo "done"
