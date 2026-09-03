#!/usr/bin/env bash
# 课 12：启动横向对比用的独立容器（不碰用户现有的 xpert-db-1）
# 固定名字 + 独立端口 + 独立 volume，交付后由 l12-cleanup.sh 清理
set -u

start() {
  local name="$1"; local image="$2"; shift 2
  if docker ps -a --format '{{.Names}}' | grep -qx "$name"; then
    echo "[$name] already exists -> starting"
    docker start "$name" >/dev/null 2>&1
  else
    echo "[$name] creating from $image"
    docker run -d --name "$name" "$@" "$image" >/dev/null
  fi
}

start l12-pg pgvector/pgvector:pg16 \
  -e POSTGRES_PASSWORD=l12pass -e POSTGRES_USER=l12 -e POSTGRES_DB=l12 \
  -v l12pgdata:/var/lib/postgresql/data -p 5433:5432

start l12-mongo mongo:7 \
  -e MONGO_INITDB_ROOT_USERNAME=l12 -e MONGO_INITDB_ROOT_PASSWORD=l12pass \
  -v l12mongodata:/data/db -p 27018:27017

start l12-neo4j neo4j:5 \
  -e NEO4J_AUTH=neo4j/l12pass123 \
  -v l12neo4jdata:/data -p 7688:7687 -p 7475:7474

echo
echo "=== 容器状态 ==="
docker ps -a --format '{{.Names}} | {{.Image}} | {{.Status}} | {{.Ports}}' | grep l12-
