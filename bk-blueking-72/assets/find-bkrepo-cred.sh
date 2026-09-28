#!/usr/bin/env bash
set -uo pipefail
NS=blueking

echo "===== 1. bkrepo 相关 Secret ====="
kubectl get secret -n $NS --no-headers 2>/dev/null | grep -iE 'bkrepo|repo' | awk '{printf "  %-46s %-16s\n", $1, $2}'

echo ""
echo "===== 2. bkpaas3 用的 bkrepo-envs（当前密码来源）====="
kubectl get secret bkpaas3-apiserver-bkrepo-envs -n $NS -o jsonpath='{range .data}{"  "}{@}{"\n"}{end}' 2>/dev/null >/dev/null
for k in $(kubectl get secret bkpaas3-apiserver-bkrepo-envs -n $NS -o jsonpath='{range .data}{$.key}{"\n"}{end}' 2>/dev/null); do :; done
kubectl get secret bkpaas3-apiserver-bkrepo-envs -n $NS -o go-template='{{range $k,$v := .data}}  {{$k}} = {{$v | base64decode}}{{"\n"}}{{end}}' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 3. bkrepo 自己的 admin 凭据（可能在不同 secret）====="
for s in $(kubectl get secret -n $NS --no-headers 2>/dev/null | grep -i bkrepo | awk '{print $1}'); do
  echo "  --- $s ---"
  kubectl get secret $s -n $NS -o go-template='{{range $k,$v := .data}}    {{$k}} = {{$v | base64decode}}{{"\n"}}{{end}}' 2>&1 | head -8
done

echo ""
echo "===== 4. 解密 base64: YWRtaW46Ymx1ZWtpbmc= ====="
echo "  $(echo 'YWRtaW46Ymx1ZWtpbmc=' | base64 -d)"
echo "  即当前用的是 admin:blueking"

echo ""
echo "===== 5. 测试正确的 admin 密码（试几个候选）====="
for P in blueking Blueking admin bkrepo bkrepo@123 Bkrepo@123 paas paas@123; do
  C=$(kubectl exec netprobe -n $NS -- bash -c "curl -s -o /dev/null -w '%{http_code}' --max-time 8 -u admin:$P http://bkrepo.paas.example.com/repository/api/project/list" 2>/dev/null)
  echo "    admin:$P -> HTTP ${C:-000}"
done

echo ""
echo "===== 6. bkrepo 用的是什么认证？查 bkrepo pod 的 env ====="
BP=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep -E 'bkrepo.*auth|bk-repo' | grep Running | awk '{print $1}' | head -3)
for p in $BP; do
  echo "  --- $p ---"
  kubectl exec $p -n $NS -- env 2>/dev/null | grep -iE 'ADMIN|PASS|USER' | head -6 | sed 's/^/    /'
done
