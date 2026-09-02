#!/bin/bash
# 结课实战项目 · 修正 ACL：最小权限 ≠ 一刀切禁用 dangerous
# 教训：-@dangerous 会把 INFO / CONFIG GET / CLIENT 等运维只读命令一起禁掉，
#       结果是可观测能力归零，出问题时什么都查不了。
#       正确做法：先 -@dangerous 收紧，再把运维必需的命令显式加回来。
set -u

BASE=/tmp/redis-final
CFG=$BASE/7201/redis.conf

echo "===== 1. 备份并重写 ACL 段落 ====="
# 丢弃旧的 user 配置行，写入修正后的版本
grep -v '^user ' $CFG > $CFG.tmp

cat >> $CFG.tmp <<'EOF'

# ============================================================
# ACL 安全基线（阶段4·课9）
# 设计原则：默认拒绝 + 按角色授权 + 运维必需命令显式加回
# ============================================================

# 1) 关闭默认用户——出厂默认是 nopass + @all，等于裸奔
user default off

# 2) 应用账号：只能碰业务 key 前缀，禁用危险命令，
#    但把 INFO / CONFIG GET / CLIENT / MEMORY / SLOWLOG / LATENCY / OBJECT
#    这些「运维只读」命令显式加回，否则诊断层完全不可用（本轮实测踩坑）
user appuser on >AppPass123! ~cache:* ~inventory:* ~rank:* ~stats:* \
  +@all -@dangerous -KEYS -FLUSHALL -FLUSHDB -DEBUG -SHUTDOWN -SCRIPT -MULTI -EXEC -WATCH -DISCARD \
  +INFO +CONFIG +CLIENT +MEMORY +SLOWLOG +LATENCY +OBJECT +SCAN +TTL +TYPE +DBSIZE

# 3) 只读账号：给运营/报表用，只能读 cache 前缀
#    注意 +@read 默认包含 KEYS，必须显式 -KEYS（课9实测高频坑）
user readonly on >ReadOnly123! ~cache:* +@read -KEYS +INFO +CONFIG +MEMORY +SLOWLOG +LATENCY

# 4) 复制专用账号：只需要复制握手相关的少量命令，不能写数据
#    本轮实测踩坑：关掉 default 后若不建此账号，从库会一直 NOPERM 连不上
user replicator on >ReplPass123! ~* +psync +replconf +ping +info +@read
EOF

mv $CFG.tmp $CFG
echo "  已重写 ACL 配置"

echo
echo "===== 2. 重启 7201 加载新 ACL ====="
PID=$(ss -lntp 2>/dev/null | grep ':7201' | grep -oP 'pid=\K[0-9]+' | head -1)
if [ -n "$PID" ]; then
  kill -TERM $PID; sleep 2
fi
redis-server $CFG --daemonize yes --logfile $BASE/7201/redis.log
sleep 1.5
echo -n "  重启后 appuser PING: "
redis-cli -p 7201 --user appuser --pass 'AppPass123!' PING 2>/dev/null | head -1

echo
echo "===== 3. 验证诊断命令已恢复 ====="
R() { redis-cli -p 7201 --user appuser --pass 'AppPass123!' "$@" 2>/dev/null; }
echo -n "  INFO server        : "; R INFO server | grep -m1 redis_version
echo -n "  CONFIG GET 淘汰策略: "; R CONFIG GET maxmemory-policy | tail -1
echo -n "  MEMORY USAGE       : "; R MEMORY USAGE cache:probe 2>/dev/null | head -1
echo -n "  SLOWLOG GET        : "; R SLOWLOG GET 1 | head -1
echo -n "  OBJECT FREQ        : "; R OBJECT FREQ cache:probe 2>&1 | head -1
echo -n "  LATENCY LATEST     : "; R LATENCY LATEST 2>&1 | head -1

echo
echo "===== 4. 验证危险命令仍然被拒 ====="
echo -n "  KEYS *             : "; R KEYS '*' 2>&1 | head -1
echo -n "  FLUSHALL           : "; R FLUSHALL 2>&1 | head -1
echo -n "  DEBUG SLEEP        : "; R DEBUG SLEEP 1 2>&1 | head -1
echo -n "  SHUTDOWN           : "; R SHUTDOWN 2>&1 | head -1
echo -n "  写非业务前缀 key   : "; R SET evil:hack 1 2>&1 | head -1
echo -n "  写业务前缀 key     : "; R SET cache:probe ok 2>&1 | head -1

echo
echo "===== 5. 复制链路是否仍健康 ====="
sleep 2
redis-cli -p 7202 INFO replication 2>/dev/null | grep -E 'master_link_status|master_repl_offset' | head -2
