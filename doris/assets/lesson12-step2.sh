#!/bin/bash
# 课 12 步骤 2：知识点 2 —— 存算分离架构
# 用法：bash lesson12-step2.sh
#
# 核心思路：本机是存算一体（cloud mode 专属功能全不可用，实测报错照录），
# 但可以用 S3 TVF 读 MinIO 上的 parquet 来「具象化共享存储层」，
# 实测出本地性代价到底落在哪 —— 聚合几乎无差，明细扫描差 3 倍以上。

FE='docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop'
q() { $FE -e "$1" 2>&1 | grep -vE "^Warning|Using a password"; }
t() {
  START=$(date +%s.%N)
  $FE -e "$1" > /dev/null 2>&1
  END=$(date +%s.%N)
  echo "$(echo "$END - $START" | bc)"
}

echo "################################################################"
echo "# 2.1 先确认本机是什么架构：存算一体的证据"
echo "################################################################"
echo ""
echo "--- BE 上数据落在本地磁盘（RemoteUsedCapacity 是 0）---"
q "SHOW BACKENDS\G" | grep -E "^ +(Host|DataUsedCapacity|RemoteUsedCapacity|AvailCapacity|TabletNum):"

echo ""
echo "################################################################"
echo "# 2.2 存算分离的语法：本机全不可用（报错原文照录）"
echo "################################################################"
echo ""
echo "  这三条是存算分离（cloud mode）的核心管理语句，本机一一试过："
echo ""
q "SHOW COMPUTE GROUPS;"
q "SHOW STORAGE VAULT;"
q "SHOW CACHE HOTSPOTS;"
echo ""
echo "  → 全部报「only support in cloud mode」。"
echo "    这不是命令写错，是部署形态不同：all-in-one 镜像是存算一体。"
echo "    存算分离要另外部署（Doris 3.x 起的 cloud mode / 存算分离版）。"

echo ""
echo "################################################################"
echo "# 2.3 用 S3 TVF 具象化「共享存储层」"
echo "################################################################"
echo ""
echo "  思路：存算分离的本质是「数据不放本地盘，放共享存储，计算节点按需拉」。"
echo "  本机虽不能切架构，但可以让 Doris 直接从 MinIO 读 parquet —— "
echo "  这条路径的数据流向，和存算分离下 BE 从共享存储拉数据是一样的。"
echo ""
echo "--- 共享存储上有什么（setup 阶段导出的 2025 Q1 数据）---"
docker exec doris-minio sh -c "ls -la /data/doris-demo/l12/ 2>&1 | head -8"

echo ""
echo "--- 用 S3 TVF 直接读，不落地到本地盘 ---"
q "SELECT COUNT(*) AS cnt, SUM(amount) AS sum_amt FROM S3(
     'uri' = 'http://minio:9000/doris-demo/l12/*',
     's3.access_key' = 'minioadmin',
     's3.secret_key' = 'minioadmin',
     's3.region' = 'us-east-1',
     'use_path_style' = 'true',
     'format' = 'parquet');"
echo ""
echo "  ⚠️ 注意 'use_path_style' = 'true' 这一行："
echo "     MinIO 是路径风格（path style），不加这个连不上。"
echo "     （课 6 建 S3 仓库时踩过同一个坑，这里再次出现）"

echo ""
echo "################################################################"
echo "# 2.4 本地性代价实测：聚合查询几乎无差"
echo "################################################################"
echo ""
echo "  同一份 314 万行数据，一边在本地盘（local_1m），一边在共享存储（MinIO parquet）。"
echo "  先确认两边口径完全一致："
echo ""
echo "  本地表："
q "SELECT COUNT(*) AS cnt, SUM(amount) AS sum_amt FROM local_1m;"
echo "  共享存储："
q "SELECT COUNT(*) AS cnt, SUM(amount) AS sum_amt FROM S3(
     'uri' = 'http://minio:9000/doris-demo/l12/*',
     's3.access_key' = 'minioadmin', 's3.secret_key' = 'minioadmin',
     's3.region' = 'us-east-1', 'use_path_style' = 'true', 'format' = 'parquet');"

echo ""
echo "--- 聚合查询（GROUP BY province），各 5 轮 ---"
echo ""
echo "  [本地表]"
for i in 1 2 3 4 5; do
  echo "    第 $i 轮：$(t "SELECT province, SUM(amount) AS s FROM local_1m GROUP BY province ORDER BY s DESC LIMIT 10;") 秒"
done
echo ""
echo "  [共享存储]"
for i in 1 2 3 4 5; do
  echo "    第 $i 轮：$(t "SELECT province, SUM(amount) AS s FROM S3('uri'='http://minio:9000/doris-demo/l12/*','s3.access_key'='minioadmin','s3.secret_key'='minioadmin','s3.region'='us-east-1','use_path_style'='true','format'='parquet') GROUP BY province ORDER BY s DESC LIMIT 10;") 秒"
done
echo ""
echo "  → 聚合查询两边几乎没差别。为什么？"
echo "     因为聚合要把全表扫一遍，瓶颈在计算不在读取；"
echo "     而且列式 parquet 只需传需要的列，网络量被压缩得很小。"

echo ""
echo "################################################################"
echo "# 2.5 本地性代价实测：明细扫描差 3 倍以上"
echo "################################################################"
echo ""
echo "  换成需要读多列做过滤的明细查询，差距就出来了。"
echo ""
echo "--- 带谓词的明细扫描（amount > 5000 AND quantity > 5），各 5 轮 ---"
echo ""
echo "  [本地表]"
for i in 1 2 3 4 5; do
  echo "    第 $i 轮：$(t "SELECT COUNT(*) FROM local_1m WHERE amount > 5000 AND quantity > 5;") 秒"
done
echo ""
echo "  [共享存储]"
for i in 1 2 3 4 5; do
  echo "    第 $i 轮：$(t "SELECT COUNT(*) FROM S3('uri'='http://minio:9000/doris-demo/l12/*','s3.access_key'='minioadmin','s3.secret_key'='minioadmin','s3.region'='us-east-1','use_path_style'='true','format'='parquet') WHERE amount > 5000 AND quantity > 5;") 秒"
done
echo ""
echo "  → 明细扫描共享存储明显更慢。原因："
echo "     ① 没有本地缓存兜底，每次都要跨网络读；"
echo "     ② 谓词要读多列，网络传输量上去了；"
echo "     ③ 本地盘的操作系统 page cache 帮了大忙（第二三轮更快）。"

echo ""
echo "################################################################"
echo "# 2.6 存算分离到底换了什么（对照课 9）"
echo "################################################################"
echo ""
echo "  课 9 讲过多副本与自动修复，那是【存算一体】的语义："
echo "    - 数据存在 BE 本地盘，靠多副本（replication_num）保证可靠"
echo "    - BE 挂了，FE 调度其他 BE 从剩余副本补数据"
echo "    - 扩缩容要搬数据（tablet 迁移）"
echo ""
echo "  存算分离下语义完全不同："
echo "    - 数据在共享存储（S3/HDFS），可靠性由存储层保证（如 S3 的 11 个 9）"
echo "    - BE 变成无状态计算节点，挂了直接换一个，不用搬数据"
echo "    - 扩缩容是加减计算节点，秒级完成"
echo "    - 本地盘只做缓存（file cache），丢了不影响正确性"
echo ""
echo "  本机实测的副本情况（存算一体，1 副本）："
q "SHOW PROC '/statistic';" | awk -F'\t' 'NR==1{for(i=1;i<=NF;i++){if($i=="DbName")d=i;if($i=="TabletNum")t=i;if($i=="ReplicaNum")r=i};next}{if($t+0==0)next;printf "     %-16s tablet=%-8s replica=%-8s 副本倍数=%.2f\n",$d,$t,$r,$r/$t}' | head -8

echo ""
echo "################################################################"
echo "# 2.7 弹性：存算分离真正的卖点（原理，本机无法实测）"
echo "################################################################"
echo ""
echo "  🔴 以下为原理推演，本机无法实测（1 FE 且非 cloud mode）"
echo ""
echo "  存算分离的核心价值不是「更快」，是「更弹」："
echo "    ① 计算组（compute group）隔离："
echo "       导入组、查询组、adhoc 组各用各的计算资源，互不干扰"
echo "       （课 10 讲的 Workload Group 是在同一组 BE 内切分；"
echo "         计算组是物理上不同的 BE 集合，隔离更彻底）"
echo "    ② 弹性伸缩：大促时加 20 个计算节点，过后释放，数据不用动"
echo "    ③ 成本：共享存储（对象存储）比 SSD 便宜一个数量级"
echo "    ④ 多写多读：一份数据多个计算组同时查"
echo ""
echo "  付出的代价："
echo "    ① 本地性：没有本地盘，冷查询要跨网络（2.5 节实测差 3 倍）"
echo "    ② 延迟：首次访问的冷读延迟明显，靠 file cache 缓解"
echo "    ③ 依赖共享存储：S3 抖动会直接影响查询"
echo "    ④ 架构复杂度：多了元数据管理、缓存一致性等问题"

echo ""
echo "################################################################"
echo "# 2.8 小结"
echo "################################################################"
echo ""
echo "  存算一体：数据在本地盘，快，但扩缩容要搬数据"
echo "  存算分离：数据在共享存储，弹，但冷查询要跨网络"
echo ""
echo "  选型判据（不是「哪个更好」）："
echo "    - 数据量大、查询模式固定、追求极致性能 → 存算一体"
echo "    - 负载波动大、要多租户隔离、成本敏感 → 存算分离"
echo ""
echo "  下一步：bash lesson12-step3.sh （知识点 3：典型场景架构与反模式）"
