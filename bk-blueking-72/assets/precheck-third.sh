#!/usr/bin/env bash
# 部署前准入风险预检：避免像 snippet 那样部署时才撞墙
set -uo pipefail
export PATH=/root/bk72/install/bin:$PATH
HF=/root/bk72/install/bin/helmfile
B=/root/bk72/install/blueking
cd "$B" || exit 1
SEQ=${1:-third}

echo "===== 1. 渲染 seq=$SEQ 到临时文件 ====="
$HF -f base-blueking.yaml.gotmpl -l seq=$SEQ template 2>/dev/null > /tmp/render-$SEQ.yaml
echo "  渲染行数: $(wc -l < /tmp/render-$SEQ.yaml)"
[ ! -s /tmp/render-$SEQ.yaml ] && { echo "  渲染为空，终止"; exit 1; }

echo ""
echo "===== 2. snippet 类注解（已知会拦）====="
grep -oE 'nginx.ingress.kubernetes.io/[a-z-]*snippet[a-z-]*' /tmp/render-$SEQ.yaml | sort | uniq -c | sed 's/^/  /' || echo "  无"

echo ""
echo "===== 3. 所有 ingress 注解种类（找陌生注解）====="
grep -oE '(nginx|bk|blueking)\.[a-z.-]+/[a-zA-Z.-]+' /tmp/render-$SEQ.yaml | sort -u | sed 's/^/  /'

echo ""
echo "===== 4. 集群准入控制清单（可能被拦的类型）====="
echo "  --- ValidatingWebhook ---"
kubectl get validatingwebhookconfigurations --no-headers 2>/dev/null | awk '{print "    "$1}'
echo "  --- MutatingWebhook ---"
kubectl get mutatingwebhookconfigurations --no-headers 2>/dev/null | awk '{print "    "$1}'

echo ""
echo "===== 5. ResourceQuota / LimitRange（可能资源不足）====="
kubectl get resourcequota -A --no-headers 2>/dev/null | awk '{print "    "$1" "$2}' || echo "    无 quota"
kubectl get limitrange -A --no-headers 2>/dev/null | awk '{print "    "$1" "$2}' || echo "    无 limitrange"

echo ""
echo "===== 6. PodSecurity / 特权检查（securityContext 敏感项）====="
grep -cE 'privileged: true' /tmp/render-$SEQ.yaml 2>/dev/null | sed 's/^/  privileged:true 出现 /'
grep -oE 'runAsUser: [0-9]+' /tmp/render-$SEQ.yaml 2>/dev/null | sort | uniq -c | sed 's/^/  /'

echo ""
echo "===== 7. storageClass 需求 vs 集群现有 ====="
echo "  --- 渲染中申请的 SC ---"
grep -oE 'storageClassName: [^ ]+' /tmp/render-$SEQ.yaml | sort -u | sed 's/^/    /'
echo "  --- 集群现有 SC ---"
kubectl get storageclass --no-headers 2>/dev/null | awk '{print "    "$1"  (default:"($2=="(default)"?"是":"否")" )"}' || echo "    无"

echo ""
echo "===== 8. 镜像清单 ====="
grep -oE 'image: "?[^ "]+' /tmp/render-$SEQ.yaml | sed -E 's/image: "?//' | tr -d '"' | sort -u > /tmp/imgs-$SEQ.txt
echo "  镜像数: $(wc -l < /tmp/imgs-$SEQ.txt)"
sed 's/^/    /' /tmp/imgs-$SEQ.txt

echo ""
echo "===== 9. 节点剩余磁盘（大镜像能否装下）====="
for n in k8s-c1-calico-control-plane k8s-c1-calico-worker k8s-c1-calico-worker2; do
  docker exec $n df -h /var/lib/containerd 2>/dev/null | tail -1 | awk '{printf "  %-32s 已用%s 可用%s 使用率%s\n", "'"$n"'", $3, $4, $5}'
done
