#!/usr/bin/env bash
# 核验：65M 是不是 bolt 预分配？增量 0 是不是测量方式错了？
BASE=/tmp/consul-ops
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501
ADDR=http://127.0.0.1:8501

echo "########## 1. 拆解 65M：各文件占多少 ##########"
ls -la $BASE/data/node1/ 2>/dev/null
echo
echo "  raft/ 子目录:"
ls -la $BASE/data/node1/raft/ 2>/dev/null

echo
echo "########## 2. 逻辑大小 vs 磁盘占用（bolt 预分配特征）##########"
for f in $BASE/data/node1/raft/raft.db $BASE/data/node1/serf/local.snapshot; do
  [ -f "$f" ] && echo "  $(basename $f): 逻辑=$(stat -c%s $f) 占块=$(du -b $f | awk '{print $1}')"
done

echo
echo "########## 3. 正确测增量：用 KV 条数 + API，而不是 du ##########"
B=$(curl -s $ADDR/v1/kv/?keys 2>/dev/null | python3 -c "import sys,json;print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)
echo "  当前 KV 条数 = $B"
for i in $(seq 1 300); do curl -s -o /dev/null -X PUT -d "0123456789" "$ADDR/v1/kv/cost2/$i"; done
sleep 2
A=$(curl -s $ADDR/v1/kv/?keys | python3 -c "import sys,json;print(len(json.load(sys.stdin)))")
echo "  写入 300 条后 = $A（增量 $((A-B))）"

echo
echo "########## 4. 重测吞吐：用 batch 事务 vs 单条，看写放大成本 ##########"
echo "-- 单条写 100 次 --"
S=$(date +%s.%N)
for i in $(seq 1 100); do curl -s -o /dev/null -X PUT -d "v" "$ADDR/v1/kv/t1/$i"; done
E=$(date +%s.%N)
python3 -c "print(f'  耗时 {$E-$S:.2f}s → {100/($E-$S):.0f} 条/秒')"

echo "-- 事务批量写（100 条塞进 1 个 txn）--"
python3 - <<PYEOF
import json,urllib.request,time
ops=[{"KV":{"Verb":"set","Key":f"t2/{i}","Value":"dg=="}} for i in range(100)]
body=json.dumps(ops).encode()
t=time.time()
req=urllib.request.Request("http://127.0.0.1:8501/v1/txn",data=body,method="PUT")
urllib.request.urlopen(req,timeout=30)
print(f"  1 个事务写 100 条 耗时 {time.time()-t:.2f}s")
PYEOF

echo
echo "########## 5. 大 value 的成本（对比 10B vs 8KB vs 64KB）##########"
for SZ in 10 8192 65536; do
  V=$(python3 -c "print('x'*$SZ)")
  S=$(date +%s.%N)
  for i in $(seq 1 30); do curl -s -o /dev/null -X PUT -d "$V" "$ADDR/v1/kv/sz$SZ/$i"; done
  E=$(date +%s.%N)
  python3 -c "print(f'  value={$SZ:6d}B: 30 条耗时 {$E-$S:.2f}s → {30/($E-$S):.0f} 条/秒')"
done
