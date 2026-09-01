#!/usr/bin/env bash
# 课 7 备课实测 2b：CRC16 一致性校验（修正版）+ 哈希标签边界 case
set -u
CLI="redis-cli"

cat > /tmp/crc16_mod.py <<'PY'
def crc16(data: bytes) -> int:
    """CRC16-XMODEM: 多项式 0x1021, 初值 0x0000, 无反射, 无终异或"""
    crc = 0
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            if crc & 0x8000:
                crc = ((crc << 1) ^ 0x1021) & 0xFFFF
            else:
                crc = (crc << 1) & 0xFFFF
    return crc

def hash_slot(key: bytes) -> int:
    """Redis 哈希槽算法：先处理哈希标签，再 CRC16 & 16383"""
    s = key.find(b'{')
    if s != -1:
        e = key.find(b'}', s + 1)
        if e != -1 and e != s + 1:
            key = key[s+1:e]
    return crc16(key) & 16383
PY

echo "=== 1. 一致性校验：手写实现 vs CLUSTER KEYSLOT ==="
echo "  key                      KEYSLOT   手写实现   一致?"
pass=0; fail=0
while IFS= read -r k; do
  [ -z "$k" ] && continue
  a=$($CLI -p 7001 cluster keyslot "$k")
  b=$(KEYSLOT_KEY="$k" python3 -c "
import os,sys
sys.path.insert(0,'/tmp')
from crc16_mod import hash_slot
print(hash_slot(os.environ['KEYSLOT_KEY'].encode()))
")
  if [ "$a" = "$b" ]; then flag="YES"; pass=$((pass+1)); else flag="NO"; fail=$((fail+1)); fi
  printf "  %-24s %-10s %-10s %s\n" "$k" "$a" "$b" "$flag"
done <<'KEYS'
foo
bar
hello
world
user:1001
user:1002
user:1003
user:{1001}
user:{1001}:profile
user:{1001}:orders
{}abc
{}{abc}
a{b}c{d}
abc{
}{abc
user:{}:x
x{}y
{1001}
order:{A}:item
order:{A}:total
KEYS
echo "  结果：一致 $pass 个，不一致 $fail 个"

echo ""
echo "=== 2. 哈希标签边界 case（重点）==="
echo "  规则：取第一个 '{' 与其后第一个 '}' 之间的内容；"
echo "        若 {} 不存在、为空、或无闭合 → 整个 key 参与 CRC16"
echo ""
printf "  %-22s %-8s %s\n" "key" "slot" "参与计算的部分"
for k in "user:{1001}" "{1001}" "user:{1001}:profile" "{}abc" "user:{}:x" "abc{" "}{abc" "a{b}c{d}" "x{}y"; do
  s=$($CLI -p 7001 cluster keyslot "$k")
  # 推导实际参与部分
  part=$(python3 -c "
import sys
sys.path.insert(0,'/tmp')
from crc16_mod import hash_slot
k=b'''$k'''
s=k.find(b'{')
if s!=-1:
    e=k.find(b'}',s+1)
    if e!=-1 and e!=s+1:
        k=k[s+1:e]
print(repr(k.decode()))
")
  printf "  %-22s %-8s %s\n" "$k" "$s" "$part"
done

echo ""
echo "=== 3. 哈希标签的实用价值：让相关数据落在同一槽 ==="
echo "  -- 场景：用户 1001 的 profile / orders / cart 需要一起操作 --"
echo "  不带标签（分散到不同槽，无法原子操作）："
for k in "user:1001:profile" "user:1001:orders" "user:1001:cart"; do
  s=$($CLI -p 7001 cluster keyslot "$k")
  printf "    %-22s -> slot %-6s\n" "$k" "$s"
done
echo "  带标签（全部同槽，可 MGET / 事务 / Lua 原子操作）："
for k in "user:{1001}:profile" "user:{1001}:orders" "user:{1001}:cart"; do
  s=$($CLI -p 7001 cluster keyslot "$k")
  printf "    %-22s -> slot %-6s\n" "$k" "$s"
done

echo ""
echo "=== 4. 实测：跨槽多 key 操作被拒绝 ==="
echo "  -- 不带标签，MGET 跨槽 --"
$CLI -c -p 7001 mget "user:1001:profile" "user:1001:orders" "user:1001:cart" 2>&1 | head -3
echo "  -- 带标签，MGET 同槽 --"
$CLI -c -p 7001 mset "user:{1001}:profile" p1 "user:{1001}:orders" o1 "user:{1001}:cart" c1 2>&1 | head -3
$CLI -c -p 7001 mget "user:{1001}:profile" "user:{1001}:orders" "user:{1001}:cart" 2>&1 | head -5

echo ""
echo "=== 5. 热点风险：哈希标签用错的后果 ==="
echo "  若所有 key 都用同一个标签（如 {global}），会全部挤到同一槽："
for k in "{global}:a" "{global}:b" "{global}:c"; do
  s=$($CLI -p 7001 cluster keyslot "$k")
  printf "    %-16s -> slot %s\n" "$k" "$s"
done
echo "  → 单槽单节点，集群失去分片意义（其余 16383 槽空闲）"

echo ""
echo "=== 完成 ==="
