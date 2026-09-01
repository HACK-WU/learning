#!/usr/bin/env bash
# 课 7 备课实测 2：CRC16 算法、哈希标签、key 归属验证
set -u
CLI="redis-cli"
C="$CLI -c -p 7001"

echo "=== 1. CLUSTER KEYSLOT 基本验证 ==="
for k in foo bar hello world user:1001 user:1002 user:1003; do
  s=$($CLI -p 7001 cluster keyslot "$k")
  printf "  %-12s -> slot %s\n" "$k" "$s"
done

echo ""
echo "=== 2. 手写 CRC16-XMODEM 实现（与 Redis 一致性校验）==="
cat > /tmp/crc16.py <<'PY'
def crc16(data: bytes) -> int:
    crc = 0
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            if crc & 0x8000:
                crc = ((crc << 1) ^ 0x1021) & 0xFFFF
            else:
                crc = (crc << 1) & 0xFFFF
    return crc

def hash_slot(key: str) -> int:
    # 哈希标签：只有第一个 { 和其后第一个 } 之间的内容参与计算
    s = key.find(b'{')
    if s != -1:
        e = key.find(b'}', s + 1)
        if e != -1 and e != s + 1:
            key = key[s+1:e]
    return crc16(key) & 16383

tests = ["foo","bar","hello","world","user:1001","user:1002",
         "user:{1001}","user:{1001}:profile","user:{1001}:orders",
         "{}abc","{}{abc}","a{b}c{d}","abc{","}{abc","user:{}:x","x{}y"]
for t in tests:
    print(f"{t:24s} -> {hash_slot(t.encode())}")
PY
python3 /tmp/crc16.py

echo ""
echo "=== 3. 与 CLUSTER KEYSLOT 对比（一致性校验）==="
echo "  key                      KEYSLOT   手写实现   一致?"
for k in foo bar hello world user:1001 user:1002 "user:{1001}" "user:{1001}:profile" "user:{1001}:orders" "a{b}c{d}" "x{}y"; do
  a=$($CLI -p 7001 cluster keyslot "$k")
  b=$(python3 -c "
import sys
sys.path.insert(0,'/tmp')
from crc16 import hash_slot
print(hash_slot('''$k'''.encode()))
" 2>/dev/null)
  if [ "$a" = "$b" ]; then flag="YES"; else flag="NO  <-- 不一致"; fi
  printf "  %-24s %-10s %-10s %s\n" "$k" "$a" "$b" "$flag"
done

echo ""
echo "=== 4. 哈希标签：同标签必定同槽 ==="
echo "  -- 带标签（应全部同槽）--"
for k in "user:{1001}:profile" "user:{1001}:orders" "user:{1001}:cart" "{1001}"; do
  s=$($CLI -p 7001 cluster keyslot "$k")
  printf "    %-24s -> %s\n" "$k" "$s"
done
echo "  -- 不带标签（应分散）--"
for k in "user:1001:profile" "user:1001:orders" "user:1001:cart" "1001"; do
  s=$($CLI -p 7001 cluster keyslot "$k")
  printf "    %-24s -> %s\n" "$k" "$s"
done

echo ""
echo "=== 5. 实际写入：观察重定向 ==="
echo "  -- 用 -c（集群模式，自动跟随重定向）--"
for k in foo bar hello world user:1001; do
  r=$($C set "$k" "v-$k" 2>&1)
  printf "    SET %-10s -> %s\n" "$k" "$r"
done

echo ""
echo "  -- 不用 -c（单机模式连到 7001）--"
for k in foo bar hello world user:1001; do
  r=$($CLI -p 7001 set "$k" "v-$k" 2>&1)
  printf "    SET %-10s -> %s\n" "$k" "$r"
done

echo ""
echo "=== 6. MOVED 重定向原文 ==="
echo "  --- 单机模式访问不属于本节点的 key ---"
$CLI -p 7001 get foo 2>&1
$CLI -p 7001 get hello 2>&1

echo ""
echo "  --- cluster countkeysinslot 统计 ---"
for s in 0 5461 10923; do
  n=$($CLI -p 7001 cluster countkeysinslot $s 2>&1)
  echo "    slot $s: $n keys"
done

echo ""
echo "=== 7. 找出每个 key 实际落在哪个节点 ==="
echo "  key                  slot    所在节点(port)"
for k in foo bar hello world user:1001 user:1002 user:1003; do
  s=$($CLI -p 7001 cluster keyslot "$k")
  for p in 7001 7002 7003; do
    n=$($CLI -p $p cluster countkeysinslot $s 2>/dev/null)
    if [ "${n:-0}" != "0" ] && [ -n "${n:-}" ]; then echo "    $k -> slot $s -> $p (countkeysinslot=$n)"; fi
  done
done

echo ""
echo "=== 8. 用 dbsize 交叉验证分布 ==="
for p in 7001 7002 7003; do
  echo "    $p dbsize = $($CLI -p $p dbsize 2>/dev/null)"
done

echo ""
echo "=== 完成 ==="
