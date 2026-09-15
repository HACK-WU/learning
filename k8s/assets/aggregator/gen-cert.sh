#!/usr/bin/env bash
set -eu
# 生成聚合层 extension-apiserver 的 TLS 证书
# 关键点：CN/SAN 必须是 <svc>.<ns>.svc，因为主 API Server 用这个 DNS 名访问它
NS=${NS:-aggregator}
SVC=${SVC:-hello-apiserver}
OUT=${OUT:-/tmp/aggcerts}
mkdir -p "$OUT"
cd "$OUT"

echo "===== 1. 建自签 CA（聚合层证书必须由我们掌握 CA，因为要把 CA 写进 APIService.caBundle）====="
openssl genrsa -out ca-key.pem 2048 2>/dev/null
openssl req -x509 -new -nodes -key ca-key.pem -sha256 -days 365 \
  -subj "/CN=hello-aggregated-ca" -out ca.pem 2>/dev/null
echo "  CA: $(openssl x509 -in ca.pem -noout -subject)"

echo "===== 2. server 私钥 + CSR ====="
openssl genrsa -out server-key.pem 2048 2>/dev/null
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
DNS.3 = $SVC
DNS.4 = localhost
IP.1 = 127.0.0.1
EOF
openssl req -new -key server-key.pem -out server.csr -config csr.conf 2>/dev/null

echo "===== 3. 用 CA 签发 ====="
cat > sign.conf <<EOF
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[alt_names]
DNS.1 = $SVC.$NS.svc
DNS.2 = $SVC.$NS.svc.cluster.local
DNS.3 = $SVC
DNS.4 = localhost
IP.1 = 127.0.0.1
EOF
openssl x509 -req -in server.csr -CA ca.pem -CAkey ca-key.pem -CAcreateserial \
  -out server-cert.pem -days 365 -sha256 -extfile sign.conf 2>/dev/null
echo "  server cert: $(openssl x509 -in server-cert.pem -noout -subject)"
echo "  SAN: $(openssl x509 -in server-cert.pem -noout -ext subjectAltName 2>/dev/null | tail -1)"

echo "===== 4. 自校验（caBundle 必须能验证 server 证书）====="
openssl verify -CAfile ca.pem server-cert.pem 2>&1 | head -1

echo "===== 5. 写入 Secret ====="
kubectl create secret generic hello-apiserver-certs -n "$NS" \
  --from-file=tls.crt=server-cert.pem \
  --from-file=tls.key=server-key.pem \
  --dry-run=client -o yaml | kubectl apply -f - 2>&1 | tail -1
echo "  caBundle 长度: $(base64 -w0 < ca.pem | wc -c) bytes(base64)"
