#!/usr/bin/env bash
# 课 4 知识点 2：ZSet 跳表+哈希表双结构 —— 实测
PORT=6404
DIR=/tmp/redis-course-l04b
mkdir -p "$DIR"
redis-server --port "$PORT" --daemonize yes --save '' --appendonly no --dir "$DIR" > /dev/null 2>&1
sleep 1

echo "########## 1. ZSet 唯一 vs List 可重（与课 3 呼应）##########"
redis-cli -p "$PORT" del z:rank l:rank > /dev/null
redis-cli -p "$PORT" zadd z:rank 100 alice > /dev/null
redis-cli -p "$PORT" zadd z:rank 200 alice > /dev/null
echo "ZADD alice 两次: zcard=$(redis-cli -p "$PORT" zcard z:rank), alice 分数=$(redis-cli -p "$PORT" zscore z:rank alice)  <-- 覆盖更新，不是新增"
redis-cli -p "$PORT" rpush l:rank alice > /dev/null
redis-cli -p "$PORT" rpush l:rank alice > /dev/null
echo "RPUSH alice 两次: llen=$(redis-cli -p "$PORT" llen l:rank)  <-- List 允许重复"

echo ""
echo "########## 2. 分数相同怎么办（字典序）##########"
redis-cli -p "$PORT" del z:tie > /dev/null
redis-cli -p "$PORT" zadd z:tie 100 banana 100 apple 100 cherry > /dev/null
echo "同分 100 三个成员的升序: $(redis-cli -p "$PORT" zrange z:tie 0 -1 | tr '\n' ' ')"
echo "  <-- 分数相同按成员字典序排（banana/apple/cherry -> apple, banana, cherry）"

echo ""
echo "########## 3. 双结构证据：按成员 O(1) 查分 + 按分数 O(logN) 排 ##########"
redis-cli -p "$PORT" del z:big > /dev/null
seq 1 200000 | sed "s/^/zadd z:big /;s/$/ 0/" > /tmp/l04b_cmds.txt
# 造 20 万成员：memberN 分数 N
seq 1 200000 | awk '{print "zadd z:big "$1" m"$1}' | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
echo "成员数 zcard = $(redis-cli -p "$PORT" zcard z:big)"
echo "-- 按成员查分（哈希表能力）--"
/usr/bin/time -f "  ZSCORE m199999 耗时: %e 秒" redis-cli -p "$PORT" zscore z:big m199999
echo "-- 按排名取（跳表能力）--"
/usr/bin/time -f "  ZRANGE 0 9 耗时: %e 秒" redis-cli -p "$PORT" zrange z:big 0 9 > /dev/null
echo "-- 反查排名（需要 rank 字段）--"
/usr/bin/time -f "  ZREVRANK m199999 耗时: %e 秒" redis-cli -p "$PORT" zrevrank z:big m199999

echo ""
echo "########## 4. ZRANGEBYSCORE vs ZRANGE：语法已变（Redis 6.2+）##########"
echo "ZRANGEBYSCORE（旧，仍可用）: $(redis-cli -p "$PORT" zrangebyscore z:big 1 3 | tr '\n' ' ')"
echo "ZRANGE BYSCORE（新推荐）:   $(redis-cli -p "$PORT" zrange z:big 1 3 byscore | tr '\n' ' ')"
echo "ZRANGE BYSCORE + LIMIT:    $(redis-cli -p "$PORT" zrange z:big 1 100 byscore limit 0 3 | tr '\n' ' ')"

echo ""
echo "########## 5. 排行榜经典：ZREVRANGE + WITHSCORES ##########"
redis-cli -p "$PORT" del z:lb > /dev/null
redis-cli -p "$PORT" zadd z:lb 3000 张三 5200 李四 4100 王五 > /dev/null
echo "--- 降序 Top3（真实排名）---"
redis-cli -p "$PORT" zrevrange z:lb 0 2 withscores
echo "--- 张三排名第几（从 0 开始，+1 即真实名次）---"
echo "ZREVRANK 张三 = $(redis-cli -p "$PORT" zrevrank z:lb 张三)，即第 $(( $(redis-cli -p "$PORT" zrevrank z:lb 张三) + 1 )) 名"

echo ""
echo "########## 6. ZSet 编码：listpack -> skiplist ##########"
redis-cli -p "$PORT" del z:small z:big2 > /dev/null
seq 1 100 | awk '{print "zadd z:small "$1" m"$1}' | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
echo "  100 个成员 -> $(redis-cli -p "$PORT" object encoding z:small)  (zset-max-listpack-entries=128)"
seq 1 200 | awk '{print "zadd z:big2 "$1" m"$1}' | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
echo "  200 个成员 -> $(redis-cli -p "$PORT" object encoding z:big2)"
echo "  --- 长 value 触发 ---"
redis-cli -p "$PORT" del z:long > /dev/null
redis-cli -p "$PORT" zadd z:long 1 short > /dev/null
redis-cli -p "$PORT" zadd z:long 2 "$(printf 'y%.0s' $(seq 1 70))" > /dev/null
echo "  含 70 字节成员 -> $(redis-cli -p "$PORT" object encoding z:long)  (zset-max-listpack-value=64)"
echo "  --- 不可逆性 ---"
redis-cli -p "$PORT" del z:irr > /dev/null
seq 1 300 | awk '{print "zadd z:irr "$1" m"$1}' | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
echo "  300 个成员 -> $(redis-cli -p "$PORT" object encoding z:irr)"
for i in $(seq 101 300); do redis-cli -p "$PORT" zrem z:irr "m$i" > /dev/null; done
echo "  删到只剩 100 个 -> $(redis-cli -p "$PORT" object encoding z:irr)  (zcard=$(redis-cli -p "$PORT" zcard z:irr))"

echo ""
echo "清理中..."
redis-cli -p "$PORT" shutdown nosave 2>/dev/null
rm -f /tmp/l04b_cmds.txt
rmdir "$DIR" 2>/dev/null
echo "done"
