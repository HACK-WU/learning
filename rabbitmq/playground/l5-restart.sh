#!/usr/bin/env bash
# 课5 持久化验证：重启容器，观察队列与消息存活情况

echo "############ 重启前：当前状态 ############"
docker exec rabbitmq-learn rabbitmqctl list_queues name type durable messages 2>&1

echo ""
echo "############ 准备测试消息 ############"
cat > /tmp/prep.py <<'PYEOF'
import pika
CR = pika.PlainCredentials('learn','learn123')
c = pika.BlockingConnection(pika.ConnectionParameters('localhost',5672,'/',CR))
ch = c.channel()
qs = {
  'r_durable_q':   True,   # durable 队列
}
for q in qs:
    ch.queue_declare(queue=q, durable=True, arguments={'x-queue-type':'classic'})

# 持久化队列 + 持久化消息
ch.basic_publish(exchange='', routing_key='r_durable_q', body='PERSIST-MSG',
                 properties=pika.BasicProperties(delivery_mode=2))
# 持久化队列 + 非持久化消息
ch.basic_publish(exchange='', routing_key='r_durable_q', body='TRANSIENT-MSG',
                 properties=pika.BasicProperties(delivery_mode=1))
print("已发送 2 条消息到 r_durable_q")
c.close()
PYEOF
docker cp /tmp/prep.py rabbitmq-learn:/tmp/prep.py >/dev/null 2>&1
docker exec rabbitmq-learn python3 /tmp/prep.py 2>&1 || \
  docker exec rabbitmq-learn sh -c "python /tmp/prep.py" 2>&1

echo ""
echo "############ 重启前的消息数 ############"
docker exec rabbitmq-learn rabbitmqctl list_queues name durable messages 2>&1 | grep -E "r_durable_q|name"

echo ""
echo "############ 执行重启 ############"
docker restart rabbitmq-learn 2>&1
echo "等待就绪..."
for i in $(seq 1 90); do
  if docker exec rabbitmq-learn rabbitmq-diagnostics -q check_running >/dev/null 2>&1; then
    echo "第 ${i} 秒：已就绪"; break
  fi
  sleep 1
done

echo ""
echo "############ 重启后：队列与消息 ############"
docker exec rabbitmq-learn rabbitmqctl list_queues name type durable messages 2>&1

echo ""
echo "############ 验证持久化消息内容是否还在 ############"
cat > /tmp/check.py <<'PYEOF'
import pika
CR = pika.PlainCredentials('learn','learn123')
c = pika.BlockingConnection(pika.ConnectionParameters('localhost',5672,'/',CR))
ch = c.channel()
for q in ['r_durable_q']:
    try:
        r = ch.queue_declare(queue=q, durable=True, passive=True)
        print(f"[{q}] 存在, 消息数 = {r.method.message_count}, 消费者 = {r.method.consumer_count}")
    except Exception as e:
        print(f"[{q}] 不存在或异常: {type(e).__name__}")
    # 逐条取出看内容
    n = 0
    while True:
        m,h,b = ch.basic_get(queue=q, auto_ack=True)
        if not m: break
        n += 1
        print(f"    消息{n}: {b.decode()}  (delivery_mode={h.delivery_mode})")
    if n == 0:
        print(f"    (队列为空)")
c.close()
PYEOF
docker cp /tmp/check.py rabbitmq-learn:/tmp/check.py >/dev/null 2>&1
docker exec rabbitmq-learn python3 /tmp/check.py 2>&1 || \
  docker exec rabbitmq-learn sh -c "python /tmp/check.py" 2>&1
