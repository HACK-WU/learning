#!/usr/bin/env bash
# 课 3 备课脚本 E：验证 List 的真实底层结构 quicklist（而非纯链表）
# 背景：500 万元素下 LINDEX 中间只要 4.6ms，与"纯链表 O(N)"不符，需查清真实结构
# 用法：bash /mnt/d/projects/learning/redis/playground/prep-lesson-03-quicklist.sh

set -u
PORT=6399
DIR=/tmp/redis-course-l03e
mkdir -p "$DIR"
cd "$DIR" || exit 1

redis-server --port "$PORT" --daemonize yes --save '' --appendonly no --dir "$DIR" > /dev/null 2>&1
sleep 1
redis-cli -p "$PORT" flushall > /dev/null

echo "########## 1. List 的底层编码 ##########"
redis-cli -p "$PORT" rpush q "a" "b" "c"
echo -n "OBJECT ENCODING q → "
redis-cli -p "$PORT" object encoding q

echo ""
echo "########## 2. quicklist 相关配置（决定每个节点打包多少元素）##########"
echo "--- list-max-listpack-size（正数=每节点元素数上限；负数=每节点字节数上限）---"
redis-cli -p "$PORT" config get list-max-listpack-size
echo "--- list-compress-depth（两端不压缩的节点数，0=不压缩）---"
redis-cli -p "$PORT" config get list-compress-depth

echo ""
echo "########## 3. 验证 quicklist 的分段结构：DEBUG QUICKLIST-PACKED-INFO ##########"
echo "--- 造 10000 元素的 List，看它被切成多少个 node ---"
redis-cli -p "$PORT" flushall > /dev/null
redis-cli -p "$PORT" eval "for i=1,10000 do redis.call('rpush','bigq','value'..i) end return 'ok'" 0
echo "长度: $(redis-cli -p "$PORT" llen bigq)"

echo ""
echo "########## 4. 用 DEBUG 命令观察 quicklist 节点信息 ##########"
redis-cli -p "$PORT" debug quicklist-packed-info bigq 2>&1 | head -20

echo ""
echo "########## 5. 用 MEMORY USAGE 对比：纯字符串 List vs 单个大 String ##########"
echo "--- 10000 元素的 List ---"
redis-cli -p "$PORT" memory usage bigq
echo "--- 同等内容的单个 String ---"
BIG=$(redis-cli -p "$PORT" eval "local s='' for i=1,10000 do s=s..'value'..i..',' end redis.call('set','bigstr',s) return string.len(s)" 0)
redis-cli -p "$PORT" memory usage bigstr
echo "（List 因节点元数据+指针，内存开销明显高于同等内容的单个 String）"

echo ""
echo "########## 6. 结论性验证：LINDEX 在不同规模下的耗时 ##########"
for N in 100000 1000000 5000000; do
  redis-cli -p "$PORT" flushall > /dev/null
  redis-cli -p "$PORT" eval "for i=1,tonumber(ARGV[1]) do redis.call('rpush','t','value'..i) end return 'ok'" 0 "$N"
  MID=$((N/2))
  # 用 Redis 内部计时更准：执行 100 次 LINDEX 取总耗时
  TOTAL=$(redis-cli -p "$PORT" eval "
    local s = redis.call('TIME')
    local t0 = s[1]*1000000 + s[2]
    for i=1,100 do redis.call('lindex','t',tonumber(ARGV[1])) end
    local e = redis.call('TIME')
    local t1 = e[1]*1000000 + e[2]
    return (t1-t0)/100
  " 0 "$MID")
  echo "N=$N, LINDEX 下标 $MID, 单次平均 ${TOTAL} 微秒"
done

echo ""
echo "########## 7. 清理 ##########"
redis-cli -p "$PORT" flushall > /dev/null
redis-cli -p "$PORT" shutdown nosave 2>/dev/null
sleep 0.5
echo "OK: 实例已关闭"
