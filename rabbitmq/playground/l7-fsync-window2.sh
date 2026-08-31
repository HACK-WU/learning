#!/usr/bin/env bash
# 课 7 知识点 2（修正版）：持久化的"真实程度" —— 捕捉 fsync 丢失窗口
#
# 【v1 的设计缺陷】
#   v1 让发布脚本跑完 20000 条后才 kill -9。但 fsync 默认间隔是毫秒级，
#   等脚本跑完再 kill，所有消息早已落盘 → 必然测出"零丢失"，得出假结论。
#   → 必须在**发布进行中** kill，才能捕捉"已 ack 但尚未 fsync"的那一小批。
#
# 【v2 设计】
#   1. 后台启动发布进程（持续 30 秒，逐条 confirm 同步等）
#   2. 主进程 sleep 一个随机短窗口（3~6 秒，确保正在高频写入）
#   3. 主进程 kill -9 broker（发布进程随之报错退出）
#   4. 重启后统计：已 ack 数 vs 实际存活数 → 差值即"已确认但丢失"
#
# 【为什么这样能证明"持久化不是绝对不丢"】
#   如果持久化是"ack 即安全"，那么已 ack 的消息一条都不该丢。
#   只要出现 已ack数 > 存活数，就证明存在 fsync 窗口。
source "$(dirname "$0")/l7-env.sh"
set -u
cd "$(dirname "$0")"

echo "=== 1. fsync / 刷盘相关参数默认值 ==="
"$DOCKER" exec "$RMQ_CT" rabbitmqctl environment 2>&1 \
  | grep -iE "fsync|flush_interval|sync_interval|msg_store_file_size" | head -20

echo ""
echo "=== 2. 清理旧队列 ==="
"$DOCKER" exec "$RMQ_CT" rabbitmqctl delete_queue l7.fsync.test >/dev/null 2>&1
rm -f l7_fsync_counter.txt

# 后台发布进程
cat > l7_fsync_pub.py <<'PYEOF'
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
ch.queue_declare(queue="l7.fsync.test", durable=True)
ch.confirm_delivery()  # 注意：pika BlockingChannel 用 confirm_delivery，不是 confirm_select

acked = 0
deadline = time.time() + 30  # 最多跑 30 秒
try:
    i = 0
    while time.time() < deadline:
        i += 1
        ch.basic_publish(
            exchange="",
            routing_key="l7.fsync.test",
            body=f"m{i}".encode(),
            properties=pika.BasicProperties(delivery_mode=2),
        )
        acked = i  # pika confirm 同步等，未抛异常即已 ack
except Exception as exc:
    pass  # 被 kill 时会在这里抛异常，正常
finally:
    with open("l7_fsync_counter.txt", "w", encoding="utf-8") as f:
        f.write(f"{acked}\n")
PYEOF

echo ""
echo "=== 3. 后台启动发布进程（将持续 30 秒）==="
python l7_fsync_pub.py &
PUB_PID=$!
echo "  发布进程 PID=$PUB_PID"

echo ""
echo "=== 4. 等待 5 秒，让发布进入稳定高频状态 ==="
sleep 5

echo ""
echo "=== 5. 【关键】在发布进行中 kill -9 broker ==="
"$DOCKER" kill -s KILL "$RMQ_CT" >/dev/null 2>&1
echo "  已 kill -9（此刻发布进程正在高频写入）"

# 等发布进程退出
wait $PUB_PID 2>/dev/null
sleep 1

echo ""
echo "=== 6. 读取发布进程记录的已 ack 数 ==="
if [ -f l7_fsync_counter.txt ]; then
  ACK=$(sed -n 1p l7_fsync_counter.txt)
  echo "  已确认(ack) 数 = $ACK"
else
  echo "  ❌ 计数器文件不存在，发布进程可能被杀得太早"
  ACK=0
fi

echo ""
echo "=== 7. 重启 broker 并等待恢复 ==="
"$DOCKER" start "$RMQ_CT" >/dev/null 2>&1
for i in $(seq 1 120); do
  if "$DOCKER" exec "$RMQ_CT" rabbitmqctl status >/dev/null 2>&1; then
    echo "  broker 已就绪（等待 ${i} 秒）"
    break
  fi
  sleep 1
done
sleep 8

SURVIVED=$("$DOCKER" exec "$RMQ_CT" rabbitmqctl list_queues name messages -q 2>/dev/null \
  | awk -F'\t' '$1=="l7.fsync.test"{print $2}')
SURVIVED=${SURVIVED:-0}

echo ""
echo "  ┌────────────────────────────────────────────────┐"
echo "  │ 已确认(ack) 数        : $ACK"
echo "  │ 重启后实际存活数      : $SURVIVED"
echo "  │ 已确认但丢失          : $((ACK - SURVIVED))"
echo "  └────────────────────────────────────────────────┘"
echo ""
if [ "$((ACK - SURVIVED))" -gt 0 ]; then
  echo "  ✅ 结论：存在 fsync 窗口 —— 已被 confirm 确认的消息，仍可能因未落盘而丢失"
  echo "     这证明 delivery_mode=2 ≠ 绝对不丢"
else
  echo "  ⚠️  本次未捕获到丢失（可能 fsync 太快或 ack 数太少），需增大写入压力重试"
fi
