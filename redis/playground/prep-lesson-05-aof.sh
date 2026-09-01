#!/usr/bin/env bash
# 课 5 知识点 2：AOF 写后日志与刷盘策略 —— 实测
PORT=6405
BASE=/tmp/redis-course-l05-aof
rm -rf "$BASE"; mkdir -p "$BASE"

echo "########## 1. AOF 开启后的文件结构（Redis 7+ multi-part AOF）##########"
DIR1="$BASE/d1"; mkdir -p "$DIR1"
redis-server --port "$PORT" --daemonize yes --save '' --dir "$DIR1" > /dev/null 2>&1
sleep 1
redis-cli -p "$PORT" config set appendonly yes > /dev/null
sleep 1.5
echo "  appenddir 下的文件："
ls -la "$DIR1/appendonlydir/" 2>/dev/null | tail -5
echo ""
echo "  manifest 内容："
cat "$DIR1/appendonlydir/appendonly.aof.manifest" 2>/dev/null
echo ""
echo "  --- multi-part AOF 三部分说明 ---"
echo "  base:     RDB 格式的全量数据（rewrite 时生成）"
echo "  incr:     增量命令（AOF 格式）"
echo "  manifest: 索引文件，记录有哪些 base/incr 及其顺序"

echo ""
echo "########## 2. 写后日志：先执行命令，再写 AOF ##########"
redis-cli -p "$PORT" set writetest "value-1" > /dev/null
sleep 1.2
echo "  写入后 AOF incr 文件大小: $(ls -l "$DIR1"/appendonlydir/*.incr.aof 2>/dev/null | awk '{print $5}') 字节"
echo "  查看 AOF 内容（RESP 协议格式）："
cat "$DIR1"/appendonlydir/*.incr.aof 2>/dev/null | head -5 | cat -A | head -5

echo ""
echo "  === 关键验证：命令不合法时，AOF 里不会有记录 ==="
redis-cli -p "$PORT" set badkey "before" > /dev/null
# 执行一条会失败的命令（对 String 用 List 命令）
redis-cli -p "$PORT" rpush badkey "x" 2>&1 | head -1
echo "  失败的命令是否被写入 AOF？"
cat "$DIR1"/appendonlydir/*.incr.aof 2>/dev/null | grep -c "RPUSH" || echo "  0 次（证明写后日志：先执行成功，才记录）"

echo ""
echo "########## 3. 三种刷盘策略的性能对比 ##########"
echo "  用 redis-benchmark 测 SET 吞吐（pipeline=1，模拟真实单条写入）"
echo ""
printf "%-14s %-22s %-18s\n" "策略" "吞吐(ops/s)" "相对倍数"
printf "%-14s %-22s %-18s\n" "--------------" "----------------------" "------------------"

declare -A RES
for pol in no everysec always; do
  redis-cli -p "$PORT" config set appendfsync "$pol" > /dev/null
  sleep 0.5
  T=$(redis-benchmark -p "$PORT" -n 50000 -c 10 -t set -q 2>/dev/null | grep -oP 'SET: \K[\d.]+')
  [ -z "$T" ] && T=0
  RES[$pol]=$T
done

BASE_T=${RES[no]}
[ -z "$BASE_T" ] || [ "$BASE_T" = "0" ] && BASE_T=1
for pol in no everysec always; do
  printf "%-14s %-22s %-18s\n" "$pol" "${RES[$pol]} ops/s" \
    "$(awk -v t=${RES[$pol]} -v b=$BASE_T 'BEGIN{printf "%.2fx", t/b}')"
done

echo ""
echo "  === 延迟对比（P50 / P99）==="
for pol in no everysec always; do
  redis-cli -p "$PORT" config set appendfsync "$pol" > /dev/null
  sleep 0.5
  L=$(redis-benchmark -p "$PORT" -n 20000 -c 10 -t set 2>/dev/null | grep -A3 "Latency" | head -2 | tr '\n' ' ')
  echo "  $pol: $L"
done

echo ""
echo "########## 4. AOF 重写：文件从大到小 ##########"
redis-cli -p "$PORT" config set appendfsync everysec > /dev/null
# 制造大量冗余命令
echo "  对同一个 key 反复写入 10000 次..."
for i in $(seq 1 10000); do echo "set hotkey value-$i"; done | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
sleep 1.5
SZ_BEFORE=$(du -sb "$DIR1/appendonlydir" 2>/dev/null | awk '{print $1}')
echo "  重写前 appendonlydir 大小: $(awk -v v=$SZ_BEFORE 'BEGIN{printf "%.2f MB", v/1024/1024}')"
echo "  dbsize: $(redis-cli -p "$PORT" dbsize)  <-- 只有几个 key，但 AOF 记了 1 万条命令"

redis-cli -p "$PORT" bgrewriteaof > /dev/null
sleep 3
SZ_AFTER=$(du -sb "$DIR1/appendonlydir" 2>/dev/null | awk '{print $1}')
echo "  重写后 appendonlydir 大小: $(awk -v v=$SZ_AFTER 'BEGIN{printf "%.2f MB", v/1024/1024}')"
echo "  压缩比: $(awk -v a=$SZ_AFTER -v b=$SZ_BEFORE 'BEGIN{printf "%.1f%%", (1-a/b)*100}')"
echo "  重写后 dbsize 不变: $(redis-cli -p "$PORT" dbsize)"
echo "  hotkey 的值仍是最后的: $(redis-cli -p "$PORT" get hotkey)"

echo ""
echo "########## 5. 混合持久化：aof-use-rdb-preamble ##########"
echo "  aof-use-rdb-preamble = $(redis-cli -p "$PORT" config get aof-use-rdb-preamble | tail -1)"
echo "  base 文件的开头几个字节（RDB 格式以 REDIS 开头）："
head -c 16 "$DIR1"/appendonlydir/*.base.aof 2>/dev/null | cat -v
echo ""
echo "  <-- 如果是 'REDIS' 开头，说明 base 是 RDB 格式（混合持久化生效）"

echo ""
echo "########## 6. 重启加载：AOF vs RDB 谁优先 ##########"
echo "  AOF enabled: $(redis-cli -p "$PORT" info persistence | grep -oP '(?<=^aof_enabled:)\d+')"
echo "  RDB 存在: $([ -f "$DIR1/dump.rdb" ] && echo yes || echo no)"
redis-cli -p "$PORT" set survive:test "should-survive" > /dev/null
sleep 1.2
redis-cli -p "$PORT" shutdown nosave 2>/dev/null
sleep 1
DIR2="$BASE/d1"
redis-server --port "$PORT" --daemonize yes --dir "$DIR2" > /dev/null 2>&1
sleep 2
echo "  重启后 survive:test = $(redis-cli -p "$PORT" get survive:test)  <-- AOF 恢复了数据"

echo ""
echo "清理中..."
redis-cli -p "$PORT" shutdown nosave 2>/dev/null
rm -rf "$BASE"
echo "done"
