#!/bin/bash
# 诊断2：set_config 返回 {} —— 策略到底设上没有？
# 方法：绕过 Python 客户端，直接查 SR 的 REST API 看配置
set -u
echo "=== 1. 全局默认配置 ==="
docker exec l9-sr curl -s http://localhost:8081/config
echo ""
echo ""
echo "=== 2. DIAG-full 这个 subject 的 subject 级配置 ==="
docker exec l9-sr curl -s http://localhost:8081/config/DIAG-full
echo ""
echo ""
echo "=== 3. 所有 subject ==="
docker exec l9-sr curl -s http://localhost:8081/subjects
echo ""
echo ""
echo "=== 4. 用 REST 直接设 full 再查 ==="
docker exec l9-sr curl -s -X PUT -H "Content-Type: application/json" \
  -d '{"compatibility": "FULL"}' http://localhost:8081/config/REST-full
echo ""
docker exec l9-sr curl -s http://localhost:8081/config/REST-full
echo ""
echo ""
echo "=== 5. 用 REST 注册 v1 再注册 v2（删字段），看是否被拒 ==="
docker exec l9-sr curl -s -X POST -H "Content-Type: application/json" \
  -d '{"schema": "{\"type\":\"record\",\"name\":\"RP\",\"fields\":[{\"name\":\"a\",\"type\":\"string\"},{\"name\":\"b\",\"type\":\"int\"}]}"}' \
  http://localhost:8081/subjects/REST-full/versions
echo ""
docker exec l9-sr curl -s -X POST -H "Content-Type: application/json" \
  -d '{"schema": "{\"type\":\"record\",\"name\":\"RP\",\"fields\":[{\"name\":\"b\",\"type\":\"int\"}]}"}' \
  http://localhost:8081/subjects/REST-full/versions
echo ""
