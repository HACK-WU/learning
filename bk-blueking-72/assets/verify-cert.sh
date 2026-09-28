#!/usr/bin/env bash
# 用途：1) 修正格式后做 md5 校验  2) 从 helm repo 定位 GSE/证书相关 chart
# 幂等：可重复执行
set -uo pipefail

SSL="/mnt/d/projects/learning/bk-blueking-72/assets/ssl"
cd "$SSL" || exit 1

echo "===== 1. md5 校验（转换官方 md5.txt 格式为 md5sum 标准格式）====="
# 官方格式 "file: md5" -> 标准格式 "md5  file"
awk -F': ' '{print $2"  "$1}' md5.txt > md5.std 2>/dev/null
md5sum -c md5.std 2>&1 | tail -25
RC=${PIPESTATUS[0]}
echo "校验结论: $([ $RC -eq 0 ] && echo '全部通过' || echo '存在不一致')"

echo ""
echo "===== 2. helm repo 中与 GSE / 证书相关的 chart ====="
timeout 40 curl -sS -k "https://hub.bktencent.com/chartrepo/blueking/index.yaml" -o /tmp/idx2.yaml 2>&1
grep -oE '^  [a-z0-9-]+:' /tmp/idx2.yaml | tr -d ' :' | grep -iE 'gse|cert|license|bk-base|bkbcs' | head -15

echo ""
echo "===== 3. 全部 chart 数量复核 ====="
grep -cE '^  [a-z0-9-]+:' /tmp/idx2.yaml
