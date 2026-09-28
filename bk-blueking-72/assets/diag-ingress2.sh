#!/usr/bin/env bash
set -uo pipefail
NS=ingress-nginx
CM=ingress-nginx-controller

echo "===== 1. configmap 全文 ====="
kubectl get cm $CM -n $NS -o yaml 2>&1

echo ""
echo "===== 2. 是否有 allow-snippet-annotations ====="
kubectl get cm $CM -n $NS -o jsonpath='{.data.allow-snippet-annotations}' 2>/dev/null | sed 's/^/  值: /'
echo ""

echo ""
echo "===== 3. 检查 rc 文件里是否已有部署配置（避免改了被覆盖）====="
grep -rlnE 'ingress-nginx|server-snippet' /root/bk72/install/blueking/environments/default/ 2>/dev/null | sed 's/^/  /' || echo "  (未在 environments 找到)"

echo ""
echo "===== 4. bk-iam chart 里 server-snippet 在哪个文件 ====="
find /root/.cache/helm/repository /root/bk72 -name '*.tgz' 2>/dev/null | grep -iE 'bkiam|bkssm|console' | sed 's/^/  /'

echo ""
echo "===== 5. 渲染 bk-iam 看 ingress 注解 ====="
export PATH=/root/bk72/install/bin:$PATH
cd /root/bk72/install/blueking && /root/bk72/install/bin/helmfile -f base-blueking.yaml.gotmpl -l name=bk-iam template 2>/dev/null \
  | grep -B3 -A8 'server-snippet' | sed 's/^/  /' || echo "  (渲染中未见 server-snippet)"
