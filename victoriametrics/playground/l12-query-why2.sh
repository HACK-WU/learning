#!/bin/bash
# 课 12 实验 29：定位「新写入查不到」—— 查 maxLabelsPerTimeseries 等写入侧限制
set -u
cd /mnt/d/projects/learning/victoriametrics/playground
VM=http://localhost:8428

echo "===== [1] 容器完整启动参数 ====="
docker inspect vm-learn --format '{{range .Args}}{{.}}{{"\n"}}{{end}}'

echo ""
echo "===== [2] 关键怀疑：maxLabelsPerTimeseries 是否有非默认配置 ====="
docker exec vm-learn sh -c '/victoria-metrics-prod --help 2>&1 | grep -A3 "maxLabelsPerTimeseries" | head -6'

echo ""
echo "===== [3] 对照实验：往「集群」写入同样的探针，看是否也查不到 ====="
echo "-- 单节点 --"
curl -s -o /dev/null -w "  vm-learn:8428 写入 HTTP=%{http_code}\n" -X POST \
  --data-binary 'l12_cmp_test{job="l12"} 42' "$VM/api/v1/import/prometheus"
echo "-- 集群 tenant 0 --"
curl -s -o /dev/null -w "  vminsert:8480 写入 HTTP=%{http_code}\n" -X POST \
  --data-binary 'l12_cmp_test{job="l12"} 42' "http://localhost:8480/insert/0/prometheus/api/v1/import/prometheus"
sleep 3
echo "-- 单节点查 --"
curl -s --data-urlencode 'query=l12_cmp_test' "$VM/api/v1/query" | head -c 200; echo
echo "-- 集群查 --"
curl -s --data-urlencode 'query=l12_cmp_test' "http://localhost:8481/select/0/prometheus/api/v1/query" | head -c 200; echo

echo ""
echo "===== [4] 决定性实验：查刚写入数据的时间戳到底落在哪 ====="
echo "-- 用 query_range 大范围查（过去 1 小时到未来 1 小时） --"
NOW=$(date +%s)
curl -s --data-urlencode 'query=l12_cmp_test' \
  --data-urlencode "start=$((NOW-3600))" --data-urlencode "end=$((NOW+3600))" --data-urlencode 'step=60' \
  "$VM/api/v1/query_range" | head -c 300; echo

echo ""
echo "===== [5] 用 /api/v1/export 直接导出（绕过查询层，看数据到底在不在存储里） ====="
curl -s --data-urlencode 'match[]=l12_cmp_test' "$VM/api/v1/export" 2>&1 | head -c 400; echo
echo "-- 对照：导出一个已知存在的指标 --"
curl -s --data-urlencode 'match[]=up' "$VM/api/v1/export" 2>&1 | head -c 300; echo

echo ""
echo "===== [6] 检查是不是 relabelConfig 生效导致的问题 ====="
echo "-- 去掉 relabel 配置试写（用集群，集群无此配置） --"
curl -s -o /dev/null -w "  集群写入 l12_norelabel HTTP=%{http_code}\n" -X POST \
  --data-binary 'l12_norelabel{job="l12"} 88' "http://localhost:8480/insert/0/prometheus/api/v1/import/prometheus"
sleep 2
curl -s --data-urlencode 'query=l12_norelabel' "http://localhost:8481/select/0/prometheus/api/v1/query" | head -c 250; echo
