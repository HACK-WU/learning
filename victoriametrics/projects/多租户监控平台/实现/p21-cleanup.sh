#!/usr/bin/env bash
# 清理脚本：把项目恢复到「未启动」的干净状态
#
# 用法：
#   bash p21-cleanup.sh              # 停容器 + 清数据 + 清临时脚本（默认）
#   bash p21-cleanup.sh --keep-data  # 只停容器，保留 data（想留着查上次数据时用）
#
# ⚠ 为什么必须停容器：p01-up.sh 占用固定的 8500-8507 端口。
#   上一轮容器还在跑时再执行 p01-up.sh 会直接报 port is already allocated，
#   读者按 README 第一步就会失败。所以交付/重跑前必须先清干净。
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

KEEP_DATA=0
[ "${1:-}" = "--keep-data" ] && KEEP_DATA=1

PROJ="$(cd .. && pwd)"

echo "=== 1/3 停止并删除项目容器 ==="
# ⚠ 括号里必须同时列出旧名 capstone-vmalert（拆分双实例前的名字）。
#   漏掉它，旧容器会继续占着 8505 端口不释放，新容器起不来。
CONTAINERS="capstone-exporter-a capstone-exporter-b \
capstone-vmagent-a capstone-vmagent-b \
capstone-vminsert capstone-vmselect \
capstone-vmstorage-1 capstone-vmstorage-2 \
capstone-vmauth capstone-alertmanager \
capstone-vmalert-a capstone-vmalert-b capstone-vmalert \
capstone-ab-drop capstone-ab-nodrop"

FOUND=0
for c in $CONTAINERS; do
  if docker ps -a --format '{{.Names}}' | grep -qx "$c"; then
    docker rm -f "$c" >/dev/null 2>&1 && echo "  ✗ 已删除 $c"
    FOUND=1
  fi
done
[ "$FOUND" = "0" ] && echo "  （无项目容器，已是干净状态）"

echo
echo "=== 2/3 清理数据目录 ==="
if [ "$KEEP_DATA" = "1" ]; then
  echo "  --keep-data：保留 $PROJ/data"
else
  # ⚠ 数据在 bind mount 的宿主机目录里，不在 docker volume 里。
  #   用 `docker run --rm -v 卷名:/d alpine rm -rf /d/*` 清不掉（卷里根本没东西），
  #   reset 会形同无效、旧数据持续污染后续实验。必须直接删宿主机目录。
  if [ -d "$PROJ/data" ]; then
    rm -rf "$PROJ/data"
    echo "  ✗ 已删除 $PROJ/data"
  else
    echo "  （无 data 目录）"
  fi
fi

echo
echo "=== 3/3 保留主干脚本，删除一次性诊断脚本 ==="
KEEP="p00-render.sh p01-up.sh p02-verify.sh p10-final-ab.sh p14-failover.sh p20-check-delivery.sh p21-cleanup.sh"
for f in p03-diag.sh p04-diag2.sh p05-diag3.sh p06-diag4.sh p07-diag5.sh \
         p08-ab-test.sh p09-isolate.sh p11-wait-alerts.sh p12-diag-alerts.sh \
         p13-diag-rules.sh p15-diag-failover.sh p16-diag-absent.sh \
         p17-diag-stall.sh p18-watch-firing.sh p22-verify-cleanup.sh; do
  [ -f "$f" ] && { rm -f "$f"; echo "  ✗ $f"; }
done

echo
echo "保留："
for f in $KEEP; do [ -f "$f" ] && echo "  ✓ $f"; done

echo
echo "=== 校验：8500-8507 应全部空闲 ==="
BUSY=0
for p in 8500 8501 8502 8503 8504 8505 8506 8507; do
  r=$(docker ps --format '{{.Names}}' --filter "publish=$p" 2>/dev/null)
  if [ -z "$r" ]; then echo "  ✓ $p 空闲"; else echo "  ✗ $p 仍被占用: $r"; BUSY=1; fi
done

echo
if [ "$BUSY" = "0" ]; then
  echo "✅ 清理完成，现在可以直接：bash p00-render.sh && bash p01-up.sh --reset"
else
  echo "⚠ 仍有端口被占用，用 docker ps --filter publish=<端口> 查是谁"
fi
