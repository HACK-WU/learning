#!/bin/bash
# 课 7 步骤 2：窄列 vs 宽列，13 倍差距复现
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

echo "########## A. 扫 1 个窄列 amount（跑 3 次）##########"
for i in 1 2 3; do
  runq "SET enable_profile = true;
        SELECT COUNT(*) AS c, ROUND(SUM(amount),2) AS t FROM perf_wide;" > /dev/null
  runq "SHOW QUERY PROFILE '/';" > $OUT/la.txt
  Q=$(grep 'SUM(amount)' $OUT/la.txt | grep -oE '[0-9a-f]{16}-[0-9a-f]{16}' | head -1)
  if [ -n "$Q" ]; then
    getprof "$Q" > $OUT/pa.txt
    echo "  第 $i 次: $(grep -E '^   - Total:' $OUT/pa.txt) | $(grep -E 'ScanBytes' $OUT/pa.txt | head -1 | sed 's/^ *//')"
  else
    echo "  第 $i 次: 未抓到 Profile —— 检查 enable_profile 是否为 true"
  fi
done

echo ""
echo "########## B. 扫 3 个 500 字节宽列（跑 3 次）##########"
for i in 1 2 3; do
  runq "SET enable_profile = true;
        SELECT COUNT(*) AS c, ROUND(SUM(LENGTH(pad1)+LENGTH(pad2)+LENGTH(pad3)),2) AS t FROM perf_wide;" > /dev/null
  runq "SHOW QUERY PROFILE '/';" > $OUT/lb.txt
  Q=$(grep 'LENGTH' $OUT/lb.txt | grep -oE '[0-9a-f]{16}-[0-9a-f]{16}' | head -1)
  if [ -n "$Q" ]; then
    getprof "$Q" > $OUT/pb.txt
    echo "  第 $i 次: $(grep -E '^   - Total:' $OUT/pb.txt) | $(grep -E 'ScanBytes' $OUT/pb.txt | head -1 | sed 's/^ *//')"
  else
    echo "  第 $i 次: 未抓到 Profile"
  fi
done

echo ""
echo "########## C. 两个查询的扫描算子完整指标对比 ##########"
echo "--- 窄列 ---"
awk '/OLAP_SCAN_OPERATOR/,/CustomCounters/' $OUT/pa.txt | grep -E "ExecTime|OutputBlockBytes|RowsProduced|BlocksProduced|ScanBytes" | sed 's/^ */    /'
echo "--- 宽列 ---"
awk '/OLAP_SCAN_OPERATOR/,/CustomCounters/' $OUT/pb.txt | grep -E "ExecTime|OutputBlockBytes|RowsProduced|BlocksProduced|ScanBytes" | sed 's/^ */    /'

echo "STEP2_DONE"
