#!/usr/bin/env bash
# 用 psql 变量把本地演示凭据注入初始化 SQL；仓库只保存变量名与演示默认值。
set -eu

psql -v ON_ERROR_STOP=1 \
  --username "$POSTGRES_USER" \
  --dbname "$POSTGRES_DB" \
  --set=replication_password="$REPLICATION_PASSWORD" \
  --set=app_password="$APP_PASSWORD" \
  --set=report_password="$REPORT_PASSWORD" \
  --set=tenant_password="$TENANT_PASSWORD" \
  --file=/docker-entrypoint-initdb.d/templates/01-roles.sql
