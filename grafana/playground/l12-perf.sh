#!/bin/bash
# 12.1 性能实验：面板数量 / 并发 / 渲染
GF=http://localhost:3001
PROM=efxhrcfu7s3k0e
AUTH="-u admin:admin"

echo "########## 实验 A：面板数量 → 响应时间 ##########"
echo "(同一 dashboard，面板数 1 / 5 / 10 / 20 / 40，各测 3 次取中位数)"
echo

for N in 1 5 10 20 40; do
  # 构造 N 个面板的 dashboard
  python3 - "$N" > /tmp/dash_$N.json <<'PYEOF'
import json,sys
n=int(sys.argv[1])
panels=[{"id":i+1,"type":"timeseries","title":f"p{i+1}","gridPos":{"x":0,"y":i*8,"w":24,"h":8},
         "targets":[{"refId":"A","datasource":{"uid":"efxhrcfu7s3k0e"},"expr":"up"}]} for i in range(n)]
print(json.dumps({"dashboard":{"uid":f"perf-n{N}","title":f"Perf N={N}","panels":panels,"schemaVersion":41},"overwrite":True}))
PYEOF
  curl -s --noproxy '*' $AUTH -X POST $GF/api/dashboards/db -H 'Content-Type: application/json' -d @/tmp/dash_$N.json -o /dev/null -w "  N=$N 建表=%{http_code} " 
  # 预热
  curl -s --noproxy '*' $AUTH -o /dev/null -X POST $GF/api/ds/query -H 'Content-Type: application/json' -d "{\"queries\":[{\"refId\":\"A\",\"datasource\":{\"uid\":\"$PROM\"},\"expr\":\"up\",\"instant\":true}],\"from\":\"now-1h\",\"to\":\"now\"}"
  # 测 3 次：模拟浏览器打开 dashboard 时后端要跑 N 个查询
  T1=$(curl -s --noproxy '*' $AUTH -o /dev/null -w '%{time_total}' -X POST $GF/api/ds/query -H 'Content-Type: application/json' -d "{\"queries\":[$(python3 -c "print(','.join(['{\"refId\":\"Q%d\",\"datasource\":{\"uid\":\"%s\"},\"expr\":\"up\",\"instant\":true}'%(i,'$PROM') for i in range($N)]))")],\"from\":\"now-1h\",\"to\":\"now\"}")
  T2=$(curl -s --noproxy '*' $AUTH -o /dev/null -w '%{time_total}' -X POST $GF/api/ds/query -H 'Content-Type: application/json' -d "{\"queries\":[$(python3 -c "print(','.join(['{\"refId\":\"Q%d\",\"datasource\":{\"uid\":\"%s\"},\"expr\":\"up\",\"instant\":true}'%(i,'$PROM') for i in range($N)]))")],\"from\":\"now-1h\",\"to\":\"now\"}")
  T3=$(curl -s --noproxy '*' $AUTH -o /dev/null -w '%{time_total}' -X POST $GF/api/ds/query -H 'Content-Type: application/json' -d "{\"queries\":[$(python3 -c "print(','.join(['{\"refId\":\"Q%d\",\"datasource\":{\"uid\":\"%s\"},\"expr\":\"up\",\"instant\":true}'%(i,'$PROM') for i in range($N)]))")],\"from\":\"now-1h\",\"to\":\"now\"}")
  echo "耗时: $T1 / $T2 / $T3 秒"
done
echo

echo "########## 实验 B：并发查询 → 是否排队 ##########"
echo "(同时发起 C 个并发请求，看总耗时是线性增长还是被限流)"
echo
for C in 1 4 8 16 32; do
  START=$(date +%s.%N)
  for i in $(seq 1 $C); do
    curl -s --noproxy '*' $AUTH -o /dev/null -X POST $GF/api/ds/query -H 'Content-Type: application/json' -d "{\"queries\":[{\"refId\":\"A\",\"datasource\":{\"uid\":\"$PROM\"},\"expr\":\"up\",\"instant\":true}],\"from\":\"now-1h\",\"to\":\"now\"}" &
  done
  wait
  END=$(date +%s.%N)
  echo "  并发=$C 全部完成总耗时=$(echo "$END - $START" | bc) 秒"
done
echo

echo "########## 实验 C：查询数据量 → 响应体大小 ##########"
echo "(同一个查询，时间窗 1h / 6h / 24h / 7d，看返回字节数与耗时)"
echo
for W in 1h 6h 24h 7d; do
  SZ=$(curl -s --noproxy '*' $AUTH -X POST $GF/api/ds/query -H 'Content-Type: application/json' -d "{\"queries\":[{\"refId\":\"A\",\"datasource\":{\"uid\":\"$PROM\"},\"expr\":\"up\",\"instant\":false,\"intervalMs\":15000}],\"from\":\"now-$W\",\"to\":\"now\"}" | wc -c)
  TM=$(curl -s --noproxy '*' $AUTH -o /dev/null -w '%{time_total}' -X POST $GF/api/ds/query -H 'Content-Type: application/json' -d "{\"queries\":[{\"refId\":\"A\",\"datasource\":{\"uid\":\"$PROM\"},\"expr\":\"up\",\"instant\":false,\"intervalMs\":15000}],\"from\":\"now-$W\",\"to\":\"now\"}")
  echo "  窗口=$W 响应字节=$SZ 耗时=$TM 秒"
done
