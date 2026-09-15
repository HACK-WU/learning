#!/usr/bin/env bash
NS=webhooklab
SVC=admission-webhook
ASSETS=/mnt/d/projects/learning/k8s/assets/webhook

echo "################ 阶段 A：部署 webhook ################"
kubectl create ns $NS --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1
kubectl create configmap webhook-code -n $NS --from-file=server.py=$ASSETS/server.py --dry-run=client -o yaml | kubectl apply -f - 2>&1 | tail -1
kubectl apply -f $ASSETS/deploy.yaml 2>&1 | grep -E "created|unchanged|configured" | tail -6

echo "  --- 生成证书（走 K8s CSR 流程）---"
NS=$NS SVC=$SVC bash $ASSETS/gen-cert.sh 2>&1 | grep -E "批准|证书:|caBundle|Secret|回退" | tail -6

kubectl rollout restart deployment/$SVC -n $NS >/dev/null 2>&1
kubectl rollout status deployment/$SVC -n $NS --timeout=180s 2>&1 | tail -1

CABUNDLE=$(base64 -w0 < /tmp/webhookcerts/cabundle.pem)

echo
echo "################ 阶段 B：注册 ValidatingWebhookConfiguration ################"
cat <<EOF | kubectl apply -f - 2>&1 | tail -1
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: require-app-label
webhooks:
- name: require-app-label.k8s.io
  admissionReviewVersions: ["v1"]
  sideEffects: None
  failurePolicy: Fail
  clientConfig:
    service:
      name: $SVC
      namespace: $NS
      path: /validate
      port: 443
    caBundle: $CABUNDLE
  rules:
  - apiGroups: [""]
    apiVersions: ["v1"]
    operations: ["CREATE"]
    resources: ["pods"]
    scope: "Namespaced"
  namespaceSelector:
    matchLabels:
      webhook: enabled
  timeoutSeconds: 5
EOF

echo
echo "################ 阶段 C：验证拦截生效 ################"
kubectl create ns wh-test --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1
kubectl label ns wh-test webhook=enabled --overwrite >/dev/null 2>&1

echo "  --- C1. 不带标签的 Pod（应被拒绝）---"
kubectl run no-label --image=busybox:1.36 -n wh-test --restart=Never --command -- sleep 60 2>&1 | tail -2

echo
echo "  --- C2. 带标签的 Pod（应通过）---"
kubectl run has-label --image=busybox:1.36 -n wh-test --restart=Never \
  --labels="app.kubernetes.io/name=demo" --command -- sleep 60 2>&1 | tail -2

echo
echo "  --- C3. 未被 namespaceSelector 选中的 ns（应不受影响）---"
kubectl create ns wh-plain --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1
kubectl run plain-pod --image=busybox:1.36 -n wh-plain --restart=Never --command -- sleep 60 2>&1 | tail -1

echo
echo "################ 阶段 D：Mutating（补默认标签）################"
cat <<EOF | kubectl apply -f - 2>&1 | tail -1
apiVersion: admissionregistration.k8s.io/v1
kind: MutatingWebhookConfiguration
metadata:
  name: add-team-label
webhooks:
- name: add-team-label.k8s.io
  admissionReviewVersions: ["v1"]
  sideEffects: None
  failurePolicy: Ignore
  clientConfig:
    service:
      name: $SVC
      namespace: $NS
      path: /mutate
      port: 443
    caBundle: $CABUNDLE
  rules:
  - apiGroups: [""]
    apiVersions: ["v1"]
    operations: ["CREATE"]
    resources: ["pods"]
    scope: "Namespaced"
  namespaceSelector:
    matchLabels:
      webhook: enabled
EOF
sleep 3
kubectl run mut-demo --image=busybox:1.36 -n wh-test --restart=Never \
  --labels="app.kubernetes.io/name=demo" --command -- sleep 60 2>&1 | tail -1
# 连通性测试 pod（后面阶段 E 要用它直接打 webhook 验证故障）
kubectl run curltest --image=curlimages/curl:8.7.1 -n $NS --restart=Never --command -- sleep 600 >/dev/null 2>&1
kubectl wait --for=condition=Ready pod/curltest -n $NS --timeout=90s 2>&1 | tail -1
sleep 2
echo -n "  mut-demo 实际拿到的标签: "
kubectl get pod mut-demo -n wh-test -o jsonpath='{.metadata.labels}{"\n"}' 2>&1
echo "  --- 再验证「labels 对象完全不存在」时的双 op 分支 ---"
kubectl create ns wh-mutonly --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1
kubectl label ns wh-mutonly webhook=enabled --overwrite >/dev/null 2>&1
# 这个 ns 只挂 mutating；validating 因为缺 app 标签会拒，所以给它补上标签只测 mutating 的另一分支
kubectl run mut-min --image=busybox:1.36 -n wh-mutonly --restart=Never \
  --labels="app.kubernetes.io/name=demo" --command -- sleep 60 2>&1 | tail -1
sleep 2
echo -n "  mut-min 实际拿到的标签: "
kubectl get pod mut-min -n wh-mutonly -o jsonpath='{.metadata.labels}{"\n"}' 2>&1

echo
echo "################ 阶段 E：事故演示 failurePolicy=Fail ################"
echo "  --- E1. 让 webhook 进入 boom 模式（真实故障：返回 HTTP 500）---"
# 注意：不能用 --type merge 打 containers 数组（会把 image 等字段冲掉）
kubectl set env deployment/$SVC -n $NS WEBHOOK_MODE=boom >/dev/null 2>&1
kubectl patch deployment/$SVC -n $NS --type json \
  -p '[{"op":"replace","path":"/spec/template/spec/containers/0/args","value":["boom"]}]' 2>&1 | tail -1
kubectl rollout status deployment/$SVC -n $NS --timeout=120s 2>&1 | tail -1
echo -n "  webhook 实际启动参数: "
kubectl get deployment/$SVC -n $NS -o jsonpath='{.spec.template.spec.containers[0].args}{"\n"}'
echo "  --- 先确认故障真的发生了（应返回 500）---"
kubectl exec curltest -n $NS -- curl -sk -m 5 -o /dev/null -w "    POST /validate -> %{http_code}（500 = webhook 故障）\n" \
  -X POST -d '{}' https://admission-webhook.webhooklab.svc/validate 2>&1

echo "  --- E2. 此时在受控 ns 建 Pod（Fail 会拒绝，即使 Pod 完全合法）---"
kubectl run fail-demo --image=busybox:1.36 -n wh-test --restart=Never \
  --labels="app.kubernetes.io/name=demo" --command -- sleep 60 2>&1 | tail -2
echo "  --- E3. 不受控 ns 仍然正常（证明爆炸半径被 namespaceSelector 限制）---"
kubectl run fail-plain --image=busybox:1.36 -n wh-plain --restart=Never --command -- sleep 60 2>&1 | tail -1

echo
echo "################ 阶段 F：修复（Fail -> Ignore）################"
# 注意：patch 数组时必须带上 admissionReviewVersions，否则会被合并策略冲掉
kubectl patch validatingwebhookconfiguration require-app-label --type json \
  -p '[{"op":"replace","path":"/webhooks/0/failurePolicy","value":"Ignore"},{"op":"add","path":"/webhooks/0/admissionReviewVersions","value":["v1"]}]' 2>&1 | tail -1
sleep 3
echo "  --- webhook 仍挂，但建 Pod 应该放行（Ignore 的代价：校验被静默跳过）---"
kubectl run ignore-demo --image=busybox:1.36 -n wh-test --restart=Never --command -- sleep 60 2>&1 | tail -1
echo "  ⚠️ 注意：这个 Pod 没有 app.kubernetes.io/name 却通过了 —— 这就是 Ignore 的代价"
kubectl get pod ignore-demo -n wh-test -o jsonpath='  labels={.metadata.labels}{"\n"}' 2>&1

echo
echo "################ 阶段 G：恢复 webhook，验证回到正轨 ################"
kubectl patch deployment/$SVC -n $NS --type json \
  -p '[{"op":"replace","path":"/spec/template/spec/containers/0/args","value":["validate"]}]' 2>&1 | tail -1
kubectl rollout status deployment/$SVC -n $NS --timeout=120s 2>&1 | tail -1
kubectl patch validatingwebhookconfiguration require-app-label --type json \
  -p '[{"op":"replace","path":"/webhooks/0/failurePolicy","value":"Fail"},{"op":"add","path":"/webhooks/0/admissionReviewVersions","value":["v1"]}]' 2>&1 | tail -1
sleep 5
echo "  --- 恢复后不带标签应再被拒绝 ---"
kubectl run back-demo --image=busybox:1.36 -n wh-test --restart=Never --command -- sleep 60 2>&1 | tail -1
