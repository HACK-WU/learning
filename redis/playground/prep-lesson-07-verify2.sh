#!/usr/bin/env bash
# 课 7 备课实测 8：最终确认 —— Lua 跨槽拦截机制 + 槽归属查询修正
set -u
CLI="redis-cli"

slot_owner() {
  python3 - "$1" <<'PY'
import subprocess,sys
s=int(sys.argv[1])
out=subprocess.run(["redis-cli","-p","7001","cluster","nodes"],capture_output=True,text=True).stdout
for l in out.splitlines():
    f=l.split()
    if len(f)<8: continue
    if 'master' not in f[2]: continue
    for tok in f[8:]:
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
echo "# 1. 槽归属查询（修正索引：cluster nodes 字段从 8 开始）"
echo "############################################################"
echo ""
printf "  %-18s %-8s %s\n" "key" "slot" "归属节点"
for k in k1 k2 k3 "{s1}:a" "probe:key" nodeclared; do
  s=$($CLI -p 7001 cluster keyslot "$k")
  o=$(slot_owner $s)
  printf "  %-18s %-8s %s\n" "$k" "$s" "${o:-未找到}"
done

echo ""
echo "############################################################"
echo "# 2. 关键确认：硬编码 key 到底会不会静默读到脏数据？"
echo "############################################################"
echo ""
echo "上一轮实验的注释写『会静默读到脏数据』，但实测输出其实是报错。"
echo "这一轮用最干净的方式确认："
echo ""

# 用 probe:key，槽 14312 归属 7003
TARGET="probe:key"
TS=$($CLI -p 7001 cluster keyslot "$TARGET")
TOWNER=$(slot_owner $TS)
echo "  $TARGET -> slot $TS -> $TOWNER"
echo ""
echo "  当前各节点上该 key 的值："
for p in 7001 7002 7003; do
  v=$($CLI -p $p get "$TARGET" 2>&1 | head -1)
  printf "    %s: %s\n" "$p" "$v"
done
echo "  ↑ 注意：7001/7002 上确实存在同名 key（脏数据已写入）"
echo ""

echo "  -- 测试 A：numkeys=0，脚本内硬编码 GET --"
echo "     连到 7001（非归属，但本地有脏数据）："
$CLI -c -p 7001 eval "return redis.call('GET','$TARGET')" 0 2>&1 | head -1
echo ""
echo "  -- 测试 B：numkeys=0，但用 SET（写操作）--"
echo "     连到 7001 执行 redis.call('SET','$TARGET','HACK')："
$CLI -c -p 7001 eval "return redis.call('SET','$TARGET','HACK')" 0 2>&1 | head -1
echo ""
echo "  -- 测试 C：numkeys=1，正确声明 KEYS --"
for p in 7001 7002 7003; do
  r=$($CLI -c -p $p eval "return redis.call('GET', KEYS[1])" 1 "$TARGET" 2>&1 | head -1)
  printf "    连到 %s → %s\n" "$p" "$r"
done

echo ""
echo "############################################################"
echo "# 3. 结论：Redis 集群对 Lua 脚本的两道检查"
echo "############################################################"
echo ""
echo "  第一道（路由层）：根据 numkeys + KEYS[] 计算槽，跨槽 → CROSSSLOT"
echo "  第二道（执行层）：脚本内访问非本节点负责的槽 → "
echo "                    ERR Script attempted to access a non local key"
echo ""
echo "  ★ 两道检查都是【报错拦截】，不是静默返回错数据。"
echo "  ★ 但 numkeys=0 时脚本发到连接节点，若 key 恰在本节点则正常执行"
echo "    —— 这可能让人误以为『硬编码可行』，实际只是碰巧。"

echo ""
echo "############################################################"
echo "# 4. 验证『碰巧可行』的误导性"
echo "############################################################"
echo ""
# 找一个槽归属 7001 的 key，连 7001 硬编码访问应该成功
for k in k1 kk1 test1 abc1; do
  s=$($CLI -p 7001 cluster keyslot "$k")
  o=$(slot_owner $s)
  p=$(echo "$o" | sed 's/.*://' 2>/dev/null)
  if [ "$p" = "7001" ]; then
    echo "  找到槽归属 7001 的 key: $k (slot $s)"
    echo "  在 7001 上写入该 key："
    $CLI -p 7001 set "$k" "local-value" >/dev/null 2>&1
    echo "  连到 7001，numkeys=0 硬编码访问："
    echo "    → $($CLI -c -p 7001 eval "return redis.call('GET','$k')" 0 2>&1 | head -1)"
    echo "    ★ 成功了！但这只是因为槽恰好在 7001。"
    echo "  连到 7002，同样脚本："
    echo "    → $($CLI -c -p 7002 eval "return redis.call('GET','$k')" 0 2>&1 | head -1)"
    echo "    ★ 同一个脚本、同一个 key，换节点就报错。"
    break
  fi
done

echo ""
echo "############################################################"
echo "# 5. 集群可用性：节点宕机时的行为"
echo "############################################################"
echo ""
echo "  当前 cluster_size = $($CLI -p 7001 cluster info | grep -o 'cluster_size:[0-9]*')"
echo "  （每个主库有 1 个从库，共 3 主 3 从）"
echo ""
echo "  检查主从对应关系："
$CLI -p 7001 cluster nodes | awk '$3 ~ /master|slave/ {printf "    %s  %s  %s\n", $2, $3, ($3=="slave" ? "replicates "$4 : "")}'

echo ""
echo "############################################################"
echo "# 6. cluster-require-full-coverage 配置（重要）"
echo "############################################################"
echo ""
echo "  该配置决定：有槽无节点负责时，整个集群是否停止服务"
for p in 7001 7002 7003; do
  v=$($CLI -p $p config get cluster-require-full-coverage 2>&1 | tail -1)
  printf "    %s: %s\n" "$p" "$v"
done

echo ""
echo "############################################################"
echo "# 7. 重定向开销实测（更严谨）"
echo "############################################################"
echo ""
echo "  测试：连到固定节点，访问 N 个随机 key，统计 MOVED 比例"
echo ""
moved=0; total=0; ok=0
for i in $(seq 1 300); do
  k="perf:k$i"
  out=$($CLI -p 7001 exists "$k" 2>&1 | head -1)
  total=$((total+1))
  case "$out" in
    MOVED*) moved=$((moved+1));;
    *) ok=$((ok+1));;
  esac
done
echo "    总计 $total 次，MOVED $moved 次（$(echo "scale=1; $moved*100/$total" | bc)%），直接命中 $ok 次"
echo ""
echo "  含义：客户端若没有缓存路由表，约 $(echo "scale=0; $moved*100/$total" | bc)% 的请求需要两次网络往返。"
echo "  这解释了为什么集群客户端必须缓存 slot→node 映射。"

echo ""
echo "=== 完成 ==="
