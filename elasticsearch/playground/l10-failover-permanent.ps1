# 课10 实验：节点永久丢失 —— 验证 red 与数据是否真丢
# 目标：回答课9悬念「node-3 永远回不来，那 7 个无副本主分片是不是彻底丢了？」
$ErrorActionPreference = "Continue"

function Show($t) { Write-Output "`n===== $t =====" }

Show "STEP 0 停集群前基线"
curl.exe -s "http://localhost:9201/_cluster/health?pretty" | Select-String -Pattern "status|unassigned|active_primary"
curl.exe -s "http://localhost:9201/_cat/shards?v&h=index,shard,prirep,state,docs,node" | Select-String -Pattern "l9_hi|l9_trap2|l9_orders|node-3"

Show "STEP 0.1 记录将被销毁的分片清单"
curl.exe -s "http://localhost:9201/_cat/shards?v&h=index,shard,prirep,state,docs,node" | Select-String -Pattern "node-3"
