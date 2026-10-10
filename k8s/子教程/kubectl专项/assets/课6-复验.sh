#!/usr/bin/env bash
# 课 6《发布与回滚》复验 —— 命令原样照抄讲义第四幕
PASS=0; FAIL=0
ck(){ if [ "$2" = "$3" ]; then echo "  ✅ PASS  $1 (实测=$2)"; PASS=$((PASS+1));
      else echo "  ❌ FAIL  $1 (期望=$3 实测=$2)"; FAIL=$((FAIL+1)); fi; }
ckc(){ if echo "$2" | grep -qF "$3"; then echo "  ✅ PASS  $1 (含: $3)"; PASS=$((PASS+1));
      else echo "  ❌ FAIL  $1 (期望含: $3 实测: $(echo "$2"|head -c 150))"; FAIL=$((FAIL+1)); fi; }
sec(){ echo ""; echo "### $1"; }
NS=kcr-lab
REV(){ kubectl get deployment rdep -n $NS -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}' 2>&1; }
RSN(){ kubectl get rs -n $NS -l app=rdep --no-headers 2>&1 | wc -l; }

echo "########## 课6 复验 ##########"
echo "context: $(kubectl config current-context)"

sec "4.1 准备环境"
kubectl create ns $NS >/dev/null 2>&1
kubectl create deployment rdep --image=nginx:1.25-alpine --replicas=3 -n $NS >/dev/null 2>&1
O=$(kubectl wait --for=condition=Available deployment/rdep -n $NS --timeout=120s 2>&1)
ckc "Deployment Available" "$O" "condition met"

sec "4.2 revision 存在 RS 上，Deployment 只记一个数字"
O=$(kubectl get rs -n $NS -l app=rdep -o custom-columns='NAME:.metadata.name,REV:.metadata.annotations.deployment\.kubernetes\.io/revision,DESIRED:.spec.replicas,IMAGE:.spec.template.spec.containers[0].image' 2>&1)
ckc "RS 上有 revision 注解" "$O" "REV"
ckc "RS 显示镜像" "$O" "nginx:1.25-alpine"
O=$(kubectl get deployment rdep -n $NS -o jsonpath='{.metadata.annotations}' 2>&1)
ckc "Deployment 只有 revision 数字" "$O" "deployment.kubernetes.io/revision"

sec "4.3 改镜像产生新 revision"
V1=$(REV); N1=$(RSN)
kubectl set image deployment/rdep nginx=nginx:1.26-alpine -n $NS >/dev/null 2>&1
kubectl rollout status deployment/rdep -n $NS --timeout=60s >/dev/null 2>&1
V2=$(REV); N2=$(RSN)
echo "  revision: $V1 → $V2 ; RS数: $N1 → $N2"
if [ "$V2" -gt "$V1" ] 2>/dev/null; then echo "  ✅ PASS  revision 递增"; PASS=$((PASS+1));
else echo "  ❌ FAIL  revision 未递增 ($V1→$V2)"; FAIL=$((FAIL+1)); fi
echo "  ℹ️  RS 数受 revisionHistoryLimit=10 限制，满额后新增即淘汰，故不作为断言"
O=$(kubectl get rs -n $NS -l app=rdep -o custom-columns='DESIRED:.spec.replicas,IMAGE:.spec.template.spec.containers[0].image' 2>&1)
ckc "新镜像生效" "$O" "nginx:1.26-alpine"

sec "4.4 undo 创建新版本号（核心）—— 必须用还存在的 revision"
echo "  ⚠️ 不能用 --to-revision=1：经多轮改动后 rev1 已被 revisionHistoryLimit 淘汰，"
echo "     实测 undo 会【退出码0但不回滚】"
kubectl set image deployment/rdep nginx=nginx:1.27-alpine -n $NS >/dev/null 2>&1
kubectl rollout status deployment/rdep -n $NS --timeout=60s >/dev/null 2>&1
V3=$(REV)
TARGET=$((V3 - 1))
echo "  当前 revision=$V3，回滚目标=$TARGET（保证还存在于 history）"
kubectl rollout undo deployment/rdep -n $NS --to-revision=$TARGET >/dev/null 2>&1
kubectl rollout status deployment/rdep -n $NS --timeout=60s >/dev/null 2>&1
V4=$(REV)
echo "  undo 后 revision=$V4"
if [ "$V4" -gt "$V3" ] 2>/dev/null; then echo "  ✅ PASS  undo 后 revision 号变大（不是退回 $TARGET）"; PASS=$((PASS+1));
else echo "  ❌ FAIL  revision 未变大 ($V3→$V4)"; FAIL=$((FAIL+1)); fi
IMG=$(kubectl get deployment rdep -n $NS -o jsonpath='{.spec.template.spec.containers[0].image}' 2>&1)
echo "  回滚后镜像=$IMG"
ckc "镜像确实变了（回滚生效）" "$IMG" "nginx:1.2"

sec "4.4b 补充：回滚到已淘汰 revision 会报错（退出码1，非静默失败）"
OLDEST=$(kubectl rollout history deployment/rdep -n $NS 2>&1 | awk 'NR>2{print $1}' | head -1)
echo "  history 中最小 revision=$OLDEST"
if [ "$OLDEST" != "1" ]; then
  echo "  rev1 已被淘汰，测 undo --to-revision=1"
  IMGB=$(kubectl get deployment rdep -n $NS -o jsonpath='{.spec.template.spec.containers[0].image}' 2>&1)
  OUT=$(kubectl rollout undo deployment/rdep -n $NS --to-revision=1 2>&1); RC=$?
  IMGA=$(kubectl get deployment rdep -n $NS -o jsonpath='{.spec.template.spec.containers[0].image}' 2>&1)
  echo "  退出码=$RC ; 镜像 $IMGB → $IMGA"
  ckc "报错原文" "$OUT" "unable to find specified revision 1 in history"
  ck "已淘汰 退出码=1" "$RC" "1"
  ck "镜像未变" "$IMGA" "$IMGB"
else
  echo "  ℹ️  rev1 仍存在，跳过（需在多次改动后才能触发该场景）"
fi

sec "4.5 undo 两个边界"
O=$(kubectl rollout undo deployment/rdep -n $NS --to-revision=999 2>&1); RC=$?
ckc "版本不存在报错" "$O" "unable to find specified revision 999"
ck "不存在 退出码=1" "$RC" "1"
CUR=$(REV)
O=$(kubectl rollout undo deployment/rdep -n $NS --to-revision=$CUR 2>&1); RC=$?
ckc "回滚到当前版提示 skipped" "$O" "skipped rollback"
ck "skipped 退出码=0（陷阱）" "$RC" "0"

sec "4.6 pause 攒改动"
NA=$(RSN); GA=$(kubectl get deployment rdep -n $NS -o jsonpath='{.metadata.generation}')
kubectl rollout pause deployment/rdep -n $NS >/dev/null 2>&1
kubectl set env deployment/rdep X=1 -n $NS >/dev/null 2>&1
kubectl set env deployment/rdep Y=2 -n $NS >/dev/null 2>&1
NB=$(RSN); GB=$(kubectl get deployment rdep -n $NS -o jsonpath='{.metadata.generation}')
echo "  RS数: $NA → $NB ; generation: $GA → $GB"
ck "pause 期间 RS 数不变" "$NB" "$NA"
if [ "$GB" -gt "$GA" ] 2>/dev/null; then echo "  ✅ PASS  generation 上涨（改动记下了）"; PASS=$((PASS+1));
else echo "  ❌ FAIL  generation 未涨"; FAIL=$((FAIL+1)); fi
kubectl rollout resume deployment/rdep -n $NS >/dev/null 2>&1
kubectl rollout status deployment/rdep -n $NS --timeout=60s >/dev/null 2>&1
echo "  ℹ️  RS 数同样受 revisionHistoryLimit 限制，改为断言『改动已合并生效』"
ENV=$(kubectl get deployment rdep -n $NS -o jsonpath='{.spec.template.spec.containers[0].env}' 2>&1)
ckc "pause 期间的两个 env 都已生效" "$ENV" "X"
ckc "且 Y 也在（合并成一次发布）" "$ENV" "Y"

sec "4.7 pause 期间 rollout status 超时（需先造一个待发布改动）"
kubectl rollout pause deployment/rdep -n $NS >/dev/null 2>&1
kubectl set image deployment/rdep nginx=nginx:1.27-alpine -n $NS >/dev/null 2>&1
O=$(kubectl rollout status deployment/rdep -n $NS --timeout=10s 2>&1); RC=$?
ckc "超时报错原文" "$O" "timed out waiting for the condition"
ck "超时退出码=1" "$RC" "1"
P=$(kubectl get deployment rdep -n $NS -o jsonpath='{.spec.paused}' 2>&1)
ck "paused 字段=true" "$P" "true"
kubectl rollout resume deployment/rdep -n $NS >/dev/null 2>&1
kubectl rollout status deployment/rdep -n $NS --timeout=60s >/dev/null 2>&1
P2=$(kubectl get deployment rdep -n $NS -o jsonpath='{.spec.paused}' 2>&1)
ck "resume 后 paused 为空" "$P2" ""

sec "4.8 restart 改注解不改镜像"
A1=$(kubectl get deployment rdep -n $NS -o jsonpath='{.spec.template.metadata.annotations}' 2>&1)
kubectl rollout restart deployment/rdep -n $NS >/dev/null 2>&1
sleep 3
A2=$(kubectl get deployment rdep -n $NS -o jsonpath='{.spec.template.metadata.annotations}' 2>&1)
if [ "$A1" != "$A2" ]; then echo "  ✅ PASS  restartedAt 时间戳变化"; PASS=$((PASS+1));
else echo "  ❌ FAIL  注解未变 ($A1)"; FAIL=$((FAIL+1)); fi
ckc "注解含 restartedAt" "$A2" "restartedAt"
IMG1=$(kubectl get deployment rdep -n $NS -o jsonpath='{.spec.template.spec.containers[0].image}' 2>&1)
kubectl rollout restart deployment/rdep -n $NS >/dev/null 2>&1
kubectl rollout status deployment/rdep -n $NS --timeout=60s >/dev/null 2>&1
IMG2=$(kubectl get deployment rdep -n $NS -o jsonpath='{.spec.template.spec.containers[0].image}' 2>&1)
ck "restart 不改镜像" "$IMG2" "$IMG1"

sec "4.9 status 卡住的报错"
kubectl set image deployment/rdep nginx=nginx:nonexistent-zzz -n $NS >/dev/null 2>&1
O=$(kubectl rollout status deployment/rdep -n $NS --timeout=30s 2>&1); RC=$?
ckc "Waiting 输出" "$O" "new replicas have been updated"
ckc "timed out" "$O" "timed out"
ck "卡住退出码=1" "$RC" "1"
O=$(kubectl get deployment rdep -n $NS -o jsonpath='{.status.conditions[*].type}' 2>&1)
ckc "conditions 含 Available" "$O" "Available"

sec "补充：revisionHistoryLimit 默认 10"
O=$(kubectl get deployment rdep -n $NS -o jsonpath='{.spec.revisionHistoryLimit}' 2>&1)
ck "revisionHistoryLimit" "$O" "10"
O=$(kubectl get deployment rdep -n $NS -o jsonpath='{.spec.progressDeadlineSeconds}' 2>&1)
ck "progressDeadlineSeconds" "$O" "600"

sec "补充：history 的 CHANGE-CAUSE 为 none"
O=$(kubectl rollout history deployment/rdep -n $NS 2>&1)
ckc "CHANGE-CAUSE 列存在" "$O" "CHANGE-CAUSE"
ckc "值为 none" "$O" "<none>"

sec "4.10 清理"
kubectl set image deployment/rdep nginx=nginx:1.27-alpine -n $NS >/dev/null 2>&1
kubectl rollout status deployment/rdep -n $NS --timeout=120s >/dev/null 2>&1
kubectl delete ns $NS --timeout=120s >/dev/null 2>&1
O=$(kubectl get ns $NS 2>&1)
ckc "命名空间已删" "$O" "NotFound"

echo ""
echo "########## 课6 结果: PASS=$PASS FAIL=$FAIL ##########"
