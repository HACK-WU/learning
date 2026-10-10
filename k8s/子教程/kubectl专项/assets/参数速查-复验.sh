#!/usr/bin/env bash
# 参数速查.md 独立复验：重跑文档关键结论，验证可复现
PASS=0; FAIL=0
ck(){ if [ "$2" = "$3" ]; then echo "  ✅ PASS  $1 (实测=$2)"; PASS=$((PASS+1));
      else echo "  ❌ FAIL  $1 (期望=$3 实测=$2)"; FAIL=$((FAIL+1)); fi; }
ckc(){ if echo "$2" | grep -qF "$3"; then echo "  ✅ PASS  $1 (含: $3)"; PASS=$((PASS+1));
      else echo "  ❌ FAIL  $1 (期望含: $3 实测: $(echo "$2"|head -c 120))"; FAIL=$((FAIL+1)); fi; }
sec(){ echo ""; echo "### $1"; }
rc(){ OUT=$(eval "$1" 2>&1); echo $?; }

NS=kcpv-lab
echo "########## 参数速查 独立复验 ##########"
echo "基线 context: $(kubectl config current-context)"
echo ""

mkdir -p /tmp/vdir
cat > /tmp/vdir/cm.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata: {name: pv-a, namespace: $NS, labels: {pv: "true"}}
data: {k: v}
EOF
kubectl create ns $NS >/dev/null 2>&1
cat > /tmp/v-webpod.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata: {name: web-pod, namespace: kcpv-lab, labels: {app: web}}
spec:
  containers:
  - name: app
    image: nginx:alpine
  - name: side
    image: busybox:1.36
    command: ["sh","-c","while true; do echo x; sleep 5; done"]
EOF
kubectl apply -f /tmp/v-webpod.yaml >/dev/null 2>&1
kubectl wait --for=condition=Ready pod/web-pod -n $NS --timeout=90s >/dev/null 2>&1

sec "V1 认证优先级：--token 被 client-cert 静默覆盖"
R=$(rc "kubectl --token=fake-token-123 get nodes >/dev/null 2>&1")
ck "假 token + 自带 cert → 成功" "$R" "0"
SRV=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
cat > /tmp/v-clean.yaml <<EOF
apiVersion: v1
kind: Config
clusters: [{name: c, cluster: {server: $SRV, insecure-skip-tls-verify: true}}]
users: [{name: u, user: {}}]
contexts: [{name: cx, context: {cluster: c, user: u}}]
current-context: cx
EOF
O=$(kubectl --kubeconfig=/tmp/v-clean.yaml --token=fake-token-123 get nodes 2>&1)
ckc "干净 config + 假 token → Unauthorized" "$O" "Unauthorized"

sec "V2 auth whoami 能确认身份"
O=$(kubectl auth whoami 2>&1)
ckc "whoami 显示 kubernetes-admin" "$O" "kubernetes-admin"

sec "V3 exec 必须加 --"
O=$(kubectl exec -n $NS web-pod -c app true 2>&1)
ckc "不写 -- 报 is not supported anymore" "$O" "is not supported anymore"

sec "V4 --request-timeout 生效"
O=$(kubectl --request-timeout=1ms get nodes 2>&1)
ckc "1ms 超时（两种文案其一）" "$O" "Unable to connect to the server"
echo "  ℹ️  本次实测原文: $(echo "$O"|head -1|head -c 110)"

sec "V5 -v=6 统计关键词 verb=\"GET\""
N=$(kubectl get nodes -v=6 2>&1 | grep -c 'verb="GET"')
if [ "$N" -ge 1 ]; then echo "  ✅ PASS  verb=\"GET\" 可统计 (实测=$N)"; PASS=$((PASS+1));
else echo "  ❌ FAIL  verb=\"GET\" 计数=$N"; FAIL=$((FAIL+1)); fi
M=$(kubectl get nodes -v=6 2>&1 | grep -c 'GET https')
ck "GET https 恒为 0" "$M" "0"

sec "V6 get 输出类 flag"
O=$(kubectl get pods -n $NS --show-labels --no-headers 2>&1)
ckc "--show-labels 含 app=" "$O" "app="
O=$(kubectl get pods -n $NS --show-kind --no-headers 2>&1)
ckc "--show-kind 带 pod/ 前缀" "$O" "pod/"
O=$(kubectl get pods -n $NS -L app --no-headers 2>&1)
echo "  ℹ️  -L app 输出: $O"
ckc "-L app 有独立列（末列=标签值 web）" "$(echo "$O" | awk '{print $NF}')" "web"
O=$(kubectl get pods -n $NS --show-labels --no-headers 2>&1)
echo "  ℹ️  --show-labels 输出: $(echo "$O"|head -1|tail -c 40)"

sec "V7 --subresource=status"
O=$(kubectl get pod web-pod -n $NS --subresource=status -o jsonpath='{.status.phase}' 2>&1)
ck "取 status 子资源" "$O" "Running"

sec "V8 --validate=ignore vs strict"
cat > /tmp/v-bad.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata: {name: v-bad, namespace: $NS}
data: {k: v}
unknownField: oops
EOF
ck "strict 退出码=1" "$(rc "kubectl apply -f /tmp/v-bad.yaml --validate=strict >/dev/null 2>&1")" "1"
ck "ignore 退出码=0" "$(rc "kubectl apply -f /tmp/v-bad.yaml --validate=ignore >/dev/null 2>&1")" "0"
O=$(kubectl get cm v-bad -n $NS -o jsonpath='{.unknownField}' 2>&1)
echo "  ℹ️  ignore 后 unknownField 存进集群了吗: [$O]"

sec "V9 --prune 格式必须是 group/version/kind"
O=$(kubectl apply -f /tmp/vdir/ --prune -l pv=true --prune-allowlist=v1/ConfigMap 2>&1)
ckc "v1/ConfigMap 报错格式" "$O" "please follow <group/version/kind>"

sec "V10 --prune 不加 -l 拒绝执行"
O=$(kubectl apply -f /tmp/vdir/ -n $NS --prune --prune-allowlist=core/v1/ConfigMap --dry-run=client 2>&1)
ckc "要求显式 --all" "$O" "without explicitly passing --all"

sec "V11 --prune 只删被 apply 过的（不删 create 建的）"
mkdir -p /tmp/vdir
cat > /tmp/vdir/a.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata: {name: pv-a, namespace: $NS, labels: {pv: "true"}}
data: {k: v}
EOF
kubectl apply -f /tmp/vdir/ -n $NS --prune -l pv=true --prune-allowlist=core/v1/ConfigMap >/dev/null 2>&1
kubectl create cm pv-c --from-literal=k=v -n $NS >/dev/null 2>&1
kubectl label cm pv-c pv=true -n $NS --overwrite >/dev/null 2>&1
kubectl apply -f /tmp/vdir/ -n $NS --prune -l pv=true --prune-allowlist=core/v1/ConfigMap >/dev/null 2>&1
ck "create 建的 pv-c 仍存在" "$(kubectl get cm pv-c -n $NS --no-headers 2>&1 | wc -l)" "1"
ANN=$(kubectl get cm pv-c -n $NS -o jsonpath='{.metadata.annotations.kubectl\.kubernetes\.io/last-applied-configuration}' 2>&1)
ck "pv-c 无 last-applied 注解" "$ANN" ""

sec "V12 --warnings-as-errors 对【服务端告警】是否生效"
echo "  （A. 服务端告警样例：v1 Endpoints deprecated）"
O=$(kubectl apply -f /tmp/vdir/ -n $NS --prune -l pv=true 2>&1)
ckc "服务端告警原文" "$O" "v1 Endpoints is deprecated"
ck "服务端告警 + --warnings-as-errors → 退出码=1（生效）" "$(rc "kubectl apply -f /tmp/vdir/ -n $NS --prune -l pv=true --warnings-as-errors=true >/dev/null 2>&1")" "1"
echo "  （B. 客户端告警样例：缺 last-applied 注解）"
kubectl create cm v-warn --from-literal=k=v -n $NS >/dev/null 2>&1
cat > /tmp/v-warn.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata: {name: v-warn, namespace: $NS}
data: {k: v}
EOF
O=$(kubectl apply -f /tmp/v-warn.yaml 2>&1)
ckc "客户端告警原文" "$O" "last-applied-configuration annotation"
R0=$(rc "kubectl apply -f /tmp/v-warn.yaml >/dev/null 2>&1")
echo "  ℹ️  客户端告警 不加 flag 退出码=$R0"
kubectl annotate cm v-warn -n $NS kubectl.kubernetes.io/last-applied-configuration- >/dev/null 2>&1
R1=$(rc "kubectl apply -f /tmp/v-warn.yaml --warnings-as-errors=true >/dev/null 2>&1")
echo "  ℹ️  客户端告警 加 --warnings-as-errors 退出码=$R1"
ck "客户端告警 + --warnings-as-errors → 退出码=0（无效）" "$R1" "0"

sec "V13 退出码表"
ck "rollout status 不存在=1" "$(rc "kubectl rollout status deployment/nonexistent-qq --timeout=3s >/dev/null 2>&1")" "1"
ck "wait 不存在=1" "$(rc "kubectl wait --for=condition=Ready pod/nonexistent-qq --timeout=3s >/dev/null 2>&1")" "1"
ck "get 不存在=1" "$(rc "kubectl get pod/nonexistent-qq >/dev/null 2>&1")" "1"

sec "V14 管道会吃掉退出码（验证文档 4.2 陷阱）"
echo "   ⚠️ 说明：管道后 \$? 是最后一条命令(head)的退出码，非 kubectl 的"
kubectl get pod/nonexistent-qq 2>&1 | head -1 >/dev/null
PIPED=${PIPESTATUS[0]}
echo "  ℹ️  PIPESTATUS[0]（管道中 kubectl 真实退出码）=$PIPED"
echo "  ℹ️  \$?（管道整体，即 head）= $?"
OUT2=$(kubectl get pod/nonexistent-qq 2>&1); DIRECT=$?
ck "PIPESTATUS[0] 正确反映 kubectl 失败=1" "$PIPED" "1"
ck "直接取退出码=1" "$DIRECT" "1"

sec "V15 rollout 命令族可用"
kubectl create deployment v-roll --image=nginx:alpine -n $NS >/dev/null 2>&1
kubectl wait --for=condition=Available deployment/v-roll -n $NS --timeout=90s >/dev/null 2>&1
O=$(kubectl rollout status deployment/v-roll -n $NS 2>&1)
ckc "rollout status" "$O" "successfully rolled out"
O=$(kubectl rollout history deployment/v-roll -n $NS 2>&1)
ckc "history CHANGE-CAUSE 为 none" "$O" "<none>"

sec "V16 scale --current-replicas 报错原文"
O=$(kubectl scale deployment/v-roll --current-replicas=99 --replicas=5 -n $NS 2>&1)
echo "  ℹ️  原文: $(echo "$O"|head -1)"

sec "V17 auth can-i"
ck "can-i get pods = yes" "$(kubectl auth can-i get pods 2>&1)" "yes"

sec "V18 port-forward / cp / logs 多容器静默选"
O=$(kubectl cp /tmp/v-bad.yaml $NS/web-pod:/tmp/x.txt 2>&1)
ckc "cp 不写 -c 有 Defaulted" "$O" "Defaulted container"
O=$(kubectl logs -n $NS web-pod --tail=1 2>&1)
ckc "logs 不写 -c 有 Defaulted" "$O" "Defaulted container"

echo ""
echo "########## 清理 ##########"
kubectl delete ns $NS --timeout=120s 2>&1|head -1
rm -rf /tmp/vdir /tmp/v-clean.yaml /tmp/v-bad.yaml /tmp/v-warn.yaml /tmp/v-webpod.yaml 2>/dev/null
echo "断言 NS: $(kubectl get ns $NS 2>&1|head -1)"
echo "context: $(kubectl config current-context)"
echo ""
echo "########## 结果: PASS=$PASS FAIL=$FAIL ##########"
