#!/usr/bin/env bash
# 所有脚本共用的 Compose / psql 包装器。
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"
PROJECT_NAME="${COMPOSE_PROJECT_NAME:-pg-capstone}"
POSTGRES_DB="${POSTGRES_DB:-order_service}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-pg_demo_only}"
REPLICATION_PASSWORD="${REPLICATION_PASSWORD:-replica_demo_only}"
APP_PASSWORD="${APP_PASSWORD:-app_demo_only}"
REPORT_PASSWORD="${REPORT_PASSWORD:-report_demo_only}"
TENANT_PASSWORD="${TENANT_PASSWORD:-tenant_demo_only}"

if [[ -f "$PROJECT_DIR/.env" ]]; then
  set -a
  # .env 是用户本地配置；仓库只提交 .env.example。
  # shellcheck disable=SC1091
  source "$PROJECT_DIR/.env"
  set +a
fi

compose() {
  docker compose --project-name "$PROJECT_NAME" --file "$COMPOSE_FILE" "$@"
}

password_for() {
  case "$1" in
    postgres) printf '%s' "$POSTGRES_PASSWORD" ;;
    replicator) printf '%s' "$REPLICATION_PASSWORD" ;;
    app_runtime) printf '%s' "$APP_PASSWORD" ;;
    report_reader) printf '%s' "$REPORT_PASSWORD" ;;
    tenant_a_app|tenant_b_app) printf '%s' "$TENANT_PASSWORD" ;;
    *) printf '%s' "$POSTGRES_PASSWORD" ;;
  esac
}

primary_psql() {
  local user="$1"
  shift
  compose exec -T \
    -e "PGPASSWORD=$(password_for "$user")" \
    primary psql -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -U "$user" -d "$POSTGRES_DB" "$@"
}

standby_psql() {
  local user="$1"
  shift
  compose exec -T \
    -e "PGPASSWORD=$(password_for "$user")" \
    standby psql -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -U "$user" -d "$POSTGRES_DB" "$@"
}

wait_for_service() {
  local service="$1"
  local deadline=$((SECONDS + ${2:-120}))
  until compose exec -T "$service" pg_isready -U postgres -d "$POSTGRES_DB" >/dev/null 2>&1; do
    if (( SECONDS >= deadline )); then
      echo "等待 $service 就绪超时" >&2
      compose logs --tail=40 "$service" >&2 || true
      return 1
    fi
    sleep 2
  done
}
