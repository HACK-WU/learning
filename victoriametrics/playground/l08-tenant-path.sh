#!/bin/bash
# 核实 M4：不带 tenant 的路径返回 200，租户 ID 默认值是什么
echo "=============================================="
echo " N1 /select/prometheus/... 到底查的是哪个租户"
echo "=============================================="
echo -n "  查 l08_tenant_value: "
curl -s --max-time 30 --data-urlencode 'query=count_over_time(l08_tenant_value[10m])' \
  'http://localhost:8481/select/prometheus/api/v1/query' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print(int(sum(float(x["value"][1]) for x in r)) if r else 0, "个样本")' 2>&1

echo -n "  对照 /select/0/ : "
curl -s --max-time 30 --data-urlencode 'query=count_over_time(l08_tenant_value[10m])' \
  'http://localhost:8481/select/0/prometheus/api/v1/query' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print(int(sum(float(x["value"][1]) for x in r)) if r else 0, "个样本")' 2>&1

echo
echo "  -- 再试几种写法 --"
for path in "/select//prometheus/api/v1/query" "/select/0:0/prometheus/api/v1/query" "/select/abc/prometheus/api/v1/query"; do
  echo -n "    $path -> "
  curl -s -o /dev/null --max-time 10 --data-urlencode 'query=up' \
    "http://localhost:8481$path" -w 'HTTP %{http_code}\n'
done

echo
echo "=============================================="
echo " N2 accountID:projectID 两级租户"
echo "=============================================="
python3 - <<'PY'
import time
ts = (int(time.time()) - 60) * 1000000000
lines = ["l08_proj,idx=%d value=%d %d" % (i, i, ts) for i in range(3)]
open("/tmp/l08_proj.influx","w").write("\n".join(lines)+"\n")
PY
echo "  写入 accountID=7, projectID=9"
curl -s -X POST --max-time 30 --data-binary @/tmp/l08_proj.influx \
  'http://localhost:8480/insert/7:9/influx/write' -o /dev/null -w '  HTTP %{http_code}\n'
sleep 4
echo -n "  查 7:9 -> "
curl -s --max-time 30 --data-urlencode 'query=count_over_time(l08_proj_value[10m])' \
  'http://localhost:8481/select/7:9/prometheus/api/v1/query' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print(int(sum(float(x["value"][1]) for x in r)) if r else 0, "个样本")' 2>&1
echo -n "  查 7:0 -> "
curl -s --max-time 30 --data-urlencode 'query=count_over_time(l08_proj_value[10m])' \
  'http://localhost:8481/select/7:0/prometheus/api/v1/query' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print(int(sum(float(x["value"][1]) for x in r)) if r else 0, "个样本")' 2>&1
echo -n "  查 7   -> "
curl -s --max-time 30 --data-urlencode 'query=count_over_time(l08_proj_value[10m])' \
  'http://localhost:8481/select/7/prometheus/api/v1/query' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print(int(sum(float(x["value"][1]) for x in r)) if r else 0, "个样本")' 2>&1

echo
echo "=============================================="
echo " N3 用标签指定租户（vm_account_id）"
echo "=============================================="
python3 - <<'PY'
import time
ts = (int(time.time()) - 60) * 1000000000
lines = ['l08_lbl,idx=%d,vm_account_id="55" value=%d %d' % (i, i, ts) for i in range(3)]
open("/tmp/l08_lbl.influx","w").write("\n".join(lines)+"\n")
PY
echo "  写入带 vm_account_id=55 标签的数据到 /insert/0/"
curl -s -X POST --max-time 30 --data-binary @/tmp/l08_lbl.influx \
  'http://localhost:8480/insert/0/influx/write' -o /dev/null -w '  HTTP %{http_code}\n'
sleep 4
echo -n "  查 tenant 0 -> "
curl -s --max-time 30 --data-urlencode 'query=count_over_time(l08_lbl_value[10m])' \
  'http://localhost:8481/select/0/prometheus/api/v1/query' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print(int(sum(float(x["value"][1]) for x in r)) if r else 0, "个样本")' 2>&1
echo -n "  查 tenant 55 -> "
curl -s --max-time 30 --data-urlencode 'query=count_over_time(l08_lbl_value[10m])' \
  'http://localhost:8481/select/55/prometheus/api/v1/query' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print(int(sum(float(x["value"][1]) for x in r)) if r else 0, "个样本")' 2>&1
