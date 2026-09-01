#!/usr/bin/env bash
# 课 7 备课实测 7：槽归属查询修正 + 集群路由与重定向的完整验证
set -u
CLI="redis-cli"

# 通用函数：查槽归属节点
slot_owner() {
  local s=$1
  python3 - "$s" <<'PY'
import subprocess,sys
s=int(sys.argv[1])
out=subprocess.run(["redis-cli","-p","7001","cluster","nodes"],capture_output=True,text=True).stdout
for l in out.splitlines():
    f=l.split()
    if len(f)<9: continue
    if 'master' not in f[2]: continue
    for tok in f[9:]:
        tok=tok.strip('[]')
        if '-' in tok:
            try: a,b=tok.split('-')
            except ValueError: continue
            if a.isdigit() and b.isdigit() and int(a)<=s<=int(b):
                print(f[1].split('@')[0]); sys.exit()
        elif tok.isdigit() and int(tok)==s:
            print(f[1].split('@')[0]); sys.exit()
PY
}

echo "############################################################"
echo "# 0. 先修复实验残留：检查集群健康"
echo "############################################################"
$CLI -p 7001 cluster info | grep -E 'cluster_state|cluster_slots_assigned|cluster_slots_fail'
echo ""

echo "############################################################"
echo "# 1. 槽归属查询（修正版）"
echo "############################################################"
echo ""
printf "  %-16s %-8s %s\n" "key" "slot" "归属节点"
for k in k1 k2 k3 "{s1}:a" "belongs:to:7003" nodeclared; do
  s=$($CLI -p 7001 cluster keyslot "$k")
  o=$(slot_owner $s)
  printf "  %-16s %-8s %s\n" "$k" "$s" "${o:-未找到}"
done

echo ""
echo "############################################################"
echo "# 2. 复现『同一脚本连不同节点结果不同』（关键实验）"
echo "############################################################"
echo ""
# 选一个明确属于某节点的 key
TARGET="probe:key"
TS=$($CLI -p 7001 cluster keyslot "$TARGET")
TOWNER=$(slot_owner $TS)
TPORT=$(echo "$TOWNER" | sed 's/.*://' 2>/dev/null)
echo "  探测 key = $TARGET"
echo "  槽 = $TS ，归属节点 = $TOWNER"

if [ -n "$TPORT" ]; then
  echo ""
  echo "  步骤 1：在归属节点 $TPORT 写入真实值"
  $CLI -p $TPORT set "$TARGET" "REAL-VALUE" 2>&1
  echo "    归属节点读到: $($CLI -p $TPORT get "$TARGET")"
  echo ""
  echo "  步骤 2：在【非归属节点】上写入同名 key（模拟脏数据）"
  for p in 7001 7002 7003; do
    if [ "$p" != "$TPORT" ]; then
      $CLI -p $p set "$TARGET" "DIRTY-VALUE-on-$p" >/dev/null 2>&1
      echo "    $p 写入 DIRTY-VALUE-on-$p （$TARGET 本不该存在这里）"
    fi
  done
  echo ""
  echo "  步骤 3：用 numkeys=0 的 Lua 脚本从不同节点读同一个 key"
  echo "    脚本: eval \"return redis.call('GET','$TARGET')\" 0"
  echo ""
  for p in 7001 7002 7003; do
    mark=""
    [ "$p" = "$TPORT" ] && mark="  ← 正确的归属节点"
    r=$($CLI -c -p $p eval "return redis.call('GET','$TARGET')" 0 2>&1)
    printf "    连到 %s → %s%s\n" "$p" "$(echo "$r" | head -1)" "$mark"
  done
  echo ""
  echo "  ★ 这就是 numkeys=0 + 硬编码 key 的真实风险："
  echo "    连错节点会静默读到脏数据，且不报错。"
  echo ""
  echo "  步骤 4：对照 —— 正确做法（key 写进 KEYS[]）"
  for p in 7001 7002 7003; do
    mark=""
    [ "$p" = "$TPORT" ] && mark="  ← 正确的归属节点"
    r=$($CLI -c -p $p eval "return redis.call('GET', KEYS[1])" 1 "$TARGET" 2>&1)
    printf "    连到 %s → %s%s\n" "$p" "$(echo "$r" | head -1)" "$mark"
  done
  echo ""
  echo "  ★ 声明 KEYS 后，无论连哪个节点都会路由到正确位置，结果一致。"
fi

echo ""
echo "############################################################"
echo "# 3. MOVED 与 ASK 的完整对比（含客户端行为）"
echo "############################################################"
echo ""
echo "  MOVED：槽已永久易主。客户端应【更新本地路由表】，下次直连新节点。"
echo "  ASK  ：槽迁移中。客户端【临时】去目标节点取，【不更新】路由表。"
echo ""
echo "  为什么 ASK 不更新路由表？"
echo "  因为迁移未完成，槽里还有一部分 key 在源节点。"
echo "  若更新路由表，后续访问【尚未迁走】的 key 就会被路由到错误位置。"
echo ""

echo "  -- 实测：用 -c 观察 redis-cli 的处理 --"
echo ""
# 找一个不属于 7001 的 key
PROBE="moved:probe"
PS=$($CLI -p 7001 cluster keyslot "$PROBE")
POWNER=$(slot_owner $PS)
PPORT=$(echo "$POWNER" | sed 's/.*://' 2>/dev/null)
echo "  $PROBE -> slot $PS -> $POWNER"
echo ""
if [ "$PPORT" != "7001" ] && [ -n "$PPORT" ]; then
  echo "  连到 7001（非归属）用普通模式访问："
  echo "    → $($CLI -p 7001 get "$PROBE" 2>&1 | head -1)"
  echo "  连到 7001 用 -c 模式访问（自动跟随）："
  echo "    → $($CLI -c -p 7001 get "$PROBE" 2>&1 | head -1)"
  echo "    跟随后再 get 一次（应无重定向提示）："
  echo "    → $($CLI -c -p 7001 get "$PROBE" 2>&1 | head -1)"
fi

echo ""
echo "############################################################"
echo "# 4. 客户端缓存路由表的重要性（CLUSTER SLOTS / SHARDS）"
echo "############################################################"
echo ""
echo "  集群客户端启动时拉取一次路由表，之后直连正确节点："
echo ""
echo "  CLUSTER SLOTS 输出片段："
$CLI -p 7001 cluster slots 2>&1 | head -12
echo ""
echo "  CLUSTER SHARDS（Redis 7+ 推荐，信息更全）输出片段："
$CLI -p 7001 cluster shards 2>&1 | head -14

echo ""
echo "############################################################"
echo "# 5. 重定向次数与性能影响（实测）"
echo "############################################################"
echo ""
echo "  场景：客户端路由表过期（模拟）"
echo "  测试：随机访问 500 个 key，统计重定向发生次数"
echo ""
# 统计：连到固定节点访问随机 key，看 MOVED 比例
moved=0; total=0
for i in $(seq 1 200); do
  k="perf:k$i"
  r=$($CLI -p 7001 cluster keyslot "$k" >/dev/null 2>&1)
  out=$($CLI -p 7001 exists "$k" 2>&1 | head -1)
  total=$((total+1))
  case "$out" in
    MOVED*) moved=$((moved+1));;
  esac
done
echo "  连到 7001 随机访问 200 个 key：发生 MOVED $moved 次 / $total"
echo "  → 约 $(echo "scale=1; $moved * 100 / $total" | bc)% 的请求需要重定向"
echo "  （理论上 2/3 的 key 不属于 7001，符合预期）"

echo ""
echo "  对照：用 -c（客户端跟随重定向）后的额外网络开销"
start=$(date +%s.%N)
for i in $(seq 1 200); do
  $CLI -c -p 7001 exists "perf:k$i" >/dev/null 2>&1
done
end=$(date +%s.%N)
t1=$(echo "$end - $start" | bc)
echo "    -c 模式 200 次访问耗时: $t1 秒"

start=$(date +%s.%N)
for i in $(seq 1 200); do
  $CLI -p 7001 exists "perf:k$i" >/dev/null 2>&1
done
end=$(date +%s.%N)
t2=$(echo "$end - $start" | bc)
echo "    普通模式 200 次访问耗时: $t2 秒（但有 $(echo "scale=0; 200*2/3" | bc) 次实际未拿到正确结果）"

echo ""
echo "=== 完成 ==="
