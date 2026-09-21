#!/usr/bin/env bash
# 决定性判据：用旧快照恢复全新集群，看 CA 是否还原
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501
D=/tmp/consul-ops

echo "########## 恢复前的状态 ##########"
echo "  ActiveRootID = $(curl -s $CONSUL_HTTP_ADDR/v1/connect/ca/roots | python3 -c 'import sys,json;print(json.load(sys.stdin)["ActiveRootID"])')"
echo "  marker(KV)   = $(curl -s $CONSUL_HTTP_ADDR/v1/kv/lesson5/marker?raw 2>/dev/null || echo '(不存在)')"

echo
echo "########## 执行快照恢复 ##########"
consul snapshot restore $D/tls/full.snap 2>&1 | sed 's/^/  /'
sleep 5

echo
echo "########## 恢复后的状态 ##########"
curl -s $CONSUL_HTTP_ADDR/v1/connect/ca/roots > $D/tls/roots_restored.json
python3 /mnt/d/projects/learning/consul/playground-ops/cmp_all.py
echo "  marker(KV) = $(curl -s $CONSUL_HTTP_ADDR/v1/kv/lesson5/marker?raw 2>/dev/null || echo '(不存在)')"
