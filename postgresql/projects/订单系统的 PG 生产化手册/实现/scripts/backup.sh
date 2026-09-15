#!/usr/bin/env bash
# 同时落三份资产：custom 逻辑备份、全局角色备份、物理基础备份。
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_dir="$PROJECT_DIR/runtime/backups/$stamp"
mkdir -p "$backup_dir"

primary_psql postgres -Atqc 'CHECKPOINT;' >/dev/null

echo "[1/3] pg_dump custom"
compose exec -T -e "PGPASSWORD=$POSTGRES_PASSWORD" primary \
  pg_dump -h 127.0.0.1 -U postgres -d "$POSTGRES_DB" -Fc \
  >"$backup_dir/order_service.dump"

echo "[2/3] pg_dumpall globals-only"
compose exec -T -e "PGPASSWORD=$POSTGRES_PASSWORD" primary \
  pg_dumpall -h 127.0.0.1 -U postgres --globals-only \
  >"$backup_dir/globals.sql"

echo "[3/3] pg_basebackup physical tar"
compose exec -T -e "PGPASSWORD=$POSTGRES_PASSWORD" primary sh -s >"$backup_dir/base.tar.gz" <<'CONTAINER'
set -eu
rm -rf /tmp/pg-capstone-base
mkdir -p /tmp/pg-capstone-base
pg_basebackup -h 127.0.0.1 -U postgres -D /tmp/pg-capstone-base -Fp -X stream -c fast
tar -C /tmp/pg-capstone-base -czf - .
rm -rf /tmp/pg-capstone-base
CONTAINER

echo "backup_dir=$backup_dir"
du -h "$backup_dir"/*
echo "=== BACKUP CREATED ==="
