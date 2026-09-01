#!/usr/bin/env bash
# 课 4 知识点 2 最终版：用 Lua 脚本在服务端内部计时，彻底隔离网络往返
# 网络 RTT 约 40us，命令本身耗时是零头，必须服务端内计时才能看到复杂度差异
PORT=6404
DIR=/tmp/redis-course-l04b4
mkdir -p "$DIR"
redis-server --port "$PORT" --daemonize yes --save '' --appendonly no --dir "$DIR" > /dev/null 2>&1
sleep 1

echo "=== 服务端内 Lua 计时：单次命令真实耗时（纳秒级）==="
echo ""

printf "%-12s %-16s %-16s %-16s\n" "规模" "ZSCORE(ns)" "ZREVRANK(ns)" "LINDEX(ns)"
printf "%-12s %-16s %-16s %-16s\n" "------------" "----------------" "----------------" "----------------"

for n in 10000 100000 1000000; do
  zkey="z:L:$n"
  lkey="l:L:$n"
  redis-cli -p "$PORT" del "$zkey" "$lkey" > /dev/null
  seq 1 "$n" | awk -v k="$zkey" '{print "zadd "k" "$1" m"$1}' | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
  seq 1 "$n" | sed "s/^/v/" | awk -v k="$lkey" '{print "rpush "k" "$1}' | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
  mid=$((n/2))

  # Lua：服务端内循环 200000 次 ZSCORE，返回总耗时(微秒)
  zs_ns=$(redis-cli -p "$PORT" eval "
    local t0 = redis.call('TIME')
    local s0 = t0[1]*1000000 + t0[2]
    for i=1,200000 do redis.call('zscore', KEYS[1], ARGV[1]) end
    local t1 = redis.call('TIME')
    local s1 = t1[1]*1000000 + t1[2]
    return (s1-s0)*1000/200000
  " 1 "$zkey" "m$mid")
  zs=$(awk "BEGIN{printf \"%.1f\", $zs_ns}")

  zr_ns=$(redis-cli -p "$PORT" eval "
    local t0 = redis.call('TIME')
    local s0 = t0[1]*1000000 + t0[2]
    for i=1,200000 do redis.call('zrevrank', KEYS[1], ARGV[1]) end
    local t1 = redis.call('TIME')
    local s1 = t1[1]*1000000 + t1[2]
    return (s1-s0)*1000/200000
  " 1 "$zkey" "m$mid")
  zr=$(awk "BEGIN{printf \"%.1f\", $zr_ns}")

  # LINDEX 是 O(N)，循环次数减少避免超时
  li_ns=$(redis-cli -p "$PORT" eval "
    local t0 = redis.call('TIME')
    local s0 = t0[1]*1000000 + t0[2]
    for i=1,20000 do redis.call('lindex', KEYS[1], ARGV[1]) end
    local t1 = redis.call('TIME')
    local s1 = t1[1]*1000000 + t1[2]
    return (s1-s0)*1000/20000
  " 1 "$lkey" "$mid")
  li=$(awk "BEGIN{printf \"%.1f\", $li_ns}")

  printf "%-12s %-16s %-16s %-16s\n" "$n" "$zs ns" "$zr ns" "$li ns"
done

echo ""
echo "=== 理论对照：log2(N) 与 N 的增长 ==="
printf "%-12s %-16s %-16s\n" "规模 N" "log2(N)" "N 相对倍数"
printf "%-12s %-16s %-16s\n" "------------" "----------------" "----------------"
for n in 10000 100000 1000000; do
  printf "%-12s %-16s %-16s\n" "$n" \
    "$(awk "BEGIN{printf \"%.1f\", log($n)/log(2)}")" \
    "$(awk "BEGIN{printf \"%.0fx\", $n/10000}")"
done

echo ""
echo "=== ZSet vs List 内存（100 万）==="
echo "ZSet: $(redis-cli -p "$PORT" memory usage z:L:1000000 | awk '{printf "%.2f MB", $1/1024/1024}')"
echo "List: $(redis-cli -p "$PORT" memory usage l:L:1000000 | awk '{printf "%.2f MB", $1/1024/1024}')"

echo ""
echo "清理中..."
redis-cli -p "$PORT" flushall > /dev/null
redis-cli -p "$PORT" shutdown nosave 2>/dev/null
rmdir "$DIR" 2>/dev/null
echo "done"
