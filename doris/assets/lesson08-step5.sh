#!/bin/bash
# ============================================================
# 课 8 第四幕 步骤 5：看实测耗时与磁盘占用
#
# 前提：已跑过 lesson08-step4.sh（三张表已建好并跑过查询）
#
# ⚠️ 两个必须知道的前提：
#   1. SHOW DATA 依赖后台统计，紧跟 INSERT 执行会返回 0.000
#      （不是没数据，是统计还没刷新）。实测需等约 45 秒，这里等 60 秒。
#   2. 耗时从 Profile 里取，按 SQL 文本 grep 过滤
# ============================================================
MYSQL="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"

runq() {
  echo "$1" | $MYSQL 2>&1 | grep -vE "^Warning|Using a password"
}

echo "========== 步骤 5.1：从 Profile 取过滤场景的真实耗时 =========="
echo ""
echo "--- 结构化列（WHERE device = 'iOS'）---"
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop -e "SHOW QUERY PROFILE '/';" 2>&1 \
  | grep -vE "^Warning|Using a password" | grep "log_typed" | head -4

echo ""
echo "--- VARIANT 子列（WHERE payload['device'] = 'iOS'）---"
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop -e "SHOW QUERY PROFILE '/';" 2>&1 \
  | grep -vE "^Warning|Using a password" | grep "log_variant" | head -4

echo ""
echo "--- JSON 字符串（WHERE get_json_string(...) = 'iOS'）---"
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop -e "SHOW QUERY PROFILE '/';" 2>&1 \
  | grep -vE "^Warning|Using a password" | grep "log_json" | head -4

echo ""
echo "👆 输出格式：QueryID | QUERY | 开始时间 | 结束时间 | 耗时 | 状态 | ... | SQL文本"
echo "   看第 5 列（耗时）。本机参考值（过滤场景）："
echo "     结构化列  26-46 ms"
echo "     VARIANT   16-26 ms"
echo "     JSON 串   129-156 ms   ← 慢 6-9 倍"
echo ""
echo "   ⚠️ 数值会浮动：这台机器上还跑着 Kafka、MinIO 和一批监控容器，"
echo "      同一条 SQL 不同批次能差 2 倍。看倍数趋势，不要看绝对毫秒数。"

echo ""
echo "========== 步骤 5.2：聚合场景耗时对比（各跑 4 次）=========="
echo "--- 结构化列 ---"
for i in 1 2 3 4; do
  runq "SELECT city, COUNT(*) AS cnt, SUM(cost) AS total FROM log_typed GROUP BY city ORDER BY city;" > /dev/null
done
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop -e "SHOW QUERY PROFILE '/';" 2>&1 \
  | grep -vE "^Warning|Using a password" | grep "log_typed" | head -4

echo ""
echo "--- VARIANT 子列（CAST 后）---"
for i in 1 2 3 4; do
  runq "SELECT CAST(payload['city'] AS VARCHAR(32)) AS city, COUNT(*) AS cnt, SUM(CAST(payload['cost'] AS BIGINT)) AS total FROM log_variant GROUP BY CAST(payload['city'] AS VARCHAR(32)) ORDER BY city;" > /dev/null
done
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop -e "SHOW QUERY PROFILE '/';" 2>&1 \
  | grep -vE "^Warning|Using a password" | grep "log_variant" | head -4

echo ""
echo "--- JSON 字符串 ---"
for i in 1 2 3 4; do
  runq "SELECT get_json_string(payload, '\$.city') AS city, COUNT(*) AS cnt, SUM(CAST(get_json_string(payload, '\$.cost') AS BIGINT)) AS total FROM log_json GROUP BY get_json_string(payload, '\$.city') ORDER BY city;" > /dev/null
done
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop -e "SHOW QUERY PROFILE '/';" 2>&1 \
  | grep -vE "^Warning|Using a password" | grep "log_json" | head -4

echo ""
echo "👆 本机参考值：结构化列 30-46ms / VARIANT 49-67ms / JSON 串 237-287ms"

echo ""
echo "========== 步骤 5.3：确认三种写法结果一致 =========="
echo "--- 结构化列 ---"
runq "SELECT city, COUNT(*) AS cnt FROM log_typed GROUP BY city ORDER BY city;"
echo "--- VARIANT（CAST 后）---"
runq "SELECT CAST(payload['city'] AS VARCHAR(32)) AS city, COUNT(*) AS cnt FROM log_variant GROUP BY CAST(payload['city'] AS VARCHAR(32)) ORDER BY city;"
echo "--- JSON 字符串 ---"
runq "SELECT get_json_string(payload, '\$.city') AS city, COUNT(*) AS cnt FROM log_json GROUP BY get_json_string(payload, '\$.city') ORDER BY city;"
echo ""
echo "👆 三组数字应该完全相同。对不上说明写法有问题，先别往下跑。"

echo ""
echo "========== 步骤 5.4：磁盘占用对比 =========="
echo "    （SHOW DATA 依赖后台统计，紧跟 INSERT 会返回 0.000。"
echo "     等待 60 秒让统计刷新，否则你会误以为数据丢了）"
sleep 60
echo "--- 结构化列 ---"
runq "SHOW DATA FROM log_typed;"
echo "--- VARIANT ---"
runq "SHOW DATA FROM log_variant;"
echo "--- JSON 字符串 ---"
runq "SHOW DATA FROM log_json;"

echo ""
echo "👆 本机参考值：结构化列 3.46 MB / VARIANT 3.49 MB / JSON 串 7.37 MB"
echo "   VARIANT 的磁盘占用几乎和结构化列一样（多了不到 1%），"
echo "   而 JSON 字符串要多占一倍。"
echo "   （不同批次的绝对值会略有出入，看三者的比例关系即可）"

echo ""
echo "==================== 步骤 5 完成 ===================="
echo "下一步：bash lesson08-step6.sh  （Array / Map / Struct）"
