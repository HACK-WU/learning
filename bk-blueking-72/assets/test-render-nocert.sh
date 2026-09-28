#!/usr/bin/env bash
# 用途：决定性验证——证书目录为空时，values 渲染是否会失败
# 方法：用 helm/helmfile 模板渲染方式模拟 readFile 行为（无集群、不下发）
set -uo pipefail
E=/root/bk72/install/blueking/environments/default
B=/root/bk72/install/blueking
CERT="$E/cert"
BAK=/root/bk72/cert_bak

echo "===== 0. 备份真实证书 ====="
rm -rf "$BAK"; mkdir -p "$BAK"
cp -a "$CERT"/. "$BAK"/ 2>/dev/null
echo "已备份 $(ls "$BAK" | wc -l) 个文件到 $BAK"

echo ""
echo "===== 1. 检查 helm/helmfile 是否可用 ====="
command -v helm >/dev/null 2>&1 && helm version --short 2>/dev/null || echo "helm 未安装"
command -v helmfile >/dev/null 2>&1 && helmfile version --short 2>/dev/null || echo "helmfile 未安装"

echo ""
echo "===== 2. 模拟 readFile 缺失行为：临时移走证书 ====="
rm -rf "$CERT"; mkdir -p "$CERT"
echo "已清空 $CERT，当前文件数: $(ls "$CERT" | wc -l)"

echo ""
echo "===== 3. 用 helm template 渲染 gse values（readFile 会怎样）====="
# 构造最小 chart 复现 readFile "cert/xxx" 的行为
TMP=/tmp/readfile_test
rm -rf "$TMP"; mkdir -p "$TMP/templates"
cat > "$TMP/Chart.yaml" <<'EOF'
apiVersion: v2
name: readfile-test
version: 0.1.0
EOF
cat > "$TMP/values.yaml" <<'EOF'
EOF
cat > "$TMP/templates/cm.yaml" <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: gse-cert-test
data:
  ca: {{ readFile "cert/gseca.crt" | b64enc | quote }}
EOF
mkdir -p "$TMP/cert"
cp -a "$BAK"/gseca.crt "$TMP/cert/" 2>/dev/null

echo "--- 3a. 证书存在时渲染 ---"
helm template test "$TMP" 2>&1 | grep -E 'ca:|Error|error' | head -3

echo "--- 3b. 证书缺失时渲染 ---"
rm -f "$TMP/cert/gseca.crt"
helm template test "$TMP" 2>&1 | grep -E 'ca:|Error|error' | head -3

echo ""
echo "===== 4. 恢复真实证书到部署目录 ====="
cp -a "$BAK"/. "$CERT"/ 2>/dev/null
echo "已恢复，cert 目录文件数: $(ls "$CERT" | wc -l)"
