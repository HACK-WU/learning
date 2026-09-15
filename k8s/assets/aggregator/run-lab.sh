#!/usr/bin/env bash
NS=aggregator
SVC=hello-apiserver
ASSETS=/mnt/d/projects/learning/k8s/assets/aggregator

echo "################ 阶段 0：安全清理（顺序很重要）################"
echo "  [教学要点] 必须先删 APIService 再删 namespace。"
echo "  若 APIService 指向已消失的 Service，namespace 会卡在 Terminating"
echo "  报 NamespaceDeletionDiscoveryFailure（本实验真实踩到过）。"
kubectl delete apiservice v1.hello.example.com --ignore-not-found >/dev/null 2>&1
kubectl delete ns $NS --ignore-not-found >/dev/null 2>&1
for i in $(seq 1 20); do
  kubectl get ns $NS >/dev/null 2>&1 || break
  sleep 2
done
echo "  清理完成"

echo
echo "################ 阶段 A：构建镜像并载入 kind ################"
cd $ASSETS
docker build -t hello-apiserver:latest . 2>&1 | tail -3
# kind load 在上一步 CSI 实验中失败过（ctr import 问题），改用 docker save + ctr import
docker save hello-apiserver:latest -o /tmp/hello-apiserver.tar 2>&1 | tail -1
docker exec -i k8s-c1-control-plane ctr --namespace=k8s.io images import --all-platforms --digests - < /tmp/hello-apiserver.tar 2>&1 | tail -3
echo -n "  节点上是否已有镜像: "
docker exec k8s-c1-control-plane ctr --namespace=k8s.io images list 2>/dev/null | grep -c "hello-apiserver" || echo 0

echo
echo "################ 阶段 B：部署 extension-apiserver ################"
kubectl create ns $NS --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1
NS=$NS SVC=$SVC bash $ASSETS/gen-cert.sh 2>&1 | grep -E "CA:|server cert:|SAN:|自校验|caBundle|Secret|ok$" | tail -7
kubectl apply -f $ASSETS/deploy.yaml 2>&1 | grep -E "created|configured|unchanged" | tail -7
kubectl rollout status deployment/$SVC -n $NS --timeout=180s 2>&1 | tail -1

echo
echo "################ 阶段 C：注册 APIService（聚合层核心）################"
CABUNDLE=$(base64 -w0 < /tmp/aggcerts/ca.pem)
cat <<EOF | kubectl apply -f - 2>&1 | tail -1
apiVersion: apiregistration.k8s.io/v1
kind: APIService
metadata:
  name: v1.hello.example.com
spec:
  group: hello.example.com
  version: v1
  groupPriorityMinimum: 1000
  versionPriority: 100
  insecureSkipTLSVerify: false      # 生产必须 false，靠 caBundle 校验证书
  service:
    name: $SVC
    namespace: $NS
    port: 443
  caBundle: $CABUNDLE
EOF

echo "  等待 APIService 变为 Available（最多 90s）..."
for i in $(seq 1 30); do
  AV=$(kubectl get apiservice v1.hello.example.com -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null)
  if [ "$AV" = "True" ]; then echo "  ✓ Available=True（第 ${i} 次检查）"; break; fi
  sleep 3
done
kubectl get apiservice v1.hello.example.com --no-headers 2>&1
echo "  若非 True，看详细原因："
kubectl get apiservice v1.hello.example.com -o jsonpath='  {.status.conditions[?(@.type=="Available")].message}{"\n"}' 2>&1

echo
echo "################ 阶段 D：用原生 kubectl 访问聚合 API ################"
echo "  --- D1. API 发现 ---"
kubectl api-resources --api-group=hello.example.com 2>&1 | tail -3
echo "  --- D2. 创建资源 ---"
cat <<'EOF' | kubectl apply -f - 2>&1 | tail -2
apiVersion: hello.example.com/v1
kind: Hello
metadata:
  name: world
  namespace: default
spec:
  message: "hello from aggregated apiserver"
  replicas: 3
EOF
echo "  --- D3. 读取 ---"
kubectl get hellos -n default -o wide 2>&1 | tail -3
echo "  --- D4. 取单个（看 status 是否被填充）---"
kubectl get hello world -n default -o json 2>&1 | python3 -m json.tool 2>/dev/null | head -25
echo "  --- D5. 删除 ---"
kubectl delete hello world -n default 2>&1 | tail -1
kubectl get hellos -n default 2>&1 | tail -2

echo
echo "################ 阶段 E：证明它真的是独立进程（不是 CRD）################"
echo "  --- E1. 对比 CRD：CRD 存在 etcd，聚合 API 存在我们自己的进程内存 ---"
echo -n "    CRD 里有 hello.example.com 吗: "
kubectl get crd --no-headers 2>/dev/null | grep -c "hello.example.com" || echo "0（没有）"
echo "  --- E2. 直接绕过主 API Server 访问（证明安全隐患）---"
kubectl run aggcurl --image=curlimages/curl:8.7.1 -n $NS --restart=Never --command -- sleep 300 >/dev/null 2>&1
kubectl wait --for=condition=Ready pod/aggcurl -n $NS --timeout=90s 2>&1 | tail -1
echo "    不带 token 直接访问（应被我们的 authz 拒绝 401）："
kubectl exec aggcurl -n $NS -- curl -sk -m 5 -o /dev/null -w "      -> %{http_code}\n" \
  https://hello-apiserver.aggregator.svc/apis/hello.example.com/v1/namespaces/default/hellos 2>&1
echo "    带 serviceaccount token 访问（应 200）："
TOKEN=$(kubectl exec aggcurl -n $NS -- cat /var/run/secrets/kubernetes.io/serviceaccount/token 2>/dev/null)
kubectl exec aggcurl -n $NS -- curl -sk -m 5 -H "Authorization: Bearer $TOKEN" -o /dev/null -w "      -> %{http_code}\n" \
  https://hello-apiserver.aggregator.svc/apis/hello.example.com/v1/namespaces/default/hellos 2>&1

echo
echo "################ 阶段 F：故障演示 APIService 不可用时会怎样 ################"
echo "  --- F1. 删除 APIService，kubectl 还能看到 hello 吗 ---"
kubectl delete apiservice v1.hello.example.com --ignore-not-found 2>&1 | tail -1
sleep 3
kubectl api-resources --api-group=hello.example.com 2>&1 | tail -2
echo "  --- F2. 重新注册，恢复 ---"
CABUNDLE=$(base64 -w0 < /tmp/aggcerts/ca.pem)
cat <<EOF | kubectl apply -f - 2>&1 | tail -1
apiVersion: apiregistration.k8s.io/v1
kind: APIService
metadata:
  name: v1.hello.example.com
spec:
  group: hello.example.com
  version: v1
  groupPriorityMinimum: 1000
  versionPriority: 100
  service:
    name: $SVC
    namespace: $NS
    port: 443
  caBundle: $CABUNDLE
EOF
for i in $(seq 1 20); do
  AV=$(kubectl get apiservice v1.hello.example.com -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null)
  [ "$AV" = "True" ] && { echo "  ✓ 恢复 Available=True"; break; }
  sleep 3
done
kubectl get hellos -n default 2>&1 | tail -2
