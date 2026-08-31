#!/usr/bin/env bash
# 精确复核：非持久化交换机（durable=False）在真实宕机后到底还在不在？
#
# 背景：l7-run-persist3.sh 真实宕机后，B 组 l7.ex.noex 显示"存在=True"。
#      但这里有个陷阱：check() 之前，脚本可能通过某种方式重新声明了它？
#      或者 rabbitmqctl list_exchanges 的 -q 输出包含了别的东西？
#
# 本脚本做三件独立核验：
#   1. 用 HTTP API 直接查 l7.ex.noex 是否存在（权威来源）
#   2. 检查它的 durable 属性
#   3. 检查绑定关系是否还在（交换机若在，绑定应在；若绑定没了说明交换机是新重建的）
source "$(dirname "$0")/l7-env.sh"
set -u

echo "=== 1. rabbitmqctl list_exchanges 原始输出（grep l7）==="
"$DOCKER" exec "$RMQ_CT" rabbitmqctl list_exchanges name durable auto_delete -q 2>&1 | grep l7

echo ""
echo "=== 2. HTTP API 权威查询：/api/exchanges/%2F ==="
curl -s -u "$RMQ_USER:$RMQ_PASS" "$RMQ_API/exchanges/%2F" \
  | python -c "
import sys, json
try:
    data = json.load(sys.stdin)
except Exception as e:
    print('  解析失败:', e); sys.exit()
found = [e for e in data if e.get('name','').startswith('l7.')]
if not found:
    print('  未找到任何 l7. 交换机')
for e in sorted(found, key=lambda x: x['name']):
    print(f\"  {e['name']:14s} type={e.get('type'):8s} durable={e.get('durable')} auto_delete={e.get('auto_delete')}\")
"

echo ""
echo "=== 3. 绑定关系（看非持久化交换机的绑定是否幸存）==="
"$DOCKER" exec "$RMQ_CT" rabbitmqctl list_bindings source_name destination_name routing_key -q 2>&1 | grep l7

echo ""
echo "=== 4. 关键判定：不重新声明，直接向 l7.ex.noex 发消息，看是否被路由到队列 ==="
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
# 只声明队列（durable），绝不重新声明交换机 —— 若交换机已被宕机抹掉，这里会 404
ch.queue_declare(queue="l7.q.noex", durable=True)
try:
    ch.basic_publish(
        exchange="l7.ex.noex",
        routing_key="rk",
        body=b"probe-after-kill",
        properties=pika.BasicProperties(delivery_mode=2),
    )
    print("  向 l7.ex.noex 发布：未报错（交换机仍在，或 AMQP 异步未立即报错）")
except Exception as exc:
    print(f"  发布异常：{type(exc).__name__}: {exc}")

# 强制一次网络往返，让异步错误浮出水面
try:
    ch.queue_declare(queue="l7.q.noex", durable=True, passive=True)
    print("  passive 声明成功（交换机未被判定为缺失）")
except Exception as exc:
    print(f"  passive 声明异常：{type(exc).__name__}: {exc}")
conn.close()
PY

echo ""
echo "=== 5. 看消息到底有没有进队列（是否路由成功）==="
"$DOCKER" exec "$RMQ_CT" rabbitmqctl list_queues name messages -q 2>&1 | grep l7
