#!/bin/bash
# 课 4 配套验证脚本：一键复现本课全部路由行为
# 用法（Windows + WSL）：
#   & "C:\Windows\System32\bash.exe" -c "bash /mnt/d/projects/learning/rabbitmq/playground/verify-exchanges.sh"
#
# 前置：用课 3 的 docker run 命令起好 rabbitmq-learn 容器

set -u
RAB="docker exec rabbitmq-learn"
cd /mnt/d/projects/learning/rabbitmq/playground

echo "########## 0. 内置交换机清单 ##########"
$RAB rabbitmqctl list_exchanges name type 2>&1 | head -12

echo ""
echo "########## 1. 交换机不存消息 ##########"
echo "--- 尝试查交换机的消息数（应报错，证明它没有这一列）---"
$RAB rabbitmqctl list_exchanges name messages 2>&1 | head -3

echo ""
echo "########## 2. fanout 广播（忽略 routing key）##########"
python3 - <<'PYEOF'
import pika, time
c = pika.PlainCredentials('learn','learn123')
conn = pika.BlockingConnection(pika.ConnectionParameters(host='localhost',port=5672,credentials=c))
ch = conn.channel()
ch.exchange_declare(exchange='t_fanout', exchange_type='fanout', durable=True)
for q in ['f_q1','f_q2','f_q3']:
    ch.queue_declare(queue=q, durable=True)
    ch.queue_bind(exchange='t_fanout', queue=q)
ch.basic_publish(exchange='t_fanout', routing_key='IGNORED_BY_FANOUT', body='广播消息')
print("  已发送（routing_key 被 fanout 忽略）")
time.sleep(1); conn.close()
PYEOF
echo "--- 预期：三个队列各 1 条 ---"
$RAB rabbitmqctl list_queues name messages 2>&1 | grep -E "f_q|name"

echo ""
echo "########## 3. direct 精确匹配 ##########"
python3 - <<'PYEOF'
import pika, time
c = pika.PlainCredentials('learn','learn123')
conn = pika.BlockingConnection(pika.ConnectionParameters(host='localhost',port=5672,credentials=c))
ch = conn.channel()
ch.exchange_declare(exchange='t_direct', exchange_type='direct', durable=True)
ch.queue_declare(queue='d_error', durable=True)
ch.queue_bind(exchange='t_direct', queue='d_error', routing_key='error')
ch.queue_declare(queue='d_all', durable=True)
for k in ['error','info','warning']:
    ch.queue_bind(exchange='t_direct', queue='d_all', routing_key=k)
for rk in ['error','info','debug']:
    ch.basic_publish(exchange='t_direct', routing_key=rk, body=f'消息-{rk}')
print("  发送 error / info / debug")
time.sleep(1); conn.close()
PYEOF
echo "--- 预期：d_error=1, d_all=2（debug 被丢弃）---"
$RAB rabbitmqctl list_queues name messages 2>&1 | grep -E "d_error|d_all|name"

echo ""
echo "########## 4. topic 通配符 ##########"
python3 - <<'PYEOF'
import pika, time
c = pika.PlainCredentials('learn','learn123')
conn = pika.BlockingConnection(pika.ConnectionParameters(host='localhost',port=5672,credentials=c))
ch = conn.channel()
ch.exchange_declare(exchange='t_topic', exchange_type='topic', durable=True)
ch.queue_declare(queue='t_star', durable=True)
ch.queue_bind(exchange='t_topic', queue='t_star', routing_key='*.orange.*')
ch.queue_declare(queue='t_hash', durable=True)
ch.queue_bind(exchange='t_topic', queue='t_hash', routing_key='lazy.#')
tests = ['quick.orange.rabbit','lazy.orange.elephant','quick.orange.fox',
         'lazy.brown.fox','lazy.pink.rabbit','quick.brown.fox',
         'orange','lazy.orange.male.rabbit']
for rk in tests:
    ch.basic_publish(exchange='t_topic', routing_key=rk, body=rk)
time.sleep(1); conn.close()
PYEOF
echo "--- 预期：t_star=3, t_hash=4 ---"
$RAB rabbitmqctl list_queues name messages 2>&1 | grep -E "t_star|t_hash|name"
echo "--- 再验证 # 可匹配零个词 ---"
python3 - <<'PYEOF'
import pika, time
c = pika.PlainCredentials('learn','learn123')
conn = pika.BlockingConnection(pika.ConnectionParameters(host='localhost',port=5672,credentials=c))
ch = conn.channel()
ch.basic_publish(exchange='t_topic', routing_key='lazy', body='bare lazy')
time.sleep(1); conn.close()
PYEOF
$RAB rabbitmqctl list_queues name messages 2>&1 | grep -E "t_hash"
echo "  t_hash 若 +1 则证明 # 匹配零个词"

echo ""
echo "########## 5. headers 的 x-match（all vs any）##########"
python3 - <<'PYEOF'
import pika, time
c = pika.PlainCredentials('learn','learn123')
conn = pika.BlockingConnection(pika.ConnectionParameters(host='localhost',port=5672,credentials=c))
ch = conn.channel()
ch.exchange_declare(exchange='t_headers', exchange_type='headers', durable=True)
for q, m in [('h_all','all'), ('h_any','any')]:
    ch.queue_declare(queue=q, durable=True)
    ch.queue_bind(exchange='t_headers', queue=q,
                  arguments={'x-match': m, 'format':'pdf', 'type':'report'})
for hdrs in [{'format':'pdf','type':'report'}, {'format':'pdf','type':'log'}, {'format':'txt','type':'log'}]:
    ch.basic_publish(exchange='t_headers', routing_key='', body=str(hdrs),
                     properties=pika.BasicProperties(headers=hdrs))
time.sleep(1); conn.close()
PYEOF
echo "--- 预期：h_all=1（仅全中）, h_any=2 ---"
$RAB rabbitmqctl list_queues name messages 2>&1 | grep -E "h_all|h_any|name"

echo ""
echo "########## 6. 默认交换机 ##########"
python3 - <<'PYEOF'
import pika, time
c = pika.PlainCredentials('learn','learn123')
conn = pika.BlockingConnection(pika.ConnectionParameters(host='localhost',port=5672,credentials=c))
ch = conn.channel()
ch.queue_declare(queue='defq', durable=True)
ch.basic_publish(exchange='', routing_key='defq', body='走默认交换机')
ch.basic_publish(exchange='', routing_key='nosuchqueue', body='无人收')
time.sleep(1)
try:
    ch.queue_bind(exchange='', queue='defq', routing_key='custom')
    print("  显式绑定默认交换机：成功")
except Exception as e:
    print("  显式绑定默认交换机失败（预期）:", str(e)[:90])
conn.close()
PYEOF
echo "--- 预期：defq=1，第二条被丢弃，绑定报 ACCESS_REFUSED ---"
$RAB rabbitmqctl list_queues name messages 2>&1 | grep -E "defq|name"
echo "--- 默认交换机的自动绑定 ---"
$RAB rabbitmqctl list_bindings source_name destination_name routing_key 2>&1 | grep -E "defq|source"

echo ""
echo "########## 7. 无可路由：mandatory + AE ##########"
python3 - <<'PYEOF'
import pika, time
c = pika.PlainCredentials('learn','learn123')
conn = pika.BlockingConnection(pika.ConnectionParameters(host='localhost',port=5672,credentials=c))
ch = conn.channel()
# AE 兜底
ch.exchange_declare(exchange='ae_fanout', exchange_type='fanout', durable=True)
ch.queue_declare(queue='unrouted_holder', durable=True)
ch.queue_bind(exchange='ae_fanout', queue='unrouted_holder')
ch.exchange_declare(exchange='t_ae', exchange_type='direct', durable=True,
                    arguments={'alternate-exchange':'ae_fanout'})
ch.queue_declare(queue='ae_orange', durable=True)
ch.queue_bind(exchange='t_ae', queue='ae_orange', routing_key='orange')
ch.basic_publish(exchange='t_ae', routing_key='orange', body='正常消息')
ch.basic_publish(exchange='t_ae', routing_key='black', body='无人要的消息')
# mandatory 退回（无 AE 的交换机）
ch.exchange_declare(exchange='t_nr2', exchange_type='direct', durable=True)
ch.add_on_return_callback(lambda ch,m,p,b: print(f"  [RETURNED] code={m.reply_code} {m.reply_text}", flush=True))
ch.basic_publish(exchange='t_nr2', routing_key='nobody', body='无人接收', mandatory=True)
time.sleep(1); ch.connection.sleep(1)
conn.close()
PYEOF
echo "--- 预期：unrouted_holder=1（AE 兜住）、ae_orange=1 ---"
$RAB rabbitmqctl list_queues name messages 2>&1 | grep -E "unrouted_holder|ae_orange|name"

echo ""
echo "########## 8. 多消费者轮询分发（先启消费者再发消息）##########"
$RAB rabbitmqctl delete_queue rr2 >/dev/null 2>&1
cat > /tmp/cons2.py <<'PYEOF'
import pika, sys, time, threading
name = sys.argv[1]
c = pika.PlainCredentials('learn','learn123')
conn = pika.BlockingConnection(pika.ConnectionParameters(host='localhost',port=5672,credentials=c))
ch = conn.channel()
ch.queue_declare(queue='rr2', durable=True)
count = [0]
def cb(ch, m, p, body):
    count[0] += 1
    print(f"  [{name}] 收到: {body.decode()}", flush=True)
    time.sleep(0.5)
ch.basic_consume(queue='rr2', on_message_callback=cb, auto_ack=True)
print(f"  [{name}] 已就绪", flush=True)
threading.Thread(target=ch.start_consuming, daemon=True).start()
time.sleep(11)
print(f"  [{name}] 共收到 {count[0]} 条", flush=True)
PYEOF
(python3 /tmp/cons2.py C1 > /tmp/c1.log 2>&1 &)
(python3 /tmp/cons2.py C2 > /tmp/c2.log 2>&1 &)
sleep 3
python3 - <<'PYEOF'
import pika
c = pika.PlainCredentials('learn','learn123')
conn = pika.BlockingConnection(pika.ConnectionParameters(host='localhost',port=5672,credentials=c))
ch = conn.channel()
ch.queue_declare(queue='rr2', durable=True)
for i in range(6):
    ch.basic_publish(exchange='', routing_key='rr2', body=f'任务{i}')
print("  已发 6 条（消费者已就绪）")
conn.close()
PYEOF
sleep 9
echo "--- 预期：C1=3, C2=3（轮询均分）---"
cat /tmp/c1.log; cat /tmp/c2.log
echo ""
echo "--- 默认 prefetch（无上限是造成不均的根因）---"
$RAB rabbitmqctl environment 2>&1 | grep default_consumer_prefetch

echo ""
echo "########## 9. 清理 ##########"
for q in f_q1 f_q2 f_q3 d_error d_all t_star t_hash h_all h_any defq unrouted_holder ae_orange rr2; do
  $RAB rabbitmqctl delete_queue $q >/dev/null 2>&1
done
for e in t_fanout t_direct t_topic t_headers t_ae ae_fanout t_nr2; do
  $RAB rabbitmqctl delete_exchange $e >/dev/null 2>&1
done
echo "验证完成，测试用交换机与队列已清理"
