#!/usr/bin/env bash
# 课 7 备课实测 5：集群下的 Lua 脚本限制
set -u
CLI="redis-cli"
C="$CLI -c -p 7001"

echo "############################################################"
echo "# 实验 1：Lua 脚本跨槽访问 key"
echo "############################################################"
echo ""
echo "  -- 同槽 Lua（用 hash tag）--"
echo "     脚本: return redis.call('MGET', KEYS[1], KEYS[2])"
$CLI -c -p 7001 mset "{s1}:a" 1 "{s1}:b" 2 >/dev/null 2>&1
echo "     执行结果:"
$CLI -c -p 7001 eval "return redis.call('MGET', KEYS[1], KEYS[2])" 2 "{s1}:a" "{s1}:b" 2>&1

echo ""
echo "  -- 跨槽 Lua --"
echo "     执行: eval \"return redis.call('MGET', KEYS[1], KEYS[2])\" 2 k1 k2"
$CLI -c -p 7001 eval "return redis.call('MGET', KEYS[1], KEYS[2])" 2 k1 k2 2>&1 | head -2

echo ""
echo "  -- 关键：不声明 KEYS，直接在脚本里硬编码 key --"
echo "     单机 Redis 可以跑（不推荐），集群下会怎样？"
$CLI -c -p 7001 eval "return redis.call('GET', 'k1')" 0 2>&1 | head -2
echo "     —— 注意：即使 k1 不在本节点，也可能返回 MOVED 或报错"

echo ""
echo "############################################################"
echo "# 实验 2：Lua 脚本的集群路由规则"
echo "############################################################"
echo ""
echo "  规则：集群根据 numkeys + KEYS[] 计算槽，脚本发到该槽所在节点。"
echo "        若 KEYS 跨槽 → 直接拒绝；若 KEYS 为空 → 脚本发到连接节点。"
echo ""
echo "  -- KEYS 为空的脚本（发到连接节点）--"
echo "     eval \"return redis.call('PING')\" 0"
$CLI -c -p 7001 eval "return redis.call('PING')" 0 2>&1
echo "     eval \"return 'hello'\" 0"
$CLI -c -p 7001 eval "return 'hello'" 0 2>&1

echo ""
echo "  -- 硬编码 key 但槽不属于本节点 --"
SLOT_K1=$($CLI -p 7001 cluster keyslot k1)
echo "     k1 的槽 = $SLOT_K1"
owner=$($CLI -p 7001 cluster nodes | awk -v s="$SLOT_K1" '$3 ~ /master/ {for(i=9;i<=NF;i++){if($i~/^[0-9]+-[0-9]+$/){split($i,a,"-"); if(s>=a[1]&&s<=a[2]) print $2}}}')
echo "     槽归属 = $owner"
echo "     连到 7001 执行 eval \"return redis.call('GET','k1')\" 0:"
$CLI -c -p 7001 eval "return redis.call('GET','k1')" 0 2>&1 | head -2

echo ""
echo "############################################################"
echo "# 实验 3：脚本复制模式（effects replication vs script）"
echo "############################################################"
echo ""
echo "  Redis 7+ 默认用 effects replication（复制脚本产生的写命令，而非脚本本身）"
echo ""
echo "  -- 查看 lua-replicate-commands 配置 --"
$CLI -p 7001 config get enable-debug-command >/dev/null 2>&1
echo "     Redis 版本: $($CLI -p 7001 info server | grep -o 'redis_version:[0-9.]*')"
echo ""
echo "  -- 用随机数的脚本验证两种模式的差异 --"
echo "     脚本: 写入一个随机数（非确定性）"
echo ""
echo "     确定性脚本 vs 非确定性脚本在集群下的表现："
echo "     eval \"local v = redis.call('TIME'); return redis.call('SET', KEYS[1], v[1])\" 1 {rnd}:t"
$CLI -c -p 7001 eval "local v = redis.call('TIME'); return redis.call('SET', KEYS[1], v[1])" 1 "{rnd}:t" 2>&1 | head -2

echo ""
echo "  -- 检查从库是否同步（effects replication 下应该一致）--"
# 找到 {rnd}:t 所在节点
SLOT_R=$($CLI -p 7001 cluster keyslot "{rnd}:t")
owner_r=$($CLI -p 7001 cluster nodes | awk -v s="$SLOT_R" '$3 ~ /master/ {for(i=9;i<=NF;i++){if($i~/^[0-9]+-[0-9]+$/){split($i,a,"-"); if(s>=a[1]&&s<=a[2]) print $2}}}')
op=$(echo "$owner_r" | sed 's/.*://;s/@.*//')
replica=$($CLI -p 7001 cluster nodes | awk -v o="$op" '
  $0 ~ o && $3 ~ /master/ {mid=$1}
  END {print mid}')
# 找该 master 的 slave
slave=$(python3 - <<PY
import subprocess
out = subprocess.run(["redis-cli","-p","7001","cluster","nodes"],capture_output=True,text=True).stdout
lines=[l.split() for l in out.splitlines() if l.strip()]
mid=None
for f in lines:
    if len(f)>=9 and f[1].startswith("127.0.0.1:$op@"):
        mid=f[0]
for f in lines:
    if len(f)>=9 and f[3]==mid and 'slave' in f[2]:
        print(f[1].split('@')[0].split(':')[1]); break
PY
)
echo "     主节点=$op  从节点=$slave"
if [ -n "$slave" ]; then
  sleep 0.5
  echo "     主库值 = $($CLI -p $op get '{rnd}:t' 2>&1)"
  echo "     从库值 = $($CLI -p $slave get '{rnd}:t' 2>&1)"
fi

echo ""
echo "############################################################"
echo "# 实验 4：EVALSHA 与集群"
echo "############################################################"
echo ""
SHA=$($CLI -c -p 7001 script load "return redis.call('GET', KEYS[1])" 2>&1)
echo "  SCRIPT LOAD 返回 SHA = $SHA"
echo "  在 7001 上 SCRIPT EXISTS: $($CLI -p 7001 script exists $SHA 2>&1)"
echo "  在 7002 上 SCRIPT EXISTS: $($CLI -p 7002 script exists $SHA 2>&1)"
echo "  在 7003 上 SCRIPT EXISTS: $($CLI -p 7003 script exists $SHA 2>&1)"
echo "  → 脚本缓存是每节点独立的！"
echo ""
echo "  -- 连到不含该槽的节点执行 EVALSHA --"
echo "     （若脚本未加载在该节点 → NOSCRIPT 错误）"
$CLI -p 7003 evalsha $SHA 1 "{s1}:a" 2>&1 | head -2

echo ""
echo "  -- 正确做法：客户端捕获 NOSCRIPT 后自动 SCRIPT LOAD 重试 --"
echo "     或直接用 EVAL（每次传完整脚本）"

echo ""
echo "############################################################"
echo "# 实验 5：集群模式下的多 key 命令清单验证"
echo "############################################################"
echo ""
echo "  跨槽（应报错 CROSSSLOT）："
for cmd in "mget k1 k2" "mset kx 1 ky 2" "sinter sk1 sk2" "sunionstore dst sk1 sk2" "rename k1 k2"; do
  r=$($CLI -c -p 7001 $cmd 2>&1 | head -1)
  printf "    %-32s -> %s\n" "$cmd" "$r"
done

echo ""
echo "  同槽（应成功）："
$CLI -c -p 7001 sadd "{set}:a" x y z >/dev/null 2>&1
$CLI -c -p 7001 sadd "{set}:b" y z w >/dev/null 2>&1
for cmd in "sinter {set}:a {set}:b" "sunionstore {set}:dst {set}:a {set}:b"; do
  r=$($CLI -c -p 7001 $cmd 2>&1 | head -1)
  printf "    %-32s -> %s\n" "$cmd" "$r"
done

echo ""
echo "############################################################"
echo "# 实验 6：Lua 脚本中的 redis.call 跨槽检测"
echo "############################################################"
echo ""
echo "  -- 脚本内访问未声明的 key --"
echo "     eval \"redis.call('SET','nodeclared',1); return 'ok'\" 1 {s1}:a"
$CLI -c -p 7001 eval "redis.call('SET','nodeclared',1); return 'ok'" 1 "{s1}:a" 2>&1 | head -2
echo ""
echo "     （Redis 不会强制检查，但这是隐患：脚本在主库执行、从库重放时"
echo "       若 key 落在不同槽，会导致主从数据不一致）"

echo ""
echo "  -- CLUSTER KEYSLOT 在 Lua 中可用吗 --"
$CLI -c -p 7001 eval "return redis.call('CLUSTER','KEYSLOT','k1')" 0 2>&1 | head -2

echo ""
echo "=== 完成 ==="
