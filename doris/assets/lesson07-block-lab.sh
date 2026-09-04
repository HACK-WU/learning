#!/bin/bash
# 课 7：Block 批处理证据（向量化的直接体现）
OUT=/tmp/loadlab
mkdir -p $OUT

runq() {
  docker exec doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop -e "$1" 2>&1 \
    | grep -vE "^Warning|Using a password"
}
getprof() {
  docker exec doris-learn curl -s -u root: "http://127.0.0.1:8030/api/profile?query_id=$1" \
    | sed -e 's/\\n/\n/g' -e 's/\\"/"/g' -e 's/^.*"profile":"//' -e 's/"}}$//'
}

echo "########## 1. 相关配置 ##########"
runq "SELECT @@batch_size AS batch_size, @@preferred_block_size_bytes AS prefer_block_bytes, @@parallel_pipeline_task_num AS par_task, @@deprecated_parallel_fragment_exec_instance_num AS frag_inst;"

echo ""
echo "########## 2. 窄列扫描：SCAN 算子的 Block 切分 ##########"
runq "SET GLOBAL enable_sql_cache = false; SET GLOBAL enable_profile = true;"
runq "SET enable_profile = true; SELECT COUNT(*) AS c, SUM(amount) AS s FROM perf_wide;" >/dev/null
runq "SHOW QUERY PROFILE '/';" > $OUT/l.txt
Q=$(grep 'SUM(amount)' $OUT/l.txt | grep -oE '[0-9a-f]{16}-[0-9a-f]{16}' | head -1)
echo "Q=$Q"
[ -n "$Q" ] && getprof "$Q" > $OUT/pn.txt && awk '/OLAP_SCAN_OPERATOR/,/Scanner:/' $OUT/pn.txt | head -22

echo ""
echo "########## 3. 宽列扫描：SCAN 算子的 Block 切分 ##########"
runq "SET enable_profile = true; SELECT COUNT(*) AS c, SUM(LENGTH(pad1)+LENGTH(pad2)+LENGTH(pad3)) AS t FROM perf_wide;" >/dev/null
runq "SHOW QUERY PROFILE '/';" > $OUT/l.txt
Q=$(grep 'LENGTH' $OUT/l.txt | grep -oE '[0-9a-f]{16}-[0-9a-f]{16}' | head -1)
echo "Q=$Q"
[ -n "$Q" ] && getprof "$Q" > $OUT/pw.txt && awk '/OLAP_SCAN_OPERATOR/,/Scanner:/' $OUT/pw.txt | head -22

echo ""
echo "########## 4. LOCAL_EXCHANGE 的 Block 证据（宽列）##########"
grep -A 14 "LOCAL_EXCHANGE_OPERATOR(PASSTHROUGH)" $OUT/pw.txt | head -16

echo ""
echo "########## 5. 大表 orders（2150万行）的 Block 切分 ##########"
runq "SET enable_profile = true; SELECT COUNT(*) AS c, SUM(amount) AS s FROM orders;" >/dev/null
runq "SHOW QUERY PROFILE '/';" > $OUT/l.txt
Q=$(grep 'SUM(amount)' $OUT/l.txt | grep -oE '[0-9a-f]{16}-[0-9a-f]{16}' | head -1)
echo "Q=$Q"
[ -n "$Q" ] && getprof "$Q" > $OUT/po.txt && awk '/OLAP_SCAN_OPERATOR/,/Scanner:/' $OUT/po.txt | head -22

echo ""
echo "########## 6. Pipeline 层级全貌（窄列查询）##########"
grep -E "Fragment [0-9]:|Pipeline [0-9]|OPERATOR\(|instance_num" $OUT/pn.txt | head -30

echo "BLOCK_DONE"
