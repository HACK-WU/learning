#!/bin/bash
# 课 10 评审辅助 2：实跑正文里的 CREATE WORKLOAD GROUP 示例
# ⚠️ 修正 review1 的 bug：Doris 的组名不能以下划线开头，改用 rv 前缀
FE='docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop'
q() { $FE -e "$1" 2>&1 | grep -vE "^Warning|Using a password"; }

runq() {
  local label="$1"
  local sql="$2"
  out=$(q "$sql" 2>&1 | head -1)
  if echo "$out" | grep -q "ERROR"; then
    printf "  [FAIL] %s\n         %s\n" "$label" "${out:0:150}"
  else
    printf "  [OK]   %s\n" "$label"
  fi
}

echo "===== 正文 1.3 节：big_etl / fast_report 建组语句 ====="
runq "big_etl（正文 1.3）" \
  "CREATE WORKLOAD GROUP IF NOT EXISTS rvbig PROPERTIES ( 'max_concurrency'='1', 'max_queue_size'='3', 'queue_timeout'='30000', 'max_memory_percent'='30', 'min_memory_percent'='5' );"
runq "fast_report（正文 1.3）" \
  "CREATE WORKLOAD GROUP IF NOT EXISTS rvfast PROPERTIES ( 'max_concurrency'='10', 'max_queue_size'='0', 'queue_timeout'='0', 'max_memory_percent'='30', 'min_memory_percent'='10' );"

echo ""
echo "===== 正文 1.4 节：可用属性清单（逐个建，验证都能过）====="
for i in 1 2 3 4 5 6 7 8 9 10 11; do
  case $i in
    1)  p="'min_cpu_percent'='10'";;
    2)  p="'max_cpu_percent'='50'";;
    3)  p="'min_memory_percent'='10'";;
    4)  p="'max_memory_percent'='30'";;
    5)  p="'max_concurrency'='2'";;
    6)  p="'max_queue_size'='5'";;
    7)  p="'queue_timeout'='3000'";;
    8)  p="'scan_thread_num'='4'";;
    9)  p="'memory_low_watermark'='50%'";;
    10) p="'memory_high_watermark'='70%'";;
    11) p="'read_bytes_per_second'='1048576'";;
  esac
  runq "属性 $p" "CREATE WORKLOAD GROUP IF NOT EXISTS rvattr$i PROPERTIES ( $p );"
done

echo ""
echo "===== 正文 1.4 节：废弃属性（应该报错，正文是这么写的）====="
for i in 1 2 3 4 5; do
  case $i in
    1)  p="'cpu_share'='1024'";;
    2)  p="'memory_limit'='30%'";;
    3)  p="'cpu_hard_limit'='20%'";;
    4)  p="'enable_memory_overcommit'='true'";;
    5)  p="'tag'='dev'";;
  esac
  out=$(q "CREATE WORKLOAD GROUP IF NOT EXISTS rvbad$i PROPERTIES ( $p );" 2>&1 | head -1)
  if echo "$out" | grep -q "ERROR"; then
    printf "  [OK]   %-40s 确实报错（与正文一致）\n" "$p"
  else
    printf "  [FAIL] %-40s 没报错！正文说它废弃，实际能用\n" "$p"
  fi
done

echo ""
echo "===== 正文 1.4 节：水位约束（应该报错）====="
out=$(q "CREATE WORKLOAD GROUP IF NOT EXISTS rvwl PROPERTIES ( 'memory_low_watermark'='75%', 'memory_high_watermark'='70%' );" 2>&1 | head -1)
if echo "$out" | grep -q "ERROR"; then
  echo "  [OK]   高水位<低水位 确实报错（与正文一致）"
else
  echo "  [FAIL] 没报错，正文说法有误"
fi

echo ""
echo "===== 正文 3.7 节：生产配置示例 ====="
runq "report_wg" \
  "CREATE WORKLOAD GROUP IF NOT EXISTS rvrep PROPERTIES ( 'min_memory_percent'='20', 'max_memory_percent'='40', 'max_concurrency'='20', 'max_queue_size'='5', 'queue_timeout'='3000', 'memory_low_watermark'='70%', 'memory_high_watermark'='85%' );"
runq "etl_wg" \
  "CREATE WORKLOAD GROUP IF NOT EXISTS rvetl PROPERTIES ( 'min_memory_percent'='10', 'max_memory_percent'='50', 'max_concurrency'='2', 'max_queue_size'='20', 'queue_timeout'='600000', 'memory_low_watermark'='60%', 'memory_high_watermark'='80%' );"

echo ""
echo "===== 正文 3.7 节：GRANT + SET PROPERTY 两步 ====="
runq "GRANT report_wg" "GRANT USAGE_PRIV ON WORKLOAD GROUP 'rvrep' TO root;"
runq "SET PROPERTY report_wg" "SET PROPERTY FOR 'root' 'default_workload_group' = 'rvrep';"
q "SET PROPERTY FOR 'root' 'default_workload_group' = 'normal';" >/dev/null 2>&1

echo ""
echo "===== 小测第 3 题参考答案里的三个组 ====="
runq "report_wg（小测）" \
  "CREATE WORKLOAD GROUP IF NOT EXISTS rvq1 PROPERTIES ( 'min_memory_percent'='25', 'max_memory_percent'='45', 'max_concurrency'='20', 'max_queue_size'='5', 'queue_timeout'='3000' );"
runq "etl_wg（小测）" \
  "CREATE WORKLOAD GROUP IF NOT EXISTS rvq2 PROPERTIES ( 'min_memory_percent'='10', 'max_memory_percent'='40', 'max_concurrency'='3', 'max_queue_size'='20', 'queue_timeout'='600000' );"
runq "adhoc_wg（小测）" \
  "CREATE WORKLOAD GROUP IF NOT EXISTS rvq3 PROPERTIES ( 'min_memory_percent'='5', 'max_memory_percent'='15', 'max_concurrency'='2', 'max_queue_size'='3', 'queue_timeout'='5000' );"

echo ""
echo "===== 清理 ====="
for g in rvbig rvfast rvrep rvetl rvq1 rvq2 rvq3 rvwl $(for i in $(seq 1 11); do echo "rvattr$i"; done); do
  q "DROP WORKLOAD GROUP IF EXISTS $g;" >/dev/null 2>&1
done
q "SET PROPERTY FOR 'root' 'default_workload_group' = 'normal';" >/dev/null 2>&1
echo "  已清理，剩余组："
q "SHOW WORKLOAD GROUPS;" | cut -f2 | sed 's/^/    /'
