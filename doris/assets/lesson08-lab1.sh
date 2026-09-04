#!/bin/bash
# 课 8 实验 1：Join 的真实耗时 + Profile 看时间花在哪
# 前提：enable_sql_cache 必须关（课 7 已关），否则第二次跑命中缓存
MYSQL="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"
runq() {
  echo "$1" | $MYSQL 2>&1 | grep -vE "^Warning|Using a password"
}

echo "========== 0. 确认前置条件 =========="
runq "SHOW VARIABLES LIKE 'enable_sql_cache';"
runq "SHOW VARIABLES LIKE 'enable_profile';"
runq "SET GLOBAL enable_sql_cache = false;"
echo "--- 等 3 秒让全局设置生效 ---"
sleep 3
runq "SHOW VARIABLES LIKE 'enable_sql_cache';"

echo ""
echo "========== 1. 基线：单表聚合（Join 前的成本）=========="
echo "--- 单表：按省聚合 ---"
for i in 1 2 3; do
  echo "  第 $i 次："
  runq "SELECT province, COUNT(*) AS cnt, SUM(amount) AS amt FROM orders GROUP BY province ORDER BY province;" > /dev/null
  runq "SELECT 'single' AS q, COUNT(*) AS n FROM (SELECT province FROM orders GROUP BY province) x;"
done

echo ""
echo "========== 2. 大表 JOIN 小表（dim_province 12 行）=========="
for i in 1 2 3; do
  echo "  第 $i 次："
  runq "SELECT o.province, d.region, COUNT(*) AS cnt, SUM(o.amount) AS amt FROM orders o JOIN dim_province d ON o.province = d.province GROUP BY o.province, d.region ORDER BY o.province;"
done

echo ""
echo "========== 3. 大表 JOIN 中表（perf_wide 200 万行，分桶键）=========="
for i in 1 2 3; do
  echo "  第 $i 次："
  runq "SELECT o.province, w.province, COUNT(*) AS cnt FROM orders o JOIN perf_wide w ON o.province = w.province GROUP BY o.province, w.province ORDER BY o.province;"
done

echo ""
echo "========== 4. 大表 JOIN 大表（orders_dup 2050 万行，非分桶键）=========="
echo "--- 只统计行数，避免输出爆炸 ---"
for i in 1 2; do
  echo "  第 $i 次："
  runq "SELECT COUNT(*) AS total FROM orders o JOIN orders_dup p ON o.user_id = p.user_id;"
done

echo ""
echo "========== 5. Colocate Join（orders JOIN fact_prov，同组同分桶键）=========="
for i in 1 2 3; do
  echo "  第 $i 次："
  runq "SELECT o.province, COUNT(*) AS cnt FROM orders o JOIN fact_prov f ON o.province = f.province GROUP BY o.province ORDER BY o.province;"
done

echo ""
echo "========== 6. 用 Profile 看 Join 查询的时间花在哪 =========="
runq "SELECT o.province, d.region, COUNT(*) AS cnt, SUM(o.amount) AS amt FROM orders o JOIN dim_province d ON o.province = d.province GROUP BY o.province, d.region ORDER BY o.province;" > /dev/null
sleep 2
echo "$MYSQL" > /dev/null
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop -e "SHOW QUERY PROFILE '/';" 2>&1 | grep -vE "^Warning|Using a password" | grep "dim_province" | tail -3
