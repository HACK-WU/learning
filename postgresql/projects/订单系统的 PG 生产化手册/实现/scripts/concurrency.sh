#!/usr/bin/env bash
# 两个会话同时抢最后一件商品：原子 UPDATE 只允许一个会话成功。
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

PRODUCT_ID=101
primary_psql postgres -Atqc "UPDATE orders.products SET stock = 1 WHERE product_id = $PRODUCT_ID;"

session_a="$(mktemp)"
session_b="$(mktemp)"
trap 'rm -f "$session_a" "$session_b"' EXIT

compose exec -T \
  -e "PGPASSWORD=$POSTGRES_PASSWORD" \
  primary psql -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -U postgres -d "$POSTGRES_DB" \
  >"$session_a" <<SQL &
BEGIN;
SELECT 'A reserve=' || orders.reserve_stock($PRODUCT_ID, 1);
SELECT pg_sleep(2);
COMMIT;
SQL
pid_a=$!
sleep 0.3

compose exec -T \
  -e "PGPASSWORD=$POSTGRES_PASSWORD" \
  primary psql -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -U postgres -d "$POSTGRES_DB" \
  >"$session_b" <<SQL &
BEGIN;
SELECT 'B reserve=' || orders.reserve_stock($PRODUCT_ID, 1);
COMMIT;
SQL
pid_b=$!

wait "$pid_a"
wait "$pid_b"

cat "$session_a" "$session_b"
final_stock="$(primary_psql postgres -Atqc "SELECT stock FROM orders.products WHERE product_id = $PRODUCT_ID;")"
[[ "$final_stock" == "0" ]]
echo "final_stock=$final_stock"
echo "=== CONCURRENCY CHECK PASSED: one success, one no-op ==="
