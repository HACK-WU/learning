#!/usr/bin/env bash
set -uo pipefail
NS=blueking

echo "===== 1. 实测真正的 ping 地址（走 APIGW）====="
for u in \
  "http://bkapi.paas.example.com/api/bk-iam/prod/ping" \
  "http://bkapi.paas.example.com/api/bk-iam/prod/" \
  "http://bkapi.paas.example.com/" ; do
  C=$(kubectl exec paas3-dbg -n $NS -- bash -c "curl -s -o /dev/null -w '%{http_code}' --max-time 8 '$u'" 2>/dev/null)
  echo "  ${C:-000}  $u"
done

echo ""
echo "===== 2. apigw 上 bk-iam 是否已注册 ====="
kubectl exec paas3-dbg -n $NS -- bash -c "curl -s --max-time 8 'http://bkapi.paas.example.com/api/bk-iam/prod/ping' | head -c 300" 2>&1 | sed 's/^/    /'

echo ""
echo "===== 3. apigateway 相关 Pod 状态 ====="
kubectl get pods -n $NS --no-headers 2>/dev/null | grep -E 'bk-apigateway' | awk '{printf "  %-48s %-14s 重启%s\n", $1, $3, $4}'

echo ""
echo "===== 4. 已注册的网关列表（apigw dashboard/backend）====="
kubectl exec paas3-dbg -n $NS -- bash -c "curl -s --max-time 8 'http://apigw.paas.example.com/backend/' -o /dev/null -w '  dashboard HTTP %{http_code}\n'" 2>&1

echo ""
echo "===== 5. 关键判断：能不能让 paas3 绕过 APIGW 直连 IAM ====="
echo "  方案：把 BK_IAM_APIGATEWAY_URL 置空 → 自动回落到 BK_IAM_V3_INNER_URL"
echo "  看 ConfigMap 里该值在哪定义"
kubectl get cm bkpaas3-apiserver-general-envs -n $NS -o jsonpath='{range .data}{"\n"}{end}' 2>/dev/null >/dev/null
kubectl get cm bkpaas3-apiserver-general-envs -n $NS -o yaml 2>/dev/null | grep -iE 'IAM|APIGATEWAY' | head -10 | sed 's/^/    /'

echo ""
echo "===== 6. 或：确认 bk-iam 是否应通过 apigw 同步（sync job 失败导致未注册）====="
kubectl get jobs -n $NS --no-headers 2>/dev/null | grep -iE 'iam.*sync|sync.*iam' | awk '{printf "  %-48s %-10s\n", $1, $2}'
