#!/bin/bash
# 结课实战项目 · 环境预检（只读探测，不执行任何危险命令）
set -u

echo "===== 1. WSL 与 Redis 版本 ====="
lsb_release -d 2>/dev/null
redis-server --version
redis-cli --version
python3 --version

echo
echo "===== 2. 当前监听的 Redis 实例 ====="
ss -lntp 2>/dev/null | grep -E 'redis|:(6379|710[0-9])' || echo "(未发现监听中的 Redis 实例)"

echo
echo "===== 3. 6379 连通性（只读 PING + INFO） ====="
redis-cli -p 6379 PING 2>&1 | head -2
redis-cli -p 6379 INFO server 2>/dev/null | grep -E 'redis_version|uptime_in_seconds|executable' || echo "(6379 未响应)"

echo
echo "===== 4. 7101-7106 是否残留上一课实例 ====="
for p in 7101 7102 7103 7104 7105 7106; do
  if redis-cli -p $p PING >/dev/null 2>&1; then
    echo "  端口 $p: 存活"
  else
    echo "  端口 $p: 空闲"
  fi
done

echo
echo "===== 5. 磁盘与内存余量（决定压测规模） ====="
free -m | head -2
df -h /tmp | tail -1
nproc

echo
echo "===== 6. 确认 6379 数据为空（避免误用用户数据） ====="
redis-cli -p 6379 DBSIZE 2>&1 | head -1
