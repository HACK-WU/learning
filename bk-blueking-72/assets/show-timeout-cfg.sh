#!/usr/bin/env bash
B=/root/bk72/install/blueking
echo "===== defaults.yaml 前 30 行 ====="
cat -n "$B/defaults.yaml" | head -30
echo ""
echo "===== base-blueking.yaml.gotmpl 125-160 行 ====="
cat -n "$B/base-blueking.yaml.gotmpl" | sed -n '125,160p'
