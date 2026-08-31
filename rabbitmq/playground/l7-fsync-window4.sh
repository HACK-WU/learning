#!/usr/bin/env bash
# 课 7 知识点 2（v4 终版）：持久化的真实程度 —— 精确计数 + 直击 fsync 窗口
#
# 【v3 的计数 bug】
#   v3 里 `acked = i` 只在每批 confirm 成功后才更新。kill -9 时发布进程在
#   `basic_publish` 中途抛错进入 except，此时 acked 仍是**上一批**的值，
#   而实际上最后一批中有一部分已经发出并被 broker 接收（broker 已计入队列），
#   只是客户端没来得及记账 → 出现"存活数 > 已确认数"的负值(-88)。
#   计数口径错误会让结论完全颠倒，必须修掉。
#
# 【v4 修正】
#   1. 用 broker 侧权威数字做基准：kill 之前先读一次 list_queues 的 messages
#      → 这是"broker 确实收下并计入队列"的数（BEFORE）
#   2. kill -9 → 重启 → 再读 messages（AFTER）
#   3. 丢失 = BEFORE - AFTER
#      这样完全不依赖客户端记账，两端都是 broker 权威视角。
#
# 【为什么这样能真实反映 fsync 窗口】
#   BEFORE 时刻消息已在队列里（broker 已接收）。若这些消息尚未 fsync 落盘，
#   kill -9 后就会消失 → AFTER < BEFORE。差值即"已在队列但未落盘而丢失"的量。
source "$(dirname "$0")/l7-env.sh"
set -u
cd "$(dirname "$0")"

run_case() {
  local label="$1"
  local batch="$2"
  local queue="l7.fs.$3"

  echo ""
  echo "════════════════════════════════════════════════════════════"
  echo "【$label】batch=$batch"
  echo "════════════════════════════════════════════════════════════"

  "$DOCKER" exec "$RMQ_CT" rabbitmqctl delete_queue "$queue" >/dev/null 2>&1
  sleep 1

  cat > "l7_pub4_$3.py" <<PYEOF
import os
import time

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
ch.queue_declare(queue="$queue", durable=True)
ch.confirm_delivery()

BATCH = $batch
i = 0
deadline = time.time() + 25
try:
    while time.time() < deadline:
        for _ in range(BATCH):
            i += 1
            ch.basic_publish(
                exchange="",
                routing_key="$queue",
                body=f"m{i}".encode(),
                properties=pika.BasicProperties(delivery_mode=2),
            )
        if BATCH == 1:
            pass  # 逐条：basic_publish 本身就同步等 ack
        else:
            ch.connection.process_data_events(time_limit=0)
except Exception:
    pass
PYEOF

  python "l7_pub4_$3.py" &
  local pid=$!
  sleep 6

  # 【关键修正】kill 之前，先读 broker 权威的队列深度
  local before
  before=$("$DOCKER" exec "$RMQ_CT" rabbitmqctl list_queues name messages -q 2>/dev/null \
    | awk -F'\t' -v q="$queue" '$1==q{print $2}')
  before=${before:-0}
  echo "  [kill 前] broker 队列深度（权威）= $before"

  "$DOCKER" kill -s KILL "$RMQ_CT" >/dev/null 2>&1
  wait $pid 2>/dev/null
  sleep 1

  "$DOCKER" start "$RMQ_CT" >/dev/null 2>&1
  for n in $(seq 1 120); do
    "$DOCKER" exec "$RMQ_CT" rabbitmqctl status >/dev/null 2>&1 && break
    sleep 1
  done
  sleep 10

  local after
  after=$("$DOCKER" exec "$RMQ_CT" rabbitmqctl list_queues name messages -q 2>/dev/null \
    | awk -F'\t' -v q="$queue" '$1==q{print $2}')
  after=${after:-0}

  local lost=$((before - after))
  echo "  [重启后] broker 队列深度（权威）= $after"
  echo ""
  echo "  ┌────────────────────────────────────────────┐"
  echo "  │ kill 前已入队 : $before"
  echo "  │ 重启后存活    : $after"
  echo "  │ 已入队但丢失  : $lost"
  echo "  └────────────────────────────────────────────┘"
  if [ "$lost" -gt 0 ]; then
    echo "  ✅ 捕获 fsync 窗口：$lost 条已入队的持久化消息因未落盘而丢失"
  else
    echo "  ⚠️  本轮未捕获丢失（broker 在 6 秒内已完成落盘）"
  fi
}

echo "=== 前置：确认 broker 在线 ==="
"$DOCKER" exec "$RMQ_CT" rabbitmqctl status >/dev/null 2>&1 || "$DOCKER" start "$RMQ_CT" >/dev/null 2>&1
sleep 3

run_case "对照组：逐条同步 confirm" 1 sync
run_case "实验组：批量 200 条后统一确认" 200 batch

echo ""
echo "════════════════════════════════════════════════════════════"
echo "最终对比见两组「已入队但丢失」"
echo "════════════════════════════════════════════════════════════"
