#!/bin/bash
# 诊断 6379 现状（只读，绝不执行破坏性命令）
echo "=== 1. 运行中的 redis 进程 ==="
ps aux | grep -E "[r]edis-server" | head

echo ""
echo "=== 2. 6379 是否可达 ==="
redis-cli -p 6379 ping 2>&1 | head -2

echo ""
echo "=== 3. systemd 单元 ==="
systemctl list-unit-files 2>/dev/null | grep -iE "redis|valkey" || echo "(none)"
echo "--- 状态 ---"
systemctl is-active redis-server 2>&1
systemctl is-active redis 2>&1

echo ""
echo "=== 4. 配置文件 ==="
ls -la /etc/redis/redis.conf 2>&1
grep -nE "^(bind|port|daemonize|dir|logfile|supervised|appendonly|save|dbfilename|requirepass|maxmemory)" /etc/redis/redis.conf 2>/dev/null | head -30

echo ""
echo "=== 5. 最近日志 ==="
tail -30 /var/log/redis/redis-server.log 2>/dev/null || echo "(no log at that path)"

echo ""
echo "=== 6. dump.rdb / appendonly 位置 ==="
grep -nE "^dir" /etc/redis/redis.conf 2>/dev/null
ls -la /var/lib/redis/ 2>/dev/null | head -20

echo ""
echo "=== 7. redis-stack 进程还在吗 ==="
ps aux | grep "[r]edis-stack" | head
ls -la /opt/redis-stack/bin/ 2>/dev/null | head
