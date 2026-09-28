#!/usr/bin/env bash
# 用途：查 3 个缺失文件由谁生成（走官方路径补齐）
set -uo pipefail
B=/root/bk72/install/blueking
E=$B/environments/default
S=$B/scripts/setup_bkce7.sh

echo "===== 1. cert_encrypt.key 由谁生成 ====="
grep -rn 'cert_encrypt' "$B"/scripts/ "$E"/*.gotmpl 2>/dev/null | grep -v '^Binary' | head -6

echo ""
echo "===== 2. gse_job_api_client.keystore 由谁生成 ====="
grep -rn 'keystore' "$B"/scripts/ 2>/dev/null | head -8

echo ""
echo "===== 3. paas3_initial_cluster.yaml 由谁生成 ====="
grep -rn 'paas3_initial_cluster\|initial_cluster' "$B"/scripts/ 2>/dev/null | head -8

echo ""
echo "===== 4. 你的证书包里有没有 keystore/encrypt 类文件 ====="
ls -1 "$E/cert" | head -25

echo ""
echo "===== 5. 演示证书包里有没有 ====="
ls -1 /root/bk72/demo/blueking/environments/default/cert 2>/dev/null | head -25
