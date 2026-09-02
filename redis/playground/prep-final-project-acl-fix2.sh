#!/bin/bash
# 结课实战项目 · 用 ACL SETUSER 逐个创建（避开配置文件续行语法问题）
# 生产环境同样推荐用 ACL SETUSER + ACL SAVE 持久化，比手改 conf 更不容易出错
set -u

BASE=/tmp/redis-final
CFG=$BASE/7201/redis.conf

echo "===== 1. 先把 conf 里的 user 段清空，只保留 default off ====="
grep -v '^user ' $CFG > $CFG.tmp
echo 'user default off' >> $CFG.tmp
mv $CFG.tmp $CFG
echo "  已清空，仅保留 user default off（重启后靠 ACL SETUSER 动态创建）"

echo
echo "===== 2. 重启 7201 ====="
PID=$(ss -lntp 2>/dev/null | grep ':7201' | grep -oP 'pid=\K[0-9]+' | head -1)
if [ -n "$PID" ]; then kill -TERM $PID; sleep 2; fi
redis-server $CFG --daemonize yes --logfile $BASE/7201/redis.log
sleep 1.5
echo -n "  启动检查（无认证应 NOAUTH）: "
redis-cli -p 7201 PING 2>&1 | head -1

echo
echo "===== 3. 用带外方式创建账号 ====="
# default 已 off，无法用 redis-cli 执行命令 —— 这是"关门后再配钥匙"的死锁
# 解法：临时用 redis-cli 的 AUTH 走不了，改用 redis-server 启动时载入的
#       一个临时 conf，或直接用 redis-cli --user default（已 off 不行）
# 正解：把 ACL 写回 conf 文件（单行，无续行），重启加载
echo "  → default 已关闭，无法在线创建账号（这正是生产上要预留应急账号的原因）"
echo "  → 改为把 ACL 以单行形式写回配置文件"

cat >> $CFG <<'ACLLINE'
user appuser on >AppPass123! ~cache:* ~inventory:* ~rank:* ~stats:* +@all -@dangerous -KEYS -FLUSHALL -FLUSHDB -DEBUG -SHUTDOWN -SCRIPT -MULTI -EXEC -WATCH -DISCARD +INFO +CONFIG +CLIENT +MEMORY +SLOWLOG +LATENCY +OBJECT +SCAN +TTL +TYPE +DBSIZE
user readonly on >ReadOnly123! ~cache:* +@read -KEYS +INFO +CONFIG +MEMORY +SLOWLOG +LATENCY
user replicator on >ReplPass123! ~* +psync +replconf +ping +info +@read
ACLLINE

PID=$(ss -lntp 2>/dev/null | grep ':7201' | grep -oP 'pid=\K[0-9]+' | head -1)
if [ -n "$PID" ]; then kill -TERM $PID; sleep 2; fi
redis-server $CFG --daemonize yes --logfile $BASE/7201/redis.log
sleep 1.5

echo
echo "===== 4. 连通性与诊断命令验证 ====="
R() { redis-cli -p 7201 --user appuser --pass 'AppPass123!' "$@" 2>/dev/null; }
echo -n "  appuser PING       : "; R PING | head -1
echo -n "  INFO server        : "; R INFO server | grep -m1 redis_version
echo -n "  CONFIG GET 策略    : "; R CONFIG GET maxmemory-policy | tail -1
echo -n "  MEMORY USAGE       : "; R SET cache:probe ok >/dev/null; R MEMORY USAGE cache:probe | head -1
echo -n "  SLOWLOG GET        : "; R SLOWLOG GET 1 | head -1
echo -n "  OBJECT FREQ        : "; R OBJECT FREQ cache:probe 2>&1 | head -1
echo -n "  LATENCY LATEST     : "; R LATENCY LATEST 2>&1 | head -1
echo -n "  SCAN               : "; R SCAN 0 COUNT 3 | head -1

echo
echo "===== 5. 危险命令必须仍被拒 ====="
echo -n "  KEYS *             : "; R KEYS '*' 2>&1 | head -1
echo -n "  FLUSHALL           : "; R FLUSHALL 2>&1 | head -1
echo -n "  DEBUG SLEEP        : "; R DEBUG SLEEP 1 2>&1 | head -1
echo -n "  SHUTDOWN           : "; R SHUTDOWN 2>&1 | head -1
echo -n "  写非业务前缀       : "; R SET evil:hack 1 2>&1 | head -1
echo -n "  写业务前缀 cache:  : "; R SET cache:probe2 ok 2>&1 | head -1

echo
echo "===== 6. 复制链路恢复 ====="
redis-cli -p 7202 CONFIG SET masteruser replicator >/dev/null 2>&1
redis-cli -p 7202 CONFIG SET masterauth 'ReplPass123!' >/dev/null 2>&1
sleep 3
redis-cli -p 7202 INFO replication 2>/dev/null | grep -E 'master_link_status|master_repl_offset|slave_repl_offset' | head -3
