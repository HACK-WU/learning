#!/usr/bin/env bash
echo "=== 容器 ==="
docker ps -a --format '{{.Names}}|{{.Status}}|{{.Ports}}'
echo "=== 镜像 ==="
docker images --format '{{.Repository}}:{{.Tag}}|{{.Size}}'
