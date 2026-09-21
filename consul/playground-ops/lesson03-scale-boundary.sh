#!/usr/bin/env bash
# 知识点 1：规模边界——写入吞吐基线 + 写放大（1 条 KV → 落几份）+ value 大小影响
BASE=/tmp/consul-ops
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501
ADDR=http://127.0.0.1:8501

echo "########## 0. 基线：磁盘上 Raft 数据占多少（空集群）##########"
du -sh $BASE/data/node1 2>/dev/null

echo
echo "########## 1. 写入吞吐基线（小 value，100 条串行）##########"
START=$(date +%s.%N)
for i in $(seq 1 100); do
  curl -s -o /dev/null -X PUT -d "v$i" "$ADDR/v1/kv/perf/small/$i"
done
END=$(date +%s.%N)
python3 -c "
d=$END-$START
print(f'  100 条串行写入耗时 {d:.2f}s → {100/d:.1f} 条/秒，单条平均 {d/100*1000:.1f} ms')"

echo
echo "########## 2. 写放大：1 条 KV 在三个节点各落一份？##########"
curl -s -o /dev/null -X PUT -d "amplification-test-value" "$ADDR/v1/kv/perf/amp/probe"
sleep 2
for i in 1 2 3; do
  SZ=$(du -sb $BASE/data/node$i 2>/dev/null | awk '{print $1}')
  HAS=$(curl -s "http://127.0.0.$i:$((8500+i))/v1/kv/perf/amp/probe?raw" 2>/dev/null)
  echo "  node$i 数据目录=$SZ 字节  本节点能读到=[${HAS:0:30}]"
done

echo
echo "########## 3. value 大小对吞吐的影响（每条 8KB，写 50 条）##########"
BIG=$(python3 -c "print('x'*8192)")
START=$(date +%s.%N)
for i in $(seq 1 50); do
  curl -s -o /dev/null -X PUT -d "$BIG" "$ADDR/v1/kv/perf/big/$i"
done
END=$(date +%s.%N)
python3 -c "
d=$END-$START
print(f'  50 条 8KB 写入耗时 {d:.2f}s → {50/d:.1f} 条/秒，单条 {d/50*1000:.1f} ms')"

echo
echo "########## 4. 写入后 Raft 日志增长量 ##########"
for i in 1 2 3; do
  echo "  node$i: $(du -sh $BASE/data/node$i 2>/dev/null | awk '{print $1}')"
done
echo "  raft Commit Index: $(consul operator raft list-peers | awk 'NR==2{print $7}')"

echo
echo "########## 5. 单条 KV 的磁盘成本（粗测）##########"
BEFORE=$(du -sb $BASE/data/node1 2>/dev/null | awk '{print $1}')
for i in $(seq 1 200); do
  curl -s -o /dev/null -X PUT -d "0123456789" "$ADDR/v1/kv/perf/cost/$i"
done
sleep 3
AFTER=$(du -sb $BASE/data/node1 2>/dev/null | awk '{print $1}')
python3 -c "
b=$BEFORE; a=$AFTER
print(f'  200 条 10B KV → node1 目录增长 {a-b} 字节 → 约 {(a-b)/200:.0f} 字节/条（含 Raft 日志开销）')"
