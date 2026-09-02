#!/bin/bash
# 结课实战项目 · 启动实验实例
# 端口规划：7201=主(生产基线) 7202=从(复制) 7203=反例(默认配置)
# ⚠️ 安全纪律：本脚本不使用 SHUTDOWN 等危险命令；清理见 cleanup 脚本
set -u

BASE=/tmp/redis-final
mkdir -p $BASE/{7201,7202,7203}

# ---------- 7201：主实例（生产基线配置） ----------
cat > $BASE/7201/redis.conf <<'EOF'
port 7201
dir /tmp/redis-final/7201
# 内存与淘汰（阶段4·课8）
maxmemory 512mb
maxmemory-policy allkeys-lru
# 持久化（阶段3·课5）：混合持久化
appendonly yes
appendfsync everysec
save 900 1
# 诊断基线（阶段4·课9）
latency-monitor-threshold 100
slowlog-log-slower-than 5000
slowlog-max-len 256
# 性能（阶段4·课9）
io-threads 4
# 安全基线（阶段4·课9）：关闭默认用户的全部权限，另建最小权限账号
user default off
user appuser on >AppPass123! ~cache:* ~inventory:* ~rank:* ~stats:* +@all -@dangerous -KEYS -FLUSHALL -FLUSHDB -DEBUG -CONFIG -SHUTDOWN
user readonly on >ReadOnly123! ~cache:* +@read -KEYS
EOF

# ---------- 7202：从实例（演示复制延迟） ----------
cat > $BASE/7202/redis.conf <<'EOF'
port 7202
dir /tmp/redis-final/7202
maxmemory 512mb
maxmemory-policy allkeys-lru
appendonly no
save ""
latency-monitor-threshold 100
slowlog-log-slower-than 5000
EOF

# ---------- 7203：反例实例（出厂默认配置，故意不加固） ----------
cat > $BASE/7203/redis.conf <<'EOF'
port 7203
dir /tmp/redis-final/7203
save ""
appendonly no
EOF

start() {
  local port=$1
  if redis-cli -p $port PING >/dev/null 2>&1; then
    echo "  端口 $port 已在运行，跳过"
    return
  fi
  redis-server /tmp/redis-final/$port/redis.conf --daemonize yes --logfile /tmp/redis-final/$port/redis.log
  sleep 1
  if redis-cli -p $port PING >/dev/null 2>&1; then
    echo "  端口 $port 启动成功"
  else
    echo "  端口 $port 启动失败，日志："
    tail -5 /tmp/redis-final/$port/redis.log
  fi
}

echo "===== 启动 7201 主实例 ====="
start 7201
echo "===== 启动 7202 从实例 ====="
start 7202
echo "===== 启动 7203 反例实例 ====="
start 7203

echo
echo "===== 建立主从复制 7202 -> 7201 ====="
redis-cli -p 7202 REPLICAOF 127.0.0.1 7201 2>&1 | head -1
sleep 2
redis-cli -p 7202 INFO replication 2>/dev/null | grep -E 'role|master_link_status' || echo "(复制未建立)"

echo
echo "===== 连通性验证 ====="
for p in 7201 7202 7203; do
  echo -n "  $p: "
  redis-cli -p $p PING 2>&1 | head -1
done
