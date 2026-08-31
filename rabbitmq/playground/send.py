import pika

# 1. 建立 TCP 连接：5672 是 AMQP 协议端口，15672 是管理界面端口，别搞混
credentials = pika.PlainCredentials('learn', 'learn123')
parameters = pika.ConnectionParameters(host='localhost', port=5672, credentials=credentials)
connection = pika.BlockingConnection(parameters)

# 2. 在 TCP 连接之上开一条信道（channel）：真正干活的都是信道，不是连接
channel = connection.channel()

# 3. 声明队列：durable=True 在 RabbitMQ 4.3 是必须的（见讲义说明）
#    这个操作是幂等的——队列已存在且参数一致时不会重复创建
channel.queue_declare(queue='hello', durable=True)

# 4. 发消息：exchange 留空 = 走默认交换机，routing_key 直接填队列名
channel.basic_publish(
    exchange='',
    routing_key='hello',
    body='Hello RabbitMQ!'
)
print(" [x] 已发送 Hello RabbitMQ!")

# 5. 关闭连接
connection.close()
