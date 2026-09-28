#!/usr/bin/env bash
# 用途：从渲染结果解析「真实」镜像名（不靠猜），为可达性测试提供准确目标
set -uo pipefail
B=/root/bk72/install/blueking
E=$B/environments/default
BIN=/root/bk72/tools/bin
HF=$BIN/helmfile
export PATH="$BIN:$PATH"

echo "===== 1. 从已渲染的 GSE values 里看镜像结构 ====="
grep -nE 'repository:|tag:|imageRegistry|image:' /root/bk72/render_test/p6.log 2>/dev/null | head -20

echo ""
echo "===== 2. 解析所有 values 模板里的 repository（真实镜像路径）====="
grep -hoE 'repository:[[:space:]]*"?[^"[:space:]]+"?' "$E"/*-values.yaml.gotmpl 2>/dev/null \
  | sed 's/repository:[[:space:]]*//; s/"//g' | sort -u | head -25

echo ""
echo "===== 3. 看 chart-images 清单（官方镜像总表）====="
ls -la /root/bk72/chart-images* /root/.cache/bkdl/ce7/*/chart-images* 2>/dev/null | head -5
find /root/bk72 /root/.cache/bkdl -iname '*chart-images*' 2>/dev/null | head -5
