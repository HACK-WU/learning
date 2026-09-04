#!/usr/bin/env bash
# Phase 3 · Task 3：基线测量 → 加速 → 优化后测量 → Profile
# 用法：bash assets/phase3-task3-tune.sh
# 计时用单连接串行，避免 docker exec 连接开销污染（课 12 教训）
set -u

Q() { docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot "$@" 2>&1; }
DQ() { docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot dw "$@" 2>&1; }

# 跑 5 轮取 min/max（每轮一次 docker exec，避免连接开销污染）
bench_range() {
  local SQL="$1"
  local TIMES=""
  for r in 1 2 3 4 5; do
    local S E
    S=$(date +%s.%N)
    echo "$SQL" | docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot dw -N > /dev/null 2>&1
    E=$(date +%s.%N)
    TIMES="$TIMES $(echo "scale=3; $E - $S" | bc)"
  done
  echo "$TIMES" | tr ' ' '\n' | grep -v '^$' | sort -n \
    | awk 'NR==1{printf "%s", $0} END{printf " - %s\n", $0}'
}

echo "=========================================="
echo " Phase 3 · Task 3：查询加速与调优"
echo "=========================================="
echo

echo "--- 0. 确认前置数据 ---"
DQ -e "SELECT COUNT(*) AS dwd_rows, SUM(amount) AS dwd_sum FROM dwd_orders;"
echo

echo "########## 1. 基线测量 ##########"
echo

Q1="SELECT province, COUNT(*) AS cnt, SUM(amount) AS s FROM dwd_orders GROUP BY province ORDER BY s DESC LIMIT 10;"
Q2="SELECT COUNT(*) AS cnt, SUM(amount) AS gmv FROM dwd_orders;"
Q3="SELECT order_date, user_id, order_id, amount FROM dwd_orders WHERE user_id = 100234 ORDER BY order_date DESC LIMIT 100;"
Q4="SELECT category, pay_type, COUNT(*) AS cnt, SUM(amount) AS s FROM dwd_orders GROUP BY category, pay_type ORDER BY s DESC;"
Q5="SELECT p.region, COUNT(*) AS cnt, SUM(d.amount) AS s FROM dwd_orders d JOIN dim_province p ON d.province = p.province GROUP BY p.region ORDER BY s DESC;"

echo "  Q1 省份聚合（基线）: $(bench_range "$Q1")"
echo "  Q2 全量 GMV（基线）: $(bench_range "$Q2")"
echo "  Q3 用户点查（基线）: $(bench_range "$Q3")"
echo "  Q4 交叉分析（基线）: $(bench_range "$Q4")"
echo "  Q5 Join 大区（基线）: $(bench_range "$Q5")"
echo

echo "########## 2. 分区裁剪验证 ##########"
echo "--- 2.1 不带分区谓词 ---"
DQ -e "EXPLAIN SELECT SUM(amount) FROM dwd_orders;" 2>&1 | grep -oE "partitions=[0-9]+/[0-9]+" | head -1
echo "--- 2.2 带分区谓词（单月）---"
DQ -e "EXPLAIN SELECT SUM(amount) FROM dwd_orders WHERE order_date >= '2025-06-01' AND order_date < '2025-07-01';" 2>&1 | grep -oE "partitions=[0-9]+/[0-9]+" | head -1
echo "--- 2.3 ⚠️ 对分区列用函数（退化证明）---"
DQ -e "EXPLAIN SELECT SUM(amount) FROM dwd_orders WHERE DATE_FORMAT(order_date,'%Y-%m') = '2025-06';" 2>&1 | grep -oE "partitions=[0-9]+/[0-9]+" | head -1
echo
echo "  说明：本机只灌了 2025 年 12 个月，故不带谓词是 12/28（空分区被自动跳过）。"
echo

echo "########## 3. Rollup（Unique 表上不可用，改在 Duplicate 表上演示）##########"
echo
echo "--- 3.0 【报错演示】在 Unique MoW 表上加 Rollup ---"
echo "  写法一（只放部分唯一键）:"
DQ -e "ALTER TABLE dwd_orders ADD ROLLUP r_bad1 (order_date, province, amount);" 2>&1 | head -3
echo "  写法二（放全部唯一键）:"
DQ -e "ALTER TABLE dwd_orders ADD ROLLUP r_bad2 (order_date, user_id, order_id, province, amount);" 2>&1 | head -3
echo "  → 两条路都被拒绝，Unique MoW 表基本无法使用 Rollup"
echo

echo "--- 3.1 建 Duplicate 对照表 ---"
DQ -e "DROP TABLE IF EXISTS rollup_test;"
DQ -e "
CREATE TABLE rollup_test (
  order_date DATE NOT NULL, province VARCHAR(16) NOT NULL,
  user_id BIGINT NOT NULL, amount DECIMAL(10,2) NOT NULL
) DUPLICATE KEY(order_date, province)
DISTRIBUTED BY HASH(user_id) BUCKETS 8
PROPERTIES ('replication_num'='1');"
DQ -e "INSERT INTO rollup_test SELECT order_date, province, user_id, amount FROM dwd_orders;"
DQ -e "SELECT COUNT(*) AS rows_cnt, SUM(amount) AS s FROM rollup_test;"
echo

echo "--- 3.2 在 Duplicate 表上加 Rollup (province, amount) ---"
DQ -e "ALTER TABLE rollup_test ADD ROLLUP r_prov (province, amount);" 2>&1
for i in 1 2 3 4 5 6; do
  ST=$(DQ -e "SHOW ALTER TABLE ROLLUP FROM dw ORDER BY JobId DESC LIMIT 1;" 2>&1 | tail -1)
  echo "  第 $i 次: $(echo "$ST" | awk '{print $8}')"
  echo "$ST" | grep -q "FINISHED" && break
  sleep 5
done
echo

echo "--- 3.3 EXPLAIN 确认命中 Rollup（看 TABLE 是不是 r_prov）---"
DQ -e "EXPLAIN SELECT province, SUM(amount) FROM rollup_test GROUP BY province;" 2>&1 \
  | grep -iE "TABLE:|r_prov chose|PREAGGREGATION"
echo

Q1R="SELECT province, SUM(amount) AS s FROM rollup_test GROUP BY province;"
Q1RB="SELECT province, SUM(amount) AS s FROM dwd_orders GROUP BY province;"
echo "  Q1 Unique 表（无 Rollup）:     $(bench_range "$Q1RB")"
echo "  Q1 Duplicate 表（有 Rollup）:  $(bench_range "$Q1R")"
echo "  （注意：两表数据量/列数/分桶不同，此对比不公平，仅记录现象）"
echo

echo "########## 4. 异步物化视图 ##########"
echo
DQ -e "DROP MATERIALIZED VIEW IF EXISTS mv_region_month;" 2>&1
DQ -e "
CREATE MATERIALIZED VIEW mv_region_month
BUILD IMMEDIATE REFRESH AUTO ON MANUAL
PARTITION BY(stat_month)
DISTRIBUTED BY HASH(province) BUCKETS 4
PROPERTIES ('replication_num' = '1')
AS
SELECT
  DATE_TRUNC(d.order_date, 'month') AS stat_month,
  d.province,
  p.region,
  COUNT(*)      AS order_cnt,
  SUM(d.amount) AS total_amount
FROM dwd_orders d
JOIN dim_province p ON d.province = p.province
GROUP BY DATE_TRUNC(d.order_date, 'month'), d.province, p.region;" 2>&1
echo

echo "--- 4.0 【前置校验】维表覆盖性 —— 防止 INNER JOIN 静默丢数据 ---"
MISS=$(DQ -e "SELECT COUNT(*) FROM (SELECT DISTINCT d.province FROM dwd_orders d LEFT JOIN dim_province p ON d.province = p.province WHERE p.province IS NULL) t;" 2>&1 | tail -1)
echo "  DWD 有、维表没有的省份数: $MISS   （必须为 0）"
if [ "$MISS" != "0" ]; then
  echo "  ❌ 维表覆盖不全！MV 用 INNER JOIN 会静默丢数据。请先跑 Task 1 的维表修复。"
else
  echo "  ✅ 维表覆盖完整"
fi
DQ -e "SELECT * FROM dim_province ORDER BY region_code, province;"
echo

echo "--- 4.1 刷新前看透明改写（预期 fail）---"
DQ -e "EXPLAIN SELECT DATE_TRUNC(d.order_date,'month') AS stat_month, d.province, p.region, COUNT(*) AS order_cnt, SUM(d.amount) AS total_amount FROM dwd_orders d JOIN dim_province p ON d.province = p.province GROUP BY DATE_TRUNC(d.order_date,'month'), d.province, p.region;" 2>&1 | grep -A6 "MATERIALIZATIONS"
echo

echo "--- 4.2 诊断：MV 分区有容器但没数据 ---"
DQ -e "SHOW PARTITIONS FROM mv_region_month;" 2>&1 | head -3 | cut -c1-200
echo

echo "--- 4.3 用 REFRESH COMPLETE 全量刷新（AUTO 不够）---"
DQ -e "REFRESH MATERIALIZED VIEW mv_region_month COMPLETE;" 2>&1
sleep 20
DQ -e "SELECT COUNT(*) AS mv_rows, SUM(total_amount) AS mv_sum FROM mv_region_month;"
echo

echo "--- 4.4 刷新后再看透明改写 ---"
DQ -e "EXPLAIN SELECT DATE_TRUNC(d.order_date,'month') AS stat_month, d.province, p.region, COUNT(*) AS order_cnt, SUM(d.amount) AS total_amount FROM dwd_orders d JOIN dim_province p ON d.province = p.province GROUP BY DATE_TRUNC(d.order_date,'month'), d.province, p.region;" 2>&1 | grep -A6 "MATERIALIZATIONS"
echo

echo "--- 4.4.1 【关键对账】MV 金额必须等于 DWD 金额 ---"
DQ -e "SELECT COUNT(*) AS mv_rows, COUNT(DISTINCT province) AS mv_provs FROM mv_region_month;"
DQ -e "
SELECT
  (SELECT SUM(amount) FROM dwd_orders) AS dwd_sum,
  (SELECT SUM(total_amount) FROM mv_region_month) AS mv_sum,
  (SELECT SUM(amount) FROM dwd_orders) - (SELECT SUM(total_amount) FROM mv_region_month) AS diff;"
echo "  ⚠️ diff 必须为 0。若不为 0，说明 INNER JOIN 丢数据（多半是维表覆盖不全）。"
echo "     第一版实测：mv_rows=48（应 96）、diff=12558978081.44（125 亿凭空消失）。"
echo

echo "--- 4.5 直查 MV 的耗时 ---"
QMV="SELECT region, SUM(total_amount) AS s, SUM(order_cnt) AS c FROM mv_region_month GROUP BY region ORDER BY s DESC;"
echo "  直查 MV: $(bench_range "$QMV")"
echo

echo "########## 5. Colocate Join ##########"
echo
DQ -e "ALTER TABLE dim_province SET ('colocate_with' = 'p3_group');" 2>&1
DQ -e "ALTER TABLE dws_prov_month SET ('colocate_with' = 'p3_group');" 2>&1
sleep 5
echo "--- Colocate 组状态（注意 IsStable 可能是 false，需等后台搬迁）---"
Q -e "SHOW PROC '/colocation_group';" 2>&1 | grep -E "p3_group"
echo

echo "--- 5.1 灌 DWS 数据（bitmap 列必须用 bitmap_union 包一层）---"
DQ -e "TRUNCATE TABLE dws_prov_month;" 2>&1
DQ -e "
INSERT INTO dws_prov_month
SELECT DATE_TRUNC(order_date,'month') AS stat_month, province,
       COUNT(*) AS order_cnt,
       bitmap_union(TO_BITMAP(user_id)) AS uv,
       SUM(amount) AS total_amount, MAX(amount) AS max_amount
FROM dwd_orders GROUP BY DATE_TRUNC(order_date,'month'), province;" 2>&1
DQ -e "SELECT COUNT(*) AS dws_rows, SUM(total_amount) AS dws_sum FROM dws_prov_month;"
echo "  （dws_sum 应等于 dwd_sum = 25097795339.16）"
echo

Q5C="SELECT p.region, SUM(s.total_amount) AS s, SUM(s.order_cnt) AS c FROM dws_prov_month s JOIN dim_province p ON s.province = p.province GROUP BY p.region ORDER BY s DESC;"
echo "  Q5 Colocate Join（DWS 层，仅 96 行）: $(bench_range "$Q5C")"
echo "--- EXPLAIN 看 EXCHANGE（shuffle）节点数 ---"
N_EX=$(DQ -e "EXPLAIN $Q5C" 2>&1 | grep -icE "EXCHANGE")
echo "  EXCHANGE 节点数: $N_EX"
echo "  注意：0 个 EXCHANGE 主要是因为维表只有 8 行走了 BROADCAST，不是 Colocate 生效"
echo

echo "########## 6. Profile 抓取 ##########"
echo
Q -e "SET GLOBAL enable_profile = true;" 2>&1
DQ -e "SELECT p.region, COUNT(*) AS c, SUM(d.amount) AS s FROM dwd_orders d JOIN dim_province p ON d.province = p.province GROUP BY p.region ORDER BY s DESC;" > /dev/null 2>&1
sleep 3
QID=$(Q -e "SHOW QUERY PROFILE '/'" 2>&1 | grep -i "dwd_orders" | tail -1 | awk '{print $1}')
echo "  QueryID: $QID"
if [ -n "$QID" ]; then
  PF=$(docker exec -i doris-learn curl -s -u root: "http://127.0.0.1:8030/api/profile?query_id=$QID" 2>&1)
  echo "  --- Summary 关键行 ---"
  echo "$PF" | tr '\\' '\n' | grep -E "^\s+- (Total|Task State|Plan Time|Schedule Time|Wait and Fetch Result Time|Instances Num Per BE)"
  echo "  --- 各算子 ExecTime / ScanRows ---"
  echo "$PF" | tr '\\' '\n' | grep -E "OPERATOR\(|ScanRows:|ScanBytes:|- ExecTime:" | head -24
  echo "  --- RuntimeFilter ---"
  echo "$PF" | tr '\\' '\n' | grep -E "RF[01] (FilterRows|InputRows):" | head -4
fi
echo

echo "########## 7. 优化后测量 ##########"
echo
Q2P="SELECT COUNT(*) AS cnt, SUM(amount) AS gmv FROM dwd_orders WHERE order_date >= '2025-06-01' AND order_date < '2025-07-01';"
echo "  Q1 Unique 表（无 Rollup）:        $(bench_range "$Q1RB")"
echo "  Q1 Duplicate 表（有 Rollup）:     $(bench_range "$Q1R")"
echo "  Q2 全量（12/28 分区）:            $(bench_range "$Q2")"
echo "  Q2 单月（1/28 分区）:             $(bench_range "$Q2P")"
echo "  Q3 用户点查:                      $(bench_range "$Q3")"
echo "  Q4 交叉分析:                      $(bench_range "$Q4")"
echo "  Q5 大区聚合（走 MV）:             $(bench_range "$QMV")"
echo "  Q5 大区聚合（不走 MV）:           $(bench_range "$Q5")"
echo
echo "  ⚠️ 本机 1000 万行规模下，多数优化收益在噪声范围内。"
echo "     本脚本的价值是验证「手段能否跑通 + 坑在哪」，而非跑出加速比。"
echo

echo "=========================================="
echo " Task 3 调优完成"
echo "=========================================="
