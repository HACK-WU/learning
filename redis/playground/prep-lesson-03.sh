#!/usr/bin/env bash
# 课 3《List 与 Hash》备课脚本：实测 List 双向/阻塞操作、List 当 MQ 的三个硬伤、Hash vs String 内存对比
# 用法：bash /mnt/d/projects/learning/redis/playground/prep-lesson-03.sh

set -u
PORT=6399
DIR=/tmp/redis-course-l03
mkdir -p "$DIR"
cd "$DIR" || exit 1

redis-server --port "$PORT" --daemonize yes --save '' --appendonly no --dir "$DIR" > /dev/null 2>&1
sleep 1
redis-cli -p "$PORT" flushall > /dev/null

echo "########## 1. List 双向操作 ##########"
redis-cli -p "$PORT" rpush q "a" "b" "c"
redis-cli -p "$PORT" lpush q "z"
redis-cli -p "$PORT" lrange q 0 -1
echo "--- llen / lindex / ltrim ---"
redis-cli -p "$PORT" llen q
redis-cli -p "$PORT" lindex q 0
redis-cli -p "$PORT" lindex q -1
redis-cli -p "$PORT" ltrim q 0 2
redis-cli -p "$PORT" lrange q 0 -1

echo ""
echo "########## 2. BLPOP/BRPOP 阻塞弹出 ##########"
echo "--- 空列表上 BRPOP 阻塞 3 秒后超时返回 nil ---"
S=$(date +%s.%N)
redis-cli -p "$PORT" brpop empty:q 3
E=$(date +%s.%N)
echo "实际阻塞耗时: $(echo "$E - $S" | bc) 秒（返回 nil = (nil)）"

echo "--- 阻塞中被 LPUSH 唤醒：立刻拿到值并提前返回 ---"
(
  sleep 1
  redis-cli -p "$PORT" lpush wake:q "hello" > /dev/null
) &
S=$(date +%s.%N)
redis-cli -p "$PORT" brpop wake:q 5
E=$(date +%s.%N)
echo "实际等待耗时: $(echo "$E - $S" | bc) 秒（远小于 5 秒超时，说明被唤醒）"
wait

echo "--- timeout=0 表示永久阻塞（危险，此例用后台 sleep 5 后 kill 演示）---"
( redis-cli -p "$PORT" brpop forever:q 0 > /tmp/forever.txt 2>&1 & echo $! > /tmp/forever.pid )
sleep 1
echo "发起后 1 秒，进程是否还在: $(ps -p "$(cat /tmp/forever.pid)" > /dev/null 2>&1 && echo '是（仍在阻塞）' || echo '否')"
kill "$(cat /tmp/forever.pid)" 2>/dev/null
echo "已 kill 该阻塞连接（说明 timeout=0 不会自己退出）"

echo ""
echo "########## 3. 硬伤一：没有消费确认（消费者崩了消息就丢）##########"
redis-cli -p "$PORT" flushall > /dev/null
redis-cli -p "$PORT" rpush tasks "task:1" "task:2" "task:3"
echo "生产者投入 3 个任务，当前队列长度:"
redis-cli -p "$PORT" llen tasks
echo "--- 消费者用 RPOP 取出 task:1（RPOP 一返回，消息就从 Redis 里消失了）---"
redis-cli -p "$PORT" rpop tasks
echo "取出后队列剩余（task:1 已从 Redis 消失，无人再能拿到它）:"
redis-cli -p "$PORT" lrange tasks 0 -1
echo "--- 模拟消费者处理到一半崩溃：task:1 永久丢失，且没有任何机制能找回 ---"
echo "（对比：专业 MQ 有 ACK，消费者崩溃后消息会重新投递）"

echo ""
echo "########## 4. 硬伤二：没有消费组，多个消费者无法协作（但不会重复消费）##########"
redis-cli -p "$PORT" flushall > /dev/null
redis-cli -p "$PORT" rpush tasks "t1" "t2" "t3" "t4"
echo "--- 消费者 A 取 2 个 ---"
redis-cli -p "$PORT" rpop tasks 2
echo "--- 消费者 B 取 2 个 ---"
redis-cli -p "$PORT" rpop tasks 2
echo "--- 队列剩余 ---"
redis-cli -p "$PORT" llen tasks
echo "结论：多消费者各自取走不同消息（不重复），但没有消费组概念，无法做负载均衡+故障转移的统一管理"

echo ""
echo "########## 5. 硬伤三：没有消息堆积能力 / 无重试 / 无回溯 ##########"
redis-cli -p "$PORT" flushall > /dev/null
redis-cli -p "$PORT" rpush log:q "m1" "m2" "m3"
echo "--- 消息被消费后即消失，无法重放历史 ---"
redis-cli -p "$PORT" rpop log:q
redis-cli -p "$PORT" lrange log:q 0 -1
echo "--- 大 List 的 LRANGE 是 O(N)，取尾部 10 条也要 O(N) ---"
redis-cli -p "$PORT" eval "for i=1,200000 do redis.call('rpush','big:q','v'..i) end return 'ok'" 0
echo "big:q 长度: $(redis-cli -p "$PORT" llen big:q)"
echo "--- LRANGE big:q -10 -1 耗时（尾部 10 条）---"
/usr/bin/time -f "LRANGE 尾部10条 耗时: %e 秒" redis-cli -p "$PORT" lrange big:q -10 -1 > /dev/null
echo "--- LINDEX big:q 100000 耗时（按下标访问中间元素，O(N)）---"
/usr/bin/time -f "LINDEX 中间元素 耗时: %e 秒" redis-cli -p "$PORT" lindex big:q 100000 > /dev/null

echo ""
echo "########## 6. Hash vs String 存对象：内存实测 ##########"
redis-cli -p "$PORT" flushall > /dev/null
N=10000
echo "--- 写入 $N 个对象，方案 A：String 存 JSON ---"
redis-cli -p "$PORT" eval "
for i=1,tonumber(ARGV[1]) do
  local j = string.format('{\"id\":%d,\"name\":\"user%d\",\"age\":%d,\"city\":\"beijing\",\"vip\":1}', i, i, 20+(i%30))
  redis.call('set', 'user:json:'..i, j)
end
return 'ok'" 0 "$N"
MEM_JSON=$(redis-cli -p "$PORT" info memory | grep -oP 'used_memory:\K[0-9]+')
echo "String+JSON 占用: $MEM_JSON 字节"

redis-cli -p "$PORT" flushall > /dev/null
echo "--- 写入 $N 个对象，方案 B：Hash ---"
redis-cli -p "$PORT" eval "
for i=1,tonumber(ARGV[1]) do
  local k = 'user:hash:'..i
  redis.call('hset', k, 'id', i, 'name', 'user'..i, 'age', 20+(i%30), 'city', 'beijing', 'vip', 1)
end
return 'ok'" 0 "$N"
MEM_HASH=$(redis-cli -p "$PORT" info memory | grep -oP 'used_memory:\K[0-9]+')
echo "Hash 占用: $MEM_HASH 字节"

echo "--- 对比 ---"
echo "String+JSON: $MEM_JSON 字节"
echo "Hash:        $MEM_HASH 字节"
awk -v a="$MEM_JSON" -v b="$MEM_HASH" 'BEGIN{printf "Hash 相比 String+JSON 节省: %.1f%%\n", (a-b)/a*100}'

echo ""
echo "--- 底层编码 ---"
redis-cli -p "$PORT" object encoding user:hash:1
echo "--- 单个对象的内存占用 ---"
redis-cli -p "$PORT" memory usage user:hash:1

echo ""
echo "########## 7. Hash 的部分读写优势 ##########"
redis-cli -p "$PORT" hset user:1001 name "张三" age 28 city "北京" vip 1
echo "--- 只改 age 一个字段：HSET 一条命令搞定 ---"
redis-cli -p "$PORT" hset user:1001 age 29
redis-cli -p "$PORT" hmget user:1001 name age
echo "--- 原子自增：HINCRBY ---"
redis-cli -p "$PORT" hset user:1001 login_count 0
redis-cli -p "$PORT" hincrby user:1001 login_count 1
redis-cli -p "$PORT" hincrby user:1001 login_count 5
echo "--- 只取需要的字段，不用拉全量 ---"
redis-cli -p "$PORT" hmget user:1001 name city

echo ""
echo "########## 8. hash-max-listpack 临界值验证 ##########"
echo "--- 当前配置 ---"
redis-cli -p "$PORT" config get hash-max-listpack-entries
redis-cli -p "$PORT" config get hash-max-listpack-value
echo "--- 小 hash（字段少、值短）编码：---"
redis-cli -p "$PORT" hset small:h a 1 b 2
redis-cli -p "$PORT" object encoding small:h
echo "--- 超过 value 长度阈值（>64 字节）后编码转为 hashtable：---"
redis-cli -p "$PORT" hset bigval:h a "$(head -c 100 < /dev/zero | tr '\0' 'x')"
redis-cli -p "$PORT" object encoding bigval:h

echo ""
echo "########## 9. 清理 ##########"
redis-cli -p "$PORT" flushall > /dev/null
redis-cli -p "$PORT" shutdown nosave 2>/dev/null
sleep 0.5
echo "OK: 实例已关闭"
