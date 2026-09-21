#!/usr/bin/env bash
# 修正：中文变量名导致 python 语法错误；重测三种读模式延迟
ADDR=http://127.0.0.1:8501
export CONSUL_HTTP_ADDR=$ADDR

echo "########## 1. 三种读模式各 300 次 ##########"
bench() {
  local name="$1" url="$2"
  local S E
  S=$(date +%s.%N)
  for i in $(seq 1 300); do curl -s -o /dev/null "$url"; done
  E=$(date +%s.%N)
  python3 -c "
import sys
n='$name'
s=$S; e=$E
print(f'  {n:22s} 300 次 {e-s:.3f}s  单次 {(e-s)/300*1000:.2f} ms')"
}

bench "default"     "$ADDR/v1/kv/perf/small/1?raw"
bench "consistent"  "$ADDR/v1/kv/perf/small/1?raw&consistent"
bench "stale"       "$ADDR/v1/kv/perf/small/1?raw&stale"

echo
echo "########## 2. stale 在 follower 上 vs leader 上 ##########"
LN=$(consul operator raft list-peers | awk '$4=="leader"{print $1}' | grep -oE '[0-9]+$')
for i in 1 2 3; do
  S=$(date +%s.%N)
  for k in $(seq 1 100); do curl -s -o /dev/null "http://127.0.0.$i:$((8500+i))/v1/kv/perf/small/1?raw&stale"; done
  E=$(date +%s.%N)
  ROLE=$(consul operator raft list-peers | awk -v x="ops-node-$i" '$1==x{print $4}')
  python3 -c "print(f'  node$i ({\"$ROLE\":9s}) stale 100 次 {($E-$S)/100*1000:.2f} ms/次')"
done

echo
echo "########## 3. 陈旧窗口：写完后 follower stale 多久追上 ##########"
LN=$(consul operator raft list-peers | awk '$4=="leader"{print $1}' | grep -oE '[0-9]+$')
FN=$(consul operator raft list-peers | awk '$4!="leader"{print $1}' | head -1 | grep -oE '[0-9]+$')
echo "  leader=node$LN  follower=node$FN"

for round in 1 2 3; do
  curl -s -o /dev/null -X PUT -d "old-$round" "$ADDR/v1/kv/lag/p"
  sleep 1
  curl -s -o /dev/null -X PUT -d "NEW-$round" "http://127.0.0.$LN:$((8500+LN))/v1/kv/lag/p"
  # 立刻在 follower 上反复 stale 读，测多久追上
  FOUND=""
  for t in $(seq 1 30); do
    R=$(curl -s --max-time 2 "http://127.0.0.$FN:$((8500+FN))/v1/kv/lag/p?raw&stale")
    if [ "$R" = "NEW-$round" ]; then FOUND=$t; break; fi
    sleep 0.1
  done
  if [ -n "$FOUND" ]; then
    python3 -c "print(f'  第$round 轮: stale 追上新值用了约 {$FOUND*0.1:.1f}s')"
  else
    echo "  第$round 轮: 3s 内未追上"
  fi
done

echo
echo "########## 4. consistent 读：任何节点都返回新值？（代价是过 Raft）##########"
curl -s -o /dev/null -X PUT -d "FINAL-VALUE" "$ADDR/v1/kv/lag/p"
for i in 1 2 3; do
  echo "  node$i consistent = $(curl -s --max-time 3 "http://127.0.0.$i:$((8500+i))/v1/kv/lag/p?raw&consistent")"
done
