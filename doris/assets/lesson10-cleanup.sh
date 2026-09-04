#!/bin/bash
# 课 10 清理：删除本课创建的所有 Workload Group，恢复环境
# 用法：bash lesson10-cleanup.sh

FE='docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop'
q() { $FE -e "$1" 2>&1 | grep -vE "^Warning|Using a password"; }

echo "=========================================="
echo " 课 10 清理"
echo "=========================================="
echo ""

echo "===== 1. 恢复 root 默认组 ====="
q "SET PROPERTY FOR 'root' 'default_workload_group' = 'normal';" >/dev/null 2>&1
q "SHOW PROPERTY FOR 'root' LIKE '%workload%';" | sed 's/^/  /'

echo ""
echo "===== 2. 删除本课创建的 Workload Group ====="
for g in big_etl fast_report wg_c1 wg_c5 wg_t1 etl_small ad_hoc mem_hi mem_lo memA memB \
         cpu_hi cpu_lo scan_lo wg_bigmem wg_smallmem wgA wgB wgC probe_wg; do
  out=$(q "DROP WORKLOAD GROUP IF EXISTS $g;" 2>&1)
  if [ -z "$out" ]; then
    echo "  已删: $g"
  fi
done

echo ""
echo "===== 3. 清理 spill 临时目录 ====="
echo "  ⚠️ 只能在没有查询在跑的时候清理"
RUNNING=$(q "SHOW WORKLOAD GROUPS;" | awk -F'\t' 'NR>1 && $18!="" {s+=$18} END{print s+0}')
echo "  当前 running_query_num 合计: $RUNNING"
if [ "${RUNNING:-0}" = "0" ]; then
  docker exec -i doris-learn bash -c 'rm -rf /opt/apache-doris/be/storage/spill/*' 2>/dev/null
  echo "  已清空 spill 目录"
else
  echo "  [SKIP] 有查询在跑，跳过清理"
fi

echo ""
echo "===== 4. 恢复全局设置 ====="
echo "  把会话期间可能被改过的变量恢复出厂值："
q "SET GLOBAL enable_spill = false;" >/dev/null 2>&1
echo "    enable_spill → false（出厂默认）"
q "SHOW VARIABLES LIKE 'enable_spill';" | sed 's/^/  /'

echo ""
echo "===== 5. 最终状态 ====="
q "SHOW WORKLOAD GROUPS;" | cut -f2 | sed 's/^/  /'

echo ""
echo "=========================================="
echo " 课 10 清理完成"
echo "=========================================="
echo ""
echo "  ⚠️ 课 9 的遗留项（本课未改动）："
echo "     - disable_balance = false（课 9 从 true 改过来的，课 11 做确定性实验前需先关回 true）"
echo "     - enable_sql_cache = false（课 7 关的，测性能需要；不测性能请恢复 true）"
echo "     - BE2 仍在运行（课 9 拉起的第二个 BE，127.0.0.1:19050）"
