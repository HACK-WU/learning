#!/usr/bin/env bash
# 用途：解压并校验蓝鲸 7.2 证书包 ssl_certificates.tar.gz
# 幂等：可重复执行
set -uo pipefail

SRC="/mnt/c/Users/v_wypgwu/Downloads/ssl_certificates.tar.gz"
DST="/mnt/d/projects/learning/bk-blueking-72/assets/ssl"

mkdir -p "$DST"
cp -f "$SRC" "$DST/" || { echo "拷贝失败，检查源路径"; exit 1; }

cd "$DST" || exit 1
tar -xzf ssl_certificates.tar.gz || { echo "解压失败"; exit 1; }

echo "===== 文件清单 ====="
ls -l

echo ""
echo "===== md5 校验（官方 md5.txt 比对）====="
md5sum -c md5.txt 2>&1 | tail -25

echo ""
echo "===== 各证书 subject 与有效期 ====="
for f in *.crt *.cert; do
  [ -f "$f" ] || continue
  echo "--- $f ---"
  openssl x509 -in "$f" -noout -subject -dates 2>&1
done

echo ""
echo "===== 私钥文件（仅确认可读，不打印内容）====="
for f in *.key; do
  [ -f "$f" ] || continue
  echo "$f : $(head -1 "$f")"
done
