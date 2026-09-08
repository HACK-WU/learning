#!/usr/bin/env bash
# Prometheus 3.x OTLP receiver 状态核查（阶段要求：须事实核查）
# 网上说法冲突：
#   A. --enable-feature=otlp-write-receiver（Prometheus 2.x 写法，大量教程仍在用）
#   B. --web.enable-otlp-receiver（3.x 官方文档写法）
# 用本机 v3.14.0 实测哪个能用
set -uo pipefail
NET=l9net
IMG=prom/prometheus:v3.14.0

mkcfg() { cat > /tmp/otlp-cfg.yml <<'EOF'
global:
  scrape_interval: 15s
otlp:
  promote_resource_attributes:
    - service.name
    - service.namespace
    - deployment.environment
EOF
}
mkcfg

try() { # $1=说明 $2...=flags
  local desc=$1; shift
  printf '%-52s => ' "$desc"
  local id="l9-otlp-$$-$RANDOM"
  local out
  out=$(docker run --rm --network $NET \
    -v /tmp/otlp-cfg.yml:/etc/prometheus/prometheus.yml:ro \
    --name $id $IMG \
    --config.file=/etc/prometheus/prometheus.yml \
    --storage.tsdb.path=/prometheus \
    "$@" 2>&1 | head -25)
  if echo "$out" | grep -qiE 'unknown long flag|flag provided but not defined|unknown feature'; then
    echo "REJECTED: $(echo "$out" | grep -oiE 'unknown [a-z ]*flag[^ ]*|unknown feature[^ ]*' | head -1)"
  elif echo "$out" | grep -qi 'level=error'; then
    echo "ERROR: $(echo "$out" | grep -i 'level=error' | head -1 | cut -c1-90)"
  elif echo "$out" | grep -qi 'Server is ready\|listening on'; then
    echo "ACCEPTED (正常启动)"
  else
    echo "OTHER: $(echo "$out" | head -2 | tr '\n' ' ' | cut -c1-90)"
  fi
}

echo "############ 1. flag 存在性实测（v3.14.0）############"
try "B: --web.enable-otlp-receiver"                --web.enable-otlp-receiver
try "A: --enable-feature=otlp-write-receiver"      --enable-feature=otlp-write-receiver
try "两者都给"                                      --web.enable-otlp-receiver --enable-feature=otlp-write-receiver
try "A + deltatocumulative"                        --enable-feature=otlp-deltatocumulative
try "B + deltatocumulative"                        --web.enable-otlp-receiver --enable-feature=otlp-deltatocumulative

echo
echo "############ 2. 官方 --help 里的 OTLP 相关 flag ############"
docker run --rm $IMG --help 2>&1 | grep -iE 'otlp' | head -8

echo
echo "############ 3. 官方 --help 里 otlp 相关 feature ############"
docker run --rm $IMG --help 2>&1 | grep -iE 'deltatocumulative|native-delta|otlp' | head -8
