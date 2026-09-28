#!/usr/bin/env bash
D=/root/bk72/install/blueking/environments/default
echo "===== 1. ingress-nginx-values.yaml.gotmpl 全文 ====="
cat -n "$D/ingress-nginx-values.yaml.gotmpl" 2>&1

echo ""
echo "===== 2. bkingress-nginx-values.yaml.gotmpl 全文 ====="
cat -n "$D/bkingress-nginx-values.yaml.gotmpl" 2>&1

echo ""
echo "===== 3. values.yaml 里 ingress 相关 ====="
grep -nE 'ingress|snippet' "$D/values.yaml" 2>/dev/null | sed 's/^/  /'

echo ""
echo "===== 4. base-blueking 里 ingress-nginx release 定义 ====="
grep -n -A14 'name: ingress-nginx' /root/bk72/install/blueking/base-blueking.yaml.gotmpl 2>/dev/null | sed 's/^/  /'
