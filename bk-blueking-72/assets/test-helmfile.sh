#!/usr/bin/env bash
# 用途：安装 helmfile 工具后，决定性验证「证书缺失时 helmfile 渲染是否失败」
set -uo pipefail
S=/root/bk72/bin/bkdl-7.2-stable.sh
BIN=/root/bk72/tools

echo "===== 1. 下载 helmfile 工具（官方 tools 组）====="
timeout 300 bash "$S" -r 7.2.19 -i "$BIN" helmfile_cmd 2>&1 | grep -vE '^\s*[#%]|%$' | tail -6

echo ""
echo "===== 2. 找到 helmfile 可执行文件 ====="
HF=$(find "$BIN" /root/bk72/install -name 'helmfile' -type f 2>/dev/null | head -1)
echo "路径: [$HF]"
if [ -n "$HF" ]; then chmod +x "$HF"; "$HF" version --short 2>&1 | head -2; fi

echo ""
echo "===== 3. 用真实 values 模板验证 readFile（helmfile 原生支持）====="
if [ -n "$HF" ]; then
  T=/tmp/hf_test; rm -rf "$T"; mkdir -p "$T"
  # 构造最小 helmfile，模拟官方模板的 readFile 行为
  cat > "$T/helmfile.yaml.gotmpl" <<'EOF'
templates:
  cm: &cm |
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: gse-cert-probe
    data:
      ca: {{ readFile "cert/gseca.crt" | b64enc }}

releases:
  - name: probe
    chart: /tmp/hf_test/empty
EOF
  mkdir -p "$T/empty/templates" "$T/cert"
  cp -a /root/bk72/cert_bak/gseca.crt "$T/cert/" 2>/dev/null

  echo "--- 3a. 证书存在 ---"
  (cd "$T" && timeout 60 "$HF" -f helmfile.yaml.gotmpl template 2>&1 | head -8)

  echo "--- 3b. 证书缺失 ---"
  rm -f "$T/cert/gseca.crt"
  (cd "$T" && timeout 60 "$HF" -f helmfile.yaml.gotmpl template 2>&1 | head -8)
fi
