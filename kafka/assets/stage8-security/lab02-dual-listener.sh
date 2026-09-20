#!/bin/bash
# 课 8 实验 2：双监听器改造 —— 阶段一"先加门，不锁门"
#
# 设计（关键：先加监听器，不强制认证，保证老客户端零中断）：
#   PLAINTEXT://0.0.0.0:9092       老客户端专用（保持不动）
#   SASL_PLAINTEXT://0.0.0.0:9095  新客户端专用（先加，还没人用）
#   CONTROLLER://0.0.0.0:29093     控制面（保持 PLAINTEXT）
#
# 这一步 ONLY 增加监听器，不动 inter.broker.listener.name，
# 也不开 authorizer —— 老客户端完全无感。
set -e
cd /mnt/d/projects/learning/kafka/assets/stage6-observability || exit 1

echo "=== 2-0. 备份原 compose ==="
cp docker-compose.yml docker-compose.yml.bak.lesson08
echo "已备份到 docker-compose.yml.bak.lesson08"

echo ""
echo "=== 2-1. 改造每个节点：加 SASL_PLAINTEXT 监听器 + SCRAM 机制 ==="
# 用 sed 在 KAFKA_LISTENERS 中加入 SASL_PLAINTEXT，在 ADVERTISED 中加入，在协议映射中加入
# 注意：这里先只加监听器与协议映射，不改 inter.broker.listener.name
docker compose down 2>&1 | tail -3
echo "集群已停止（滚动改造前的准备：先验证配置能起来）"
