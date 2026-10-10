#!/usr/bin/env bash
# 课 3 讲义复验：原样照抄讲义第四幕命令
NS=kc-l3-lab
kubectl config use-context kind-k8s-c1 >/dev/null 2>&1
echo "########## 课3 复验（基线: $(kubectl config current-context) / ns=$NS）##########"
PASS=0; FAIL=0
chk(){ if [ "$2" = "$3" ]; then echo "  ✅ $1"; PASS=$((PASS+1)); else echo "  ❌ $1  期望[$3] 实际[$2]"; FAIL=$((FAIL+1)); fi; }

# 第0步 照抄
kubectl delete ns $NS --ignore-not-found >/dev/null 2>&1
kubectl create ns $NS 2>&1
chk "第0步 命名空间创建" "$([ -n "$(kubectl get ns $NS -o name 2>/dev/null)" ] && echo 1 || echo 0)" "1"

echo ""
echo "=== 第1步：last-applied 注解 ==="
cat > /tmp/cm1.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: demo
  namespace: kc-l3-lab
data:
  a: "1"
  b: "2"
EOF
kubectl apply -f /tmp/cm1.yaml 2>&1
ANN=$(kubectl get cm demo -n kc-l3-lab -o jsonpath='{.metadata.annotations}' 2>&1)
chk "第1步 注解含 last-applied" "$(echo "$ANN" | grep -c 'last-applied-configuration')" "1"
chk "第1步 注解含空 annotations 标记" "$(echo "$ANN" | grep -c 'annotations')" "1"

echo ""
echo "=== 第2步：三方合并删字段 ==="
cat > /tmp/cm2.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: demo
  namespace: kc-l3-lab
data:
  a: "1"
EOF
kubectl apply -f /tmp/cm2.yaml 2>&1
D2=$(kubectl get cm demo -n kc-l3-lab -o jsonpath='{.data}' 2>&1)
echo "  data: $D2"
chk "第2步 b 被删除" "$(echo "$D2" | grep -c '\"b\"')" "0"
chk "第2步 a 仍在" "$(echo "$D2" | grep -c '\"a\"')" "1"

echo ""
echo "=== 第3步：别人加的字段 apply 删不掉 ==="
kubectl patch cm demo -n kc-l3-lab --type=merge -p '{"data":{"c":"3"}}' 2>&1
D3a=$(kubectl get cm demo -n kc-l3-lab -o jsonpath='{.data}' 2>&1)
echo "  patch 后: $D3a"
chk "第3步 patch 加上了 c" "$(echo "$D3a" | grep -c '\"c\"')" "1"
kubectl apply -f /tmp/cm2.yaml 2>&1
D3b=$(kubectl get cm demo -n kc-l3-lab -o jsonpath='{.data}' 2>&1)
echo "  再 apply 后: $D3b"
chk "第3步 apply 后 c 仍在（删不掉）" "$(echo "$D3b" | grep -c '\"c\"')" "1"

echo ""
echo "=== 第4步：两步删除法 ==="
cat > /tmp/cm3.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: demo
  namespace: kc-l3-lab
data:
  a: "1"
  c: "9"
EOF
kubectl apply -f /tmp/cm3.yaml 2>&1
kubectl apply -f /tmp/cm2.yaml 2>&1
D4=$(kubectl get cm demo -n kc-l3-lab -o jsonpath='{.data}' 2>&1)
echo "  data: $D4"
chk "第4步 c 被删除" "$(echo "$D4" | grep -c '\"c\"')" "0"

echo ""
echo "=== 第5步：patch 三种语义 ==="
cat > /tmp/dep.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: parr
  namespace: kc-l3-lab
spec:
  replicas: 1
  selector:
    matchLabels: {app: parr}
  template:
    metadata:
      labels: {app: parr}
    spec:
      containers:
      - name: c1
        image: nginx:alpine
        ports:
        - containerPort: 80
          name: http
        - containerPort: 443
          name: https
EOF
reset_dep() {
  kubectl delete deploy parr -n kc-l3-lab --ignore-not-found >/dev/null 2>&1
  for i in $(seq 1 30); do kubectl get deploy parr -n kc-l3-lab >/dev/null 2>&1 || break; sleep 1; done
  kubectl apply -f /tmp/dep.yaml >/dev/null 2>&1
  sleep 2
}
show() { kubectl get deploy parr -n kc-l3-lab -o jsonpath='{.spec.template.spec.containers[0].ports}' 2>&1; echo; }

reset_dep
BASE=$(show)
echo "  基线: $BASE"
chk "第5步 基线 2 端口" "$(echo "$BASE" | grep -o 'containerPort' | wc -l)" "2"

reset_dep
kubectl patch deploy parr -n kc-l3-lab --type=strategic -p '{"spec":{"template":{"spec":{"containers":[{"name":"c1","ports":[{"containerPort":8080,"name":"metrics"}]}]}}}}' 2>&1
SA=$(show)
echo "  5A: $SA"
chk "第5步 5A strategic 追加成功(3端口)" "$(echo "$SA" | grep -o 'containerPort' | wc -l)" "3"
chk "第5步 5A 新元素在最前" "$(echo "$SA" | head -c 40 | grep -c '8080')" "1"

reset_dep
MB_OUT=$(kubectl patch deploy parr -n kc-l3-lab --type=merge -p '{"spec":{"template":{"spec":{"containers":[{"name":"c1","ports":[{"containerPort":8080,"name":"metrics"}]}]}}}}' 2>&1)
echo "  5B 输出: $MB_OUT"
SB=$(show)
echo "  5B: $SB"
chk "第5步 5B merge 报错 image Required" "$(echo "$MB_OUT" | grep -c 'image: Required value')" "1"
chk "第5步 5B ports 未变(2端口)" "$(echo "$SB" | grep -o 'containerPort' | wc -l)" "2"

reset_dep
kubectl patch deploy parr -n kc-l3-lab --type=json -p '[{"op":"add","path":"/spec/template/spec/containers/0/ports/-","value":{"containerPort":8080,"name":"metrics"}}]' 2>&1
SC=$(show)
echo "  5C: $SC"
chk "第5步 5C json 追加成功(3端口)" "$(echo "$SC" | grep -o 'containerPort' | wc -l)" "3"
chk "第5步 5C 新元素在末尾" "$(echo "$SC" | tail -c 60 | grep -c '8080')" "1"

echo ""
echo "=== 第6步：diff 退出码 ==="
cat > /tmp/cmd.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata: {name: d2, namespace: kc-l3-lab}
data: {a: "1"}
EOF
kubectl apply -f /tmp/cmd.yaml >/dev/null 2>&1
DOUT=$(kubectl diff -f /tmp/cmd.yaml 2>&1); DRC=$?
echo "  无改动退出码: $DRC  输出:[$DOUT]"
chk "第6步 无改动退出码=0" "$DRC" "0"
chk "第6步 无改动无输出" "$([ -z "$DOUT" ] && echo 1 || echo 0)" "1"
sed 's/a: "1"/a: "CHANGED"/' /tmp/cmd.yaml > /tmp/cmd-chg.yaml
kubectl diff -f /tmp/cmd-chg.yaml >/dev/null 2>&1; DRC2=$?
echo "  有改动退出码: $DRC2"
chk "第6步 有改动退出码=1" "$DRC2" "1"

echo ""
echo "=== 第7步：dry-run 校验强度 ==="
COUT=$(kubectl apply -f - --dry-run=client 2>&1 <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata: {name: badfield, namespace: kc-l3-lab}
data: {x: "1"}
bogusField: true
EOF
)
echo "  client: $COUT"
chk "第7步 client 通过(不校验字段)" "$(echo "$COUT" | grep -c 'dry run')" "1"
chk "第7步 client 未报 strict decoding" "$(echo "$COUT" | grep -c 'strict decoding')" "0"
SOUT=$(kubectl apply -f - --dry-run=server 2>&1 <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata: {name: badfield, namespace: kc-l3-lab}
data: {x: "1"}
bogusField: true
EOF
)
echo "  server: $SOUT"
chk "第7步 server 报 strict decoding" "$(echo "$SOUT" | grep -c 'strict decoding error')" "1"
chk "第7步 报错含字段名" "$(echo "$SOUT" | grep -c 'bogusField')" "1"

echo ""
echo "=== 第8步：replace 缺字段 ==="
reset_dep
kubectl get deploy parr -n kc-l3-lab -o json > /tmp/parr-full.json 2>&1
python3 -c "
import json
d=json.load(open('/tmp/parr-full.json'))
d['spec']['template']['spec']['containers'][0].pop('image',None)
json.dump(d,open('/tmp/parr-noimage.json','w'))
"
ROUT=$(kubectl replace -f /tmp/parr-noimage.json 2>&1)
echo "  输出: $ROUT"
chk "第8步 replace 报 image Required" "$(echo "$ROUT" | grep -c 'image: Required value')" "1"

echo ""
echo "=== 第9步：replace --force 换 uid ==="
reset_dep
UID1=$(kubectl get deploy parr -n kc-l3-lab -o jsonpath='{.metadata.uid}' 2>&1)
FOUT=$(kubectl replace -f /tmp/dep.yaml --force 2>&1)
sleep 2
UID2=$(kubectl get deploy parr -n kc-l3-lab -o jsonpath='{.metadata.uid}' 2>&1)
echo "  before=$UID1"
echo "  after =$UID2"
chk "第9步 输出含 deleted（证明删了重建）" "$(echo "$FOUT" | grep -c 'deleted from')" "1"
chk "第9步 uid 变了" "$([ "$UID1" != "$UID2" ] && echo 1 || echo 0)" "1"

echo ""
echo "=== 第10步：Server-Side Apply ==="
kubectl delete cm d3 -n kc-l3-lab --ignore-not-found >/dev/null 2>&1
cat > /tmp/cmssa.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata: {name: d3, namespace: kc-l3-lab}
data: {a: "1"}
EOF
kubectl apply --server-side -f /tmp/cmssa.yaml 2>&1
SSA_ANN=$(kubectl get cm d3 -n kc-l3-lab -o jsonpath='{.metadata.annotations.kubectl\.kubernetes\.io/last-applied-configuration}' 2>&1)
echo "  last-applied 注解: [$SSA_ANN]"
chk "第10步 SSA 后无 last-applied 注解" "$([ -z "$SSA_ANN" ] && echo 1 || echo 0)" "1"
MF=$(kubectl get cm d3 -n kc-l3-lab -o jsonpath='{range .metadata.managedFields[*]}{.manager}{" / "}{.operation}{"\n"}{end}' 2>&1)
echo "  managedFields: $MF"
chk "第10步 有 managedFields" "$([ -n "$MF" ] && echo 1 || echo 0)" "1"
kubectl patch cm d3 -n kc-l3-lab --type=merge -p '{"data":{"a":"from-patch"}}' >/dev/null 2>&1
CONF=$(kubectl apply --server-side -f /tmp/cmssa.yaml 2>&1)
echo "  冲突输出: $(echo "$CONF" | head -1)"
chk "第10步 SSA 报 conflict" "$(echo "$CONF" | grep -c 'conflict with')" "1"
chk "第10步 冲突提示 --force-conflicts" "$(echo "$CONF" | grep -c 'force-conflicts')" "1"
FC=$(kubectl apply --server-side --force-conflicts -f /tmp/cmssa.yaml 2>&1)
chk "第10步 force-conflicts 成功" "$(echo "$FC" | grep -c 'serverside-applied')" "1"
D10=$(kubectl get cm d3 -n kc-l3-lab -o jsonpath='{.data}' 2>&1)
echo "  data: $D10"
chk "第10步 强制接管后 a=1" "$(echo "$D10" | grep -c '\"a\":\"1\"')" "1"

echo ""
echo "=== 第11步：清理 ==="
kubectl delete ns $NS 2>&1
sleep 3
chk "第11步 命名空间已删除" "$(kubectl get ns $NS 2>&1 | grep -c 'NotFound')" "1"
rm -f /tmp/cm1.yaml /tmp/cm2.yaml /tmp/cm3.yaml /tmp/dep.yaml /tmp/cmd.yaml /tmp/cmd-chg.yaml /tmp/cmssa.yaml /tmp/parr-full.json /tmp/parr-noimage.json

echo ""
echo "=== 讲义链接可达性 ==="
cd /mnt/d/projects/learning/k8s/子教程/kubectl专项/lessons
for L in "02-查看与筛选.md" "01-kubectl怎么找到集群.md" "../overview.md" \
         "../../../stages/1-心智模型与架构/lessons/02-声明式API与调谐循环.md"; do
  printf "  %-58s " "$(basename "$L")"
  if [ -f "$L" ]; then echo "✅"; PASS=$((PASS+1)); else echo "❌ 不存在"; FAIL=$((FAIL+1)); fi
done

echo ""
echo "########## 课3 复验：PASS=$PASS  FAIL=$FAIL ##########"
