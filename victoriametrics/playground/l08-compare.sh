#!/bin/bash
# 课 8：单节点 vs 集群 的资源开销与能力对比

echo "=============================================="
echo " R1 容器资源占用对比"
echo "=============================================="
docker stats --no-stream --format 'table {{.Name}}\t{{.MemUsage}}\t{{.CPUPerc}}' \
  vm-learn vmstorage-learn vmstorage-learn2 vminsert-learn vmselect-learn 2>&1

echo
echo "=============================================="
echo " R2 集群各组件的内存细节"
echo "=============================================="
for pair in "vmstorage-learn:8482" "vmstorage-learn2:8492" "vminsert-learn:8480" "vmselect-learn:8481"; do
  name="${pair%%:*}"; port="${pair##*:}"
  echo -n "  $name RSS: "
  curl -s --max-time 15 "http://localhost:$port/metrics" 2>/dev/null \
    | grep '^process_resident_memory_bytes' | head -1 \
    | awk '{printf "%.1f MB\n", $2/1048576}'
done
echo -n "  单节点 vm-learn RSS: "
curl -s --max-time 15 'http://localhost:8428/metrics' 2>/dev/null \
  | grep '^process_resident_memory_bytes' | head -1 \
  | awk '{printf "%.1f MB\n", $2/1048576}'

echo
echo "=============================================="
echo " R3 关键洞察：vmstorage 的缓存预分配"
echo "=============================================="
echo "  每个 vmstorage 都独立预分配缓存 —— 节点越多，固定开销越大"
for pair in "vmstorage-learn:8482" "vmstorage-learn2:8492"; do
  name="${pair%%:*}"; port="${pair##*:}"
  echo "  -- $name --"
  curl -s --max-time 15 "http://localhost:$port/metrics" 2>/dev/null \
    | grep -E 'vm_cache_size_bytes\{type="storage/(tsid|metricIDs)"' \
    | awk '{printf "     %-40s %.1f MB\n", $1, $2/1048576}'
done

echo
echo "=============================================="
echo " R4 磁盘占用对比"
echo "=============================================="
cd /mnt/d/projects/learning/victoriametrics/playground || exit 1
echo "  单节点 data/:      $(du -sh data 2>/dev/null | cut -f1)"
echo "  集群 storage/:     $(du -sh cluster-data/storage 2>/dev/null | cut -f1)"
echo "  集群 storage2/:    $(du -sh cluster-data/storage2 2>/dev/null | cut -f1)"

echo
echo "=============================================="
echo " R5 能力对比：集群能做什么单节点做不了"
echo "=============================================="
echo "  -- 多租户：集群有，单节点没有 --"
echo -n "    集群 /insert/42/ 写入: "
curl -s -X POST --max-time 10 --data-binary @/tmp/l08_shard.influx \
  'http://localhost:8480/insert/42/influx/write' -o /dev/null -w 'HTTP %{http_code}\n'
echo -n "    单节点 /insert/42/ 写入: "
curl -s -X POST --max-time 10 --data-binary @/tmp/l08_shard.influx \
  'http://localhost:8428/insert/42/influx/write' -o /dev/null -w 'HTTP %{http_code}\n'

echo
echo "  -- 租户 42 的数据能查到吗 --"
echo -n "    tenant 42: "
curl -s --max-time 30 --data-urlencode 'query=count(l08_shard_value)' \
  'http://localhost:8481/select/42/prometheus/api/v1/query' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print(int(float(r[0]["value"][1])) if r else 0, "条序列")' 2>&1

echo
echo "  -- 独立扩缩容：vmselect 可以单独加 --"
echo "    当前 vmselect 节点数: $(docker ps --filter name=vmselect-learn --format '{{.Names}}' | wc -l)"
echo "    可以再加一个 vmselect 分担查询压力，不动 vmstorage"

echo
echo "=============================================="
echo " R6 组件独立性验证：只停 vmselect，写入是否受影响"
echo "=============================================="
echo "  停掉 vmselect ..."
docker stop vmselect-learn >/dev/null 2>&1
sleep 3
echo -n "  写入 vminsert: "
curl -s -X POST --max-time 20 --data-binary @/tmp/l08_single.influx \
  'http://localhost:8480/insert/0/influx/write' -o /dev/null -w 'HTTP %{http_code} (应正常)\n'
echo -n "  查询 vmselect: "
curl -s -o /dev/null --max-time 10 --data-urlencode 'query=up' \
  'http://localhost:8481/select/0/prometheus/api/v1/query' -w 'HTTP %{http_code} (应失败)\n'
echo "  → 证明【写入与查询可以独立故障】，这是拆分的核心价值"

echo "  恢复 vmselect ..."
docker start vmselect-learn >/dev/null 2>&1
sleep 5
echo -n "  恢复后查询: "
curl -s -o /dev/null --max-time 15 --data-urlencode 'query=up' \
  'http://localhost:8481/select/0/prometheus/api/v1/query' -w 'HTTP %{http_code}\n'

echo
echo "=============================================="
echo " R7 vmselect 的查询聚合指标"
echo "=============================================="
curl -s --max-time 15 'http://localhost:8481/metrics' 2>/dev/null \
  | grep -E 'vm_vmselect|vm_select_|vm_concurrent' | head -10
