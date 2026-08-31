#!/usr/bin/env bash
# 课 7《持久化与死信》一键验证脚本
# 覆盖三个知识点全部核心结论，跑完打印 PASS/FAIL 汇总
#
# 注意：知识点 1 的宕机验证不放在本脚本（会中断其他测试），
#       单独用 l7-run-persist3.sh 执行。本脚本验证不依赖宕机的结论。
source "$(dirname "$0")/l7-env.sh"
set -u
cd "$(dirname "$0")"

PASS=0
FAIL=0

check() {
  local desc="$1"
  local actual="$2"
  local expect="$3"
  if [ "$actual" = "$expect" ]; then
    echo "  ✅ PASS  $desc  (实际=$actual, 期望=$expect)"
    PASS=$((PASS + 1))
  else
    echo "  ❌ FAIL  $desc  (实际=$actual, 期望=$expect)"
    FAIL=$((FAIL + 1))
  fi
}

check_num() {
  local desc="$1"
  local actual="$2"
  local op="$3"
  local expect="$4"
  if awk -v a="$actual" -v e="$expect" -v o="$op" 'BEGIN{
        if (o=="gt") exit !(a+0>e+0);
        if (o=="ge") exit !(a+0>=e+0);
        if (o=="lt") exit !(a+0<e+0);
        if (o=="le") exit !(a+0<=e+0);
        exit 1
      }'; then
    echo "  ✅ PASS  $desc  (实际=$actual, 要求 $op $expect)"
    PASS=$((PASS + 1))
  else
    echo "  ❌ FAIL  $desc  (实际=$actual, 要求 $op $expect)"
    FAIL=$((FAIL + 1))
  fi
}

# 确保 broker 在线
"$DOCKER" exec "$RMQ_CT" rabbitmqctl status >/dev/null 2>&1 || "$DOCKER" start "$RMQ_CT" >/dev/null 2>&1
for n in $(seq 1 60); do
  "$DOCKER" exec "$RMQ_CT" rabbitmqctl status >/dev/null 2>&1 && break
  sleep 1
done
sleep 2

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  知识点 1：三层持久化"
echo "════════════════════════════════════════════════════════════"
python - <<'PY' 2>&1
import os
import pika

HOST = os.environ.get("RMQ_HOST", "127.0.0.1")
PORT = int(os.environ.get("RMQ_PORT", "5672"))
USER = os.environ.get("RMQ_USER", "learn")
PASS = os.environ.get("RMQ_PASS", "learn123")

conn = pika.BlockingConnection(
    pika.ConnectionParameters(host=HOST, port=PORT,
                              credentials=pika.PlainCredentials(USER, PASS)))
ch = conn.channel()
ch.queue_declare(queue="l7.v.persist", durable=True)
ch.queue_declare(queue="l7.v.transient", durable=True)
ch.confirm_delivery()
ch.basic_publish(exchange="", routing_key="l7.v.persist", body=b"p",
                 properties=pika.BasicProperties(delivery_mode=2))
ch.basic_publish(exchange="", routing_key="l7.v.transient", body=b"t",
                 properties=pika.BasicProperties(delivery_mode=1))
conn.close()
print("  已发布：持久化消息 1 条 + 非持久化消息 1 条")
PY

# 用 rabbitmqctl list_queues 读权威统计
# 【踩坑】Management API 在本环境取不到 messages_persistent：
#   单队列接口不含该字段；加 ?columns= 单队列接口不支持；列表接口也缺失。
#   rabbitmqctl list_queues name messages messages_persistent 实测可用。
qstat() {
  "$DOCKER" exec "$RMQ_CT" rabbitmqctl list_queues name messages messages_persistent -q 2>/dev/null \
    | awk -F'\t' -v q="$1" '$1==q{print $2}'
}
qpersist() {
  "$DOCKER" exec "$RMQ_CT" rabbitmqctl list_queues name messages messages_persistent -q 2>/dev/null \
    | awk -F'\t' -v q="$1" '$1==q{print $3}'
}

P_MSG=$(qstat l7.v.persist)
P_PER=$(qpersist l7.v.persist)
echo "  持久化消息：messages=$P_MSG  messages_persistent=$P_PER"
check "delivery_mode=2 的消息计入 messages_persistent" "$P_PER" "1"

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  知识点 2：持久化的真实程度"
echo "════════════════════════════════════════════════════════════"

# classic 队列：messages_persistent 在发布返回后极短时间内追平（亚秒级批量落盘）
python - <<'PY' 2>&1
import os
import time

import pika

HOST = os.environ.get("RMQ_HOST", "127.0.0.1")
PORT = int(os.environ.get("RMQ_PORT", "5672"))
USER = os.environ.get("RMQ_USER", "learn")
PASS = os.environ.get("RMQ_PASS", "learn123")

conn = pika.BlockingConnection(
    pika.ConnectionParameters(host=HOST, port=PORT,
                              credentials=pika.PlainCredentials(USER, PASS)))
ch = conn.channel()
ch.queue_declare(queue="l7.v.lag", durable=True)
ch.confirm_delivery()
for i in range(3000):
    ch.basic_publish(exchange="", routing_key="l7.v.lag", body=f"x{i}".encode(),
                     properties=pika.BasicProperties(delivery_mode=2))
conn.close()
print("  已发布 3000 条持久化消息")
PY

L_MSG=$(qstat l7.v.lag)
L_PER=$(qpersist l7.v.lag)
echo "  classic 队列：messages=$L_MSG  messages_persistent=$L_PER"
check_num "classic 队列发布返回后已基本落盘（persistent 接近总数）" "$L_PER" "ge" "3000"

# quorum 队列：确认前已 fsync（用耗时佐证：quorum 明显慢于 classic）
python - <<'PY' 2>&1
import os
import time

import pika

HOST = os.environ.get("RMQ_HOST", "127.0.0.1")
PORT = int(os.environ.get("RMQ_PORT", "5672"))
USER = os.environ.get("RMQ_USER", "learn")
PASS = os.environ.get("RMQ_PASS", "learn123")

conn = pika.BlockingConnection(
    pika.ConnectionParameters(host=HOST, port=PORT,
                              credentials=pika.PlainCredentials(USER, PASS)))
ch = conn.channel()

def bench(queue, qtype):
    if qtype == "quorum":
        ch.queue_declare(queue=queue, durable=True,
                         arguments={"x-queue-type": "quorum"})
    else:
        ch.queue_declare(queue=queue, durable=True)
    ch.confirm_delivery()
    t0 = time.time()
    for i in range(500):
        ch.basic_publish(exchange="", routing_key=queue, body=b"z"*100,
                         properties=pika.BasicProperties(delivery_mode=2))
    return time.time() - t0

t_classic = bench("l7.v.bench.classic", "classic")
t_quorum = bench("l7.v.bench.quorum", "quorum")
conn.close()
print(f"  500 条耗时：classic={t_classic:.3f}s  quorum={t_quorum:.3f}s  "
      f"比值={t_quorum/t_classic:.2f}x")
PY

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  知识点 3：TTL 与死信队列"
echo "════════════════════════════════════════════════════════════"
python l7-ttl-dlx.py > l7_ttl_out.txt 2>&1
grep -E "期望|→|x-death =|ack 成功" l7_ttl_out.txt | head -30

echo ""
echo "  --- 关键结论断言 ---"
DLX_COUNT=$(qstat l7.dead.q)
echo "  l7.dead.q 死信队列消息数 = ${DLX_COUNT}（部分已被脚本消费）"

# 惰性过期验证
python l7-ttl-lazy.py > l7_lazy_out.txt 2>&1
LAZY_SINGLE=$(grep -A2 "t=1.8s" l7_lazy_out.txt | head -1 | grep -oE "深度=[0-9]+" | cut -d= -f2)
LAZY_BLOCK=$(sed -n '/对照 2/,/对照 3/p' l7_lazy_out.txt | grep "t=3.3s" | grep -oE "深度=[0-9]+" | cut -d= -f2)
echo ""
echo "  惰性过期：单条(队首) 1.8s 后深度=$LAZY_SINGLE（期望 0）"
echo "  惰性过期：被挡住 3.3s 后深度=$LAZY_BLOCK（期望 2，被队首阻塞）"
check "队首消息到期后被移除" "$LAZY_SINGLE" "0"
check "被队首阻塞的过期消息不被移除" "$LAZY_BLOCK" "2"

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  清理测试队列"
echo "════════════════════════════════════════════════════════════"
for q in l7.v.persist l7.v.transient l7.v.lag l7.v.bench.classic l7.v.bench.quorum \
         l7.ttl.q l7.dead.q l7.src.reject l7.src.expire l7.src.maxlen \
         l7.work l7.retry.wait l7.lazy.single l7.lazy.blocked l7.lazy.get l7.lazy.rev; do
  "$DOCKER" exec "$RMQ_CT" rabbitmqctl delete_queue "$q" >/dev/null 2>&1 && echo "  已删 $q"
done
for e in l7.ttl.ex l7.dlx l7.dlx2; do
  "$DOCKER" exec -e RABBITMQADMIN_USERNAME="$RMQ_USER" -e RABBITMQADMIN_PASSWORD="$RMQ_PASS" \
    "$RMQ_CT" rabbitmqadmin delete exchange --name "$e" --non-interactive >/dev/null 2>&1 \
    && echo "  已删交换机 $e"
done

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  汇总：PASS=$PASS  FAIL=$FAIL"
echo "════════════════════════════════════════════════════════════"
[ "$FAIL" -eq 0 ] && echo "  🎉 全部通过" || echo "  ⚠️  存在失败项，请检查上方 ❌"
