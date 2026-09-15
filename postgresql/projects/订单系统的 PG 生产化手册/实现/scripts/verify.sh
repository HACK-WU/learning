#!/usr/bin/env bash
# 一次性冒烟验收：数据完整性、复制、幂等函数、RLS 与观察面。
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

counts_file="$(mktemp)"
trap 'rm -f "$counts_file"' EXIT

compose ps
wait_for_service primary 30
wait_for_service standby 30

echo "=== 1. 版本与复制角色 ==="
primary_psql postgres -Atqc "SELECT version();"
[[ "$(standby_psql postgres -Atqc 'SELECT pg_is_in_recovery();')" == "t" ]]
replica_count="$(primary_psql postgres -Atqc "SELECT count(*) FROM pg_stat_replication WHERE application_name = 'pg-capstone-standby';")"
(( replica_count >= 1 ))
echo "replica_count=$replica_count"

echo "=== 2. 订单数据完整性 ==="
primary_psql postgres -Atqc "
  SELECT count(*) FROM orders.orders;
  SELECT count(*) FROM orders.order_items;
  SELECT count(*) FROM orders.order_events;
  SELECT count(*) FROM orders.orders o
  WHERE o.total_amount <> (
    SELECT sum(oi.quantity * oi.unit_price)
    FROM orders.order_items oi WHERE oi.order_id = o.order_id
  );
" | tee "$counts_file"
[[ "$(tail -1 "$counts_file")" == "0" ]]

echo "=== 3. 幂等下单函数 ==="
first_order="$(primary_psql app_runtime -Atqc "SELECT orders.place_order('00000000-0000-0000-0000-00000000000a', 1, 101, 1, 'verify-idempotent');")"
second_order="$(primary_psql app_runtime -Atqc "SELECT orders.place_order('00000000-0000-0000-0000-00000000000a', 1, 101, 1, 'verify-idempotent');")"
[[ "$first_order" == "$second_order" ]]
echo "same_order_id=$first_order"

echo "=== 4. RLS 租户隔离 ==="
tenant_a_rows="$(primary_psql tenant_a_app -Atqc "SELECT count(*) FROM orders.orders;")"
tenant_b_rows="$(primary_psql tenant_b_app -Atqc "SELECT count(*) FROM orders.orders;")"
all_rows="$(primary_psql postgres -Atqc "SELECT count(*) FROM orders.orders;")"
(( tenant_a_rows > 0 && tenant_b_rows > 0 && tenant_a_rows < all_rows && tenant_b_rows < all_rows ))
echo "tenant_a_rows=$tenant_a_rows tenant_b_rows=$tenant_b_rows all_rows=$all_rows"

echo "=== 5. 从库数据最终一致 ==="
primary_rows="$(primary_psql postgres -Atqc "SELECT count(*) FROM orders.orders;")"
standby_rows="$(standby_psql postgres -Atqc "SELECT count(*) FROM orders.orders;")"
[[ "$primary_rows" == "$standby_rows" ]]
echo "primary_rows=$primary_rows standby_rows=$standby_rows"

echo "=== ALL SMOKE CHECKS PASSED ==="
