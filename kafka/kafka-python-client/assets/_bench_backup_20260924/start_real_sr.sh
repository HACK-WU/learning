#!/bin/bash
# 启动真 Confluent Schema Registry（镜像 3.6GB，已拉取完成）
set -u
docker rm -f l9-sr >/dev/null 2>&1
docker run -d --network bench_kafka-net --name l9-sr \
  -e SCHEMA_REGISTRY_HOST_NAME=schema-registry \
  -e SCHEMA_REGISTRY_LISTENERS=http://0.0.0.0:8081 \
  -e SCHEMA_REGISTRY_KAFKASTORE_BOOTSTRAP_SERVERS=PLAINTEXT://kafka-1:9092,kafka-2:9092,kafka-3:9092 \
  -e SCHEMA_REGISTRY_KAFKASTORE_TOPIC=_schemas \
  -e SCHEMA_REGISTRY_KAFKASTORE_REPLICATION_FACTOR=3 \
  -e SCHEMA_REGISTRY_SCHEMA_COMPATIBILITY_LEVEL=backward \
  confluentinc/cp-schema-registry:7.6.1 >/dev/null 2>&1
echo "等待 SR 启动（JVM 冷启动较慢）..."
for i in $(seq 1 24); do
  sleep 5
  code=$(docker exec l9-sr curl -s -o /dev/null -w '%{http_code}' http://localhost:8081/subjects 2>/dev/null)
  if [ "$code" = "200" ]; then
    echo "SR 就绪（${i}0 秒内）"
    docker exec l9-sr curl -s http://localhost:8081/subjects
    echo
    exit 0
  fi
  echo "  ${i}0s: 未就绪 (http=$code)"
done
echo "SR 启动超时，查看日志："
docker logs l9-sr 2>&1 | tail -20
