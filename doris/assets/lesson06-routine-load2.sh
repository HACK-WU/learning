#!/bin/bash
Q() { docker exec doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop --batch -e "$1" 2>&1 | grep -vE "^Warning|Using a password"; }

echo "############ 1. 清理旧作业与表 ############"
Q "STOP ROUTINE LOAD FOR shop.kafka_rl_orders" 2>&1 | tail -2
Q "DROP TABLE IF EXISTS kafka_orders"

echo ""
echo "############ 2. 建目标表 ############"
Q "CREATE TABLE kafka_orders (
    order_id    BIGINT,
    user_id     BIGINT,
    province    VARCHAR(32),
    amount      DECIMAL(10,2),
    order_time  DATETIME
)
DUPLICATE KEY(order_id)
DISTRIBUTED BY HASH(order_id) BUCKETS 4
PROPERTIES ('replication_num' = '1')"
echo "建表完成"
Q "SHOW TABLES LIKE 'kafka_orders'"

echo ""
echo "############ 3. 建 Routine Load 作业（broker = kafka:9092）############"
Q "CREATE ROUTINE LOAD shop.kafka_rl_orders ON kafka_orders
COLUMNS(order_id, user_id, province, amount, order_time)
PROPERTIES
(
    'desired_concurrent_number' = '1',
    'max_batch_interval' = '10',
    'max_batch_rows' = '200000',
    'max_batch_size' = '104857600',
    'strict_mode' = 'false',
    'format' = 'json'
)
FROM KAFKA
(
    'kafka_broker_list' = 'kafka:9092',
    'kafka_topic' = 'doris_orders',
    'property.group.id' = 'doris_rl_group',
    'property.kafka_default_offsets' = 'OFFSET_BEGINNING'
)"
echo "创建返回码: $?"

echo ""
echo "############ 4. 等 15 秒 ############"
sleep 15

echo ""
echo "############ 5. 作业状态（期望 RUNNING）############"
Q "SHOW ROUTINE LOAD FOR shop.kafka_rl_orders\G" | grep -E "^\s*(Id|Name|State|CurrentTaskNum|DataSourceType|Progress|Lag|ReasonOfStateChanged):"

echo ""
echo "############ 6. 发 500 条 Kafka 消息 ############"
docker exec doris-kafka bash -c "
for i in \$(seq 1 500); do
  P=\$((RANDOM % 5))
  case \$P in
    0) PROV='广东';; 1) PROV='山东';; 2) PROV='江苏';; 3) PROV='浙江';; 4) PROV='四川';;
  esac
  echo \"{\\\"order_id\\\":\$i,\\\"user_id\\\":\$((RANDOM % 100000)),\\\"province\\\":\\\"\$PROV\\\",\\\"amount\\\":\$((RANDOM % 5000)).99,\\\"order_time\\\":\\\"2024-03-15 10:00:00\\\"}\"
done > /tmp/kafka_msgs.json
wc -l < /tmp/kafka_msgs.json
/opt/kafka/bin/kafka-console-producer.sh --bootstrap-server kafka:9092 --topic doris_orders < /tmp/kafka_msgs.json 2>&1 | tail -2
echo '发送完成'
"

echo ""
echo "############ 7. 等 20 秒消费 ############"
sleep 20

echo ""
echo "############ 8. Doris 落库行数（期望 500）############"
Q "SELECT COUNT(*) AS rows_in_doris FROM kafka_orders"

echo ""
echo "############ 9. 完整作业状态 + lag ############"
Q "SHOW ROUTINE LOAD FOR shop.kafka_rl_orders\G"

echo ""
echo "############ 10. 再发 200 条，验证增量消费（断点续传）############"
docker exec doris-kafka bash -c "
for i in \$(seq 501 700); do
  echo \"{\\\"order_id\\\":\$i,\\\"user_id\\\":999,\\\"province\\\":\\\"福建\\\",\\\"amount\\\":12.34,\\\"order_time\\\":\\\"2024-03-15 11:00:00\\\"}\"
done > /tmp/kafka_msgs2.json
/opt/kafka/bin/kafka-console-producer.sh --bootstrap-server kafka:9092 --topic doris_orders < /tmp/kafka_msgs2.json 2>&1 | tail -2
echo '第二批发送完成'
"
sleep 20
Q "SELECT COUNT(*) AS rows_after_2nd FROM kafka_orders"
Q "SELECT province, COUNT(*) FROM kafka_orders GROUP BY province ORDER BY province"
