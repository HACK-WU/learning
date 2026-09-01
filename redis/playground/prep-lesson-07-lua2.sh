#!/usr/bin/env bash
# 课 7 备课实测 6：Lua 硬编码 key 的强制检查 —— 修正错误认知
set -u
CLI="redis-cli"

echo "############################################################"
echo "# 核心问题：Lua 脚本里硬编码 key，Redis 到底管不管？"
echo "############################################################"
echo ""
echo "上一轮实验发现："
echo "  eval \"redis.call('SET','nodeclared',1); return 'ok'\" 1 {s1}:a"
echo "  → ERR Script attempted to access a non local key in a cluster node script"
echo ""
echo "这说明 Redis **会**检查。但另一个实验却『成功』了："
echo "  eval \"return redis.call('GET','k1')\" 0  → 返回 x"
echo ""
echo "矛盾吗？不矛盾。差别在于 numkeys 与 key 归属。下面逐层验证。"
echo ""

echo "=== 1. 确认 {s1}:a 的槽与归属 ==="
S=$($CLI -p 7001 cluster keyslot "{s1}:a")
echo "  {s1}:a -> slot $S"
echo "  k1     -> slot $($CLI -p 7001 cluster keyslot k1)"
echo "  nodeclared -> slot $($CLI -p 7001 cluster keyslot nodeclared)"

echo ""
echo "=== 2. 情况 A：声明了 KEYS（numkeys>0），脚本内访问非本槽 key ==="
echo "  脚本: redis.call('SET','nodeclared',1); return 'ok'"
echo "  KEYS: {s1}:a （槽 $S）"
echo "  访问: nodeclared （槽 $($CLI -p 7001 cluster keyslot nodeclared)）"
echo "  结果:"
$CLI -c -p 7001 eval "redis.call('SET','nodeclared',1); return 'ok'" 1 "{s1}:a" 2>&1
echo "  → 被拦截。因为脚本被路由到槽 $S 所在节点，该节点不负责 nodeclared 的槽。"

echo ""
echo "=== 3. 情况 B：不声明 KEYS（numkeys=0），脚本内访问任意 key ==="
echo "  numkeys=0 时脚本发到『连接所在的节点』，不按槽路由。"
echo ""
echo "  测试 B1: 连到 7001，读 k1（k1 槽属于哪个节点？）"
K1SLOT=$($CLI -p 7001 cluster keyslot k1)
echo "    k1 槽 = $K1SLOT"
owner=$(python3 - <<PY
import subprocess
out=subprocess.run(["redis-cli","-p","7001","cluster","nodes"],capture_output=True,text=True).stdout
for l in out.splitlines():
    f=l.split()
    if len(f)<9 or 'master' not in f[2]: continue
    for tok in f[9:]:
        if '-' in tok:
            a,b=tok.split('-')
            if $K1SLOT>=int(a) and $K1SLOT<=int(b): print(f[1].split('@')[0])
PY
)
echo "    k1 槽归属 = $owner"
echo "    执行 eval \"return redis.call('GET','k1')\" 0 连到 7001:"
r=$($CLI -c -p 7001 eval "return redis.call('GET','k1')" 0 2>&1)
echo "    → $r"
echo ""
echo "  测试 B2: 同样脚本，连到 7003 执行"
r2=$($CLI -c -p 7003 eval "return redis.call('GET','k1')" 0 2>&1)
echo "    → $r2"
echo ""
echo "  ★ 关键：同一脚本连不同节点结果可能不同！"
if [ "$r" != "$r2" ]; then
  echo "    ⚠️  实测差异：7001 返回 [$r]，7003 返回 [$r2]"
else
  echo "    本次两者一致（都是 $r），但机制上仍存在风险"
fi

echo ""
echo "=== 4. 验证『读到了错误数据』的真实风险 ==="
echo "  思路：在槽归属节点写入一个值，然后在非归属节点读同名 key"
echo ""
# 选一个明确属于 7003 的 key
TESTKEY="belongs:to:7003"
TS=$($CLI -p 7001 cluster keyslot "$TESTKEY")
echo "  $TESTKEY -> slot $TS"
towner=$(python3 - <<PY
import subprocess
out=subprocess.run(["redis-cli","-p","7001","cluster","nodes"],capture_output=True,text=True).stdout
for l in out.splitlines():
    f=l.split()
    if len(f)<9 or 'master' not in f[2]: continue
    for tok in f[9:]:
        if '-' in tok:
            a,b=tok.split('-')
            if $TS>=int(a) and $TS<=int(b): print(f[1].split('@')[0])
PY
)
echo "  归属节点 = $towner"
if [ -n "$towner" ]; then
  tport=$(echo "$towner" | sed 's/.*://')
  echo "  在归属节点 $tport 写入: SET $TESTKEY 'correct-value'"
  $CLI -p $tport set "$TESTKEY" "correct-value" 2>&1
  echo ""
  echo "  现在从『非归属节点』用 Lua 读它："
  for p in 7001 7002 7003; do
    if [ "$p" != "$tport" ]; then
      rr=$($CLI -c -p $p eval "return redis.call('GET','$TESTKEY')" 0 2>&1)
      echo "    连到 $p 执行 → $rr"
    fi
  done
  echo ""
  echo "  从归属节点 $tport 读:"
  echo "    → $($CLI -c -p $tport eval "return redis.call('GET','$TESTKEY')" 0 2>&1)"
fi

echo ""
echo "=== 5. 结论对比：单机 vs 集群 ==="
echo ""
echo "  ┌──────────────────┬────────────────────┬────────────────────┐"
echo "  │ 场景              │ 单机 Redis          │ Redis Cluster       │"
echo "  ├──────────────────┼────────────────────┼────────────────────┤"
echo "  │ 声明 KEYS 跨槽    │ 无此概念            │ CROSSSLOT 拒绝      │"
echo "  │ 脚本内硬编码 key  │ 允许（不推荐）      │ 非本槽 → 报错拦截   │"
echo "  │ numkeys=0 硬编码  │ 允许（不推荐）      │ 发到连接节点，静默  │"
echo "  │                  │                    │ 读到本地脏数据风险   │"
echo "  └──────────────────┴────────────────────┴────────────────────┘"
echo ""
echo "  ★ 结论：集群下 Lua 脚本必须把所有 key 写进 KEYS[]。"

echo ""
echo "=== 6. 同时验证：声明了 KEYS 但脚本内用其他同槽 key ==="
echo "  脚本声明 {s1}:a，脚本内访问 {s1}:zzz（同槽不同 key）"
S2=$($CLI -p 7001 cluster keyslot "{s1}:zzz")
echo "  {s1}:a -> $S , {s1}:zzz -> $S2 （同槽: $([ "$S" = "$S2" ] && echo YES || echo NO)）"
$CLI -c -p 7001 eval "redis.call('SET','{s1}:zzz','ok'); return redis.call('GET','{s1}:zzz')" 1 "{s1}:a" 2>&1
echo "  → 同槽允许，即使没在 KEYS 里显式列出"

echo ""
echo "=== 完成 ==="
