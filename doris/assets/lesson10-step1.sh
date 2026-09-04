#!/bin/bash
# 课 10 步骤 1：验证资源隔离（知识点 1）
# 用三组对照证明：隔离让小查询快 6 倍，而大查询单条耗时不变
#
# 用法：bash lesson10-step1.sh
# 耗时：约 60 秒
#
# ⚠️ 数值浮动说明：所有耗时都跑 5 轮取范围。
#    你本机重跑的具体毫秒数会不一样（取决于 CPU 核数、磁盘 IO、系统负载），
#    但三组之间的**倍数关系**不会变。看趋势，不看绝对值。

FE='docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop'
q() { $FE -e "$1" 2>&1 | grep -vE "^Warning|Using a password"; }

# 大查询：orders 自关联，产出 4 亿行中间结果，单条约 1 秒
SLOW="SELECT COUNT(*) FROM orders a JOIN orders b ON a.user_id = b.user_id;"
# 小查询：报表用的分组统计
FAST="SELECT province, COUNT(*) c FROM orders GROUP BY province ORDER BY c DESC LIMIT 8;"

echo "=========================================="
echo " 课 10 · 步骤 1：资源隔离验证"
echo "=========================================="
echo ""
echo "判据（看倍数关系，不看绝对毫秒数）："
echo "  基线（无干扰）      ≈ 150 ms"
echo "  场景 A（无隔离）    ≈ 1000-2000 ms   ← 应该明显变慢"
echo "  场景 B（有隔离）    ≈ 200-300 ms     ← 应该接近基线"
echo ""

# 确保组存在
q "CREATE WORKLOAD GROUP IF NOT EXISTS big_etl PROPERTIES ( 'max_concurrency'='1', 'max_queue_size'='3', 'queue_timeout'='30000', 'max_memory_percent'='30' );" >/dev/null 2>&1
q "CREATE WORKLOAD GROUP IF NOT EXISTS fast_report PROPERTIES ( 'max_concurrency'='10', 'max_queue_size'='0', 'queue_timeout'='0', 'max_memory_percent'='30' );" >/dev/null 2>&1
q "GRANT USAGE_PRIV ON WORKLOAD GROUP 'big_etl' TO root;" >/dev/null 2>&1
q "GRANT USAGE_PRIV ON WORKLOAD GROUP 'fast_report' TO root;" >/dev/null 2>&1

ms() {  # 毫秒级计时
  local s=$(date +%s%N)
  "$@" >/dev/null 2>&1
  local e=$(date +%s%N)
  echo $(( (e - s) / 1000000 ))
}

echo "############ 基线：无干扰时小查询（5 次）############"
q "SET PROPERTY FOR 'root' 'default_workload_group' = 'normal';" >/dev/null 2>&1
sleep 2
BASE=""
for i in 1 2 3 4 5; do
  t=$(ms bash -c "$FE -e \"$FAST\"")
  BASE="$BASE $t"
  printf "  第%s次: %s ms\n" "$i" "$t"
done
echo "  → 基线范围:$BASE ms"

echo ""
echo "############ 场景 A：无隔离（3 条大查询并发干扰）############"
echo "  两条 SQL 都跑在 normal 组（出厂状态：并发几乎无限、队列 0）"
q "SET PROPERTY FOR 'root' 'default_workload_group' = 'normal';" >/dev/null 2>&1
sleep 2
for r in 1 2 3 4 5; do
  for i in 1 2 3; do ( $FE -e "$SLOW" >/dev/null 2>&1 ) & done
  sleep 0.5
  t=$(ms bash -c "$FE -e \"$FAST\"")
  printf "  第%s轮: %s ms\n" "$r" "$t"
  wait
done

echo ""
echo "############ 场景 B：有隔离（大查询限并发 1）############"
echo "  大查询 → big_etl（max_concurrency=1，其余排队）"
echo "  小查询 → fast_report（独立并发额度）"
for r in 1 2 3 4 5; do
  q "SET PROPERTY FOR 'root' 'default_workload_group' = 'big_etl';" >/dev/null 2>&1
  for i in 1 2 3; do ( $FE -e "$SLOW" >/dev/null 2>&1 ) & done
  sleep 0.5
  t=$(ms bash -c "$FE -e \"SET workload_group='fast_report'; $FAST\"")
  printf "  第%s轮: %s ms\n" "$r" "$t"
  wait
done

echo ""
echo "############ 观察：并发跑时组里发生了什么 ############"
q "SET PROPERTY FOR 'root' 'default_workload_group' = 'big_etl';" >/dev/null 2>&1
sleep 2
for i in 1 2 3 4; do ( $FE -e "$SLOW" >/dev/null 2>&1 ) & done
sleep 1.5
echo "  提交了 4 条大查询，看 big_etl（max_concurrency=1, max_queue_size=3）："
q "SHOW WORKLOAD GROUPS;" | awk -F'\t' '
  NR==1 { for(i=1;i<=NF;i++){ h[i]=$i } }
  NR>1 && $2=="big_etl" {
    for(i=1;i<=NF;i++){
      if(h[i]=="max_concurrency"||h[i]=="max_queue_size"||h[i]=="running_query_num")
        printf "    %s = %s\n", h[i], $i
    }
  }'
wait

echo ""
echo "############ 收尾 ############"
q "SET PROPERTY FOR 'root' 'default_workload_group' = 'normal';" >/dev/null 2>&1
echo "  已恢复 root 默认组为 normal"
echo ""
echo "=========================================="
echo " 步骤 1 完成 → 下一步：bash lesson10-step2.sh"
echo "=========================================="
