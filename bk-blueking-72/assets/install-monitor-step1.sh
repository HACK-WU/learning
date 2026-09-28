#!/usr/bin/env bash
set -uo pipefail
BK=/root/bk72/install/blueking
V=$BK/environments/default/version.yaml
TS=$(date +%Y%m%d-%H%M%S)

echo "===== 1. 备份 version.yaml ====="
cp -a "$V" "${V}.bak-${TS}" && echo "  已备份: version.yaml.bak-${TS}"

echo ""
echo "===== 2. 改动前的相关行 ====="
grep -nE 'bk-monitor|kafka|consul|influxdb' "$V" | sed 's/^/  /'

echo ""
echo "===== 3. 执行降级 bk-monitor -> 3.8.27 ====="
sed -i 's|^\( *bk-monitor: *\)"3\.9\.0-beta\.38"|\1"3.8.27"|' "$V"
echo "  改动后的相关行:"
grep -nE 'bk-monitor' "$V" | sed 's/^/  /'

echo ""
echo "===== 4. 校验改动生效（没改动则报错）====="
if grep -qE 'bk-monitor: *"3\.8\.27"' "$V"; then
  echo "  OK  bk-monitor 已降到 3.8.27"
else
  echo "  FAIL 降级未生效，中止" >&2
  exit 1
fi

echo ""
echo "===== 5. 确认 chart 3.8.27 可拉取 ====="
rm -rf /tmp/mtest && mkdir -p /tmp/mtest
if helm pull blueking/bk-monitor --version 3.8.27 --destination /tmp/mtest 2>&1 | head -3; then
  ls -la /tmp/mtest/ 2>/dev/null | sed 's/^/  /'
  echo "  OK  chart 3.8.27 可拉取"
else
  echo "  FAIL chart 拉取失败" >&2
  exit 1
fi

echo ""
echo "===== 6. 渲染校验（build，只读不改集群）====="
cd "$BK" || exit 1
timeout 180 /root/bk72/install/bin/helmfile -f 04-bkmonitor.yaml.gotmpl build 2>&1 | tail -20 | sed 's/^/  /'
echo "  build exit=$?"
