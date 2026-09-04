#!/bin/bash
# 课 7 步骤 5：并行度实验 —— 单机为什么调大不提速
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

echo "########## 并行度 1 / 2 / 4 / 8 对比 ##########"
for N in 1 2 4 8; do
  echo "--- parallel_pipeline_task_num = $N ---"
  for i in 1 2; do
    runq "SET enable_profile = true;
          SET parallel_pipeline_task_num = $N;
          SELECT COUNT(*) AS c, ROUND(SUM(LENGTH(pad1)+LENGTH(pad2)+LENGTH(pad3)),2) AS t
          FROM perf_wide;" > /dev/null
    runq "SHOW QUERY PROFILE '/';" > $OUT/l.txt
    Q=$(grep 'LENGTH' $OUT/l.txt | grep -oE '[0-9a-f]{16}-[0-9a-f]{16}' | head -1)
    if [ -n "$Q" ]; then
      getprof "$Q" > $OUT/p.txt
      TOTAL=$(grep -E '^   - Total:' $OUT/p.txt | grep -oE '[0-9]+ms')
      SCAN=$(grep -A 12 'OLAP_SCAN_OPERATOR' $OUT/p.txt | grep -oE 'ExecTime: avg [0-9.]+ms' | head -1)
      INST=$(grep -oE 'instance_num=[0-9]+' $OUT/p.txt | head -3 | tr '\n' ' ')
      echo "    Total=$TOTAL | Scan $SCAN | instance_num: $INST"
    fi
  done
done

echo ""
echo "########## 恢复默认并行度 ##########"
runq "SET parallel_pipeline_task_num = 0;"
runq "SELECT @@parallel_pipeline_task_num AS restored;"

echo ""
echo "########## 关键证据：扫描算子到底有几个 instance 在干活 ##########"
runq "SET enable_profile = true;
      SELECT COUNT(*) AS c, SUM(LENGTH(pad1)+LENGTH(pad2)+LENGTH(pad3)) AS t FROM perf_wide;" > /dev/null
runq "SHOW QUERY PROFILE '/';" > $OUT/l.txt
Q=$(grep 'LENGTH' $OUT/l.txt | grep -oE '[0-9a-f]{16}-[0-9a-f]{16}' | head -1)
[ -n "$Q" ] && getprof "$Q" > $OUT/p.txt
echo "  OLAP_SCAN_OPERATOR 的 RowsProduced（sum=max 说明只有 1 个 instance）:"
grep -A 14 'OLAP_SCAN_OPERATOR' $OUT/p.txt | grep -E 'RowsProduced' | sed 's/^ */    /'
echo "  LOCAL_EXCHANGE_OPERATOR 的 RowsProduced（sum≠avg 说明有 10 个 instance）:"
grep -A 14 'LOCAL_EXCHANGE_OPERATOR' $OUT/p.txt | grep -E 'RowsProduced' | sed 's/^ */    /'

echo "STEP5_DONE"
