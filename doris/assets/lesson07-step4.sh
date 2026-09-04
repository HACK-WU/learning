#!/bin/bash
# 课 7 步骤 4：减少扫描列 → 验证瓶颈确实在扫描量
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

echo "########## 扫 1 / 2 / 3 个 pad 列，看耗时线性增长 ##########"
declare -a SQLS=(
  "SELECT COUNT(*) AS c, SUM(LENGTH(pad1)) AS t FROM perf_wide"
  "SELECT COUNT(*) AS c, SUM(LENGTH(pad1)+LENGTH(pad2)) AS t FROM perf_wide"
  "SELECT COUNT(*) AS c, SUM(LENGTH(pad1)+LENGTH(pad2)+LENGTH(pad3)) AS t FROM perf_wide"
)
declare -a LABELS=("1 个 pad 列" "2 个 pad 列" "3 个 pad 列")

for idx in 0 1 2; do
  LABEL=${LABELS[$idx]}
  SQL=${SQLS[$idx]}
  echo "--- $LABEL ---"
  for i in 1 2; do
    runq "SET enable_profile = true; $SQL;" > /dev/null
    runq "SHOW QUERY PROFILE '/';" > $OUT/l.txt
    Q=$(grep 'LENGTH' $OUT/l.txt | grep -oE '[0-9a-f]{16}-[0-9a-f]{16}' | head -1)
    if [ -n "$Q" ]; then
      getprof "$Q" > $OUT/p.txt
      TOTAL=$(grep -E '^   - Total:' $OUT/p.txt | grep -oE '[0-9]+ms')
      SCAN=$(grep -A 12 'OLAP_SCAN_OPERATOR' $OUT/p.txt | grep -oE 'ExecTime: avg [0-9.]+ms' | head -1)
      OUTB=$(grep -A 12 'OLAP_SCAN_OPERATOR' $OUT/p.txt | grep -oE 'OutputBlockBytes: sum [0-9.]+ (MB|GB)' | head -1)
      echo "    第 $i 次: Total=$TOTAL | Scan $SCAN | $OUTB"
    fi
  done
done

echo ""
echo "########## 对照：只扫窄列 amount ##########"
for i in 1 2; do
  runq "SET enable_profile = true; SELECT COUNT(*) AS c, SUM(amount) AS t FROM perf_wide;" > /dev/null
  runq "SHOW QUERY PROFILE '/';" > $OUT/l.txt
  Q=$(grep 'SUM(amount)' $OUT/l.txt | grep -oE '[0-9a-f]{16}-[0-9a-f]{16}' | head -1)
  if [ -n "$Q" ]; then
    getprof "$Q" > $OUT/p.txt
    echo "    第 $i 次: Total=$(grep -E '^   - Total:' $OUT/p.txt | grep -oE '[0-9]+ms') | $(grep -A 12 'OLAP_SCAN_OPERATOR' $OUT/p.txt | grep -oE 'OutputBlockBytes: sum [0-9.]+ (MB|GB)' | head -1)"
  fi
done

echo "STEP4_DONE"
