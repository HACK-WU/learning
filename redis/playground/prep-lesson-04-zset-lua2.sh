#!/usr/bin/env bash
# 课 4 知识点 2 计时修正：验证 TIME 命令在 Lua 中的精度问题，并改用累加法
PORT=6404
DIR=/tmp/redis-course-l04b5
mkdir -p "$DIR"
redis-server --port "$PORT" --daemonize yes --save '' --appendonly no --dir "$DIR" > /dev/null 2>&1
sleep 1

echo "=== 先诊断：Lua 中 redis.call('TIME') 是否返回真实时间 ==="
redis-cli -p "$PORT" eval "
  local a = redis.call('TIME')
  local s = 0
  for i=1,1000000 do s = s + i end
  local b = redis.call('TIME')
  return {tostring(a[1]), tostring(a[2]), tostring(b[1]), tostring(b[2]), 'sum='..s}
" 0

echo ""
echo "=== 改用 redis.call 累计大量操作 + 多次重复取最小值 ==="
echo "策略：每组测 5 轮，每轮循环 N 次，取最小总耗时除以次数"
echo ""

printf "%-12s %-18s %-18s %-18s\n" "规模" "ZSCORE(ns)" "ZREVRANK(ns)" "LINDEX(ns)"
printf "%-12s %-18s %-18s %-18s\n" "------------" "------------------" "------------------" "------------------"

for n in 10000 1000000; do
  zkey="z:T:$n"
  lkey="l:T:$n"
  redis-cli -p "$PORT" del "$zkey" "$lkey" > /dev/null
  seq 1 "$n" | awk -v k="$zkey" '{print "zadd "k" "$1" m"$1}' | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
  seq 1 "$n" | sed "s/^/v/" | awk -v k="$lkey" '{print "rpush "k" "$1}' | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
  mid=$((n/2))

  # 每轮 100 万次，测 5 轮取最小
  zs=$(redis-cli -p "$PORT" eval "
    local best = 1e18
    for r=1,5 do
      local a = redis.call('TIME'); local s0 = a[1]*1e6 + a[2]
      for i=1,1000000 do redis.call('zscore', KEYS[1], ARGV[1]) end
      local b = redis.call('TIME'); local s1 = b[1]*1e6 + b[2]
      local d = (s1-s0)*1000/1000000
      if d < best then best = d end
    end
    return best
  " 1 "$zkey" "m$mid")

  zr=$(redis-cli -p "$PORT" eval "
    local best = 1e18
    for r=1,5 do
      local a = redis.call('TIME'); local s0 = a[1]*1e6 + a[2]
      for i=1,1000000 do redis.call('zrevrank', KEYS[1], ARGV[1]) end
      local b = redis.call('TIME'); local s1 = b[1]*1e6 + b[2]
      local d = (s1-s0)*1000/1000000
      if d < best then best = d end
    end
    return best
  " 1 "$zkey" "m$mid")

  # LINDEX O(N)，减少循环次数
  li=$(redis-cli -p "$PORT" eval "
    local best = 1e18
    for r=1,3 do
      local a = redis.call('TIME'); local s0 = a[1]*1e6 + a[2]
      for i=1,100000 do redis.call('lindex', KEYS[1], ARGV[1]) end
      local b = redis.call('TIME'); local s1 = b[1]*1e6 + b[2]
      local d = (s1-s0)*1000/100000
      if d < best then best = d end
    end
    return best
  " 1 "$lkey" "$mid")

  printf "%-12s %-18s %-18s %-18s\n" "$n" \
    "$(awk "BEGIN{printf \"%.1f ns\", $zs}")" \
    "$(awk "BEGIN{printf \"%.1f ns\", $zr}")" \
    "$(awk "BEGIN{printf \"%.1f ns\", $li}")"
done

echo ""
echo "清理中..."
redis-cli -p "$PORT" flushall > /dev/null
redis-cli -p "$PORT" shutdown nosave 2>/dev/null
rmdir "$DIR" 2>/dev/null
echo "done"
