#!/usr/bin/env bash
BASE=/tmp/consul-ops
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501
SECRET=$(grep 'SecretID' "$BASE/acl/boot.txt" | awk '{print $2}')
export CONSUL_HTTP_TOKEN="$SECRET"

echo "===== 1. Raft 健康：last_contact / commit index ====="
consul operator raft list-peers

echo
echo "===== 2. 写性能：连续 50 次 KV 写 ====="
start=$(date +%s%N)
for i in $(seq 1 50); do
  curl -s -X PUT -d "perf-$i" -H "X-Consul-Token: $SECRET" "http://127.0.0.1:8501/v1/kv/perf/$i" > /dev/null
done
end=$(date +%s%N)
ms=$(( (end-start)/1000000 ))
echo "50 次写耗时 ${ms}ms → 平均 $((ms/50))ms/次"

echo
echo "===== 3. 读性能（stale vs 默认一致性）====="
s1=$(date +%s%N)
for i in $(seq 1 50); do curl -s "http://127.0.0.1:8501/v1/kv/perf/$i?raw&stale" -H "X-Consul-Token: $SECRET" > /dev/null; done
e1=$(date +%s%N)
echo "stale 读 50 次: $(( (e1-s1)/1000000 ))ms"

s2=$(date +%s%N)
for i in $(seq 1 50); do curl -s "http://127.0.0.1:8501/v1/kv/perf/$i?raw" -H "X-Consul-Token: $SECRET" > /dev/null; done
e2=$(date +%s%N)
echo "强一致读 50 次: $(( (e2-s2)/1000000 ))ms"

echo
echo "===== 4. 阻塞查询（变更通知/长轮询）====="
echo "-- 先拿 index --"
IDX=$(curl -si -H "X-Consul-Token: $SECRET" "http://127.0.0.1:8501/v1/kv/ops/a" | grep -i '^X-Consul-Index' | tr -d '\r' | awk '{print $2}')
echo "current X-Consul-Index = $IDX"
echo "-- 阻塞查询 5s（期间另一进程写入则立即返回）--"
( sleep 2; curl -s -X PUT -d 'changed' -H "X-Consul-Token: $SECRET" "http://127.0.0.1:8501/v1/kv/ops/a" > /dev/null ) &
s3=$(date +%s%N)
curl -s -H "X-Consul-Token: $SECRET" "http://127.0.0.1:8501/v1/kv/ops/a?index=$IDX&wait=5s" > /dev/null
e3=$(date +%s%N)
echo "阻塞查询返回耗时: $(( (e3-s3)/1000000 ))ms （无变更应≈5000ms，有变更提前返回）"
wait

echo
echo "===== 5. 清理 perf 数据 ====="
curl -s -X DELETE -H "X-Consul-Token: $SECRET" "http://127.0.0.1:8501/v1/kv/perf/?recurse" > /dev/null && echo "cleaned"
