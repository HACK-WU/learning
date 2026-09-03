#!/usr/bin/env bash
# 排查 VM 容器启动失败
set -u
echo "===== 1. 容器状态 ====="
docker ps -a --filter name=vm-learn --format '  {{.Names}} | {{.Status}}'
echo
echo "===== 2. 容器日志（最后 40 行）====="
docker logs --tail 40 vm-learn 2>&1 | sed 's/^/  /'
echo
echo "===== 3. 端口 ====="
for p in 8428 2003 4242; do
  if (echo > /dev/tcp/127.0.0.1/$p) 2>/dev/null; then echo "  $p: 已监听"
  else echo "  $p: 未监听"; fi
done
echo
echo "===== 4. 数据卷内容 ====="
ls -la /mnt/d/projects/learning/victoriametrics/playground/data/ 2>&1 | head -10
