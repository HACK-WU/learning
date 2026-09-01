#!/usr/bin/env bash
# 课 5 知识点 1：RDB fork 与写时复制 —— 实测
PORT=6405
DIR=/tmp/redis-course-l05-rdb
rm -rf "$DIR"; mkdir -p "$DIR"

redis-server --port "$PORT" --daemonize yes --save '' --appendonly no --dir "$DIR" --maxmemory 0 > /dev/null 2>&1
sleep 1

echo "########## 1. SAVE vs BGSAVE：一个阻塞，一个不阻塞 ##########"
redis-cli -p "$PORT" set k1 v1 > /dev/null
echo "-- SAVE（主线程执行，会阻塞）--"
s=$(date +%s%N)
redis-cli -p "$PORT" save
e=$(date +%s%N)
echo "  SAVE 返回耗时: $(awk "BEGIN{printf \"%.2f ms\", ($e-$s)/1000000}")"

echo "-- BGSAVE（fork 子进程，主线程继续服务）--"
s=$(date +%s%N)
redis-cli -p "$PORT" bgsave
e=$(date +%s%N)
echo "  BGSAVE 命令返回耗时: $(awk "BEGIN{printf \"%.2f ms\", ($e-$s)/1000000}")  <-- 只是发起，不等完成"
sleep 1
echo "  上次保存状态: $(redis-cli -p "$PORT" info persistence | grep -oP '(?<=^rdb_bgsave_in_progress:)\d+') (0=已完成)"
echo "  最后保存时间: $(redis-cli -p "$PORT" lastsave)"

echo ""
echo "########## 2. fork 阻塞实测：主线程真的会卡住 ##########"
echo "构造较大数据集..."
# 造约 200MB 数据
redis-cli -p "$PORT" flushall > /dev/null
for i in $(seq 1 40); do
  eval "redis-cli -p \"$PORT\" set bigkey:$i \"\$(head -c 5000000 /dev/urandom | base64 | head -c 5000000)\"" > /dev/null 2>&1
done
USED=$(redis-cli -p "$PORT" info memory | grep -oP '(?<=^used_memory:)\d+')
echo "  已用内存: $(awk "BEGIN{printf \"%.1f MB\", $USED/1024/1024}")"
echo "  键数量: $(redis-cli -p "$PORT" dbsize)"

echo ""
echo "  -- 测量 fork 耗时（latest_fork_usec）--"
redis-cli -p "$PORT" bgsave > /dev/null
sleep 2
echo "  上次 fork 耗时: $(redis-cli -p "$PORT" info stats | grep -oP '(?<=^latest_fork_usec:)\d+') 微秒 = $(redis-cli -p "$PORT" info stats | grep -oP '(?<=^latest_fork_usec:)\d+' | awk '{printf "%.2f ms", $1/1000}')"

echo ""
echo "########## 3. 写时复制（COW）实测：快照期间写操作会让内存涨 ##########"
echo "原理：fork 后父子共享内存页；父进程修改某页时，内核复制该页"
echo ""

# 记录基线
BEFORE=$(redis-cli -p "$PORT" info memory | grep -oP '(?<=^used_memory:)\d+')
echo "  快照前 used_memory: $(awk "BEGIN{printf \"%.1f MB\", $BEFORE/1024/1024}")"

# 启动 BGSAVE，然后立即大量写入
echo "  发起 BGSAVE 并同时写入（模拟 COW）..."
redis-cli -p "$PORT" bgsave > /dev/null &
BGPID=$!
# 立即修改大量 key，触发 COW
for i in $(seq 1 40); do
  redis-cli -p "$PORT" set bigkey:$i "modified-$i-$(date +%s%N)" > /dev/null 2>&1
done
wait $BGPID 2>/dev/null
sleep 2

AFTER=$(redis-cli -p "$PORT" info memory | grep -oP '(?<=^used_memory:)\d+')
PEAK=$(redis-cli -p "$PORT" info memory | grep -oP '(?<=^used_memory_peak:)\d+')
echo "  快照后 used_memory: $(awk "BEGIN{printf \"%.1f MB\", $AFTER/1024/1024}")"
echo "  峰值 used_memory_peak: $(awk "BEGIN{printf \"%.1f MB\", $PEAK/1024/1024}")"

echo ""
echo "########## 4. RDB 文件与压缩 ##########"
ls -lh "$DIR"/*.rdb 2>/dev/null | awk '{print "  RDB 文件: " $9 " 大小: " $5}'
echo "  rdbcompression=$(redis-cli -p "$PORT" config get rdbcompression | tail -1)"
echo "  rdbchecksum=$(redis-cli -p "$PORT" config get rdbchecksum | tail -1)"

echo ""
echo "########## 5. 自动 BGSAVE：save 配置的触发 ##########"
echo "配置 save 规则：每 10 秒有 1 次变更就保存"
redis-cli -p "$PORT" config set save "10 1" > /dev/null
echo "  save = $(redis-cli -p "$PORT" config get save | tail -1)"
BEFORE_SAVE=$(redis-cli -p "$PORT" info persistence | grep -oP '(?<=^rdb_changes_since_last_save:)\d+')
echo "  当前距上次保存的变更数: $BEFORE_SAVE"
redis-cli -p "$PORT" set trigger:test 1 > /dev/null
echo "  写入一个 key 后变更数: $(redis-cli -p "$PORT" info persistence | grep -oP '(?<=^rdb_changes_since_last_save:)\d+')"
echo "  等待 12 秒看是否自动触发..."
sleep 12
echo "  12 秒后变更数: $(redis-cli -p "$PORT" info persistence | grep -oP '(?<=^rdb_changes_since_last_save:)\d+')（回到 0 说明已自动保存）"
echo "  rdb_last_save_time: $(redis-cli -p "$PORT" info persistence | grep -oP '(?<=^rdb_last_save_time:)\d+')"

echo ""
echo "########## 6. 数据丢失窗口：RDB 会丢多少 ##########"
echo "save 10 1 意味着：最多丢失最后一次快照之后的写操作"
echo "  即最坏情况丢失约 10 秒的数据（如果 10 秒内没达到触发条件，则更久）"
echo "  实测：写入后立即 kill 进程，数据是否还在？"
redis-cli -p "$PORT" config set save "" > /dev/null
redis-cli -p "$PORT" set will:lose "this-will-be-lost" > /dev/null
echo "  写入 will:lose 后，未做快照，直接 kill -9"
PID=$(redis-cli -p "$PORT" info server | grep -oP '(?<=^process_id:)\d+')
kill -9 "$PID" 2>/dev/null
sleep 1
echo "  进程已杀。重启看数据是否还在..."

echo ""
echo "清理中..."
rm -rf "$DIR"
echo "done"
