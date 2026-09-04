#!/bin/bash
# 课 11 步骤 3：知识点 3 —— 监控告警与集群升级
# 用法：bash lesson11-step3.sh
#
# ⚠️ 边界说明：本机是 1 FE + 2 BE 的伪多节点（host 都是 127.0.0.1），
#    真正的滚动升级（多 FE 切换 Master）无法实机演练，本脚本只做
#    「可观测项」的实地采集 + 升级顺序的原理验证。
FE='docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop'
q() { $FE -e "$1" 2>&1 | grep -vE "^Warning|Using a password"; }
mfe() { docker exec doris-learn curl -s http://127.0.0.1:8030/metrics | grep -E "$1" | grep -vE '^#'; }
mbe() { docker exec doris-learn curl -s http://127.0.0.1:8040/metrics | grep -E "$1" | grep -vE '^#'; }

echo "##################################################################"
echo "# 3.1 监控数据从哪来：FE 和 BE 各有一个 Prometheus 端点              #"
echo "##################################################################"
echo "  FE 端点: http://<fe_host>:8030/metrics"
echo "  BE 端点: http://<be_host>:8040/metrics （第二个 BE 是 18040）"
echo "--- 各端点指标条数 ---"
echo "  FE: $(docker exec doris-learn curl -s http://127.0.0.1:8030/metrics | grep -cE '^doris_fe_')"
echo "  BE1: $(docker exec doris-learn curl -s http://127.0.0.1:8040/metrics | grep -cE '^doris_be_')"
echo "  BE2: $(docker exec doris-learn curl -s http://127.0.0.1:18040/metrics | grep -cE '^doris_be_')"

echo ""
echo "##################################################################"
echo "# 3.2 查询侧指标（FE）                                               #"
echo "##################################################################"
echo "--- QPS / 错误率 / 累计错误数 ---"
mfe '^doris_fe_qps|^doris_fe_query_err_rate|^doris_fe_query_err ' | sed 's/^/  /'
echo "--- 解读要点 ---"
cat <<'EOF'
  doris_fe_qps              查询吞吐，突降要警惕（可能是 FE 卡住或连接打满）
  doris_fe_query_err_rate   错误率，非 0 就要看 audit log
  doris_fe_query_err        累计错误数（按 user 维度拆分）
EOF

echo ""
echo "##################################################################"
echo "# 3.3 副本健康指标（FE）—— 这是最重要的一类                          #"
echo "##################################################################"
echo "--- SHOW PROC '/statistic'：TabletNum vs ReplicaNum ---"
q "SHOW PROC '/statistic';"
echo "  >> 判据：ReplicaNum / TabletNum = 实际副本倍数。看下面自动算出来的值："
q "SHOW PROC '/statistic';" | awk -F'\t' '
NR==1 { for(i=1;i<=NF;i++){ if($i=="TabletNum") t=i; if($i=="ReplicaNum") r=i; if($i=="DbName") d=i } ; next }
{ if ($t+0 == 0) next; printf "     %-20s tablet=%-8s replica=%-8s 副本倍数=%.2f\n", $d, $t, $r, $r/$t }'
echo "  >> 副本倍数 = 1 意味着零冗余：任何一台 BE 挂了，数据就查不了"
echo "     （本课现在看到的是 1.00，与课 9 的结论一致：本机 2 台 BE 同 host，反亲和规则下放不下 2 副本）"
echo ""
echo "--- 更细的健康视图 ---"
q "SHOW PROC '/cluster_health/tablet_health';" | cut -f1-8
echo "  >> 重点看这几列："
cat <<'EOF'
  ReplicaMissingNum     缺副本 —— 硬件故障或副本没补上
  VersionIncompleteNum 版本不完整 —— 副本间数据不一致
  NeedFurtherRepairNum 待进一步修复 —— 调度器还没处理完
  UnrecoverableNum     不可恢复 —— 数据真丢了，必须人工介入
  InconsistentNum      不一致 —— 副本内容对不上
EOF

echo ""
echo "##################################################################"
echo "# 3.4 磁盘与内存水位（BE）                                           #"
echo "##################################################################"
echo "--- 磁盘容量（字节）---"
mbe '^doris_be_disks_total_capacity|^doris_be_disks_avail_capacity|^doris_be_disks_local_used_capacity|^doris_be_disks_state' | sed 's/^/  /'
echo "--- SQL 视角更好读 ---"
q "SHOW BACKENDS\G" | grep -E "Host:|DataUsedCapacity|AvailCapacity|TotalCapacity|UsedPct|MaxDiskUsedPct"
echo "  >> 告警建议：UsedPct > 70% 预警，> 85% 严重（Doris 有水位保护，满了会禁写）"
echo ""
echo "--- 内存 ---"
mbe '^doris_be_memory_jemalloc_allocated_bytes|^doris_be_workload_group_mem_used_bytes' | sed 's/^/  /'
echo "  >> 结合课 10：BE 进程 mem_limit 默认 40%，Workload Group 再切一层"

echo ""
echo "##################################################################"
echo "# 3.5 进程资源指标（BE）—— 最容易被忽略的一类                        #"
echo "##################################################################"
mbe '^doris_be_process_thread_num|^doris_be_process_fd_num_used|^doris_be_process_fd_num_limit_soft' | sed 's/^/  /'
echo "  >> 告警建议：fd_num_used / fd_num_limit_soft > 80% 要处理"
echo "     （文件句柄耗尽的表现是"建表失败/导入失败"，报错信息常常看不出是 fd 问题）"

echo ""
echo "##################################################################"
echo "# 3.6 Compaction 压力（升级前必查）                                  #"
echo "##################################################################"
mfe 'doris_fe_tablet_max_compaction_score' | sed 's/^/  /'
echo "  >> 升级前最好等它降下来。带着高 compaction score 重启 BE，"
echo "     重启后要补做大量合并，恢复期会被拉长"

echo ""
echo "##################################################################"
echo "# 3.7 导入侧指标                                                     #"
echo "##################################################################"
echo "--- Stream Load 处理中 / 累计耗时 ---"
mbe '^doris_be_streaming_load_current_processing|^doris_be_streaming_load_duration_ms' | sed 's/^/  /'
echo "--- Routine Load 错误行数 ---"
mfe '^doris_fe_routine_load_error_rows' | sed 's/^/  /'
echo "--- 最近的导入作业 ---"
q "SHOW LOAD FROM shop ORDER BY CreateTime DESC LIMIT 3;" 2>&1 | cut -f1-6 | sed 's/^/  /'

echo ""
echo "##################################################################"
echo "# 3.8 升级前体检清单（脚本化，可照抄）                               #"
echo "##################################################################"
echo "--- ① 所有节点版本一致 ---"
q "SHOW FRONTENDS\G" | grep -E "Host:|Role:|IsMaster:|Version:" | sed 's/^/  /'
q "SHOW BACKENDS\G" | grep -E "Host:|Alive:|Version:" | sed 's/^/  /'
echo ""
echo "--- ② 副本无缺失 ---"
q "SHOW PROC '/cluster_health/tablet_health';" | awk -F'\t' '
NR==1 { for(i=1;i<=NF;i++){ if($i=="TabletNum") t=i; if($i=="HealthyNum") h=i; if($i=="ReplicaMissingNum") m=i; if($i=="UnrecoverableNum") u=i } ; next }
{ printf "     DbId=%-16s tablet=%-6s 健康=%-6s 缺副本=%-4s 不可恢复=%s\n", $1, $t, $h, $m, $u }'
echo "     >> 缺副本和不可恢复列必须都是 0，否则先修数据再谈升级"
echo "--- ③ 没有未完成的作业 ---"
echo "  Schema Change 作业状态分布:"
q "SHOW ALTER TABLE COLUMN FROM shop\G" | grep -E "^ +State:" | awk '{print $2}' | sort | uniq -c | sed 's/^/    /'
echo "  备份作业最新: $(q "SHOW BACKUP\G" | grep -E "^ +State:" | awk '{print $2}' | tail -1)"
echo "  恢复作业最新: $(q "SHOW RESTORE\G" | grep -E "^ +State:" | awk '{print $2}' | tail -1)"
echo ""
echo "--- ④ 磁盘有冗余空间 ---"
q "SHOW BACKENDS\G" | grep -E "UsedPct" | sed 's/^/  /'
echo ""
echo "--- ⑤ 元数据与数据目录位置（备份/回滚要用）---"
echo "  FE 元数据: /opt/apache-doris/fe/doris-meta/"
docker exec doris-learn du -sh /opt/apache-doris/fe/doris-meta/ 2>&1 | sed 's/^/     /'
echo "  BE 数据:   /opt/apache-doris/be/storage/"
docker exec doris-learn du -sh /opt/apache-doris/be/storage/ 2>&1 | sed 's/^/     /'

echo ""
echo "##################################################################"
echo "# 3.9 升级顺序：为什么是「先 BE 后 FE，FE 里先 Observer 后 Master」  #"
echo "##################################################################"
echo "--- 本机 FE 角色（只有 1 台，无法演练切换）---"
q "SHOW FRONTENDS\G" | grep -E "Host:|Role:|IsMaster:|Join:|Alive:" | sed 's/^/  /'
echo ""
cat <<'EOF'
  🟡 本节为原理推演（本机 1 FE + 2 BE 且同 host，滚动升级无法真机演练）

  顺序与理由：
  ┌────┬──────────────────┬─────────────────────────────────────────┐
  │ 步 │ 升级对象         │ 为什么是这个位置                        │
  ├────┼──────────────────┼─────────────────────────────────────────┤
  │ 1  │ BE（逐台）       │ FE 设计时兼容旧版 BE，所以 BE 可以先升； │
  │    │                  │ 反过来 BE 不保证兼容新 FE 的指令        │
  │ 2  │ FE Observer      │ 不参与投票，挂了不影响选主，先试水      │
  │ 3  │ FE Follower      │ 有投票权，必须留够多数派（N/2+1）        │
  │ 4  │ FE Master        │ 唯一可写，最后动它 = 写中断时间最短     │
  └────┴──────────────────┴─────────────────────────────────────────┘

  每一步之间要确认：SHOW FRONTENDS / SHOW BACKENDS 里 Alive=true、Version 已经是新版本
  回滚：元数据版本（fe/doris-meta/image/VERSION 的 clusterId/token）决定能不能退回旧版，
        跨大版本升级后元数据格式可能不兼容，所以升级前先备份 doris-meta 目录
EOF

echo ""
echo "##################################################################"
echo "# 3.10 告警阈值建议（本课给出的参考值）                              #"
echo "##################################################################"
cat <<'EOF'
  ┌────────────────────────┬───────────────┬──────────────────────────────┐
  │ 指标                   │ 建议阈值      │ 说明                         │
  ├────────────────────────┼───────────────┼──────────────────────────────┤
  │ 磁盘 UsedPct           │ >70% 预警     │ >85% 接近禁写水位            │
  │                        │ >85% 严重     │                              │
  │ ReplicaMissingNum      │ >0 即告警     │ 有副本缺失，可靠性已经降级    │
  │ UnrecoverableNum       │ >0 立即处理   │ 数据可能真丢了               │
  │ query_err_rate         │ 连续 5 分钟   │ 偶发报错正常，持续报错要查    │
  │                        │ >1% 告警      │                              │
  │ fd_num_used/limit      │ >80% 预警     │ 句柄耗尽会导致建表/导入失败   │
  │ max_compaction_score   │ >100 关注     │ 高说明合并跟不上写入         │
  │ BE Alive               │ false 立即    │ 节点掉线，10 秒后开始补副本   │
  └────────────────────────┴───────────────┴──────────────────────────────┘
  ⚠️ 阈值是参考起点，不是标准答案。要按自己集群的历史水位调。
EOF

echo ""
echo "===== step3 完成 ====="
echo "  下一步：bash lesson11-cleanup.sh （清理实验对象）"
