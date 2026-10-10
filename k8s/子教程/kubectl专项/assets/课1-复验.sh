#!/usr/bin/env bash
# 课1 复验 v2：修正脚本缺陷 + 锁定基线 context
echo "########## 课1 复验 v2（锁定 k8s-c1 基线）##########"
PASS=0; FAIL=0
chk(){ if [ "$2" = "$3" ]; then echo "  ✅ $1"; PASS=$((PASS+1)); else echo "  ❌ $1  期望[$3] 实际[$2]"; FAIL=$((FAIL+1)); fi; }

# 强制锁基线（修正 v1 缺陷：context 漂移）
kubectl config use-context kind-k8s-c1 >/dev/null 2>&1
echo "基线 context: $(kubectl config current-context)"
echo ""

echo "=== 第1步：版本 ==="
chk "version --client 含 v1.34.0" "$(kubectl version --client 2>&1 | head -1 | grep -c 'v1.34.0')" "1"
chk "version --short 报 unknown flag" "$(kubectl version --short 2>&1 | grep -c 'unknown flag')" "1"
chk "version -o yaml 可用" "$(kubectl version -o yaml 2>&1 | grep -c gitVersion)" "2"

echo ""
echo "=== 第2步：找到集群 ==="
CC=$(kubectl config current-context 2>&1)
chk "current-context=k8s-c1" "$CC" "kind-k8s-c1"
chk "context 数=4" "$(kubectl config get-contexts --no-headers 2>&1 | wc -l)" "4"

echo ""
echo "=== 第3步：集群地址 ==="
SRV=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>&1)
echo "  server: $SRV"
chk "server 格式正确" "$(echo "$SRV" | grep -cE '^https://127\.0\.0\.1:[0-9]+$')" "1"

echo ""
echo "=== 第4步：资源清单（锁定 c1）==="
AR=$(kubectl api-resources --no-headers 2>&1 | wc -l)
AV=$(kubectl api-versions 2>&1 | wc -l)
echo "  api-resources=$AR (讲义68)  api-versions=$AV (讲义24)"
chk "api-resources=68" "$([ "$AR" = "68" ] && echo 1 || echo 0)" "1"
chk "api-versions=24"  "$([ "$AV" = "24" ] && echo 1 || echo 0)" "1"
# 修正 v1 缺陷：用 --api-group="" 精确取核心组 pods
PO=$(kubectl api-resources --no-headers --api-group="" 2>&1 | awk '$1=="pods"{print $2}')
echo "  pods 缩写(核心组)=[$PO]"
chk "pods 缩写=po" "$PO" "po"
# 验证讲义新增的"同名不同组"坑
DUP=$(kubectl api-resources --no-headers 2>&1 | awk '$1=="pods"' | wc -l)
echo "  pods 出现次数(全组)=$DUP (讲义说 2)"
chk "pods 同名两行" "$([ "$DUP" = "2" ] && echo 1 || echo 0)" "1"

echo ""
echo "=== 第5步：TYPE 等价 ==="
A=$(kubectl get pods -n kube-system --no-headers 2>&1 | wc -l)
B=$(kubectl get pod  -n kube-system --no-headers 2>&1 | wc -l)
C=$(kubectl get po   -n kube-system --no-headers 2>&1 | wc -l)
echo "  pods=$A pod=$B po=$C"
chk "三者相等" "$([ "$A" = "$B" ] && [ "$B" = "$C" ] && echo 1 || echo 0)" "1"

echo ""
echo "=== 第6步：作用域 ==="
NF=$(kubectl api-resources --no-headers 2>&1 | awk '$4=="false"' | wc -l)
chk "集群级=10" "$([ "$NF" = "10" ] && echo 1 || echo 0)" "1"
chk "nodes 加 -n 有输出" "$([ "$(kubectl get nodes -n kube-system --no-headers 2>&1 | wc -l)" -ge 1 ] && echo 1 || echo 0)" "1"
# 修正 v1/v2 缺陷：kubectl get --no-headers 无资源时会输出 "No resources found" 一行提示，
# wc -l 会把它算成 1。必须过滤掉提示行再计数（既有铁律：统计别把提示/错误行计入）。
count_pods(){ kubectl get pods $1 --no-headers 2>/dev/null | grep -v "No resources found" | wc -l; }
DEF=$(count_pods "")
KS=$(count_pods "-n kube-system")
echo "  default=$DEF  kube-system=$KS"
chk "default 无 Pod（c1 基线）" "$([ "$DEF" = "0" ] && echo 1 || echo 0)" "1"
chk "kube-system 有 Pod" "$([ "$KS" -ge 1 ] && echo 1 || echo 0)" "1"
chk "不加 -n 落到 default（输出含 default）" "$(kubectl get pods 2>&1 | grep -c 'default namespace')" "1"

echo ""
echo "=== 第7步：explain ==="
chk "存在字段有 FIELD" "$([ "$(kubectl explain pod.spec.containers.resources 2>&1 | grep -c 'FIELD:')" -ge 1 ] && echo 1 || echo 0)" "1"
chk "不存在字段无 FIELD" "$(kubectl explain pod.spec.notexistfield 2>&1 | grep -c 'FIELD:')" "0"

echo ""
echo "=== 第8步：切 context ==="
OLD=$(kubectl config current-context 2>&1)
kubectl config use-context kind-k8s-c1 >/dev/null 2>&1
chk "切后能拿节点" "$([ "$(kubectl get nodes --no-headers 2>&1 | wc -l)" -ge 1 ] && echo 1 || echo 0)" "1"
kubectl config use-context "$OLD" >/dev/null 2>&1
chk "能还原" "$(kubectl config current-context 2>&1)" "$OLD"
chk "不存在 context 报错" "$(kubectl config use-context no-such-ctx-xyz 2>&1 | grep -c 'no context exists')" "1"

echo ""
echo "=== 讲义链接可达性 ==="
cd /mnt/d/projects/learning/k8s/子教程/kubectl专项/lessons
for L in "../../../web-index/INDEX.md" "../../../00-环境准备.md" "../../../09-排障速查手册.md" \
         "../../../stages/1-心智模型与架构/lessons/02-声明式API与调谐循环.md" "../overview.md"; do
  printf "  %-68s " "$(basename "$L")"
  if [ -f "$L" ]; then echo "✅"; PASS=$((PASS+1)); else echo "❌"; FAIL=$((FAIL+1)); fi
done

echo ""
echo "########## 复验 v2：PASS=$PASS  FAIL=$FAIL ##########"
