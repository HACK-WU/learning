#!/bin/bash
# 课 8 核心：一致性哈希的稳定性验证
# 关键命题：同一条序列，无论经过多少跳，永远落到同一个 vmstorage
# 方法：反复查同一条序列，确认它每次都能被找到（说明路由稳定）

echo "=============================================="
echo " S1 分片归属的稳定性：同一序列多次查询"
echo "=============================================="
echo "  如果路由不稳定，同一条序列会时有时无"
for i in 1 2 3 4 5; do
  echo -n "  第 $i 次 count(l08_shard_value): "
  curl -s --max-time 60 --data-urlencode 'query=count(l08_shard_value)' \
    'http://localhost:8481/select/0/prometheus/api/v1/query' \
    | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print(int(float(r[0]["value"][1])) if r else "空")' 2>&1
done

echo
echo "=============================================="
echo " S2 分片算法：按什么哈希？"
echo "=============================================="
echo "  官方文档：consistent hashing over metric name and all its labels"
echo "  验证方法：同 metric name 不同标签 → 应分散；"
echo "            不同 metric name 同标签 → 也应分散"
echo
echo "  -- 先看 1000 条序列在两个节点的分布细节 --"
for pair in "vmstorage-learn:8482" "vmstorage-learn2:8492"; do
  name="${pair%%:*}"; port="${pair##*:}"
  echo -n "    $name tsid: "
  curl -s --max-time 20 "http://localhost:$port/metrics" 2>/dev/null \
    | grep 'vm_cache_entries{type="storage/tsid"' | head -1 | awk '{print $2}'
done

echo
echo "=============================================="
echo " S3 决定性验证：vminsert 的分片是否可预测"
echo "=============================================="
echo "  写入【同一条序列】多次，看它是否只落到一个节点"
M="l08_single_$(date +%s)"
python3 - "$M" <<'PY'
import sys, time
mark = sys.argv[1]
now = int(time.time())
lines = []
for k in range(20):
    ts = (now - 60 + k) * 1000000000
    lines.append("%s,idx=fixed value=%d %d" % (mark, k, ts))
open("/tmp/l08_single.influx","w").write("\n".join(lines)+"\n")
print("  序列: %s{idx=fixed}  20 个样本" % mark)
PY

B1=$(curl -s --max-time 20 'http://localhost:8482/metrics' 2>/dev/null | grep 'vm_cache_entries{type="storage/tsid"' | head -1 | awk '{print $2}')
B2=$(curl -s --max-time 20 'http://localhost:8492/metrics' 2>/dev/null | grep 'vm_cache_entries{type="storage/tsid"' | head -1 | awk '{print $2}')

curl -s -X POST --max-time 30 --data-binary @/tmp/l08_single.influx \
  'http://localhost:8480/insert/0/influx/write' -o /dev/null -w '  写入 HTTP %{http_code}\n'
sleep 5

A1=$(curl -s --max-time 20 'http://localhost:8482/metrics' 2>/dev/null | grep 'vm_cache_entries{type="storage/tsid"' | head -1 | awk '{print $2}')
A2=$(curl -s --max-time 20 'http://localhost:8492/metrics' 2>/dev/null | grep 'vm_cache_entries{type="storage/tsid"' | head -1 | awk '{print $2}')

echo "  vmstorage1: $B1 → $A1  (增量 $((A1-B1)))"
echo "  vmstorage2: $B2 → $A2  (增量 $((A2-B2)))"
echo
echo "  → 如果只有一个节点增量为 1，证明同一条序列【只落到一个节点】"

echo
echo "=============================================="
echo " S4 一致性哈希的『一致性』体现在哪"
echo "=============================================="
echo "  场景：3 个节点时，序列 X 落在节点 A。"
echo "        加到 4 个节点后，X 应该【仍然】落在 A（不在环上移动的部分）"
echo
echo "  ⚠️ 但我们已经加了节点，旧数据的归属已经变了。"
echo "     这正是【扩容需要迁移数据】的原因 —— 社区版不自动迁移。"
echo
echo "  -- 验证：旧数据(l08_cluster, 扩容前写的)还能查到吗 --"
curl -s --max-time 60 --data-urlencode 'query=count_over_time(l08_cluster_value[24h])' \
  'http://localhost:8481/select/0/prometheus/api/v1/query' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print("    l08_cluster 样本数:", int(sum(float(x["value"][1]) for x in r)) if r else "空")' 2>&1

echo "  -- 新数据(l08_shard, 扩容后写的) --"
curl -s --max-time 60 --data-urlencode 'query=count(l08_shard_value)' \
  'http://localhost:8481/select/0/prometheus/api/v1/query' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print("    l08_shard 序列数:", int(float(r[0]["value"][1])) if r else "空")' 2>&1

echo
echo "  → 两者都能查到，因为 vmselect 会【问所有节点】再聚合。"

echo
echo "=============================================="
echo " S5 vmselect 的聚合行为自证"
echo "=============================================="
echo "  -- 分别停掉一个节点，看查询结果如何变化 --"
echo "  ⚠️ 这步演示【无副本时节点故障=数据丢失】，课 9 会讲副本"
echo
echo "  当前两节点都在，count = $(curl -s --max-time 60 --data-urlencode 'query=count(l08_shard_value)' 'http://localhost:8481/select/0/prometheus/api/v1/query' | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print(int(float(r[0]["value"][1])) if r else 0)' 2>&1)"

echo
echo "  停掉 vmstorage-learn2 ..."
docker stop vmstorage-learn2 >/dev/null 2>&1
sleep 5
echo -n "  只剩 vmstorage1 时 count = "
curl -s --max-time 60 --data-urlencode 'query=count(l08_shard_value)' \
  'http://localhost:8481/select/0/prometheus/api/v1/query' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print(int(float(r[0]["value"][1])) if r else "查询失败")' 2>&1

echo
echo "  恢复 vmstorage-learn2 ..."
docker start vmstorage-learn2 >/dev/null 2>&1
sleep 8
echo -n "  恢复后 count = "
curl -s --max-time 60 --data-urlencode 'query=count(l08_shard_value)' \
  'http://localhost:8481/select/0/prometheus/api/v1/query' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print(int(float(r[0]["value"][1])) if r else "查询失败")' 2>&1
