#!/usr/bin/env bash
# 用途：看 setup 脚本如何生成 keystore/truststore/encrypt key（走官方路径）
set -uo pipefail
S=/root/bk72/install/blueking/scripts/setup_bkce7.sh
B=/root/bk72/install/blueking
E=$B/environments/default
OUT=/root/bk72/render_test
mkdir -p "$OUT"

echo "===== 1. setup 中 _config_job_gateway_tls_cert 完整实现 ====="
sed -n '390,410p' "$S"

echo ""
echo "===== 2. generate_jobGateway_tls_cert.sh 输出哪些文件 ====="
grep -nE 'keystore|truststore|OUTPUT|\.p12|write|tee|>' "$B/scripts/generate_jobGateway_tls_cert.sh" | grep -iE 'keystore|truststore' | head -12

echo ""
echo "===== 3. 演示包 keystore 是什么格式 ====="
D=/root/bk72/demo/blueking/environments/default/cert
for f in gse_job_api_client.keystore job_server.keystore; do
  echo "--- $f ---"
  file "$D/$f" 2>/dev/null
  ls -l "$D/$f" 2>/dev/null | awk '{print "大小:",$5}'
done

echo ""
echo "===== 4. 检查 ce 版模板是否真的需要 keystore（还是 ee 版才要）====="
grep -n 'keystore' "$E"/*-values.yaml.gotmpl 2>/dev/null | head -6
