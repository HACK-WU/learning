#!/usr/bin/env bash
# 课 8 备课前置环境检查
set -u
echo "===== 系统 ====="
lsb_release -d 2>/dev/null | sed 's/Description://' || cat /etc/os-release | head -2
echo "===== Redis ====="
redis-server --version
redis-cli --version
echo "===== Redis 服务状态 ====="
redis-cli -p 6379 ping 2>&1 | head -3
echo "===== 模块（是否内置 Bloom）====="
redis-cli -p 6379 MODULE LIST 2>&1 | head -20
echo "----- BF 命令探测 -----"
redis-cli -p 6379 BF.RESERVE probe:bf 0.01 1000 2>&1 | head -3
redis-cli -p 6379 BF.ADD probe:bf hello 2>&1 | head -3
redis-cli -p 6379 BF.EXISTS probe:bf hello 2>&1 | head -3
redis-cli -p 6379 BF.EXISTS probe:bf nope_xyz 2>&1 | head -3
redis-cli -p 6379 DEL probe:bf 2>&1 | head -2
echo "===== 关键配置 ====="
redis-cli -p 6379 CONFIG GET maxmemory
redis-cli -p 6379 CONFIG GET maxmemory-policy
redis-cli -p 6379 CONFIG GET maxmemory-samples
redis-cli -p 6379 CONFIG GET maxmemory-eviction-tenacity
redis-cli -p 6379 CONFIG GET hz
redis-cli -p 6379 CONFIG GET activedefrag
echo "===== 数据库规模（确认 6379 是用户实例，勿动）====="
redis-cli -p 6379 DBSIZE
redis-cli -p 6379 INFO keyspace | head -10
echo "===== 端口占用 ====="
ss -lntp 2>/dev/null | grep -E ':(6379|7001|7002|7003|7004|7005|7006|7007|7101|7102)' || echo "无相关端口占用"
echo "===== Python ====="
python3 --version
python3 -c "import redis; print('redis-py', redis.__version__)" 2>&1 | head -3
echo "===== 临时目录 ====="
ls -d /tmp/redis-l07 2>/dev/null || echo "/tmp/redis-l07 不存在（课7已清理）"
echo "===== playground ====="
ls /mnt/d/projects/learning/redis/playground/ 2>&1 | head -40
