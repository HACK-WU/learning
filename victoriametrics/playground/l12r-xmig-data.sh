#!/bin/bash
# 关键认知：/api/v1/import/prometheus 是「纯文本行协议」端点，不是 JSON 端点。
# 喂 JSON 会返回 204 但数据全部丢弃（只在 vminsert 日志里有 error）。
# 正确格式：metric_name{label="value"} value timestamp_ms

SRC="http://localhost:8480/insert/0/prometheus/api/v1/import/prometheus"
NOW=$(date +%s)

echo "=== [1] 用正确的行协议写入 l12r_xmig_alpha / beta / tenant_journey ==="
for m in l12r_xmig_alpha l12r_xmig_beta l12r_xmig_gamma; do
  payload=""
  for i in $(seq 0 29); do
    ts=$(( (NOW - 1800 + i*60) * 1000 ))
    val=$((i * 7))
    payload="${payload}${m}{tenant_src=\"0\",idx=\"${i}\"} ${val} ${ts}\n"
  done
  printf "${payload}" | curl -s -X POST --data-binary @- "${SRC}" -w "  ${m} -> HTTP %{http_code}\n"
done

payload=""
for i in $(seq 0 29); do
  ts=$(( (NOW - 1800 + i*60) * 1000 ))
  payload="${payload}l12r_tenant_journey{stage=\"src0\",idx=\"${i}\"} ${i} ${ts}\n"
done
printf "${payload}" | curl -s -X POST --data-binary @- "${SRC}" -w "  l12r_tenant_journey -> HTTP %{http_code}\n"

echo ""
echo "=== [2] 等 3 秒后用 export 验证（不用 query，绕开 staleness） ==="
sleep 3
echo -n "l12r_xmig_alpha 样本数: "
curl -s -G "http://localhost:8481/select/0/prometheus/api/v1/export" \
  --data-urlencode 'match[]={__name__=~"l12r_xmig_alpha"}' | grep -c '"values"'
echo -n "l12r_xmig_beta  样本数: "
curl -s -G "http://localhost:8481/select/0/prometheus/api/v1/export" \
  --data-urlencode 'match[]={__name__=~"l12r_xmig_beta"}' | grep -c '"values"'
echo -n "l12r_tenant_journey 样本数: "
curl -s -G "http://localhost:8481/select/0/prometheus/api/v1/export" \
  --data-urlencode 'match[]={__name__=~"l12r_tenant_journey"}' | grep -c '"values"'

echo ""
echo "=== [3] 校验样本值（alpha 第 idx=7 的应为 49） ==="
curl -s -G "http://localhost:8481/select/0/prometheus/api/v1/export" \
  --data-urlencode 'match[]={__name__=~"l12r_xmig_alpha",idx="7"}' | head -c 300
echo ""

echo ""
echo "=== [4] 指标名已注册 ==="
curl -s "http://localhost:8481/select/0/prometheus/api/v1/label/__name__/values" | grep -o 'l12r_[a-z_]*' | sort -u

echo ""
echo "=== [5] 迁移前基线 ==="
echo -n "租户 0   系列数: "; curl -s "http://localhost:8481/select/0/prometheus/api/v1/series/count"; echo ""
echo -n "租户 4242 系列数: "; curl -s "http://localhost:8481/select/4242/prometheus/api/v1/series/count"; echo ""
