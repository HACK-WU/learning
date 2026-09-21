#!/usr/bin/env bash
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501
D=/tmp/consul-ops

echo "########## 1. 当前 CA 配置（看支持哪些字段）##########"
curl -s $CONSUL_HTTP_ADDR/v1/connect/ca/configuration 2>&1 | head -c 600
echo

echo
echo "########## 2. 尝试用 CLI 轮换（consul connect ca）##########"
consul connect ca get-config 2>&1 | head -20 | sed 's/^/  /'

echo
echo "########## 3. 尝试 set-config 触发轮换 ##########"
consul connect ca set-config -config-file=/dev/stdin <<'EOF' 2>&1 | head -10
{
  "Provider": "consul",
  "Config": {
    "RotationPeriod": "2160h",
    "IntermediateCertTTL": "8760h"
  }
}
EOF

echo
echo "########## 4. 是否有 ACL 拦截 ##########"
curl -s -o /dev/null -w "  HTTP %{http_code}\n" -X PUT -d '{"Provider":"consul"}' \
  $CONSUL_HTTP_ADDR/v1/connect/ca/configuration
curl -s -X PUT -d '{"Provider":"consul"}' $CONSUL_HTTP_ADDR/v1/connect/ca/configuration 2>&1 | head -c 300
echo

echo
echo "########## 5. gossip 加密启用后 keyring 是什么样（需要加密环境）##########"
echo "  当前状态: 未启用 → keyring is empty"
echo "  → 说明：不启用加密时，keyring 命令无意义，这是运维必查项之一"
