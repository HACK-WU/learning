#!/usr/bin/env bash
BASE=/tmp/consul-ops
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501
set -e

echo "===== 1. 写入基线数据 ====="
for k in a b c; do
  curl -s -X PUT -d "value-$k" "http://127.0.0.1:8501/v1/kv/ops/$k" > /dev/null
done
curl -s http://127.0.0.1:8501/v1/kv/ops/?keys

echo
echo "===== 2. 打快照 ====="
consul snapshot save "$BASE/full.snap"

echo
echo "===== 3. 删掉数据（模拟误删）====="
curl -s -X DELETE "http://127.0.0.1:8501/v1/kv/ops/?recurse" > /dev/null
echo "删除后剩余:"
curl -s http://127.0.0.1:8501/v1/kv/ops/?keys; echo "(空)"

echo
echo "===== 4. 从快照恢复 ====="
consul snapshot restore "$BASE/full.snap"

echo
echo "===== 5. 验证数据回来了 ====="
sleep 2
curl -s http://127.0.0.1:8501/v1/kv/ops/?keys
for k in a b c; do
  printf "  %s = %s\n" "$k" "$(curl -s http://127.0.0.1:8501/v1/kv/ops/$k?raw)"
done
