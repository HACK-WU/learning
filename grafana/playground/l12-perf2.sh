#!/bin/bash
GF=http://localhost:3001
AUTH="-u admin:admin"
PROM=afx7x6dx803y8e

echo "########## 实验 A2：面板数量 → 响应时间（修正版）##########"
for N in 1 5 10 20 40 80; do
  python3 -c "
import json
n=$N
panels=[{'id':i+1,'type':'timeseries','title':'p%d'%(i+1),'gridPos':{'x':0,'y':i*8,'w':24,'h':8},'targets':[{'refId':'A','datasource':{'uid':'$PROM'},'expr':'up'}]} for i in range(n)]
print(json.dumps({'dashboard':{'uid':'perf-n%d'%n,'title':'Perf N=%d'%n,'panels':panels,'schemaVersion':41},'overwrite':True}))
" > /tmp/d.json
  curl -s --noproxy '*' $AUTH -X POST $GF/api/dashboards/db -H 'Content-Type: application/json' -d @/tmp/d.json -o /dev/null
  Q=$(python3 -c "print(','.join(['{\"refId\":\"Q%d\",\"datasource\":{\"uid\":\"%s\"},\"expr\":\"up\",\"instant\":true}'%(i,'$PROM') for i in range($N)]))")
  curl -s --noproxy '*' $AUTH -o /dev/null -X POST $GF/api/ds/query -H 'Content-Type: application/json' -d "{\"queries\":[$Q],\"from\":\"now-1h\",\"to\":\"now\"}"
  T1=$(curl -s --noproxy '*' $AUTH -o /dev/null -w '%{time_total}' -X POST $GF/api/ds/query -H 'Content-Type: application/json' -d "{\"queries\":[$Q],\"from\":\"now-1h\",\"to\":\"now\"}")
  T2=$(curl -s --noproxy '*' $AUTH -o /dev/null -w '%{time_total}' -X POST $GF/api/ds/query -H 'Content-Type: application/json' -d "{\"queries\":[$Q],\"from\":\"now-1h\",\"to\":\"now\"}")
  T3=$(curl -s --noproxy '*' $AUTH -o /dev/null -w '%{time_total}' -X POST $GF/api/ds/query -H 'Content-Type: application/json' -d "{\"queries\":[$Q],\"from\":\"now-1h\",\"to\":\"now\"}")
  echo "  N=$N  三次: $T1 / $T2 / $T3"
done
echo

echo "########## 实验 C2：窗口 → 步长自动放大（关键发现）##########"
echo "  窗口       Grafana算出的步长   响应字节   耗时"
for W in 15m 1h 6h 12h 24h 3d 7d; do
  OUT=$(curl -s --noproxy '*' $AUTH -X POST $GF/api/ds/query -H 'Content-Type: application/json' -d "{\"queries\":[{\"refId\":\"A\",\"datasource\":{\"uid\":\"$PROM\"},\"expr\":\"up\",\"instant\":false}],\"from\":\"now-$W\",\"to\":\"now\"}")
  STEP=$(echo "$OUT" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['results']['A']['frames'][0]['schema']['meta']['custom'].get('calculatedMinStep','?'))" 2>/dev/null)
  SZ=$(echo "$OUT" | wc -c)
  TM=$(curl -s --noproxy '*' $AUTH -o /dev/null -w '%{time_total}' -X POST $GF/api/ds/query -H 'Content-Type: application/json' -d "{\"queries\":[{\"refId\":\"A\",\"datasource\":{\"uid\":\"$PROM\"},\"expr\":\"up\",\"instant\":false}],\"from\":\"now-$W\",\"to\":\"now\"}")
  echo "  $W        ${STEP}ms              $SZ      $TM"
done
echo

echo "########## 实验 D：maxDataPoints 的影响（面板宽度决定数据量）##########"
echo "  maxDataPoints   响应字节"
for M in 100 500 1000 2000; do
  SZ=$(curl -s --noproxy '*' $AUTH -X POST $GF/api/ds/query -H 'Content-Type: application/json' -d "{\"queries\":[{\"refId\":\"A\",\"datasource\":{\"uid\":\"$PROM\"},\"expr\":\"node_cpu_seconds_total\",\"instant\":false,\"maxDataPoints\":$M}],\"from\":\"now-6h\",\"to\":\"now\"}" | wc -c)
  echo "  $M            $SZ"
done
echo

echo "########## 实验 E：高基数查询（性能杀手）##########"
echo "  --- 普通基数 ---"
T=$(curl -s --noproxy '*' $AUTH -o /dev/null -w '%{time_total}' -X POST $GF/api/ds/query -H 'Content-Type: application/json' -d "{\"queries\":[{\"refId\":\"A\",\"datasource\":{\"uid\":\"$PROM\"},\"expr\":\"up\",\"instant\":false}],\"from\":\"now-6h\",\"to\":\"now\"}")
echo "  up (低基数): ${T}s"
echo "  --- 高基数 ---"
T2=$(curl -s --noproxy '*' $AUTH -o /dev/null -w '%{time_total}' -X POST $GF/api/ds/query -H 'Content-Type: application/json' -d "{\"queries\":[{\"refId\":\"A\",\"datasource\":{\"uid\":\"$PROM\"},\"expr\":\"node_cpu_seconds_total\",\"instant\":false}],\"from\":\"now-6h\",\"to\":\"now\"}")
SZ2=$(curl -s --noproxy '*' $AUTH -X POST $GF/api/ds/query -H 'Content-Type: application/json' -d "{\"queries\":[{\"refId\":\"A\",\"datasource\":{\"uid\":\"$PROM\"},\"expr\":\"node_cpu_seconds_total\",\"instant\":false}],\"from\":\"now-6h\",\"to\":\"now\"}" | wc -c)
echo "  node_cpu_seconds_total (高基数): ${T2}s  字节=$SZ2"
