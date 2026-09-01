#!/usr/bin/env bash
# 课 6 知识点 1：全量与增量复制 —— 环境准备与基础验证
# 拓扑：1 主(6401) + 2 从(6402, 6403)
BASE=/tmp/redis-course-l06
rm -rf "$BASE"; mkdir -p "$BASE"/{6401,6402,6403}

echo "=== 版本与命令可用性 ==="
redis-server --version
which redis-sentinel redis-cli
echo ""

echo "=== 启动主库 6401 ==="
redis-server --port 6401 --daemonize yes --save '' --appendonly no \
  --dir "$BASE/6401" --logfile "$BASE/6401/redis.log" > /dev/null 2>&1
sleep 1
echo "  主库: $(redis-cli -p 6401 ping)"
redis-cli -p 6401 info replication | grep -E "role:|connected_slaves:|master_replid:|master_repl_offset:"
echo ""

echo "=== 启动从库 6402 并指向主库 ==="
redis-server --port 6402 --daemonize yes --save '' --appendonly no \
  --dir "$BASE/6402" --logfile "$BASE/6402/redis.log" > /dev/null 2>&1
sleep 1
# 先灌数据再挂从库，这样能观察全量复制
echo "  主库先写入 5000 个 key..."
seq 1 5000 | awk '{print "set k:"$1" v"$1}' | redis-cli -p 6401 --pipe > /dev/null 2>&1
echo "  主库 dbsize: $(redis-cli -p 6401 dbsize)"
echo "  主库 lastsave 前 repl_backlog: $(redis-cli -p 6401 info replication | grep -oP '(?<=^repl_backlog_active:)\d+')"

echo ""
echo "  执行 REPLICAOF..."
redis-cli -p 6402 replicaof 127.0.0.1 6401
sleep 2
echo "  从库 dbsize: $(redis-cli -p 6402 dbsize)"
echo "  从库 role: $(redis-cli -p 6402 info replication | grep -oP '(?<=^role:)\w+')"
echo ""

echo "=== 主库视角 ==="
redis-cli -p 6401 info replication | grep -E "role:|connected_slaves:|^slave0:"
echo ""

echo "=== 从库 6402 的复制状态关键字段 ==="
redis-cli -p 6402 info replication | grep -E "master_link_status:|master_repl_offset:|slave_repl_offset:|slave_read_repl_offset:|repl_backlog_active:"
echo ""

echo "=== 启动第二个从库 6403 ==="
redis-server --port 6403 --daemonize yes --save '' --appendonly no \
  --dir "$BASE/6403" --logfile "$BASE/6403/redis.log" > /dev/null 2>&1
sleep 1
redis-cli -p 6403 replicaof 127.0.0.1 6401
sleep 2
echo "  从库 6403 dbsize: $(redis-cli -p 6403 dbsize)"
echo "  主库 connected_slaves: $(redis-cli -p 6401 info replication | grep -oP '(?<=^connected_slaves:)\d+')"
echo ""

echo "=== 验证读写分离：从库默认只读 ==="
echo "  主库写入: $(redis-cli -p 6401 set rw:test 'from-master')"
sleep 0.5
echo "  从库读取: $(redis-cli -p 6402 get rw:test)"
echo "  从库写入尝试: $(redis-cli -p 6402 set rw:test 'from-slave' 2>&1)"
echo "  replica-read-only: $(redis-cli -p 6402 config get replica-read-only | tail -1)"
echo ""

echo "=== 复制延迟实测：主库写入到从库可见的时间 ==="
echo "  连续测 5 次（每次写后立即读从库）"
for i in 1 2 3 4 5; do
  redis-cli -p 6401 set "lag:$i" "v$i-$(date +%s%N)" > /dev/null
  R=$(redis-cli -p 6402 get "lag:$i")
  if [ -n "$R" ]; then echo "    第$i次: 立即可见 ($R)"; else echo "    第$i次: 不可见（异步复制有延迟）"; fi
done

echo ""
echo "=== 主库日志中的全量复制痕迹 ==="
grep -iE "replica|sync|backlog|rdb" "$BASE/6402/redis.log" 2>/dev/null | head -8

echo ""
echo "=== 清理 ==="
for p in 6403 6402 6401; do redis-cli -p $p shutdown nosave 2>/dev/null; done
sleep 1
rm -rf "$BASE"
echo "done"
