#!/usr/bin/env bash
# 验证：回滚到【已被 revisionHistoryLimit 淘汰】的 revision，是"明确报错+退出码1"还是"静默失败"
# ✅ 实测结论（2026-10-10）：明确报错 `unable to find specified revision 1 in history`，退出码 1。
# ❌ 曾一度被误记为"退出码 0 静默失败"——凭印象写的，未回看真实报错，已更正。
NS=kcr2-lab
echo "########## 验证：已淘汰 revision 的 undo 行为 ##########"
kubectl create ns $NS >/dev/null 2>&1
kubectl create deployment r2 --image=nginx:1.25-alpine --replicas=1 -n $NS >/dev/null 2>&1
kubectl wait --for=condition=Available deployment/r2 -n $NS --timeout=120s >/dev/null 2>&1

echo "revisionHistoryLimit=$(kubectl get deployment r2 -n $NS -o jsonpath='{.spec.revisionHistoryLimit}')"
echo ""
echo "--- 连续改 13 次镜像，把 rev1~rev3 挤出去 ---"
for i in $(seq 1 13); do
  kubectl set image deployment/r2 nginx=nginx:1.2${i}-alpine -n $NS >/dev/null 2>&1
  kubectl rollout status deployment/r2 -n $NS --timeout=60s >/dev/null 2>&1
done
echo ""
echo "--- 当前 history ---"
kubectl rollout history deployment/r2 -n $NS 2>&1 | head -15
echo ""
MINREV=$(kubectl rollout history deployment/r2 -n $NS 2>&1 | awk 'NR>2{print $1}' | head -1)
echo "history 中最小 revision = $MINREV"
echo ""
if [ "$MINREV" = "1" ]; then
  echo "⚠️ rev1 仍在 history 中（未被淘汰），无法验证该场景"
else
  echo "✅ rev1 已被淘汰（最小是 $MINREV），现在测试 undo --to-revision=1"
  IMGB=$(kubectl get deployment r2 -n $NS -o jsonpath='{.spec.template.spec.containers[0].image}')
  VB=$(kubectl get deployment r2 -n $NS -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}')
  echo "  前: revision=$VB image=$IMGB"
  OUT=$(kubectl rollout undo deployment/r2 -n $NS --to-revision=1 2>&1); RC=$?
  sleep 3
  IMGA=$(kubectl get deployment r2 -n $NS -o jsonpath='{.spec.template.spec.containers[0].image}')
  VA=$(kubectl get deployment r2 -n $NS -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}')
  echo "  输出: $OUT"
  echo "  退出码: $RC"
  echo "  后: revision=$VA image=$IMGA"
  echo ""
  # ✅ 实测结论：已淘汰 revision 会【明确报错 + 退出码 1】，不是静默失败
  if [ "$RC" != "0" ] && [ "$IMGA" = "$IMGB" ] && echo "$OUT" | grep -q "unable to find specified revision"; then
    echo "✅ 证实：退出码=$RC（非0）+ 明确报错 + 镜像未变 → 是【明确失败】，退出码可信"
  else
    echo "⚠️ 与预期不符，需重新分析：RC=$RC 镜像 $IMGB → $IMGA 输出=$OUT"
  fi
fi
echo ""
echo "########## 清理 ##########"
kubectl delete ns $NS --timeout=120s >/dev/null 2>&1
echo "断言: $(kubectl get ns $NS 2>&1|head -1)"
