#!/usr/bin/env bash
set -u
echo "===== 6379 实例是如何加载模块的？====="
redis-cli -p 6379 CONFIG GET dir
echo "--- 找配置文件 ---"
ps aux | grep -E 'redis-server' | grep -v grep
echo "--- 模块 .so 文件清单 ---"
ls -la /usr/lib/redis/modules/ 2>/dev/null
echo "--- 系统里所有 redis 相关 so ---"
find / -name "*.so" -path "*redis*" 2>/dev/null | head -20
echo "===== 尝试 MODULE LOAD ====="
ls /usr/lib/redis/modules/ 2>/dev/null | while read f; do
  echo "--- load $f ---"
  redis-cli -p 7101 MODULE LOAD "/usr/lib/redis/modules/$f" 2>&1 | head -3
done
echo "===== 加载后 MODULE LIST (7101) ====="
redis-cli -p 7101 MODULE LIST 2>&1
echo "===== BF 探测 ====="
redis-cli -p 7101 BF.RESERVE probe:bf 0.01 1000 2>&1 | head -2
redis-cli -p 7101 BF.ADD probe:bf a 2>&1 | head -2
redis-cli -p 7101 BF.EXISTS probe:bf a 2>&1 | head -2
redis-cli -p 7101 DEL probe:bf 2>&1 | head -2
echo "===== 7379 上模块为何有？查看 redis-server 启动参数 ====="
cat /proc/$(pgrep -f "redis-server \*:6379" | head -1)/cmdline 2>/dev/null | tr '\0' ' '; echo
pgrep -af redis-server | head
