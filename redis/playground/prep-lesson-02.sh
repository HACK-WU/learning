#!/usr/bin/env bash
# 课 2《跑起来第一个 Redis》备课脚本：实测五种基础类型、通用命令、KEYS vs SCAN
# 用法：bash /mnt/d/projects/learning/redis/playground/prep-lesson-02.sh

set -u
PORT=6399
DIR=/tmp/redis-course-l02
mkdir -p "$DIR"
cd "$DIR" || exit 1

redis-server --port "$PORT" --daemonize yes --save '' --appendonly no --dir "$DIR" > /dev/null 2>&1
sleep 1
redis-cli -p "$PORT" flushall > /dev/null

echo "########## 1. 五种基础类型 ##########"
echo "--- string ---"
redis-cli -p "$PORT" set product:1001:name "机械键盘"
redis-cli -p "$PORT" get product:1001:name
redis-cli -p "$PORT" set stock:1001 100
redis-cli -p "$PORT" incr stock:1001
redis-cli -p "$PORT" decrby stock:1001 5

echo "--- list ---"
redis-cli -p "$PORT" rpush queue:orders "order:1" "order:2" "order:3"
redis-cli -p "$PORT" llen queue:orders
redis-cli -p "$PORT" lpop queue:orders
redis-cli -p "$PORT" lrange queue:orders 0 -1

echo "--- hash ---"
redis-cli -p "$PORT" hset user:1001 name "张三" age 28 city "北京"
redis-cli -p "$PORT" hget user:1001 name
redis-cli -p "$PORT" hgetall user:1001
redis-cli -p "$PORT" hlen user:1001

echo "--- set ---"
redis-cli -p "$PORT" sadd tags:1001 "电子" "外设" "促销"
redis-cli -p "$PORT" sadd tags:1001 "电子"
redis-cli -p "$PORT" smembers tags:1001
redis-cli -p "$PORT" scard tags:1001
redis-cli -p "$PORT" sismember tags:1001 "外设"

echo "--- zset ---"
redis-cli -p "$PORT" zadd rank:daily 1200 "player:a" 950 "player:b" 1600 "player:c"
redis-cli -p "$PORT" zrevrange rank:daily 0 -1 withscores
redis-cli -p "$PORT" zscore rank:daily "player:b"
redis-cli -p "$PORT" zcard rank:daily

echo ""
echo "########## 2. 通用命令 ##########"
redis-cli -p "$PORT" type product:1001:name
redis-cli -p "$PORT" type queue:orders
redis-cli -p "$PORT" type user:1001
redis-cli -p "$PORT" type tags:1001
redis-cli -p "$PORT" type rank:daily
echo "--- exists / dbsize / keys count ---"
redis-cli -p "$PORT" exists product:1001:name
redis-cli -p "$PORT" exists notexist:key
redis-cli -p "$PORT" dbsize
echo "--- ttl 三态：-1 永不过期 / -2 不存在 / 正数剩余秒 ---"
redis-cli -p "$PORT" ttl product:1001:name
redis-cli -p "$PORT" ttl notexist:key
redis-cli -p "$PORT" expire product:1001:name 60
redis-cli -p "$PORT" ttl product:1001:name
echo "--- set ex：写入即设过期 ---"
redis-cli -p "$PORT" set sms:code:13800138000 "8848" ex 300
redis-cli -p "$PORT" ttl sms:code:13800138000
echo "--- persist 取消过期 / del 删除 ---"
redis-cli -p "$PORT" persist product:1001:name
redis-cli -p "$PORT" ttl product:1001:name
redis-cli -p "$PORT" del sms:code:13800138000
redis-cli -p "$PORT" exists sms:code:13800138000

echo ""
echo "########## 3. OBJECT ENCODING（看底层编码，为阶段2埋伏笔）##########"
redis-cli -p "$PORT" object encoding product:1001:name
redis-cli -p "$PORT" object encoding stock:1001
redis-cli -p "$PORT" object encoding user:1001
redis-cli -p "$PORT" object encoding rank:daily

echo ""
echo "########## 4. KEYS vs SCAN 实测（造 20000 个 key）##########"
redis-cli -p "$PORT" flushall > /dev/null
redis-cli -p "$PORT" eval "for i=1,20000 do redis.call('set', 'biz:item:'..i, 'v'..i) end return 'ok'" 0
echo "当前 key 总数:"
redis-cli -p "$PORT" dbsize

echo "--- KEYS biz:item:* 耗时（全量扫描，一次性返回）---"
/usr/bin/time -f "KEYS 耗时: %e 秒" redis-cli -p "$PORT" keys "biz:item:*" > /dev/null

echo "--- SCAN 游标分批遍历耗时 ---"
START=$(date +%s.%N)
COUNT=0
CURSOR=0
while true; do
  RESP=$(redis-cli -p "$PORT" scan "$CURSOR" match "biz:item:*" count 1000)
  CURSOR=$(echo "$RESP" | head -1)
  CURSOR=$(echo "$CURSOR" | tr -d '\r')
  N=$(echo "$RESP" | tail -n +2 | grep -c .)
  COUNT=$((COUNT + N))
  if [ "$CURSOR" = "0" ]; then break; fi
done
END=$(date +%s.%N)
echo "SCAN 遍历完成，共 $COUNT 个 key，耗时: $(echo "$END - $START" | bc) 秒"

echo ""
echo "########## 5. 单线程阻塞验证：慢命令期间 PING 被阻塞 ##########"
# 后台发起一个 5 秒的 DEBUG SLEEP（模拟慢命令），期间测量 PING 延迟
redis-cli -p "$PORT" --latency-history -i 1 > /tmp/lat.txt 2>/dev/null &
LPID=$!
sleep 1
redis-cli -p "$PORT" debug sleep 3 > /dev/null 2>&1
sleep 3
kill $LPID 2>/dev/null
echo "--- 延迟采样（debug sleep 3 期间的 PING 延迟，单位 ms）---"
grep -o 'min: [0-9.]*, max: [0-9.]*' /tmp/lat.txt | head -6

echo ""
echo "########## 清理 ##########"
redis-cli -p "$PORT" flushall > /dev/null
redis-cli -p "$PORT" shutdown nosave 2>/dev/null
sleep 0.5
echo "OK: 实例已关闭"
