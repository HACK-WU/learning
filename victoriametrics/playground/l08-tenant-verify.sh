#!/bin/bash
# 课 8：核实 tenant 42 写入 204 却查到 0 条
echo "=============================================="
echo " M1 tenant 42 到底有没有数据"
echo "=============================================="
echo -n "  count_over_time[1h] tenant 42: "
curl -s --max-time 60 --data-urlencode 'query=count_over_time(l08_shard_value[1h])' \
  'http://localhost:8481/select/42/prometheus/api/v1/query' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print(int(sum(float(x["value"][1]) for x in r)) if r else "空")' 2>&1

echo -n "  count_over_time[1h] tenant 0 : "
curl -s --max-time 60 --data-urlencode 'query=count_over_time(l08_shard_value[1h])' \
  'http://localhost:8481/select/0/prometheus/api/v1/query' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print(int(sum(float(x["value"][1]) for x in r)) if r else "空")' 2>&1

echo
echo "=============================================="
echo " M2 原因：l08_shard 数据的时间戳"
echo "=============================================="
echo "  l08_shard 是在扩容实验时写入的，时间戳是【过去 120 秒】"
echo "  到现在已经过了很久，[1h] 应该还能覆盖"
echo
echo "  -- 查 tenant 42 有哪些指标 --"
curl -s --max-time 30 'http://localhost:8481/select/42/prometheus/api/v1/label/__name__/values' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); v=d.get("data",[])
print("   tenant 42 指标:", v if v else "空")' 2>&1
echo "  -- 查 tenant 0 有哪些指标 --"
curl -s --max-time 30 'http://localhost:8481/select/0/prometheus/api/v1/label/__name__/values' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); v=d.get("data",[])
print("   tenant 0 指标:", [x for x in v if x.startswith("l08")])' 2>&1

echo
echo "=============================================="
echo " M3 重新做一次干净的多租户实验"
echo "=============================================="
python3 - <<'PY'
import time
now = int(time.time())
ts = (now - 60) * 1000000000
lines = ["l08_tenant,idx=%d value=%d %d" % (i, i, ts) for i in range(5)]
open("/tmp/l08_tenant.influx","w").write("\n".join(lines)+"\n")
print("  生成 5 条序列，时间戳 = 过去 60 秒")
PY

for t in 0 42 100; do
  curl -s -X POST --max-time 30 --data-binary @/tmp/l08_tenant.influx \
    "http://localhost:8480/insert/$t/influx/write" -o /dev/null \
    -w "  写入 tenant $t: HTTP %{http_code}\n"
done

sleep 5

echo
echo "  -- 分别查询 --"
for t in 0 42 100 999; do
  echo -n "    tenant $t: "
  curl -s --max-time 30 --data-urlencode 'query=count_over_time(l08_tenant_value[10m])' \
    "http://localhost:8481/select/$t/prometheus/api/v1/query" \
    | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print(int(sum(float(x["value"][1]) for x in r)) if r else 0, "个样本")' 2>&1
done

echo
echo "=============================================="
echo " M4 跨租户查询：官方说不支持"
echo "=============================================="
echo -n "  不带 tenant 的路径 /select/prometheus/... : "
curl -s -o /dev/null --max-time 10 --data-urlencode 'query=up' \
  'http://localhost:8481/select/prometheus/api/v1/query' -w 'HTTP %{http_code}\n'
echo -n "  用一个不存在的 tenant: "
curl -s --max-time 30 --data-urlencode 'query=count_over_time(l08_tenant_value[10m])' \
  'http://localhost:8481/select/999/prometheus/api/v1/query' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print("空" if not r else r)' 2>&1
