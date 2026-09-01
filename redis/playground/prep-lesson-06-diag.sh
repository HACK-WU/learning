#!/usr/bin/env bash
# 诊断：从库为什么 dbsize 一直是 0
BASE=/tmp/redis-course-l06-diag
rm -rf "$BASE"; mkdir -p "$BASE"/{m,s}
M=6401; S=6402

redis-server --port $M --daemonize yes --save '' --appendonly no --dir "$BASE/m" --logfile "$BASE/m.log" > /dev/null 2>&1
redis-server --port $S --daemonize yes --save '' --appendonly no --dir "$BASE/s" --logfile "$BASE/s.log" > /dev/null 2>&1
sleep 1

echo "=== 1. 测试 awk 生成的命令是否正确 ==="
seq 1 3 | awk -v s=10 '{printf "set gap:%s %s\n", $1, sprintf("%*s", s, "")}' | head -3 | cat -A | head -3
echo ""

echo "=== 2. 主库写入测试 ==="
redis-cli -p $M set tk 1 > /dev/null
echo "  主库 dbsize: $(redis-cli -p $M dbsize)"
seq 1 1000 | awk '{print "set k:"$1" v"$1}' | redis-cli -p $M --pipe 2>&1 | tail -2
echo "  主库 dbsize: $(redis-cli -p $M dbsize)"
echo ""

echo "=== 3. 带 --pipe 的 awk printf 写入测试 ==="
seq 1 1000 | awk -v s=100 '{printf "set gap:%s %s\n", $1, sprintf("%*s", s, "")}' | redis-cli -p $M --pipe 2>&1 | tail -2
echo "  主库 dbsize: $(redis-cli -p $M dbsize)"
echo ""

echo "=== 4. 建立复制，完整等待 ==="
redis-cli -p $S replicaof 127.0.0.1 $M
echo "  REPLICAOF 返回后立刻查: dbsize=$(redis-cli -p $S dbsize) link=$(redis-cli -p $S info replication | grep -oP '(?<=^master_link_status:)\w+')"
# 等待更久，并检查
for i in $(seq 1 20); do
  L=$(redis-cli -p $S info replication | grep -oP '(?<=^master_link_status:)\w+')
  D=$(redis-cli -p $S dbsize)
  echo "  t=$(awk "BEGIN{printf \"%.1f\", $i*0.5}")s link=$L dbsize=$D"
  [ "$L" = "up" ] && [ "$D" -gt 0 ] && break
  sleep 0.5
done

echo ""
echo "=== 5. 从库完整日志 ==="
cat "$BASE/s.log" | tail -15 | cut -c1-150

echo ""
echo "=== 6. 主库完整日志 ==="
cat "$BASE/m.log" | tail -10 | cut -c1-150

echo ""
echo "=== 清理 ==="
redis-cli -p $S shutdown nosave 2>/dev/null
redis-cli -p $M shutdown nosave 2>/dev/null
sleep 1
rm -rf "$BASE"
echo "done"
