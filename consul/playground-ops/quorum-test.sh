#!/usr/bin/env bash
BASE=/tmp/consul-ops
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501

echo "===== A. 基线：写入一个 KV ====="
curl -s -X PUT -d 'quorum-test' http://127.0.0.1:8501/v1/kv/ops/quorum
echo "written"

echo
echo "===== B. 停掉 1 个 follower (node3)，剩 2/3 ====="
pkill -f 'conf/node3.hcl'
sleep 6
echo "-- members --"
consul members 2>&1 | head -6
echo "-- 写还能成功吗（quorum 2/3）--"
curl -s -X PUT -d 'after-1-down' http://127.0.0.1:8501/v1/kv/ops/quorum && echo "WRITE OK"
echo "-- 读 --"
curl -s http://127.0.0.1:8501/v1/kv/ops/quorum?raw; echo

echo
echo "===== C. 再停 1 个 (node2=leader)，只剩 1/3 ====="
pkill -f 'conf/node2.hcl'
sleep 6
echo "-- 写（预期失败：无 quorum）--"
curl -s --max-time 8 -X PUT -d 'should-fail' http://127.0.0.1:8501/v1/kv/ops/quorum || echo "WRITE FAILED (exit=$?)"
echo
echo "-- 读（预期失败或 stale）--"
curl -s --max-time 8 http://127.0.0.1:8501/v1/kv/ops/quorum?raw || echo "READ FAILED (exit=$?)"
echo
echo "-- 剩余节点日志尾部 --"
tail -5 "$BASE/log/node1.log"
