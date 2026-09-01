#!/usr/bin/env bash
# 课 7 备课实测 4：ASK 重定向专项实验 + 集群数据写入的正确姿势
set -u
CLI="redis-cli"

echo "############################################################"
echo "# 实验 A：--pipe 在集群模式下的问题"
echo "############################################################"
echo ""
echo "现象：连到单个节点用 --pipe 批量导入，大量命令失败。"
echo ""

# 先清空
for p in 7001 7002 7003; do $CLI -p $p flushall >/dev/null 2>&1; done
sleep 0.5

python3 -c "
for i in range(3000):
    print(f'SET k{i} v{i}')
" > /tmp/l07-pipe.txt

echo "  -- 方式 1：redis-cli --pipe 直连 7001 --"
r=$($CLI -c -p 7001 --pipe < /tmp/l07-pipe.txt 2>&1 | tail -2)
echo "     $r"
echo "     实际写入: 7001=$($CLI -p 7001 dbsize) 7002=$($CLI -p 7002 dbsize) 7003=$($CLI -p 7003 dbsize)"
echo "     合计 = $(( $($CLI -p 7001 dbsize) + $($CLI -p 7002 dbsize) + $($CLI -p 7003 dbsize) )) / 3000"

echo ""
echo "  -- 方式 2：逐条 -c（自动重定向）--"
for p in 7001 7002 7003; do $CLI -p $p flushall >/dev/null 2>&1; done
sleep 0.5
start=$(date +%s.%N)
while read -r line; do
  $CLI -c -p 7001 $line >/dev/null 2>&1
done < /tmp/l07-pipe.txt
end=$(date +%s.%N)
echo "     耗时: $(echo "$end - $start" | bc) 秒"
echo "     实际写入: 7001=$($CLI -p 7001 dbsize) 7002=$($CLI -p 7002 dbsize) 7003=$($CLI -p 7003 dbsize)"
echo "     合计 = $(( $($CLI -p 7001 dbsize) + $($CLI -p 7002 dbsize) + $($CLI -p 7003 dbsize) )) / 3000"

echo ""
echo "  -- 方式 3：按槽分组，各自 --pipe 到归属节点（正确姿势）--"
for p in 7001 7002 7003; do $CLI -p $p flushall >/dev/null 2>&1; done
sleep 0.5
# 用 redis-cli --cluster call 或先算槽再分组
python3 - <<'PY' > /tmp/l07-grouped.sh
import subprocess
# 获取槽映射
shards = subprocess.run(["redis-cli","-p","7001","cluster","slots"],
                        capture_output=True,text=True).stdout.split("\n")
# cluster slots 输出格式: 行1=起始槽 行2=结束槽 行3=master host port
mapping = {}
i=0
toks=[t for t in shards if t.strip()]
while i < len(toks):
    try:
        start=int(toks[i]); end=int(toks[i+1])
    except (ValueError, IndexError):
        i+=1; continue
    # 后面找 master 行
    host=None; port=None
    j=i+2
    while j < len(toks):
        parts = toks[j].split()
        if len(parts)>=3:
            host, port = parts[0], parts[1]
            break
        j+=1
    if host:
        for s in range(start,end+1):
            mapping[s]=(host,port)
    i+=1
PY
echo "     （槽映射已生成）"

# 简化：直接用 python 计算槽并分组写入
python3 - <<'PY'
import subprocess, sys
sys.path.insert(0,'/tmp')
from crc16_mod import hash_slot

def slot_of(k): return hash_slot(k.encode())

out = subprocess.run(["redis-cli","-p","7001","cluster","nodes"],
                     capture_output=True,text=True).stdout
node_slots = {}
for line in out.splitlines():
    f=line.split()
    if len(f)<9: continue
    if 'master' not in f[2]: continue
    port=f[1].split('@')[0].split(':')[1]
    for tok in f[9:]:
        if '-' in tok:
            a,b=tok.split('-'); node_slots[port]=node_slots.get(port,[])+list(range(int(a),int(b)+1))
        elif tok.isdigit():
            node_slots[port]=node_slots.get(port,[])+[int(tok)]

slot2port={}
for port,slots in node_slots.items():
    for s in slots: slot2port[s]=port

groups={}
for i in range(3000):
    k=f"k{i}"
    p=slot2port.get(slot_of(k))
    if p: groups.setdefault(p,[]).append(k)

for port,keys in groups.items():
    with open(f"/tmp/l07-pipe-{port}.txt","w") as fh:
        for k in keys:
            fh.write(f"SET {k} v\n")
    print(f"    节点 {port}: {len(keys)} 个 key")
PY

start=$(date +%s.%N)
for p in 7001 7002 7003; do
  [ -f /tmp/l07-pipe-$p.txt ] && $CLI -p $p --pipe < /tmp/l07-pipe-$p.txt 2>&1 | tail -1
done
end=$(date +%s.%N)
echo "     耗时: $(echo "$end - $start" | bc) 秒"
echo "     实际写入: 7001=$($CLI -p 7001 dbsize) 7002=$($CLI -p 7002 dbsize) 7003=$($CLI -p 7003 dbsize)"
echo "     合计 = $(( $($CLI -p 7001 dbsize) + $($CLI -p 7002 dbsize) + $($CLI -p 7003 dbsize) )) / 3000"

echo ""
echo "############################################################"
echo "# 实验 B：ASK 重定向（手动制造迁移中间态）"
echo "############################################################"
echo ""
echo "原理：MOVED = 槽已永久归属别处（客户端应更新本地路由表）"
echo "      ASK   = 槽正在迁移中，仅这一个 key 去目标节点找（不更新路由表）"
echo ""

# 准备：确保 k1 存在
$CLI -c -p 7001 set k1 "v-k1" >/dev/null 2>&1
SLOT=$($CLI -p 7001 cluster keyslot k1)
echo "  k1 -> slot $SLOT"

# 找出该槽当前归属
SRC=$($CLI -p 7001 cluster nodes | awk -v s="$SLOT" '
  $3 ~ /master/ {
    for(i=9;i<=NF;i++){
      if($i ~ /^[0-9]+-[0-9]+$/){split($i,a,"-"); if(s>=a[1]&&s<=a[2]) print $2}
    }
  }')
echo "  槽 $SLOT 当前归属: $SRC"
SRCPORT=$(echo "$SRC" | sed 's/.*://;s/@.*//')

# 选一个目标节点（不是 SRC 的 master）
DSTPORT=""
for p in 7001 7002 7003; do
  if [ "$p" != "$SRCPORT" ]; then DSTPORT=$p; break; fi
done
echo "  迁移目标: $DSTPORT"
SRCID=$($CLI -p $SRCPORT cluster myid)
DSTID=$($CLI -p $DSTPORT cluster myid)
echo "  SRC id=$SRCID"
echo "  DST id=$DSTID"

echo ""
echo "  -- 步骤 1：在目标节点标记 IMPORTING --"
$CLI -p $DSTPORT cluster setslot $SLOT importing $SRCID 2>&1
echo "     目标节点槽状态: $($CLI -p $DSTPORT cluster nodes | grep -E "^$DSTID" | awk '{print $9,$10,$11}')"

echo ""
echo "  -- 步骤 2：在源节点标记 MIGRATING --"
$CLI -p $SRCPORT cluster setslot $SLOT migrating $DSTID 2>&1
echo "     源节点槽状态: $($CLI -p $SRCPORT cluster nodes | grep -E "^$SRCID" | awk '{print $9,$10,$11}')"

echo ""
echo "  -- 步骤 3：迁移中间态下访问 k1（应触发 ASK）--"
echo "     注意：此刻 k1 还在源节点，槽尚未真正搬走"
echo ""
echo "     直连源节点 $SRCPORT 执行 GET k1:"
$CLI -p $SRCPORT get k1 2>&1 | head -2

echo ""
echo "  -- 步骤 4：把 key 迁到目标节点后，再从源节点访问 --"
echo "     执行 MIGRATE 把 k1 搬到 $DSTPORT"
$CLI -p $SRCPORT migrate 127.0.0.1 $DSTPORT k1 0 5000 2>&1
echo ""
echo "     现在 k1 已在目标节点，但槽仍标记在源（中间态）"
echo "     从源节点 $SRCPORT 访问 k1:"
ask_resp=$($CLI -p $SRCPORT get k1 2>&1 | head -2)
echo "     → $ask_resp"
echo ""
echo "     ★ 这就是 ASK 重定向：槽的归属还没改，但这个 key 已经搬走了"

echo ""
echo "  -- 步骤 5：对比 MOVED（完成迁移后）--"
echo "     在两个节点上清除迁移标记，把槽正式交给目标"
$CLI -p $DSTPORT cluster setslot $SLOT node $DSTID >/dev/null 2>&1
$CLI -p $SRCPORT cluster setslot $SLOT node $DSTID >/dev/null 2>&1
sleep 1
echo "     从源节点 $SRCPORT 访问 k1（此时槽已正式归属 $DSTPORT）:"
$CLI -p $SRCPORT get k1 2>&1 | head -2
echo "     ★ 这就是 MOVED：槽永久易主，客户端应更新路由表"

echo ""
echo "  -- 步骤 6：把槽还原给源节点（清理实验现场）--"
$CLI -p $SRCPORT cluster setslot $SLOT migrating $DSTID 2>/dev/null
$CLI -p $DSTPORT cluster setslot $SLOT importing $SRCID 2>/dev/null
$CLI -p $SRCPORT migrate 127.0.0.1 $DSTPORT "" 0 5000 2>/dev/null
$CLI -p $DSTPORT cluster setslot $SLOT node $SRCID >/dev/null 2>&1
$CLI -p $SRCPORT cluster setslot $SLOT node $SRCID >/dev/null 2>&1
sleep 1
echo "     还原后槽归属: $($CLI -p 7001 cluster nodes | grep -E '^[0-9a-f]{40}' | awk -v s="$SLOT" '{for(i=9;i<=NF;i++){if($i~/^[0-9]+-[0-9]+$/){split($i,a,"-"); if(s>=a[1]&&s<=a[2]) print $2" ("$i")"}}}')"

echo ""
echo "############################################################"
echo "# 实验 C：集群下的 hash tag 与多 key 限制"
echo "############################################################"
echo ""
echo "  -- 跨槽 MGET --"
$CLI -c -p 7001 mget k1 k2 k3 2>&1 | head -2
echo "  -- 同槽 MGET（用 hash tag 重写 key）--"
$CLI -c -p 7001 mset "{u1}:a" 1 "{u1}:b" 2 "{u1}:c" 3 2>&1 | head -2
$CLI -c -p 7001 mget "{u1}:a" "{u1}:b" "{u1}:c" 2>&1 | head -4
echo ""
echo "  -- 跨槽事务 --"
echo "     MULTI / SET k1 / SET k2 / EXEC 结果："
$CLI -c -p 7001 multi >/dev/null 2>&1
$CLI -c -p 7001 set k1 x >/dev/null 2>&1
echo "     （用单行命令模拟）"
printf 'MULTI\r\nSET t1 1\r\nSET t2 2\r\nEXEC\r\n' | $CLI -c -p 7001 2>&1 | tail -3

echo ""
echo "=== 完成 ==="
