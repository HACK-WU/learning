#!/usr/bin/env bash
# 启动主库，再让从库用 pg_basebackup -R 从主库自动初始化。
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

compose up -d primary
wait_for_service primary 120
compose up -d standby
wait_for_service standby 180

echo "=== PG 生产化项目已就绪 ==="
compose ps
primary_psql postgres -Atqc "SELECT 'primary=' || split_part(version(), ' on ', 1);"
standby_psql postgres -Atqc "SELECT 'standby_recovery=' || pg_is_in_recovery();"
