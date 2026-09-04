#!/bin/bash
# ============================================================
# 课 8 清理脚本：删除本课创建的实验对象，恢复全局设置
#
# ⚠️ 会删除的内容（都带 lesson08 命名特征或本课专用前缀）：
#   dim_region, fact_1m, colo_dim, non_colo_dim
#   log_typed, log_variant, log_json, user_profile
#   mv_prov_pay_daily, mv_part_daily, mv_sched
#   orders_part, v_probe, c_probe
#   dim_province, dim_province_colo, dim_province_big, fact_prov（探测阶段建的）
#   dim_mid, dim_small, mid_orders, mid_small, t_bucket_8（探测阶段建的，早期遗漏）
# 不会删除：orders, orders_dup, perf_wide 等前几课的既有表
# ============================================================
MYSQL="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"

runq() {
  echo "$1" | $MYSQL 2>&1 | grep -vE "^Warning|Using a password"
}

echo "========== 1. 删除异步物化视图（必须先删，它们依赖基表）=========="
for mv in mv_prov_pay_daily mv_part_daily mv_sched; do
  echo "--- DROP MATERIALIZED VIEW $mv ---"
  runq "DROP MATERIALIZED VIEW IF EXISTS $mv;"
done

echo ""
echo "========== 2. 删除本课建的表 =========="
for t in dim_region fact_1m colo_dim non_colo_dim \
         log_typed log_variant log_json user_profile \
         orders_part v_probe c_probe \
         dim_province dim_province_colo dim_province_big fact_prov \
         dim_mid dim_small mid_orders mid_small t_bucket_8; do
  printf "  %-22s " "$t"
  runq "DROP TABLE IF EXISTS $t;" 2>&1 | head -1
  echo "  dropped"
done

echo ""
echo "========== 3. 恢复全局设置 =========="
echo "--- 恢复 SQL 缓存（课 8 实验时关掉了，这是生产默认行为）---"
runq "SET GLOBAL enable_sql_cache = true;"
sleep 2
runq "SHOW VARIABLES LIKE 'enable_sql_cache';"

echo ""
echo "--- Profile 开关保持开启（后续课还要用，且它是排查利器）---"
runq "SHOW VARIABLES LIKE 'enable_profile';"

echo ""
echo "========== 4. 确认前几课的表还在 =========="
runq "SHOW TABLES;"

echo ""
echo "========== 5. 确认 orders 表数据完好（2150 万行）=========="
runq "SELECT COUNT(*) AS orders_rows FROM orders;"

echo ""
echo "==================== 清理完成 ===================="
echo "课 8 的全部实验对象已删除，全局设置已恢复。"
