#!/usr/bin/env bash
# 课 3 精确验证（v2）：gap 填补 + 保留指标名的真实边界
# 用独立 python 文件格式化，避免 heredoc 引号转义问题
set -u
BASE="http://localhost:8428"
FMT=/mnt/d/projects/learning/victoriametrics/playground/l03-fmt.py
. /tmp/l3_meta.env

q() {
  local label="$1" query="$2"; shift 2
  echo "--- $label ---"
  echo "    query: $query"
  curl -s -m 20 -G "$BASE/api/v1/query" \
    --data-urlencode "query=$query" "$@" | python3 "$FMT"
}

echo "########## A. 保留指标名：到底哪些函数保留？##########"
q "A1 round()      [文档称保留]" 'round(l3_gappy)'             --data-urlencode "nocache=1"
q "A2 ceil()       [文档称保留]" 'ceil(l3_gappy)'              --data-urlencode "nocache=1"
q "A3 clamp_max()  [文档称保留]" 'clamp_max(l3_gappy, 1000)'   --data-urlencode "nocache=1"
q "A4 min_over_time()"           'min_over_time(l3_gappy[5m])' --data-urlencode "nocache=1"
q "A5 max_over_time()"           'max_over_time(l3_gappy[5m])' --data-urlencode "nocache=1"
q "A6 sum_over_time()"           'sum_over_time(l3_gappy[5m])' --data-urlencode "nocache=1"
q "A7 abs()"                     'abs(l3_gappy)'               --data-urlencode "nocache=1"
q "A8 rate()       [语义改变]"    'rate(l3_counter_total[5m])'  --data-urlencode "nocache=1"

echo
echo "########## B. gap 填补（精确命中 gap 中点）##########"
echo "  gap 区间: $(date -d @${L3_GAP_START} '+%H:%M:%S') -> $(date -d @${L3_GAP_END} '+%H:%M:%S')"
echo "  取样点  : $(date -d @${L3_GAP_MID} '+%H:%M:%S')"
q "B1 原始值（gap 处应为空）" 'l3_gappy'                  --data-urlencode "time=$L3_GAP_MID" --data-urlencode "nocache=1"
q "B2 keep_last_value 填补"  'keep_last_value(l3_gappy)' --data-urlencode "time=$L3_GAP_MID" --data-urlencode "nocache=1"
q "B3 keep_next_value 填补"  'keep_next_value(l3_gappy)' --data-urlencode "time=$L3_GAP_MID" --data-urlencode "nocache=1"
q "B4 default 填 -1"         'l3_gappy default -1'       --data-urlencode "time=$L3_GAP_MID" --data-urlencode "nocache=1"
q "B5 对照：gap 外一点"       'l3_gappy'                  --data-urlencode "time=$((L3_GAP_START-60))" --data-urlencode "nocache=1"
