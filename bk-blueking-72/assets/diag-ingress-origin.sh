#!/usr/bin/env bash
set -uo pipefail
export PATH=/root/bk72/install/bin:$PATH

echo "===== 1. ingress-nginx release 定义在哪个 helmfile ====="
grep -rln 'name: ingress-nginx' /root/bk72/install/blueking/*.yaml* 2>/dev/null | sed 's/^/  /'
echo "  --- 匹配内容 ---"
grep -rn 'name: ingress-nginx' /root/bk72/install/blueking/*.yaml* 2>/dev/null | sed 's/^/  /'

echo ""
echo "===== 2. bk-ingress-nginx 是否也定义了 ====="
grep -rn 'name: bk-ingress-nginx' /root/bk72/install/blueking/*.yaml* 2>/dev/null | sed 's/^/  /' || echo "  (未找到)"

echo ""
echo "===== 3. 当前 ingressClass 有哪些 ====="
kubectl get ingressclass --no-headers 2>/dev/null | awk '{print "  "$1"  默认:"($2=="true"?"是":"否")"  controller="$3}'

echo ""
echo "===== 4. 实际运行的 controller 镜像（社区版 or 蓝鲸版）====="
kubectl get deploy ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | sed 's/^/  /'
echo ""

echo ""
echo "===== 5. 所有 release 里带 ingress 的（含 third/fourth 批，评估影响面）====="
/root/bk72/install/bin/helmfile -f /root/bk72/install/blueking/base-blueking.yaml.gotmpl list 2>/dev/null | grep -iE 'ingress' | awk '{print "  "$1}' | sort -u

echo ""
echo "===== 6. 后续批次有多少 ingress 用了 snippet（影响面）====="
cd /root/bk72/install/blueking
for s in third fourth; do
  cnt=$(/root/bk72/install/bin/helmfile -f base-blueking.yaml.gotmpl -l seq=$s template 2>/dev/null | grep -cE 'nginx.ingress.kubernetes.io/[a-z-]*snippet')
  echo "  seq=$s: $cnt 处 snippet 注解"
done
