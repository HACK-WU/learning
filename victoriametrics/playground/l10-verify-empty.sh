#!/bin/bash
# 排查：自检时 backend/frontend 查 l10_va_value 返回空
set -u
echo "=============================================="
echo " Q1 直接查（不带时间范围）"
echo "=============================================="
for u in backend:backend-pass-123 frontend:frontend-pass-456; do
  printf "  %-10s 原始响应: " "${u%%:*}"
  curl -s --max-time 20 -u "$u" --data-urlencode 'query=l10_va_value' \
    'http://localhost:8427/api/v1/query' 2>&1 | head -c 300
  echo
done

echo
echo "=============================================="
echo " Q2 绕过 vmauth 直连后端"
echo "=============================================="
for t in 100 200; do
  printf "  tenant %s: " "$t"
  curl -s --max-time 20 --data-urlencode 'query=l10_va_value' \
    "http://localhost:8481/select/$t/prometheus/api/v1/query" 2>&1 | head -c 200
  echo
done

echo
echo "=============================================="
echo " Q3 用 count_over_time 查（大窗口）"
echo "=============================================="
for t in 100 200; do
  printf "  tenant %s count_over_time[24h]: " "$t"
  curl -s --max-time 30 --data-urlencode 'query=count_over_time(l10_va_value[24h])' \
    "http://localhost:8481/select/$t/prometheus/api/v1/query" \
    | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print(int(sum(float(x["value"][1]) for x in r)) if r else 0)' 2>/dev/null
done

echo
echo "=============================================="
echo " Q4 检查数据的时间戳与当前查询窗口"
echo "=============================================="
echo "  当前时间: $(date '+%Y-%m-%d %H:%M:%S') ($(date +%s))"
echo "  用 range query 找数据实际所在时间"
for t in 100 200; do
  printf "  tenant %s 最近 2 小时: " "$t"
  curl -s --max-time 30 -G \
    --data-urlencode 'query=l10_va_value' \
    --data-urlencode "start=$(( $(date +%s) - 7200 ))" \
    --data-urlencode "end=$(date +%s)" \
    --data-urlencode 'step=600' \
    "http://localhost:8481/select/$t/prometheus/api/v1/query_range" \
    | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
n=sum(len(x.get("values",[])) for x in r)
print("%d 条序列, %d 个数据点" % (len(r), n))' 2>/dev/null
done

echo
echo "=============================================="
echo " Q5 关键：Prometheus instant query 的默认回溯窗口"
echo "=============================================="
echo "  instant query (/api/v1/query) 默认只找【最近 5 分钟】的数据"
echo "  -search.lookback-delta 默认 5m"
echo
echo "  l10_va 的时间戳是【写入时刻 - 120 秒】，"
echo "  之后又跑了很多实验，早已超过 5 分钟"
echo
echo "  → 数据还在，只是 instant query 的时间窗口外了"
echo
echo "  验证：查 vmselect 的 lookback-delta"
docker inspect vmselect-learn --format '  vmselect 参数: {{.Args}}' 2>&1
echo
echo "  结论：自检脚本用 instant query 查历史数据 = 伪阴性"
echo "        应该用 count_over_time 或 range query（课 6/8/9 都强调过）"

echo
echo "=============================================="
echo " Q6 用正确方式重新验证租户绑定"
echo "=============================================="
echo "  -- 先写入一批新数据（时间戳 = NOW-120）--"
python3 - <<'PY'
import time
ts = (int(time.time()) - 120) * 1000000000
open("/tmp/l10_vc.influx","w").write("\n".join("l10_vc,idx=%d value=100 %d" % (i,ts) for i in range(5))+"\n")
open("/tmp/l10_vd.influx","w").write("\n".join("l10_vc,idx=%d value=200 %d" % (i,ts) for i in range(5))+"\n")
print("  准备 l10_vc (backend=100, frontend=200)")
PY
curl -s -o /dev/null -w '  backend 写入:  HTTP %{http_code}\n' -X POST --max-time 30 \
  -u backend:backend-pass-123 --data-binary @/tmp/l10_vc.influx \
  'http://localhost:8427/write'
curl -s -o /dev/null -w '  frontend 写入: HTTP %{http_code}\n' -X POST --max-time 30 \
  -u frontend:frontend-pass-456 --data-binary @/tmp/l10_vd.influx \
  'http://localhost:8427/write'
sleep 8
echo
echo "  -- instant query（数据在 5 分钟窗口内，应该能查到）--"
for u in backend:backend-pass-123 frontend:frontend-pass-456 viewer:viewer-pass-000; do
  printf "    %-10s " "${u%%:*}"
  curl -s --max-time 20 -u "$u" --data-urlencode 'query=l10_vc_value' \
    'http://localhost:8427/api/v1/query' \
    | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
    print(sorted(set(x["value"][1] for x in r)) if r else "空")
except Exception as e: print("解析失败")' 2>&1
done
echo
echo "  -- count_over_time（不受窗口限制）--"
for u in backend:backend-pass-123 frontend:frontend-pass-456; do
  printf "    %-10s " "${u%%:*}"
  curl -s --max-time 20 -u "$u" \
    --data-urlencode 'query=count_over_time(l10_vc_value[1h])' \
    'http://localhost:8427/api/v1/query' \
    | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
    print(int(sum(float(x["value"][1]) for x in r)) if r else 0)
except Exception: print("N/A")' 2>&1
done
