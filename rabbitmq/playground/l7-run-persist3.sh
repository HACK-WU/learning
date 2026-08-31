#!/usr/bin/env bash
# 课 7 知识点 1 实测（v3 终版）：三层持久化 + 真实强制宕机
#
# 【两次方法错误的教训】
#  v1 用 `docker restart`：优雅关机（SIGTERM），broker 有落盘机会，
#     连 durable=False 的交换机都活过重启 → 测不出差异。
#  v2 用 `pkill -9 -f beam.smp`：broker 在容器内 PID=1，Linux 不允许 kill -9 杀 PID 1，
#     进程根本没死，uptime 连续 94 秒从未中断 → 三组全"存活"是假象。
#  v3 改用 `docker kill -s KILL`：直接杀容器主进程（等价于断电），
#     再用 `docker start` 拉起。这是模拟真实宕机的正确手段。
#
# 判断宕机是否真实发生的硬指标：容器 RestartCount / StartedAt 变化 + uptime 归零重算。
source "$(dirname "$0")/l7-env.sh"
set -u
cd "$(dirname "$0")"

echo "############ 阶段 0：清理上一轮残留 ############"
for q in l7.q.all l7.q.noex l7.q.rmsg; do
  "$DOCKER" exec "$RMQ_CT" rabbitmqctl delete_queue "$q" >/dev/null 2>&1 && echo "  已删队列 $q"
done
for e in l7.ex.all l7.ex.noex l7.ex.rmsg; do
  "$DOCKER" exec -e RABBITMQADMIN_USERNAME="$RMQ_USER" -e RABBITMQADMIN_PASSWORD="$RMQ_PASS" \
    "$RMQ_CT" rabbitmqadmin delete exchange --name "$e" --non-interactive >/dev/null 2>&1 \
    && echo "  已删交换机 $e"
done

echo ""
echo "############ 阶段 1：构建三组对照 ############"
python l7-persist.py build 2>&1 | grep -E "重启前|【"

echo ""
echo "############ 阶段 1.5：记录宕机前的 uptime（作为对照）############"
BEFORE=$("$DOCKER" inspect -f '{{.State.StartedAt}}' "$RMQ_CT" 2>/dev/null)
UPTIME_BEFORE=$("$DOCKER" exec "$RMQ_CT" rabbitmqctl status 2>/dev/null | grep -A1 "Uptime" | grep -oE '[0-9]+' | head -1)
echo "  宕机前 启动时间=$BEFORE  uptime=${UPTIME_BEFORE}s"

echo ""
echo "############ 阶段 2：真实强制宕机（docker kill -s KILL）############"
"$DOCKER" kill -s KILL "$RMQ_CT" >/dev/null 2>&1
echo "  已 docker kill -s KILL（等价于断电，无落盘机会）"
sleep 2

if "$DOCKER" exec "$RMQ_CT" rabbitmqctl status >/dev/null 2>&1; then
  echo "  ❌ 容器仍在运行，宕机失败！请检查"
  exit 1
else
  echo "  ✅ 确认容器已停止"
fi

"$DOCKER" start "$RMQ_CT" >/dev/null 2>&1
echo "  已 start，等待就绪..."

for i in $(seq 1 120); do
  if "$DOCKER" exec "$RMQ_CT" rabbitmqctl status >/dev/null 2>&1; then
    echo "  broker 已就绪（等待 ${i} 秒）"
    break
  fi
  sleep 1
done

# 等待队列恢复（durable 队列要从磁盘加载索引，需要时间）
echo "  额外等待 8 秒，确保持久队列从磁盘恢复完成..."
sleep 8

echo ""
echo "############ 阶段 2.5：确认宕机真实发生（uptime 应远小于宕机前）############"
AFTER=$("$DOCKER" inspect -f '{{.State.StartedAt}}' "$RMQ_CT" 2>/dev/null)
UPTIME_AFTER=$("$DOCKER" exec "$RMQ_CT" rabbitmqctl status 2>/dev/null | grep -A1 "Uptime" | grep -oE '[0-9]+' | head -1)
echo "  宕机后 启动时间=$AFTER  uptime=${UPTIME_AFTER}s"
if [ "$BEFORE" != "$AFTER" ]; then
  echo "  ✅ 启动时间已变化，确认真实重启"
else
  echo "  ⚠️  启动时间未变化，可能未真正重启"
fi

echo ""
echo "############ 阶段 3：检查真实宕机后的存活情况 ############"
python l7-persist.py check 2>&1 | grep -E "重启后|【"
