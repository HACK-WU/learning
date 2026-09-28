#!/usr/bin/env bash
set -uo pipefail
BK=/root/bk72/install/blueking
V=$BK/environments/default/version.yaml
TS=$(date +%Y%m%d-%H%M%S)

{
echo "===== 1. 备份 ====="
cp -a "$V" "${V}.bak-nodeman-${TS}" && echo "  已备份: version.yaml.bak-nodeman-${TS}"

echo ""
echo "===== 2. 改动前 ====="
grep -nE 'bk-nodeman|bk-job' "$V" | sed 's/^/  /'

echo ""
echo "===== 3. 降级 bk-nodeman 2.4.12-rc.2148 -> 2.4.11 ====="
sed -i 's|^\( *bk-nodeman: *\)"2\.4\.12-rc\.2148"|\1"2.4.11"|' "$V"
grep -nE 'bk-nodeman' "$V" | sed 's/^/  /'

echo ""
echo "===== 4. 校验生效 ====="
if grep -qE 'bk-nodeman: *"2\.4\.11"' "$V"; then echo "  OK  已降到 2.4.11"; else echo "  FAIL 降级未生效" >&2; exit 1; fi

echo ""
echo "===== 5. chart 可拉取验证 ====="
rm -rf /tmp/ntest && mkdir -p /tmp/ntest
if helm pull blueking/bk-nodeman --version 2.4.11 --destination /tmp/ntest 2>&1 | head -3; then
  ls -la /tmp/ntest/ | sed 's/^/  /'
  echo "  OK  chart 2.4.11 可拉取"
else
  echo "  FAIL chart 拉取失败" >&2; exit 1
fi

echo ""
echo "===== 6. 渲染校验 base-blueking（只读）====="
cd "$BK" || exit 1
timeout 200 /root/bk72/install/bin/helmfile -f base-blueking.yaml.gotmpl build 2>&1 | tail -15 | sed 's/^/  /'
echo "  build exit=$?"
} > /root/nodeman-prep.txt 2>&1
cat /root/nodeman-prep.txt
