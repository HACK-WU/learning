#!/usr/bin/env bash
# 核验：叶子与全局的 rate 差异是"真不一致"还是"查询时刻不同"
echo "=== 交替各查 5 次，看差异是否随时刻漂移 ==="
echo "  轮次   叶子rate      全局rate      差值"
for i in 1 2 3 4 5; do
  LR=$(curl -s -G 'http://localhost:19110/api/v1/query' --data-urlencode 'query=rate(l8_requests_total{method="GET"}[2m])' | python3 -c "import sys,json;d=json.load(sys.stdin);r=d['data']['result'];print(r[0]['value'][1] if r else '0')")
  GR=$(curl -s -G 'http://localhost:19114/api/v1/query' --data-urlencode 'query=rate(l8_requests_total{method="GET",cluster="leaf-a"}[2m])' | python3 -c "import sys,json;d=json.load(sys.stdin);r=d['data']['result'];print(r[0]['value'][1] if r else '0')")
  D=$(python3 -c "print(f'{abs(float($LR)-float($GR)):.5f}')")
  printf "  %d    %-12s  %-12s  %s\n" "$i" "$LR" "$GR" "$D"
  sleep 2
done

echo
echo "=== 关键对照：同一时刻，叶子 vs 全局，各自连续两次 ==="
echo "  若差值随时刻变化 -> 说明是采样时刻差异（各自的最新样本时刻不同）"
echo "  若差值恒定       -> 说明是系统性偏差"

echo
echo "=== 更严谨的对照：用固定的时间窗口（不用 2m 相对窗口）==="
NOW=$(date +%s)
S=$((NOW - 120)); E=$((NOW - 10))
for port in 19110 19114; do
  extra=""
  [ "$port" = "19114" ] && extra=',cluster="leaf-a"'
  V=$(curl -s -G "http://localhost:$port/api/v1/query" \
    --data-urlencode "query=rate(l8_requests_total{method=\"GET\"$extra}[2m])" \
    --data-urlencode "time=$E" \
    | python3 -c "import sys,json;d=json.load(sys.stdin);r=d['data']['result'];print(r[0]['value'][1] if r else '0')")
  echo "  端口 $port 在固定时刻 $E 的 rate = $V"
done
