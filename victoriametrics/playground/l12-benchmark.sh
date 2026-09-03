#!/bin/bash
# 课 12 实验 23：选型决策的硬数据 —— 压缩率 / 资源占用 / 降采样 / 删除代价
set -u
cd /mnt/d/projects/learning/victoriametrics/playground
VM=http://localhost:8428
PROM=http://localhost:9090

echo "===== [1] 压缩率对照：同样的数据在 VM 与 Prometheus 各占多少 ====="
echo "-- Prometheus 数据目录 --"
docker exec prom-learn sh -c "du -sk /prometheus 2>/dev/null | tail -1"
echo "-- Prometheus 序列数 --"
curl -s "$PROM/api/v1/query?query=count(up)" > /dev/null 2>&1
curl -s "$PROM/api/v1/label/__name__/values" | python3 -c "import sys,json;print('  Prometheus 指标名数 =',len(json.load(sys.stdin)['data']))"
echo "-- VM 数据目录 --"
du -sk ./data | tail -1
echo "-- VM 序列数 --"
curl -s $VM/api/v1/series/count | python3 -c "import sys,json;print('  VM 序列数 =',json.load(sys.stdin)['data'][0])"

echo ""
echo "===== [2] 内存占用对照 ====="
echo "-- VM 单节点 --"
docker stats --no-stream --format "  {{.Name}}  MEM={{.MemUsage}}" vm-learn
echo "-- Prometheus --"
docker stats --no-stream --format "  {{.Name}}  MEM={{.MemUsage}}" prom-learn

echo ""
echo "===== [3] 降采样（社区版 vs 企业版）—— VM 的核心差异点 ====="
echo "-- 查 VM 是否有降采样相关 flag --"
docker exec vm-learn sh -c '/victoria-metrics-prod --help 2>&1 | grep -iE "downsampl|retentionFilter" | head -10' 2>&1 | head -12

echo ""
echo "===== [4] 查询性能对照：同样的聚合查询在两端耗时 ====="
echo "-- VM --"
for q in "count(up)" "sum(rate(up[5m]))" "max_over_time(up[1h])"; do
  curl -s -o /dev/null -w "  VM   $q -> %{time_total}s\n" --data-urlencode "query=$q" "$VM/api/v1/query"
done
echo "-- Prometheus --"
for q in "count(up)" "sum(rate(up[5m]))" "max_over_time(up[1h])"; do
  curl -s -o /dev/null -w "  PROM $q -> %{time_total}s\n" --data-urlencode "query=$q" "$PROM/api/v1/query"
done

echo ""
echo "===== [5] 删除的代价：删除后磁盘是否立即释放 ====="
echo "-- 写入 50000 条数据 --"
: > /tmp/l12_bigdel.txt
for i in $(seq 1 50000); do
  printf 'l12_bigdel{job="l12",i="%s"} %s %s000\n' "$i" "$i" "$(date +%s)" >> /tmp/l12_bigdel.txt
done
DF1=$(du -sk ./data | awk '{print $1}')
S1=$(curl -s $VM/api/v1/series/count | python3 -c "import sys,json;print(json.load(sys.stdin)['data'][0])")
echo "  写入前: 磁盘=${DF1}KB 序列=$S1"
curl -s -o /dev/null -w "  写入 HTTP=%{http_code}\n" -X POST --data-binary @/tmp/l12_bigdel.txt "$VM/api/v1/import/prometheus"
sleep 5
DF2=$(du -sk ./data | awk '{print $1}')
S2=$(curl -s $VM/api/v1/series/count | python3 -c "import sys,json;print(json.load(sys.stdin)['data'][0])")
echo "  写入后: 磁盘=${DF2}KB 序列=$S2  (磁盘增 $((DF2-DF1))KB)"

echo "-- 删除这 50000 条 --"
curl -s -o /dev/null -w "  删除 HTTP=%{http_code}\n" -X POST "$VM/api/v1/admin/tsdb/delete_series" --data-urlencode 'match[]=l12_bigdel'
sleep 8
DF3=$(du -sk ./data | awk '{print $1}')
S3=$(curl -s $VM/api/v1/series/count | python3 -c "import sys,json;print(json.load(sys.stdin)['data'][0])")
echo "  删除后: 磁盘=${DF3}KB 序列=$S3"
echo "  >> 磁盘变化 = $((DF3-DF2))KB  ← 若为正或接近 0，说明删除不立即释放空间"

echo ""
echo "===== [6] 集群版才有而单节点没有的能力（选型关键） ====="
echo "-- 多租户 --"
curl -s -o /dev/null -w "  单节点 /insert/42/prometheus HTTP=%{http_code}\n" -X POST --data-binary 'l12_t{job="x"} 1' "http://localhost:8428/insert/42/prometheus/api/v1/import"
curl -s -o /dev/null -w "  集群   /insert/42/prometheus HTTP=%{http_code}\n" -X POST --data-binary 'l12_t{job="x"} 1' "http://localhost:8480/insert/42/prometheus/api/v1/import/prometheus"
