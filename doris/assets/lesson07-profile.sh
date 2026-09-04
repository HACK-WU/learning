#!/bin/bash
# 课 7 Profile 抓取实验
OUT=/tmp/loadlab
mkdir -p $OUT

runq() {
  docker exec doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop -e "$1" 2>&1 \
    | grep -vE "^Warning|Using a password"
}

echo "=== 0. 确认 profile 开启 ==="
runq "SET GLOBAL enable_profile = true; SELECT @@enable_profile AS g; SET enable_profile = true; SELECT @@enable_profile AS s;"

echo ""
echo "=== 1. 跑一个会触发 Exchange 的聚合查询 ==="
runq "SELECT province, COUNT(*) AS cnt, ROUND(SUM(amount),2) AS total FROM orders GROUP BY province ORDER BY total DESC LIMIT 5;"

echo ""
echo "=== 2. 跑查询并立即取 profile 列表（同一会话）==="
runq "SELECT province, COUNT(*) AS c FROM orders GROUP BY province LIMIT 3; SHOW QUERY PROFILE '/';" > $OUT/prof_list.txt
cat $OUT/prof_list.txt

QID=$(grep -oE '[0-9a-f]{16}-[0-9a-f]{16}' $OUT/prof_list.txt | head -1)
echo ">>> QID=$QID"

if [ -n "$QID" ]; then
  echo ""
  echo "=== 3. 抓该 QueryID 的完整 Profile ==="
  runq "SHOW QUERY PROFILE '/$QID';" > $OUT/prof_full.txt
  echo "行数: $(wc -l < $OUT/prof_full.txt)"
  cat $OUT/prof_full.txt
fi

echo ""
echo "=== 4. 更重的查询（全表聚合）==="
runq "SELECT COUNT(*), ROUND(SUM(amount),2), ROUND(AVG(amount),2), MAX(amount), MIN(amount) FROM orders;"

echo ""
echo "=== 5. profile 列表 ==="
runq "SHOW QUERY PROFILE '/';" | head -12

echo ""
echo "=== 6. EXPLAIN GRAPH 完整输出 ==="
runq "EXPLAIN GRAPH SELECT province, COUNT(*) AS cnt FROM orders GROUP BY province ORDER BY cnt DESC LIMIT 5;"

echo ""
echo "=== 7. EXPLAIN VERBOSE ==="
runq "EXPLAIN VERBOSE SELECT province, COUNT(*) AS cnt FROM orders GROUP BY province ORDER BY cnt DESC LIMIT 5;"

echo "PROFILE_DONE"
