#!/bin/bash
# 课 9 收官：容量代价量化 + dedup 边界 + 与单节点对比
set -u
q() {
  curl -s --max-time 60 --data-urlencode "query=$1" \
    "http://localhost:$2/select/0/prometheus/api/v1/query" \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print(int(sum(float(x["value"][1]) for x in r)) if r else 0)' 2>/dev/null
}

echo "=============================================="
echo " K1 容量代价：RF=2 让磁盘/内存翻倍了吗？"
echo "=============================================="
echo "  -- 各 vmstorage 的 tsid 条目（RF=2 后应接近相等）--"
echo -n "    vmstorage1: "
curl -s --max-time 15 'http://localhost:8482/metrics' 2>/dev/null \
  | grep 'vm_cache_entries{type="storage/tsid"' | head -1 | awk '{print $2}'
echo -n "    vmstorage2: "
curl -s --max-time 15 'http://localhost:8492/metrics' 2>/dev/null \
  | grep 'vm_cache_entries{type="storage/tsid"' | head -1 | awk '{print $2}'

echo
echo "  -- 内存占用 --"
for pair in "vmstorage-learn:8482" "vmstorage-learn2:8492"; do
  n="${pair%%:*}"; p="${pair##*:}"
  echo -n "    $n RSS: "
  curl -s --max-time 15 "http://localhost:$p/metrics" 2>/dev/null \
    | grep '^process_resident_memory_bytes' | head -1 \
    | awk '{printf "%.1f MB\n", $2/1048576}'
done
echo -n "    单节点 vm-learn RSS: "
curl -s --max-time 15 'http://localhost:8428/metrics' 2>/dev/null \
  | grep '^process_resident_memory_bytes' | head -1 \
  | awk '{printf "%.1f MB\n", $2/1048576}'

echo
echo "  -- 磁盘占用 --"
cd /mnt/d/projects/learning/victoriametrics/playground || exit 1
echo "    单节点 data/:   $(du -sh data 2>/dev/null | cut -f1)"
echo "    集群 storage/:  $(du -sh cluster-data/storage 2>/dev/null | cut -f1)"
echo "    集群 storage2/: $(du -sh cluster-data/storage2 2>/dev/null | cut -f1)"

echo
echo "=============================================="
echo " K2 dedup 的边界：minScrapeInterval 该设多少"
echo "=============================================="
echo "  规则：应设为【采集间隔】或略大。设太大会误删正常数据。"
echo
echo "  -- 用不同间隔测试（数据间隔 5 秒）--"
M="l09_dw_$(date +%s)"
python3 - "$M" <<'PY'
import sys, time
mark = sys.argv[1]
now = int(time.time()) - 300
lines = []
# 每 5 秒一个点，共 12 个点（跨 60 秒）
for i in range(12):
    ts = (now + i*5) * 1000000000
    lines.append("%s,idx=0 value=%d %d" % (mark, i, ts))
open("/tmp/l09_dw.influx","w").write("\n".join(lines)+"\n")
print("  写入 %s: 12 个点，间隔 5 秒，跨 60 秒" % mark)
PY
curl -s -X POST --max-time 30 --data-binary @/tmp/l09_dw.influx \
  'http://localhost:8480/insert/0/influx/write' -o /dev/null -w '  写入 HTTP %{http_code}\n'
sleep 10

Q="count_over_time(${M}_value[10m])"
echo "    无 dedup (8481):        $(q "$Q" 8481) 个样本"
echo "    dedup=30s (8487):      $(q "$Q" 8487) 个样本"

echo
echo "  -- 再起一个 dedup=5s 的 vmselect (8489) --"
docker rm -f vmsel-d5 >/dev/null 2>&1
docker run -d --name vmsel-d5 --network vm-cluster-net -p 8489:8481 \
  victoriametrics/vmselect:v1.151.0-cluster \
  -storageNode=vmstorage-learn:8401 -storageNode=vmstorage-learn2:8401 \
  -dedup.minScrapeInterval=5s -httpListenAddr=:8481 >/dev/null 2>&1
for i in $(seq 1 30); do
  a=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 'http://localhost:8489/health' 2>/dev/null)
  if [ "$a" = "200" ]; then break; fi
  sleep 2
done
echo "    dedup=5s  (8489):      $(q "$Q" 8489) 个样本"
echo
echo "  → 数据间隔 5 秒时：dedup=5s 保留 ~12 个，dedup=30s 只保留 ~2 个"
echo "    说明 dedup 间隔必须【等于或略大于】真实采集间隔"

echo
echo "=============================================="
echo " K3 dedup 的代价：查询性能"
echo "=============================================="
echo "  -- 相同查询，开/关 dedup 的耗时对比 --"
for p in 8481 8487; do
  label=$([ "$p" = "8481" ] && echo "无 dedup" || echo "有 dedup(30s)")
  T=$(curl -s -o /dev/null -w '%{time_total}' --max-time 60 \
      --data-urlencode "query=count_over_time(${M}_value[10m])" \
      "http://localhost:$p/select/0/prometheus/api/v1/query")
  echo "    $label: ${T}s"
done

echo
echo "=============================================="
echo " K4 单节点版的 dedup（对照）"
echo "=============================================="
echo "  单节点 vm-learn 是否支持 dedup？"
docker run --rm victoriametrics/victoria-metrics:latest --help 2>&1 \
  | grep -A2 'dedup.minScrapeInterval' | head -4

echo
echo "=============================================="
echo " K5 决策清单验证：副本数该怎么选"
echo "=============================================="
echo "  当前集群: 2 个 vmstorage, RF=2"
echo
echo "  如果 RF=3 但只有 2 个节点会怎样？"
docker rm -f vmi-test-rf3 >/dev/null 2>&1
docker run -d --name vmi-test-rf3 --network vm-cluster-net \
  victoriametrics/vminsert:v1.151.0-cluster \
  -storageNode=vmstorage-learn:8400 -storageNode=vmstorage-learn2:8400 \
  -replicationFactor=3 -httpListenAddr=:8480 >/dev/null 2>&1
sleep 5
echo "  -- RF=3 (仅 2 节点) 的日志 --"
docker logs vmi-test-rf3 2>&1 | grep -iE 'replication|copy|warn' | head -5
docker rm -f vmi-test-rf3 >/dev/null 2>&1

echo
echo "=============================================="
echo " K6 关键指标：如何监控副本健康"
echo "=============================================="
echo "  -- vminsert 的副本相关指标 --"
curl -s --max-time 15 'http://localhost:8480/metrics' 2>/dev/null \
  | grep -iE 'vm_insert_|vm_rpc_' | head -12
echo
echo "  -- 如何发现副本缺口：查日志 --"
echo "     docker logs vminsert-learn 2>&1 | grep 'cannot make a copy'"
echo "     当前累计次数: $(docker logs vminsert-learn 2>&1 | grep -c 'cannot make a copy')"
