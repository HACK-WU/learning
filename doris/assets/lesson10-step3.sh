#!/bin/bash
# 课 10 步骤 3：并发、排队、超时三种处置（知识点 3）
#
# 用法：bash lesson10-step3.sh
# 耗时：约 40 秒
#
# ⚠️ 重要：场景 A/B/C 里"哪几条被拒"是**不确定的** ——
#    取决于 3 个并发连接谁先抢到坑。你重跑可能得到不同分布。
#    判据是"能看到拒绝/排队/超时这三种现象"，不是"第几条被拒"。

FE='docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop'
q() { $FE -e "$1" 2>&1 | grep -vE "^Warning|Using a password"; }

# 慢查询：单条约 1 秒
SLOW="SELECT COUNT(*) FROM orders a JOIN orders b ON a.user_id=b.user_id;"

echo "=========================================="
echo " 课 10 · 步骤 3：并发、排队、超时"
echo "=========================================="
echo ""

# 确保组存在
q "CREATE WORKLOAD GROUP IF NOT EXISTS wg_c1 PROPERTIES ( 'max_concurrency'='1', 'max_queue_size'='0', 'queue_timeout'='0' );" >/dev/null 2>&1
q "CREATE WORKLOAD GROUP IF NOT EXISTS wg_c5 PROPERTIES ( 'max_concurrency'='1', 'max_queue_size'='5', 'queue_timeout'='10000' );" >/dev/null 2>&1
q "CREATE WORKLOAD GROUP IF NOT EXISTS wg_t1 PROPERTIES ( 'max_concurrency'='1', 'max_queue_size'='5', 'queue_timeout'='1000' );" >/dev/null 2>&1
for g in wg_c1 wg_c5 wg_t1; do
  q "GRANT USAGE_PRIV ON WORKLOAD GROUP '$g' TO root;" >/dev/null 2>&1
done

echo "############ 场景 A：max_concurrency=1, queue=0（拒绝策略）############"
echo "  预期：3 条并发，超出的**直接被拒**，连排队的资格都没有"
q "SET PROPERTY FOR 'root' 'default_workload_group' = 'wg_c1';" >/dev/null 2>&1
sleep 2
for i in 1 2 3; do
  ( q "$SLOW" > /tmp/l10_a$i.txt 2>&1 ) &
done
wait
for i in 1 2 3; do
  out=$(tail -1 /tmp/l10_a$i.txt)
  if echo "$out" | grep -q "ERROR"; then
    printf "  查询 %s: 被拒 → %s\n" "$i" "$(echo "$out" | grep -oE 'query waiting queue is full[^"]*' | head -1)"
  else
    printf "  查询 %s: 成功 → %s\n" "$i" "$out"
  fi
done

echo ""
echo "############ 场景 B：max_concurrency=1, queue=5, timeout=10s（排队策略）############"
echo "  预期：3 条**全部成功**，但耗时阶梯式增长（串行排队）"
q "SET PROPERTY FOR 'root' 'default_workload_group' = 'wg_c5';" >/dev/null 2>&1
sleep 2
for i in 1 2 3; do
  (
    s=$(date +%s.%N)
    out=$(q "$SLOW" 2>&1 | tail -1)
    e=$(date +%s.%N)
    printf "  查询 %s [%6.2fs]: %s\n" "$i" "$(echo "$e - $s" | bc)" "$out"
  ) &
done
wait

echo ""
echo "############ 场景 C：max_concurrency=1, queue=5, timeout=1s（排队后超时）############"
echo "  预期：排得上但等不到，至少 1 条超时被拒"
q "SET PROPERTY FOR 'root' 'default_workload_group' = 'wg_t1';" >/dev/null 2>&1
sleep 2
for i in 1 2 3; do
  (
    s=$(date +%s.%N)
    out=$(q "$SLOW" 2>&1 | tail -1)
    e=$(date +%s.%N)
    if echo "$out" | grep -q "ERROR"; then
      printf "  查询 %s [%6.2fs]: 超时被拒 → %s\n" "$i" "$(echo "$e - $s" | bc)" "$(echo "$out" | grep -oE 'query queue timeout[^"]*' | head -1)"
    else
      printf "  查询 %s [%6.2fs]: 成功 → %s\n" "$i" "$(echo "$e - $s" | bc)" "$out"
    fi
  ) &
done
wait

echo ""
echo "############ 两种报错对比（别混淆！）############"
cat <<'EOF'
  ┌───────────────────────────────────────────────┬──────────────────────────┐
  │ 报错                                          │ 该调哪个参数             │
  ├───────────────────────────────────────────────┼──────────────────────────┤
  │ query waiting queue is full, queue capacity=0 │ max_queue_size（调大）   │
  │   含义：队列满了，压根不让进                   │                          │
  ├───────────────────────────────────────────────┼──────────────────────────┤
  │ query queue timeout, timeout: 1000 ms         │ queue_timeout 或         │
  │   含义：排上了，但等太久                       │ max_concurrency          │
  └───────────────────────────────────────────────┴──────────────────────────┘

  记忆口诀：is full = 不让进；timeout = 进来了但等不及
EOF

echo ""
echo "############ 收尾 ############"
q "SET PROPERTY FOR 'root' 'default_workload_group' = 'normal';" >/dev/null 2>&1
rm -f /tmp/l10_a*.txt
echo "  已恢复 root 默认组为 normal（实验组由 cleanup 脚本统一清理）"
echo ""
echo "=========================================="
echo " 步骤 3 完成 → 收尾：bash lesson10-cleanup.sh"
echo "=========================================="
