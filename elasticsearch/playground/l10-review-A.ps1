# Lesson 10 Review A: fact-check every number in the lecture
Write-Output "===== A1 green baseline ====="
curl.exe -s 'http://localhost:9201/_cluster/health?pretty' | Select-String -Pattern 'status|unassigned|active_primary|number_of_nodes'
Write-Output ""

Write-Output "===== A2 rebuild yellow: replicas=3 on l9_orders ====="
curl.exe -s -X PUT 'http://localhost:9201/l9_orders/_settings' -H 'Content-Type: application/json' --data-binary '@D:\projects\learning\elasticsearch\playground\l10_rep3.json'
Start-Sleep -Seconds 3
curl.exe -s 'http://localhost:9201/_cluster/health?pretty' | Select-String -Pattern 'status|unassigned|active_primary'
Write-Output ""

Write-Output "===== A3 verify no data loss during yellow ====="
curl.exe -s 'http://localhost:9201/l9_orders/_count'
Write-Output ""

Write-Output "===== A4 explain decider ====="
curl.exe -s 'http://localhost:9201/_cluster/allocation/explain?pretty' -H 'Content-Type: application/json' -d '{"index":"l9_orders","shard":0,"primary":false}' | Select-String -Pattern 'reason|decider|can_allocate' | Select-Object -First 6
Write-Output ""

Write-Output "===== A5 restore replicas=1 ====="
curl.exe -s -X PUT 'http://localhost:9201/l9_orders/_settings' -H 'Content-Type: application/json' --data-binary '@D:\projects\learning\elasticsearch\playground\l10_rep1.json'
Start-Sleep -Seconds 3
curl.exe -s 'http://localhost:9201/_cluster/health?pretty' | Select-String -Pattern 'status|unassigned'
Write-Output ""

Write-Output "===== A6 watermark defaults ====="
curl.exe -s 'http://localhost:9201/_cluster/settings?include_defaults=true&pretty' | Select-String -Pattern 'watermark|low|high|flood' | Select-Object -First 8
Write-Output ""

Write-Output "===== A7 shard latency comparison (verify 3.8/3.4/12.2) ====="
foreach ($n in @(1,3,50)) {
  $idx = "l10_shard_$n"
  $times = @()
  for ($k=0; $k -lt 5; $k++) {
    $r = curl.exe -s -X POST "http://localhost:9201/$idx/_search" -H 'Content-Type: application/json' --data-binary '@D:\projects\learning\elasticsearch\playground\l10_shard_q.json' | ConvertFrom-Json
    $times += $r.took
  }
  $avg = [math]::Round(($times | Measure-Object -Average).Average,1)
  Write-Output "$idx : avg=$avg ms  runs=$($times -join ',')"
}
Write-Output ""

Write-Output "===== A8 store sizes ====="
curl.exe -s 'http://localhost:9201/_cat/indices/l10_shard_*?v&h=index,pri,docs.count,store.size'
Write-Output ""

Write-Output "===== A9 l9_trap2 aggregation error (verify error_upper_bound=3) ====="
curl.exe -s -X POST 'http://localhost:9201/l9_trap2/_search?pretty' -H 'Content-Type: application/json' --data-binary '@D:\projects\learning\elasticsearch\playground\l10_agg_q.json' | Select-String -Pattern 'error_upper_bound|sum_other|key|doc_count' | Select-Object -First 8
Write-Output ""

Write-Output "===== A10 no_master_block default ====="
curl.exe -s 'http://localhost:9201/_cluster/settings?include_defaults=true&pretty' | Select-String -Pattern 'no_master_block' | Select-Object -First 3
