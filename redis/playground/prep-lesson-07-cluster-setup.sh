#!/usr/bin/env bash
# 课 7 备课实测 1：搭建 3 主 3 从集群，观察槽分配
# 端口：7001-7003 主，7004-7006 从；集群总线端口 17001-17006
set -u

BASE=/tmp/redis-l07
CLI="redis-cli"

echo "=== 0. 清理上轮 6401/6402 残留（课 6 遗留）==="
for p in 6401 6402; do
  if $CLI -p $p ping >/dev/null 2>&1; then
    $CLI -p $p shutdown nosave 2>/dev/null && echo "  已关闭 $p"
  fi
done
sleep 1

echo ""
echo "=== 1. 清理本轮环境 ==="
# 只杀本轮目录相关的进程
for p in 7001 7002 7003 7004 7005 7006; do
  $CLI -p $p shutdown nosave 2>/dev/null
done
sleep 1
rm -rf "$BASE"
mkdir -p "$BASE"
echo "  工作目录: $BASE"

echo ""
echo "=== 2. 启动 6 个节点（cluster-enabled）==="
for p in 7001 7002 7003 7004 7005 7006; do
  mkdir -p "$BASE/$p"
  cat > "$BASE/$p/redis.conf" <<EOF
port $p
cluster-enabled yes
cluster-config-file nodes.conf
cluster-node-timeout 5000
appendonly no
save ""
daemonize yes
logfile $BASE/$p/redis.log
dir $BASE/$p
repl-diskless-sync-delay 0
EOF
  redis-server "$BASE/$p/redis.conf"
done
echo "  已发起启动，等待就绪..."

wait_ready() {
  local p=$1 i
  for i in $(seq 1 40); do
    if [ "$($CLI -p $p ping 2>/dev/null)" = "PONG" ]; then return 0; fi
    sleep 0.5
  done
  return 1
}

all_up=1
for p in 7001 7002 7003 7004 7005 7006; do
  if wait_ready $p; then
    echo "  $p 就绪"
  else
    echo "  $p 未就绪！"; all_up=0
  fi
done

if [ "$all_up" = "0" ]; then
  echo ""
  echo "!!! 有节点未就绪，查看日志："
  for p in 7001 7002 7003 7004 7005 7006; do tail -5 "$BASE/$p/redis.log"; done
  exit 1
fi

echo ""
echo "=== 3. 创建集群（3 主 3 从）==="
$CLI --cluster create 127.0.0.1:7001 127.0.0.1:7002 127.0.0.1:7003 \
                      127.0.0.1:7004 127.0.0.1:7005 127.0.0.1:7006 \
                      --cluster-replicas 1 --cluster-yes 2>&1 | tail -40

echo ""
echo "=== 4. 等待集群状态收敛 ==="
for i in $(seq 1 30); do
  state=$($CLI -p 7001 cluster info 2>/dev/null | grep -o 'cluster_state:[a-z]*' | cut -d: -f2)
  if [ "$state" = "ok" ]; then break; fi
  sleep 0.5
done
echo "  cluster_state = $state"

echo ""
echo "=== 5. 槽分配总览 ==="
$CLI -p 7001 cluster info | grep -E 'cluster_state|cluster_slots_assigned|cluster_slots_ok|cluster_slots_pfail|cluster_slots_fail|cluster_known_nodes|cluster_size'

echo ""
echo "=== 6. 各节点角色与槽区间 ==="
for p in 7001 7002 7003 7004 7005 7006; do
  info=$($CLI -p $p cluster info 2>/dev/null)
  role=$(echo "$info" | grep -o 'myself,[a-z]*' | cut -d, -f2)
  slots=$(echo "$info" | grep -o 'myself,[a-z]*,[^ ]*' | head -1 | cut -d, -f9-)
  nodeid=$($CLI -p $p cluster myid 2>/dev/null)
  # 用 cluster nodes 取本节点槽区间
  own=$($CLI -p $p cluster nodes 2>/dev/null | grep "$p" | grep -v '^$' | awk '{print $1, $3, $9, $10, $11}')
  printf "  %s  %s\n" "$p" "$own"
done

echo ""
echo "=== 7. cluster nodes 原始输出（7001 视角）==="
$CLI -p 7001 cluster nodes

echo ""
echo "=== 8. 槽数校验 ==="
total=$($CLI -p 7001 cluster nodes | awk '{for(i=9;i<=NF;i++) if($i ~ /^[0-9]+-[0-9]+$/) {split($i,a,"-"); s+=a[2]-a[1]+1; c++} else if ($i ~ /^[0-9]+$/) {s+=1; c++}} END {print c" 个区间, 共 "s" 个槽"}')
echo "  $total"

echo ""
echo "=== 完成 ==="
