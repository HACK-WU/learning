#!/usr/bin/env bash
B=/tmp/bklite-src/bootstrap.sh

echo "=== 1. FUSION_COLLECTOR 在 bootstrap 中的全部用途 ==="
grep -n 'FUSION_COLLECTOR' $B | head -10

echo ""
echo "=== 2. generate_collector_packages 函数 (是否必需) ==="
awk '/^generate_collector_packages\(\)/,/^}/' $B | head -25

echo ""
echo "=== 3. 是否可跳过 collector 相关 ==="
grep -nE 'SKIP_COLLECTOR|skip.*collector|collector.*skip' $B | head -5 || echo "(无跳过开关)"

echo ""
echo "=== 4. monitor.yaml 中该服务的定义 ==="
sed -n '50,75p' /tmp/bklite-src/compose/monitor.yaml
