#!/usr/bin/env bash
set -u
export GOPROXY=https://goproxy.cn,direct
export GOSUMDB=sum.golang.org
export GOTOOLCHAIN=go1.26.8
export CGO_ENABLED=0
cd /mnt/d/projects/learning/k8s/assets/aggregator

echo "===== 1. 清理 module 依赖（改为纯标准库，不需要 k8s 库）====="
cat > go.mod <<'EOF'
module k8s-learning/aggregator

go 1.22
EOF
rm -f go.sum

echo "===== 2. 编译（纯标准库，应为秒级）====="
go vet ./... 2>&1 | tail -5
echo "  go vet exit=$?"
time go build -o /tmp/aggregator-apiserver . 2>&1 | tail -10
echo "  build exit=$?"

echo
echo "===== 3. 产物 ====="
ls -lh /tmp/aggregator-apiserver 2>&1
file /tmp/aggregator-apiserver 2>&1 | head -1
