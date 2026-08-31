# Review B: copy every code block from the lecture verbatim and run it
Write-Output "===== B1 health (3.1) ====="
curl.exe -s 'http://localhost:9201/_cluster/health?pretty'
Write-Output ""

Write-Output "===== B2 make yellow (3.1) ====="
curl.exe -s -X PUT 'http://localhost:9201/l9_orders/_settings' -H 'Content-Type: application/json' -d '{"index.number_of_replicas": 3}'
Start-Sleep -Seconds 2
curl.exe -s 'http://localhost:9201/_cluster/health?pretty' | Select-String -Pattern 'status|unassigned'
Write-Output ""

Write-Output "===== B3 count during yellow ====="
curl.exe -s 'http://localhost:9201/l9_orders/_count'
Write-Output ""

Write-Output "===== B4 restore ====="
curl.exe -s -X PUT 'http://localhost:9201/l9_orders/_settings' -H 'Content-Type: application/json' -d '{"index.number_of_replicas": 1}'
Start-Sleep -Seconds 3
curl.exe -s 'http://localhost:9201/_cluster/health?pretty' | Select-String -Pattern 'status|unassigned'
Write-Output ""

Write-Output "===== B5 allocation explain (3.2) bare call ====="
curl.exe -s 'http://localhost:9201/_cluster/allocation/explain?pretty' | Select-String -Pattern 'note|index|shard' | Select-Object -First 4
Write-Output ""

Write-Output "===== B6 cat shards UNASSIGNED (3.8) ====="
curl.exe -s 'http://localhost:9201/_cat/shards?v&h=index,shard,prirep,state,docs,node' | Select-String -Pattern 'UNASSIGNED'
Write-Output "(empty = none unassigned, expected)"
Write-Output ""

Write-Output "===== B7 cat nodes (3.8) ====="
curl.exe -s 'http://localhost:9201/_cat/nodes?v&h=name,port,node.role,heap.percent,cpu,load_1m,master'
Write-Output ""

Write-Output "===== B8 cat allocation (3.8) ====="
curl.exe -s 'http://localhost:9201/_cat/allocation?v&h=shards,disk.indices,disk.used,disk.avail,disk.percent,node'
Write-Output ""

Write-Output "===== B9 cat recovery (3.8) ====="
curl.exe -s 'http://localhost:9201/_cat/recovery?v&active_only=true'
Write-Output "(empty = no active recovery)"
Write-Output ""

Write-Output "===== B10 cat pending tasks (3.8) ====="
curl.exe -s 'http://localhost:9201/_cat/pending_tasks?v'
Write-Output ""

Write-Output "===== B11 flood stage unlock command (3.3) - verify syntax ====="
Write-Output "command: PUT /索引名/_settings with index.blocks.read_only_allow_delete=null"
$chk = curl.exe -s 'http://localhost:9201/l9_hi/_settings?pretty' | Select-String -Pattern 'read_only' | Select-Object -First 2
if ($chk) { Write-Output "current: $chk" } else { Write-Output "current: no read_only block set (normal)" }
Write-Output ""

Write-Output "===== B12 search_shards (routing probe, 3.7) ====="
curl.exe -s 'http://localhost:9201/l9_trap2/_search_shards?routing=R0'
Write-Output ""

Write-Output "===== B13 verify l10_shard indexes exist for exp4 ====="
curl.exe -s 'http://localhost:9201/_cat/indices/l10_shard_*?v&h=index,pri,rep,docs.count,health'
