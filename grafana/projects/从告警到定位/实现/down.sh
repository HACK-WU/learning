#!/bin/bash
# 一键停止：从告警到定位 实战项目
# 用法：bash down.sh          # 仅停止并删除项目容器（保留镜像与数据）
#       bash down.sh --purge  # 额外删除镜像与运行产物（日志、收到的告警）
set -u

PURGE=0
[ "${1:-}" = "--purge" ] && PURGE=1

echo "=============================================="
echo " 停止「从告警到定位」实战项目"
echo " 模式: $([ "$PURGE" = 1 ] && echo '清理（会删镜像与运行产物）' || echo '常规（保留镜像与数据）')"
echo "=============================================="

for c in p3-grafana p3-prom p3-webhook p3-shop p3-promtail; do
  if docker ps -a --format '{{.Names}}' | grep -qx "$c"; then
    echo "停止并删除容器 $c ..."
    docker rm -f "$c" >/dev/null 2>&1
  else
    echo "容器 $c 不存在，跳过"
  fi
done

if [ "$PURGE" = 1 ]; then
  W="$(cd "$(dirname "$0")/.." && pwd)"
  echo "删除镜像 p3-shop:1.1 ..."
  docker rmi -f p3-shop:1.1 >/dev/null 2>&1 || echo "  镜像不存在或无引用，跳过"
  echo "清理运行产物 ..."
  rm -rf "$W/实现/app/logs" "$W/实现/webhook/out" 2>/dev/null
  echo "  已清理 实现/app/logs 与 实现/webhook/out"
fi

echo
echo "剩余项目容器："
docker ps -a --format 'table {{.Names}}\t{{.Status}}' | grep -E '^p3-|NAMES' || echo "  （无）"

echo
echo "=============================================="
echo " 已停止"
echo " 注意：Loki / Jaeger 是课程公共基础设施，本脚本不会动它们。"
echo " 重新拉起：bash up.sh  （加参数 1 可开启故障注入）"
echo "=============================================="
