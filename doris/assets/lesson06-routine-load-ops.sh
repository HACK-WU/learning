#!/bin/bash
Q() { docker exec doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop --batch -e "$1" 2>&1 | grep -vE "^Warning|Using a password"; }
RL="SHOW ROUTINE LOAD FOR shop.kafka_rl_orders\G"

echo "############ 实验 A：PAUSE / RESUME —— 暂停期间的消息会不会丢？############"
echo "--- A1: 先记录当前行数 ---"
Q "SELECT COUNT(*) AS before_pause FROM kafka_orders"

echo ""
echo "--- A2: 暂停作业 ---"
Q "PAUSE ROUTINE LOAD FOR shop.kafka_rl_orders"
sleep 3
Q "$RL" | grep -E "^\s*(State|CurrentTaskNum|Progress|Lag):"

echo ""
echo "--- A3: 暂停期间往 Kafka 发 300 条（作业不消费）---"
docker exec doris-kafka bash -c "
for i in \$(seq 701 1000); do
  echo \"{\\\"order_id\\\":\$i,\\\"user_id\\\":777,\\\"province\\\":\\\"陕西\\\",\\\"amount\\\":55.55,\\\"order_time\\\":\\\"2024-03-15 12:00:00\\\"}\"
done > /tmp/kafka_msgs3.json
/opt/kafka/bin/kafka-console-producer.sh --bootstrap-server kafka:9092 --topic doris_orders < /tmp/kafka_msgs3.json 2>&1 | tail -1
echo '暂停期间已发 300 条'
"
sleep 10
echo "--- 暂停中 Doris 行数（应仍是 700，消息积压在 Kafka）---"
Q "SELECT COUNT(*) AS while_paused FROM kafka_orders"

echo ""
echo "--- A4: 关键指标 —— 暂停时的 Lag（应 > 0）---"
Q "$RL" | grep -E "^\s*(State|Lag|Progress):"

echo ""
echo "--- A5: 恢复作业 ---"
Q "RESUME ROUTINE LOAD FOR shop.kafka_rl_orders"
sleep 25
echo "--- 恢复后行数（应变 1000，暂停期间的消息被补消费）---"
Q "SELECT COUNT(*) AS after_resume FROM kafka_orders"
Q "$RL" | grep -E "^\s*(State|Lag|Statistic):"

echo ""
echo "############ 实验 B：ALTER ROUTINE LOAD 修改属性 ############"
echo "--- B1: 改 max_batch_rows 从 200000 到 1000 ---"
Q "ALTER ROUTINE LOAD FOR shop.kafka_rl_orders
PROPERTIES ('max_batch_rows' = '1000')"
sleep 3
Q "$RL" | grep -E '"max_batch_rows"'

echo ""
echo "############ 实验 C：脏数据进 Kafka → 作业如何处理 ############"
echo "--- C1: 发 3 条脏数据（amount 非数字）---"
docker exec doris-kafka bash -c "
printf '{\"order_id\":2001,\"user_id\":1,\"province\":\"广东\",\"amount\":\"BAD_DATA\",\"order_time\":\"2024-03-15 13:00:00\"}\n' > /tmp/kafka_bad.json
printf '{\"order_id\":2002,\"user_id\":2,\"province\":\"广东\",\"amount\":66.66,\"order_time\":\"2024-03-15 13:00:00\"}\n' >> /tmp/kafka_bad.json
/opt/kafka/bin/kafka-console-producer.sh --bootstrap-server kafka:9092 --topic doris_orders < /tmp/kafka_bad.json 2>&1 | tail -1
cat /tmp/kafka_bad.json
echo '已发送（1 条脏 + 1 条正常）'
"
sleep 25
echo "--- C2: 脏数据是否被计入 errorRows ---"
Q "$RL" | grep -E "^\s*(State|Statistic|ErrorLogUrls|ReasonOfStateChanged):"
echo "--- C3: 好数据是否仍进来（order_id=2002 应存在）---"
Q "SELECT order_id, amount FROM kafka_orders WHERE order_id IN (2001,2002)"

echo ""
echo "############ 实验 D：最终状态汇总 ############"
Q "$RL"
