#!/usr/bin/env bash
# 课 4 知识点 2 计时最终方案：redis-benchmark + pipeline 摊薄网络 RTT
# 已知障碍（备课实测结论，写进讲义的"实测方法"说明）：
#   1. redis-cli 单次启动约 1.54ms 进程开销 -> 淹没命令耗时
#   2. redis-benchmark -c 1 约 40us 全是本地回环 RTT -> 仍淹没命令耗时
#   3. Lua 中 redis.call('TIME') 因复制确定性要求，整个脚本内返回固定值 -> 不能用于计时
# 方案：用 -P pipeline 把 N 条命令打包成一个 TCP 往返，摊薄 RTT，测的是服务端吞吐
PORT=6404
DIR=/tmp/redis-course-l04b6
mkdir -p "$DIR"
redis-server --port "$PORT" --daemonize yes --save '' --appendonly no --dir "$DIR" > /dev/null 2>&1
sleep 1

echo "=== pipeline=50 摊薄 RTT 后，各命令吞吐（ops/s）==="
echo ""

printf "%-12s %-20s %-20s %-20s\n" "规模" "ZSCORE" "ZREVRANK" "ZADD(插入)"
printf "%-12s %-20s %-20s %-20s\n" "------------" "--------------------" "--------------------" "--------------------"

for n in 10000 100000 1000000; do
  zkey="z:P:$n"
  redis-cli -p "$PORT" del "$zkey" > /dev/null
  seq 1 "$n" | awk -v k="$zkey" '{print "zadd "k" "$1" m"$1}' | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
  mid=$((n/2))

  zs=$(redis-benchmark -p "$PORT" -n 200000 -c 1 -P 50 zscore "$zkey" "m$mid" 2>/dev/null | grep -oP '[\d.]+(?= requests per second)')
  zr=$(redis-benchmark -p "$PORT" -n 200000 -c 1 -P 50 zrevrank "$zkey" "m$mid" 2>/dev/null | grep -oP '[\d.]+(?= requests per second)')
  # ZADD 是 O(logN) 插入
  za=$(redis-benchmark -p "$PORT" -n 200000 -c 1 -P 50 zadd "$zkey" "$mid" "m$mid" 2>/dev/null | grep -oP '[\d.]+(?= requests per second)')

  printf "%-12s %-20s %-20s %-20s\n" "$n" "${zs} ops/s" "${zr} ops/s" "${za} ops/s"
done

echo ""
echo "=== 换算单次耗时（微妙）与相对 1 万的倍数 ==="
printf "%-12s %-14s %-10s %-14s %-10s\n" "规模" "ZSCORE(us)" "倍数" "ZREVRANK(us)" "倍数"
printf "%-12s %-14s %-10s %-14s %-10s\n" "------------" "--------------" "----------" "--------------" "----------"

base_zs=""; base_zr=""
for n in 10000 100000 1000000; do
  zkey="z:P:$n"; mid=$((n/2))
  zs=$(redis-benchmark -p "$PORT" -n 200000 -c 1 -P 50 zscore "$zkey" "m$mid" 2>/dev/null | grep -oP '[\d.]+(?= requests per second)')
  zr=$(redis-benchmark -p "$PORT" -n 200000 -c 1 -P 50 zrevrank "$zkey" "m$mid" 2>/dev/null | grep -oP '[\d.]+(?= requests per second)')
  zs_us=$(awk "BEGIN{printf \"%.4f\", 1000000/$zs}")
  zr_us=$(awk "BEGIN{printf \"%.4f\", 1000000/$zr}")
  if [ -z "$base_zs" ]; then base_zs=$zs_us; base_zr=$zr_us; fi
  printf "%-12s %-14s %-10s %-14s %-10s\n" "$n" "${zs_us} us" \
    "$(awk "BEGIN{printf \"%.2fx\", $zs_us/$base_zs}")" \
    "${zr_us} us" "$(awk "BEGIN{printf \"%.2fx\", $zr_us/$base_zr}")"
done

echo ""
echo "=== 关键对照：LINDEX (O(N)) 在 pipeline 下的表现 ==="
printf "%-12s %-18s %-10s\n" "规模" "LINDEX(us)" "倍数"
printf "%-12s %-18s %-10s\n" "------------" "------------------" "----------"
base_li=""
for n in 10000 100000 1000000; do
  lkey="l:P:$n"
  if [ "$n" = "10000" ] || [ ! -f /tmp/l04_P_$n.done ]; then
    redis-cli -p "$PORT" del "$lkey" > /dev/null
    seq 1 "$n" | sed "s/^/v/" | awk -v k="$lkey" '{print "rpush "k" "$1}' | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
    touch /tmp/l04_P_$n.done
  fi
  mid=$((n/2))
  cnt=200000; if [ "$n" = "1000000" ]; then cnt=20000; fi
  li=$(redis-benchmark -p "$PORT" -n $cnt -c 1 -P 50 lindex "$lkey" "$mid" 2>/dev/null | grep -oP '[\d.]+(?= requests per second)')
  li_us=$(awk "BEGIN{printf \"%.4f\", 1000000/$li}")
  if [ -z "$base_li" ]; then base_li=$li_us; fi
  printf "%-12s %-18s %-10s\n" "$n" "${li_us} us" "$(awk "BEGIN{printf \"%.2fx\", $li_us/$base_li}")"
done

echo ""
echo "清理中..."
redis-cli -p "$PORT" flushall > /dev/null
redis-cli -p "$PORT" shutdown nosave 2>/dev/null
rm -f /tmp/l04_P_*.done
rmdir "$DIR" 2>/dev/null
echo "done"
