#!/usr/bin/env bash
# 课 5 知识点 3：持久化选型 —— RDB vs AOF 加载速度实测
PORT=6405
BASE=/tmp/redis-course-l05-load
rm -rf "$BASE"; mkdir -p "$BASE"

echo "########## 1. 构造相同数据集，分别用 RDB 和纯 AOF 持久化 ##########"
N=300000
echo "  数据量: $N 个 key"

# --- RDB ---
DR="$BASE/rdb"; mkdir -p "$DR"
redis-server --port "$PORT" --daemonize yes --save '' --appendonly no --dir "$DR" --maxmemory 0 > /dev/null 2>&1
sleep 1.2
seq 1 $N | awk '{print "set key:"$1" value-"$1}' | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
echo "  RDB 实例 dbsize: $(redis-cli -p "$PORT" dbsize)"
redis-cli -p "$PORT" bgsave > /dev/null
sleep 3
echo "  RDB 文件大小: $(ls -l "$DR/dump.rdb" | awk '{printf "%.2f MB", $5/1024/1024}')"
redis-cli -p "$PORT" shutdown nosave 2>/dev/null
sleep 1

# --- 纯 AOF（关闭混合持久化）---
DA="$BASE/aof"; mkdir -p "$DA"
redis-server --port "$PORT" --daemonize yes --save '' --dir "$DA" --maxmemory 0 > /dev/null 2>&1
sleep 1.2
redis-cli -p "$PORT" config set aof-use-rdb-preamble no > /dev/null
redis-cli -p "$PORT" config set appendonly yes > /dev/null
sleep 1.5
seq 1 $N | awk '{print "set key:"$1" value-"$1}' | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
sleep 1
redis-cli -p "$PORT" bgrewriteaof > /dev/null
sleep 3
echo "  纯 AOF 大小: $(du -sb "$DA/appendonlydir" | awk '{printf "%.2f MB", $1/1024/1024}')"
redis-cli -p "$PORT" shutdown nosave 2>/dev/null
sleep 1

# --- 混合（默认）---
DH="$BASE/hyb"; mkdir -p "$DH"
redis-server --port "$PORT" --daemonize yes --save '' --appendonly yes --dir "$DH" --maxmemory 0 > /dev/null 2>&1
sleep 1.2
seq 1 $N | awk '{print "set key:"$1" value-"$1}' | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
sleep 1
redis-cli -p "$PORT" bgrewriteaof > /dev/null
sleep 3
echo "  混合持久化大小: $(du -sb "$DH/appendonlydir" | awk '{printf "%.2f MB", $1/1024/1024}')"
redis-cli -p "$PORT" shutdown nosave 2>/dev/null
sleep 1

echo ""
echo "########## 2. 重启加载速度对比 ##########"
echo ""

measure_load() {
  local dir=$1; local label=$2; local extra=$3
  local s=$(date +%s%N)
  if [ -n "$extra" ]; then
    redis-server --port "$PORT" --daemonize yes --dir "$dir" $extra > /dev/null 2>&1
  else
    redis-server --port "$PORT" --daemonize yes --dir "$dir" > /dev/null 2>&1
  fi
  # 等待可服务
  local ok=0
  for i in $(seq 1 100); do
    if [ "$(redis-cli -p "$PORT" ping 2>/dev/null)" = "PONG" ]; then ok=1; break; fi
    sleep 0.1
  done
  local e=$(date +%s%N)
  local ms=$(awk "BEGIN{printf \"%.0f\", ($e-$s)/1000000}")
  local cnt=$(redis-cli -p "$PORT" dbsize 2>/dev/null || echo 0)
  echo "  $label: 启动到可服务 ${ms} ms, 加载 $cnt 个 key"
  redis-cli -p "$PORT" shutdown nosave 2>/dev/null
  sleep 1
  echo "$ms"
}

echo "  --- RDB 加载 ---"
T_RDB=$(measure_load "$DR" "RDB" "")
echo ""
echo "  --- 纯 AOF 加载（30 万条命令重放）---"
T_AOF=$(measure_load "$DA" "纯AOF" "--appendonly yes")
echo ""
echo "  --- 混合持久化加载 ---"
T_HYB=$(measure_load "$DH" "混合" "--appendonly yes")

echo ""
echo "########## 3. 汇总 ##########"
printf "%-16s %-18s\n" "方式" "启动到可服务"
printf "%-16s %-18s\n" "----------------" "------------------"
printf "%-16s %-18s\n" "RDB" "${T_RDB} ms"
printf "%-16s %-18s\n" "纯 AOF" "${T_AOF} ms"
printf "%-16s %-18s\n" "混合(RDB+AOF)" "${T_HYB} ms"

echo ""
echo "########## 4. 文件大小汇总 ##########"
printf "%-16s %-18s\n" "方式" "磁盘占用"
printf "%-16s %-18s\n" "----------------" "------------------"
R=$(du -sb "$DR/dump.rdb" | awk '{printf "%.2f MB", $1/1024/1024}')
A=$(du -sb "$DA/appendonlydir" | awk '{printf "%.2f MB", $1/1024/1024}')
H=$(du -sb "$DH/appendonlydir" | awk '{printf "%.2f MB", $1/1024/1024}')
printf "%-16s %-18s\n" "RDB" "$R"
printf "%-16s %-18s\n" "纯 AOF" "$A"
printf "%-16s %-18s\n" "混合" "$H"

echo ""
echo "########## 5. 关闭持久化：纯缓存场景 ##########"
DN="$BASE/none"; mkdir -p "$DN"
s=$(date +%s%N)
redis-server --port "$PORT" --daemonize yes --save '' --appendonly no --dir "$DN" > /dev/null 2>&1
for i in $(seq 1 100); do
  [ "$(redis-cli -p "$PORT" ping 2>/dev/null)" = "PONG" ] && break
  sleep 0.1
done
e=$(date +%s%N)
echo "  无持久化启动: $(awk "BEGIN{printf \"%.0f\", ($e-$s)/1000000}") ms"
echo "  save 配置: '$(redis-cli -p "$PORT" config get save | tail -1)'"
echo "  appendonly: $(redis-cli -p "$PORT" config get appendonly | tail -1)"
redis-cli -p "$PORT" shutdown nosave 2>/dev/null

echo ""
echo "清理中..."
sleep 0.5
rm -rf "$BASE"
echo "done"
