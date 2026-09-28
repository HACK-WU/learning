#!/usr/bin/env bash
set -uo pipefail

echo "===== 1. coredns 实际加载的 Corefile ====="
POD=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep dns | awk '{print $1}' | head -1)
echo "  Pod: $POD"
kubectl exec $POD -n kube-system -- cat /etc/coredns/Corefile 2>&1 | head -30 | sed 's/^/    /'

echo ""
echo "===== 2. coredns 日志（看有没有 template 相关报错）====="
kubectl logs $POD -n kube-system --tail=20 2>&1 | sed 's/^/    /'

echo ""
echo "===== 3. 直接用 nslookup 指定 coredns 测试 ====="
CIP=$(kubectl get svc kube-dns -n kube-system -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
echo "  kube-dns ClusterIP = $CIP"
kubectl exec paas3-dbg -n blueking -- getent hosts paas.example.com 2>&1 | sed 's/^/    /'

echo ""
echo "===== 4. 检查 paas3-dbg 的 resolv.conf（是否走 coredns）====="
kubectl exec paas3-dbg -n blueking -- cat /etc/resolv.conf 2>&1 | sed 's/^/    /'

echo ""
echo "===== 5. coredns Pod 重启次数（确认是新 Pod）====="
kubectl get pods -n kube-system --no-headers 2>/dev/null | grep dns | awk '{printf "  %-46s %-10s 重启%s  年龄%s\n", $1, $3, $4, $5}'

echo ""
echo "===== 6. 关键：template 的 match 是否要去掉结尾点 ====="
echo "  CoreDNS template match 的正则匹配的是查询名，通常带结尾点"
echo "  当前规则: ^([a-zA-Z0-9-]+)\\.paas\\.example\\.com\\.$"
echo "  实测查询名可能是: bkiam.paas.example.com. （带点）"
# 换一版：同时兼容带点和不带点
cat > /tmp/C2 <<'EOF'
.:53 {
    errors
    health {
       lameduck 5s
    }
    ready
    template IN A {
        match "(paas\\.example\\.com|example\\.com)\\.?$"
        answer "{{ .Name }} 60 IN A 10.96.110.202"
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
echo "  已生成简化版 /tmp/C2（不锚定开头，兼容带点/不带点）"
