#!/bin/bash
# 课 10 实验 1：租户模型的边界（课 8 未验证的部分）
set -u
I=http://localhost:8480
S=http://localhost:8481

echo "=============================================="
echo " T1 租户 ID 的取值范围"
echo "=============================================="
echo "  官方文档：accountID 是 32 位无符号整数 (0 .. 2^32-1)"
echo "  我们来实测边界值"
echo

# 准备一批数据
python3 - <<'PY'
import time
ts = (int(time.time()) - 120) * 1000000000
open("/tmp/l10_tenant.influx","w").write(
    "\n".join("l10_tenant,idx=%d value=%d %d" % (i,i,ts) for i in range(5)) + "\n")
print("  准备 5 条序列 l10_tenant")
PY

q() {   # q <租户路径> -> 样本数
  curl -s --max-time 30 --data-urlencode 'query=count_over_time(l10_tenant_value[1h])' \
    "$S/select/$1/prometheus/api/v1/query" \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print(int(sum(float(x["value"][1]) for x in r)) if r else 0)' 2>/dev/null
}
qn() {  # qn <port> <query> -> 样本数（连指定 vmselect）
  curl -s --max-time 30 --data-urlencode "query=$2" \
    "http://localhost:$1/select/66/prometheus/api/v1/query" \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print(int(sum(float(x["value"][1]) for x in r)) if r else 0)' 2>/dev/null
}
w() {   # w <租户路径> -> HTTP code
  curl -s -o /dev/null -w '%{http_code}' -X POST --max-time 30 \
    --data-binary @/tmp/l10_tenant.influx "$I/insert/$1/influx/write" 2>/dev/null
}

for T in 0 1 42 2147483647 4294967295 4294967296; do
  code=$(w "$T")
  echo "  accountID=$T  写入 HTTP $code"
done

echo
echo "  -- 4294967295 (2^32-1) 是上限，4294967296 (2^32) 应该失败 --"

echo
echo "=============================================="
echo " T2 非法租户 ID 会怎样"
echo "=============================================="
for T in -1 abc "" "1:2:3" "99999999999999999999"; do
  code=$(w "$T")
  echo "  accountID='$T'  写入 HTTP $code"
done

echo
echo "=============================================="
echo " T3 projectID 的语义（课 8 结论复核）"
echo "=============================================="
echo "  写入 7、7:0、7:9，然后分别查"
echo
for T in 7 7:0 7:9; do
  w "$T" >/dev/null
done
sleep 5
echo "  查 7   : $(q 7)"
echo "  查 7:0 : $(q 7:0)"
echo "  查 7:9 : $(q 7:9)"
echo "  查 0   : $(q 0)"
echo
echo "  → 若 7 与 7:0 结果相同，说明 7 等价于 7:0"
echo "    若 7:9 独立，说明 projectID 是平级标识不是层级包含"

echo
echo "=============================================="
echo " T4 租户数据是否分散在所有 vmstorage"
echo "=============================================="
echo "  ⚠️ 这是课 8 遗留的疑问：官方说租户数据会均匀分散，哈希不看租户"
echo
M="l10_spread_$(date +%s)"
python3 - "$M" <<'PY'
import sys, time
ts = (int(time.time()) - 120) * 1000000000
open("/tmp/l10_spread.influx","w").write(
    "\n".join("%s,idx=%%d value=%%d %%d" % sys.argv[1] % (i,i,ts) for i in range(100)) + "\n")
print("  写入 %s: 100 条序列到 tenant 66" % sys.argv[1])
PY
curl -s -X POST --max-time 60 --data-binary @/tmp/l10_spread.influx \
  "$I/insert/66/influx/write" -o /dev/null -w '  HTTP %{http_code}\n'
sleep 10

QS="count_over_time(${M}_value[1h])"
echo "  tenant 66 的数据分布:"
  echo "    vmstorage1 (8485): $(qn 8485 "$QS")"
  echo "    vmstorage2 (8486): $(qn 8486 "$QS")"
echo "    集群聚合   (8481): $(curl -s --max-time 30 --data-urlencode "query=${QS}" "$S/select/66/prometheus/api/v1/query" | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print(int(sum(float(x["value"][1]) for x in r)) if r else 0)' 2>/dev/null)"
echo
echo "  → 若两个节点都有数据（各约 100，RF=2），说明租户数据确实分散在所有节点"
echo "    即：无法把某个租户固定到特定节点"
