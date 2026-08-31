#!/usr/bin/env bash
# 课 3 备课脚本 B：修正队列方向 + 四种对象存储方案内存横评 + 多消费者扇出验证
# 用法：bash /mnt/d/projects/learning/redis/playground/prep-lesson-03-mq.sh

set -u
PORT=6399
DIR=/tmp/redis-course-l03b
mkdir -p "$DIR"
cd "$DIR" || exit 1

redis-server --port "$PORT" --daemonize yes --save '' --appendonly no --dir "$DIR" > /dev/null 2>&1
sleep 1
redis-cli -p "$PORT" flushall > /dev/null

echo "########## 1. 正确的队列模型：LPUSH + RPOP（左进右出，FIFO）##########"
redis-cli -p "$PORT" lpush q "task:1" "task:2" "task:3"
echo "--- LPUSH 后从头到尾 ---"
redis-cli -p "$PORT" lrange q 0 -1
echo "--- RPOP 取出（应拿到最先进入的 task:1，符合 FIFO）---"
redis-cli -p "$PORT" rpop q
echo "--- 取出后队列剩余 ---"
redis-cli -p "$PORT" lrange q 0 -1

echo ""
echo "########## 2. 硬伤一：RPOP 一出队就没了（无 ACK）##########"
redis-cli -p "$PORT" lpush tasks "task:1" "task:2" "task:3"
echo "队列内容（lrange 0 -1）:"
redis-cli -p "$PORT" lrange tasks 0 -1
echo "--- 消费者 A 取出 task:1 ---"
redis-cli -p "$PORT" rpop tasks
echo "--- 此刻 Redis 里还剩什么（task:1 已彻底消失）---"
redis-cli -p "$PORT" lrange tasks 0 -1
echo "--- 消费者 A 处理时崩溃 → task:1 永久丢失，Redis 里没有任何副本能找回 ---"
echo "（专业 MQ：消费者取走后消息处于 unacked 状态，崩溃则重新投递）"

echo ""
echo "########## 3. 硬伤二：无消费组 —— 无法扇出（同一条消息给多个消费组各消费一次）##########"
redis-cli -p "$PORT" flushall > /dev/null
redis-cli -p "$PORT" lpush orders "order:1" "order:2"
echo "--- 消费组「发货」取走 order:1 ---"
redis-cli -p "$PORT" rpop orders
echo "--- 消费组「计费」想再读一次 order:1：队列里还有什么？---"
redis-cli -p "$PORT" lrange orders 0 -1
echo "结论：同一条消息只能被取走一次，其他消费组永远读不到它。List 做不到扇出。"
echo "      （多个消费者 BRPOP 同一 list 只是『分摊』，不是『各消费一份』）"

echo ""
echo "########## 4. 硬伤三：消费即删除 —— 无法回溯、重放、重试 ##########"
redis-cli -p "$PORT" flushall > /dev/null
redis-cli -p "$PORT" lpush events "e1" "e2" "e3"
redis-cli -p "$PORT" rpop events > /dev/null
redis-cli -p "$PORT" rpop events > /dev/null
echo "--- 消费完 e1、e2 后，想重放 e1：队列里只剩 ---"
redis-cli -p "$PORT" lrange events 0 -1
echo "结论：消息消费即删除，没有历史可回溯，没有重试队列，没有死信队列。"

echo ""
echo "########## 5. 对照：BRPOP 多消费者是『分摊』而非『扇出』##########"
redis-cli -p "$PORT" flushall > /dev/null
redis-cli -p "$PORT" lpush work "w1" "w2" "w3" "w4"
echo "--- 消费者1 取 ---"
redis-cli -p "$PORT" rpop work 2
echo "--- 消费者2 取 ---"
redis-cli -p "$PORT" rpop work 2
echo "--- 队列剩余 ---"
redis-cli -p "$PORT" llen work
echo "结论：4 条消息被两个消费者『分摊』了，每条只被处理一次——这是负载均衡，不是扇出。"

echo ""
echo "########## 6. 四种对象存储方案内存横评（10000 个对象，每个 5 字段）##########"
N=10000
mem() { redis-cli -p "$PORT" info memory | grep -oP 'used_memory:\K[0-9]+'; }

# 基线：空库占用
redis-cli -p "$PORT" flushall > /dev/null
BASE=$(mem)
echo "空库基线: $BASE 字节"

# 方案 A：每个对象一个 String（JSON）
redis-cli -p "$PORT" eval "
for i=1,tonumber(ARGV[1]) do
  local j = string.format('{\"id\":%d,\"name\":\"user%d\",\"age\":%d,\"city\":\"beijing\",\"vip\":1}', i, i, 20+(i%30))
  redis.call('set', 'u:j:'..i, j)
end return 'ok'" 0 "$N"
M_A=$(mem)
echo "A. String 存 JSON（$N 个 key）:      $((M_A-BASE)) 字节"

# 方案 B：每个对象一个 Hash
redis-cli -p "$PORT" flushall > /dev/null
redis-cli -p "$PORT" eval "
for i=1,tonumber(ARGV[1]) do
  redis.call('hset', 'u:h:'..i, 'id', i, 'name', 'user'..i, 'age', 20+(i%30), 'city', 'beijing', 'vip', 1)
end return 'ok'" 0 "$N"
M_B=$(mem)
echo "B. Hash 每个对象一个（$N 个 key）:   $((M_B-BASE)) 字节"

# 方案 C：分片 Hash（100 个对象聚合进一个 Hash）
redis-cli -p "$PORT" flushall > /dev/null
redis-cli -p "$PORT" eval "
local N = tonumber(ARGV[1])
local SHARD = 100
for i=1,N do
  local shard = math.floor((i-1)/SHARD)
  local field = 'o'..i
  redis.call('hset', 'u:shard:'..shard, field..':id', i, field..':name', 'user'..i,
             field..':age', 20+(i%30), field..':city', 'beijing', field..':vip', 1)
end return 'ok'" 0 "$N"
M_C=$(mem)
echo "C. 分片 Hash（100 对象/key，约 $(( (N+99)/100 )) 个 key）: $((M_C-BASE)) 字节"

# 方案 D：每个字段一个 String（最浪费，作为对照）
redis-cli -p "$PORT" flushall > /dev/null
redis-cli -p "$PORT" eval "
for i=1,tonumber(ARGV[1]) do
  redis.call('mset', 'u:f:'..i..':id', i, 'u:f:'..i..':name', 'user'..i,
             'u:f:'..i..':age', 20+(i%30), 'u:f:'..i..':city', 'beijing', 'u:f:'..i..':vip', 1)
end return 'ok'" 0 "$N"
M_D=$(mem)
echo "D. String 每字段一个 key（$((N*5)) 个 key）: $((M_D-BASE)) 字节"

echo ""
echo "--- 内存占用排名（越小越好）---"
awk -v a=$((M_A-BASE)) -v b=$((M_B-BASE)) -v c=$((M_C-BASE)) -v d=$((M_D-BASE)) 'BEGIN{
  printf "C 分片Hash: %d 字节  (基准 1.00x)\n", c;
  printf "B 对象Hash: %d 字节  (%.2fx)\n", b, b/c;
  printf "A String JSON: %d 字节  (%.2fx)\n", a, a/c;
  printf "D 每字段String: %d 字节  (%.2fx)\n", d, d/c;
  printf "\nB 比 A 节省: %.1f%%\n", (a-b)/a*100;
  printf "C 比 A 节省: %.1f%%\n", (a-c)/a*100;
  printf "D 比 A 多耗: %.1f%%\n", (d-a)/a*100;
}'

echo ""
echo "########## 7. 分片 Hash 的临界值：listpack 上限 ##########"
redis-cli -p "$PORT" flushall > /dev/null
echo "--- 分片 Hash 在 100 对象/key 时的编码（500 个 field，接近 512 阈值）---"
redis-cli -p "$PORT" config get hash-max-listpack-entries | tail -1
echo "--- 造一个 100 对象的分片，看编码 ---"
redis-cli -p "$PORT" eval "
for i=1,100 do
  redis.call('hset','test:shard', 'o'..i..':id', i, 'o'..i..':name','u'..i)
end return 'ok'" 0
echo "field 数: $(redis-cli -p "$PORT" hlen test:shard)  → 编码: $(redis-cli -p "$PORT" object encoding test:shard)"
echo "--- 再加 60 个对象（field 数超过 512）---"
redis-cli -p "$PORT" eval "
for i=101,160 do
  redis.call('hset','test:shard', 'o'..i..':id', i, 'o'..i..':name','u'..i)
end return 'ok'" 0
echo "field 数: $(redis-cli -p "$PORT" hlen test:shard)  → 编码: $(redis-cli -p "$PORT" object encoding test:shard)"
echo "超过 hash-max-listpack-entries(512) 后 listpack 退化为 hashtable，内存优势消失"

echo ""
echo "########## 8. 清理 ##########"
redis-cli -p "$PORT" flushall > /dev/null
redis-cli -p "$PORT" shutdown nosave 2>/dev/null
sleep 0.5
echo "OK: 实例已关闭"
