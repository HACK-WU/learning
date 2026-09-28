#!/usr/bin/env bash
# 方案C：让 *.paas.example.com / *.example.com 在集群内解析到 ingress ClusterIP
# 关键：hosts 插件不支持通配 → 用 template 插件（已确认 coredns 支持）
set -uo pipefail

CIP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.clusterIP}')
echo "ingress ClusterIP = $CIP"

echo ""
echo "===== 1. 生成新 Corefile ====="
cat > /tmp/Corefile-new <<EOF
.:53 {
    errors
    health {
       lameduck 5s
    }
    ready

    # ===== 蓝鲸统一域名通配解析（方案C）=====
    # 集群内所有 Pod 访问 *.paas.example.com / *.example.com 都转发到 ingress-nginx
    template IN A {
        match "^([a-zA-Z0-9-]+)\\\\.paas\\\\.example\\\\.com\\\\.\$"
        answer "{{ .Name }} 60 IN A ${CIP}"
        fallthrough
    }
    template IN A {
        match "^([a-zA-Z0-9-]+)\\\\.example\\\\.com\\\\.\$"
        answer "{{ .Name }} 60 IN A ${CIP}"
        fallthrough
    }
    template IN A {
        match "^example\\\\.com\\\\.\$"
        answer "{{ .Name }} 60 IN A ${CIP}"
        fallthrough
    }
    template IN A {
        match "^paas\\\\.example\\\\.com\\\\.\$"
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

echo "  新 Corefile（template 段）:"
grep -A2 'template IN A' /tmp/Corefile-new | head -8 | sed 's/^/    /'

echo ""
echo "===== 2. 校验 Corefile 语法 ====="
# 用现有 coredns 二进制校验
POD=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep dns | awk '{print $1}' | head -1)
kubectl cp /tmp/Corefile-new kube-system/$POD:/tmp/Corefile-check 2>&1 | sed 's/^/  /'
kubectl exec $POD -n kube-system -- /coredns -conf /tmp/Corefile-check -dns.port 15353 2>&1 | head -12 | sed 's/^/    /' &
sleep 4
kill %1 2>/dev/null
echo "  （上面若无 parse error 即语法 OK）"

echo ""
echo "===== 3. 应用新 Corefile ====="
kubectl create cm coredns -n kube-system --from-file=Corefile=/tmp/Corefile-new --dry-run=client -o yaml \
  | kubectl apply -f - 2>&1 | sed 's/^/  /'

echo ""
echo "===== 4. 重启 coredns 生效 ====="
kubectl rollout restart deployment/coredns -n kube-system 2>&1 | sed 's/^/  /'
kubectl rollout status deployment/coredns -n kube-system --timeout=90s 2>&1 | sed 's/^/  /'

echo ""
echo "===== 5. 等 DNS 生效后验证（在 paas3-dbg 里测）====="
sleep 8
for d in bkiam.paas.example.com bkapi.paas.example.com bkrepo.example.com paas.example.com; do
  R=$(kubectl exec paas3-dbg -n blueking -- getent hosts $d 2>/dev/null | head -1)
  if [ -n "$R" ]; then
    echo "  ✅ $d  ->  $R"
  else
    echo "  ❌ $d  仍解析失败"
  fi
done

echo ""
echo "===== 6. 实测 HTTP 连通 ====="
kubectl exec paas3-dbg -n blueking -- bash -c "curl -s -o /dev/null -w '  bkiam  HTTP %{http_code}\n' --max-time 10 http://bkiam.paas.example.com/ping" 2>&1 | sed 's/^/  /'
