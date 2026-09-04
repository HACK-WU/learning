#!/bin/bash
# 课 10 步骤 2：内存超限与 Spill to Disk（知识点 2）
# 证明 Spill 是"保命"而非"加速"
#
# 用法：bash lesson10-step2.sh
# 耗时：约 60 秒
#
# ⚠️ 关键坑：
#   1. SET 会话变量跨连接失效，必须写成 runq "SET x=1; SELECT ...;" 同一连接
#   2. spill 临时文件查询结束后自动清理，峰值只有在**查询过程中**采样才能看到
#   3. 不要用 SELECT COUNT(*) 验证数据 —— 那走元数据优化不扫 BE（课 9 血泪教训）

FE='docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop'
q() { $FE -e "$1" 2>&1 | grep -vE "^Warning|Using a password"; }

# 高基数聚合查询：2150 万行按 user_id 分组，内存杀手
BIGQ="SELECT user_id, COUNT(*) c, SUM(amount) s FROM orders GROUP BY user_id ORDER BY c DESC LIMIT 10;"
LIM=402653184   # 384 MB

spill_dir() { docker exec -i doris-learn bash -c 'du -sh /opt/apache-doris/be/storage/spill 2>/dev/null | cut -f1'; }
spill_cnt() { docker exec -i doris-learn bash -c 'find /opt/apache-doris/be/storage/spill -type f 2>/dev/null | wc -l'; }

echo "=========================================="
echo " 课 10 · 步骤 2：内存超限与 Spill to Disk"
echo "=========================================="
echo ""
echo "实验查询（高基数聚合，内存杀手）："
echo "  $BIGQ"
echo ""

q "SET PROPERTY FOR 'root' 'default_workload_group' = 'normal';" >/dev/null 2>&1

echo "############ 1. 基线：内存充足（不限）############"
for i in 1 2 3; do
  s=$(date +%s.%N)
  o=$(q "$BIGQ" 2>&1 | head -1)
  e=$(date +%s.%N)
  if echo "$o" | grep -q "MEM_LIMIT_EXCEEDED"; then
    printf "  第%s次 [%6.2fs] 失败（不应该，检查 exec_mem_limit 是否被改过）\n" "$i" "$(echo "$e - $s" | bc)"
  else
    printf "  第%s次 [%6.2fs] 成功\n" "$i" "$(echo "$e - $s" | bc)"
  fi
done

echo ""
echo "############ 2. 限 384MB + spill=OFF（预期：报错被杀）############"
echo "  ⚠️ 这是 Doris 的默认行为，因为 enable_spill 默认就是 false"
for i in 1 2 3; do
  s=$(date +%s.%N)
  o=$(q "SET enable_spill=false; SET exec_mem_limit=$LIM; $BIGQ" 2>&1 | head -1)
  e=$(date +%s.%N)
  if echo "$o" | grep -q "MEM_LIMIT_EXCEEDED"; then
    lim=$(echo "$o" | grep -oE "limit [0-9.]+ MB" | head -1)
    printf "  第%s次 [%6.2fs] 被杀  %s\n" "$i" "$(echo "$e - $s" | bc)" "$lim"
  else
    printf "  第%s次 [%6.2fs] 成功（与预期不符）\n" "$i" "$(echo "$e - $s" | bc)"
  fi
done

echo ""
echo "  --- 完整报错原文（第 1 次）---"
q "SET enable_spill=false; SET exec_mem_limit=$LIM; $BIGQ" 2>&1 | head -1 | sed 's/^/    /'

echo ""
echo "############ 3. 限 384MB + spill=ON（预期：落盘后跑通）############"
echo "  注意：查询结束后才看目录，此时临时文件已被自动清理（所以是 8.0K 不是 36M）"
for i in 1 2 3; do
  docker exec -i doris-learn bash -c 'rm -rf /opt/apache-doris/be/storage/spill/*' 2>/dev/null
  s=$(date +%s.%N)
  o=$(q "SET enable_spill=true; SET exec_mem_limit=$LIM; $BIGQ" 2>&1 | head -3 | tr '\n' ' ')
  e=$(date +%s.%N)
  PEAK=$(spill_dir)
  if echo "$o" | grep -q "MEM_LIMIT_EXCEEDED"; then
    printf "  第%s次 [%6.2fs] 失败  落盘后目录=%s\n" "$i" "$(echo "$e - $s" | bc)" "$PEAK"
  else
    printf "  第%s次 [%6.2fs] 成功  落盘后目录=%s  %s\n" "$i" "$(echo "$e - $s" | bc)" "$PEAK" "${o:0:50}"
  fi
done

echo ""
echo "############ 4. Spill 落盘过程采样（每 2 秒，看峰值）############"
echo "  这才是看到真实落盘量的方式 —— 必须在查询**运行中**采样"
docker exec -i doris-learn bash -c 'rm -rf /opt/apache-doris/be/storage/spill/*' 2>/dev/null
( $FE -e "SET enable_spill=true; SET exec_mem_limit=$LIM; $BIGQ" >/dev/null 2>&1 ) &
BG=$!
for i in $(seq 1 8); do
  sleep 2
  N=$(spill_cnt)
  S=$(spill_dir)
  printf "  t=%2ds  文件数=%-4s 大小=%s\n" $((i*2)) "$N" "$S"
  kill -0 $BG 2>/dev/null || break
done
wait $BG

echo ""
echo "############ 5. 三个场景放一起看 ############"
cat <<'EOF'
  ┌──────────────────────────┬──────────────┬────────────┐
  │ 场景                     │ 耗时         │ 结果       │
  ├──────────────────────────┼──────────────┼────────────┤
  │ 内存充足（不限）         │ 0.35-0.38 s  │ ✅ 成功    │
  │ 限 384MB, spill=OFF      │ 0.25 s       │ ❌ 报错    │
  │ 限 384MB, spill=ON       │ 8.79-13.77 s │ ✅ 落盘成功│
  └──────────────────────────┴──────────────┴────────────┘

  结论：Spill 慢 25-40 倍，但"能跑完"和"报错失败"是两回事。
       它是保命，不是加速。
EOF

echo ""
echo "############ 6. Spill 不是万能的（进阶验证，可选）############"
echo "  同样的查询，把内存压得更狠，看会怎样："
JOINQ="SELECT COUNT(*) FROM orders a JOIN orders b ON a.user_id=b.user_id;"
for lim in 134217728 268435456; do
  MB=$((lim/1048576))
  s=$(date +%s.%N)
  o=$(q "SET enable_spill=true; SET exec_mem_limit=$lim; $JOINQ" 2>&1 | head -1)
  e=$(date +%s.%N)
  r="成功"; echo "$o" | grep -q "MEM_LIMIT_EXCEEDED" && r="被杀"
  printf "  exec_mem_limit=%-5sMB  spill=ON  [%7.2fs]  %s\n" "$MB" "$(echo "$e - $s" | bc)" "$r"
done
echo "  ⚠️ 注意：这两条可能非常慢（几分钟到十几分钟）或失败，"
echo "     这本身就是结论 —— 内存差太远时 spill 也救不了。"

echo ""
echo "############ 7. 清理 ############"
docker exec -i doris-learn bash -c 'rm -rf /opt/apache-doris/be/storage/spill/*' 2>/dev/null
q "SET PROPERTY FOR 'root' 'default_workload_group' = 'normal';" >/dev/null 2>&1
echo "  spill 目录已清空，root 默认组已恢复"
echo ""
echo "=========================================="
echo " 步骤 2 完成 → 下一步：bash lesson10-step3.sh"
echo "=========================================="
