#!/bin/bash
# 课 7 实验表：200 万行，含 3 个 500 字节填充列
# 用法：bash /tmp/lesson07-setup.sh

# ⚠️ 必须带 -i：docker exec 默认不转发 stdin，
#    不加 -i 时 `echo "$1" | docker exec ... mysql` 会静默无输出，
#    建表/造数全部失败却不报错，后续步骤全对不上。
MYSQL="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"

runq() {
  echo "$1" | $MYSQL 2>&1 | grep -vE "^Warning|Using a password"
}

echo "=== 1. 建表（若已存在会先删掉，保证每次跑都是干净的 200 万行）==="
runq "DROP TABLE IF EXISTS perf_wide;"
runq "CREATE TABLE perf_wide (
  id BIGINT NOT NULL,
  province VARCHAR(32) NOT NULL,
  city VARCHAR(32) NOT NULL,
  amount DECIMAL(10,2) NOT NULL,
  pad1 VARCHAR(500) NOT NULL DEFAULT '',
  pad2 VARCHAR(500) NOT NULL DEFAULT '',
  pad3 VARCHAR(500) NOT NULL DEFAULT '',
  dt DATE NOT NULL
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 8
PROPERTIES ('replication_num' = '1');"

echo ""
echo "=== 2. 确认表建成了 ==="
runq "SHOW CREATE TABLE perf_wide\G" | grep -E "CREATE TABLE|DISTRIBUTED|BUCKETS"

echo ""
echo "=== 3. 造 200 万行数据（约需 30-60 秒）==="
runq "INSERT INTO perf_wide
SELECT
  n,
  CONCAT('prov_', CAST(n % 8 AS VARCHAR)),
  CONCAT('city_', CAST(n % 200 AS VARCHAR)),
  CAST((n % 5000) + 10 AS DECIMAL(10,2)),
  REPEAT('x', 500),
  REPEAT('y', 500),
  REPEAT('z', 500),
  DATE_ADD('2024-01-01', INTERVAL (n % 365) DAY)
FROM (
  SELECT ROW_NUMBER() OVER () AS n FROM orders LIMIT 2000000
) t;"

echo ""
echo "=== 4. 验证数据 ==="
runq "SELECT COUNT(*) AS rows_loaded,
       COUNT(DISTINCT province) AS prov_cnt,
       ROUND(SUM(LENGTH(pad1)+LENGTH(pad2)+LENGTH(pad3))/1024/1024,1) AS pad_mb
FROM perf_wide;"

echo ""
echo "=== 5. 看磁盘占用（列存压缩的证据）==="
# ⚠️ SHOW DATA 依赖后台统计，紧跟 INSERT 执行会返回 0（不是没数据，是统计还没刷新）。
#    实测需等待约 45 秒。这里等 60 秒留余量。
echo "    （等待 60 秒让统计信息刷新，否则会看到 0.000）"
sleep 60
runq "SHOW DATA FROM perf_wide;"

echo "SETUP_DONE"
