#!/usr/bin/env bash
# 初始化阶段准备 WAL 归档目录，并显式放行复制连接。
set -eu

mkdir -p "$PGDATA/pg_wal_archive"

cat >> "$PGDATA/pg_hba.conf" <<'EOF'
host replication replicator all scram-sha-256
host all all all scram-sha-256
EOF
