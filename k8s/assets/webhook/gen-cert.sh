#!/usr/bin/env bash
set -eu
# 生成 webhook 自签证书 + 用 K8s CA 签发（演示 CSR 流程）
# 教学目的：展示「webhook 必须 HTTPS，且 CA bundle 必须写进 webhook 配置」
NS=${NS:-webhooklab}
SVC=${SVC:-admission-webhook}
OUT=${OUT:-/tmp/webhookcerts}
mkdir -p "$OUT"
cd "$OUT"

echo "===== 1. 生成私钥 ====="
openssl genrsa -out server-key.pem 2048 2>/dev/null

echo "===== 2. 生成 CSR（CN 必须是 service 的 DNS 名）====="
cat > csr.conf <<EOF
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
prompt = no
[req_distinguished_name]
CN = $SVC.$NS.svc
[v3_req]
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[alt_names]
DNS.1 = $SVC.$NS.svc
DNS.2 = $SVC.$NS.svc.cluster.local
DNS.3 = localhost
IP.1 = 127.0.0.1
EOF
openssl req -new -key server-key.pem -out server.csr -config csr.conf 2>/dev/null
echo "  CSR 生成完成，CN=$SVC.$NS.svc"

echo "===== 3. 提交到 K8s CA 签发（演示真实 CSR 流程）====="
cat <<EOF | kubectl apply -f - >/dev/null 2>&1
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: ${SVC}.${NS}
spec:
  request: $(base64 -w0 < server.csr)
  signerName: kubernetes.io/kubelet-serving
  usages:
  - digital signature
  - key encipherment
  - server auth
EOF

echo "===== 4. 批准 CSR ====="
kubectl certificate approve "${SVC}.${NS}" 2>&1 | tail -1

echo "===== 5. 取回签发的证书 ====="
for i in $(seq 1 10); do
  kubectl get csr "${SVC}.${NS}" -o jsonpath='{.status.certificate}' 2>/dev/null | base64 -d > server-cert.pem 2>/dev/null || true
  if [ -s server-cert.pem ]; then break; fi
  sleep 1
done
if [ ! -s server-cert.pem ]; then
  echo "  [教学要点] K8s CA 拒绝签发，原因见下："
  kubectl get csr "${SVC}.${NS}" -o jsonpath='  {.status.conditions[?(@.type=="Failed")].message}{"\n"}' 2>/dev/null
  echo "  → kubernetes.io/kubelet-serving 只签 subject O=system:nodes 的 CSR（给 kubelet 用），"
  echo "    而 kind 集群未启用 kubernetes.io/legacy-unknown 这类通用 signer。"
  echo "  → 生产做法：用 cert-manager 或企业 CA 签发；教学环境回退为自签 CA。"
  # 自签 CA：先建 CA，再用 CA 签 server 证书（caBundle 用这个 CA）
  openssl genrsa -out ca-key.pem 2048 2>/dev/null
  openssl req -x509 -new -nodes -key ca-key.pem -sha256 -days 365 \
    -subj "/CN=webhook-demo-ca" -out ca-self.pem 2>/dev/null
  cat > sign.conf <<EOF2
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[alt_names]
DNS.1 = $SVC.$NS.svc
DNS.2 = $SVC.$NS.svc.cluster.local
DNS.3 = localhost
DNS.4 = admission-webhook
IP.1 = 127.0.0.1
EOF2
  openssl x509 -req -in server.csr -CA ca-self.pem -CAkey ca-key.pem \
    -CAcreateserial -out server-cert.pem -days 365 -sha256 -extfile sign.conf 2>/dev/null
  cp ca-self.pem ca.pem
  echo "  已改用自签 CA：CN=webhook-demo-ca"
fi
echo "  证书 subject: $(openssl x509 -in server-cert.pem -noout -subject 2>/dev/null)"
echo "  证书 issuer : $(openssl x509 -in server-cert.pem -noout -issuer 2>/dev/null)"

echo "===== 6. 确定 caBundle ====="
echo "  [核心规则] caBundle 必须是「签出 server 证书的那把 CA」，不是随便拿集群 CA"
ISSUER=$(openssl x509 -in server-cert.pem -noout -issuer 2>/dev/null)
echo "  server 证书签发者: $ISSUER"
if echo "$ISSUER" | grep -qi "kubernetes"; then
  # K8s CA 签的 -> 用集群 CA
  kubectl config view --raw --minify --flatten \
    -o jsonpath='{.clusters[].cluster.certificate-authority-data}' | base64 -d > ca.pem 2>/dev/null || \
  kubectl get configmap kube-root-ca.crt -o jsonpath='{.data.ca\.crt}' > ca.pem 2>/dev/null || true
  cp ca.pem cabundle.pem
  echo "  caBundle = 集群 CA"
else
  # 自签 CA -> 用自签 CA
  cp ca-self.pem cabundle.pem
  echo "  caBundle = 自签 CA (CN=webhook-demo-ca)"
fi
echo "  caBundle subject: $(openssl x509 -in cabundle.pem -noout -subject 2>/dev/null)"
echo "  [验证] 用 caBundle 校验证书是否通过："
openssl verify -CAfile cabundle.pem server-cert.pem 2>&1 | head -1

echo "===== 7. 生成 Secret ====="
kubectl create secret generic webhook-certs -n "$NS" \
  --from-file=tls.crt=server-cert.pem \
  --from-file=tls.key=server-key.pem \
  --dry-run=client -o yaml | kubectl apply -f - 2>&1 | tail -1
echo "  caBundle(base64) 长度: $(base64 -w0 < cabundle.pem | wc -c)"
