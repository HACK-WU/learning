#!/usr/bin/env bash
# 排查：为什么 durable=False 的交换机活过了 kill -9 宕机？
#
# 官方文档（AMQP concepts / Exchanges）明确说：
#   "Exchanges can be durable or transient. Durable exchanges survive broker
#    restart, transient exchanges do not (they have to be redeclared...)"
# 但本机 4.3.5 实测相反：l7.ex.noex (durable=False) 活过了 docker kill -s KILL。
#
# 关键线索（官方 Exchanges 文档原文）：
#   "Further in the 4.x series, support for transient (non-durable) entities
#    will be removed when Khepri becomes the only supported metadata store"
# 假设 H：4.3 已用 Khepri 作为元数据存储，所有元数据（无论 durable 与否）
#        都进 Raft 日志并落盘 → durable=False 的交换机照样活过宕机。
#
# 本脚本验证：
#   1. 元数据存储是不是 Khepri
#   2. 最小化干净复现：只建一个 transient 交换机，不带任何队列/绑定/消息
#   3. 真实 kill -9 后看它还在不在
source "$(dirname "$0")/l7-env.sh"
set -u

echo "=== 1. 元数据存储类型（是否 Khepri）==="
"$DOCKER" exec "$RMQ_CT" rabbitmqctl status 2>&1 | grep -iE "khepri|mnesia|metadata" | head -10

echo ""
echo "=== 2. 关键配置项 ==="
"$DOCKER" exec "$RMQ_CT" rabbitmqctl environment 2>&1 | grep -iE "khepri|metadata_store" | head -10

echo ""
echo "=== 3. 特性开关：是否有 transient 相关弃用 ==="
"$DOCKER" exec "$RMQ_CT" rabbitmqctl environment 2>&1 | grep -iE "deprecated" | head -10

echo ""
echo "=== 4. 干净环境准备：删除所有 l7. 残留 ==="
for q in l7.q.all l7.q.noex l7.q.rmsg; do
  "$DOCKER" exec "$RMQ_CT" rabbitmqctl delete_queue "$q" >/dev/null 2>&1
done
for e in l7.ex.all l7.ex.noex l7.ex.rmsg; do
  "$DOCKER" exec -e RABBITMQADMIN_USERNAME="$RMQ_USER" -e RABBITMQADMIN_PASSWORD="$RMQ_PASS" \
    "$RMQ_CT" rabbitmqadmin delete exchange --name "$e" --non-interactive >/dev/null 2>&1
done
echo "  已清理；当前 l7. 交换机："
"$DOCKER" exec "$RMQ_CT" rabbitmqctl list_exchanges name -q 2>&1 | grep l7 || echo "  （无）"

echo ""
echo "=== 5. 最小化复现：只声明一个 transient 交换机，无队列无绑定无消息 ==="
cd "$(dirname "$0")"
python - <<'PY' 2>&1
import os
import pika

HOST = os.environ.get("RMQ_HOST", "127.0.0.1")
PORT = int(os.environ.get("RMQ_PORT", "5672"))
USER = os.environ.get("RMQ_USER", "learn")
PASS = os.environ.get("RMQ_PASS", "learn123")

conn = pika.BlockingConnection(
    pika.ConnectionParameters(host=HOST, port=PORT,
                              credentials=pika.PlainCredentials(USER, PASS))
)
ch = conn.channel()
ch.exchange_declare(exchange="l7.mini.transient", exchange_type="direct", durable=False)
ch.exchange_declare(exchange="l7.mini.durable", exchange_type="direct", durable=True)
conn.close()
print("  已声明：l7.mini.transient(durable=False) 与 l7.mini.durable(durable=True)")
PY
"$DOCKER" exec "$RMQ_CT" rabbitmqctl list_exchanges name durable -q 2>&1 | grep "l7.mini"

echo ""
echo "=== 6. 真实宕机（docker kill -s KILL），无任何优雅关机机会 ==="
"$DOCKER" kill -s KILL "$RMQ_CT" >/dev/null 2>&1
sleep 2
"$DOCKER" start "$RMQ_CT" >/dev/null 2>&1
for i in $(seq 1 120); do
  if "$DOCKER" exec "$RMQ_CT" rabbitmqctl status >/dev/null 2>&1; then
    echo "  broker 已就绪（等待 ${i} 秒）"
    break
  fi
  sleep 1
done
sleep 5

echo ""
echo "=== 7. 宕机后：两个 mini 交换机还在吗？==="
"$DOCKER" exec "$RMQ_CT" rabbitmqctl list_exchanges name durable -q 2>&1 | grep "l7.mini" \
  || echo "  ❌ 两个都不在了（与官方文档一致）"
