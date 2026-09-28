#!/usr/bin/env bash
# 串行重试拉取缺失镜像，直接看真实错误输出
set -uo pipefail
IMG=hub.bktencent.com/blueking/bkssm:v1.0.12
N=k8s-c1-calico-worker

echo "===== 在 $N 上试拉 $IMG（看真实报错）====="
docker exec $N ctr -n k8s.io images pull "$IMG" 2>&1 | tail -20
echo ""
echo "退出码: ${PIPESTATUS[0]}"
