#!/bin/bash
# 清理课 5 临时验证索引，保留 news / news_ik / shop 等课程资产
ES="https://localhost:9200"
PW="ESlearn2026"

for i in l5_shop_bad l5_datecheck l5_wrong l5_right l5_trap l5_trap_v2 l5_logs-2026.08.31; do
  printf "%-24s " "$i"
  curl.exe -s -k -u elastic:$PW -X DELETE "$ES/$i"
  echo ""
done

echo -n "index_template           "
curl.exe -s -k -u elastic:$PW -X DELETE "$ES/_index_template/l5_logs_template"
echo ""

echo ""
echo "--- 清理后剩余索引 ---"
curl.exe -s -k -u elastic:$PW "$ES/_cat/indices?v"
echo ""
echo "--- 集群健康 ---"
curl.exe -s -k -u elastic:$PW "$ES/_cluster/health?filter_path=status,active_shards_percent_as_number"
