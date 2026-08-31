#!/usr/bin/env bash
# 课 7 知识点 1 实测（修正版）：三层持久化 + 强制宕机对照
#
# 【为什么必须换掉 docker restart】
# 上一版用 `docker restart` = 优雅关机（SIGTERM），broker 会在退出前把所有元数据
# （含 durable=False 的交换机/队列）落盘，导致 B 组「交换机非持久化」也活过了重启，
# 得出与生产实际相反的结论。真实宕机（断电 / OOM / kill -9）没有这个落盘机会。
# 故本脚本改用 kill -9 强杀容器进程，再启动，模拟真实崩溃。
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
echo "############ 阶段 1：构建三组对照（重启前）############"
python l7-persist.py build 2>&1

echo ""
echo "############ 阶段 2：强制宕机（kill -9，非优雅关机）############"
# 找到容器内 rabbitmq 主进程并强杀，模拟断电/OOM
"$DOCKER" exec "$RMQ_CT" bash -c "pkill -9 -f beam.smp" 2>&1 | head -3
echo "已 kill -9 broker 主进程（模拟断电，不给落盘机会）"
sleep 3

# 容器因主进程退出而停止，重新启动
"$DOCKER" start "$RMQ_CT" >/dev/null 2>&1
echo "已重新 start 容器，等待就绪..."

for i in $(seq 1 90); do
  if "$DOCKER" exec "$RMQ_CT" rabbitmqctl status >/dev/null 2>&1; then
    echo "broker 已就绪（等待 ${i} 秒）"
    break
  fi
  sleep 1
done
sleep 5

echo ""
echo "############ 阶段 3：检查强制宕机后的存活情况 ############"
python l7-persist.py check 2>&1
