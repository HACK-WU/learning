#!/bin/bash
# 课 12 实验 33：决定性 —— 秒级 vs 毫秒级时间戳 + 延迟可见性（迁移验证必知）
set -u
cd /mnt/d/projects/learning/victoriametrics/playground
CLEAN=http://localhost:8458

echo "===== [1] 复查：之前查不到的，现在能查到吗（延迟可见性） ====="
for n in l12_ts_a l12_ts_b l12_ts_c l12_single l12_multi; do
  echo -n "  $n query = "
  curl -s --data-urlencode "query=$n" "$CLEAN/api/v1/query" \
    | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print('查得到 值='+r[0]['value'][1] if r else '查不到')" 2>&1 | head -1
done

echo ""
echo "===== [2] 决定性：秒级 vs 毫秒级时间戳（这是写入查不到的真正原因） ====="
SEC=$(date +%s)
MS="${SEC}000"
echo "  当前秒级时间戳 = $SEC"
echo "  当前毫秒时间戳 = $MS"
echo "-- 写入：秒级时间戳（错误用法） --"
curl -s -o /dev/null -w "  HTTP=%{http_code}\n" -X POST --data-binary "l12_sec_ts{job=\"l12\"} 111 $SEC" "$CLEAN/api/v1/import/prometheus"
echo "-- 写入：毫秒级时间戳（正确用法） --"
curl -s -o /dev/null -w "  HTTP=%{http_code}\n" -X POST --data-binary "l12_ms_ts{job=\"l12\"} 222 $MS" "$CLEAN/api/v1/import/prometheus"
echo "-- 写入：不带时间戳 --"
curl -s -o /dev/null -w "  HTTP=%{http_code}\n" -X POST --data-binary 'l12_no_ts{job="l12"} 333' "$CLEAN/api/v1/import/prometheus"
sleep 3

echo ""
echo "===== [3] 用 export 看它们实际落在哪个时间点 ====="
for n in l12_sec_ts l12_ms_ts l12_no_ts; do
  echo -n "  $n export = "
  curl -s --data-urlencode "match[]=$n" "$CLEAN/api/v1/export" | head -c 200; echo
done

echo ""
echo "===== [4] 查询对照 ====="
for n in l12_sec_ts l12_ms_ts l12_no_ts; do
  echo -n "  $n query = "
  curl -s --data-urlencode "query=$n" "$CLEAN/api/v1/query" \
    | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print('查得到 值='+r[0]['value'][1] if r else '查不到')" 2>&1 | head -1
done

echo ""
echo "===== [5] 把秒级时间戳换算成日期，看它落在哪一年 ====="
python3 -c "
import datetime
sec=$SEC
print('  秒级时间戳', sec, '被当作毫秒解析 ->', datetime.datetime.fromtimestamp(sec/1000).strftime('%Y-%m-%d %H:%M:%S'))
print('  毫秒时间戳', ${MS}, '正确解析 ->', datetime.datetime.fromtimestamp(${MS}/1000).strftime('%Y-%m-%d %H:%M:%S'))
"

echo ""
echo "===== [6] 检查 small_timestamp 丢弃计数（秒级时间戳会被判为太旧） ====="
curl -s "$CLEAN/api/v1/query?query=sum%20by%20(reason)%20(vm_rows_ignored_total)" | head -c 400; echo

echo ""
echo "===== [7] 对课程的意义：迁移验证必须用毫秒时间戳 ====="
echo "  -- 用 export 验证（最可靠，绕过 staleness） --"
curl -s --data-urlencode 'match[]=l12_ms_ts' "$CLEAN/api/v1/export" | head -c 200; echo
