#!/bin/bash
# 为跨租户迁移准备带标记的源数据（写入租户 0）
SRC="http://localhost:8480/insert/0/prometheus/api/v1/import/prometheus"
NOW=$(date +%s)

echo "=== [1] 写入 3 个专属指标到租户 0，每指标 30 个样本（覆盖近 30 分钟） ==="
for m in l12r_xmig_alpha l12r_xmig_beta; do
  payload=""
  for i in $(seq 0 29); do
    ts=$(( (NOW - 1800 + i*60) * 1000 ))
    val=$((i * 7))
    payload="${payload}{\"metric\":{\"__name__\":\"${m}\",\"tenant_src\":\"0\",\"idx\":\"${i}\"},\"values\":[${val}],\"timestamps\":[${ts}]}\n"
  done
  echo -e "${payload}" | curl -s -X POST --data-binary @- "${SRC}" -w "  -> HTTP %{http_code}\n"
  echo "  metric=${m} 写入完成"
done

echo ""
echo "=== [2] 再写一个带 l12r 前缀的可辨识指标用于对照 ==="
payload=""
for i in $(seq 0 29); do
  ts=$(( (NOW - 1800 + i*60) * 1000 ))
  payload="${payload}{\"metric\":{\"__name__\":\"l12r_tenant_journey\",\"stage\":\"src0\",\"idx\":\"${i}\"},\"values\":[${i}],\"timestamps\":[${ts}]}\n"
done
echo -e "${payload}" | curl -s -X POST --data-binary @- "${SRC}" -w "  -> HTTP %{http_code}\n"

echo ""
echo "=== [3] 等待可查（等 3 秒）后核验写入 ==="
sleep 3
echo -n "租户 0 中 l12r_xmig_alpha 样本数: "
curl -s -G "http://localhost:8481/select/0/prometheus/api/v1/query" \
  --data-urlencode 'query=count_over_time(l12r_xmig_alpha[2h])' | grep -o '"result":\[[^]]*\]' | head -c 200
echo ""
echo -n "租户 0 中 l12r_tenant_journey 样本数: "
curl -s -G "http://localhost:8481/select/0/prometheus/api/v1/query" \
  --data-urlencode 'query=count_over_time(l12r_tenant_journey[2h])' | grep -o '"result":\[[^]]*\]' | head -c 200
echo ""

echo ""
echo "=== [4] 用 label/values 确认指标名已注册 ==="
curl -s "http://localhost:8481/select/0/prometheus/api/v1/label/__name__/values" | tr ',' '\n' | grep -i "l12r_" | head -20

echo ""
echo "=== [5] 迁移前目标租户 4242 序列数（应为 0） ==="
curl -s "http://localhost:8481/select/4242/prometheus/api/v1/series/count"; echo ""
