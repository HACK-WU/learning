#!/bin/bash
# 课 10 评审辅助 1：learner 视角 —— 正文里所有 SQL / 命令能否照抄跑通
# 检查项：① 省略写法 ② 属性名是否废弃 ③ 引用了不存在的脚本 ④ 表名/列名是否真实存在
LESSON="/mnt/d/projects/learning/doris/stages/4-分布式运维与生产落地/lessons/lesson-10-资源隔离与负载管理.md"
SCRIPTS="/mnt/d/projects/learning/doris/assets"
FE='docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop'
q() { $FE -e "$1" 2>&1 | grep -vE "^Warning|Using a password"; }

echo "===== 1. 省略写法检查（硬约束）====="
hits=$(grep -nE "（同上）|\(同上\)|列定义同上" "$LESSON" | grep -vE "禁止出现|这类省略|没有「|无「")
if [ -z "$hits" ]; then
  echo "  [OK] 无省略写法"
else
  echo "  [FAIL] 发现省略写法："
  echo "$hits" | sed 's/^/    /'
fi

echo ""
echo "===== 2. 废弃属性名检查（正文里不该出现可用写法之外的旧属性）====="
for p in memory_limit cpu_share cpu_hard_limit enable_memory_overcommit; do
  n=$(grep -c "'$p'" "$LESSON")
  if [ "$n" -gt 0 ]; then
    # 出现在"已废弃"说明里是允许的
    ctx=$(grep -n "'$p'" "$LESSON" | head -3 | cut -c1-90)
    echo "  属性 $p 出现 $n 次，上下文："
    echo "$ctx" | sed 's/^/    /'
  fi
done

echo ""
echo "===== 3. 正文引用的脚本是否真实存在 ====="
for s in $(grep -oE 'lesson10-[a-z0-9]+\.sh' "$LESSON" | sort -u); do
  if [ -f "$SCRIPTS/$s" ]; then
    echo "  [OK]   $s"
  else
    echo "  [FAIL] $s （正文引用了但文件不存在）"
  fi
done

echo ""
echo "===== 4. 正文引用的 SVG 是否真实存在 ====="
ASSETS="/mnt/d/projects/learning/doris/stages/4-分布式运维与生产落地/assets"
for f in $(grep -oE 'lesson-10-[a-z]+\.svg' "$LESSON" | sort -u); do
  if [ -f "$ASSETS/$f" ]; then
    echo "  [OK]   $f"
  else
    echo "  [FAIL] $f （引用了但不存在）"
  fi
done

echo ""
echo "===== 5. 正文提到的表是否真实存在 ====="
for t in orders perf_wide perf_wide_big fact_1m dim_region cost1 repl3 ha_demo pinned_be2; do
  if [ "$t" = "cost1" ] || [ "$t" = "repl3" ] || [ "$t" = "ha_demo" ] || [ "$t" = "pinned_be2" ]; then
    continue   # 课 9 的表，正文只在环境清单里提到
  fi
  if q "SHOW TABLES LIKE '$t';" | grep -q "$t"; then
    echo "  [OK]   表 $t 存在"
  else
    echo "  [FAIL] 表 $t 不存在"
  fi
done

echo ""
echo "===== 6. 正文用到的列是否真实存在（orders 表）====="
echo "  orders 表实际列："
q "DESC orders;" | awk 'NR>1{printf "    %s\n", $1}'

echo ""
echo "===== 7. 正文里的关键 SQL 逐条实跑验证 ====="
runq() {
  local label="$1"
  local sql="$2"
  out=$(q "$sql" 2>&1 | head -1)
  if echo "$out" | grep -q "ERROR"; then
    printf "  [FAIL] %s\n         %s\n" "$label" "${out:0:120}"
  else
    printf "  [OK]   %s\n" "$label"
  fi
}

runq "SHOW WORKLOAD GROUPS"            "SHOW WORKLOAD GROUPS;"
runq "SHOW PROPERTY"                   "SHOW PROPERTY FOR 'root' LIKE '%workload%';"
runq "SHOW VARIABLES spill"            "SHOW VARIABLES LIKE 'enable_spill';"
runq "SHOW VARIABLES exec_mem_limit"   "SHOW VARIABLES LIKE 'exec_mem_limit';"
runq "小查询（报表）"                   "SELECT province, COUNT(*) c FROM orders GROUP BY province ORDER BY c DESC LIMIT 8;"
runq "大查询（自关联）"                 "SELECT COUNT(*) FROM orders a JOIN orders b ON a.user_id=b.user_id;"
runq "高基数聚合（spill 用）"           "SELECT user_id, COUNT(*) c, SUM(amount) s FROM orders GROUP BY user_id ORDER BY c DESC LIMIT 10;"
runq "CREATE big_etl 语法"             "CREATE WORKLOAD GROUP IF NOT EXISTS _probe_a PROPERTIES ( 'max_concurrency'='1', 'max_queue_size'='3', 'queue_timeout'='30000', 'min_memory_percent'='5', 'max_memory_percent'='30' );"
runq "CREATE fast_report 语法"         "CREATE WORKLOAD GROUP IF NOT EXISTS _probe_b PROPERTIES ( 'max_concurrency'='10', 'max_queue_size'='0', 'queue_timeout'='0', 'min_memory_percent'='5', 'max_memory_percent'='30' );"
runq "GRANT 语法"                      "GRANT USAGE_PRIV ON WORKLOAD GROUP '_probe_a' TO root;"
runq "SET PROPERTY 语法"               "SET PROPERTY FOR 'root' 'default_workload_group' = '_probe_a';"
runq "SET workload_group 语法"         "SET workload_group = '_probe_b';"
runq "生产配置示例 report_wg"           "CREATE WORKLOAD GROUP IF NOT EXISTS _probe_c PROPERTIES ( 'min_memory_percent'='20', 'max_memory_percent'='40', 'max_concurrency'='20', 'max_queue_size'='5', 'queue_timeout'='3000', 'memory_low_watermark'='70%', 'memory_high_watermark'='85%' );"
runq "生产配置示例 etl_wg"             "CREATE WORKLOAD GROUP IF NOT EXISTS _probe_d PROPERTIES ( 'min_memory_percent'='10', 'max_memory_percent'='50', 'max_concurrency'='2', 'max_queue_size'='20', 'queue_timeout'='600000', 'memory_low_watermark'='60%', 'memory_high_watermark'='80%' );"
runq "小测第3题 report_wg"             "CREATE WORKLOAD GROUP IF NOT EXISTS _probe_e PROPERTIES ( 'min_memory_percent'='25', 'max_memory_percent'='45', 'max_concurrency'='20', 'max_queue_size'='5', 'queue_timeout'='3000' );"
runq "小测第3题 adhoc_wg"              "CREATE WORKLOAD GROUP IF NOT EXISTS _probe_f PROPERTIES ( 'min_memory_percent'='5', 'max_memory_percent'='15', 'max_concurrency'='2', 'max_queue_size'='3', 'queue_timeout'='5000' );"

echo ""
echo "===== 8. 清理探测组 ====="
for g in _probe_a _probe_b _probe_c _probe_d _probe_e _probe_f; do
  q "DROP WORKLOAD GROUP IF EXISTS $g;" >/dev/null 2>&1
done
q "SET PROPERTY FOR 'root' 'default_workload_group' = 'normal';" >/dev/null 2>&1
echo "  已清理"
