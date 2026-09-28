#!/usr/bin/env bash
# ndots:5 导致查询被拼上 search 域，template 匹配不到原名
# 修法：template 同时匹配 "原名" 和 "原名+search域" 两种形态
set -uo pipefail

CIP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.clusterIP}')
echo "ingress ClusterIP = $CIP"

echo ""
echo "===== 验证猜想：查询是否被拼上 search 域 ====="
echo "  在 coredns 里开 log 看真实查询名 —— 先看现有日志能否看到"
POD=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep dns | awk '{print $1}' | head -1)

echo ""
echo "===== 生成兼容 search 域的 Corefile ====="
# 关键：match 正则不锚定结尾，允许后面跟 .blueking.svc.cluster.local. 等
cat > /tmp/Corefile-v3 <<EOF
.:53 {
    errors
    log
    health {
       lameduck 5s
    }
    ready

    # 蓝鲸统一域名 → ingress-nginx
    # 兼容 ndots:5 拼 search 域后的查询名（如 bkiam.paas.example.com.blueking.svc.cluster.local.）
    template IN A {
        match "^[^.]+\\\\.paas\\\\.example\\\\.com(\\\\.[a-z0-9-]+)*\\\\.?\$"
        answer "{{ .Name }} 60 IN A ${CIP}"
        fallthrough
    }
    template IN A {
        match "^[^.]+\\\\.example\\\\.com(\\\\.[a-z0-9-]+)*\\\\.?\$"
        answer "{{ .Name }} 60 IN A ${CIP}"
        fallthrough
    }
    template IN A {
        match "^(paas\\\\.example\\\\.com|example\\\\.com)(\\\\.[a-z0-9-]+)*\\\\.?\$"
        answer "{{ .Name }} 60 IN A ${CIP}"
        fallthrough
    }

    kubernetes cluster.local in-addr.arpa ip6.arpa {
       pods insecure
       fallthrough in-addr.arpa ip6.arpa
       ttl 30
    }
    prometheus :9153
    forward . /etc/resolv.conf {
       max_concurrent 1000
    }
    cache 30 {
       disable success cluster.local
       disable denial cluster.local
    }
    loop
    reload
    loadbalance
}
EOF

echo "  match 规则预览:"
grep 'match' /tmp/Corefile-v3 | sed 's/^/    /'

echo ""
echo "===== 应用 v3 ====="
kubectl create cm coredns -n kube-system --from-file=Corefile=/tmp/Corefile-v3 --dry-run=client -o yaml \
  | kubectl apply -f - 2>&1 | tail -1 | sed 's/^/  /'
kubectl rollout restart deployment/coredns -n kube-system 2>&1 | sed 's/^/  /'
kubectl rollout status deployment/coredns -n kube-system --timeout=90s 2>&1 | tail -1 | sed 's/^/  /'

echo ""
echo "===== 验证 ====="
sleep 10
for d in bkiam.paas.example.com bkapi.paas.example.com paas.example.com; do
  R=$(kubectl exec paas3-dbg -n blueking -- getent hosts $d 2>/dev/null | head -1)
  [ -n "$R" ] && echo "  ✅ $d -> $R" || echo "  ❌ $d 失败"
done

echo ""
echo "===== coredns 日志（看真实查询名，确认是否被拼 search 域）====="
POD2=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep dns | awk '{print $1}' | head -1)
kubectl exec paas3-dbg -n blueking -- getent hosts bkiam.paas.example.com >/dev/null 2>&1
sleep 2
kubectl logs $POD2 -n kube-system --tail=15 2>&1 | grep -iE 'example|NOERROR|NXDOMAIN' | tail -8 | sed 's/^/    /'
