#!/usr/bin/env bash
# 用途：验证「没有自己申请的证书，能否用官方演示证书搭建」
set -uo pipefail
S=/root/bk72/bin/bkdl-7.2-stable.sh
DEMO=/root/bk72/demo

echo "===== 1. 下载官方演示证书 example_cert ====="
mkdir -p "$DEMO"
timeout 180 bash "$S" -r 7.2.19 -i "$DEMO" example_cert 2>&1 | grep -vE '^\s*[#%]|%$' | tail -8

echo ""
echo "===== 2. 演示证书落在哪、有哪些文件 ====="
find "$DEMO" -iname '*.crt' -o -iname '*.key' -o -iname '*.cert' -o -iname '*.p12' 2>/dev/null | head -25

echo ""
echo "===== 3. 与真实证书的文件名对比 ====="
REAL=/root/bk72/install/blueking/environments/default/cert
echo "--- 真实证书(18个) vs 演示证书，同名文件数: ---"
if [ -d "$REAL" ]; then
  same=0; total=0
  for f in "$REAL"/*; do
    b=$(basename "$f"); total=$((total+1))
    [ "$b" = "md5.txt" ] && continue
    if find "$DEMO" -name "$b" 2>/dev/null | grep -q .; then same=$((same+1)); fi
  done
  echo "真实证书 $total 个文件中，演示证书里同名的有 $same 个"
fi

echo ""
echo "===== 4. 演示证书的 subject / 有效期（看是否与MAC绑定）====="
for f in $(find "$DEMO" -name 'gse_server.crt' -o -name 'gseca.crt' 2>/dev/null | head -3); do
  echo "--- $(basename $f) ---"
  openssl x509 -in "$f" -noout -subject -dates 2>&1
done
