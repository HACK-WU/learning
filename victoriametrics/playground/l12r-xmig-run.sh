#!/bin/bash
echo "=== [0] 先用 JSON 端点（/api/v1/import）做对照，证明端点差异 ==="
NOW=$(date +%s)
echo "--- 行协议写入 /import/prometheus ---"
printf "l12r_ep_test{ep=\"line\"} 1 %s000\n" "${NOW}" \
  | curl -s -X POST --data-binary @- "http://localhost:8480/insert/0/prometheus/api/v1/import/prometheus" -w "HTTP %{http_code}\n"
echo "--- 同样内容用 JSON 写 /api/v1/import ---"
printf '{"metric":{"__name__":"l12r_ep_test2","ep":"json"},"values":[1],"timestamps":[%s000]}\n' "${NOW}" \
  | curl -s -X POST --data-binary @- "http://localhost:8480/insert/0/prometheus/api/v1/import" -w "HTTP %{http_code}\n"
sleep 3
echo -n "行协议端点结果: "
curl -s -G "http://localhost:8481/select/0/prometheus/api/v1/export" --data-urlencode 'match[]={__name__="l12r_ep_test"}' | head -c 150
echo ""
echo -n "JSON 端点结果  : "
curl -s -G "http://localhost:8481/select/0/prometheus/api/v1/export" --data-urlencode 'match[]={__name__="l12r_ep_test2"}' | head -c 150
echo ""

echo ""
echo "=== [1] 迁移前：租户 0 的 l12r_* 样本总数与租户 4242 基线 ==="
echo -n "租户 0 l12r_* 系列数: "
curl -s -G "http://localhost:8481/select/0/prometheus/api/v1/series" \
  --data-urlencode 'match[]={__name__=~"l12r_xmig.*|l12r_tenant_journey"}' | grep -o '"__name__"' | wc -l
echo -n "租户 4242 系列数（迁移前）: "; curl -s "http://localhost:8481/select/4242/prometheus/api/v1/series/count"; echo ""

echo ""
echo "=== [2] 执行 vm-native 跨租户迁移：租户 0 -> 租户 4242 ==="
START=$(date +%s)
docker run --rm --network host victoriametrics/vmctl:v1.151.0 vm-native \
  --vm-native-src-addr=http://localhost:8481/select/0/prometheus \
  --vm-native-dst-addr=http://localhost:8480/insert/4242/prometheus \
  --vm-native-filter-time-start="2026-09-02T00:00:00Z" \
  --vm-native-filter-match='{__name__=~"l12r_xmig.*|l12r_tenant_journey"}' \
  --vm-native-step-interval=day \
  -s --disable-progress-bar 2>&1 | tail -25
END=$(date +%s)
echo "迁移耗时: $((END-START)) 秒"

echo ""
echo "=== [3] 迁移后核验：租户 4242 是否收到数据 ==="
sleep 3
echo -n "租户 4242 系列数（迁移后）: "; curl -s "http://localhost:8481/select/4242/prometheus/api/v1/series/count"; echo ""
echo "--- 租户 4242 中的 l12r 指标名 ---"
curl -s "http://localhost:8481/select/4242/prometheus/api/v1/label/__name__/values" | grep -o 'l12r_[a-z_]*' | sort -u
echo ""
echo "--- 校验 alpha idx=7 的值（应为 49） ---"
curl -s -G "http://localhost:8481/select/4242/prometheus/api/v1/export" \
  --data-urlencode 'match[]={__name__=~"l12r_xmig_alpha",idx="7"}' | head -c 300
echo ""

echo ""
echo "=== [4] 核验源租户 0 数据仍在（迁移不删源） ==="
curl -s -G "http://localhost:8481/select/0/prometheus/api/v1/export" \
  --data-urlencode 'match[]={__name__=~"l12r_xmig_alpha",idx="7"}' | head -c 300
echo ""

echo ""
echo "=== [5] 逐指标统计租户 4242 的样本数 ==="
for m in l12r_xmig_alpha l12r_xmig_beta l12r_xmig_gamma l12r_tenant_journey; do
  n=$(curl -s -G "http://localhost:8481/select/4242/prometheus/api/v1/export" \
    --data-urlencode "match[]={__name__=\"${m}\"}" | grep -o '"values":\[' | wc -l)
  echo "  ${m}: ${n} 条序列"
done
