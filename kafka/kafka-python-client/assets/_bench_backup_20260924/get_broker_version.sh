#!/bin/bash
# 查 broker 真实版本（已知镜像是 apache/kafka:4.0.0，但要实证）
docker exec l15-kafka-1 bash -c 'ls /opt/kafka/libs/ 2>/dev/null | grep -E "^kafka_" | head -5'
echo "--- 镜像标签 ---"
docker inspect l15-kafka-1 --format '{{.Config.Image}}'
echo "--- 通过 kafka-python 的 api_versions 探协议版本范围 ---"
