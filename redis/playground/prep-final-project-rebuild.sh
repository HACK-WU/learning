#!/bin/bash
# 结课实战项目 · 干净重建 7201
# 教训：Redis 8 配置文件里的 user 行对复杂权限串（含 -@dangerous 后跟多项）解析脆弱，
#       实战中用 redis-cli ACL SETUSER 动态创建更可靠，再用 ACL SAVE 落盘。
set -u
BASE=/tmp/redis-final
CFG=$BASE/7201/redis.conf

echo "===== 1. 写最小化配置文件（user 段全部移除，稍后动态创建） ====="
cat > $CFG <<'EOF'
port 7201
dir /tmp/redis-final/7201
maxmemory 512mb
maxmemory-policy allkeys-lru
appendonly yes
appendfsync everysec
save 900 1
latency-monitor-threshold 100
slowlog-log-slower-than 5000
slowlog-max-len 256
io-threads 4
EOF
echo "  配置已最小化（无 user 段）"

echo
echo "===== 2. 启动 7201 ====="
PID=$(ss -lntp 2>/dev/null | grep ':7201' | grep -oP 'pid=\K[0-9]+' | head -1)
if [ -n "$PID" ]; then kill -TERM $PID; sleep 2; fi
redis-server $CFG --daemonize yes --logfile $BASE/7201/redis.log
sleep 1.5
echo -n "  无认证 PING（此时应通，default 尚在）: "
redis-cli -p 7201 PING 2>&1 | head -1

echo
echo "===== 3. 动态创建角色账号 ====="
# 3.1 应用账号：业务 key 前缀 + 禁危险命令 + 加回运维只读命令
redis-cli -p 7201 ACL SETUSER appuser on '>AppPass123!' '~cache:*' '~inventory:*' '~rank:*' '~stats:*' \
  +@all -@dangerous -KEYS -FLUSHALL -FLUSHDB -DEBUG -SHUTDOWN -SCRIPT -MULTI -EXEC -WATCH -DISCARD \
  +INFO +CONFIG +CLIENT +MEMORY +SLOWLOG +LATENCY +OBJECT +SCAN +TTL +TYPE +DBSIZE 2>&1 | head -2

# 3.2 只读账号：+@read 默认含 KEYS，必须显式 -KEYS
redis-cli -p 7201 ACL SETUSER readonly on '>ReadOnly123!' '~cache:*' +@read -KEYS +INFO +CONFIG +MEMORY +SLOWLOG +LATENCY 2>&1 | head -2

# 3.3 复制账号：只需复制握手命令
redis-cli -p 7201 ACL SETUSER replicator on '>ReplPass123!' '~*' +psync +replconf +ping +info +@read 2>&1 | head -2

echo
echo "===== 4. 最后关闭 default（顺序很关键：先建号，再关门） ====="
redis-cli -p 7201 ACL SETUSER default off 2>&1 | head -1
echo "  default 已关闭"

echo
echo "===== 5. 用 ACL SAVE 持久化到 users.acl ====="
redis-cli -p 7201 --user appuser --pass 'AppPass123!' ACL SAVE 2>&1 | head -1

echo
echo "===== 6. 验证 ====="
R() { redis-cli -p 7201 --user appuser --pass 'AppPass123!' "$@" 2>/dev/null; }
echo -n "  无认证 PING（应 NOAUTH）: "; redis-cli -p 7201 PING 2>&1 | head -1
echo -n "  appuser PING            : "; R PING | head -1
echo -n "  INFO server             : "; R INFO server | grep -m1 redis_version
echo -n "  CONFIG GET 策略         : "; R CONFIG GET maxmemory-policy | tail -1
R SET cache:probe ok >/dev/null 2>&1
echo -n "  MEMORY USAGE            : "; R MEMORY USAGE cache:probe | head -1
echo -n "  SLOWLOG GET             : "; R SLOWLOG GET 1 | head -1
echo -n "  OBJECT FREQ             : "; R OBJECT FREQ cache:probe 2>&1 | head -1
echo -n "  LATENCY LATEST          : "; R LATENCY LATEST 2>&1 | head -1
echo -n "  SCAN                    : "; R SCAN 0 COUNT 3 | head -1

echo
echo "===== 7. 危险命令必须被拒 ====="
echo -n "  KEYS *        : "; R KEYS '*' 2>&1 | head -1
echo -n "  FLUSHALL      : "; R FLUSHALL 2>&1 | head -1
echo -n "  DEBUG SLEEP   : "; R DEBUG SLEEP 1 2>&1 | head -1
echo -n "  SHUTDOWN      : "; R SHUTDOWN 2>&1 | head -1
echo -n "  写 evil: 前缀 : "; R SET evil:hack 1 2>&1 | head -1
echo -n "  写 cache: 前缀: "; R SET cache:probe2 ok 2>&1 | head -1

echo
echo "===== 8. 恢复复制 ====="
redis-cli -p 7202 CONFIG SET masteruser replicator >/dev/null 2>&1
redis-cli -p 7202 CONFIG SET masterauth 'ReplPass123!' >/dev/null 2>&1

# 复制握手需要时间，固定 sleep 3 在慢机器上会误报 down。改为轮询等待，最多 20 秒。
LINK=down
for i in $(seq 1 20); do
  sleep 1
  LINK=$(redis-cli -p 7202 INFO replication 2>/dev/null | grep -oP 'master_link_status:\K.*' | tr -d '\r')
  if [ "$LINK" = "up" ]; then
    echo "  master_link_status:up （等待 ${i} 秒后就绪）"
    break
  fi
done

if [ "$LINK" != "up" ]; then
  echo "  ✗ 20 秒后复制仍未就绪（master_link_status:$LINK）"
  echo "    排查：从库日志 tail -5 /tmp/redis-final/7202/redis.log"
  echo "          主库是否 reachable：redis-cli -p 7201 --user replicator --pass 'ReplPass123!' --no-auth-warning PING"
else
  redis-cli -p 7202 INFO replication 2>/dev/null | grep -E 'master_repl_offset|slave_repl_offset' | head -2
fi
