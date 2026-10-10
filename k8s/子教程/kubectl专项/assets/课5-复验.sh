#!/usr/bin/env bash
# 课 5《进到容器里》复验 —— 命令原样照抄讲义第四幕，不得自行补全
PASS=0; FAIL=0
ck(){ if [ "$2" = "$3" ]; then echo "  ✅ PASS  $1 (实测=$2)"; PASS=$((PASS+1));
      else echo "  ❌ FAIL  $1 (期望=$3 实测=$2)"; FAIL=$((FAIL+1)); fi; }
ckc(){ if echo "$2" | grep -qF "$3"; then echo "  ✅ PASS  $1 (含: $3)"; PASS=$((PASS+1));
      else echo "  ❌ FAIL  $1 (期望含: $3 实测: $(echo "$2"|head -c 150))"; FAIL=$((FAIL+1)); fi; }
sec(){ echo ""; echo "### $1"; }
NS=kce-lab

echo "########## 课5 复验 ##########"
echo "context: $(kubectl config current-context)"

sec "4.1 准备环境"
kubectl create ns $NS >/dev/null 2>&1
cat <<'EOF' | kubectl apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Pod
metadata: {name: epod, namespace: kce-lab, labels: {app: e}}
spec:
  containers:
  - name: app
    image: nginx:alpine
  - name: side
    image: busybox:1.36
    command: ["sh","-c","while true; do echo tick-$(date +%s) >> /tmp/t.log; sleep 3; done"]
EOF
O=$(kubectl wait --for=condition=Ready pod/epod -n $NS --timeout=90s 2>&1)
ckc "Pod Ready" "$O" "condition met"

sec "4.2 每次 exec 是新进程（PID 不同）"
P1=$(kubectl exec -n $NS epod -c side -- sh -c 'echo PID=$$' 2>&1)
P2=$(kubectl exec -n $NS epod -c side -- sh -c 'echo PID=$$' 2>&1)
echo "  P1=$P1 / P2=$P2"
if [ "$P1" != "$P2" ]; then echo "  ✅ PASS  两次 PID 不同"; PASS=$((PASS+1));
else echo "  ❌ FAIL  两次 PID 相同"; FAIL=$((FAIL+1)); fi
O=$(kubectl exec -n $NS epod -c side -- ps -o pid,ppid,comm 2>&1)
ckc "进程树含 PID 1" "$O" "1 "

sec "4.3 退出码透传"
OUT=$(kubectl exec -n $NS epod -c side -- sh -c 'exit 42' 2>&1); RC=$?
ck "exit 42 退出码" "$RC" "42"
ckc "报错原文" "$OUT" "exit code 42"

sec "4.4 多容器静默选第一个"
O=$(kubectl exec -n $NS epod -- sh -c 'cat /etc/os-release | head -1' 2>&1)
ckc "有 Defaulted 提示" "$O" "Defaulted container"
ckc "进的是 Alpine(app)" "$O" "Alpine"
O=$(kubectl exec -n $NS epod -c side -- sh -c 'cat /etc/os-release | head -1' 2>&1)
ckc "side 无 os-release" "$O" "No such file"

sec "4.5 -i 是 stdin 开关"
O=$(echo "payload" | kubectl exec -n $NS epod -c side -- cat 2>&1)
ck "无 -i 收不到输入" "$O" ""
O=$(echo "payload" | kubectl exec -i -n $NS epod -c side -- cat 2>&1)
ck "有 -i 收到输入" "$O" "payload"

sec "4.6 不写 -- 的两种报错"
O=$(kubectl exec -n $NS epod -c side nosuchcmd 2>&1)
ckc "报错1 not supported anymore" "$O" "is not supported anymore"
O=$(kubectl exec -n $NS epod -c side ls -l /tmp 2>&1)
ckc "报错2 unknown shorthand flag" "$O" "unknown shorthand flag: 'l'"

sec "4.7 -- 之后的特殊字符"
O=$(kubectl exec -n $NS epod -c side -- sh -c 'echo a && echo b' 2>&1)
ckc "&& 由容器内 shell 解释" "$O" "a
b"
O=$(kubectl exec -n $NS epod -c side -- sh -c 'echo "hello world"' 2>&1)
ck "空格保留" "$O" "hello world"
O=$(kubectl exec -n $NS epod -c side -- sh -c 'echo $HOSTNAME' 2>&1)
ck '$HOSTNAME 容器内展开' "$O" "epod"

sec "补充：退出码 false/true"
OUT=$(kubectl exec -n $NS epod -c side -- true 2>&1); ck "true=0" "$?" "0"
OUT=$(kubectl exec -n $NS epod -c side -- false 2>&1); ck "false=1" "$?" "1"

sec "补充：容器名错 vs Pod 名错"
O=$(kubectl exec -n $NS epod -c nosuchcontainer -- true 2>&1)
ckc "容器错=BadRequest" "$O" "BadRequest"
O=$(kubectl exec -n $NS nosuchpod -- true 2>&1)
ckc "Pod错=NotFound" "$O" "NotFound"

sec "补充：命令不存在报错尾部"
O=$(kubectl exec -n $NS epod -c side -- nosuchcmd 2>&1)
ckc "executable file not found" "$O" "executable file not found"

sec "补充：-t 无 CRLF 污染（纠正速查文档错误）"
A=$(kubectl exec -n $NS epod -c side -- echo hi 2>&1 | od -c | head -1)
B=$(kubectl exec -t -n $NS epod -c side -- echo hi 2>&1 | od -c | head -1)
ck "无-t 与 有-t 字节相同" "$A" "$B"
ckc "都是 \\n 结尾" "$A" "\\n"

sec "补充：env 有 k8s 注入变量"
O=$(kubectl exec -n $NS epod -c side -- env 2>&1)
ckc "含 KUBERNETES_SERVICE_HOST" "$O" "KUBERNETES_SERVICE_HOST"

sec "4.8 多副本只进一个"
kubectl create deployment edep --image=nginx:alpine --replicas=3 -n $NS >/dev/null 2>&1
kubectl wait --for=condition=Available deployment/edep -n $NS --timeout=90s >/dev/null 2>&1
O=$(kubectl exec -n $NS deployment/edep -- sh -c 'echo 我在 $HOSTNAME' 2>&1)
ckc "进了某个 Pod" "$O" "edep-"
N=$(kubectl get pods -n $NS -l app=edep --no-headers 2>&1 | wc -l)
ck "共 3 个 Pod" "$(echo $N)" "3"

sec "4.10 清理"
kubectl delete ns $NS --timeout=120s >/dev/null 2>&1
O=$(kubectl get ns $NS 2>&1)
ckc "命名空间已删" "$O" "NotFound"

echo ""
echo "########## 课5 结果: PASS=$PASS FAIL=$FAIL ##########"
