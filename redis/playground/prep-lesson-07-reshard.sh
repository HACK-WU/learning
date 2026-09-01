#!/usr/bin/env bash
# 课 7 备课实测 3：集群伸缩（扩容/缩容）与重定向（MOVED / ASK）
set -u
CLI="redis-cli"
BASE=/tmp/redis-l07

echo "=== 1. 扩容前基线 ==="
$CLI -p 7001 cluster info | grep -E 'cluster_state|cluster_slots_assigned|cluster_known_nodes|cluster_size'
echo ""
for p in 7001 7002 7003; do
  echo "  $p dbsize = $($CLI -p $p dbsize)"
done

echo ""
echo "=== 2. 灌入一批数据（带哈希标签，便于观察迁移）==="
# 写入 2000 个 key，分散到各槽
python3 - <<'PY' > /tmp/l07-data.txt
for i in range(2000):
    print(f"SET k{i} v{i}")
PY
$CLI -c -p 7001 --pipe < /tmp/l07-data.txt 2>&1 | tail -3
sleep 1
echo "  写入后："
for p in 7001 7002 7003; do
  echo "    $p dbsize = $($CLI -p $p dbsize)"
done
echo "  总计 = $(( $($CLI -p 7001 dbsize) + $($CLI -p 7002 dbsize) + $($CLI -p 7003 dbsize) ))"

echo ""
echo "=== 3. 启动新节点 7007（作为待加入的主库）==="
mkdir -p "$BASE/7007"
cat > "$BASE/7007/redis.conf" <<EOF
port 7007
cluster-enabled yes
cluster-config-file nodes.conf
cluster-node-timeout 5000
appendonly no
save ""
daemonize yes
logfile $BASE/7007/redis.log
dir $BASE/7007
repl-diskless-sync-delay 0
EOF
redis-server "$BASE/7007/redis.conf"
for i in $(seq 1 30); do
  [ "$($CLI -p 7007 ping 2>/dev/null)" = "PONG" ] && break
  sleep 0.5
done
echo "  7007 状态: $($CLI -p 7007 ping 2>/dev/null)"
echo "  加入前槽数: $($CLI -p 7007 cluster info 2>/dev/null | grep -o 'cluster_slots_assigned:[0-9]*')"

echo ""
echo "=== 4. 加入集群（add-node，此时不持有槽）==="
$CLI --cluster add-node 127.0.0.1:7007 127.0.0.1:7001 2>&1 | tail -12
sleep 2
echo ""
echo "  加入后 cluster info: $($CLI -p 7001 cluster info | grep -o 'cluster_known_nodes:[0-9]*')"
echo "  7007 当前槽: $($CLI -p 7001 cluster nodes | grep 7007 | awk '{print $3, $9, $10, $11}')"

echo ""
echo "=== 5. 执行 reshard：迁移 1000 个槽给 7007 ==="
NEWID=$($CLI -p 7001 cluster nodes | grep 7007 | awk '{print $1}')
echo "  7007 node id = $NEWID"
echo "  开始迁移（记录耗时）..."
start=$(date +%s.%N)
$CLI --cluster reshard 127.0.0.1:7001 \
  --cluster-from all \
  --cluster-to $NEWID \
  --cluster-slots 1000 \
  --cluster-yes 2>&1 | tail -6
end=$(date +%s.%N)
echo "  迁移耗时: $(echo "$end - $start" | bc) 秒"

echo ""
echo "=== 6. 迁移后槽分布 ==="
$CLI -p 7001 cluster info | grep -E 'cluster_state|cluster_slots_assigned|cluster_size'
echo ""
$CLI -p 7001 cluster nodes | grep -E 'master' | awk '{print "  " $2, $3, $9, $10, $11, $12}'

echo ""
echo "=== 7. 数据分布验证（迁移是否搬走了数据）==="
total=0
for p in 7001 7002 7003 7007; do
  n=$($CLI -p $p dbsize 2>/dev/null)
  echo "  $p dbsize = $n"
  total=$((total + n))
done
echo "  总计 = $total （迁移前 2000，应保持一致）"

echo ""
echo "=== 8. 迁移期间的 ASK 重定向（关键实验）==="
echo "  原理：槽迁移中，部分 key 已在目标节点、部分还在源节点。"
echo "        客户端访问源节点时，若该 key 已迁走 → 返回 ASK 重定向。"
echo ""
# 手动制造迁移中间态：用 MIGRATE 搬一个 key，观察 ASK
echo "  -- 找一个新节点上的 key --"
sample=$($CLI -p 7007 --scan --count 10 2>/dev/null | head -3)
echo "    7007 上采样 key: $sample"
echo ""
echo "  -- 用 MIGRATE 把 7007 的某个槽标记迁移中，观察 ASK --"
SLOT=$($CLI -p 7001 cluster keyslot k1)
echo "    k1 的槽 = $SLOT"
# 查该槽当前归属
owner=$($CLI -p 7001 cluster nodes | awk -v s="$SLOT" '
  $3=="master" || $3 ~ /master/ {
    for(i=9;i<=NF;i++){
      if($i ~ /^[0-9]+-[0-9]+$/){split($i,a,"-"); if(s>=a[1]&&s<=a[2]) print $2}
      else if($i ~ /^[0-9]+$/){if(s==$i) print $2}
    }
  }')
echo "    槽 $SLOT 归属: $owner"

echo ""
echo "  -- 用 redis-cli -c 访问时，观察是否出现重定向提示 --"
echo "    执行: redis-cli -c -p 7001 get k1"
$CLI -c -p 7001 get k1 2>&1

echo ""
echo "=== 9. MOVED vs ASK 的区别（用 -c 观察自动跟随）==="
echo "  --- 场景 A：访问不属于 7001 的 key（应 MOVED）---"
$CLI -p 7001 get k1 2>&1 | head -2
echo ""
echo "  --- 场景 B：用 -c 自动跟随 ---"
$CLI -c -p 7001 get k1 2>&1

echo ""
echo "=== 10. 缩容：把 7007 的槽迁回并删除节点 ==="
echo "  第 1 步：把 7007 的 1000 个槽迁回 7001"
start=$(date +%s.%N)
$CLI --cluster reshard 127.0.0.1:7001 \
  --cluster-from $NEWID \
  --cluster-to $($CLI -p 7001 cluster nodes | grep 7001 | awk '{print $1}') \
  --cluster-slots 1000 \
  --cluster-yes 2>&1 | tail -4
end=$(date +%s.%N)
echo "  迁移耗时: $(echo "$end - $start" | bc) 秒"
sleep 2
echo ""
echo "  第 2 步：检查 7007 是否已空"
$CLI -p 7001 cluster nodes | grep 7007 | awk '{print "  7007:", $3, $9, $10, $11}'
echo "  7007 dbsize = $($CLI -p 7007 dbsize 2>/dev/null)"

echo ""
echo "  第 3 步：删除节点"
$CLI --cluster del-node 127.0.0.1:7001 $NEWID 2>&1 | tail -4
sleep 1
echo "  删除后 known_nodes = $($CLI -p 7001 cluster info | grep -o 'cluster_known_nodes:[0-9]*')"

echo ""
echo "=== 11. 最终状态校验 ==="
$CLI -p 7001 cluster info | grep -E 'cluster_state|cluster_slots_assigned|cluster_slots_ok|cluster_size|cluster_known_nodes'
total=0
for p in 7001 7002 7003; do
  n=$($CLI -p $p dbsize 2>/dev/null)
  echo "  $p dbsize = $n"
  total=$((total + n))
done
echo "  总计 = $total"

echo ""
echo "=== 完成 ==="
