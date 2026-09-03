#!/bin/bash
# 课 7 开课环境检查：容器 + 端口 + 数据基线 + 缓存指标全景
Q() { curl -s --max-time 15 --data-urlencode "query=$1" http://localhost:8428/api/v1/query; }

echo "=============================================="
echo " E1 容器状态"
echo "=============================================="
docker ps -a --format 'table {{.Names}}\t{{.Status}}' 2>&1

echo
echo "=============================================="
echo " E2 端口可达性"
echo "=============================================="
for p in 8428 9090; do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://localhost:$p/-/healthy" 2>/dev/null)
  [ "$code" = "000" ] && code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://localhost:$p/health" 2>/dev/null)
  echo "  port $p -> HTTP $code"
done

echo
echo "=============================================="
echo " E3 缓存相关指标全景（课 7 主角）"
echo "=============================================="
curl -s --max-time 15 'http://localhost:8428/api/v1/label/__name__/values' \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)['data']
keys=['cache','memory','mem_','malloc','gc_','go_','search','query','block']
hit=[m for m in d if any(k in m.lower() for k in keys)]
print('  总指标数:',len(d))
print('  缓存/内存/查询相关指标:')
for m in sorted(hit): print('   ',m)
" 2>&1

echo
echo "=============================================="
echo " E4 当前数据基线"
echo "=============================================="
cd /mnt/d/projects/learning/victoriametrics/playground || exit 1
echo "  总序列数:"
Q 'sum(vm_cache_entries{type="storage/hour_metric_ids"})' | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
print("    hour_metric_ids:", int(float(d[0]["value"][1])) if d else "无")' 2>/dev/null
echo "  磁盘占用:"
du -sh data/ 2>&1
echo
echo "  ZSTD 压缩比:"
Q 'sum(vm_zstd_block_original_bytes_total)/sum(vm_zstd_block_compressed_bytes_total)' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
print("    %.3f 倍" % float(d[0]["value"][1]))' 2>/dev/null

echo
echo "=============================================="
echo " E5 cache/ 目录（课 5 提过但未展开）"
echo "=============================================="
for d in data/cache data/cache/fastcache data/cache/blocks; do
  if [ -d "$d" ]; then
    echo "  $d :"
    ls -la "$d" 2>&1 | head -8
  else
    echo "  $d : 不存在"
  fi
done

echo
echo "=============================================="
echo " E6 内存使用（Go runtime）"
echo "=============================================="
Q 'vm_memory_usage_bytes' | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
for r in d: print("    %-24s %12.0f 字节" % (r["metric"].get("type","-"), float(r["value"][1])))' 2>/dev/null
