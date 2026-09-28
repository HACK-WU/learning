#!/usr/bin/env bash
# 用途：探查蓝鲸7.2部署包的 helmfile 入口与渲染方式
set -uo pipefail
B=/root/bk72/install/blueking
E=$B/environments/default

echo "===== 1. 顶层结构 ====="
ls -1 "$B" | head -30

echo ""
echo "===== 2. helmfile 入口文件 ====="
find "$B" -maxdepth 3 -name 'helmfile*.yaml*' -o -maxdepth 3 -name 'helmfile*.gotmpl' 2>/dev/null | head -15

echo ""
echo "===== 3. environments/default 内容 ====="
ls -1 "$E" | head -30

echo ""
echo "===== 4. environments 下有哪些环境 ====="
ls -1 "$B/environments" | head

echo ""
echo "===== 5. values 模板清单（数量与名称）====="
ls -1 "$E"/*.gotmpl 2>/dev/null | wc -l
ls -1 "$E"/*.gotmpl 2>/dev/null | xargs -n1 basename | head -40

echo ""
echo "===== 6. 是否已有渲染好的 values.yaml ====="
ls -1 "$E"/*.yaml 2>/dev/null | xargs -n1 basename | head -20

echo ""
echo "===== 7. charts 目录是否存在 ====="
ls -1 "$B/charts" 2>/dev/null | head -20
echo "charts 数量: $(ls -1 "$B/charts" 2>/dev/null | wc -l)"
