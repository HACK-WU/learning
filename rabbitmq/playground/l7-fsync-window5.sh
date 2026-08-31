#!/usr/bin/env bash
# 课 7 知识点 2（v5 终版）：先停发布 → 再读权威值 → 再 kill
#
# 【v4 为什么还是负值】
#   v4 在"发布仍在高速写入"的同时读 list_queues。但 list_queues 是**异步统计**，
#   返回的深度滞后于真实值几秒（对 13000+ 条的队列尤其明显）。
#   于是：kill 前读到的是滞后旧值(13646)，而实际已经写到 13805+
#   → kill 后读到 13805，反而比"kill 前"大 → 负丢失。测量方法本身有问题。
#
# 【v5 修正：三段式，消除读写竞态】
#   阶段 A：发布 6 秒（持续写入）
#   阶段 B：【关键】先 SIGSTOP 暂停发布进程 → 等待 2 秒让统计追平 → 读权威值 BEFORE
#           （此时不再有新消息写入，统计值稳定可靠）
#   阶段 C：kill -9 broker → 重启 → 读 AFTER
#           丢失 = BEFORE - AFTER
#   这样 BEFORE 是"停止写入后的稳定真实值"，无竞态。
source "$(dirname "$0")/l7-env.sh"
set -u
cd "$(dirname "$0")"

run_case() {
  local label="$1"
  local batch="$2"
  local queue="l7.fs5.$3"

  echo ""
  echo "════════════════════════════════════════════════════════════"
  echo "【$label】batch=$batch"
  echo "════════════════════════════════════════════════════════════"

  "$DOCKER" exec "$RMQ_CT" rabbitmqctl delete_queue "$queue" >/dev/null 2>&1
  sleep 1

  cat > "l7_pub5_$3.py" <<PYEOF
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
deadline = time.time() + 40
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
        if BATCH > 1:
            ch.connection.process_data_events(time_limit=0)
except Exception:
    pass
PYEOF

  python "l7_pub5_$3.py" &
  local pid=$!

  echo "  阶段 A：持续发布 6 秒..."
  sleep 6

  echo "  阶段 B：暂停发布进程（SIGSTOP），等待统计追平..."
  kill -STOP "$pid" 2>/dev/null
  sleep 3   # 给 broker 统计与内部缓冲时间追平

  local before
  before=$("$DOCKER" exec "$RMQ_CT" rabbitmqctl list_queues name messages -q 2>/dev/null \
    | awk -F'\t' -v q="$queue" '$1==q{print $2}')
  before=${before:-0}
  echo "  [停止写入后] 队列深度 BEFORE = $before"

  echo "  阶段 C：kill -9 broker..."
  "$DOCKER" kill -s KILL "$RMQ_CT" >/dev/null 2>&1
  kill -CONT "$pid" 2>/dev/null
  wait $pid 2>/dev/null

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
  echo "  [重启后] 队列深度 AFTER = $after"
  echo ""
  echo "  ┌────────────────────────────────────────────┐"
  echo "  │ 停止写入后已入队 : $before"
  echo "  │ 重启后存活       : $after"
  echo "  │ 已入队但丢失     : $lost"
  echo "  └────────────────────────────────────────────┘"
  if [ "$lost" -gt 0 ]; then
    echo "  ✅ 捕获 fsync 窗口：$lost 条已入队消息因未落盘丢失"
  elif [ "$lost" -lt 0 ]; then
    echo "  ❌ 仍为负值，测量方法仍有问题"
  else
    echo "  ⚠️  零丢失：本环境下 broker 停止写入后已全部落盘"
  fi
}

echo "=== 前置：确认 broker 在线 ==="
"$DOCKER" exec "$RMQ_CT" rabbitmqctl status >/dev/null 2>&1 || "$DOCKER" start "$RMQ_CT" >/dev/null 2>&1
sleep 3

run_case "对照组：逐条同步 confirm" 1 sync
run_case "实验组：批量 200 条后统一确认" 200 batch

echo ""
echo "════════════════════════════════════════════════════════════"
echo "对比结论见两组「已入队但丢失」"
echo "════════════════════════════════════════════════════════════"
