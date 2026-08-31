import pika

credentials = pika.PlainCredentials('learn', 'learn123')
parameters = pika.ConnectionParameters(host='localhost', port=5672, credentials=credentials)
connection = pika.BlockingConnection(parameters)
channel = connection.channel()

# 消费者这边也要声明：你无法保证生产者一定先跑过。
# 注意 durable 参数必须和生产者完全一致，否则报 PRECONDITION_FAILED
channel.queue_declare(queue='hello', durable=True)


# 回调函数：消息是被"推"给我们的，不是我们去轮询拉取
def on_message(ch, method, properties, body):
    # flush=True：输出被管道重定向时 Python 会缓冲，不加可能在超时被杀时丢输出
    print(f" [x] 收到 {body.decode()}", flush=True)


# 注册消费者：auto_ack=True 表示一收到就自动确认（课 6 会讲为什么生产环境不该这么干）
channel.basic_consume(
    queue='hello',
    auto_ack=True,
    on_message_callback=on_message
)

print(' [*] 等待消息中。按 CTRL+C 退出')
channel.start_consuming()
