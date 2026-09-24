#!/bin/bash
echo "=== l11 镜像 ==="
docker inspect l11 --format '{{.Config.Image}}'
echo "=== l11 挂载 ==="
docker inspect l11 --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{println}}{{end}}'
echo "=== 当前 capstone 进程 ==="
docker exec l11 sh -c 'for p in $(ls /proc | grep -E "^[0-9]+$"); do
  [ -r /proc/$p/cmdline ] || continue
  c=$(tr "\0" " " < /proc/$p/cmdline 2>/dev/null)
  case "$c" in *"uvicorn app.main:app"*) echo "  $p :: $c";; esac
done'
