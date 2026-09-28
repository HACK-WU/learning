#!/usr/bin/env bash
# 用途：从官方部署包内查找「证书用途」与「能否用演示证书」的权威依据
set -uo pipefail
B=/root/bk72/install/blueking

echo "===== 1. 部署包内是否有说明文档 ====="
find "$B" -maxdepth 2 \( -iname '*.md' -o -iname 'README*' \) 2>/dev/null | head -10

echo ""
echo "===== 2. 部署脚本里对「证书缺失」的处理（是否有校验/报错）====="
grep -rn --include='*.sh' -iE 'cert' "$B"/scripts/ 2>/dev/null | head -15

echo ""
echo "===== 3. license 相关 chart 是否存在（证书绑license服务）====="
ls "$B"/charts/ 2>/dev/null | grep -iE 'license|gse|job' | head -10

echo ""
echo "===== 4. 哪些 values 引用了 license/platform 证书 ====="
grep -rln --include='*-values.yaml.gotmpl' -E 'license_cert|platform\.cert|platform\.key' "$B"/environments/ 2>/dev/null | head -10

echo ""
echo "===== 5. 这些引用的具体写法 ====="
for f in $(grep -rln --include='*-values.yaml.gotmpl' -E 'license_cert|platform\.cert' "$B"/environments/ 2>/dev/null | head -5); do
  echo "--- $(basename $f) ---"
  grep -nE 'license_cert|platform\.cert|platform\.key' "$f" | head -6
done
