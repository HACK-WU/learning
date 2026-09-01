#!/bin/bash
# 课 9 备课：环境检查（只读）
echo "=== 1. WSL / 系统 ==="
lsb_release -d 2>/dev/null || cat /etc/os-release | head -2

echo ""
echo "=== 2. redis-server / redis-cli 版本 ==="
which -a redis-server redis-cli
redis-server --version
redis-cli --version

echo ""
echo "=== 3. 运行中实例 ==="
ps aux | grep -E "[r]edis-server" | head -20

echo ""
echo "=== 4. 默认实例 6379 信息 ==="
redis-cli -p 6379 ping 2>&1 | head -2
redis-cli -p 6379 info server 2>/dev/null | grep -E "redis_version|redis_mode|executable|config_file|os:|multiplexing"
redis-cli -p 6379 info server 2>/dev/null | grep -E "^run_id|^uptime_in_seconds"

echo ""
echo "=== 5. 模块（6379 上已加载的） ==="
redis-cli -p 6379 module list 2>/dev/null

echo ""
echo "=== 6. 模块文件位置 ==="
ls -la /opt/redis-stack/lib/ 2>/dev/null | grep -E "\.so$" | head -20
ls -la /usr/lib/redis/modules/ 2>/dev/null | head -20
find / -name "redisbloom*.so" -o -name "bf.*.so" -o -name "rejson.so" 2>/dev/null | head -10

echo ""
echo "=== 7. Python ==="
python3 --version
python3 -c "import socket,time,threading,random,json; print('stdlib OK')"

echo ""
echo "=== 8. 端口占用（7101-7110） ==="
for p in 7101 7102 7103 7104 7105; do
  r=$(redis-cli -p $p ping 2>/dev/null)
  echo "  $p -> ${r:-none}"
done

echo ""
echo "=== 9. 是否装了 memcached / valkey ==="
which memcached valkey-server 2>/dev/null || echo "  (none installed)"

echo ""
echo "=== 10. CPU 核数 ==="
nproc
