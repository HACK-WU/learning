#!/usr/bin/env bash
# 课 3 备课脚本 C：listpack 阈值退化验证 + 大 List 访问复杂度实测
# 用法：bash /mnt/d/projects/learning/redis/playground/prep-lesson-03-limit.sh

set -u
PORT=6399
DIR=/tmp/redis-course-l03c
mkdir -p "$DIR"
cd "$DIR" || exit 1

redis-server --port "$PORT" --daemonize yes --save '' --appendonly no --dir "$DIR" > /dev/null 2>&1
sleep 1
redis-cli -p "$PORT" flushall > /dev/null

echo "########## 1. listpack 阈值退化验证（hash-max-listpack-entries=512）##########"
redis-cli -p "$PORT" config get hash-max-listpack-entries | tail -1
redis-cli -p "$PORT" eval "for i=1,250 do redis.call('hset','t','o'..i..':id',i) end return 'ok'" 0
echo -n "field=250  → 编码: "
redis-cli -p "$PORT" object encoding t

redis-cli -p "$PORT" eval "for i=251,520 do redis.call('hset','t','o'..i..':id',i) end return 'ok'" 0
echo -n "field=$(redis-cli -p "$PORT" hlen t)  → 编码: "
redis-cli -p "$PORT" object encoding t
echo "结论：field 数超过 512 后，listpack 退化为 hashtable，紧凑编码的内存优势消失"

echo ""
echo "########## 2. 大 List 访问复杂度实测（100 万元素）##########"
redis-cli -p "$PORT" flushall > /dev/null
echo "--- 造 100 万元素的 List ---"
redis-cli -p "$PORT" eval "for i=1,1000000 do redis.call('rpush','bigq','v'..i) end return 'ok'" 0
echo "长度: $(redis-cli -p "$PORT" llen bigq)"

echo "--- LRANGE 头 10 条（O(10)，很快）---"
/usr/bin/time -f "LRANGE bigq 0 9 耗时: %e 秒" redis-cli -p "$PORT" lrange bigq 0 9 > /dev/null

echo "--- LINDEX 第 50 万个元素（O(N)，要遍历链表）---"
/usr/bin/time -f "LINDEX bigq 500000 耗时: %e 秒" redis-cli -p "$PORT" lindex bigq 500000 > /dev/null

echo "--- LRANGE 尾 10 条（看似 O(10)，实际要先走到尾部）---"
/usr/bin/time -f "LRANGE bigq -10 -1 耗时: %e 秒" redis-cli -p "$PORT" lrange bigq -10 -1 > /dev/null

echo "--- LPOP 头部（O(1)，很快）---"
/usr/bin/time -f "LPOP bigq 耗时: %e 秒" redis-cli -p "$PORT" lpop bigq > /dev/null

echo ""
echo "########## 3. 清理 ##########"
redis-cli -p "$PORT" flushall > /dev/null
redis-cli -p "$PORT" shutdown nosave 2>/dev/null
sleep 0.5
echo "OK: 实例已关闭"
