#!/usr/bin/env bash
# 用途：走官方路径补齐 3 个缺失文件：keystore/truststore、cert_encrypt.key、paas3_initial_cluster.yaml
set -uo pipefail
B=/root/bk72/install/blueking
E=$B/environments/default
BIN=/root/bk72/tools/bin
D=/root/bk72/demo/blueking/environments/default/cert
export PATH="$BIN:$PATH"

echo "===== 1. 用官方脚本生成 job gateway keystore/truststore ====="
cd "$E" || exit 1
VF="$E/job-custom-values.yaml.gotmpl"
timeout 300 bash "$B/scripts/generate_jobGateway_tls_cert.sh" -f "$VF" --san "JOB_SERVER" --days 18250 --force 2>&1 | tail -12

echo ""
echo "===== 2. 检查 keystore 是否生成到 cert 目录 ====="
ls -l "$E"/cert/*.keystore "$E"/cert/*.truststore 2>/dev/null | awk '{print $9, $5}' | head -8

echo ""
echo "===== 3. 若未生成到 cert，从演示包补（官方认可通用件）====="
for f in gse_job_api_client.keystore gse_job_api_client.truststore job_server.keystore job_server.truststore; do
  if [ ! -f "$E/cert/$f" ] && [ -f "$D/$f" ]; then
    cp "$D/$f" "$E/cert/$f" && echo "已补: $f"
  elif [ -f "$E/cert/$f" ]; then
    echo "已有: $f"
  else
    echo "缺失且演示包也没有: $f"
  fi
done

echo ""
echo "===== 4. 生成 cert_encrypt.key（ee 版才用，随机密钥即可）====="
if [ ! -f "$E/cert/cert_encrypt.key" ]; then
  openssl rand -base64 32 > "$E/cert/cert_encrypt.key" 2>/dev/null
  echo "已生成 cert_encrypt.key ($(wc -c < "$E/cert/cert_encrypt.key") 字节)"
else
  echo "已存在 cert_encrypt.key"
fi

echo ""
echo "===== 5. 生成 paas3_initial_cluster.yaml（需集群，先建占位）====="
if [ ! -f "$E/paas3_initial_cluster.yaml" ]; then
  cat > "$E/paas3_initial_cluster.yaml" <<'EOF'
# paas3 初始集群信息（渲染占位，实际部署时由 create_k8s_cluster_admin_for_paas3.sh 生成）
clusters: []
EOF
  echo "已建占位 paas3_initial_cluster.yaml"
else
  echo "已存在 paas3_initial_cluster.yaml"
fi

echo ""
echo "===== 6. 最终缺失核查 ====="
for f in cert/gse_job_api_client.keystore cert/cert_encrypt.key paas3_initial_cluster.yaml; do
  [ -f "$E/$f" ] && echo "  [有] $f" || echo "  [缺] $f"
done
