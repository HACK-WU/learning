#!/usr/bin/env bash
set -e
D=/mnt/d/projects/learning/prometheus/labs/lesson-10
NET=l10net; PROM=l10-prom; PORT=19440

# 用 TSDB 状态 API 取序列数（prometheus_tsdb_head_series 在本环境不存在，已查证）
series() { curl -s "http://localhost:$PORT/api/v1/status/tsdb" \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['data']['headStats']['numSeries'])"; }
top() { curl -s "http://localhost:$PORT/api/v1/status/tsdb" \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)['data']['seriesCountByMetricName'][:5]
print('; '.join(f\"{x['name']}={x['value']}\" for x in d))"; }
mem() { docker stats $PROM --no-stream --format '{{.MemUsage}}' | awk '{print $1}' | sed 's/MiB//'; }

restart_app() {
  docker rm -f l10-app >/dev/null 2>&1
  docker run -d --name l10-app --network $NET \
    -e N_USERS=$1 -e N_URLS=$2 -e N_REQIDS=$3 l10-app >/dev/null 2>&1
  sleep 18
}

echo "############ 实验 1：三类标签值失控的放大倍数（实测）############"
echo ""
printf "%-42s %8s %10s %s\n" "场景" "序列数" "内存(MiB)" "Top 指标"
echo "----------------------------------------------------------------------------"

restart_app 0 0 0
S=$(series); M=$(mem); T=$(top)
printf "%-42s %8s %10s %s\n" "A 仅基线（低基数）" "$S" "$M" "$T"
A_S=$S; A_M=$M

restart_app 5000 0 0
S=$(series); M=$(mem); T=$(top)
printf "%-42s %8s %10s %s\n" "B +5000 user_id" "$S" "$M" "$T"
B_S=$S; B_M=$M

restart_app 5000 2000 0
S=$(series); M=$(mem); T=$(top)
printf "%-42s %8s %10s %s\n" "C +2000 URL路径" "$S" "$M" "$T"
C_S=$S; C_M=$M

restart_app 5000 2000 1000
S=$(series); M=$(mem); T=$(top)
printf "%-42s %8s %10s %s\n" "D +1000 request_id(36字符)" "$S" "$M" "$T"
D_S=$S; D_M=$M

echo ""
echo "########## 放大倍数（相对基线 A）##########"
python3 -c "
a_s,a_m=$A_S,$A_M
for n,s,m in [('B (5000 user_id)',$B_S,$B_M),('C (+2000 URL)',$C_S,$C_M),('D (+1000 reqid)',$D_S,$D_M)]:
    print(f'{n:24s} 序列 {s:6d} (x{s/a_s:.1f})   内存 {m:6.2f}MiB (x{m/a_m:.2f})')
print()
print(f'每 1000 条序列的内存增量:')
for n,s,m in [('B',$B_S,$B_M),('C',$C_S,$C_M),('D',$D_S,$D_M)]:
    ds=s-a_s; dm=m-a_m
    if ds>0: print(f'  {n}: +{ds} 序列 -> +{dm:.2f} MiB  = {dm/ds*1000:.3f} MiB/千序列')
"
