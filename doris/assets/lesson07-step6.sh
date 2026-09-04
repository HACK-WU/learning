#!/bin/bash
# 课 7 步骤 6：确认 Block 批处理机制真实存在
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

echo "########## 1. Block 相关配置 ##########"
runq "SELECT @@batch_size AS batch_size,
             @@preferred_block_size_bytes AS prefer_block_bytes,
             @@parallel_pipeline_task_num AS par_task;"

echo ""
echo "########## 2. 窄列扫描的 Block 切分 ##########"
runq "SET enable_profile = true;
      SELECT COUNT(*) AS c, SUM(amount) AS s FROM perf_wide;" > /dev/null
runq "SHOW QUERY PROFILE '/';" > $OUT/l.txt
Q=$(grep 'SUM(amount)' $OUT/l.txt | grep -oE '[0-9a-f]{16}-[0-9a-f]{16}' | head -1)
[ -n "$Q" ] && getprof "$Q" > $OUT/pn.txt
echo "  200 万行被切成了多少个 Block？"
grep -A 14 'OLAP_SCAN_OPERATOR' $OUT/pn.txt | grep -E 'BlocksProduced|RowsProduced|MaxOutputBlockBytes' | sed 's/^ */    /'
BLOCKS=$(grep -A 14 'OLAP_SCAN_OPERATOR' $OUT/pn.txt | grep -oE 'BlocksProduced: sum [0-9.]+K?' | grep -oE '[0-9.]+' | head -1)
echo "  → 平均每块行数 = 2000000 / $BLOCKS"

echo ""
echo "########## 3. 宽列扫描的 Block 切分（字节数先到上限）##########"
runq "SET enable_profile = true;
      SELECT COUNT(*) AS c, SUM(LENGTH(pad1)+LENGTH(pad2)+LENGTH(pad3)) AS t FROM perf_wide;" > /dev/null
runq "SHOW QUERY PROFILE '/';" > $OUT/l.txt
Q=$(grep 'LENGTH' $OUT/l.txt | grep -oE '[0-9a-f]{16}-[0-9a-f]{16}' | head -1)
[ -n "$Q" ] && getprof "$Q" > $OUT/pw.txt
grep -A 14 'OLAP_SCAN_OPERATOR' $OUT/pw.txt | grep -E 'BlocksProduced|RowsProduced|MaxOutputBlockBytes|OutputBlockBytes' | sed 's/^ */    /'

echo ""
echo "########## 4. 对照：2150 万行的 orders 表 ##########"
runq "SET enable_profile = true;
      SELECT COUNT(*) AS c, SUM(amount) AS s FROM orders;" > /dev/null
runq "SHOW QUERY PROFILE '/';" > $OUT/l.txt
Q=$(grep 'SUM(amount)' $OUT/l.txt | grep -oE '[0-9a-f]{16}-[0-9a-f]{16}' | head -1)
[ -n "$Q" ] && getprof "$Q" > $OUT/po.txt
grep -A 14 'OLAP_SCAN_OPERATOR' $OUT/po.txt | grep -E 'BlocksProduced|RowsProduced|MaxOutputBlockBytes|ScanBytes' | sed 's/^ */    /'

echo "STEP6_DONE"
