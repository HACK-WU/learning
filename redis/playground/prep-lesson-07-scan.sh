#!/usr/bin/env bash
# 课 7 备课实测 9：Redis 8 SCAN 槽优化 + 集群批量导入正确姿势
set -u
CLI="redis-cli"

echo "############################################################"
echo "# 1. Redis 8.0 新模式：含 hash tag 的 SCAN 只扫对应槽"
echo "############################################################"
echo ""
echo "  官方文档（Redis 8.0+）："
echo "    KEYS / SCAN / SORT 等接受 glob pattern 的命令，"
echo "    若 pattern 含 hash tag 且前面无通配符 → 只扫描该槽"
echo ""
echo "  实测：对比带 tag 与不带 tag 的 SCAN 耗时"
echo ""

# 灌数据：带 tag 的 key 与不带的 key 各一批
echo "  准备数据..."
$CLI -p 7001 flushall >/dev/null 2>&1
$CLI -p 7002 flushall >/dev/null 2>&1
$CLI -p 7003 flushall >/dev/null 2>&1
sleep 0.5

# 写入 2000 个带 {tag1} 的 key 和 2000 个普通 key
python3 -c "
for i in range(2000):
    print(f'SET {{tag1}}:k{i} v{i}')
    print(f'SET plain:k{i} v{i}')
" > /tmp/l07-scan-data.txt

# 按槽分组写入
python3 - <<'PY'
import subprocess,sys
sys.path.insert(0,'/tmp')
from crc16_mod import hash_slot
out=subprocess.run(["redis-cli","-p","7001","cluster","nodes"],capture_output=True,text=True).stdout
node_slots={}
for l in out.splitlines():
    f=l.split()
    if len(f)<8 or 'master' not in f[2]: continue
    port=f[1].split('@')[0].split(':')[1]
    for tok in f[8:]:
        tok=tok.strip('[]')
        if '-' in tok:
            a,b=tok.split('-')
            if a.isdigit() and b.isdigit():
                node_slots[port]=node_slots.get(port,[])+list(range(int(a),int(b)+1))
s2p={}
for p,ss in node_slots.items():
    for s in ss: s2p[s]=p
groups={}
for i in range(2000):
    for k in [f"{{tag1}}:k{i}", f"plain:k{i}"]:
        p=s2p.get(hash_slot(k.encode()))
        if p: groups.setdefault(p,[]).append(k)
for p,ks in groups.items():
    with open(f"/tmp/l07-sd-{p}.txt","w") as fh:
        for k in ks: fh.write(f"SET {k} v\n")
    print(f"    节点 {p}: {len(ks)} keys")
PY

for p in 7001 7002 7003; do
  [ -f /tmp/l07-sd-$p.txt ] && $CLI -p $p --pipe < /tmp/l07-sd-$p.txt 2>&1 | tail -1
done
sleep 0.5
echo ""
total=0
for p in 7001 7002 7003; do
  n=$($CLI -p $p dbsize); total=$((total+n)); echo "    $p dbsize = $n"
done
echo "    合计 = $total"

echo ""
echo "  -- 测试 A：带 hash tag 的 SCAN（应只扫 1 个槽）--"
start=$(date +%s%N)
c1=$($CLI -c -p 7001 --scan --pattern '{tag1}*' 2>/dev/null | wc -l)
end=$(date +%s%N)
echo "    SCAN MATCH '{tag1}*'  → 匹配 $c1 个，耗时 $(( (end-start)/1000000 )) ms"

echo ""
echo "  -- 测试 B：不带 tag 的 SCAN（需扫全部槽）--"
start=$(date +%s%N)
c2=$($CLI -c -p 7001 --scan --pattern 'plain:*' 2>/dev/null | wc -l)
end=$(date +%s%N)
echo "    SCAN MATCH 'plain:*'   → 匹配 $c2 个，耗时 $(( (end-start)/1000000 )) ms"

echo ""
echo "  ★ 差异说明：带 tag 的 pattern 能定位到单个槽，避免全集群扫描"

echo ""
echo "############################################################"
echo "# 2. 集群批量导入的正确姿势（--pipe 失效的根因与解法）"
echo "############################################################"
echo ""
echo "  实测数据汇总（3000 个 key）："
echo "    方式 1  redis-cli --pipe 直连单节点      → 失败 1878/3000"
echo "    方式 2  逐条 redis-cli -c set            → 全成功，4.78 秒"
echo "    方式 3  按槽分组后各节点 --pipe          → 全成功，最快"
echo ""
echo "  根因：--pipe 是『批量管道』，它把命令一股脑发给连上的那个节点，"
echo "        不解析 MOVED、不重定向。落到别的槽的命令直接失败。"
echo ""
echo "  这次用修正后的分组脚本重测："
echo ""

for p in 7001 7002 7003; do $CLI -p $p flushall >/dev/null 2>&1; done
sleep 0.5

python3 -c "
for i in range(3000):
    print(f'SET k{i} v{i}')
" > /tmp/l07-imp.txt

# 正确分组
python3 - <<'PY'
import subprocess,sys
sys.path.insert(0,'/tmp')
from crc16_mod import hash_slot
out=subprocess.run(["redis-cli","-p","7001","cluster","nodes"],capture_output=True,text=True).stdout
node_slots={}
for l in out.splitlines():
    f=l.split()
    if len(f)<8 or 'master' not in f[2]: continue
    port=f[1].split('@')[0].split(':')[1]
    for tok in f[8:]:
        tok=tok.strip('[]')
        if '-' in tok:
            a,b=tok.split('-')
            if a.isdigit() and b.isdigit():
                node_slots[port]=node_slots.get(port,[])+list(range(int(a),int(b)+1))
s2p={}
for p,ss in node_slots.items():
    for s in ss: s2p[s]=p
groups={}
for i in range(3000):
    k=f"k{i}"; p=s2p.get(hash_slot(k.encode()))
    if p: groups.setdefault(p,[]).append(k)
for p,ks in groups.items():
    with open(f"/tmp/l07-imp-{p}.txt","w") as fh:
        for k in ks: fh.write(f"SET {k} v\n")
    print(f"    分组 → 节点 {p}: {len(ks)} keys")
PY

start=$(date +%s%N)
for p in 7001 7002 7003; do
  [ -f /tmp/l07-imp-$p.txt ] && $CLI -p $p --pipe < /tmp/l07-imp-$p.txt 2>&1 | grep -E 'errors' | sed "s/^/节点 $p: /"
done
end=$(date +%s%N)
echo "    分组 --pipe 耗时: $(( (end-start)/1000000 )) ms"

total=0
for p in 7001 7002 7003; do
  n=$($CLI -p $p dbsize); total=$((total+n)); echo "    $p dbsize = $n"
done
echo "    合计 = $total / 3000"

echo ""
echo "############################################################"
echo "# 3. 集群下的 FLUSHALL / 多数据库限制"
echo "############################################################"
echo ""
echo "  -- 集群不支持 SELECT（只有 db 0）--"
$CLI -c -p 7001 select 1 2>&1 | head -1
echo ""
echo "  -- FLUSHALL 在集群下只清当前节点 --"
echo "    执行前: 7001=$($CLI -p 7001 dbsize) 7002=$($CLI -p 7002 dbsize) 7003=$($CLI -p 7003 dbsize)"
$CLI -p 7001 flushall >/dev/null 2>&1
echo "    flushall 7001 后: 7001=$($CLI -p 7001 dbsize) 7002=$($CLI -p 7002 dbsize) 7003=$($CLI -p 7003 dbsize)"
echo "    → 其他节点数据仍在！集群清库要逐节点执行或用 --cluster call"
echo ""
echo "  -- 用 redis-cli --cluster call 批量执行 --"
$CLI -c -p 7001 set testkey 1 >/dev/null 2>&1
$CLI --cluster call 127.0.0.1:7001 dbsize 2>&1 | head -8

echo ""
echo "############################################################"
echo "# 4. CLUSTER COUNTKEYSINSLOT 与运维常用命令"
echo "############################################################"
echo ""
echo "  -- 查看某槽的 key 数 --"
for s in 0 5000 10000 15000; do
  n=$($CLI -p 7001 cluster countkeysinslot $s 2>&1)
  printf "    slot %-6s → %s keys\n" "$s" "$n"
done
echo ""
echo "  -- 列出某槽里的 key（CLUSTER GETKEYSINSLOT）--"
$CLI -p 7001 cluster getkeysinslot 5000 5 2>&1 | head -6

echo ""
echo "  -- 槽归属速查（CLUSTER KEYSLOT + CLUSTER NODES）--"
for k in "user:1001" "order:{1001}:item"; do
  s=$($CLI -p 7001 cluster keyslot "$k")
  printf "    %-22s → slot %s\n" "$k" "$s"
done

echo ""
echo "=== 完成 ==="
