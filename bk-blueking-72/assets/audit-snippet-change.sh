#!/usr/bin/env bash
set -uo pipefail
{
echo "===== 1. 我上一轮到底改了什么（审计）====="
echo "  --- 查 ConfigMap 的 managedFields，看谁改的 ---"
kubectl get cm ingress-nginx-controller -n ingress-nginx -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
for mf in d['metadata'].get('managedFields',[]):
    m=mf.get('manager','?')
    t=mf.get('time','?')
    op=mf.get('operation','?')
    print('  manager=%-24s time=%s op=%s' % (m,t,op))
" 2>/dev/null

echo ""
echo "===== 2. 关键：两个 controller 各自的 ConfigMap ====="
echo "  [A] ingress-nginx-controller (class=nginx)  CM=ingress-nginx/ingress-nginx-controller"
echo "      allow-snippet-annotations=true  annotations-risk-level=Critical"
echo "  [B] bk-ingress-nginx (class=bk-ingress-nginx) CM=blueking/bk-ingress-nginx"
echo "      无 allow-snippet-annotations 字段"
echo ""
echo "  --> 谁有 webhook？"
kubectl get validatingwebhookconfigurations ingress-nginx-admission -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
for w in d.get('webhooks',[]):
    print('  webhook:',w['name'])
    print('    clientConfig.service:',(w.get('clientConfig',{}).get('service') or {}).get('name'),'ns=',(w.get('clientConfig',{}).get('service') or {}).get('namespace'))
    for r in w.get('rules',[]):
        print('    rules:',r.get('operations'),r.get('apiGroups'),r.get('resources'))
" 2>/dev/null

echo ""
echo "===== 3. 失败时用的是哪个 class（决定该改谁）====="
echo "  chart values.yaml:881 的 configuration-snippet 上下文:"
sed -n '870,895p' /tmp/apigwchart/bk-apigateway/values.yaml 2>/dev/null | sed 's/^/    /'

echo ""
echo "===== 4. 判定：现在重跑能否成功 ====="
echo "  探测结果: 带 configuration-snippet 的 ingress 创建成功"
echo "  --> webhook 已放行，理论上重跑可过"
echo ""
echo "  --- 但需确认 apigw 用的是 class=nginx 还是 bk-ingress-nginx ---"
grep -rn 'ingressClassName\|ingress-class' /root/bk72/install/blueking/environments/default/bkapigateway-values.yaml.gotmpl 2>/dev/null | head -6 | sed 's/^/    /'
echo "  --- 全局默认 ---"
grep -rn 'ingressClassName' /root/bk72/install/blueking/environments/default/values.yaml 2>/dev/null | head -4 | sed 's/^/    /'
} > /root/audit-change.txt 2>&1
cat /root/audit-change.txt
