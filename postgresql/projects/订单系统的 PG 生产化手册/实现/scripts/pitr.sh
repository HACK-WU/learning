#!/usr/bin/env bash
# 在主库容器内部做一次隔离 PITR：误删表后恢复到命名恢复点。
# 恢复实例只监听容器内 15433，不改主库对外端口。
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

compose exec -T -e "PGPASSWORD=$POSTGRES_PASSWORD" primary sh -s <<'CONTAINER'
set -Eeuo pipefail
BASE=/tmp/pg-capstone-pitr-base
RESTORE=/tmp/pg-capstone-pitr-restore
LOG=/tmp/pg-capstone-pitr-restore.log

cleanup() {
  su postgres -c "pg_ctl -D '$RESTORE' -m fast stop" >/dev/null 2>&1 || true
  rm -rf "$BASE" "$RESTORE" "$LOG"
}
trap cleanup EXIT

echo '=== PITR-1: 准备事故标本 ==='
psql -h 127.0.0.1 -U postgres -d order_service <<'SQL'
DROP TABLE IF EXISTS orders.pitr_demo;
CREATE TABLE orders.pitr_demo (
  id integer PRIMARY KEY,
  note text NOT NULL
);
INSERT INTO orders.pitr_demo VALUES (1, '基础备份前');
SQL

rm -rf "$BASE" "$RESTORE"
mkdir -p "$BASE"
pg_basebackup -h 127.0.0.1 -U postgres -D "$BASE" -Fp -X stream -c fast

psql -h 127.0.0.1 -U postgres -d order_service <<'SQL'
INSERT INTO orders.pitr_demo VALUES (2, '恢复点前-A'), (3, '恢复点前-B');
SELECT pg_create_restore_point('before_capstone_incident');
INSERT INTO orders.pitr_demo VALUES (4, '事故后-不应回来');
DROP TABLE orders.pitr_demo;
SELECT pg_switch_wal();
SQL
sleep 3

echo '=== PITR-2: 从基础备份启动隔离恢复实例 ==='
cp -a "$BASE" "$RESTORE"
cat >> "$RESTORE/postgresql.auto.conf" <<'EOF'
restore_command = 'cp /var/lib/postgresql/data/pg_wal_archive/%f %p'
recovery_target_name = 'before_capstone_incident'
recovery_target_action = 'promote'
archive_mode = off
EOF
touch "$RESTORE/recovery.signal"
chown -R postgres:postgres "$RESTORE"
chmod 700 "$RESTORE"
if ! su postgres -c "pg_ctl -D '$RESTORE' -l '$LOG' -o \"-p 15433 -c listen_addresses=127.0.0.1\" -w -t 90 start"; then
  echo '--- isolated recovery log ---' >&2
  cat "$LOG" >&2 || true
  exit 1
fi

restored_count="$(psql -h 127.0.0.1 -p 15433 -U postgres -d order_service -Atqc 'SELECT count(*) FROM orders.pitr_demo;')"
restored_after="$(psql -h 127.0.0.1 -p 15433 -U postgres -d order_service -Atqc 'SELECT count(*) FROM orders.pitr_demo WHERE id = 4;')"
[ "$restored_count" = '3' ]
[ "$restored_after" = '0' ]
echo "restored_count=$restored_count row_4_count=$restored_after"
grep -aE 'recovery stopping|selected new timeline|archive recovery complete' "$LOG" || true
echo '=== PITR CHECK PASSED ==='
CONTAINER
