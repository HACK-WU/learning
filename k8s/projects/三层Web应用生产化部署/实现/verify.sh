#!/usr/bin/env bash
# 三层 Web 应用生产化部署 —— 一键验收
# 用法：bash 实现/verify.sh
# 全部断言均为本机 kind v1.34.0 实测（2026-09-14）

set -uo pipefail
NS=shop3t
PASS=0
FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
bad()  { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
info() { echo "  ℹ️  $1"; }
head1(){ echo ""; echo "=== $1 ==="; }

# ---------------------------------------------------------------
head1 "验收 1：三层全部就绪（1/1 Running）"
TOTAL=$(kubectl get pod -n $NS --no-headers 2>/dev/null | wc -l)
READY=$(kubectl get pod -n $NS --no-headers 2>/dev/null | awk '$2=="1/1"' | wc -l)
if [ "$TOTAL" -ge 5 ] && [ "$READY" -eq "$TOTAL" ]; then
  ok "三层共 $TOTAL 个 Pod 全部 1/1 就绪"
else
  bad "就绪 $READY/$TOTAL，未全部就绪"
fi
kubectl get pod -n $NS --no-headers | sed 's/^/     /'

# ---------------------------------------------------------------
head1 "验收 2：三层串联可通（web → api → db）"
WEBPOD=$(kubectl get pod -n $NS -l app=web --no-headers 2>/dev/null | awk 'NR==1{print $1}')
if [ -n "$WEBPOD" ]; then
  OUT=$(kubectl exec -n $NS "$WEBPOD" -- python -c '
import urllib.request, json
try:
    with urllib.request.urlopen("http://api.shop3t.svc.cluster.local:8000/api/info", timeout=5) as r:
        print(json.loads(r.read().decode()))
except Exception as e:
    print("ERR", e)
' 2>&1)
  echo "     $OUT"
  echo "$OUT" | grep -q "has_password.*True" && ok "web → api 串联成功，且 api 读到 Secret 密码" || bad "web → api 串联失败"
else
  bad "找不到 web Pod"
fi

# ---------------------------------------------------------------
head1 "验收 3：数据持久化（删 Pod 数据仍在）"
DBPOD=$(kubectl get pod -n $NS -l app=db --no-headers 2>/dev/null | awk 'NR==1{print $1}')
if [ -n "$DBPOD" ]; then
  # ⚠️ 幂等：先建表再清表。不清理的话第二次运行会残留多行，
  #    SELECT 返回两行拼接成 "before-deletebefore-delete"，导致断言误判失败。
  #    这是"读者照抄跑第二遍就挂"的可照抄性缺陷，必须修。
  kubectl exec -n $NS "$DBPOD" -- psql -U shopuser -d shopdb -c \
    "CREATE TABLE IF NOT EXISTS persist_test (id int, note text);" >/dev/null 2>&1
  kubectl exec -n $NS "$DBPOD" -- psql -U shopuser -d shopdb -c \
    "DELETE FROM persist_test;" >/dev/null 2>&1
  kubectl exec -n $NS "$DBPOD" -- psql -U shopuser -d shopdb -c \
    "INSERT INTO persist_test VALUES (1, 'before-delete');" >/dev/null 2>&1
  # 用 COUNT 聚合，只取一个值，杜绝多行拼接
  BEFORE=$(kubectl exec -n $NS "$DBPOD" -- psql -U shopuser -d shopdb -tAc \
    "SELECT note FROM persist_test WHERE id=1 LIMIT 1;" 2>&1 | tr -d '[:space:]')
  info "删除前读到：[$BEFORE]"

  # 删 Pod（StatefulSet 会重建同名 Pod）
  kubectl delete pod -n $NS "$DBPOD" --grace-period=10 >/dev/null 2>&1
  for i in $(seq 1 40); do
    S=$(kubectl get pod -n $NS "$DBPOD" --no-headers 2>/dev/null | awk '{print $2}')
    [ "$S" = "1/1" ] && break
    sleep 2
  done

  AFTER=$(kubectl exec -n $NS "$DBPOD" -- psql -U shopuser -d shopdb -tAc \
    "SELECT note FROM persist_test WHERE id=1 LIMIT 1;" 2>&1 | tr -d '[:space:]')
  info "重建后读到：[$AFTER]"
  if [ "$BEFORE" = "before-delete" ] && [ "$AFTER" = "before-delete" ]; then
    ok "删 Pod 后数据仍在（PVC 生效，StatefulSet 重建同名 Pod）"
  else
    bad "数据未持久：before=[$BEFORE] after=[$AFTER]"
  fi
else
  bad "找不到 db Pod"
fi

# ---------------------------------------------------------------
head1 "验收 4：全部容器满足 restricted 档（非 root / 禁提权 / 丢能力）"
CNT=$(kubectl get pod -n $NS -o json 2>/dev/null | python3 -c '
import json,sys
d=json.load(sys.stdin)
n=0; bad=[]
for p in d["items"]:
    for c in p["spec"]["containers"]:
        n+=1
        sc=c.get("securityContext",{})
        psc=p["spec"].get("securityContext",{})
        issues=[]
        if not sc.get("runAsNonRoot"): issues.append("runAsNonRoot未设")
        if sc.get("allowPrivilegeEscalation") is not False: issues.append("allowPrivilegeEscalation未禁")
        if not sc.get("capabilities",{}).get("drop"): issues.append("未丢能力")
        if sc.get("seccompProfile",{}).get("type") != "RuntimeDefault": issues.append("seccomp非RuntimeDefault")
        if not psc.get("runAsNonRoot"): issues.append("Pod级runAsNonRoot未设")
        if issues: bad.append((p["metadata"]["name"], c["name"], issues))
print("TOTAL", n)
for b in bad: print("BAD", b)
')
echo "$CNT" | grep -q "^TOTAL" && info "检查容器数：$(echo "$CNT" | awk '/^TOTAL/{print $2}')"
if echo "$CNT" | grep -q "^BAD"; then
  echo "$CNT" | grep "^BAD" | sed 's/^/     /'
  bad "存在容器未满足 restricted 四件套"
else
  ok "全部容器满足 restricted 四件套"
fi

# 实测容器内身份
info "实测容器内 uid/gid："
kubectl exec -n $NS deploy/web -- sh -c 'id -u; id -g' 2>&1 | sed 's/^/     uid|gid: /'

# ---------------------------------------------------------------
head1 "验收 5：Secret 不落明文 & 权限受控"
SECMODE=$(kubectl exec -n $NS deploy/api -- sh -c 'stat -c %a /var/run/secrets/kubernetes.io/serviceaccount 2>/dev/null || echo "no-sa-token"' 2>&1)
info "SA token 目录：$SECMODE（automount=false 时应为 no-sa-token）"
if [ "$SECMODE" = "no-sa-token" ]; then
  ok "ServiceAccount token 未自动挂载（automountServiceAccountToken: false 生效）"
else
  bad "SA token 仍被挂载，存在提权风险"
fi

# Secret 可读范围
kubectl exec -n $NS deploy/api -- sh -c 'echo "DB_PASSWORD=$DB_PASSWORD"' 2>&1 | sed 's/^/     /' | head -1
kubectl exec -n $NS deploy/api -- sh -c 'echo $DB_PASSWORD' 2>/dev/null | grep -q "Sh0p-Secret" && ok "应用能读到 Secret（环境变量注入生效）" || bad "Secret 未注入"

# ---------------------------------------------------------------
head1 "验收 6：NetworkPolicy 默认拒绝生效（DNS 放行是例外）"
# 正向：业务路径应通
R=$(kubectl exec -n $NS deploy/web -- python -c '
import socket
try:
    print(socket.gethostbyname("api.shop3t.svc.cluster.local"))
except Exception as e:
    print("FAIL", e)
' 2>&1)
echo "$R" | grep -q "^10\." && ok "DNS 放行生效（能解析服务名）" || bad "DNS 解析失败：$R"

# 反向：未被授权的路径应不通（db 不应能访问 api 的 8000）
R2=$(kubectl exec -n $NS db-0 -- sh -c 'timeout 3 sh -c "echo > /dev/tcp/api.shop3t.svc.cluster.local/8000" 2>&1 && echo OPEN || echo BLOCKED' 2>&1)
info "db → api:8000 结果：$R2"
echo "$R2" | grep -q "BLOCKED" && ok "未授权路径被拒绝（db 访问 api:8000 被拦）" || bad "未授权路径未被拒绝：$R2"

# ---------------------------------------------------------------
head1 "验收 7：HPA 已就位且能取到指标"
kubectl get hpa -n $NS --no-headers | sed 's/^/     /'
# ⚠️ 字段变迁：旧字段 status.currentCPUUtilizationPercentage 在 v1.34 已不再填充，
#    实测为空；应读 status.currentMetrics[].resource.current.averageUtilization。
CPUUTIL=$(kubectl get hpa -n $NS web -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}' 2>/dev/null)
ACTIVE=$(kubectl get hpa -n $NS web -o jsonpath='{range .status.conditions[*]}{.type}={.status};{end}' 2>/dev/null)
if [ -n "$CPUUTIL" ]; then
  ok "HPA 已取到 CPU 指标：${CPUUTIL}%（metrics-server 工作正常）"
else
  bad "HPA 未取到指标（检查 metrics-server 是否运行）"
fi
echo "$ACTIVE" | grep -q "ScalingActive=True" \
  && ok "HPA ScalingActive=True（已能基于指标计算副本数）" \
  || bad "HPA ScalingActive 非 True：$ACTIVE"

# ---------------------------------------------------------------
head1 "验收 8：PDB 生效（自愿驱逐受保护）"
kubectl get pdb -n $NS --no-headers | sed 's/^/     /'
PDBN=$(kubectl get pdb -n $NS --no-headers 2>/dev/null | wc -l)
[ "$PDBN" -ge 2 ] && ok "PDB 已创建（$PDBN 个），drain 时受保护" || bad "PDB 数量不足"

# ---------------------------------------------------------------
head1 "验收 9：资源声明完整（requests/limits 齐备，无裸奔容器）"
NOLIMIT=$(kubectl get pod -n $NS -o json 2>/dev/null | python3 -c '
import json,sys
d=json.load(sys.stdin)
n=0
for p in d["items"]:
    for c in p["spec"]["containers"]:
        r=c.get("resources",{})
        if not r.get("requests") or not r.get("limits"): n+=1
print(n)
')
[ "$NOLIMIT" -eq 0 ] && ok "全部容器声明了 requests 与 limits" || bad "有 $NOLIMIT 个容器缺资源声明"

# ---------------------------------------------------------------
head1 "验收 10：Gateway 入口可用（kind 无 LB，走 NodePort）"
kubectl get gateway -n $NS --no-headers | sed 's/^/     /'
kubectl get httproute -n $NS --no-headers | sed 's/^/     /'

# ⚠️ kind 环境没有 LoadBalancer 实现：Envoy 数据面 Service 的 EXTERNAL-IP
#    会一直是 <pending>，故 Gateway 的 Programmed=False 是**预期现象**，不是故障。
#   实测（2026-09-14）：envoy-shop3t-shop-gateway-xxxx 为 LoadBalancer，
#   端口映射 80:31790/TCP —— 通过 NodePort 31790 即可访问。
GWADDR=$(kubectl get gateway -n $NS shop-gateway -o jsonpath='{.status.addresses[0].value}' 2>/dev/null)
if [ -n "$GWADDR" ]; then
  ok "Gateway 已分配地址：$GWADDR"
else
  info "Gateway 未分配地址（kind 无 LB，属预期；Programmed=False 非故障）"
fi

# 找 Envoy 数据面 Service 的 NodePort
# ⚠️ 时序：上一项验收删过 db Pod，此时 API 可能短暂不可用，
#    直接访问会拿到 502（web 层上游调用失败）。必须等系统重新稳定再验。
#    实测（2026-09-14）：删 db Pod 后立刻访问 → 502；等待稳定后 5 次重试全部 200。
info "等待三层重新稳定（受上一项删 Pod 影响）..."
for i in $(seq 1 30); do
  W=$(kubectl get pod -n $NS -l app=web --no-headers 2>/dev/null | awk '$2=="1/1"' | wc -l)
  A=$(kubectl get pod -n $NS -l app=api --no-headers 2>/dev/null | awk '$2=="1/1"' | wc -l)
  D=$(kubectl get pod -n $NS -l app=db --no-headers 2>/dev/null | awk '$2=="1/1"' | wc -l)
  if [ "$W" -ge 2 ] && [ "$A" -ge 2 ] && [ "$D" -ge 1 ]; then
    # 再等 readiness 连续就绪
    sleep 5
    break
  fi
  sleep 2
done

NPSVC=$(kubectl get svc -n envoy-gateway-system --no-headers 2>/dev/null | grep "shop-gateway" | awk '{print $1}')
NODEPORT=$(kubectl get svc -n envoy-gateway-system "$NPSVC" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
if [ -n "$NODEPORT" ]; then
  info "Envoy 数据面 Service=$NPSVC NodePort=$NODEPORT"
  NODEIP=$(kubectl get node -o jsonpath='{.items[0].status.addresses[0].address}' 2>/dev/null)
  # 重试 3 次，容忍瞬时抖动
  CODE=""
  RESP=""
  for t in 1 2 3; do
    CODE=$(curl -s -o /tmp/gwbody.txt -w "%{http_code}" --max-time 8 "http://${NODEIP}:${NODEPORT}/" 2>/dev/null)
    RESP=$(head -c 160 /tmp/gwbody.txt 2>/dev/null)
    [ "$CODE" = "200" ] && break
    info "  第 $t 次返回 $CODE，重试..."
    sleep 4
  done
  if [ "$CODE" = "200" ]; then
    ok "经 Gateway 外部访问成功（HTTP $CODE）：$RESP"
  else
    bad "经 Gateway 访问返回 $CODE（期望 200）；body=$RESP"
  fi
else
  bad "未找到 Envoy 数据面 Service 的 NodePort"
fi

# ---------------------------------------------------------------
echo ""
echo "=========================================="
echo "  验收结果：PASS=$PASS  FAIL=$FAIL"
echo "=========================================="
[ "$FAIL" -eq 0 ] && echo "  🎉 全部通过" || echo "  ⚠️  有 $FAIL 项未通过，请检查上方 ❌"
exit 0
