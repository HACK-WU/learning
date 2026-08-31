#!/usr/bin/env bash
# 课 7 知识点 2（v3）：用「批量异步 confirm」制造真正的 fsync 丢失窗口
#
# 【为什么前两版测出零丢失】
#   v2 用 pika BlockingChannel + confirm_delivery：每发一条都同步等一次 ack
#   （课 6 P0-3 已证明：每条耗时 ≈ 1 个 RTT）。这种"发一条等一条"的节奏
#   给了 broker 充裕时间把消息 fsync 落盘，所以 kill -9 时已无未落盘积压
#   → 测出零丢失是实验节奏造成的假象，不是"持久化绝对安全"的证据。
#
# 【v3 设计：制造窗口】
#   关键改动：发布端**批量发送、延迟确认**——
#     连续发 N 条（不等 ack）→ 再统一等这批的 confirm
#   这样 broker 侧会瞬时积压一批"已收到、已计入 ack，但还没来得及 fsync"的消息。
#   在统一 confirm 刚返回、fsync 尚未完成时 kill -9，即可捕捉丢失窗口。
#
# 【对照】同时跑一个"逐条同步 confirm"的对照组（同 v2 节奏），
#         两组对比可证明：丢失窗口与发布节奏相关，而非"持久化绝对安全"。
source "$(dirname "$0")/l7-env.sh"
set -u
cd "$(dirname "$0")"

run_case() {
  local label="$1"
  local batch="$2"   # batch=1 → 逐条同步；batch=200 → 批量异步
  local queue="l7.fsync.$3"

  echo ""
  echo "════════════════════════════════════════════════════════"
  echo "【$label】batch=$batch"
  echo "════════════════════════════════════════════════════════"

  "$DOCKER" exec "$RMQ_CT" rabbitmqctl delete_queue "$queue" >/dev/null 2>&1
  rm -f "l7_counter_$3.txt"

  cat > "l7_pub_$3.py" <<PYEOF
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
acked = 0
i = 0
deadline = time.time() + 25
try:
    while time.time() < deadline:
        # 连续发 BATCH 条，中间不等 ack
        for _ in range(BATCH):
            i += 1
            ch.basic_publish(
                exchange="",
                routing_key="$queue",
                body=f"m{i}".encode(),
                properties=pika.BasicProperties(delivery_mode=2),
            )
        # 统一等这批的 confirm（阻塞直到全部 ack 或抛错）
        ch.connection.process_data_events(time_limit=0)
        # 到这里说明这批已被 broker 确认接收
        acked = i
except Exception as exc:
    pass
finally:
    with open("l7_counter_$3.txt", "w", encoding="utf-8") as f:
        f.write(f"{acked}\n")
PYEOF

  python "l7_pub_$3.py" &
  local pid=$!
  sleep 6   # 让发布进入稳定状态

  "$DOCKER" kill -s KILL "$RMQ_CT" >/dev/null 2>&1
  wait $pid 2>/dev/null
  sleep 1

  local ack=0
  [ -f "l7_counter_$3.txt" ] && ack=$(sed -n 1p "l7_counter_$3.txt")

  "$DOCKER" start "$RMQ_CT" >/dev/null 2>&1
  for n in $(seq 1 120); do
    "$DOCKER" exec "$RMQ_CT" rabbitmqctl status >/dev/null 2>&1 && break
    sleep 1
  done
  sleep 8

  local survived
  survived=$("$DOCKER" exec "$RMQ_CT" rabbitmqctl list_queues name messages -q 2>/dev/null \
    | awk -F'\t' -v q="$queue" '$1==q{print $2}')
  survived=${survived:-0}

  local lost=$((ack - survived))
  echo "  已确认(ack) = $ack"
  echo "  重启后存活  = $survived"
  echo "  【已确认但丢失 = $lost】"
  if [ "$lost" -gt 0 ]; then
    echo "  ✅ 捕获到 fsync 丢失窗口：ack 过的消息仍丢了 $lost 条"
  else
    echo "  ⚠️  本轮未捕获丢失"
  fi
}

echo "=== 前置：确认 broker 在线 ==="
"$DOCKER" exec "$RMQ_CT" rabbitmqctl status >/dev/null 2>&1 || "$DOCKER" start "$RMQ_CT" >/dev/null 2>&1
sleep 3

run_case "对照组：逐条同步 confirm（v2 节奏）" 1 sync
run_case "实验组：批量 200 条后统一确认" 200 batch

echo ""
echo "════════════════════════════════════════════════════════"
echo "对比结论见上方两组「已确认但丢失」数字"
echo "════════════════════════════════════════════════════════"
