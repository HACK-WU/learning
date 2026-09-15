#!/usr/bin/env bash
# 把 custom 逻辑备份恢复到临时数据库，不触碰生产库。
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

dump_path="${1:-}"
if [[ -z "$dump_path" ]]; then
  dump_path="$(find "$PROJECT_DIR/runtime/backups" -type f -name 'order_service.dump' -print | sort | tail -1)"
fi
[[ -f "$dump_path" ]] || { echo "找不到 custom dump：$dump_path" >&2; exit 1; }

echo "restore_source=$dump_path"
compose exec -T -e "PGPASSWORD=$POSTGRES_PASSWORD" primary \
  dropdb -h 127.0.0.1 -U postgres --if-exists order_service_restore
compose exec -T -e "PGPASSWORD=$POSTGRES_PASSWORD" primary \
  createdb -h 127.0.0.1 -U postgres order_service_restore
compose exec -T primary sh -c 'cat > /tmp/order_service.dump' <"$dump_path"
compose exec -T -e "PGPASSWORD=$POSTGRES_PASSWORD" primary \
  pg_restore -h 127.0.0.1 -U postgres -d order_service_restore \
  --no-owner --exit-on-error /tmp/order_service.dump
restored_rows="$(compose exec -T -e "PGPASSWORD=$POSTGRES_PASSWORD" primary \
  psql -X -Atqc 'SELECT count(*) FROM orders.orders;' -h 127.0.0.1 -U postgres -d order_service_restore)"
echo "restored_order_rows=$restored_rows"
compose exec -T -e "PGPASSWORD=$POSTGRES_PASSWORD" primary \
  dropdb -h 127.0.0.1 -U postgres order_service_restore
echo "=== LOGICAL RESTORE CHECK PASSED ==="
