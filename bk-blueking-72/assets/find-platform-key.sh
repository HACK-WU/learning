#!/usr/bin/env bash
set -uo pipefail
NS=blueking

echo "===== 1. gateway deployment 的 env（找 accessKey/secretKey）====="
kubectl get deployment bk-repo-bkrepo-gateway -n $NS -o jsonpath='{range .spec.template.spec.containers[0].env[*]}  {.name} = {.value}{"\n"}{end}' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 2. gateway 挂载的 secret ====="
kubectl get deployment bk-repo-bkrepo-gateway -n $NS -o jsonpath='{range .spec.template.spec.containers[0].envFrom[*]}  envFrom: {..}{"\n"}{end}' 2>&1 | sed 's/^/  /'
kubectl get deployment bk-repo-bkrepo-gateway -n $NS -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}{"\n"}{end}' 2>/dev/null | grep -iE 'key|secret' | sed 's/^/  命中: /'

echo ""
echo "===== 3. 所有 bkrepo 相关 secret 内容 ====="
for s in $(kubectl get secret -n $NS --no-headers 2>/dev/null | grep -iE 'bkrepo|gateway' | awk '{print $1}'); do
  echo "  --- $s ---"
  kubectl get secret $s -n $NS -o go-template='{{range $k,$v := .data}}    {{$k}} = {{$v | base64decode}}{{"\n"}}{{end}}' 2>&1
done

echo ""
echo "===== 4. gateway configmap 里的密钥 ====="
for cm in $(kubectl get cm -n $NS -o name 2>/dev/null | grep -i 'bkrepo.*gateway\|gateway'); do
  echo "  --- $cm ---"
  kubectl get $cm -n $NS -o yaml 2>/dev/null | grep -iE 'accessKey|secretKey|key:' | head -6 | sed 's/^/    /'
done

echo ""
echo "===== 5. 用找到的密钥试调 create ====="
