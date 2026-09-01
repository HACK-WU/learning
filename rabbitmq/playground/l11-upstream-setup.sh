#!/usr/bin/env bash
# ============================================================================
# 课 11：启动独立"上游站点"容器（用于 Shovel / Federation 演示）
# ============================================================================
# 设计意图：
#   演示 Shovel/Federation 要解决的核心问题是【跨信任边界】——
#   两个 broker 无法组成同一集群（cookie 不同、各自独立），
#   但仍需要交换消息。
#
#   最初尝试用既有容器 rabbitmq-learn 当上游，但它在【不同的 docker 网络】，
#   集群容器无法访问。与其打通两个网络（有污染既有环境的风险），
#   不如新建一个独立上游容器：
#     - 连同一个网络 rabbitmq-cluster → 网络可达
#     - 使用【不同的 Erlang cookie】   → 信任边界独立，无法加入集群
#     - 完全不触碰 rabbitmq-learn     → 前 10 课环境零风险
#
#   这样"网络可达但信任独立"的状态，正是 Federation/Shovel 的典型场景。
# ============================================================================
set -euo pipefail

NET='rabbitmq-cluster'
IMAGE='rabbitmq:4.3-management'
COOKIE='learn-cluster-cookie-2026'      # 集群用的 cookie
UPSTREAM_COOKIE='upstream-different-cookie-2026'   # 故意不同

echo "=== [1/4] 启动上游站点容器 rmq-upstream ==="
if docker ps -a --format '{{.Names}}' | grep -qx 'rmq-upstream'; then
  echo "  已存在，先删除重建"
  docker rm -f rmq-upstream >/dev/null 2>&1 || true
fi

# 注意：不要设 RABBITMQ_ERLANG_COOKIE。
# 实测发现显式设置该变量会导致容器内 cookie 文件权限错误：
#   "Error when reading /var/lib/rabbitmq/.erlang.cookie: eacces"
# 不设置时容器自动生成随机 cookie，天然与集群不同——
# 这正好符合本演示"信任边界独立"的意图。
docker run -d \
  --name rmq-upstream \
  --hostname rmq-upstream \
  --network "$NET" \
  -p 5691:5672 \
  -p 15691:15672 \
  -e RABBITMQ_DEFAULT_USER=learn \
  -e RABBITMQ_DEFAULT_PASS=learn123 \
  -e RABBITMQ_NODENAME=rabbit@rmq-upstream \
  "$IMAGE" >/dev/null
echo "  已启动（AMQP 5691 / UI 15691，cookie 由容器随机生成）"

echo ""
echo "=== [2/4] 等待就绪 ==="
i=0
READY=0
while [ $i -lt 40 ]; do
  if docker exec rmq-upstream rabbitmqctl await_startup --timeout 5 >/dev/null 2>&1; then
    echo "  就绪（第 $((i*3)) 秒）"
    READY=1
    break
  fi
  sleep 3
  i=$((i+1))
done
if [ "$READY" -ne 1 ]; then
  echo "  ⚠️ 超时未就绪，请检查：docker logs rmq-upstream"
fi

echo ""
echo "=== [3/4] 验证 cookie 差异（这是无法组集群的原因） ==="
echo "  集群节点 rmq1 cookie:  $(docker exec rmq1 cat /var/lib/rabbitmq/.erlang.cookie 2>/dev/null | head -c 12)..."
echo "  上游 upstream cookie:  $(docker exec rmq-upstream cat /var/lib/rabbitmq/.erlang.cookie 2>/dev/null | head -c 12)..."
echo "  → 两者不同，因此【无法加入同一集群】"

echo ""
echo "=== [4/4] 验证网络可达性与集群独立性 ==="
echo "  上游节点列表（应只有自己）："
docker exec rmq-upstream rabbitmqctl cluster_status 2>&1 | sed -n '/Running Nodes/,/^$/p' | head -5

echo ""
echo "  从 rmq1 测试到 rmq-upstream 的网络连通性："
docker exec rmq1 bash -c 'exec 3<>/dev/tcp/rmq-upstream/5672 && echo "  ✅ 5672 可达" || echo "  ❌ 5672 不可达"'

echo ""
echo "============================================================================"
echo "上游站点就绪："
echo "  容器        : rmq-upstream"
echo "  容器内地址  : rmq-upstream:5672（集群网络内可直接解析）"
echo "  宿主映射    : localhost:5691 / UI 15691"
echo "  与集群关系  : 网络可达，但 cookie 不同，无法组集群"
echo ""
echo "清理：docker rm -f rmq-upstream"
echo "============================================================================"
