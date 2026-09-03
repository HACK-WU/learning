#!/usr/bin/env bash
# 查看 vm-learn 容器的启动参数与挂载
set -u
echo "===== 容器启动参数 ====="
docker inspect vm-learn --format '{{json .Args}}' 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "(解析失败)"
echo
echo "===== 挂载 ====="
docker inspect vm-learn --format '{{json .Mounts}}' 2>/dev/null | python3 -c '
import sys,json
for m in json.load(sys.stdin):
    print("  ", m.get("Source"), "->", m.get("Destination"))
' 2>/dev/null || echo "(解析失败)"
echo
echo "===== 环境变量 ====="
docker inspect vm-learn --format '{{json .Config.Env}}' 2>/dev/null | python3 -m json.tool 2>/dev/null
echo
echo "===== 命令行 ====="
docker inspect vm-learn --format '{{json .Config.Cmd}}' 2>/dev/null
echo
echo "===== 数据目录（宿主机）====="
ls -la /mnt/d/projects/learning/victoriametrics/ 2>/dev/null | head -20
