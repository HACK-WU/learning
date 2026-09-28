#!/usr/bin/env bash
set -uo pipefail
NS=blueking

echo "===== gateway 全部 env（精确）====="
kubectl get deployment bk-repo-bkrepo-gateway -n $NS -o json 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
for c in d['spec']['template']['spec']['containers']:
    print('  container:',c['name'])
    for e in c.get('env') or []:
        v=e.get('value')
        v=v if v is not None else ('(from: '+json.dumps(e.get('valueFrom'),ensure_ascii=False)+')' if e.get('valueFrom') else '')
        print('    %s = %s' % (e['name'], v))
" 2>&1

echo ""
echo "===== 所有 bkrepo Pod 实际运行时的 KEY 类环境变量（从 Pod 里读，含 secret 解析后的值）====="
for P in $(kubectl get pods -n $NS --no-headers 2>/dev/null | grep -E 'bkrepo-(gateway|auth|repository)' | grep Running | awk '{print $1}'); do
  echo "  --- $P ---"
  kubectl exec $P -n $NS -- env 2>/dev/null | grep -iE 'ACCESS_KEY|SECRET_KEY|ACCESSKEY|SECRETKEY|USERNAME|PASSWORD' | sed 's/^/    /'
done

echo ""
echo "===== bkrepo 的 ingress 是否已就绪（先确认外部可达）====="
kubectl get ingress -n $NS --no-headers 2>/dev/null | grep -i bkrepo | awk '{printf "  %-26s %s\n", $1, $3}'
