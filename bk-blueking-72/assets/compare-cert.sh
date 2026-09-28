#!/usr/bin/env bash
# 用途：决定性对比——真实证书与官方演示证书内容是否相同
set -uo pipefail
REAL=/root/bk72/install/blueking/environments/default/cert
DEMO=/root/bk72/demo/blueking/environments/default/cert

echo "===== 逐文件 md5 对比（相同则说明证书不绑MAC，是通用件）====="
printf "%-28s %-10s %s\n" "文件" "结果" "说明"
same=0; diff=0
for f in "$REAL"/*; do
  b=$(basename "$f"); [ "$b" = "md5.txt" ] && continue
  d="$DEMO/$b"
  if [ ! -f "$d" ]; then printf "%-28s %-10s\n" "$b" "演示缺失"; continue; fi
  m1=$(md5sum "$f" | awk '{print $1}')
  m2=$(md5sum "$d" | awk '{print $1}')
  if [ "$m1" = "$m2" ]; then
    printf "%-28s %-10s\n" "$b" "★完全相同"; same=$((same+1))
  else
    printf "%-28s %-10s\n" "$b" "不同"; diff=$((diff+1))
  fi
done
echo ""
echo "统计: 完全相同 $same 个, 不同 $diff 个"

echo ""
echo "===== gse_server.crt 是否为同一个 CA 签发 ====="
echo "--- 你的证书 ---"
openssl x509 -in "$REAL/gse_server.crt" -noout -issuer -serial 2>&1
echo "--- 演示证书 ---"
openssl x509 -in "$DEMO/gse_server.crt" -noout -issuer -serial 2>&1

echo ""
echo "===== 演示证书有效期 ====="
openssl x509 -in "$DEMO/gse_server.crt" -noout -dates 2>&1
openssl x509 -in "$DEMO/gseca.crt" -noout -dates 2>&1
