#!/usr/bin/env bash
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501
D=/tmp/consul-ops

echo "########## A. snapshot inspect：快照到底含哪些类型 ##########"
consul snapshot inspect $D/tls/full.snap 2>&1 | sed 's/^/  /'

echo
echo "########## B. 全量覆盖实验：验证『恢复是全量覆盖，快照后数据会丢』##########"
echo "--- B1. 恢复后（当前状态）写一个新 KV ---"
curl -s -X PUT -d 'after-restore' $CONSUL_HTTP_ADDR/v1/kv/lesson5/after > /dev/null
echo "  写入 lesson5/after = after-restore"
echo "  当前 lesson5/marker = $(curl -s $CONSUL_HTTP_ADDR/v1/kv/lesson5/marker?raw)"
echo "  当前 lesson5/after  = $(curl -s $CONSUL_HTTP_ADDR/v1/kv/lesson5/after?raw)"

echo
echo "--- B2. 再恢复一次旧快照（该快照只含 marker，不含 after）---"
consul snapshot restore $D/tls/full.snap 2>&1 | sed 's/^/  /'
sleep 4

echo
echo "--- B3. 恢复后检查：after 还在吗？---"
echo "  lesson5/marker = $(curl -s $CONSUL_HTTP_ADDR/v1/kv/lesson5/marker?raw 2>/dev/null || echo '(丢了)')"
echo "  lesson5/after  = $(curl -s $CONSUL_HTTP_ADDR/v1/kv/lesson5/after?raw 2>/dev/null || echo '(丢了)')"
echo "  → after 丢了即证明：恢复是全量覆盖，不是合并"
