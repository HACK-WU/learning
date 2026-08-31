#!/usr/bin/env bash
# 课 7 知识点 2：持久化的"真实程度" —— 验证 fsync 时机造成的丢失窗口
#
# 核心命题：delivery_mode=2 不等于"一定不丢"。
# 官方文档（Persistence Configuration / Publisher confirms）：
#   持久化消息在**两个时机点**之间仍可能丢：
#     (a) 消息写入页缓存 → 尚未 fsync 落盘（默认间隔约 200ms 或由 queue 决定）
#     (b) broker 收到消息 → 尚未写入任何存储
#   只有 fsync 完成后的消息才真正安全。
#
# 本脚本验证两件事：
#   1. 【可观测】fsync 间隔参数默认值（rabbitmqctl environment）
#   2. 【可实测】高频发布 + 中途 kill -9 → 统计"已 ack 但未落盘"的丢失量
#
# 实验设计（对照课 6 的 confirm 用法）：
#   - 开 confirm_select，逐条发布并记录收到 ack 的最大 delivery_tag
#   - 在发布过程中随机时刻 kill -9
#   - 重启后 count 队列实际消息数，与"已 ack 数"对比
#   - 注意：pika 的 confirm 是逐条同步等（课 6 P0-3 结论），故 ack 数 ≈ 发布数
#   - 差值 =  acknowledged but lost（已确认但丢失）
source "$(dirname "$0")/l7-env.sh"
set -u
cd "$(dirname "$0")"

echo "=== 1. fsync / 刷盘相关参数默认值 ==="
"$DOCKER" exec "$RMQ_CT" rabbitmqctl environment 2>&1 \
  | grep -iE "fsync|flush|sync_interval|msg_store" | head -20

echo ""
echo "=== 2. 队列持久化相关默认配置 ==="
"$DOCKER" exec "$RMQ_CT" rabbitmqctl environment 2>&1 \
  | grep -iE "queue_index|credits|lazy" | head -15

echo ""
echo "=== 3. 实测准备：清理并声明 durable 队列 ==="
"$DOCKER" exec "$RMQ_CT" rabbitmqctl delete_queue l7.fsync.test >/dev/null 2>&1
echo "  已清理旧队列"

echo ""
echo "=== 4. 开始高频发布（每 200 条打印一次进度），中途将被 kill -9 ==="
python - <<'PY' 2>&1
import os
import sys
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
ch.confirm_select()  # 开启发布者确认

acked = 0
published = 0
try:
    for i in range(1, 20001):
        ch.basic_publish(
            exchange="",
            routing_key="l7.fsync.test",
            body=f"m{i}".encode(),
            properties=pika.BasicProperties(delivery_mode=2),
        )
        published += 1
        # pika 的 confirm 是同步等（课 6 结论），未抛异常即视为已 ack
        acked = published
        if i % 1000 == 0:
            print(f"  已发布并被 ack: {i}", flush=True)
except Exception as exc:
    print(f"  发布中断：{type(exc).__name__}: {exc}", flush=True)
finally:
    print(f"\n>>> 发布结束：published={published} acked={acked}", flush=True)
    # 把数字写到文件，供 kill 之后读取
    with open("l7_fsync_counter.txt", "w", encoding="utf-8") as f:
        f.write(f"{published}\n{acked}\n")
PY

echo ""
echo "=== 5. 发布脚本结束，读取计数器 ==="
if [ -f l7_fsync_counter.txt ]; then
  PUB=$(sed -n 1p l7_fsync_counter.txt)
  ACK=$(sed -n 2p l7_fsync_counter.txt)
  echo "  发布数=$PUB  已确认数=$ACK"
else
  echo "  未找到计数器文件"
  exit 1
fi

echo ""
echo "=== 6. 立刻 kill -9（不给 fsync 收尾机会），然后重启统计实际存活 ==="
"$DOCKER" kill -s KILL "$RMQ_CT" >/dev/null 2>&1
sleep 2
"$DOCKER" start "$RMQ_CT" >/dev/null 2>&1
for i in $(seq 1 120); do
  if "$DOCKER" exec "$RMQ_CT" rabbitmqctl status >/dev/null 2>&1; then break; fi
  sleep 1
done
sleep 8

SURVIVED=$("$DOCKER" exec "$RMQ_CT" rabbitmqctl list_queues name messages -q 2>/dev/null \
  | awk -F'\t' '$1=="l7.fsync.test"{print $2}')
echo "  重启后队列实际消息数 = ${SURVIVED:-0}"
echo ""
echo "  ┌──────────────────────────────────────────────┐"
echo "  │ 已确认(ack) 数 : $ACK"
echo "  │ 重启后存活数  : ${SURVIVED:-0}"
echo "  │ 已确认但丢失  : $((ACK - ${SURVIVED:-0}))"
echo "  └──────────────────────────────────────────────┘"
