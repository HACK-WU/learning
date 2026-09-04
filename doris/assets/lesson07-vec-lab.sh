#!/bin/bash
# 课 7：向量化开关实测（关 vs 开）
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

echo "########## 1. 确认向量化开关存在 ##########"
runq "SHOW VARIABLES LIKE 'enable_vectorized_engine';"

echo ""
echo "########## 2. 关闭向量化后跑聚合查询 ##########"
runq "SET GLOBAL enable_vectorized_engine = false;" 2>&1
runq "SELECT @@enable_vectorized_engine AS vec_now;" 2>&1
echo "--- 关向量化：GROUP BY province（跑 3 次）---"
for i in 1 2 3; do
  runq "SET enable_profile = true; SELECT province, COUNT(*) AS c, SUM(amount) AS s FROM perf_wide GROUP BY province;" >/dev/null
  runq "SHOW QUERY PROFILE '/';" > $OUT/l.txt
  Q=$(grep 'GROUP BY province' $OUT/l.txt | grep -oE '[0-9a-f]{16}-[0-9a-f]{16}' | head -1)
  [ -n "$Q" ] && getprof "$Q" > $OUT/p.txt && echo "  第 $i 次: $(grep -E '^   - Total:' $OUT/p.txt)"
done
echo "--- 关向量化：扫描算子名是什么 ---"
runq "SET enable_profile = true; SELECT province, COUNT(*) AS c FROM perf_wide GROUP BY province;" >/dev/null
runq "SHOW QUERY PROFILE '/';" > $OUT/l.txt
Q=$(grep 'GROUP BY province' $OUT/l.txt | grep -oE '[0-9a-f]{16}-[0-9a-f]{16}' | head -1)
[ -n "$Q" ] && getprof "$Q" > $OUT/poff.txt && grep -oE '[A-Z_]*SCAN_OPERATOR|[A-Z_]*AGGREGATION[A-Z_]*OPERATOR' $OUT/poff.txt | sort -u | head -8
echo "--- 关向量化：EXPLAIN 形态变化 ---"
runq "EXPLAIN SELECT province, COUNT(*) AS c FROM perf_wide GROUP BY province;" | head -25

echo ""
echo "########## 3. 恢复向量化后跑同样查询 ##########"
runq "SET GLOBAL enable_vectorized_engine = true;" 2>&1
runq "SELECT @@enable_vectorized_engine AS vec_now;" 2>&1
echo "--- 开向量化：GROUP BY province（跑 3 次）---"
for i in 1 2 3; do
  runq "SET enable_profile = true; SELECT province, COUNT(*) AS c, SUM(amount) AS s FROM perf_wide GROUP BY province;" >/dev/null
  runq "SHOW QUERY PROFILE '/';" > $OUT/l.txt
  Q=$(grep 'GROUP BY province' $OUT/l.txt | grep -oE '[0-9a-f]{16}-[0-9a-f]{16}' | head -1)
  [ -n "$Q" ] && getprof "$Q" > $OUT/p.txt && echo "  第 $i 次: $(grep -E '^   - Total:' $OUT/p.txt)"
done
echo "--- 开向量化：扫描算子名 ---"
runq "SET enable_profile = true; SELECT province, COUNT(*) AS c FROM perf_wide GROUP BY province;" >/dev/null
runq "SHOW QUERY PROFILE '/';" > $OUT/l.txt
Q=$(grep 'GROUP BY province' $OUT/l.txt | grep -oE '[0-9a-f]{16}-[0-9a-f]{16}' | head -1)
[ -n "$Q" ] && getprof "$Q" > $OUT/pon.txt && grep -oE '[A-Z_]*SCAN_OPERATOR|[A-Z_]*AGGREGATION[A-Z_]*OPERATOR' $OUT/pon.txt | sort -u | head -8

echo ""
echo "########## 4. 更大批量下对比：扫宽列 ##########"
echo "--- 关向量化 ---"
runq "SET GLOBAL enable_vectorized_engine = false;" 2>&1
for i in 1 2; do
  runq "SET enable_profile = true; SELECT COUNT(*) AS c, SUM(LENGTH(pad1)+LENGTH(pad2)+LENGTH(pad3)) AS t FROM perf_wide;" >/dev/null
  runq "SHOW QUERY PROFILE '/';" > $OUT/l.txt
  Q=$(grep 'LENGTH' $OUT/l.txt | grep -oE '[0-9a-f]{16}-[0-9a-f]{16}' | head -1)
  [ -n "$Q" ] && getprof "$Q" > $OUT/p.txt && echo "  第 $i 次: $(grep -E '^   - Total:' $OUT/p.txt) | $(grep -oE '[A-Z_]*SCAN_OPERATOR' $OUT/p.txt | sort -u | tr '\n' ' ')"
done
echo "--- 开向量化 ---"
runq "SET GLOBAL enable_vectorized_engine = true;" 2>&1
for i in 1 2; do
  runq "SET enable_profile = true; SELECT COUNT(*) AS c, SUM(LENGTH(pad1)+LENGTH(pad2)+LENGTH(pad3)) AS t FROM perf_wide;" >/dev/null
  runq "SHOW QUERY PROFILE '/';" > $OUT/l.txt
  Q=$(grep 'LENGTH' $OUT/l.txt | grep -oE '[0-9a-f]{16}-[0-9a-f]{16}' | head -1)
  [ -n "$Q" ] && getprof "$Q" > $OUT/p.txt && echo "  第 $i 次: $(grep -E '^   - Total:' $OUT/p.txt) | $(grep -oE '[A-Z_]*SCAN_OPERATOR' $OUT/p.txt | sort -u | tr '\n' ' ')"
done

echo ""
echo "########## 5. 确认恢复 ##########"
runq "SELECT @@enable_vectorized_engine AS vec_final, @@enable_sql_cache AS cache, @@enable_profile AS prof;"

echo "VEC_DONE"
