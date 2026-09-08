#!/usr/bin/env bash
D=/mnt/d/projects/learning/prometheus/labs/lesson-12
P=http://localhost:19500

echo "===== 为什么 clean_tombstones 没释放磁盘？ ====="
echo "假设：数据在 head block（未落盘），clean_tombstones 只处理已落盘的 block"
echo
echo "--- data 目录结构 ---"
docker exec l12-prom sh -c "ls -la /prometheus | head -20"
echo
echo "--- chunks_head 与 wal 大小 ---"
docker exec l12-prom sh -c "du -sk /prometheus/chunks_head /prometheus/wal 2>/dev/null"
echo
echo "--- 有几个 block？ ---"
docker exec l12-prom sh -c "ls -d /prometheus/01* 2>/dev/null | wc -l"
echo
echo "--- tsdb 状态中的 block 列表 ---"
curl -s $P/api/v1/status/tsdb | python3 -c "
import json,sys
d=json.load(sys.stdin)['data']
print('blocks:', len(d.get('blocks',[])))
for b in d.get('blocks',[])[:5]: print('  ', b)
" 2>&1
