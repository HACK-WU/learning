#!/bin/bash
# 课 7 步骤 7：用 EXPLAIN 验证优化是否生效
runq() {
  docker exec doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop -e "$1" 2>&1 \
    | grep -vE "^Warning|Using a password"
}

echo "########## 1. 谓词下推 + 分桶裁剪（orders 表按 province 分 8 桶）##########"
runq "EXPLAIN SELECT province, COUNT(*) FROM orders WHERE province = '广东' GROUP BY province;"

echo ""
echo "########## 2. 对照：不带 WHERE，看 tablets 变化 ##########"
runq "EXPLAIN SELECT province, COUNT(*) FROM orders GROUP BY province;"

echo ""
echo "########## 3. 两阶段聚合：找 update serialize 和 merge finalize ##########"
runq "EXPLAIN SELECT province, COUNT(*) AS c, SUM(amount) AS s FROM perf_wide GROUP BY province;" \
  | grep -E "PLAN FRAGMENT|VAGGREGATE|VOlapScanNode|VEXCHANGE|STREAM DATA SINK|HASH_PARTITIONED"

echo ""
echo "########## 4. GRAPH 形态（画成框线，适合贴文档）##########"
runq "EXPLAIN GRAPH SELECT province, COUNT(*) AS c FROM perf_wide GROUP BY province ORDER BY c DESC LIMIT 3;"

echo ""
echo "########## 5. Runtime Filter（Join 时才会有）##########"
runq "EXPLAIN SELECT a.province, COUNT(*) FROM perf_wide a JOIN perf_wide b ON a.id = b.id WHERE b.province = 'prov_0' GROUP BY a.province;" \
  | grep -E "runtime filters|VHASH JOIN|VOlapScanNode|PREDICATES"

echo "STEP7_DONE"
