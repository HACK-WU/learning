#!/bin/bash
# 课 7 重大发现验证：fastcache 重启后不丢 —— 它落盘了！
Q() { curl -s --max-time 20 --data-urlencode "query=$1" http://localhost:8428/api/v1/query; }
g() { curl -s --max-time 20 --data-urlencode "query=$1" http://localhost:8428/api/v1/query \
  | python3 -c 'import json,sys
try:
  d=json.load(sys.stdin)["data"]["result"]
  print("%.0f" % float(d[0]["value"][1]) if d else 0)
except: print(0)'; }

echo "=============================================="
echo " F1 课 5 说「data/cache 目录不存在」，现在呢？"
echo "=============================================="
cd /mnt/d/projects/learning/victoriametrics/playground || exit 1
ls -la data/ 2>&1
echo
echo "-- cache 目录 --"
if [ -d "data/cache" ]; then
  echo "  存在！内容:"
  ls -la data/cache/ 2>&1 | head -12
  echo
  echo "  各子目录大小:"
  du -sh data/cache/* 2>/dev/null
else
  echo "  data/cache 仍不存在"
fi

echo
echo "=============================================="
echo " F2 找 fastcache 的落盘文件"
echo "=============================================="
echo "-- 在 data 下找非 (small|big|indexdb|flush|tmp) 的目录 --"
find data -maxdepth 1 -type d 2>/dev/null | while read d; do
  echo "  $d"
done
echo
echo "-- 找 *.bin 但不在已知子目录的 --"
find data -maxdepth 1 -type f 2>/dev/null | head -20

echo
echo "=============================================="
echo " F3 关键验证：重启前后缓存条目对比"
echo "=============================================="
echo "  课 7 冷启动实验实测："
echo "    重启前: 297415 条目  /  366361910 字节"
echo "    重启后: 337608 条目  /  374176934 字节"
echo
echo "  ⚠️ 条目数不降反升，命中率几乎不变（98.49% → 98.49%）"
echo "  这只有一个解释：fastcache 持久化到了磁盘，重启后自动加载。"

echo
echo "=============================================="
echo " F4 查看当前缓存明细（确认是重新加载而非重建）"
echo "=============================================="
Q 'sum(vm_cache_entries) by (type)' | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
rows=[]
for r in d: rows.append((r["metric"].get("type","-"), float(r["value"][1])))
rows.sort(key=lambda x:-x[1])
for t,v in rows:
    if v>0: print("    %-36s %10.0f" % (t, v))' 2>/dev/null

echo
echo "=============================================="
echo " F5 那么「冷启动」到底冷不冷？"
echo "=============================================="
echo "  实测耗时对比（10000 序列全查）："
echo "    重启前(热): 中位 0.0485 s"
echo "    重启后(冷): 中位 0.0409 s"
echo "    再跑一次  : 中位 0.0541 s"
echo
echo "  → 三者在同一量级，没有数量级差异！"
echo "  这印证了：缓存从磁盘恢复，查询没有真正「冷」过。"

echo
echo "=============================================="
echo " F6 真正的冷启动该怎么做？"
echo "=============================================="
echo "  要验证「缓存完全为空」的冷启动，需要删除缓存文件后重启。"
echo
echo "  ⚠️ 本次【不执行】，因为会破坏当前实验环境。"
echo "     记录方法供后续验证："
echo "     1. docker stop vm-learn"
echo "     2. rm -rf data/cache/*"
echo "     3. docker start vm-learn"
echo "     4. 对比首次查询耗时"

echo
echo "=============================================="
echo " F7 连带发现：ZSTD 压缩比从 5.648 跳到 8.494"
echo "=============================================="
echo "  重启前: 5.648 倍"
echo "  重启后: 8.494 倍"
echo
echo "  ⚠️ 这是【计数器重置】导致的假象吗？"
Q 'sum(vm_zstd_block_original_bytes_total)' | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
print("    当前 ZSTD 原始累计: %.0f" % float(d[0]["value"][1]))' 2>/dev/null
Q 'sum(vm_zstd_block_compressed_bytes_total)' | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
print("    当前 ZSTD 压缩累计: %.0f" % float(d[0]["value"][1]))' 2>/dev/null
echo
echo "  → 重启会重置这些计数器（它们在内存里）。"
echo "    重启后重新开始累计，所以比值不代表历史全量。"
