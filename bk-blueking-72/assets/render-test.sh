#!/usr/bin/env bash
# 用途：纯渲染验证——只渲染 values 模板，不下发集群、不耗资源
# 目标：确认 41 个 .gotmpl（含证书引用）能否全部正确渲染
set -uo pipefail
B=/root/bk72/install/blueking
E=$B/environments/default
HF=/root/bk72/tools/bin/helmfile
OUT=/root/bk72/render_test
rm -rf "$OUT"; mkdir -p "$OUT"

echo "===== 0. helmfile 版本 ====="
"$HF" version 2>&1 | head -2

echo ""
echo "===== 1. 检查 template 子命令可用性 ====="
"$HF" template --help 2>&1 | head -12

echo ""
echo "===== 2. 查看 base.yaml.gotmpl 头部（理解组织方式）====="
head -40 "$B/base.yaml.gotmpl"

echo ""
echo "===== 3. 查看 defaults.yaml / values.yaml 关键变量 ====="
echo "--- values.yaml ---"
head -30 "$E/values.yaml"
