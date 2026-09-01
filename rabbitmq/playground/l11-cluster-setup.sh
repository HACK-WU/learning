#!/usr/bin/env bash
# ============================================================================
# 课 11：搭建三节点 RabbitMQ 集群（4.3.5）
# ============================================================================
# 设计原则：
#   - 完全独立于既有容器 rabbitmq-learn（前 10 课环境），零干扰
#   - 独立 docker 网络 rabbitmq-cluster，互不污染
#   - 端口段避开已占用的 5672/15672：
#       rmq1: AMQP 5681, UI 15681
#       rmq2: AMQP 5682, UI 15682
#       rmq3: AMQP 5683, UI 15683
#   - 使用与既有环境相同的镜像 rabbitmq:4.3-management，版本一致
#   - 共享同一 Erlang cookie，这是节点互信的前提
#
# 风险说明：
#   - 只创建新的容器/网络，不删除、不修改 rabbitmq-learn
#   - 结束后可用 teardown 脚本整体清理
# ============================================================================
set -euo pipefail

COOKIE='learn-cluster-cookie-2026'
IMAGE='rabbitmq:4.3-management'
NET='rabbitmq-cluster'
ERLANG_START='-rabbitmq_stream tcp_listeners_sup [{{0,0,0,0},5552}]'

echo "=== [1/6] 创建独立网络 $NET ==="
if docker network inspect "$NET" >/dev/null 2>&1; then
  echo "  网络已存在，跳过"
else
  docker network create "$NET" >/dev/null
  echo "  已创建"
fi

echo ""
echo "=== [2/6] 拉取/确认镜像 $IMAGE ==="
docker image inspect "$IMAGE" >/dev/null 2>&1 && echo "  镜像已存在" || docker pull "$IMAGE"

# ---------------------------------------------------------------------------
# 启动三个节点
# ---------------------------------------------------------------------------
start_node() {
  local name=$1 amqp=$2 ui=$3
  echo ""
  echo "=== [3/6] 启动节点 $name (AMQP $amqp / UI $ui) ==="
  if docker ps -a --format '{{.Names}}' | grep -qx "$name"; then
    echo "  容器已存在，先删除再重建"
    docker rm -f "$name" >/dev/null 2>&1 || true
  fi
  docker run -d \
    --name "$name" \
    --hostname "$name" \
    --network "$NET" \
    -p "${amqp}:5672" \
    -p "${ui}:15672" \
    -e RABBITMQ_ERLANG_COOKIE="$COOKIE" \
    -e RABBITMQ_DEFAULT_USER=learn \
    -e RABBITMQ_DEFAULT_PASS=learn123 \
    -e RABBITMQ_NODENAME="rabbit@${name}" \
    "$IMAGE" >/dev/null
  echo "  已启动"
}

start_node rmq1 5681 15681
start_node rmq2 5682 15682
start_node rmq3 5683 15683

# ---------------------------------------------------------------------------
# 等待节点就绪
# ---------------------------------------------------------------------------
echo ""
echo "=== [4/6] 等待三个节点就绪（最多 180 秒） ==="
wait_ready() {
  local name=$1
  local i=0
  while [ $i -lt 60 ]; do
    if docker exec "$name" rabbitmqctl await_startup --timeout 5 >/dev/null 2>&1; then
      echo "  $name 就绪（第 $((i*3)) 秒）"
      return 0
    fi
    sleep 3
    i=$((i+1))
  done
  echo "  $name 超时未就绪！"
  return 1
}
wait_ready rmq1
wait_ready rmq2
wait_ready rmq3

# ---------------------------------------------------------------------------
# 组建集群：rmq2 / rmq3 加入 rmq1
# ---------------------------------------------------------------------------
echo ""
echo "=== [5/6] 组建集群 ==="
for n in rmq2 rmq3; do
  echo "  --- $n 加入 rabbit@rmq1 ---"
  docker exec "$n" rabbitmqctl stop_app
  docker exec "$n" rabbitmqctl reset
  docker exec "$n" rabbitmqctl join_cluster rabbit@rmq1 2>&1 | tail -2
  docker exec "$n" rabbitmqctl start_app
done

echo ""
echo "=== [6/6] 验证集群状态 ==="
docker exec rmq1 rabbitmqctl cluster_status 2>&1 | head -30

echo ""
echo "============================================================================"
echo "集群搭建完成。访问："
echo "  rmq1 UI: http://localhost:15681  (learn / learn123)"
echo "  rmq2 UI: http://localhost:15682"
echo "  rmq3 UI: http://localhost:15683"
echo "  AMQP  : localhost:5681 / 5682 / 5683"
echo ""
echo "清理：bash playground/l11-cluster-teardown.sh"
echo "============================================================================"
