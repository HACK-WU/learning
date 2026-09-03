#!/bin/bash
# 课 9 核心实验：RF=2 的稳定态行为 + 副本失败的后果
# 教训：容器刚启动/刚恢复时写入，副本会不完整（节点 temporarily unavailable）
#      必须等节点稳定后再写入，且要检查 vminsert 日志有无 "cannot make a copy"
set -u

q() {
  curl -s --max-time 60 --data-urlencode "query=$1" \
    "http://localhost:$2/select/0/prometheus/api/v1/query" \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print(int(sum(float(x["value"][1]) for x in r)) if r else 0)' 2>/dev/null
}

echo "=============================================="
echo " C0 等集群完全稳定"
echo "=============================================="
echo "  等待 20 秒让所有节点稳定..."
sleep 20
for pair in "vminsert:8480" "vmselect:8481" "vmstorage1:8482" "vmstorage2:8492" "vmsel-n1:8485" "vmsel-n2:8486"; do
  n="${pair%%:*}"; p="${pair##*:}"
  c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://localhost:$p/health" 2>/dev/null)
  echo "    $n (port $p): HTTP $c"
done

echo
echo "=============================================="
echo " C1 干净写入：RF=2 稳定态"
echo "=============================================="
M="l09_clean_$(date +%s)"
python3 - "$M" <<'PY'
import sys, time
mark = sys.argv[1]
ts = (int(time.time()) - 120) * 1000000000
lines = ["%s,idx=%d value=%d %d" % (mark, i, i, ts) for i in range(200)]
open("/tmp/l09_clean.influx","w").write("\n".join(lines)+"\n")
print("  序列: %s (200 条)" % mark)
PY

curl -s -X POST --max-time 60 --data-binary @/tmp/l09_clean.influx \
  'http://localhost:8480/insert/0/influx/write' -o /dev/null -w '  写入 HTTP %{http_code}\n'

echo "  等待 12 秒让副本落盘..."
sleep 12

Q="count_over_time(${M}_value[1h])"
N1=$(q "$Q" 8485); N2=$(q "$Q" 8486); AG=$(q "$Q" 8481)
echo "  vmstorage1: $N1"
echo "  vmstorage2: $N2"
echo "  集群聚合:   $AG"
echo
if [ "$N1" = "200" ] && [ "$N2" = "200" ]; then
  echo "  ✅ RF=2 正常：两个节点各有完整 200 条（副本成功）"
else
  echo "  ⚠️ 副本不完整：节点1=$N1 节点2=$N2"
fi

echo
echo "  -- 检查 vminsert 有无副本失败日志 --"
ERR=$(docker logs vminsert-learn 2>&1 | grep -c 'cannot make a copy')
echo "     'cannot make a copy' 次数: $ERR"

echo
echo "=============================================="
echo " C2 关键：没有 dedup 时，聚合结果是多少？"
echo "=============================================="
echo "  单节点各存 200，聚合 = $AG"
echo "  → 如果 AG = 400，说明【重复计算】(每条数据被算了两次)"
echo "  → 如果 AG = 200，说明 vmselect 自动去重了"

echo
echo "  -- 逐条看聚合结果的样本值分布 --"
curl -s --max-time 60 --data-urlencode "query=${M}_value{idx=\"0\"}" \
  --data-urlencode "start=$(( $(date +%s) - 3600 ))" \
  --data-urlencode "end=$(date +%s)" --data-urlencode "step=60" \
  'http://localhost:8481/select/0/prometheus/api/v1/query_range' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print("     返回的序列数:", len(r))
for x in r[:5]:
    print("       ", x["metric"], "->", x["values"])' 2>&1

echo
echo "=============================================="
echo " C3 配置 dedup 后对比"
echo "=============================================="
echo "  启动一个带 -dedup.minScrapeInterval=30s 的 vmselect (端口 8487)"
docker rm -f vmsel-dedup >/dev/null 2>&1
docker run -d --name vmsel-dedup \
  --network vm-cluster-net -p 8487:8481 \
  victoriametrics/vmselect:v1.151.0-cluster \
  -storageNode=vmstorage-learn:8401 \
  -storageNode=vmstorage-learn2:8401 \
  -dedup.minScrapeInterval=30s \
  -httpListenAddr=:8481 >/dev/null 2>&1

for i in $(seq 1 30); do
  a=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 'http://localhost:8487/health' 2>/dev/null)
  if [ "$a" = "200" ]; then echo "  vmselect(dedup) 就绪"; break; fi
  sleep 2
done

echo
echo "  -- 无 dedup (8481) vs 有 dedup (8487) --"
echo "     无 dedup count_over_time: $(q "$Q" 8481)"
echo "     有 dedup count_over_time: $(q "$Q" 8487)"
echo
echo "  -- 序列数对比 --"
echo -n "     无 dedup count(): "
curl -s --max-time 60 --data-urlencode "query=count(${M}_value)" \
  'http://localhost:8481/select/0/prometheus/api/v1/query' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print(int(float(r[0]["value"][1])) if r else "空")' 2>&1
echo -n "     有 dedup count(): "
curl -s --max-time 60 --data-urlencode "query=count(${M}_value)" \
  'http://localhost:8487/select/0/prometheus/api/v1/query' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print(int(float(r[0]["value"][1])) if r else "空")' 2>&1

echo
echo "=============================================="
echo " C4 dedup 的副作用：会不会误删正常数据？"
echo "=============================================="
echo "  写入两条【不同时间戳】的样本（间隔 5 秒），dedup=30s 应该删掉一条"
M2="l09_dedup_$(date +%s)"
python3 - "$M2" <<'PY'
import sys, time
mark = sys.argv[1]
now = int(time.time()) - 120
lines = [
    "%s,idx=0 value=111 %d" % (mark, now*1000000000),
    "%s,idx=0 value=222 %d" % (mark, (now+5)*1000000000),
]
open("/tmp/l09_dedup.influx","w").write("\n".join(lines)+"\n")
print("  写入 %s: 2 个样本，间隔 5 秒" % mark)
PY
curl -s -X POST --max-time 30 --data-binary @/tmp/l09_dedup.influx \
  'http://localhost:8480/insert/0/influx/write' -o /dev/null -w '  HTTP %{http_code}\n'
sleep 10

Q2="count_over_time(${M2}_value[1h])"
echo "     无 dedup: $(q "$Q2" 8481) 个样本"
echo "     有 dedup(30s): $(q "$Q2" 8487) 个样本"
echo
echo "  -- 保留的是哪个值？ --"
echo -n "     有 dedup 查询: "
curl -s --max-time 60 --data-urlencode "query=${M2}_value" \
  'http://localhost:8487/select/0/prometheus/api/v1/query' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print([x["value"][1] for x in r] if r else "空")' 2>&1
