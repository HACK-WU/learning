#!/usr/bin/env bash
set -uo pipefail
{
echo "===== 1. nodeman 的真实域名（从 helmfile/values 查）====="
grep -iE 'nodeman|domain' /root/bk72/install/blueking/environments/default/bknodeman-values.yaml.gotmpl 2>/dev/null | head -20 | sed 's/^/  /'

echo ""
echo "===== 2. address.yaml.gotmpl 里的域名定义 ====="
grep -iE 'nodeman|job|domain' /root/bk72/install/blueking/address.yaml.gotmpl 2>/dev/null | head -25 | sed 's/^/  /'

echo ""
echo "===== 3. 全局 domain 配置 ====="
grep -A15 'domain:' /root/bk72/install/blueking/environments/default/values.yaml 2>/dev/null | head -20 | sed 's/^/  /'

echo ""
echo "===== 4. base-blueking.yaml.gotmpl 里 nodeman 段的完整内容 ====="
sed -n '200,225p' /root/bk72/install/blueking/base-blueking.yaml.gotmpl 2>/dev/null | sed 's/^/  /'

echo ""
echo "===== 5. 参照已知组件的域名规律（ingress host 格式）====="
kubectl get ingress -n blueking --no-headers 2>/dev/null | awk '{print $3}' | head -8 | sed 's/^/  /'
} > /root/nodeman-domain.txt 2>&1
cat /root/nodeman-domain.txt
