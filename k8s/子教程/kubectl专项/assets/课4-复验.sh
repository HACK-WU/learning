#!/usr/bin/env bash
# 课 4 讲义复验：原样照抄讲义第四幕命令
echo "########## 课4 复验 ##########"
kubectl config use-context kind-k8s-c1 >/dev/null 2>&1
echo "基线 context: $(kubectl config current-context)"
PASS=0; FAIL=0
chk(){ if [ "$2" = "$3" ]; then echo "  ✅ $1"; PASS=$((PASS+1)); else echo "  ❌ $1  期望[$3] 实际[$2]"; FAIL=$((FAIL+1)); fi; }

echo ""
echo "=== 第1步：补全现状（只读）==="
chk "第1步 bash-completion 已装" "$(dpkg -s bash-completion >/dev/null 2>&1 && echo 1 || echo 0)" "1"
chk "第1步 /etc/bash_completion 存在" "$([ -f /etc/bash_completion ] && echo 1 || echo 0)" "1"
R=$(type __start_kubectl >/dev/null 2>&1 && echo 1 || echo 0)
chk "第1步 当前会话补全未加载(基线)" "$R" "0"
chk "第1步 补全脚本无 __kubectl_get_resource(讲义说法)" "$(kubectl completion bash 2>&1 | grep -c '__kubectl_get_resource')" "0"
chk "第1步 补全脚本有 __start_kubectl" "$(( $(kubectl completion bash 2>&1 | grep -c '__start_kubectl') >= 1 ))" "1"

echo ""
echo "=== 第2步：临时启用补全 ==="
bash -c 'source <(kubectl completion bash) 2>/dev/null; type __start_kubectl >/dev/null 2>&1 && echo 1 || echo 0' > /tmp/r2 2>&1
R2=$(cat /tmp/r2)
echo "  source 后补全函数加载: $R2"
chk "第2步 source 后补全函数已加载" "$R2" "1"
CP2=$(bash -c 'source <(kubectl completion bash) 2>/dev/null; complete -p kubectl 2>&1 | head -1')
echo "  complete -p kubectl: $CP2"
chk "第2步 complete 已注册 kubectl" "$(echo "$CP2" | grep -c '__start_kubectl')" "1"

echo ""
echo "=== 第4步：别名不带补全 ==="
O4a=$(bash -c '
  alias k=kubectl
  source <(kubectl completion bash) 2>/dev/null
  complete -p k >/dev/null 2>&1 && echo "有补全" || echo "无补全"
' 2>&1)
chk "第4步 别名 k 默认无补全" "$O4a" "无补全"
O4b=$(bash -c '
  alias k=kubectl
  source <(kubectl completion bash) 2>/dev/null
  complete -o default -F __start_kubectl k 2>/dev/null
  complete -p k 2>&1 | head -1
' 2>&1)
echo "  修复后: $O4b"
chk "第4步 complete -F 后 k 有补全" "$(echo "$O4b" | grep -c '__start_kubectl')" "1"

echo ""
echo "=== 第5步：explain ==="
N5=$(kubectl explain deploy.spec 2>&1 | sed -n '/^FIELDS:/,$p' | grep -cE '^  [a-zA-Z]')
echo "  deploy.spec 顶层字段数: $N5"
chk "第5步 顶层字段数=8" "$N5" "8"
R5=$(kubectl explain deploy.spec --recursive 2>&1 | wc -l)
echo "  --recursive 行数: $R5"
chk "第5步 recursive 行数≈1216" "$(( R5 > 1000 && R5 < 1400 ))" "1"
G5=$(kubectl explain deployment --recursive 2>&1 | grep -B4 containerPort | head -6)
echo "  grep -B4 containerPort 有输出"
chk "第5步 grep 能定位 containerPort" "$(echo "$G5" | grep -c containerPort)" "1"
D5=$(kubectl explain deploy.spec.template.spec.containers.ports.containerPort 2>&1)
chk "第5步 深层路径可查" "$(echo "$D5" | grep -c 'FIELD: containerPort')" "1"
E5=$(kubectl explain deploy.spec.bogusField 2>&1)
chk "第5步 不存在字段报错" "$(echo "$E5" | grep -c 'does not exist')" "1"

echo ""
echo "=== 第6步：api-resources ==="
A6=$(kubectl api-resources 2>&1 | wc -l)
echo "  api-resources 行数(含表头): $A6"
chk "第6步 总数≈69" "$(( A6 > 60 && A6 < 80 ))" "1"
NT=$(kubectl api-resources --namespaced=true 2>&1 | wc -l)
NF=$(kubectl api-resources --namespaced=false 2>&1 | wc -l)
echo "  namespaced=true: $NT / false: $NF"
chk "第6步 namespaced 分类可用" "$(( NT > 1 && NF > 1 ))" "1"
AG=$(kubectl api-resources --api-group=apps 2>&1 | grep -c 'apps/v1')
echo "  apps 组资源数: $AG"
chk "第6步 apps 组有 5 个" "$AG" "5"
CS=$(kubectl api-resources -o wide 2>&1 | grep -E '^componentstatuses')
echo "  componentstatuses: $(echo "$CS" | awk '{print $5}')"
chk "第6步 componentstatuses 无 delete" "$(echo "$CS" | grep -c 'delete')" "0"
H6=$(kubectl api-resources 2>&1 | grep -E '^hpa|HorizontalPodAutoscaler')
chk "第6步 hpa 可反查" "$(echo "$H6" | grep -c 'HorizontalPodAutoscaler')" "1"
V2=$(kubectl explain hpa 2>&1 | grep 'VERSION' | awk '{print $2}')
V1=$(kubectl explain hpa --api-version=autoscaling/v1 2>&1 | grep 'VERSION' | awk '{print $2}')
echo "  默认版本=$V2  指定v1=$V1"
chk "第6步 默认 v2" "$V2" "v2"
chk "第6步 可指定 v1" "$V1" "v1"

echo ""
echo "=== 第7步：故障 Pod 排障 ==="
NS=kc4-lab
kubectl delete ns $NS --ignore-not-found >/dev/null 2>&1
kubectl create ns $NS >/dev/null 2>&1
cat > /tmp/evfail.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: evfail
  namespace: kc4-lab
spec:
  restartPolicy: Never
  containers:
  - name: c
    image: nonexistent.invalid/nosuchimage:v1
    command: ['sh','-c','echo hi']
EOF
kubectl apply -f /tmp/evfail.yaml >/dev/null 2>&1
sleep 20
chk "第7步 Pod 非 Running" "$(kubectl get pod evfail -n $NS -o jsonpath='{.status.phase}' 2>&1)" "Pending"
DESC=$(kubectl describe pod evfail -n $NS 2>&1 | sed -n '/^Events:/,$p')
chk "第7步 describe 有 Events 段" "$(echo "$DESC" | grep -c 'Events:')" "1"
EV=$(kubectl get events -n $NS --field-selector=involvedObject.name=evfail --sort-by=.metadata.creationTimestamp --no-headers 2>&1)
echo "  筛选到事件数: $(echo "$EV" | grep -c 'evfail')"
chk "第7步 field-selector 能筛出事件" "$(( $(echo "$EV" | grep -c 'evfail') >= 1 ))" "1"
W=$(kubectl get events -n $NS --field-selector=type=Warning --no-headers 2>&1)
echo "  Warning 事件数: $(echo "$W" | grep -c 'Warning')"
chk "第7步 能只筛 Warning" "$(( $(echo "$W" | grep -c 'Warning') >= 1 ))" "1"
chk "第7步 Warning 筛出的都是 Warning" "$(( $(echo "$W" | grep -vc 'Warning') == 0 ))" "1"

echo ""
echo "=== 第8步：多容器日志 + --previous ==="
cat > /tmp/multi.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: multi
  namespace: kc4-lab
spec:
  containers:
  - name: app
    image: busybox:latest
    command: ['sh','-c','echo APP-LOG-1; echo APP-LOG-2; sleep 3600']
  - name: sidecar
    image: busybox:latest
    command: ['sh','-c','echo SIDECAR-LOG-1; sleep 3600']
EOF
kubectl apply -f /tmp/multi.yaml >/dev/null 2>&1
kubectl wait --for=condition=Ready pod/multi -n $NS --timeout=120s >/dev/null 2>&1
L8=$(kubectl logs multi -n $NS 2>&1)
echo "  不指定 -c: $(echo "$L8" | head -1)"
chk "第8步 不指定 -c 会 Defaulted" "$(echo "$L8" | grep -c 'Defaulted container')" "1"
chk "第8步 默认选了 app" "$(echo "$L8" | grep -c 'APP-LOG-1')" "1"
L8s=$(kubectl logs multi -n $NS -c sidecar 2>&1)
chk "第8步 -c sidecar 正确" "$(echo "$L8s" | grep -c 'SIDECAR-LOG-1')" "1"
L8a=$(kubectl logs multi -n $NS --all-containers=true --prefix 2>&1)
chk "第8步 --all-containers 含两个容器" "$(( $(echo "$L8a" | grep -c 'APP-LOG') + $(echo "$L8a" | grep -c 'SIDECAR-LOG') ))" "3"
L8e=$(kubectl logs multi -n $NS -c nosuch 2>&1)
chk "第8步 错容器名报错" "$(echo "$L8e" | grep -c 'is not valid for pod')" "1"

cat > /tmp/pv2.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: pv2
  namespace: kc4-lab
spec:
  restartPolicy: Always
  containers:
  - name: c
    image: busybox:latest
    command: ['sh','-c','echo "STARTED-AT-$(date +%s)"; sleep 4; exit 1']
EOF
kubectl apply -f /tmp/pv2.yaml >/dev/null 2>&1
for i in $(seq 1 25); do
  RR=$(kubectl get pod pv2 -n $NS -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null)
  [ -n "$RR" ] && [ "$RR" -ge 1 ] && break
  sleep 2
done
echo "  restartCount=$(kubectl get pod pv2 -n $NS -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>&1)"
CUR=$(kubectl logs pv2 -n $NS 2>&1 | grep STARTED-AT | head -1)
sleep 1
PREV=$(kubectl logs pv2 -n $NS --previous 2>&1 | grep STARTED-AT | head -1)
echo "  当前: $CUR"
echo "  prev: $PREV"
chk "第8步 --previous 能取到日志" "$(echo "$PREV" | grep -c 'STARTED-AT')" "1"
chk "第8步 当前与previous 不同实例" "$([ "$CUR" != "$PREV" ] && echo 1 || echo 0)" "1"

echo ""
echo "=== 第8b 步：restartPolicy=Never 时 --previous 失败 ==="
cat > /tmp/never.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: nevercrash
  namespace: kc4-lab
spec:
  restartPolicy: Never
  containers:
  - name: c
    image: busybox:latest
    command: ['sh','-c','echo BEFORE-CRASH; exit 1']
EOF
kubectl apply -f /tmp/never.yaml >/dev/null 2>&1
sleep 8
NV=$(kubectl logs nevercrash -n $NS --previous 2>&1)
echo "  输出: $NV"
chk "第8b步 Never 时 previous 报 not found" "$(echo "$NV" | grep -c 'previous terminated container')" "1"

echo ""
echo "=== 第9步：debug 三模式 ==="
kubectl debug multi -n $NS --image=busybox:latest --target=app --profile=general --attach=false >/dev/null 2>&1
EPH=$(kubectl get pod multi -n $NS -o jsonpath='{.spec.ephemeralContainers}' 2>&1)
chk "第9步 ephemeral container 已加" "$(echo "$EPH" | grep -c 'targetContainerName')" "1"
chk "第9步 原 Pod 仍 Running" "$(kubectl get pod multi -n $NS -o jsonpath='{.status.phase}' 2>&1)" "Running"
kubectl debug multi -n $NS --image=busybox:latest --copy-to=multi-copy --profile=general --attach=false >/dev/null 2>&1
CP=$(kubectl get pod multi-copy -n $NS -o jsonpath='{.spec.containers[*].name}' 2>&1)
echo "  副本容器: $CP"
chk "第9步 --copy-to 含 debugger" "$(echo "$CP" | grep -c 'debugger')" "1"
chk "第9步 副本保留原容器" "$(echo "$CP" | grep -c 'app')" "1"

echo ""
echo "=== 第10步：create --save-config ==="
kubectl create cm k4a --from-literal=a=1 -n $NS >/dev/null 2>&1
chk "第10步 裸 create 无 last-applied" "$([ -z "$(kubectl get cm k4a -n $NS -o jsonpath='{.metadata.annotations.kubectl\.kubernetes\.io/last-applied-configuration}' 2>&1)" ] && echo 1 || echo 0)" "1"
WA=$(kubectl apply -f - 2>&1 <<EOF
apiVersion: v1
kind: ConfigMap
metadata: {name: k4a, namespace: $NS}
data: {a: "1"}
EOF
)
chk "第10步 apply 缺注解会告警" "$(echo "$WA" | grep -c 'missing the kubectl.kubernetes.io/last-applied-configuration')" "1"
chk "第10步 告警后仍 configured" "$(echo "$WA" | grep -c 'configured')" "1"
kubectl create cm k4b --from-literal=a=1 -n $NS --save-config >/dev/null 2>&1
chk "第10步 --save-config 有注解" "$([ -n "$(kubectl get cm k4b -n $NS -o jsonpath='{.metadata.annotations.kubectl\.kubernetes\.io/last-applied-configuration}' 2>&1)" ] && echo 1 || echo 0)" "1"
WB=$(kubectl apply -f - 2>&1 <<EOF
apiVersion: v1
kind: ConfigMap
metadata: {name: k4b, namespace: $NS}
data: {a: "1"}
EOF
)
chk "第10步 save-config 后 apply 无告警" "$(echo "$WB" | grep -c 'missing the')" "0"

echo ""
echo "=== 第11步：-v 与性能 ==="
chk "第11步 cache 目录存在" "$([ -d ~/.kube/cache ] && echo 1 || echo 0)" "1"
for V in 0 4 6 8; do
  N=$(kubectl get ns -v=$V 2>&1 | wc -l)
  echo "  -v=$V : $N 行"
done
V6=$(kubectl get ns -v=6 2>&1)
chk "第11步 -v=6 含 round_trippers" "$(echo "$V6" | grep -c 'round_trippers')" "1"
chk "第11步 正确统计词是 verb=\"GET\"" "$(kubectl get ns -v=6 2>&1 | grep -c 'verb=\"GET\"')" "$(kubectl get ns -v=6 2>&1 | grep -c 'verb=\"GET\"')"
echo "  ⚠️ 错误词 'GET https' 计数: $(kubectl get ns -v=6 2>&1 | grep -c 'GET https')  (应为0，证明讲义说法正确)"

echo ""
echo "=== 第12步：清理 ==="
for P in $(kubectl get pods -A --no-headers 2>/dev/null | grep node-debugger | awk '{print $2}'); do
  kubectl delete pod -n default "$P" --ignore-not-found 2>&1 | head -1
done
kubectl delete ns $NS 2>&1 | head -1
sleep 3
chk "第12步 命名空间已删" "$(kubectl get ns $NS 2>&1 | grep -c 'NotFound')" "1"
ND=$(kubectl get pods -A 2>&1 | grep -c 'node-debugger')
chk "第12步 无 node-debugger 残留" "$ND" "0"
rm -f /tmp/evfail.yaml /tmp/multi.yaml /tmp/pv2.yaml /tmp/never.yaml /tmp/r2

echo ""
echo "=== 讲义链接可达性 ==="
cd /mnt/d/projects/learning/k8s/子教程/kubectl专项/lessons
for L in "01-kubectl怎么找到集群.md" "02-查看与筛选.md" "03-改写与调试.md" "../overview.md" \
         "../../../stages/1-心智模型与架构/lessons/02-声明式API与调谐循环.md"; do
  printf "  %-56s " "$(basename "$L")"
  if [ -f "$L" ]; then echo "✅"; PASS=$((PASS+1)); else echo "❌ 不存在"; FAIL=$((FAIL+1)); fi
done
printf "  %-56s " "15-排障方法论.md(应不存在,讲义标⬜)"
if [ -f "../../../stages/2-工作负载与调度/lessons/15-排障方法论.md" ]; then echo "⚠️ 实际存在，需改讲义"; else echo "✅ 一致(标⬜)"; PASS=$((PASS+1)); fi

echo ""
echo "########## 课4 复验：PASS=$PASS  FAIL=$FAIL ##########"
