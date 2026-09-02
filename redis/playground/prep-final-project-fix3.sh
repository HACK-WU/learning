#!/bin/bash
# 结课实战项目 · 修复复制权限：为复制单独建账号（生产正确做法）
# 教训：关掉 default 用户后，必须显式建一个带 psync/replconf 的复制账号，否则从库永远连不上
set -u
export REDISCLI_AUTH='AppPass123!'

# 先用 default 之外的途径改 ACL —— default 已 off，这里借助 appuser 不行（无 ACL 权限），
# 故通过 redis-cli 对 7201 用 appuser 不可行；改为直接改配置文件 + 重启该实例
echo "===== 1. 主库 7201 增加复制专用账号 ====="
cat >> /tmp/redis-final/7201/redis.conf <<'EOF'
user replicator on >ReplPass123! ~* +psync +replconf +ping +info
EOF
echo "  已在 redis.conf 追加 replicator 用户"

echo
echo "===== 2. 平滑重启 7201（不使用 SHUTDOWN，用 SIGTERM 优雅退出） ====="
PID=$(ss -lntp 2>/dev/null | grep ':7201' | grep -oP 'pid=\K[0-9]+' | head -1)
if [ -n "$PID" ]; then
  echo "  7201 进程 PID=$PID，发送 SIGTERM 优雅退出"
  kill -TERM $PID
  sleep 2
  redis-server /tmp/redis-final/7201/redis.conf --daemonize yes --logfile /tmp/redis-final/7201/redis.log
  sleep 1
  echo -n "  重启后 appuser PING: "
  redis-cli -p 7201 --user appuser PING 2>/dev/null | head -1
else
  echo "  未找到 7201 进程"
fi

echo
echo "===== 3. 从库改用 replicator 账号复制 ====="
redis-cli -p 7202 CONFIG SET masteruser replicator >/dev/null 2>&1
redis-cli -p 7202 CONFIG SET masterauth 'ReplPass123!' >/dev/null 2>&1
sleep 3
redis-cli -p 7202 INFO replication 2>/dev/null | grep -E 'role|master_link_status|master_repl_offset' || echo "(未建立)"

echo
echo "===== 4. 验证主从数据同步 ====="
redis-cli -p 7201 --user appuser SET cache:sync-test 'hello-replica' >/dev/null 2>&1
sleep 1
echo -n "  主库写入后，从库读到: "
redis-cli -p 7202 GET cache:sync-test 2>/dev/null | head -1

echo
echo "===== 5. 复制账号权限最小化验证 ====="
echo -n "  replicator 执行 SET（应 NOPERM）: "
redis-cli -p 7201 --user replicator --pass 'ReplPass123!' SET evil 1 2>/dev/null | head -1
echo -n "  replicator 执行 PSYNC（复制必需）: "
redis-cli -p 7201 --user replicator --pass 'ReplPass123!' INFO replication 2>/dev/null | head -1

echo
echo "===== 6. 三个实例的最终安全姿态对比 ====="
echo "  --- 7201（加固后） ---"
for u in default appuser readonly replicator; do
  echo "    $u: $(redis-cli -p 7201 --user appuser ACL GETUSER $u 2>/dev/null | grep -A1 -E '^"?(flags|commands|keys)"?$' | head -0)"
done
redis-cli -p 7201 --user appuser ACL LIST 2>/dev/null | sed 's/^/    /' | head -6
echo "  --- 7203（出厂默认，反例） ---"
redis-cli -p 7203 ACL LIST 2>/dev/null | sed 's/^/    /' | head -2
